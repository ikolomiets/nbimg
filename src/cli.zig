//! User-facing command parsing, help output, diagnostics, and dispatch.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const api_edit = @import("edit.zig");
const api_files = @import("files.zig");
const api_gen = @import("gen.zig");
const build_options = @import("build_options");

const exit_success = 0;
const exit_failure = 1;
const exit_usage = 2;
const exit_response_parse = 3;
const max_prompt_bytes = 16 * 1024;
const live_edit_sample_image_path = "sample_images/good_night.jpeg";
const live_edit_upload_display_name = "nbimg live edit request validity";
const live_edit_prompt = "change visual style to Broadway musical";

pub const GenCommand = struct {
    prompt: []const u8,
    write_response: bool = false,
    out_dir: ?[]const u8 = null,
};

pub const max_edit_constraints = 16;

pub const EditCommand = struct {
    prompt: []const u8,
    write_response: bool = false,
    out_dir: ?[]const u8 = null,
    base: api_edit.UploadedImage,
    base_role: api_edit.BaseRole = .scene,
    references: [api_edit.max_references]api_edit.Reference = undefined,
    reference_count: usize = 0,
    preserves: [max_edit_constraints][]const u8 = undefined,
    preserve_count: usize = 0,
    do_nots: [max_edit_constraints][]const u8 = undefined,
    do_not_count: usize = 0,

    pub fn referenceSlice(command: *const EditCommand) []const api_edit.Reference {
        return command.references[0..command.reference_count];
    }

    pub fn preserveSlice(command: *const EditCommand) []const []const u8 {
        return command.preserves[0..command.preserve_count];
    }

    pub fn doNotSlice(command: *const EditCommand) []const []const u8 {
        return command.do_nots[0..command.do_not_count];
    }
};

pub const FilesUploadCommand = struct {
    path: []const u8,
    display_name: ?[]const u8 = null,
};

pub const FilesListCommand = struct {};

pub const FilesGetCommand = struct {
    name: []const u8,
};

pub const FilesDeleteCommand = struct {
    name: []const u8,
};

pub const Command = union(enum) {
    gen: GenCommand,
    edit: EditCommand,
    files_upload: FilesUploadCommand,
    files_list: FilesListCommand,
    files_get: FilesGetCommand,
    files_delete: FilesDeleteCommand,
};

pub const ParsedCommand = struct {
    traffic_log_options: api.TrafficLogOptions = .{},
    command: Command,
};

pub const ParseError = error{
    MissingCommand,
    UnknownCommand,
    MissingFilesCommand,
    UnknownFilesCommand,
    MissingPrompt,
    EmptyPrompt,
    PromptTooLong,
    SplitPrompt,
    DuplicatePrompt,
    MissingBase,
    EmptyBase,
    DuplicateBase,
    MissingBaseRole,
    DuplicateBaseRole,
    InvalidBaseRole,
    MissingReference,
    EmptyReference,
    InvalidReference,
    TooManyReferences,
    TooManyCharacterReferences,
    TooManyObjectReferences,
    DuplicateLabel,
    InvalidLabel,
    MissingMime,
    InvalidMime,
    MalformedImageInput,
    MissingPreserve,
    MissingDoNot,
    TooManyConstraints,
    MissingPath,
    EmptyPath,
    DuplicatePath,
    MissingName,
    EmptyName,
    DuplicateName,
    InvalidName,
    MissingDisplayName,
    EmptyDisplayName,
    DuplicateDisplayName,
    InvalidDisplayNameUtf8,
    DisplayNameTooLong,
    UnknownFlag,
    UnexpectedArgument,
    WriteResponseUnsupported,
    MissingOutDir,
    EmptyOutDir,
    DuplicateOutDir,
    OutDirUnsupported,
};

const max_display_name_codepoints = 512;

const CommandArgs = struct {
    args: []const [:0]const u8,
    index: usize = 0,
    traffic_log_options: api.TrafficLogOptions = .{},

    fn nextOption(command_args: *CommandArgs) ?[]const u8 {
        while (command_args.index < command_args.args.len) {
            const arg_z = command_args.args[command_args.index];
            command_args.index += 1;

            const arg: []const u8 = arg_z;
            if (parseTrafficLogFlag(arg, &command_args.traffic_log_options)) continue;
            return arg;
        }

        return null;
    }

    fn nextValue(command_args: *CommandArgs, missing_error: ParseError) ParseError![]const u8 {
        if (command_args.index >= command_args.args.len) return missing_error;

        const value_z = command_args.args[command_args.index];
        command_args.index += 1;

        const value: []const u8 = value_z;
        if (std.mem.startsWith(u8, value, "--")) return missing_error;
        return value;
    }
};

