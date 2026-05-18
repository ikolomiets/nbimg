//! User-facing command parsing, help output, diagnostics, and dispatch.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");

const exit_success = 0;
const exit_failure = 1;
const exit_usage = 2;
const exit_response_parse = 3;

pub const GenCommand = struct {
    prompt: []const u8,
    write_response: bool = false,
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
    SplitPrompt,
    DuplicatePrompt,
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

    const parsed_command = parseArgs(args) catch |err| {
        printUsageError(err);
        return exit_usage;
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
        .files_upload => |files_upload| runFilesUpload(init, gpa, api_key, files_upload),
        .files_list => runFilesList(init, gpa, api_key),
        .files_get => |files_get| runFilesGet(init, gpa, api_key, files_get),
        .files_delete => |files_delete| runFilesDelete(init, gpa, api_key, files_delete),
    };
}

fn runGen(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8, command: GenCommand) u8 {
    var response = api.gen.generateContent(gpa, init.io, api_key, command.prompt) catch |err| {
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
        const response_id = api.gen.decodeResponseId(gpa, response.body) catch |err| {
            std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
            return exit_response_parse;
        };
        defer gpa.free(response_id);

        writeResponseFile(init.io, response_id, response.body) catch |err| {
            std.debug.print("error: failed to write API response: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
    }

    var files = api.gen.decodeGeneratedFiles(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer files.deinit(gpa);

    writeGeneratedFiles(init.io, files) catch |err| {
        std.debug.print("error: failed to write generated files: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runFilesUpload(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    api_key: []const u8,
    command: FilesUploadCommand,
) u8 {
    const mime = api.files.InputMime.fromPath(command.path) orelse {
        std.debug.print("error: unsupported upload file type; expected .jpg, .jpeg, .png, or .webp\n", .{});
        return exit_usage;
    };

    const cwd = std.Io.Dir.cwd();
    const bytes = cwd.readFileAlloc(init.io, command.path, gpa, .limited(api.files.max_upload_bytes)) catch |err| {
        std.debug.print("error: failed to read upload file: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(bytes);

    if (bytes.len == 0) {
        std.debug.print("error: upload file must not be empty\n", .{});
        return exit_usage;
    }

    var response = api.files.uploadFile(gpa, init.io, api_key, .{
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

    var file = api.files.decodeUploadedFile(gpa, response.body) catch |err| {
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

    var files: std.ArrayList(api.files.File) = .empty;
    defer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    while (true) {
        var response = api.files.listFilesPage(gpa, init.io, api_key, page_token) catch |err| {
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

        var page = api.files.decodeFileListPage(gpa, response.body) catch |err| {
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
    var response = api.files.getFile(gpa, init.io, api_key, command.name) catch |err| {
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

    var file = api.files.decodeFile(gpa, response.body) catch |err| {
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
    var response = api.files.deleteFile(gpa, init.io, api_key, command.name) catch |err| {
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
    if (args.len < 2) return error.MissingCommand;

    if (std.mem.eql(u8, args[1], "gen")) {
        var command_args: CommandArgs = .{ .args = args[2..] };
        const gen = try parseGenCommand(&command_args);
        return .{
            .traffic_log_options = command_args.traffic_log_options,
            .command = .{ .gen = gen },
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

fn parseGenCommand(command_args: *CommandArgs) ParseError!GenCommand {
    var prompt: ?[]const u8 = null;
    var write_response = false;

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (prompt != null) return error.SplitPrompt;
            return error.UnexpectedArgument;
        }

        if (std.mem.eql(u8, arg, "--write-response")) {
            write_response = true;
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
        .prompt = prompt orelse return error.MissingPrompt,
        .write_response = write_response,
    };
}

fn parseFilesUploadCommand(command_args: *CommandArgs) ParseError!FilesUploadCommand {
    var path: ?[]const u8 = null;
    var display_name: ?[]const u8 = null;

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--write-response")) {
            return error.WriteResponseUnsupported;
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

    return .{
        .path = path orelse return error.MissingPath,
        .display_name = display_name,
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
        } else if (std.mem.eql(u8, arg, "--name")) {
            if (name != null) return error.DuplicateName;

            const value = try command_args.nextValue(error.MissingName);
            if (value.len == 0) return error.EmptyName;
            if (!api.files.isCanonicalFileName(value)) return error.InvalidName;
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

fn writeResponseFile(io: std.Io, response_id: []const u8, response_body: []const u8) !void {
    var name_buffer: [128]u8 = undefined;
    const name = try api.gen.responseFileName(&name_buffer, response_id);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{
        .sub_path = name,
        .data = response_body,
        .flags = .{ .exclusive = true },
    });
}

fn writeGeneratedFiles(io: std.Io, files: api.gen.GeneratedFiles) !void {
    assert(files.items.len > 0);

    const cwd = std.Io.Dir.cwd();
    for (files.items) |file| {
        var name_buffer: [128]u8 = undefined;
        const name = try api.gen.generatedFileName(&name_buffer, files.response_id, file);
        try cwd.writeFile(io, .{
            .sub_path = name,
            .data = file.bytes,
            .flags = .{ .exclusive = true },
        });
    }
}

fn writeStdoutLine(io: std.Io, line: []const u8) !void {
    const stdout = std.Io.File.stdout();
    try stdout.writeStreamingAll(io, line);
    try stdout.writeStreamingAll(io, "\n");
}

fn takePageFiles(
    gpa: std.mem.Allocator,
    files: *std.ArrayList(api.files.File),
    page: *api.files.FileListPage,
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

fn fileMetadataJson(gpa: std.mem.Allocator, file: api.files.File) ![]u8 {
    return stringifyMetadataJson(gpa, fileJson(file));
}

fn filesListJson(gpa: std.mem.Allocator, files: []const api.files.File) ![]u8 {
    const file_jsons = try gpa.alloc(FileJson, files.len);
    defer gpa.free(file_jsons);

    for (files, 0..) |file, index| {
        file_jsons[index] = fileJson(file);
    }

    return stringifyMetadataJson(gpa, FileListJson{
        .files = file_jsons,
    });
}

fn fileJson(file: api.files.File) FileJson {
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
        error.SplitPrompt => std.debug.print("error: prompt must be one quoted argument\n", .{}),
        error.DuplicatePrompt => std.debug.print("error: prompt specified more than once\n", .{}),
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
        error.WriteResponseUnsupported => std.debug.print("error: --write-response is only supported for gen\n", .{}),
    }
    std.debug.print(
        "usage: nbimg gen [--print-request] [--print-response] [--write-response] --prompt \"PROMPT\"\n" ++
            "       nbimg files upload [--print-request] [--print-response] [--display-name NAME] --path PATH\n" ++
            "       nbimg files list [--print-request] [--print-response]\n" ++
            "       nbimg files get [--print-request] [--print-response] --name files/ID\n" ++
            "       nbimg files delete [--print-request] [--print-response] --name files/ID\n",
        .{},
    );
}

test "parseArgs accepts prompt flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
    try std.testing.expect(!gen.write_response);
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
    try std.testing.expectEqual(@as(?[]const u8, null), files_upload.display_name);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
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
    try std.testing.expectEqual(@as(?[]const u8, null), files_upload.display_name);
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
    var files = [_]api.files.File{
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

test "parseArgs rejects empty prompt" {
    try std.testing.expectError(error.EmptyPrompt, parseArgs(&.{ "nbimg", "gen", "--prompt", "" }));
}

test "parseArgs rejects split prompt" {
    try std.testing.expectError(error.SplitPrompt, parseArgs(&.{ "nbimg", "gen", "--prompt", "My", "fair", "lady" }));
}

test "parseArgs rejects unknown command" {
    try std.testing.expectError(error.UnknownCommand, parseArgs(&.{ "nbimg", "edit", "prompt" }));
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

test "parseArgs rejects write response for files upload" {
    try std.testing.expectError(error.WriteResponseUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--write-response",
    }));
}

test "parseArgs rejects write response for files list" {
    try std.testing.expectError(error.WriteResponseUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--write-response",
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

test "parseArgs rejects write response for files get" {
    try std.testing.expectError(error.WriteResponseUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--write-response",
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

test "parseArgs rejects write response for files delete" {
    try std.testing.expectError(error.WriteResponseUnsupported, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--write-response",
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

fn expectGenCommand(parsed_command: ParsedCommand) GenCommand {
    return switch (parsed_command.command) {
        .gen => |gen| gen,
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

fn testFile(gpa: std.mem.Allocator, input: TestFileInput) !api.files.File {
    var file = api.files.File{
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
