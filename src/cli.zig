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
};

pub const FilesListCommand = struct {};

pub const Command = union(enum) {
    gen: GenCommand,
    files_upload: FilesUploadCommand,
    files_list: FilesListCommand,
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
    UnknownFlag,
    UnexpectedArgument,
    WriteResponseUnsupported,
};

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

    const file_name = api.files.decodeUploadedFileName(gpa, response.body) catch |err| {
        std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer gpa.free(file_name);

    writeStdoutLine(init.io, file_name) catch |err| {
        std.debug.print("error: failed to print uploaded file id: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn runFilesList(init: std.process.Init, gpa: std.mem.Allocator, api_key: []const u8) u8 {
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

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

        for (page.names) |name| {
            writeStdoutLine(init.io, name) catch |err| {
                std.debug.print("error: failed to print file id: {s}\n", .{@errorName(err)});
                return exit_failure;
            };
        }

        page_token = page.next_page_token orelse break;
        page.next_page_token = null;
    }

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

    while (command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--write-response")) {
            return error.WriteResponseUnsupported;
        } else if (std.mem.eql(u8, arg, "--path")) {
            if (path != null) return error.DuplicatePath;

            const value = try command_args.nextValue(error.MissingPath);
            if (value.len == 0) return error.EmptyPath;
            path = value;
        } else {
            return error.UnknownFlag;
        }
    }

    return .{
        .path = path orelse return error.MissingPath,
    };
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
        error.UnknownFlag => std.debug.print("error: unknown flag\n", .{}),
        error.UnexpectedArgument => std.debug.print("error: unexpected positional argument\n", .{}),
        error.WriteResponseUnsupported => std.debug.print("error: --write-response is only supported for gen\n", .{}),
    }
    std.debug.print(
        "usage: nbimg gen [--print-request] [--print-response] [--write-response] --prompt \"PROMPT\"\n" ++
            "       nbimg files upload [--print-request] [--print-response] --path PATH\n" ++
            "       nbimg files list [--print-request] [--print-response]\n",
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
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(!parsed_command.traffic_log_options.print_response);
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
    try std.testing.expectError(error.UnknownFilesCommand, parseArgs(&.{ "nbimg", "files", "delete" }));
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