pub fn run(init: std.process.Init) u8 {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const args = init.minimal.args.toSlice(arena) catch |err| {
        std.debug.print("error: failed to read arguments: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    var stdin_prompt: ?[]u8 = null;
    defer if (stdin_prompt) |prompt| gpa.free(prompt);

    const parsed_command = parseArgs(args) catch |err| parsed: {
        if (!shouldReadPromptFromStdin(args, err)) {
            printUsageError(err);
            return exit_usage;
        }

        stdin_prompt = readPromptFromStdin(gpa, init.io) catch |read_err| switch (read_err) {
            error.MissingPrompt => {
                printUsageError(error.MissingPrompt);
                return exit_usage;
            },
            error.PromptTooLong => {
                printUsageError(error.PromptTooLong);
                return exit_usage;
            },
            else => {
                std.debug.print("error: failed to read prompt from stdin: {s}\n", .{@errorName(read_err)});
                return exit_failure;
            },
        };

        break :parsed parseArgsWithPrompt(args, stdin_prompt.?) catch |parse_err| {
            printUsageError(parse_err);
            return exit_usage;
        };
    };

    api.traffic_log_options = parsed_command.traffic_log_options;
    defer api.traffic_log_options = .{};

    const api_key = api.apiKeyFromMap(init.environ_map) catch |err| switch (err) {
        error.MissingApiKey => {
            std.debug.print("error: GEMINI_API_KEY is not set\n", .{});
            return exit_usage;
        },
        error.EmptyApiKey => {
            std.debug.print("error: GEMINI_API_KEY is empty\n", .{});
            return exit_usage;
        },
    };

    return switch (parsed_command.command) {
        .gen => |gen| runGen(init, gpa, api_key, gen),
        .edit => |edit| runEdit(init, gpa, api_key, edit),
        .files_upload => |files_upload| runFilesUpload(init, gpa, api_key, files_upload),
        .files_list => runFilesList(init, gpa, api_key),
        .files_get => |files_get| runFilesGet(init, gpa, api_key, files_get),
        .files_delete => |files_delete| runFilesDelete(init, gpa, api_key, files_delete),
    };
}

fn runGen(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8, command: GenCommand) u8 {
    var response = api_gen.generateContent(gpa, init.io, api_key, command.prompt) catch |err| {
        std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: API request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    if (command.write_response) {
        const response_id = api_gen.decodeResponseId(gpa, response.body) catch |err| {
            std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
            return exit_response_parse;
        };
        defer gpa.free(response_id);

        writeResponseFile(init.io, command.out_dir, response_id, response.body) catch |err| {
            std.debug.print("error: failed to write API response: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
    }

    var files = api_gen.decodeGeneratedFiles(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer files.deinit(gpa);

    writeGeneratedFiles(init.io, command.out_dir, files) catch |err| {
        std.debug.print("error: failed to write generated files: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runEdit(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8, command: EditCommand) u8 {
    const edit_request = api_edit.EditRequest{
        .prompt = command.prompt,
        .base = command.base,
        .base_role = command.base_role,
        .references = command.referenceSlice(),
        .preserves = command.preserveSlice(),
        .do_nots = command.doNotSlice(),
    };

    var response = api_edit.generateContent(gpa, init.io, api_key, edit_request) catch |err| {
        std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: API request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    if (command.write_response) {
        const response_id = api_gen.decodeResponseId(gpa, response.body) catch |err| {
            std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
            return exit_response_parse;
        };
        defer gpa.free(response_id);

        writeResponseFile(init.io, command.out_dir, response_id, response.body) catch |err| {
            std.debug.print("error: failed to write API response: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
    }

    var files = api_gen.decodeGeneratedFiles(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer files.deinit(gpa);

    writeGeneratedFiles(init.io, command.out_dir, files) catch |err| {
        std.debug.print("error: failed to write generated files: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn shouldReadPromptFromStdin(args: []const [:0]const u8, parse_error: ParseError) bool {
    if (parse_error != error.MissingPrompt) return false;
    if (args.len < 2) return false;

    const command: []const u8 = args[1];
    if (!std.mem.eql(u8, command, "gen") and !std.mem.eql(u8, command, "edit")) return false;

    for (args[2..]) |arg_z| {
        const arg: []const u8 = arg_z;
        if (std.mem.eql(u8, arg, "--prompt")) return false;
    }

    return true;
}

fn readPromptFromStdin(gpa: std.mem.Allocator, io: std.Io) ![]u8 {
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().readerStreaming(io, &stdin_buffer);
    return readPromptFromReader(gpa, &stdin_reader.interface);
}

fn readPromptFromReader(gpa: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    const prompt = reader.allocRemaining(gpa, .limited(max_prompt_bytes + 1)) catch |err| switch (err) {
        error.StreamTooLong => return error.PromptTooLong,
        else => return err,
    };
    errdefer gpa.free(prompt);

    if (prompt.len == 0) return error.MissingPrompt;
    if (prompt.len > max_prompt_bytes) return error.PromptTooLong;
    return prompt;
}

fn runFilesUpload(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    api_key: []const u8,
    command: FilesUploadCommand,
) u8 {
    const mime = api_files.InputMime.fromPath(command.path) orelse {
        std.debug.print("error: unsupported upload file type; expected .jpg, .jpeg, .png, or .webp\n", .{});
        return exit_usage;
    };

    const cwd = std.Io.Dir.cwd();
    const bytes = cwd.readFileAlloc(init.io, command.path, gpa, .limited(api_files.max_upload_bytes)) catch |err| {
        std.debug.print("error: failed to read upload file: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(bytes);

    if (bytes.len == 0) {
        std.debug.print("error: upload file must not be empty\n", .{});
        return exit_usage;
    }

    var response = api_files.uploadFile(gpa, init.io, api_key, .{
        .mime = mime,
        .bytes = bytes,
        .display_name = command.display_name,
    }) catch |err| {
        std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: API request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    var file = api_files.decodeUploadedFile(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer file.deinit(gpa);

    const output = fileMetadataJson(gpa, file) catch |err| {
        std.debug.print("error: failed to format uploaded file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(output);

    writeStdoutLine(init.io, output) catch |err| {
        std.debug.print("error: failed to print uploaded file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runFilesList(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8) u8 {
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    var files: std.ArrayList(api_files.File) = .empty;
    defer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    while (true) {
        var response = api_files.listFilesPage(gpa, init.io, api_key, page_token) catch |err| {
            std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
        defer response.deinit(gpa);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        if (response.status != .ok) {
            std.debug.print(
                "error: API request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(response.status), response.body },
            );
            return exit_failure;
        }

        var page = api_files.decodeFileListPage(gpa, response.body) catch |err| {
            std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
            return exit_response_parse;
        };
        defer page.deinit(gpa);

        takePageFiles(gpa, &files, &page) catch |err| {
            std.debug.print("error: failed to collect file metadata: {s}\n", .{@errorName(err)});
            return exit_failure;
        };

        page_token = page.next_page_token orelse break;
        page.next_page_token = null;
    }

    const output = filesListJson(gpa, files.items) catch |err| {
        std.debug.print("error: failed to format file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(output);

    writeStdoutLine(init.io, output) catch |err| {
        std.debug.print("error: failed to print file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runFilesGet(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8, command: FilesGetCommand) u8 {
    var response = api_files.getFile(gpa, init.io, api_key, command.name) catch |err| {
        std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: API request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    var file = api_files.decodeFile(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer file.deinit(gpa);

    const output = fileMetadataJson(gpa, file) catch |err| {
        std.debug.print("error: failed to format file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(output);

    writeStdoutLine(init.io, output) catch |err| {
        std.debug.print("error: failed to print file metadata: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runFilesDelete(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8, command: FilesDeleteCommand) u8 {
    var response = api_files.deleteFile(gpa, init.io, api_key, command.name) catch |err| {
        std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: API request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    writeStdoutLine(init.io, "OK") catch |err| {
        std.debug.print("error: failed to print delete result: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

pub fn parseArgs(args: []const [:0]const u8) ParseError!ParsedCommand {
    return parseArgsWithPrompt(args, null);
}

fn parseArgsWithPrompt(args: []const [:0]const u8, stdin_prompt: ?[]const u8) ParseError!ParsedCommand {
    if (args.len < 2) return error.MissingCommand;

    if (std.mem.eql(u8, args[1], "gen")) {
        var command_args: CommandArgs = .{ .args = args[2..] };
        const gen = try parseGenCommand(&command_args, stdin_prompt);
        return .{
            .traffic_log_options = command_args.traffic_log_options,
            .command = .{ .gen = gen },
        };
    }

    if (std.mem.eql(u8, args[1], "edit")) {
        var command_args: CommandArgs = .{ .args = args[2..] };
        const edit = try parseEditCommand(&command_args, stdin_prompt);
        return .{
            .traffic_log_options = command_args.traffic_log_options,
            .command = .{ .edit = edit },
        };
    }

    if (std.mem.eql(u8, args[1], "files")) {
        if (args.len < 3) return error.MissingFilesCommand;

        const subcommand: []const u8 = args[2];
        var command_args: CommandArgs = .{ .args = args[3..] };
        if (std.mem.eql(u8, subcommand, "upload")) {
            const files_upload = try parseFilesUploadCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .command = .{ .files_upload = files_upload },
            };
        }

        if (std.mem.eql(u8, subcommand, "list")) {
            const files_list = try parseFilesListCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .command = .{ .files_list = files_list },
            };
        }

        if (std.mem.eql(u8, subcommand, "get")) {
            const files_get = try parseFilesGetCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .command = .{ .files_get = files_get },
            };
        }

        if (std.mem.eql(u8, subcommand, "delete")) {
            const files_delete = try parseFilesDeleteCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .command = .{ .files_delete = files_delete },
            };
        }

        return error.UnknownFilesCommand;
    }

    return error.UnknownCommand;
}

fn parseGenCommand(command_args: *CommandArgs, stdin_prompt: ?[]const u8) ParseError!GenCommand {
    var prompt: ?[]const u8 = null;
    var write_response = false;
    var out_dir: ?[]const u8 = null;

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (prompt != null) return error.SplitPrompt;
            return error.UnexpectedArgument;
        }

        if (std.mem.eql(u8, arg, "--write-response")) {
            write_response = true;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            if (out_dir != null) return error.DuplicateOutDir;

            const value = try command_args.nextValue(error.MissingOutDir);
            if (value.len == 0) return error.EmptyOutDir;
            out_dir = value;
        } else if (std.mem.eql(u8, arg, "--prompt")) {
            if (prompt != null) return error.DuplicatePrompt;

            const value = try command_args.nextValue(error.MissingPrompt);
            if (value.len == 0) return error.EmptyPrompt;
            prompt = value;
        } else {
            return error.UnknownFlag;
        }
    }

    return .{
        .prompt = prompt orelse try fallbackPrompt(stdin_prompt),
        .write_response = write_response,
        .out_dir = out_dir,
    };
}

fn parseEditCommand(command_args: *CommandArgs, stdin_prompt: ?[]const u8) ParseError!EditCommand {
    var prompt: ?[]const u8 = null;
    var write_response = false;
    var out_dir: ?[]const u8 = null;
    var base: ?api_edit.UploadedImage = null;
    var base_role: api_edit.BaseRole = .scene;
    var base_role_seen = false;
    var references: [api_edit.max_references]api_edit.Reference = undefined;
    var reference_count: usize = 0;
    var preserves: [max_edit_constraints][]const u8 = undefined;
    var preserve_count: usize = 0;
    var do_nots: [max_edit_constraints][]const u8 = undefined;
    var do_not_count: usize = 0;

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (prompt != null) return error.SplitPrompt;
            return error.UnexpectedArgument;
        }

        if (std.mem.eql(u8, arg, "--write-response")) {
            write_response = true;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            if (out_dir != null) return error.DuplicateOutDir;

            const value = try command_args.nextValue(error.MissingOutDir);
            if (value.len == 0) return error.EmptyOutDir;
            out_dir = value;
        } else if (std.mem.eql(u8, arg, "--prompt")) {
            if (prompt != null) return error.DuplicatePrompt;

            const value = try command_args.nextValue(error.MissingPrompt);
            if (value.len == 0) return error.EmptyPrompt;
            prompt = value;
        } else if (std.mem.eql(u8, arg, "--base")) {
            if (base != null) return error.DuplicateBase;

            const value = try command_args.nextValue(error.MissingBase);
            base = try parseImageInput(value, error.EmptyBase);
        } else if (std.mem.eql(u8, arg, "--base-role")) {
            if (base_role_seen) return error.DuplicateBaseRole;

            const value = try command_args.nextValue(error.MissingBaseRole);
            base_role = api_edit.BaseRole.fromName(value) orelse return error.InvalidBaseRole;
            base_role_seen = true;
        } else if (std.mem.eql(u8, arg, "--character")) {
            const value = try command_args.nextValue(error.MissingReference);
            try addConvenienceReference(&references, &reference_count, .character, value);
        } else if (std.mem.eql(u8, arg, "--object")) {
            const value = try command_args.nextValue(error.MissingReference);
            try addConvenienceReference(&references, &reference_count, .object, value);
        } else if (std.mem.eql(u8, arg, "--style")) {
            const value = try command_args.nextValue(error.MissingReference);
            try addConvenienceReference(&references, &reference_count, .style, value);
        } else if (std.mem.eql(u8, arg, "--ref")) {
            const value = try command_args.nextValue(error.MissingReference);
            try addGenericReference(&references, &reference_count, value);
        } else if (std.mem.eql(u8, arg, "--preserve")) {
            const value = try command_args.nextValue(error.MissingPreserve);
            if (value.len > 0) try addConstraint(&preserves, &preserve_count, value);
        } else if (std.mem.eql(u8, arg, "--do-not")) {
            const value = try command_args.nextValue(error.MissingDoNot);
            if (value.len > 0) try addConstraint(&do_nots, &do_not_count, value);
        } else {
            return error.UnknownFlag;
        }
    }

    const parsed_base = base orelse return error.MissingBase;
    try validateEditReferenceLimits(base_role, references[0..reference_count]);

    const parsed_prompt = prompt orelse try fallbackPrompt(stdin_prompt);

    return .{
        .prompt = parsed_prompt,
        .write_response = write_response,
        .out_dir = out_dir,
        .base = parsed_base,
        .base_role = base_role,
        .references = references,
        .reference_count = reference_count,
        .preserves = preserves,
        .preserve_count = preserve_count,
        .do_nots = do_nots,
        .do_not_count = do_not_count,
    };
}

fn fallbackPrompt(stdin_prompt: ?[]const u8) ParseError![]const u8 {
    const prompt = stdin_prompt orelse return error.MissingPrompt;
    if (prompt.len == 0) return error.MissingPrompt;
    return prompt;
}

fn parseImageInput(value: []const u8, empty_error: ParseError) ParseError!api_edit.UploadedImage {
    if (value.len == 0) return empty_error;

    const comma = std.mem.indexOfScalar(u8, value, ',') orelse return error.MissingMime;
    if (std.mem.indexOfScalar(u8, value[comma + 1 ..], ',') != null) return error.MalformedImageInput;

    const name = value[0..comma];
    const mime_name = value[comma + 1 ..];
    if (!api.isCanonicalFileName(name)) return error.InvalidName;
    if (mime_name.len == 0) return error.MissingMime;

    return .{
        .name = name,
        .mime = api_edit.InputMime.fromName(mime_name) orelse return error.InvalidMime,
    };
}

fn addConvenienceReference(
    references: *[api_edit.max_references]api_edit.Reference,
    reference_count: *usize,
    role: api_edit.ReferenceRole,
    value: []const u8,
) ParseError!void {
    if (value.len == 0) return error.EmptyReference;

    const equal = std.mem.indexOfScalar(u8, value, '=');
    const label: ?[]const u8 = if (equal) |index| value[0..index] else null;
    const image_value = if (equal) |index| value[index + 1 ..] else value;

    try addReference(references, reference_count, role, label, image_value);
}

fn addGenericReference(
    references: *[api_edit.max_references]api_edit.Reference,
    reference_count: *usize,
    value: []const u8,
) ParseError!void {
    if (value.len == 0) return error.EmptyReference;

    const equal = std.mem.indexOfScalar(u8, value, '=') orelse return error.InvalidReference;
    const role_and_label = value[0..equal];
    const image_value = value[equal + 1 ..];
    if (role_and_label.len == 0) return error.InvalidReference;

    const colon = std.mem.indexOfScalar(u8, role_and_label, ':');
    const role_name = if (colon) |index| role_and_label[0..index] else role_and_label;
    const label: ?[]const u8 = if (colon) |index| role_and_label[index + 1 ..] else null;

    const role = api_edit.ReferenceRole.fromName(role_name) orelse return error.InvalidReference;
    try addReference(references, reference_count, role, label, image_value);
}

fn addReference(
    references: *[api_edit.max_references]api_edit.Reference,
    reference_count: *usize,
    role: api_edit.ReferenceRole,
    maybe_label: ?[]const u8,
    image_value: []const u8,
) ParseError!void {
    if (reference_count.* >= references.len) return error.TooManyReferences;
    if (image_value.len == 0) return error.EmptyReference;

    const image = try parseImageInput(image_value, error.EmptyReference);
    const label = if (maybe_label) |custom_label| label: {
        if (!api_edit.isValidLabel(custom_label)) return error.InvalidLabel;
        break :label custom_label;
    } else try autoLabelForRole(role, countReferencesWithRole(references[0..reference_count.*], role));

    if (hasLabel(references[0..reference_count.*], label)) return error.DuplicateLabel;

    references[reference_count.*] = .{
        .role = role,
        .label = label,
        .image = image,
    };
    reference_count.* += 1;
}

fn addConstraint(
    constraints: *[max_edit_constraints][]const u8,
    constraint_count: *usize,
    value: []const u8,
) ParseError!void {
    if (constraint_count.* >= constraints.len) return error.TooManyConstraints;

    constraints[constraint_count.*] = value;
    constraint_count.* += 1;
}

fn validateEditReferenceLimits(
    base_role: api_edit.BaseRole,
    references: []const api_edit.Reference,
) ParseError!void {
    var character_count: usize = if (base_role == .character) 1 else 0;
    var object_count: usize = if (base_role == .object) 1 else 0;

    for (references) |reference| {
        if (reference.role == .character) character_count += 1;
        if (reference.role == .object) object_count += 1;
    }

    if (character_count > api_edit.max_character_references) return error.TooManyCharacterReferences;
    if (object_count > api_edit.max_object_references) return error.TooManyObjectReferences;
}

fn countReferencesWithRole(
    references: []const api_edit.Reference,
    role: api_edit.ReferenceRole,
) usize {
    var count: usize = 0;
    for (references) |reference| {
        if (reference.role == role) count += 1;
    }
    return count;
}

fn hasLabel(references: []const api_edit.Reference, label: []const u8) bool {
    if (std.mem.eql(u8, label, "BASE_IMAGE")) return true;
    for (references) |reference| {
        if (std.mem.eql(u8, reference.label, label)) return true;
    }
    return false;
}

fn autoLabelForRole(role: api_edit.ReferenceRole, index: usize) ParseError![]const u8 {
    const labels = switch (role) {
        .character => &character_labels,
        .object => &object_labels,
        .style => &style_labels,
        .pose => &pose_labels,
        .composition => &composition_labels,
        .background => &background_labels,
        .texture => &texture_labels,
        .image => &image_labels,
    };

    if (index >= labels.len) return error.TooManyReferences;
    return labels[index];
}

const character_labels = [_][]const u8{
    "CHARACTER_A",
    "CHARACTER_B",
    "CHARACTER_C",
    "CHARACTER_D",
    "CHARACTER_E",
    "CHARACTER_F",
    "CHARACTER_G",
    "CHARACTER_H",
    "CHARACTER_I",
    "CHARACTER_J",
    "CHARACTER_K",
    "CHARACTER_L",
    "CHARACTER_M",
};

const object_labels = [_][]const u8{
    "OBJECT_A",
    "OBJECT_B",
    "OBJECT_C",
    "OBJECT_D",
    "OBJECT_E",
    "OBJECT_F",
    "OBJECT_G",
    "OBJECT_H",
    "OBJECT_I",
    "OBJECT_J",
    "OBJECT_K",
    "OBJECT_L",
    "OBJECT_M",
};

const style_labels = [_][]const u8{
    "STYLE_REFERENCE_A",
    "STYLE_REFERENCE_B",
    "STYLE_REFERENCE_C",
    "STYLE_REFERENCE_D",
    "STYLE_REFERENCE_E",
    "STYLE_REFERENCE_F",
    "STYLE_REFERENCE_G",
    "STYLE_REFERENCE_H",
    "STYLE_REFERENCE_I",
    "STYLE_REFERENCE_J",
    "STYLE_REFERENCE_K",
    "STYLE_REFERENCE_L",
    "STYLE_REFERENCE_M",
};

const pose_labels = [_][]const u8{
    "POSE_REFERENCE_A",
    "POSE_REFERENCE_B",
    "POSE_REFERENCE_C",
    "POSE_REFERENCE_D",
    "POSE_REFERENCE_E",
    "POSE_REFERENCE_F",
    "POSE_REFERENCE_G",
    "POSE_REFERENCE_H",
    "POSE_REFERENCE_I",
    "POSE_REFERENCE_J",
    "POSE_REFERENCE_K",
    "POSE_REFERENCE_L",
    "POSE_REFERENCE_M",
};

const composition_labels = [_][]const u8{
    "COMPOSITION_REFERENCE_A",
    "COMPOSITION_REFERENCE_B",
    "COMPOSITION_REFERENCE_C",
    "COMPOSITION_REFERENCE_D",
    "COMPOSITION_REFERENCE_E",
    "COMPOSITION_REFERENCE_F",
    "COMPOSITION_REFERENCE_G",
    "COMPOSITION_REFERENCE_H",
    "COMPOSITION_REFERENCE_I",
    "COMPOSITION_REFERENCE_J",
    "COMPOSITION_REFERENCE_K",
    "COMPOSITION_REFERENCE_L",
    "COMPOSITION_REFERENCE_M",
};

const background_labels = [_][]const u8{
    "BACKGROUND_REFERENCE_A",
    "BACKGROUND_REFERENCE_B",
    "BACKGROUND_REFERENCE_C",
    "BACKGROUND_REFERENCE_D",
    "BACKGROUND_REFERENCE_E",
    "BACKGROUND_REFERENCE_F",
    "BACKGROUND_REFERENCE_G",
    "BACKGROUND_REFERENCE_H",
    "BACKGROUND_REFERENCE_I",
    "BACKGROUND_REFERENCE_J",
    "BACKGROUND_REFERENCE_K",
    "BACKGROUND_REFERENCE_L",
    "BACKGROUND_REFERENCE_M",
};

const texture_labels = [_][]const u8{
    "TEXTURE_REFERENCE_A",
    "TEXTURE_REFERENCE_B",
    "TEXTURE_REFERENCE_C",
    "TEXTURE_REFERENCE_D",
    "TEXTURE_REFERENCE_E",
    "TEXTURE_REFERENCE_F",
    "TEXTURE_REFERENCE_G",
    "TEXTURE_REFERENCE_H",
    "TEXTURE_REFERENCE_I",
    "TEXTURE_REFERENCE_J",
    "TEXTURE_REFERENCE_K",
    "TEXTURE_REFERENCE_L",
    "TEXTURE_REFERENCE_M",
};

const image_labels = [_][]const u8{
    "IMAGE_REFERENCE_A",
    "IMAGE_REFERENCE_B",
    "IMAGE_REFERENCE_C",
    "IMAGE_REFERENCE_D",
    "IMAGE_REFERENCE_E",
    "IMAGE_REFERENCE_F",
    "IMAGE_REFERENCE_G",
    "IMAGE_REFERENCE_H",
    "IMAGE_REFERENCE_I",
    "IMAGE_REFERENCE_J",
    "IMAGE_REFERENCE_K",
    "IMAGE_REFERENCE_L",
    "IMAGE_REFERENCE_M",
};

fn parseFilesUploadCommand(command_args: *CommandArgs) ParseError!FilesUploadCommand {
    var path: ?[]const u8 = null;
    var display_name: ?[]const u8 = null;

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--write-response")) {
            return error.WriteResponseUnsupported;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            return error.OutDirUnsupported;
        } else if (std.mem.eql(u8, arg, "--path")) {
            if (path != null) return error.DuplicatePath;

            const value = try command_args.nextValue(error.MissingPath);
            if (value.len == 0) return error.EmptyPath;
            path = value;
        } else if (std.mem.eql(u8, arg, "--display-name")) {
            if (display_name != null) return error.DuplicateDisplayName;

            const value = try command_args.nextValue(error.MissingDisplayName);
            try validateDisplayName(value);
            display_name = value;
        } else {
            return error.UnknownFlag;
        }
    }

    const upload_path = path orelse return error.MissingPath;
    const effective_display_name = display_name orelse std.fs.path.basename(upload_path);
    try validateDisplayName(effective_display_name);

    return .{
        .path = upload_path,
        .display_name = effective_display_name,
    };
}

fn validateDisplayName(display_name: []const u8) ParseError!void {
    if (display_name.len == 0) return error.EmptyDisplayName;
    if (!std.unicode.utf8ValidateSlice(display_name)) return error.InvalidDisplayNameUtf8;

    const codepoints = std.unicode.utf8CountCodepoints(display_name) catch {
        return error.InvalidDisplayNameUtf8;
    };
    if (codepoints > max_display_name_codepoints) return error.DisplayNameTooLong;
}

fn parseFilesListCommand(command_args: *CommandArgs) ParseError!FilesListCommand {
    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--write-response")) {
            return error.WriteResponseUnsupported;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            return error.OutDirUnsupported;
        } else {
            return error.UnknownFlag;
        }
    }

    return .{};
}

fn parseFilesGetCommand(command_args: *CommandArgs) ParseError!FilesGetCommand {
    return .{
        .name = try parseRequiredFileName(command_args),
    };
}

fn parseFilesDeleteCommand(command_args: *CommandArgs) ParseError!FilesDeleteCommand {
    return .{
        .name = try parseRequiredFileName(command_args),
    };
}

fn parseRequiredFileName(command_args: *CommandArgs) ParseError![]const u8 {
    var name: ?[]const u8 = null;
    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--write-response")) {
            return error.WriteResponseUnsupported;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            return error.OutDirUnsupported;
        } else if (std.mem.eql(u8, arg, "--name")) {
            if (name != null) return error.DuplicateName;

            const value = try command_args.nextValue(error.MissingName);
            if (value.len == 0) return error.EmptyName;
            if (!api.isCanonicalFileName(value)) return error.InvalidName;
            name = value;
        } else {
            return error.UnknownFlag;
        }
    }

    return name orelse return error.MissingName;
}

fn parseTrafficLogFlag(arg: []const u8, traffic_log_options: *api.TrafficLogOptions) bool {
    if (std.mem.eql(u8, arg, "--print-request")) {
        traffic_log_options.print_request = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--print-response")) {
        traffic_log_options.print_response = true;
        return true;
    }
    return false;
}

const OutputDir = struct {
    dir: std.Io.Dir,
    should_close: bool = false,

    fn close(output_dir: OutputDir, io: std.Io) void {
        if (output_dir.should_close) output_dir.dir.close(io);
    }
};

fn openOutputDir(io: std.Io, out_dir: ?[]const u8) !OutputDir {
    if (out_dir) |path| {
        assert(path.len > 0);
        const dir = if (std.fs.path.isAbsolute(path))
            try std.Io.Dir.openDirAbsolute(io, path, .{})
        else
            try std.Io.Dir.cwd().openDir(io, path, .{});

        return .{
            .dir = dir,
            .should_close = true,
        };
    }

    return .{
        .dir = std.Io.Dir.cwd(),
    };
}

fn writeResponseFile(io: std.Io, out_dir: ?[]const u8, response_id: []const u8, response_body: []const u8) !void {
    var name_buffer: [128]u8 = undefined;
    const name = try api_gen.responseFileName(&name_buffer, response_id);

    const output_dir = try openOutputDir(io, out_dir);
    defer output_dir.close(io);

    try output_dir.dir.writeFile(io, .{
        .sub_path = name,
        .data = response_body,
        .flags = .{ .exclusive = true },
    });
}

fn writeGeneratedFiles(io: std.Io, out_dir: ?[]const u8, files: api_gen.GeneratedFiles) !void {
    assert(files.items.len > 0);

    const output_dir = try openOutputDir(io, out_dir);
    defer output_dir.close(io);

    for (files.items) |file| {
        var name_buffer: [128]u8 = undefined;
        const name = try api_gen.generatedFileName(&name_buffer, files.response_id, file);
        try output_dir.dir.writeFile(io, .{
            .sub_path = name,
            .data = file.bytes,
            .flags = .{ .exclusive = true },
        });
    }
}

test "writeGeneratedFiles writes generated files under relative output directory" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp_dir.sub_path});
    defer gpa.free(out_dir);

    var items = [_]api_gen.GeneratedFile{
        .{
            .candidate_index = 0,
            .part_index = 0,
            .mime = .text,
            .bytes = @constCast("hello"),
        },
    };
    const files = api_gen.GeneratedFiles{
        .response_id = @constCast("test-response"),
        .items = &items,
    };

    try writeGeneratedFiles(std.testing.io, out_dir, files);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "test-response-0-0.txt",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings("hello", written);
}

test "writeResponseFile writes response body under absolute output directory" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var absolute_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const absolute_len = try tmp_dir.dir.realPath(std.testing.io, &absolute_buffer);
    const out_dir = absolute_buffer[0..absolute_len];

    try writeResponseFile(std.testing.io, out_dir, "test-response", "{}");

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "test-response.json",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings("{}", written);
}

fn writeStdoutLine(io: std.Io, line: []const u8) !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(io, line);
    try stdout.writeStreamingAll(io, "\n");
}

fn takePageFiles(
    gpa: std.mem.Allocator,
    files: *std.ArrayList(api_files.File),
    page: *api_files.FileListPage,
) !void {
    try files.ensureUnusedCapacity(gpa, page.files.len);

    const page_files = page.files;
    for (page_files) |file| files.appendAssumeCapacity(file);
    page.files = &.{};
    gpa.free(page_files);
}

const FileJson = struct {
    name: []const u8,
    displayName: ?[]const u8 = null,
    mimeType: ?[]const u8 = null,
    sizeBytes: ?[]const u8 = null,
    createTime: ?[]const u8 = null,
    updateTime: ?[]const u8 = null,
    expirationTime: ?[]const u8 = null,
    sha256Hash: ?[]const u8 = null,
    uri: ?[]const u8 = null,
    state: ?[]const u8 = null,
    source: ?[]const u8 = null,
};

const FileListJson = struct {
    files: []const FileJson,
};

fn fileMetadataJson(gpa: std.mem.Allocator, file: api_files.File) ![]u8 {
    return stringifyMetadataJson(gpa, fileJson(file));
}

fn filesListJson(gpa: std.mem.Allocator, files: []const api_files.File) ![]u8 {
    const file_jsons = try gpa.alloc(FileJson, files.len);
    defer gpa.free(file_jsons);

    for (files, 0..) |file, index| {
        file_jsons[index] = fileJson(file);
    }

    return stringifyMetadataJson(gpa, FileListJson{
        .files = file_jsons,
    });
}

fn fileJson(file: api_files.File) FileJson {
    return .{
        .name = file.name,
        .displayName = file.display_name,
        .mimeType = file.mime_type,
        .sizeBytes = file.size_bytes,
        .createTime = file.create_time,
        .updateTime = file.update_time,
        .expirationTime = file.expiration_time,
        .sha256Hash = file.sha256_hash,
        .uri = file.uri,
        .state = file.state,
        .source = file.source,
    };
}

fn stringifyMetadataJson(gpa: std.mem.Allocator, value: anytype) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(value, .{
        .whitespace = .indent_2,
        .emit_null_optional_fields = false,
    }, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn printUsageError(err: ParseError) void {
    switch (err) {
        error.MissingCommand => std.debug.print("error: missing command\n", .{}),
        error.UnknownCommand => std.debug.print("error: unknown command\n", .{}),
        error.MissingFilesCommand => std.debug.print("error: missing files subcommand\n", .{}),
        error.UnknownFilesCommand => std.debug.print("error: unknown files subcommand\n", .{}),
        error.MissingPrompt => std.debug.print("error: missing prompt\n", .{}),
        error.EmptyPrompt => std.debug.print("error: prompt must not be empty\n", .{}),
        error.PromptTooLong => std.debug.print("error: prompt must be at most 16 KiB\n", .{}),
        error.SplitPrompt => std.debug.print("error: prompt must be one quoted argument\n", .{}),
        error.DuplicatePrompt => std.debug.print("error: prompt specified more than once\n", .{}),
        error.MissingBase => std.debug.print("error: missing base image\n", .{}),
        error.EmptyBase => std.debug.print("error: base image must not be empty\n", .{}),
        error.DuplicateBase => std.debug.print("error: base image specified more than once\n", .{}),
        error.MissingBaseRole => std.debug.print("error: missing base role\n", .{}),
        error.DuplicateBaseRole => std.debug.print("error: base role specified more than once\n", .{}),
        error.InvalidBaseRole => std.debug.print("error: base role must be scene, character, or object\n", .{}),
        error.MissingReference => std.debug.print("error: missing reference image\n", .{}),
        error.EmptyReference => std.debug.print("error: reference image must not be empty\n", .{}),
        error.InvalidReference => std.debug.print("error: invalid reference image\n", .{}),
        error.TooManyReferences => std.debug.print("error: edit accepts at most 13 reference images plus one base image\n", .{}),
        error.TooManyCharacterReferences => std.debug.print("error: edit accepts at most 4 character references including a character base\n", .{}),
        error.TooManyObjectReferences => std.debug.print("error: edit accepts at most 10 object references including an object base\n", .{}),
        error.DuplicateLabel => std.debug.print("error: reference labels must be unique\n", .{}),
        error.InvalidLabel => std.debug.print("error: reference label must be ASCII SCREAMING_SNAKE_CASE and start with a letter\n", .{}),
        error.MissingMime => std.debug.print("error: image input must include MIME type as files/ID,MIME\n", .{}),
        error.InvalidMime => std.debug.print("error: image MIME must be image/jpeg, image/png, or image/webp\n", .{}),
        error.MalformedImageInput => std.debug.print("error: image input must have exactly one comma: files/ID,MIME\n", .{}),
        error.MissingPreserve => std.debug.print("error: missing preserve text\n", .{}),
        error.MissingDoNot => std.debug.print("error: missing do-not text\n", .{}),
        error.TooManyConstraints => std.debug.print("error: too many edit constraints\n", .{}),
        error.MissingPath => std.debug.print("error: missing upload path\n", .{}),
        error.EmptyPath => std.debug.print("error: upload path must not be empty\n", .{}),
        error.DuplicatePath => std.debug.print("error: upload path specified more than once\n", .{}),
        error.MissingName => std.debug.print("error: missing file name\n", .{}),
        error.EmptyName => std.debug.print("error: file name must not be empty\n", .{}),
        error.DuplicateName => std.debug.print("error: file name specified more than once\n", .{}),
        error.InvalidName => std.debug.print("error: file name must use canonical files/... form\n", .{}),
        error.MissingDisplayName => std.debug.print("error: missing display name\n", .{}),
        error.EmptyDisplayName => std.debug.print("error: display name must not be empty\n", .{}),
        error.DuplicateDisplayName => std.debug.print("error: display name specified more than once\n", .{}),
        error.InvalidDisplayNameUtf8 => std.debug.print("error: display name must be valid UTF-8\n", .{}),
        error.DisplayNameTooLong => std.debug.print("error: display name must be at most 512 Unicode code points\n", .{}),
        error.UnknownFlag => std.debug.print("error: unknown flag\n", .{}),
        error.UnexpectedArgument => std.debug.print("error: unexpected positional argument\n", .{}),
        error.WriteResponseUnsupported => std.debug.print("error: --write-response is only supported for gen and edit\n", .{}),
        error.MissingOutDir => std.debug.print("error: missing output directory\n", .{}),
        error.EmptyOutDir => std.debug.print("error: output directory must not be empty\n", .{}),
        error.DuplicateOutDir => std.debug.print("error: output directory specified more than once\n", .{}),
        error.OutDirUnsupported => std.debug.print("error: --out-dir is only supported for gen and edit\n", .{}),
    }
    std.debug.print("{s}", .{usageText()});
}

fn usageText() []const u8 {
    return "usage: nbimg gen [--print-request] [--print-response] [--write-response] [--out-dir DIR] [--prompt \"PROMPT\"]\n" ++
        "       nbimg edit [--print-request] [--print-response] [--write-response] [--out-dir DIR] --base files/ID,MIME [--base-role scene|character|object] [--character [LABEL=]files/ID,MIME] [--object [LABEL=]files/ID,MIME] [--style [LABEL=]files/ID,MIME] [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt \"PROMPT\"]\n" ++
        "       nbimg files upload [--print-request] [--print-response] [--display-name NAME] --path PATH\n" ++
        "       nbimg files list [--print-request] [--print-response]\n" ++
        "       nbimg files get [--print-request] [--print-response] --name files/ID\n" ++
        "       nbimg files delete [--print-request] [--print-response] --name files/ID\n" ++
        "\n" ++
        "edit reference details:\n" ++
        "       --base-role defaults to scene\n" ++
        "       --ref ROLE[:LABEL]=files/ID,MIME requires ROLE; no default role\n" ++
        "       valid ROLE values: character|object|style|pose|composition|background|texture|image\n" ++
        "       omitted LABEL auto-assigns by role: CHARACTER_A, OBJECT_A, STYLE_REFERENCE_A, POSE_REFERENCE_A, COMPOSITION_REFERENCE_A, BACKGROUND_REFERENCE_A, TEXTURE_REFERENCE_A, IMAGE_REFERENCE_A\n" ++
        "       MIME must be image/jpeg, image/png, or image/webp\n";
}

test "usageText documents edit reference roles and defaults" {
    const usage = usageText();
    const expected = [_][]const u8{
        "--out-dir DIR",
        "--base-role defaults to scene",
        "--ref ROLE[:LABEL]=files/ID,MIME requires ROLE; no default role",
        "character|object|style|pose|composition|background|texture|image",
        "CHARACTER_A",
        "OBJECT_A",
        "STYLE_REFERENCE_A",
        "POSE_REFERENCE_A",
        "COMPOSITION_REFERENCE_A",
        "BACKGROUND_REFERENCE_A",
        "TEXTURE_REFERENCE_A",
        "IMAGE_REFERENCE_A",
        "image/jpeg, image/png, or image/webp",
    };

    for (expected) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, usage, needle) != null);
    }
}

test "parseArgs accepts prompt flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
    try std.testing.expect(!gen.write_response);
    try std.testing.expectEqual(@as(?[]const u8, null), gen.out_dir);
}

test "parseArgs accepts stdin fallback prompt for gen" {
    const parsed_command = try parseArgsWithPrompt(&.{ "nbimg", "gen" }, "My fair lady");
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(!gen.write_response);
}

test "parseArgs explicit prompt takes precedence over stdin fallback" {
    const parsed_command = try parseArgsWithPrompt(
        &.{ "nbimg", "gen", "--prompt", "argument prompt" },
        "stdin prompt",
    );
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("argument prompt", gen.prompt);
}

test "parseArgs accepts print request flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--print-request", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
    try std.testing.expect(!gen.write_response);
}

test "parseArgs accepts print response flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--prompt", "My fair lady", "--print-response" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expect(!gen.write_response);
}

test "parseArgs accepts write response flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--write-response", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
    try std.testing.expect(gen.write_response);
    try std.testing.expectEqual(@as(?[]const u8, null), gen.out_dir);
}

test "parseArgs accepts gen output directory" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--out-dir", "outputs", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expectEqualStrings("outputs", gen.out_dir.?);
}

test "parseArgs accepts print flags in any order" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--print-response",
        "--write-response",
        "--prompt",
        "My fair lady",
        "--print-request",
    });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expect(gen.write_response);
}

test "parseArgs rejects invalid gen output directory arguments" {
    try std.testing.expectError(error.MissingOutDir, parseArgs(&.{ "nbimg", "gen", "--out-dir" }));
    try std.testing.expectError(error.MissingOutDir, parseArgs(&.{ "nbimg", "gen", "--out-dir", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyOutDir, parseArgs(&.{ "nbimg", "gen", "--out-dir", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateOutDir, parseArgs(&.{
        "nbimg",
        "gen",
        "--out-dir",
        "one",
        "--out-dir",
        "two",
        "--prompt",
        "My fair lady",
    }));
}

test "parseArgs accepts minimal edit command" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("change visual style to Broadway musical", edit.prompt);
    try std.testing.expectEqualStrings("files/tjtj5me9i96c", edit.base.name);
    try std.testing.expectEqual(api_edit.InputMime.jpeg, edit.base.mime);
    try std.testing.expectEqual(api_edit.BaseRole.scene, edit.base_role);
    try std.testing.expectEqual(@as(usize, 0), edit.reference_count);
    try std.testing.expectEqual(@as(usize, 0), edit.preserve_count);
    try std.testing.expectEqual(@as(usize, 0), edit.do_not_count);
    try std.testing.expect(!edit.write_response);
    try std.testing.expectEqual(@as(?[]const u8, null), edit.out_dir);
}

test "parseArgs accepts edit output directory" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--out-dir",
        "outputs",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("outputs", edit.out_dir.?);
}

test "parseArgs rejects invalid edit output directory arguments" {
    try std.testing.expectError(error.MissingOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--out-dir",
    }));
    try std.testing.expectError(error.EmptyOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--out-dir",
        "",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.DuplicateOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--out-dir",
        "one",
        "--out-dir",
        "two",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs accepts stdin fallback prompt for edit" {
    const parsed_command = try parseArgsWithPrompt(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
    }, "change visual style to Broadway musical");
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("change visual style to Broadway musical", edit.prompt);
    try std.testing.expectEqualStrings("files/tjtj5me9i96c", edit.base.name);
    try std.testing.expectEqual(api_edit.InputMime.jpeg, edit.base.mime);
}

test "parseArgs accepts edit base role constraints and traffic flags" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--print-request",
        "--write-response",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--base-role",
        "character",
        "--preserve",
        "preserve her facial identity",
        "--do-not",
        "do not change the crop",
        "--prompt",
        "change visual style to Broadway musical",
        "--print-response",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expect(edit.write_response);
    try std.testing.expectEqual(@as(?[]const u8, null), edit.out_dir);
    try std.testing.expectEqual(api_edit.BaseRole.character, edit.base_role);
    try std.testing.expectEqual(@as(usize, 1), edit.preserve_count);
    try std.testing.expectEqualStrings("preserve her facial identity", edit.preserves[0]);
    try std.testing.expectEqual(@as(usize, 1), edit.do_not_count);
    try std.testing.expectEqualStrings("do not change the crop", edit.do_nots[0]);
}

test "parseArgs accepts edit convenience and generic references" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--character",
        "files/person,image/jpeg",
        "--object",
        "OBJECT_PRODUCT=files/product,image/png",
        "--style",
        "files/style,image/webp",
        "--ref",
        "pose:POSE_MAIN=files/pose,image/jpeg",
        "--prompt",
        "edit BASE_IMAGE using references",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 4), edit.reference_count);
    try std.testing.expectEqual(api_edit.ReferenceRole.character, edit.references[0].role);
    try std.testing.expectEqualStrings("CHARACTER_A", edit.references[0].label);
    try std.testing.expectEqualStrings("files/person", edit.references[0].image.name);
    try std.testing.expectEqual(api_edit.InputMime.jpeg, edit.references[0].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.object, edit.references[1].role);
    try std.testing.expectEqualStrings("OBJECT_PRODUCT", edit.references[1].label);
    try std.testing.expectEqual(api_edit.InputMime.png, edit.references[1].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.style, edit.references[2].role);
    try std.testing.expectEqualStrings("STYLE_REFERENCE_A", edit.references[2].label);
    try std.testing.expectEqual(api_edit.InputMime.webp, edit.references[2].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.pose, edit.references[3].role);
    try std.testing.expectEqualStrings("POSE_MAIN", edit.references[3].label);
}

test "parseArgs accepts generic edit reference without custom label" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--ref",
        "texture=files/fabric,image/png",
        "--prompt",
        "use the fabric texture",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 1), edit.reference_count);
    try std.testing.expectEqual(api_edit.ReferenceRole.texture, edit.references[0].role);
    try std.testing.expectEqualStrings("TEXTURE_REFERENCE_A", edit.references[0].label);
    try std.testing.expectEqualStrings("files/fabric", edit.references[0].image.name);
}

test "parseArgs accepts files upload path flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
    });
    const files_upload = expectFilesUploadCommand(parsed_command);
    try std.testing.expectEqualStrings("sample_images/good_night.jpeg", files_upload.path);
    try std.testing.expectEqualStrings("good_night.jpeg", files_upload.display_name.?);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
}

test "parseArgs defaults files upload display name to local file name" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "references/nested/photo.webp",
    });
    const files_upload = expectFilesUploadCommand(parsed_command);
    try std.testing.expectEqualStrings("references/nested/photo.webp", files_upload.path);
    try std.testing.expectEqualStrings("photo.webp", files_upload.display_name.?);
}

test "parseArgs accepts files upload display name" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--display-name",
        "nbimg live api sample",
        "--path",
        "sample_images/good_night.jpeg",
    });
    const files_upload = expectFilesUploadCommand(parsed_command);
    try std.testing.expectEqualStrings("sample_images/good_night.jpeg", files_upload.path);
    try std.testing.expectEqualStrings("nbimg live api sample", files_upload.display_name.?);
}

test "parseArgs accepts files upload display name with exactly 512 Unicode code points" {
    const max_name: [:0]const u8 = "\xc3\xa9" ** max_display_name_codepoints;

    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        max_name,
    });
    const files_upload = expectFilesUploadCommand(parsed_command);
    try std.testing.expectEqualStrings(max_name, files_upload.display_name.?);
}

test "parseArgs accepts files upload traffic log flags" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--print-response",
        "--path",
        "sample_images/good_night.jpeg",
        "--print-request",
    });
    const files_upload = expectFilesUploadCommand(parsed_command);
    try std.testing.expectEqualStrings("sample_images/good_night.jpeg", files_upload.path);
    try std.testing.expectEqualStrings("good_night.jpeg", files_upload.display_name.?);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files list" {
    const parsed_command = try parseArgs(&.{ "nbimg", "files", "list" });
    _ = expectFilesListCommand(parsed_command);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files list traffic log flags" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--print-response",
        "--print-request",
    });
    _ = expectFilesListCommand(parsed_command);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files get canonical name flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
    });
    const files_get = expectFilesGetCommand(parsed_command);
    try std.testing.expectEqualStrings("files/abc123", files_get.name);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files get traffic log flags" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--print-response",
        "--name",
        "files/abc123",
        "--print-request",
    });
    const files_get = expectFilesGetCommand(parsed_command);
    try std.testing.expectEqualStrings("files/abc123", files_get.name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files delete canonical name flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
    });
    const files_delete = expectFilesDeleteCommand(parsed_command);
    try std.testing.expectEqualStrings("files/abc123", files_delete.name);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files delete traffic log flags" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--print-response",
        "--name",
        "files/abc123",
        "--print-request",
    });
    const files_delete = expectFilesDeleteCommand(parsed_command);
    try std.testing.expectEqualStrings("files/abc123", files_delete.name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "files upload json formats all metadata fields" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .display_name = "sample",
        .mime_type = "image/jpeg",
        .size_bytes = "229046",
        .create_time = "2026-05-18T08:14:20.799526Z",
        .update_time = "2026-05-18T08:14:20.799526Z",
        .expiration_time = "2026-05-20T08:14:20.425492423Z",
        .sha256_hash = "hash",
        .uri = "https://generativelanguage.googleapis.com/v1beta/files/abc123",
        .state = "ACTIVE",
        .source = "UPLOADED",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"displayName\": \"sample\",\n" ++
            "  \"mimeType\": \"image/jpeg\",\n" ++
            "  \"sizeBytes\": \"229046\",\n" ++
            "  \"createTime\": \"2026-05-18T08:14:20.799526Z\",\n" ++
            "  \"updateTime\": \"2026-05-18T08:14:20.799526Z\",\n" ++
            "  \"expirationTime\": \"2026-05-20T08:14:20.425492423Z\",\n" ++
            "  \"sha256Hash\": \"hash\",\n" ++
            "  \"uri\": \"https://generativelanguage.googleapis.com/v1beta/files/abc123\",\n" ++
            "  \"state\": \"ACTIVE\",\n" ++
            "  \"source\": \"UPLOADED\"\n" ++
            "}",
        json,
    );
}

test "files upload json omits absent metadata fields" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .mime_type = "image/jpeg",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"mimeType\": \"image/jpeg\"\n" ++
            "}",
        json,
    );
}

test "files upload json escapes string content" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .display_name = "sample, \"quoted\"\nname",
        .mime_type = "image/jpeg",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"displayName\": \"sample, \\\"quoted\\\"\\nname\",\n" ++
            "  \"mimeType\": \"image/jpeg\"\n" ++
            "}",
        json,
    );
}

test "files get json formats all metadata fields" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .display_name = "sample",
        .mime_type = "image/jpeg",
        .size_bytes = "229046",
        .create_time = "2026-05-18T08:14:20.799526Z",
        .update_time = "2026-05-18T08:14:20.799526Z",
        .expiration_time = "2026-05-20T08:14:20.425492423Z",
        .sha256_hash = "hash",
        .uri = "https://generativelanguage.googleapis.com/v1beta/files/abc123",
        .state = "ACTIVE",
        .source = "UPLOADED",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"displayName\": \"sample\",\n" ++
            "  \"mimeType\": \"image/jpeg\",\n" ++
            "  \"sizeBytes\": \"229046\",\n" ++
            "  \"createTime\": \"2026-05-18T08:14:20.799526Z\",\n" ++
            "  \"updateTime\": \"2026-05-18T08:14:20.799526Z\",\n" ++
            "  \"expirationTime\": \"2026-05-20T08:14:20.425492423Z\",\n" ++
            "  \"sha256Hash\": \"hash\",\n" ++
            "  \"uri\": \"https://generativelanguage.googleapis.com/v1beta/files/abc123\",\n" ++
            "  \"state\": \"ACTIVE\",\n" ++
            "  \"source\": \"UPLOADED\"\n" ++
            "}",
        json,
    );
}

test "files get json omits absent metadata fields" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .mime_type = "image/jpeg",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"mimeType\": \"image/jpeg\"\n" ++
            "}",
        json,
    );
}

test "files get json escapes string content" {
    const gpa = std.testing.allocator;
    var file = try testFile(gpa, .{
        .name = "files/abc123",
        .display_name = "sample, \"quoted\"\nname",
        .mime_type = "image/jpeg",
    });
    defer file.deinit(gpa);

    const json = try fileMetadataJson(gpa, file);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"name\": \"files/abc123\",\n" ++
            "  \"displayName\": \"sample, \\\"quoted\\\"\\nname\",\n" ++
            "  \"mimeType\": \"image/jpeg\"\n" ++
            "}",
        json,
    );
}

test "files list json formats empty file list" {
    const gpa = std.testing.allocator;
    const json = try filesListJson(gpa, &.{});
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"files\": []\n" ++
            "}",
        json,
    );
}

test "files list json formats multiple files" {
    const gpa = std.testing.allocator;
    var files = [_]api_files.File{
        try testFile(gpa, .{
            .name = "files/one",
            .display_name = "one",
        }),
        try testFile(gpa, .{
            .name = "files/two",
            .mime_type = "image/png",
        }),
    };
    defer for (&files) |*file| file.deinit(gpa);

    const json = try filesListJson(gpa, &files);
    defer gpa.free(json);

    try std.testing.expectEqualStrings(
        "{\n" ++
            "  \"files\": [\n" ++
            "    {\n" ++
            "      \"name\": \"files/one\",\n" ++
            "      \"displayName\": \"one\"\n" ++
            "    },\n" ++
            "    {\n" ++
            "      \"name\": \"files/two\",\n" ++
            "      \"mimeType\": \"image/png\"\n" ++
            "    }\n" ++
            "  ]\n" ++
            "}",
        json,
    );
}

test "parseArgs rejects missing prompt" {
    try std.testing.expectError(error.MissingPrompt, parseArgs(&.{ "nbimg", "gen" }));
}

test "parseArgs rejects traffic flag as prompt value" {
    try std.testing.expectError(error.MissingPrompt, parseArgs(&.{ "nbimg", "gen", "--prompt", "--print-request" }));
}

test "parseArgs rejects missing prompt value even with stdin fallback" {
    try std.testing.expectError(
        error.MissingPrompt,
        parseArgsWithPrompt(&.{ "nbimg", "gen", "--prompt" }, "stdin prompt"),
    );
}

test "shouldReadPromptFromStdin requires omitted prompt flag" {
    try std.testing.expect(shouldReadPromptFromStdin(&.{ "nbimg", "gen" }, error.MissingPrompt));
    try std.testing.expect(!shouldReadPromptFromStdin(&.{ "nbimg", "gen", "--prompt" }, error.MissingPrompt));
    try std.testing.expect(!shouldReadPromptFromStdin(&.{ "nbimg", "gen" }, error.UnknownFlag));
}

test "parseArgs rejects empty prompt" {
    try std.testing.expectError(error.EmptyPrompt, parseArgs(&.{ "nbimg", "gen", "--prompt", "" }));
}

test "parseArgs rejects split prompt" {
    try std.testing.expectError(error.SplitPrompt, parseArgs(&.{ "nbimg", "gen", "--prompt", "My", "fair", "lady" }));
}

test "parseArgs rejects unknown command" {
    try std.testing.expectError(error.UnknownCommand, parseArgs(&.{ "nbimg", "draw", "prompt" }));
}

test "parseArgs rejects edit missing base" {
    try std.testing.expectError(error.MissingBase, parseArgs(&.{
        "nbimg",
        "edit",
    }));

    try std.testing.expectError(error.MissingBase, parseArgs(&.{
        "nbimg",
        "edit",
        "--prompt",
        "change visual style to Broadway musical",
    }));

    try std.testing.expectError(error.MissingBase, parseArgs(&.{
        "nbimg",
        "edit",
        "--base-role",
        "character",
    }));
}

test "parseArgs rejects edit duplicate base" {
    try std.testing.expectError(error.DuplicateBase, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/one,image/jpeg",
        "--base",
        "files/two,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit missing MIME" {
    try std.testing.expectError(error.MissingMime, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit invalid MIME" {
    try std.testing.expectError(error.InvalidMime, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/gif",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit malformed image input" {
    try std.testing.expectError(error.MalformedImageInput, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg,extra",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit invalid base role" {
    try std.testing.expectError(error.InvalidBaseRole, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/tjtj5me9i96c,image/jpeg",
        "--base-role",
        "portrait",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit invalid label" {
    try std.testing.expectError(error.InvalidLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--character",
        "character_a=files/person,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit duplicate label" {
    try std.testing.expectError(error.DuplicateLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--character",
        "CHARACTER_A=files/person,image/jpeg",
        "--object",
        "CHARACTER_A=files/object,image/png",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit reserved base image label" {
    try std.testing.expectError(error.DuplicateLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--character",
        "BASE_IMAGE=files/person,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many character references including character base" {
    try std.testing.expectError(error.TooManyCharacterReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--base-role",
        "character",
        "--character",
        "files/one,image/jpeg",
        "--character",
        "files/two,image/jpeg",
        "--character",
        "files/three,image/jpeg",
        "--character",
        "files/four,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many object references including object base" {
    try std.testing.expectError(error.TooManyObjectReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--base-role",
        "object",
        "--object",
        "files/one,image/png",
        "--object",
        "files/two,image/png",
        "--object",
        "files/three,image/png",
        "--object",
        "files/four,image/png",
        "--object",
        "files/five,image/png",
        "--object",
        "files/six,image/png",
        "--object",
        "files/seven,image/png",
        "--object",
        "files/eight,image/png",
        "--object",
        "files/nine,image/png",
        "--object",
        "files/ten,image/png",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many references" {
    try std.testing.expectError(error.TooManyReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--style",
        "files/one,image/jpeg",
        "--style",
        "files/two,image/jpeg",
        "--style",
        "files/three,image/jpeg",
        "--style",
        "files/four,image/jpeg",
        "--style",
        "files/five,image/jpeg",
        "--style",
        "files/six,image/jpeg",
        "--style",
        "files/seven,image/jpeg",
        "--style",
        "files/eight,image/jpeg",
        "--style",
        "files/nine,image/jpeg",
        "--style",
        "files/ten,image/jpeg",
        "--style",
        "files/eleven,image/jpeg",
        "--style",
        "files/twelve,image/jpeg",
        "--style",
        "files/thirteen,image/jpeg",
        "--style",
        "files/fourteen,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs accepts edit empty constraints as no-ops" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--preserve",
        "",
        "--do-not",
        "",
        "--prompt",
        "edit",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 0), edit.preserve_count);
    try std.testing.expectEqual(@as(usize, 0), edit.do_not_count);
}

test "parseArgs keeps non-empty edit constraints when mixed with empty values" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/base,image/jpeg",
        "--preserve",
        "",
        "--preserve",
        "keep the crop",
        "--do-not",
        "change the logo",
        "--do-not",
        "",
        "--prompt",
        "edit",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 1), edit.preserve_count);
    try std.testing.expectEqualStrings("keep the crop", edit.preserves[0]);
    try std.testing.expectEqual(@as(usize, 1), edit.do_not_count);
    try std.testing.expectEqualStrings("change the logo", edit.do_nots[0]);
}

test "parseArgs rejects missing files subcommand" {
    try std.testing.expectError(error.MissingFilesCommand, parseArgs(&.{ "nbimg", "files" }));
}

test "parseArgs rejects unknown files subcommand" {
    try std.testing.expectError(error.UnknownFilesCommand, parseArgs(&.{ "nbimg", "files", "remove" }));
}

test "parseArgs rejects traffic flag before files subcommand" {
    try std.testing.expectError(error.UnknownFilesCommand, parseArgs(&.{ "nbimg", "files", "--print-request", "list" }));
}

test "parseArgs rejects missing upload path" {
    try std.testing.expectError(error.MissingPath, parseArgs(&.{ "nbimg", "files", "upload" }));
}

test "parseArgs rejects traffic flag as upload path value" {
    try std.testing.expectError(error.MissingPath, parseArgs(&.{ "nbimg", "files", "upload", "--path", "--print-request" }));
}

test "parseArgs rejects empty upload path" {
    try std.testing.expectError(error.EmptyPath, parseArgs(&.{ "nbimg", "files", "upload", "--path", "" }));
}

test "parseArgs rejects duplicate upload path" {
    try std.testing.expectError(error.DuplicatePath, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--path",
        "sample_images/good_night.jpeg",
    }));
}

test "parseArgs rejects missing files upload display name" {
    try std.testing.expectError(error.MissingDisplayName, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
    }));
}

test "parseArgs rejects traffic flag as files upload display name value" {
    try std.testing.expectError(error.MissingDisplayName, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        "--print-request",
    }));
}

test "parseArgs rejects empty files upload display name" {
    try std.testing.expectError(error.EmptyDisplayName, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        "",
    }));
}

test "parseArgs rejects duplicate files upload display name" {
    try std.testing.expectError(error.DuplicateDisplayName, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--display-name",
        "one",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        "two",
    }));
}

test "parseArgs rejects invalid UTF-8 files upload display name" {
    const invalid_name: [:0]const u8 = "\xff";

    try std.testing.expectError(error.InvalidDisplayNameUtf8, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        invalid_name,
    }));
}

test "parseArgs rejects files upload display name with 513 Unicode code points" {
    const too_long_name: [:0]const u8 = "\xc3\xa9" ** (max_display_name_codepoints + 1);

    try std.testing.expectError(error.DisplayNameTooLong, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--display-name",
        too_long_name,
    }));
}

test "parseArgs rejects output directory for files upload" {
    try std.testing.expectError(error.OutDirUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--out-dir",
        "outputs",
    }));
}

test "parseArgs rejects output directory for files list" {
    try std.testing.expectError(error.OutDirUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--out-dir",
        "outputs",
    }));
}

test "parseArgs rejects missing files get name" {
    try std.testing.expectError(error.MissingName, parseArgs(&.{ "nbimg", "files", "get" }));
}

test "parseArgs rejects traffic flag as files get name value" {
    try std.testing.expectError(error.MissingName, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "--print-request",
    }));
}

test "parseArgs rejects empty files get name" {
    try std.testing.expectError(error.EmptyName, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "",
    }));
}

test "parseArgs rejects duplicate files get name" {
    try std.testing.expectError(error.DuplicateName, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--name",
        "files/abc123",
    }));
}

test "parseArgs rejects bare files get id" {
    try std.testing.expectError(error.InvalidName, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "abc123",
    }));
}

test "parseArgs rejects empty canonical files get id" {
    try std.testing.expectError(error.InvalidName, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/",
    }));
}

test "parseArgs rejects output directory for files get" {
    try std.testing.expectError(error.OutDirUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--out-dir",
        "outputs",
    }));
}

test "parseArgs rejects unknown flag for files get" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--format",
        "json",
    }));
}

test "parseArgs rejects missing files delete name" {
    try std.testing.expectError(error.MissingName, parseArgs(&.{ "nbimg", "files", "delete" }));
}

test "parseArgs rejects traffic flag as files delete name value" {
    try std.testing.expectError(error.MissingName, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "--print-request",
    }));
}

test "parseArgs rejects empty files delete name" {
    try std.testing.expectError(error.EmptyName, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "",
    }));
}

test "parseArgs rejects duplicate files delete name" {
    try std.testing.expectError(error.DuplicateName, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--name",
        "files/abc123",
    }));
}

test "parseArgs rejects bare files delete id" {
    try std.testing.expectError(error.InvalidName, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "abc123",
    }));
}

test "parseArgs rejects empty canonical files delete id" {
    try std.testing.expectError(error.InvalidName, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/",
    }));
}

test "parseArgs rejects output directory for files delete" {
    try std.testing.expectError(error.OutDirUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--out-dir",
        "outputs",
    }));
}

test "parseArgs rejects unknown flag for files delete" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--format",
        "json",
    }));
}

test "parseArgs rejects flags" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{ "nbimg", "gen", "--out", "image.png" }));
}

test "parseArgs rejects positional prompt" {
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{ "nbimg", "gen", "My fair lady" }));
}

test "parseArgs rejects positional upload path" {
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{ "nbimg", "files", "upload", "sample_images/good_night.jpeg" }));
}

test "parseArgs rejects positional files list argument" {
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{ "nbimg", "files", "list", "extra" }));
}

test "parseArgs rejects positional files get name" {
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{ "nbimg", "files", "get", "files/abc123" }));
}

test "parseArgs rejects positional files delete name" {
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{ "nbimg", "files", "delete", "files/abc123" }));
}

test "parseArgs rejects duplicate prompt" {
    try std.testing.expectError(error.DuplicatePrompt, parseArgs(&.{
        "nbimg",
        "gen",
        "--prompt",
        "My fair lady",
        "--prompt",
        "My fair lady",
    }));
}

test "live API edit request shape is valid" {
    if (!build_options.live_api_tests) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var environ_map = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ_map.deinit();
    const api_key = try api.apiKeyFromMap(&environ_map);

    api.traffic_log_options = .{
        .print_request = true,
        .print_response = true,
    };
    defer api.traffic_log_options = .{};

    const upload_mime = api_files.InputMime.fromPath(live_edit_sample_image_path) orelse return error.UnsupportedInputMime;
    var uploaded_file = try uploadLiveEditSampleImage(gpa, api_key, upload_mime);
    defer uploaded_file.deinit(gpa);
    defer deleteLiveEditSampleImage(gpa, api_key, uploaded_file.name);

    var response = api_edit.countGenerateContentRequestTokens(
        gpa,
        std.testing.io,
        api_key,
        .{
            .prompt = live_edit_prompt,
            .base = .{
                .name = uploaded_file.name,
                .mime = editMimeFromUploadMime(upload_mime),
            },
            .base_role = .scene,
        },
    ) catch |err| {
        std.debug.print("error: countTokens edit request failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: countTokens edit request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return error.CountTokensRequestFailed;
    }

    const result = api.decodeCountTokensResponse(gpa, response.body) catch |err| {
        std.debug.print(
            "error: failed to parse countTokens response: {s}\n{s}\n",
            .{ @errorName(err), response.body },
        );
        return err;
    };

    try std.testing.expect(result.total_tokens > 0);
}

fn uploadLiveEditSampleImage(
    gpa: std.mem.Allocator,
    api_key: []const u8,
    mime: api_files.InputMime,
) !api_files.File {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        live_edit_sample_image_path,
        gpa,
        .limited(api_files.max_upload_bytes),
    );
    defer gpa.free(bytes);
    if (bytes.len == 0) return error.EmptyUploadFile;

    var response = try api_files.uploadFile(gpa, std.testing.io, api_key, .{
        .mime = mime,
        .bytes = bytes,
        .display_name = live_edit_upload_display_name,
    });
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: live edit fixture upload failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return error.LiveEditFixtureUploadFailed;
    }

    return api_files.decodeUploadedFile(gpa, response.body);
}

fn deleteLiveEditSampleImage(gpa: std.mem.Allocator, api_key: []const u8, name: []const u8) void {
    var response = api_files.deleteFile(gpa, std.testing.io, api_key, name) catch |err| {
        std.debug.print(
            "warning: failed to delete live edit fixture {s}: {s}\n",
            .{ name, @errorName(err) },
        );
        return;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "warning: live edit fixture delete for {s} returned HTTP {d}\n{s}\n",
            .{ name, @intFromEnum(response.status), response.body },
        );
    }
}

fn editMimeFromUploadMime(mime: api_files.InputMime) api_edit.InputMime {
    return switch (mime) {
        .jpeg => .jpeg,
        .png => .png,
        .webp => .webp,
    };
}

test "readPromptFromReader reads stdin fallback prompt" {
    const gpa = std.testing.allocator;
    var reader = std.Io.Reader.fixed("My fair lady");
    const prompt = try readPromptFromReader(gpa, &reader);
    defer gpa.free(prompt);

    try std.testing.expectEqualStrings("My fair lady", prompt);
}

test "readPromptFromReader preserves multiline prompt" {
    const gpa = std.testing.allocator;
    var reader = std.Io.Reader.fixed("line one\nline two\n");
    const prompt = try readPromptFromReader(gpa, &reader);
    defer gpa.free(prompt);

    try std.testing.expectEqualStrings("line one\nline two\n", prompt);
}

test "readPromptFromReader rejects empty stdin" {
    var reader = std.Io.Reader.fixed("");
    try std.testing.expectError(error.MissingPrompt, readPromptFromReader(std.testing.allocator, &reader));
}

test "readPromptFromReader accepts max prompt bytes" {
    const gpa = std.testing.allocator;
    const max_prompt = "a" ** max_prompt_bytes;
    var reader = std.Io.Reader.fixed(max_prompt);
    const prompt = try readPromptFromReader(gpa, &reader);
    defer gpa.free(prompt);

    try std.testing.expectEqual(@as(usize, max_prompt_bytes), prompt.len);
}

test "readPromptFromReader rejects stdin over max prompt bytes" {
    const too_long_prompt = "a" ** (max_prompt_bytes + 1);
    var reader = std.Io.Reader.fixed(too_long_prompt);
    try std.testing.expectError(error.PromptTooLong, readPromptFromReader(std.testing.allocator, &reader));
}

fn expectGenCommand(parsed_command: ParsedCommand) GenCommand {
    return switch (parsed_command.command) {
        .gen => |gen| gen,
        else => unreachable,
    };
}

fn expectEditCommand(parsed_command: ParsedCommand) EditCommand {
    return switch (parsed_command.command) {
        .edit => |edit| edit,
        else => unreachable,
    };
}

fn expectFilesUploadCommand(parsed_command: ParsedCommand) FilesUploadCommand {
    return switch (parsed_command.command) {
        .files_upload => |files_upload| files_upload,
        else => unreachable,
    };
}

fn expectFilesListCommand(parsed_command: ParsedCommand) FilesListCommand {
    return switch (parsed_command.command) {
        .files_list => |files_list| files_list,
        else => unreachable,
    };
}

fn expectFilesGetCommand(parsed_command: ParsedCommand) FilesGetCommand {
    return switch (parsed_command.command) {
        .files_get => |files_get| files_get,
        else => unreachable,
    };
}

fn expectFilesDeleteCommand(parsed_command: ParsedCommand) FilesDeleteCommand {
    return switch (parsed_command.command) {
        .files_delete => |files_delete| files_delete,
        else => unreachable,
    };
}

const TestFileInput = struct {
    name: []const u8,
    display_name: ?[]const u8 = null,
    mime_type: ?[]const u8 = null,
    size_bytes: ?[]const u8 = null,
    create_time: ?[]const u8 = null,
    update_time: ?[]const u8 = null,
    expiration_time: ?[]const u8 = null,
    sha256_hash: ?[]const u8 = null,
    uri: ?[]const u8 = null,
    state: ?[]const u8 = null,
    source: ?[]const u8 = null,
};

fn testFile(gpa: std.mem.Allocator, input: TestFileInput) !api_files.File {
    var file = api_files.File{
        .name = try gpa.dupe(u8, input.name),
    };
    errdefer file.deinit(gpa);

    file.display_name = try testOptional(gpa, input.display_name);
    file.mime_type = try testOptional(gpa, input.mime_type);
    file.size_bytes = try testOptional(gpa, input.size_bytes);
    file.create_time = try testOptional(gpa, input.create_time);
    file.update_time = try testOptional(gpa, input.update_time);
    file.expiration_time = try testOptional(gpa, input.expiration_time);
    file.sha256_hash = try testOptional(gpa, input.sha256_hash);
    file.uri = try testOptional(gpa, input.uri);
    file.state = try testOptional(gpa, input.state);
    file.source = try testOptional(gpa, input.source);

    return file;
}

fn testOptional(gpa: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try gpa.dupe(u8, bytes) else null;
}
