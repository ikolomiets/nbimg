//! User-facing command parsing, help output, diagnostics, and dispatch.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const api_batch = @import("batch.zig");
const client = @import("client.zig");
const api_edit = @import("edit.zig");
const api_files = @import("files.zig");
const api_gen = @import("gen.zig");
const build_options = @import("build_options");

const exit_success = 0;
const exit_failure = 1;
const exit_usage = 2;
const exit_response_parse = 3;
const live_edit_sample_image_path = "sample_images/good_night.jpeg";
const live_edit_upload_display_name = "nbimg live edit request validity";
const live_edit_prompt = "change visual style to Broadway musical";
const default_cli_traffic_log_options = api.TrafficLogOptions{ .print_response = true };

const GenCommand = struct {
    prompt: []const u8,
    output_options: api.ImageOutputOptions = .{},
    grounding_options: api.GroundingOptions = .{},
    thinking_options: api.ThinkingOptions = .{},
    safety_options: ?api.SafetyOptions = null,
    generation_options: api.GenerationOptions = .{},
    request_options: api.RequestOptions = .{},
    out_dir: ?[]const u8 = null,
    batch_file: ?[]const u8 = null,
    batch_key: ?[]const u8 = null,
};

const max_edit_constraints = 16;

const EditCommand = struct {
    prompt: []const u8,
    output_options: api.ImageOutputOptions = .{},
    grounding_options: api.GroundingOptions = .{},
    thinking_options: api.ThinkingOptions = .{},
    safety_options: ?api.SafetyOptions = null,
    generation_options: api.GenerationOptions = .{},
    request_options: api.RequestOptions = .{},
    out_dir: ?[]const u8 = null,
    batch_file: ?[]const u8 = null,
    batch_key: ?[]const u8 = null,
    base: api_edit.UploadedImage,
    base_role: api_edit.ReferenceRole = .scene,
    references: [api_edit.max_references]api_edit.Reference = undefined,
    reference_count: usize = 0,
    preserves: [max_edit_constraints][]const u8 = undefined,
    preserve_count: usize = 0,
    do_nots: [max_edit_constraints][]const u8 = undefined,
    do_not_count: usize = 0,

    fn referenceSlice(command: *const EditCommand) []const api_edit.Reference {
        return command.references[0..command.reference_count];
    }

    fn preserveSlice(command: *const EditCommand) []const []const u8 {
        return command.preserves[0..command.preserve_count];
    }

    fn doNotSlice(command: *const EditCommand) []const []const u8 {
        return command.do_nots[0..command.do_not_count];
    }
};

const FilesUploadCommand = struct {
    path: []const u8,
    display_name: ?[]const u8 = null,
};

const FilesListCommand = struct {};

const FilesGetCommand = struct {
    name: []const u8,
};

const FilesDeleteCommand = struct {
    name: []const u8,
};

const BatchSubmitCommand = struct {
    path: []const u8,
    display_name: []const u8,
};

const BatchStatusCommand = struct {
    name: []const u8,
};

const BatchCancelCommand = struct {
    name: []const u8,
};

const BatchDownloadCommand = struct {
    name: []const u8,
    out_dir: ?[]const u8 = null,
};

const BatchListCommand = struct {};

const Command = union(enum) {
    gen: GenCommand,
    edit: EditCommand,
    files_upload: FilesUploadCommand,
    files_list: FilesListCommand,
    files_get: FilesGetCommand,
    files_delete: FilesDeleteCommand,
    batch_submit: BatchSubmitCommand,
    batch_status: BatchStatusCommand,
    batch_cancel: BatchCancelCommand,
    batch_download: BatchDownloadCommand,
    batch_list: BatchListCommand,
};

const ParsedCommand = struct {
    traffic_log_options: api.TrafficLogOptions = default_cli_traffic_log_options,
    api_key: ?[]const u8 = null,
    command: Command,
};

const ParseError = error{
    MissingCommand,
    UnknownCommand,
    MissingApiKey,
    EmptyApiKey,
    DuplicateApiKey,
    MissingFilesCommand,
    UnknownFilesCommand,
    MissingBatchCommand,
    UnknownBatchCommand,
    MissingPrompt,
    EmptyPrompt,
    PromptTooLong,
    SplitPrompt,
    DuplicatePrompt,
    MissingBase,
    LabeledBaseReference,
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
    EmptyPreserve,
    PreserveTooLong,
    MissingDoNot,
    EmptyDoNot,
    DoNotTooLong,
    TooManyConstraints,
    MissingPath,
    EmptyPath,
    DuplicatePath,
    MissingName,
    EmptyName,
    DuplicateName,
    InvalidName,
    InvalidBatchName,
    MissingDisplayName,
    EmptyDisplayName,
    DuplicateDisplayName,
    InvalidDisplayNameUtf8,
    DisplayNameTooLong,
    MissingAspectRatio,
    EmptyAspectRatio,
    DuplicateAspectRatio,
    InvalidAspectRatio,
    MissingImageSize,
    EmptyImageSize,
    DuplicateImageSize,
    InvalidImageSize,
    MissingGrounding,
    EmptyGrounding,
    DuplicateGrounding,
    InvalidGrounding,
    MissingThinkingLevel,
    EmptyThinkingLevel,
    DuplicateThinkingLevel,
    InvalidThinkingLevel,
    DuplicateIncludeThoughts,
    MissingSafety,
    EmptySafety,
    DuplicateSafety,
    InvalidSafety,
    MissingTemperature,
    EmptyTemperature,
    DuplicateTemperature,
    InvalidTemperature,
    MissingTopP,
    EmptyTopP,
    DuplicateTopP,
    InvalidTopP,
    MissingSeed,
    EmptySeed,
    DuplicateSeed,
    InvalidSeed,
    MissingMaxOutputTokens,
    EmptyMaxOutputTokens,
    DuplicateMaxOutputTokens,
    InvalidMaxOutputTokens,
    MissingPresencePenalty,
    EmptyPresencePenalty,
    DuplicatePresencePenalty,
    InvalidPresencePenalty,
    MissingFrequencyPenalty,
    EmptyFrequencyPenalty,
    DuplicateFrequencyPenalty,
    InvalidFrequencyPenalty,
    MissingStop,
    EmptyStop,
    TooManyStops,
    DuplicateStop,
    DuplicateResponseLogprobs,
    MissingLogprobs,
    EmptyLogprobs,
    DuplicateLogprobs,
    InvalidLogprobs,
    LogprobsRequiresResponseLogprobs,
    MissingSystem,
    EmptySystem,
    SystemTooLong,
    DuplicateSystem,
    MissingCachedContent,
    EmptyCachedContent,
    DuplicateCachedContent,
    InvalidCachedContent,
    MissingServiceTier,
    EmptyServiceTier,
    DuplicateServiceTier,
    InvalidServiceTier,
    DuplicateStore,
    UnknownFlag,
    UnexpectedArgument,
    MissingOutDir,
    EmptyOutDir,
    DuplicateOutDir,
    OutDirUnsupported,
    MissingBatchFile,
    EmptyBatchFile,
    DuplicateBatchFile,
    MissingBatchKey,
    EmptyBatchKey,
    DuplicateBatchKey,
    BatchKeyRequiresBatchFile,
    BatchFileConflictsOutDir,
};

const max_display_name_codepoints = 512;

const CommandArgs = struct {
    args: []const [:0]const u8,
    index: usize = 0,
    traffic_log_options: api.TrafficLogOptions = default_cli_traffic_log_options,
    api_key: ?[]const u8 = null,

    fn nextOption(command_args: *CommandArgs) ParseError!?[]const u8 {
        while (command_args.index < command_args.args.len) {
            const arg_z = command_args.args[command_args.index];
            command_args.index += 1;

            const arg: []const u8 = arg_z;
            if (parseTrafficLogFlag(arg, &command_args.traffic_log_options)) continue;
            if (std.mem.eql(u8, arg, "--api-key")) {
                if (command_args.api_key != null) return error.DuplicateApiKey;

                const value = try command_args.nextValue(error.MissingApiKey);
                if (value.len == 0) return error.EmptyApiKey;
                command_args.api_key = value;
                continue;
            }
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

/// Runs the CLI once and returns its process exit code.
///
/// - Borrows process initialization state and uses its allocators and I/O for temporary work.
/// - Converts command, allocation, filesystem, and network errors to exit codes and may mutate files and remote state.
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

    const api_key = resolveApiKey(parsed_command.api_key, init.environ_map) catch |err| switch (err) {
        error.MissingApiKey => {
            std.debug.print("error: GEMINI_API_KEY is not set\n", .{});
            return exit_usage;
        },
        error.EmptyApiKey => {
            std.debug.print("error: GEMINI_API_KEY is empty\n", .{});
            return exit_usage;
        },
    };
    const request_context = api.RequestContext{
        .gpa = gpa,
        .io = init.io,
        .api_key = api_key,
        .traffic_log_options = parsed_command.traffic_log_options,
    };

    return switch (parsed_command.command) {
        .gen => |gen| runGen(init, gpa, &request_context, &gen),
        .edit => |edit| runEdit(init, gpa, &request_context, edit),
        .files_upload => |files_upload| runFilesUpload(init, gpa, &request_context, files_upload),
        .files_list => runFilesList(init, gpa, &request_context),
        .files_get => |files_get| runFilesGet(init, gpa, &request_context, files_get),
        .files_delete => |files_delete| runFilesDelete(init, gpa, &request_context, files_delete),
        .batch_submit => |batch_submit| runBatchSubmit(init, gpa, &request_context, batch_submit),
        .batch_status => |batch_status| runBatchStatus(init, gpa, &request_context, batch_status),
        .batch_cancel => |batch_cancel| runBatchCancel(init, gpa, &request_context, batch_cancel),
        .batch_download => |batch_download| runBatchDownload(init, gpa, &request_context, batch_download),
        .batch_list => runBatchList(init, gpa, &request_context),
    };
}

fn resolveApiKey(
    explicit_api_key: ?[]const u8,
    environ_map: *const std.process.Environ.Map,
) api.ApiKeyError![]const u8 {
    if (explicit_api_key) |api_key| {
        if (api_key.len == 0) return error.EmptyApiKey;
        return api_key;
    }

    return api.apiKeyFromMap(environ_map);
}

fn runGen(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: *const GenCommand,
) u8 {
    if (command.batch_file) |batch_file| {
        const generate_request_json = api_gen.buildGenerateRequest(
            gpa,
            command.prompt,
            command.output_options,
            command.grounding_options,
            command.thinking_options,
            command.safety_options,
            command.generation_options,
            command.request_options,
        ) catch |err| {
            std.debug.print("error: failed to build generation request: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
        defer gpa.free(generate_request_json);

        return runBatchRequest(
            init,
            gpa,
            context,
            batch_file,
            command.batch_key,
            generate_request_json,
        );
    }

    var outcome = client.generateWithContext(
        context,
        generationRequestFromCommand(command),
        .immediate_cli,
    ) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };

    return switch (outcome) {
        .success => |*result| runGeneratedResult(gpa, init.io, command, result),
        .api_failure => |*failure| api_failure: {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: API request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            break :api_failure exit_failure;
        },
        .response_decoding_failure => |err| response_decoding_failure: {
            std.debug.print("error: failed to parse API response: {s}\n", .{@errorName(err)});
            break :response_decoding_failure exit_response_parse;
        },
    };
}

fn generationRequestFromCommand(command: *const GenCommand) client.GenerationRequest {
    return .{
        .prompt = command.prompt,
        .output_options = generationOutputOptionsFromCommand(command.output_options),
        .grounding_options = .{
            .web = command.grounding_options.web,
            .image = command.grounding_options.image,
        },
        .thinking_options = generationThinkingOptionsFromCommand(command.thinking_options),
        .safety_options = if (command.safety_options) |options|
            generationSafetyOptionsFromCommand(options)
        else
            null,
        .generation_options = generationOptionsFromCommand(&command.generation_options),
        .request_options = generationRequestOptionsFromCommand(command.request_options),
    };
}

fn generationOutputOptionsFromCommand(
    options: api.ImageOutputOptions,
) client.ImageOutputOptions {
    return .{
        .aspect_ratio = if (options.aspect_ratio) |value| switch (value) {
            .r1_1 => .r1_1,
            .r1_4 => .r1_4,
            .r1_8 => .r1_8,
            .r2_3 => .r2_3,
            .r3_2 => .r3_2,
            .r3_4 => .r3_4,
            .r4_1 => .r4_1,
            .r4_3 => .r4_3,
            .r4_5 => .r4_5,
            .r5_4 => .r5_4,
            .r8_1 => .r8_1,
            .r9_16 => .r9_16,
            .r16_9 => .r16_9,
            .r21_9 => .r21_9,
        } else null,
        .image_size = if (options.image_size) |value| switch (value) {
            .px512 => .px512,
            .k1 => .k1,
            .k2 => .k2,
            .k4 => .k4,
        } else null,
    };
}

fn generationThinkingOptionsFromCommand(
    options: api.ThinkingOptions,
) client.ThinkingOptions {
    return .{
        .level = if (options.level) |value| switch (value) {
            .minimal => .minimal,
            .high => .high,
        } else null,
        .include_thoughts = options.include_thoughts,
    };
}

fn generationSafetyOptionsFromCommand(
    options: api.SafetyOptions,
) client.SafetyOptions {
    return .{ .threshold = switch (options.threshold) {
        .block_low_and_above => .block_low_and_above,
        .block_medium_and_above => .block_medium_and_above,
        .block_only_high => .block_only_high,
        .block_none => .block_none,
        .off => .off,
        .harm_block_threshold_unspecified => .harm_block_threshold_unspecified,
    } };
}

fn generationOptionsFromCommand(
    options: *const api.GenerationOptions,
) client.GenerationOptions {
    return .{
        .max_output_tokens = options.max_output_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .seed = options.seed,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .response_logprobs = options.response_logprobs,
        .logprobs = options.logprobs,
        .stop_sequences = options.stopSequenceSlice(),
    };
}

fn generationRequestOptionsFromCommand(
    options: api.RequestOptions,
) client.RequestOptions {
    return .{
        .system_instruction = options.system_instruction,
        .cached_content = options.cached_content,
        .service_tier = if (options.service_tier) |value| switch (value) {
            .flex => .flex,
            .standard => .standard,
            .priority => .priority,
        } else null,
        .store = options.store,
    };
}

fn runGeneratedResult(
    gpa: std.mem.Allocator,
    io: std.Io,
    command: *const GenCommand,
    result: *client.GenerationResult,
) u8 {
    defer result.deinit(gpa);
    warnIfGenerationPriorityDowngraded(command.request_options, result.*);

    writeGenerationResult(io, command.out_dir, result.*) catch |err| {
        std.debug.print("error: failed to write generated files: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    return exit_success;
}

fn runEdit(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: EditCommand,
) u8 {
    const edit_request = api_edit.EditRequest{
        .prompt = command.prompt,
        .output_options = command.output_options,
        .grounding_options = command.grounding_options,
        .thinking_options = command.thinking_options,
        .safety_options = command.safety_options,
        .generation_options = command.generation_options,
        .request_options = command.request_options,
        .base = command.base,
        .base_role = command.base_role,
        .references = command.referenceSlice(),
        .preserves = command.preserveSlice(),
        .do_nots = command.doNotSlice(),
    };

    if (command.batch_file) |batch_file| {
        const generate_request_json = api_edit.buildGenerateRequest(gpa, edit_request) catch |err| {
            std.debug.print("error: failed to build edit request: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
        defer gpa.free(generate_request_json);

        return runBatchRequest(
            init,
            gpa,
            context,
            batch_file,
            command.batch_key,
            generate_request_json,
        );
    }

    var response = api_edit.generateContent(context, edit_request) catch |err| {
        printApiRequestError(context, err);
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
    warnIfPriorityDowngraded(gpa, command.request_options, response.body);

    var files = api.decodeGeneratedFiles(gpa, response.body) catch |err| {
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

const BatchAppendResult = struct {
    key: []u8,

    fn deinit(result: *BatchAppendResult, gpa: std.mem.Allocator) void {
        gpa.free(result.key);
        result.* = undefined;
    }
};

fn runBatchRequest(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    batch_file: []const u8,
    batch_key: ?[]const u8,
    generate_request_json: []const u8,
) u8 {
    const count_tokens_json = api.buildCountTokensRequestFromGenerateContentJson(
        gpa,
        .nano2,
        generate_request_json,
    ) catch |err| {
        std.debug.print("error: failed to build countTokens request: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(count_tokens_json);

    var response = api.postCountTokensJson(
        context,
        .nano2,
        count_tokens_json,
    ) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: countTokens validation failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    const token_result = api.decodeCountTokensResponse(gpa, response.body) catch |err| {
        std.debug.print(
            "error: failed to parse countTokens response: {s}\n{s}\n",
            .{ @errorName(err), response.body },
        );
        return exit_response_parse;
    };

    var append_result = appendBatchRequest(
        gpa,
        init.io,
        batch_file,
        batch_key,
        generate_request_json,
    ) catch |err| {
        switch (err) {
            error.DuplicateBatchKey => std.debug.print(
                "error: batch key already exists in {s}\n",
                .{batch_file},
            ),
            error.InvalidBatchFile => std.debug.print(
                "error: existing batch file is not valid Batch API JSONL: {s}\n",
                .{batch_file},
            ),
            error.BatchEntryTooLong => std.debug.print(
                "error: batch entry exceeds {d} bytes: {s}\n",
                .{ api_batch.max_entry_bytes, batch_file },
            ),
            error.BatchTooManyEntries => std.debug.print(
                "error: batch file already contains the maximum of {d} entries: {s}\n",
                .{ api_batch.max_entries, batch_file },
            ),
            error.BatchInputTooLong => std.debug.print(
                "error: batch file exceeds {d} bytes: {s}\n",
                .{ api_batch.max_input_bytes, batch_file },
            ),
            else => std.debug.print(
                "error: failed to append batch request to {s}: {s}\n",
                .{ batch_file, @errorName(err) },
            ),
        }
        return exit_failure;
    };
    defer append_result.deinit(gpa);

    const receipt = batchReceiptJson(
        gpa,
        append_result.key,
        token_result.total_tokens,
        batch_file,
    ) catch |err| {
        std.debug.print("error: failed to format batch receipt: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(receipt);

    writeStdoutLine(init.io, receipt) catch |err| {
        std.debug.print("error: failed to print batch receipt: {s}\n", .{@errorName(err)});
        return exit_failure;
    };

    return exit_success;
}

fn appendBatchRequest(
    gpa: std.mem.Allocator,
    io: std.Io,
    batch_file: []const u8,
    requested_key: ?[]const u8,
    generate_request_json: []const u8,
) !BatchAppendResult {
    assert(batch_file.len > 0);
    assert(generate_request_json.len > 0);
    if (requested_key) |key| assert(key.len > 0);

    var file = if (std.fs.path.isAbsolute(batch_file))
        try std.Io.Dir.createFileAbsolute(io, batch_file, .{
            .read = true,
            .truncate = false,
            .lock = .exclusive,
        })
    else
        try std.Io.Dir.cwd().createFile(io, batch_file, .{
            .read = true,
            .truncate = false,
            .lock = .exclusive,
        });
    defer file.close(io);

    const original_length = try file.length(io);
    if (original_length > api_batch.max_input_bytes) return error.BatchInputTooLong;
    var needs_separator = false;
    if (original_length > 0) {
        var last_byte: [1]u8 = undefined;
        const read_count = try file.readPositionalAll(io, &last_byte, original_length - 1);
        if (read_count != 1) return error.BatchFileReadFailed;
        needs_separator = last_byte[0] != '\n';
    }

    const entry_offset = std.math.add(
        u64,
        original_length,
        @intFromBool(needs_separator),
    ) catch return error.FileTooBig;

    const effective_key = if (requested_key) |key|
        try gpa.dupe(u8, key)
    else
        try std.fmt.allocPrint(gpa, "nbimg-{d}", .{entry_offset});
    errdefer gpa.free(effective_key);

    const inspection = try inspectBatchFile(gpa, io, file, effective_key);
    if (inspection.entry_count >= api_batch.max_entries) return error.BatchTooManyEntries;
    if (inspection.key_exists) return error.DuplicateBatchKey;

    const entry_json = try api_batch.buildEntryJson(gpa, effective_key, generate_request_json);
    defer gpa.free(entry_json);
    if (entry_json.len > api_batch.max_entry_bytes) return error.BatchEntryTooLong;

    var append_output: std.Io.Writer.Allocating = .init(gpa);
    defer append_output.deinit();
    if (needs_separator) try append_output.writer.writeByte('\n');
    try append_output.writer.writeAll(entry_json);
    try append_output.writer.writeByte('\n');
    const final_length = std.math.add(
        u64,
        original_length,
        append_output.written().len,
    ) catch return error.FileTooBig;
    if (final_length > api_batch.max_input_bytes) return error.BatchInputTooLong;

    errdefer file.setLength(io, original_length) catch {};
    try file.writePositionalAll(io, append_output.written(), original_length);

    return .{ .key = effective_key };
}

const BatchFileInspection = struct {
    entry_count: usize,
    key_exists: bool,
};

fn inspectBatchFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    file: std.Io.File,
    key: []const u8,
) !BatchFileInspection {
    assert(key.len > 0);

    var read_buffer: [16 * 1024]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    var line_output: std.Io.Writer.Allocating = .init(gpa);
    defer line_output.deinit();
    var entry_count: usize = 0;
    var key_exists = false;

    while (true) {
        line_output.clearRetainingCapacity();
        _ = file_reader.interface.streamDelimiterLimit(
            &line_output.writer,
            '\n',
            .limited(api_batch.max_entry_bytes + 1),
        ) catch |err| switch (err) {
            error.StreamTooLong => return error.BatchEntryTooLong,
            error.WriteFailed => return error.OutOfMemory,
            error.ReadFailed => return error.BatchFileReadFailed,
        };

        const buffered = file_reader.interface.buffered();
        const has_delimiter = buffered.len > 0;
        if (has_delimiter) assert(buffered[0] == '\n');

        const line = line_output.written();
        if (line.len > api_batch.max_entry_bytes) return error.BatchEntryTooLong;
        if (line.len == 0) {
            if (!has_delimiter) {
                return .{
                    .entry_count = entry_count,
                    .key_exists = key_exists,
                };
            }
            return error.InvalidBatchFile;
        }

        const ExistingBatchEntry = struct {
            key: []const u8,
            request: std.json.Value,
        };
        var parsed = std.json.parseFromSlice(
            ExistingBatchEntry,
            gpa,
            line,
            .{ .ignore_unknown_fields = true },
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidBatchFile,
        };
        defer parsed.deinit();

        if (parsed.value.key.len == 0) return error.InvalidBatchFile;
        if (parsed.value.request != .object) return error.InvalidBatchFile;
        if (std.mem.eql(u8, parsed.value.key, key)) key_exists = true;
        entry_count += 1;

        if (!has_delimiter) {
            return .{
                .entry_count = entry_count,
                .key_exists = key_exists,
            };
        }
        file_reader.interface.toss(1);
    }
}

fn batchReceiptJson(
    gpa: std.mem.Allocator,
    key: []const u8,
    total_tokens: u64,
    batch_file: []const u8,
) ![]u8 {
    assert(key.len > 0);
    assert(batch_file.len > 0);

    const BatchReceipt = struct {
        key: []const u8,
        totalTokens: u64,
        batchFile: []const u8,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(BatchReceipt{
        .key = key,
        .totalTokens = total_tokens,
        .batchFile = batch_file,
    }, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

test "batchReceiptJson serializes scripting receipt" {
    const gpa = std.testing.allocator;
    const receipt = try batchReceiptJson(
        gpa,
        "hero-\"001",
        123,
        "batch/requests.jsonl",
    );
    defer gpa.free(receipt);

    try std.testing.expectEqualStrings(
        "{\"key\":\"hero-\\\"001\",\"totalTokens\":123,\"batchFile\":\"batch/requests.jsonl\"}",
        receipt,
    );
}

test "appendBatchRequest creates file and generates offset key" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    const request_json =
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}";
    var result = try appendBatchRequest(
        gpa,
        std.testing.io,
        batch_path,
        null,
        request_json,
    );
    defer result.deinit(gpa);

    try std.testing.expectEqualStrings("nbimg-0", result.key);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings(
        "{\"key\":\"nbimg-0\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}}\n",
        written,
    );
}

test "appendBatchRequest appends after missing separator newline" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const first_entry =
        "{\"key\":\"first\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}]}}";
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "requests.jsonl",
        .data = first_entry,
    });

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    const request_json = "{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}";
    var result = try appendBatchRequest(
        gpa,
        std.testing.io,
        batch_path,
        null,
        request_json,
    );
    defer result.deinit(gpa);

    const expected_key = try std.fmt.allocPrint(gpa, "nbimg-{d}", .{first_entry.len + 1});
    defer gpa.free(expected_key);
    try std.testing.expectEqualStrings(expected_key, result.key);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(2048),
    );
    defer gpa.free(written);
    const expected = try std.fmt.allocPrint(
        gpa,
        "{s}\n{{\"key\":\"{s}\",\"request\":{s}}}\n",
        .{ first_entry, expected_key, request_json },
    );
    defer gpa.free(expected);
    try std.testing.expectEqualStrings(expected, written);
}

test "appendBatchRequest rejects duplicate key without modifying file" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const existing =
        "{\"key\":\"hero-001\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}]}}\n";
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "requests.jsonl",
        .data = existing,
    });

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    try std.testing.expectError(
        error.DuplicateBatchKey,
        appendBatchRequest(
            gpa,
            std.testing.io,
            batch_path,
            "hero-001",
            "{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}",
        ),
    );

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings(existing, written);
}

test "appendBatchRequest rejects malformed existing JSONL without modifying file" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const existing = "not-json\n";
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "requests.jsonl",
        .data = existing,
    });

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    try std.testing.expectError(
        error.InvalidBatchFile,
        appendBatchRequest(
            gpa,
            std.testing.io,
            batch_path,
            "hero-001",
            "{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}",
        ),
    );

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings(existing, written);
}

test "appendBatchRequest does not revalidate existing request semantics" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const existing =
        "{\"key\":\"older\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}],\"futureField\":true}}\n";
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "requests.jsonl",
        .data = existing,
    });

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    var result = try appendBatchRequest(
        gpa,
        std.testing.io,
        batch_path,
        "newer",
        "{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}",
    );
    defer result.deinit(gpa);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(2048),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings(
        existing ++ "{\"key\":\"newer\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}}\n",
        written,
    );
}

test "appendBatchRequest accepts maximum entry and rejects one over maximum without modifying file" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const existing = try testBatchInputJsonl(gpa, api_batch.max_entries - 1);
    defer gpa.free(existing);
    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "requests.jsonl",
        .data = existing,
    });

    const batch_path = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/requests.jsonl",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(batch_path);

    const accepted_key = try std.fmt.allocPrint(gpa, "key-{d}", .{api_batch.max_entries - 1});
    defer gpa.free(accepted_key);
    var maximum = try appendBatchRequest(
        gpa,
        std.testing.io,
        batch_path,
        accepted_key,
        "{\"contents\":[{\"parts\":[{\"text\":\"maximum\"}]}]}",
    );
    defer maximum.deinit(gpa);

    const full_file = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(api_batch.max_input_bytes),
    );
    defer gpa.free(full_file);
    try api_batch.validateInputJsonl(full_file);

    const rejected_key = try std.fmt.allocPrint(gpa, "key-{d}", .{api_batch.max_entries});
    defer gpa.free(rejected_key);
    try std.testing.expectError(
        error.BatchTooManyEntries,
        appendBatchRequest(
            gpa,
            std.testing.io,
            batch_path,
            rejected_key,
            "{\"contents\":[{\"parts\":[{\"text\":\"over maximum\"}]}]}",
        ),
    );

    const after_rejection = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "requests.jsonl",
        gpa,
        .limited(api_batch.max_input_bytes),
    );
    defer gpa.free(after_rejection);
    try std.testing.expectEqualSlices(u8, full_file, after_rejection);
}

fn warnIfPriorityDowngraded(
    gpa: std.mem.Allocator,
    request_options: api.RequestOptions,
    response_body: []const u8,
) void {
    const requested_service_tier = request_options.service_tier orelse return;
    if (requested_service_tier != .priority) return;

    const actual_service_tier = api.decodeResponseServiceTier(gpa, response_body) catch return;
    const reported_service_tier = actual_service_tier orelse return;
    if (reported_service_tier != .standard) return;

    std.debug.print(
        "warning: requested Gemini service tier priority, but the response reports standard\n",
        .{},
    );
}

fn warnIfGenerationPriorityDowngraded(
    request_options: api.RequestOptions,
    result: client.GenerationResult,
) void {
    if (!generationPriorityDowngraded(request_options, result)) return;

    std.debug.print(
        "warning: requested Gemini service tier priority, but the response reports standard\n",
        .{},
    );
}

fn generationPriorityDowngraded(
    request_options: api.RequestOptions,
    result: client.GenerationResult,
) bool {
    const requested_service_tier = request_options.service_tier orelse return false;
    if (requested_service_tier != .priority) return false;

    const reported_service_tier = result.reported_service_tier orelse return false;
    return reported_service_tier == .standard;
}

fn printApiRequestError(context: *const api.RequestContext, err: anyerror) void {
    if (err == error.Timeout) {
        std.debug.print(
            "error: API request timed out after {d} seconds\n",
            .{context.timeout.toSeconds()},
        );
        return;
    }

    std.debug.print("error: API request failed: {s}\n", .{@errorName(err)});
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
    const prompt = reader.allocRemaining(gpa, .limited(api.max_generate_text_part_bytes + 1)) catch |err| switch (err) {
        error.StreamTooLong => return error.PromptTooLong,
        else => return err,
    };
    errdefer gpa.free(prompt);

    if (prompt.len == 0) return error.MissingPrompt;
    if (prompt.len > api.max_generate_text_part_bytes) return error.PromptTooLong;
    return prompt;
}

fn runFilesUpload(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: FilesUploadCommand,
) u8 {
    const mime = api.ImageMime.fromPath(command.path) orelse {
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

    var response = api_files.uploadFile(context, .{
        .mime = mime,
        .bytes = bytes,
        .display_name = command.display_name,
    }) catch |err| {
        printApiRequestError(context, err);
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

fn runFilesList(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
) u8 {
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    var files: std.ArrayList(api_files.File) = .empty;
    defer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    while (true) {
        var response = api_files.listFilesPage(context, page_token) catch |err| {
            printApiRequestError(context, err);
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

fn runFilesGet(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: FilesGetCommand,
) u8 {
    var response = api_files.getFile(context, command.name) catch |err| {
        printApiRequestError(context, err);
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

fn runFilesDelete(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: FilesDeleteCommand,
) u8 {
    var response = api_files.deleteFile(context, command.name) catch |err| {
        printApiRequestError(context, err);
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

fn runBatchSubmit(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: BatchSubmitCommand,
) u8 {
    const bytes = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        command.path,
        gpa,
        .limited(api_batch.max_input_bytes + 1),
    ) catch |err| {
        if (err == error.StreamTooLong) {
            std.debug.print(
                "error: batch input file exceeds {d} bytes\n",
                .{api_batch.max_input_bytes},
            );
            return exit_usage;
        }
        std.debug.print("error: failed to read batch input file: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(bytes);

    api_batch.validateInputJsonl(bytes) catch |err| {
        switch (err) {
            error.EmptyBatchInput => std.debug.print("error: batch input file must not be empty\n", .{}),
            error.BatchInputTooLong => std.debug.print(
                "error: batch input file exceeds {d} bytes\n",
                .{api_batch.max_input_bytes},
            ),
            error.BatchEntryTooLong => std.debug.print(
                "error: batch input entry exceeds {d} bytes\n",
                .{api_batch.max_entry_bytes},
            ),
            error.BatchTooManyEntries => std.debug.print(
                "error: batch input contains more than {d} entries\n",
                .{api_batch.max_entries},
            ),
            error.InvalidBatchInput => std.debug.print("error: batch input contains an empty JSONL entry\n", .{}),
        }
        return exit_usage;
    };

    var upload_response = api_batch.uploadInput(
        context,
        bytes,
        command.display_name,
    ) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };
    defer upload_response.deinit(gpa);

    if (upload_response.status != .ok) {
        std.debug.print(
            "error: batch input upload failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(upload_response.status), upload_response.body },
        );
        return exit_failure;
    }

    const uploaded_file_name = api.decodeUploadedFileName(gpa, upload_response.body) catch |err| {
        std.debug.print("error: failed to parse batch input upload response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer gpa.free(uploaded_file_name);

    var submit_response = api_batch.submit(context, .{
        .file_name = uploaded_file_name,
        .display_name = command.display_name,
    }) catch |err| {
        printAmbiguousBatchCreationFailure(uploaded_file_name, err);
        return exit_failure;
    };
    defer submit_response.deinit(gpa);

    if (submit_response.status != .ok) {
        std.debug.print(
            "error: batch creation failed with HTTP {d}; uploaded input remains as {s}\n{s}\n",
            .{ @intFromEnum(submit_response.status), uploaded_file_name, submit_response.body },
        );
        return exit_failure;
    }

    const batch_name = api_batch.decodeBatchName(gpa, submit_response.body) catch |err| {
        std.debug.print("error: failed to parse batch creation response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer gpa.free(batch_name);

    return printPrettyBatchResponse(init.io, gpa, submit_response.body);
}

fn runBatchStatus(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: BatchStatusCommand,
) u8 {
    var response = api_batch.status(context, command.name) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: batch status failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    return printPrettyBatchResponse(init.io, gpa, response.body);
}

fn runBatchCancel(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: BatchCancelCommand,
) u8 {
    var response = api_batch.cancel(context, command.name) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: batch cancel failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return exit_failure;
    }

    writeStdoutLine(init.io, "OK") catch |err| {
        std.debug.print("error: failed to print batch cancel result: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    return exit_success;
}

fn runBatchDownload(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
    command: BatchDownloadCommand,
) u8 {
    var status_response = api_batch.status(context, command.name) catch |err| {
        printApiRequestError(context, err);
        return exit_failure;
    };
    defer status_response.deinit(gpa);

    if (status_response.status != .ok) {
        std.debug.print(
            "error: batch status failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(status_response.status), status_response.body },
        );
        return exit_failure;
    }

    var download_info = api_batch.decodeDownloadInfo(gpa, status_response.body) catch |err| {
        switch (err) {
            error.BatchNotSucceeded => std.debug.print(
                "error: batch download requires a succeeded batch\n",
                .{},
            ),
            error.BatchTooManyEntries => std.debug.print(
                "error: batch reports more than the supported maximum of {d} requests\n",
                .{api_batch.max_entries},
            ),
            error.MissingBatchOutputFile => std.debug.print(
                "error: succeeded batch status does not contain a downloadable output file\n",
                .{},
            ),
            else => std.debug.print(
                "error: failed to parse batch download status: {s}\n",
                .{@errorName(err)},
            ),
        }
        return exit_response_parse;
    };
    defer download_info.deinit(gpa);

    var download_response = api_batch.downloadOutput(
        context,
        download_info.file_name,
    ) catch |err| {
        if (err == error.ResponseTooLong) {
            std.debug.print(
                "error: batch output exceeds {d} bytes\n",
                .{api_batch.max_output_bytes},
            );
        } else {
            printApiRequestError(context, err);
        }
        return exit_failure;
    };
    defer download_response.deinit(gpa);

    if (download_response.status != .ok) {
        std.debug.print(
            "error: batch output download failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(download_response.status), download_response.body },
        );
        return exit_failure;
    }

    var summary = processBatchOutput(
        gpa,
        init.io,
        command.out_dir,
        download_response.body,
    ) catch |err| {
        const diagnostic = batchOutputProcessingDiagnostic(
            gpa,
            command.out_dir,
            err,
        ) catch |format_err| {
            std.debug.print(
                "error: failed to format batch output error: {s}\n",
                .{@errorName(format_err)},
            );
            return exit_failure;
        };
        defer gpa.free(diagnostic);
        std.debug.print("{s}", .{diagnostic});
        return exit_failure;
    };
    defer summary.deinit(gpa);

    for (summary.written_files) |name| {
        writeStdoutLine(init.io, name) catch |err| {
            std.debug.print("error: failed to print downloaded filename: {s}\n", .{@errorName(err)});
            return exit_failure;
        };
    }
    for (summary.existing_files) |name| {
        const diagnostic = batchOutputExistingFileDiagnostic(
            gpa,
            command.out_dir,
            name,
        ) catch |err| {
            std.debug.print(
                "error: failed to format existing batch output path: {s}\n",
                .{@errorName(err)},
            );
            return exit_failure;
        };
        defer gpa.free(diagnostic);
        std.debug.print("{s}", .{diagnostic});
    }
    for (summary.failed_keys) |key| {
        std.debug.print("error: batch result failed for key {s}\n", .{key});
    }

    return if (summary.existing_files.len == 0 and summary.failed_keys.len == 0)
        exit_success
    else
        exit_failure;
}

fn batchOutputProcessingDiagnostic(
    gpa: std.mem.Allocator,
    out_dir: ?[]const u8,
    err: anyerror,
) ![]u8 {
    return switch (err) {
        error.EmptyBatchOutput => gpa.dupe(u8, "error: downloaded batch output is empty\n"),
        error.BatchTooManyEntries => std.fmt.allocPrint(
            gpa,
            "error: downloaded batch output contains more than {d} records\n",
            .{api_batch.max_entries},
        ),
        error.FileNotFound => gpa.dupe(
            u8,
            "error: batch output directory does not exist\n",
        ),
        error.NotDir => std.fmt.allocPrint(
            gpa,
            "error: batch output path is not a directory: {s}\n",
            .{out_dir orelse "."},
        ),
        error.AccessDenied, error.PermissionDenied => std.fmt.allocPrint(
            gpa,
            "error: batch output directory is not accessible: {s}\n",
            .{out_dir orelse "."},
        ),
        else => std.fmt.allocPrint(
            gpa,
            "error: failed to process downloaded batch output: {s}\n",
            .{@errorName(err)},
        ),
    };
}

fn batchOutputExistingFileDiagnostic(
    gpa: std.mem.Allocator,
    out_dir: ?[]const u8,
    name: []const u8,
) ![]u8 {
    assert(name.len > 0);

    const path = if (out_dir) |directory|
        try std.fs.path.join(gpa, &.{ directory, name })
    else
        try gpa.dupe(u8, name);
    defer gpa.free(path);

    return std.fmt.allocPrint(
        gpa,
        "error: batch output file already exists and was not overwritten: {s}\n",
        .{path},
    );
}

fn runBatchList(
    init: std.process.Init,
    gpa: std.mem.Allocator,
    context: *const api.RequestContext,
) u8 {
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    var operations: std.ArrayList([]u8) = .empty;
    defer {
        for (operations.items) |operation| gpa.free(operation);
        operations.deinit(gpa);
    }

    while (true) {
        var response = api_batch.listPage(context, page_token) catch |err| {
            printApiRequestError(context, err);
            return exit_failure;
        };
        defer response.deinit(gpa);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        if (response.status != .ok) {
            std.debug.print(
                "error: batch list failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(response.status), response.body },
            );
            return exit_failure;
        }

        var page = api_batch.decodeListPage(gpa, response.body) catch |err| {
            std.debug.print("error: failed to parse Batch API list response: {s}\n", .{@errorName(err)});
            return exit_response_parse;
        };
        defer page.deinit(gpa);

        takeBatchPageOperations(gpa, &operations, &page) catch |err| {
            std.debug.print("error: failed to collect Batch operations: {s}\n", .{@errorName(err)});
            return exit_failure;
        };

        page_token = page.next_page_token orelse break;
        page.next_page_token = null;
    }

    const output = api_batch.listJson(gpa, operations.items) catch |err| {
        std.debug.print("error: failed to format Batch operation list: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    defer gpa.free(output);

    writeStdoutLine(init.io, output) catch |err| {
        std.debug.print("error: failed to print Batch operation list: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    return exit_success;
}

fn printPrettyBatchResponse(io: std.Io, gpa: std.mem.Allocator, response_body: []const u8) u8 {
    const output = api_batch.prettyJson(gpa, response_body) catch |err| {
        std.debug.print("error: failed to parse Batch API response: {s}\n", .{@errorName(err)});
        return exit_response_parse;
    };
    defer gpa.free(output);

    writeStdoutLine(io, output) catch |err| {
        std.debug.print("error: failed to print Batch API response: {s}\n", .{@errorName(err)});
        return exit_failure;
    };
    return exit_success;
}

fn printAmbiguousBatchCreationFailure(uploaded_file_name: []const u8, err: anyerror) void {
    assert(api.isCanonicalFileName(uploaded_file_name));

    std.debug.print(
        "error: batch creation transport failed after uploading {s}: {s}\n",
        .{ uploaded_file_name, @errorName(err) },
    );
    std.debug.print(
        "warning: batch creation is non-idempotent; a job may have been created, so nbimg did not retry\n",
        .{},
    );
}

fn ambiguousBatchCreationFailureText(
    gpa: std.mem.Allocator,
    uploaded_file_name: []const u8,
    err: anyerror,
) ![]u8 {
    assert(api.isCanonicalFileName(uploaded_file_name));
    return std.fmt.allocPrint(
        gpa,
        "error: batch creation transport failed after uploading {s}: {s}\n" ++
            "warning: batch creation is non-idempotent; a job may have been created, so nbimg did not retry\n",
        .{ uploaded_file_name, @errorName(err) },
    );
}

fn parseArgs(args: []const [:0]const u8) ParseError!ParsedCommand {
    return parseArgsWithPrompt(args, null);
}

fn parseArgsWithPrompt(args: []const [:0]const u8, stdin_prompt: ?[]const u8) ParseError!ParsedCommand {
    if (args.len < 2) return error.MissingCommand;

    if (std.mem.eql(u8, args[1], "gen")) {
        var command_args: CommandArgs = .{ .args = args[2..] };
        const gen = try parseGenCommand(&command_args, stdin_prompt);
        return .{
            .traffic_log_options = command_args.traffic_log_options,
            .api_key = command_args.api_key,
            .command = .{ .gen = gen },
        };
    }

    if (std.mem.eql(u8, args[1], "edit")) {
        var command_args: CommandArgs = .{ .args = args[2..] };
        const edit = try parseEditCommand(&command_args, stdin_prompt);
        return .{
            .traffic_log_options = command_args.traffic_log_options,
            .api_key = command_args.api_key,
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
                .api_key = command_args.api_key,
                .command = .{ .files_upload = files_upload },
            };
        }

        if (std.mem.eql(u8, subcommand, "list")) {
            const files_list = try parseFilesListCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .files_list = files_list },
            };
        }

        if (std.mem.eql(u8, subcommand, "get")) {
            const files_get = try parseFilesGetCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .files_get = files_get },
            };
        }

        if (std.mem.eql(u8, subcommand, "delete")) {
            const files_delete = try parseFilesDeleteCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .files_delete = files_delete },
            };
        }

        return error.UnknownFilesCommand;
    }

    if (std.mem.eql(u8, args[1], "batch")) {
        if (args.len < 3) return error.MissingBatchCommand;

        const subcommand: []const u8 = args[2];
        var command_args: CommandArgs = .{ .args = args[3..] };
        if (std.mem.eql(u8, subcommand, "submit")) {
            const batch_submit = try parseBatchSubmitCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .batch_submit = batch_submit },
            };
        }

        if (std.mem.eql(u8, subcommand, "status")) {
            const batch_status = try parseBatchStatusCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .batch_status = batch_status },
            };
        }

        if (std.mem.eql(u8, subcommand, "cancel")) {
            const batch_cancel = try parseBatchCancelCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .batch_cancel = batch_cancel },
            };
        }

        if (std.mem.eql(u8, subcommand, "download")) {
            const batch_download = try parseBatchDownloadCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .batch_download = batch_download },
            };
        }

        if (std.mem.eql(u8, subcommand, "list")) {
            const batch_list = try parseBatchListCommand(&command_args);
            return .{
                .traffic_log_options = command_args.traffic_log_options,
                .api_key = command_args.api_key,
                .command = .{ .batch_list = batch_list },
            };
        }

        return error.UnknownBatchCommand;
    }

    return error.UnknownCommand;
}

fn parseGenCommand(command_args: *CommandArgs, stdin_prompt: ?[]const u8) ParseError!GenCommand {
    var prompt: ?[]const u8 = null;
    var output_options: api.ImageOutputOptions = .{};
    var grounding_options: api.GroundingOptions = .{};
    var thinking_options: api.ThinkingOptions = .{};
    var safety_options: ?api.SafetyOptions = null;
    var generation_options: api.GenerationOptions = .{};
    var request_options: api.RequestOptions = .{};
    var grounding_seen = false;
    var include_thoughts_seen = false;
    var safety_seen = false;
    var response_logprobs_seen = false;
    var out_dir: ?[]const u8 = null;
    var batch_file: ?[]const u8 = null;
    var batch_key: ?[]const u8 = null;

    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (prompt != null) return error.SplitPrompt;
            return error.UnexpectedArgument;
        }

        if (std.mem.eql(u8, arg, "--out-dir")) {
            if (out_dir != null) return error.DuplicateOutDir;

            const value = try command_args.nextValue(error.MissingOutDir);
            if (value.len == 0) return error.EmptyOutDir;
            out_dir = value;
        } else if (try parseBatchOption(command_args, arg, &batch_file, &batch_key)) {
            continue;
        } else if (std.mem.eql(u8, arg, "--aspect-ratio")) {
            try parseAspectRatioOption(command_args, &output_options);
        } else if (std.mem.eql(u8, arg, "--image-size")) {
            try parseImageSizeOption(command_args, &output_options);
        } else if (std.mem.eql(u8, arg, "--grounding")) {
            try parseGroundingOption(command_args, &grounding_options, &grounding_seen);
        } else if (std.mem.eql(u8, arg, "--thinking-level")) {
            try parseThinkingLevelOption(command_args, &thinking_options);
        } else if (std.mem.eql(u8, arg, "--include-thoughts")) {
            try parseIncludeThoughtsOption(&thinking_options, &include_thoughts_seen);
        } else if (std.mem.eql(u8, arg, "--safety")) {
            try parseSafetyOption(command_args, &safety_options, &safety_seen);
        } else if (try parseRequestOption(command_args, arg, &request_options)) {
            continue;
        } else if (try parseGenerationOption(command_args, arg, &generation_options, &response_logprobs_seen)) {
            continue;
        } else if (std.mem.eql(u8, arg, "--prompt")) {
            if (prompt != null) return error.DuplicatePrompt;

            const value = try command_args.nextValue(error.MissingPrompt);
            if (value.len == 0) return error.EmptyPrompt;
            if (value.len > api.max_generate_text_part_bytes) return error.PromptTooLong;
            prompt = value;
        } else {
            return error.UnknownFlag;
        }
    }

    try validateGenerationOptionDependencies(generation_options);
    try validateBatchOptions(out_dir, batch_file, batch_key);

    return .{
        .prompt = prompt orelse try fallbackPrompt(stdin_prompt),
        .output_options = output_options,
        .grounding_options = grounding_options,
        .thinking_options = thinking_options,
        .safety_options = safety_options,
        .generation_options = generation_options,
        .request_options = request_options,
        .out_dir = out_dir,
        .batch_file = batch_file,
        .batch_key = batch_key,
    };
}

fn parseEditCommand(command_args: *CommandArgs, stdin_prompt: ?[]const u8) ParseError!EditCommand {
    var prompt: ?[]const u8 = null;
    var output_options: api.ImageOutputOptions = .{};
    var grounding_options: api.GroundingOptions = .{};
    var thinking_options: api.ThinkingOptions = .{};
    var safety_options: ?api.SafetyOptions = null;
    var generation_options: api.GenerationOptions = .{};
    var request_options: api.RequestOptions = .{};
    var grounding_seen = false;
    var include_thoughts_seen = false;
    var safety_seen = false;
    var response_logprobs_seen = false;
    var out_dir: ?[]const u8 = null;
    var batch_file: ?[]const u8 = null;
    var batch_key: ?[]const u8 = null;
    var base: ?api_edit.UploadedImage = null;
    var base_role: api_edit.ReferenceRole = .scene;
    var references: [api_edit.max_references]api_edit.Reference = undefined;
    var reference_count: usize = 0;
    var preserves: [max_edit_constraints][]const u8 = undefined;
    var preserve_count: usize = 0;
    var do_nots: [max_edit_constraints][]const u8 = undefined;
    var do_not_count: usize = 0;

    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) {
            if (prompt != null) return error.SplitPrompt;
            return error.UnexpectedArgument;
        }

        if (std.mem.eql(u8, arg, "--out-dir")) {
            if (out_dir != null) return error.DuplicateOutDir;

            const value = try command_args.nextValue(error.MissingOutDir);
            if (value.len == 0) return error.EmptyOutDir;
            out_dir = value;
        } else if (try parseBatchOption(command_args, arg, &batch_file, &batch_key)) {
            continue;
        } else if (std.mem.eql(u8, arg, "--aspect-ratio")) {
            try parseAspectRatioOption(command_args, &output_options);
        } else if (std.mem.eql(u8, arg, "--image-size")) {
            try parseImageSizeOption(command_args, &output_options);
        } else if (std.mem.eql(u8, arg, "--grounding")) {
            try parseGroundingOption(command_args, &grounding_options, &grounding_seen);
        } else if (std.mem.eql(u8, arg, "--thinking-level")) {
            try parseThinkingLevelOption(command_args, &thinking_options);
        } else if (std.mem.eql(u8, arg, "--include-thoughts")) {
            try parseIncludeThoughtsOption(&thinking_options, &include_thoughts_seen);
        } else if (std.mem.eql(u8, arg, "--safety")) {
            try parseSafetyOption(command_args, &safety_options, &safety_seen);
        } else if (try parseRequestOption(command_args, arg, &request_options)) {
            continue;
        } else if (try parseGenerationOption(command_args, arg, &generation_options, &response_logprobs_seen)) {
            continue;
        } else if (std.mem.eql(u8, arg, "--prompt")) {
            if (prompt != null) return error.DuplicatePrompt;

            const value = try command_args.nextValue(error.MissingPrompt);
            if (value.len == 0) return error.EmptyPrompt;
            if (value.len > api.max_generate_text_part_bytes) return error.PromptTooLong;
            prompt = value;
        } else if (std.mem.eql(u8, arg, "--ref")) {
            const value = try command_args.nextValue(error.MissingReference);
            if (base != null and reference_count >= references.len) return error.TooManyReferences;
            const reference = try parseReference(value);
            if (base == null) {
                if (reference.label != null) return error.LabeledBaseReference;
                base = reference.image;
                base_role = reference.role;
            } else {
                try addReference(&references, &reference_count, reference);
            }
        } else if (std.mem.eql(u8, arg, "--preserve")) {
            const value = try command_args.nextValue(error.MissingPreserve);
            if (value.len == 0) return error.EmptyPreserve;
            if (value.len > api.max_generate_text_part_bytes) return error.PreserveTooLong;
            try addConstraint(&preserves, &preserve_count, value);
        } else if (std.mem.eql(u8, arg, "--do-not")) {
            const value = try command_args.nextValue(error.MissingDoNot);
            if (value.len == 0) return error.EmptyDoNot;
            if (value.len > api.max_generate_text_part_bytes) return error.DoNotTooLong;
            try addConstraint(&do_nots, &do_not_count, value);
        } else {
            return error.UnknownFlag;
        }
    }

    const parsed_base = base orelse return error.MissingBase;
    try validateEditReferenceLimits(base_role, references[0..reference_count]);
    try validateGenerationOptionDependencies(generation_options);
    try validateBatchOptions(out_dir, batch_file, batch_key);

    const parsed_prompt = prompt orelse try fallbackPrompt(stdin_prompt);

    return .{
        .prompt = parsed_prompt,
        .output_options = output_options,
        .grounding_options = grounding_options,
        .thinking_options = thinking_options,
        .safety_options = safety_options,
        .generation_options = generation_options,
        .request_options = request_options,
        .out_dir = out_dir,
        .batch_file = batch_file,
        .batch_key = batch_key,
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

fn parseBatchOption(
    command_args: *CommandArgs,
    arg: []const u8,
    batch_file: *?[]const u8,
    batch_key: *?[]const u8,
) ParseError!bool {
    if (std.mem.eql(u8, arg, "--batch-file")) {
        if (batch_file.* != null) return error.DuplicateBatchFile;

        const value = try command_args.nextValue(error.MissingBatchFile);
        if (value.len == 0) return error.EmptyBatchFile;
        batch_file.* = value;
        return true;
    }

    if (std.mem.eql(u8, arg, "--batch-key")) {
        if (batch_key.* != null) return error.DuplicateBatchKey;

        const value = try command_args.nextValue(error.MissingBatchKey);
        if (value.len == 0) return error.EmptyBatchKey;
        batch_key.* = value;
        return true;
    }

    return false;
}

fn validateBatchOptions(
    out_dir: ?[]const u8,
    batch_file: ?[]const u8,
    batch_key: ?[]const u8,
) ParseError!void {
    if (batch_key != null and batch_file == null) return error.BatchKeyRequiresBatchFile;
    if (batch_file != null and out_dir != null) return error.BatchFileConflictsOutDir;
}

fn parseAspectRatioOption(command_args: *CommandArgs, output_options: *api.ImageOutputOptions) ParseError!void {
    if (output_options.aspect_ratio != null) return error.DuplicateAspectRatio;

    const value = try command_args.nextValue(error.MissingAspectRatio);
    if (value.len == 0) return error.EmptyAspectRatio;
    output_options.aspect_ratio = api.ImageAspectRatio.fromName(value) orelse return error.InvalidAspectRatio;
}

fn parseImageSizeOption(command_args: *CommandArgs, output_options: *api.ImageOutputOptions) ParseError!void {
    if (output_options.image_size != null) return error.DuplicateImageSize;

    const value = try command_args.nextValue(error.MissingImageSize);
    if (value.len == 0) return error.EmptyImageSize;
    output_options.image_size = api.ImageSize.fromName(value) orelse return error.InvalidImageSize;
}

fn parseGroundingOption(
    command_args: *CommandArgs,
    grounding_options: *api.GroundingOptions,
    grounding_seen: *bool,
) ParseError!void {
    if (grounding_seen.*) return error.DuplicateGrounding;

    const value = try command_args.nextValue(error.MissingGrounding);
    if (value.len == 0) return error.EmptyGrounding;
    grounding_options.* = api.GroundingOptions.fromName(value) orelse return error.InvalidGrounding;
    grounding_seen.* = true;
}

fn parseThinkingLevelOption(
    command_args: *CommandArgs,
    thinking_options: *api.ThinkingOptions,
) ParseError!void {
    if (thinking_options.level != null) return error.DuplicateThinkingLevel;

    const value = try command_args.nextValue(error.MissingThinkingLevel);
    if (value.len == 0) return error.EmptyThinkingLevel;
    thinking_options.level = api.ThinkingLevel.fromName(value) orelse return error.InvalidThinkingLevel;
}

fn parseIncludeThoughtsOption(
    thinking_options: *api.ThinkingOptions,
    include_thoughts_seen: *bool,
) ParseError!void {
    if (include_thoughts_seen.*) return error.DuplicateIncludeThoughts;

    thinking_options.include_thoughts = true;
    include_thoughts_seen.* = true;
}

fn parseSafetyOption(
    command_args: *CommandArgs,
    safety_options: *?api.SafetyOptions,
    safety_seen: *bool,
) ParseError!void {
    if (safety_seen.*) return error.DuplicateSafety;

    const value = try command_args.nextValue(error.MissingSafety);
    if (value.len == 0) return error.EmptySafety;
    safety_options.* = api.SafetyOptions.fromName(value) orelse return error.InvalidSafety;
    safety_seen.* = true;
}

fn parseRequestOption(
    command_args: *CommandArgs,
    arg: []const u8,
    request_options: *api.RequestOptions,
) ParseError!bool {
    if (std.mem.eql(u8, arg, "--system")) {
        if (request_options.system_instruction != null) return error.DuplicateSystem;

        const value = try command_args.nextValue(error.MissingSystem);
        if (value.len == 0) return error.EmptySystem;
        if (value.len > api.max_generate_text_part_bytes) return error.SystemTooLong;
        request_options.system_instruction = value;
        return true;
    }

    if (std.mem.eql(u8, arg, "--cached-content")) {
        if (request_options.cached_content != null) return error.DuplicateCachedContent;

        const value = try command_args.nextValue(error.MissingCachedContent);
        if (value.len == 0) return error.EmptyCachedContent;
        if (!api.isCanonicalCachedContentName(value)) return error.InvalidCachedContent;
        request_options.cached_content = value;
        return true;
    }

    if (std.mem.eql(u8, arg, "--service-tier")) {
        if (request_options.service_tier != null) return error.DuplicateServiceTier;

        const value = try command_args.nextValue(error.MissingServiceTier);
        if (value.len == 0) return error.EmptyServiceTier;
        request_options.service_tier = api.ServiceTier.fromName(value) orelse return error.InvalidServiceTier;
        return true;
    }

    if (std.mem.eql(u8, arg, "--store")) {
        if (request_options.store != null) return error.DuplicateStore;

        request_options.store = true;
        return true;
    }

    if (std.mem.eql(u8, arg, "--no-store")) {
        if (request_options.store != null) return error.DuplicateStore;

        request_options.store = false;
        return true;
    }

    return false;
}

fn parseGenerationOption(
    command_args: *CommandArgs,
    arg: []const u8,
    generation_options: *api.GenerationOptions,
    response_logprobs_seen: *bool,
) ParseError!bool {
    if (std.mem.eql(u8, arg, "--temperature")) {
        try parseFloatRangeOption(
            command_args,
            &generation_options.temperature,
            error.MissingTemperature,
            error.EmptyTemperature,
            error.DuplicateTemperature,
            error.InvalidTemperature,
            0.0,
            2.0,
            true,
        );
        return true;
    }

    if (std.mem.eql(u8, arg, "--top-p")) {
        try parseFloatRangeOption(
            command_args,
            &generation_options.top_p,
            error.MissingTopP,
            error.EmptyTopP,
            error.DuplicateTopP,
            error.InvalidTopP,
            0.0,
            1.0,
            true,
        );
        return true;
    }

    if (std.mem.eql(u8, arg, "--seed")) {
        if (generation_options.seed != null) return error.DuplicateSeed;

        const value = try command_args.nextValue(error.MissingSeed);
        if (value.len == 0) return error.EmptySeed;
        generation_options.seed = std.fmt.parseInt(i32, value, 10) catch return error.InvalidSeed;
        return true;
    }

    if (std.mem.eql(u8, arg, "--max-output-tokens")) {
        if (generation_options.max_output_tokens != null) return error.DuplicateMaxOutputTokens;

        const value = try command_args.nextValue(error.MissingMaxOutputTokens);
        if (value.len == 0) return error.EmptyMaxOutputTokens;
        const parsed = std.fmt.parseInt(u32, value, 10) catch return error.InvalidMaxOutputTokens;
        if (parsed < 1 or parsed > api.max_output_tokens) return error.InvalidMaxOutputTokens;
        generation_options.max_output_tokens = parsed;
        return true;
    }

    if (std.mem.eql(u8, arg, "--presence-penalty")) {
        try parseFloatRangeOption(
            command_args,
            &generation_options.presence_penalty,
            error.MissingPresencePenalty,
            error.EmptyPresencePenalty,
            error.DuplicatePresencePenalty,
            error.InvalidPresencePenalty,
            -2.0,
            2.0,
            false,
        );
        return true;
    }

    if (std.mem.eql(u8, arg, "--frequency-penalty")) {
        try parseFloatRangeOption(
            command_args,
            &generation_options.frequency_penalty,
            error.MissingFrequencyPenalty,
            error.EmptyFrequencyPenalty,
            error.DuplicateFrequencyPenalty,
            error.InvalidFrequencyPenalty,
            -2.0,
            2.0,
            false,
        );
        return true;
    }

    if (std.mem.eql(u8, arg, "--stop")) {
        try parseStopOption(command_args, generation_options);
        return true;
    }

    if (std.mem.eql(u8, arg, "--response-logprobs")) {
        if (response_logprobs_seen.*) return error.DuplicateResponseLogprobs;

        generation_options.response_logprobs = true;
        response_logprobs_seen.* = true;
        return true;
    }

    if (std.mem.eql(u8, arg, "--logprobs")) {
        if (generation_options.logprobs != null) return error.DuplicateLogprobs;

        const value = try command_args.nextValue(error.MissingLogprobs);
        if (value.len == 0) return error.EmptyLogprobs;
        const parsed = std.fmt.parseInt(u8, value, 10) catch return error.InvalidLogprobs;
        if (parsed < 1 or parsed > 20) return error.InvalidLogprobs;
        generation_options.logprobs = parsed;
        return true;
    }

    return false;
}

fn parseFloatRangeOption(
    command_args: *CommandArgs,
    target: *?f64,
    missing_error: ParseError,
    empty_error: ParseError,
    duplicate_error: ParseError,
    invalid_error: ParseError,
    min: f64,
    max: f64,
    max_inclusive: bool,
) ParseError!void {
    if (target.* != null) return duplicate_error;

    const value = try command_args.nextValue(missing_error);
    if (value.len == 0) return empty_error;
    const parsed = std.fmt.parseFloat(f64, value) catch return invalid_error;
    if (!std.math.isFinite(parsed)) return invalid_error;
    if (parsed < min) return invalid_error;
    if (max_inclusive) {
        if (parsed > max) return invalid_error;
    } else {
        if (parsed >= max) return invalid_error;
    }

    target.* = parsed;
}

fn parseStopOption(command_args: *CommandArgs, generation_options: *api.GenerationOptions) ParseError!void {
    const value = try command_args.nextValue(error.MissingStop);
    if (value.len == 0) return error.EmptyStop;
    if (generation_options.stop_sequence_count >= api.max_stop_sequences) return error.TooManyStops;

    for (generation_options.stopSequenceSlice()) |stop| {
        if (std.mem.eql(u8, stop, value)) return error.DuplicateStop;
    }

    generation_options.appendStopSequence(value);
}

fn validateGenerationOptionDependencies(generation_options: api.GenerationOptions) ParseError!void {
    if (generation_options.logprobs != null and !generation_options.response_logprobs) {
        return error.LogprobsRequiresResponseLogprobs;
    }
}

fn fallbackPrompt(stdin_prompt: ?[]const u8) ParseError![]const u8 {
    const prompt = stdin_prompt orelse return error.MissingPrompt;
    if (prompt.len == 0) return error.MissingPrompt;
    if (prompt.len > api.max_generate_text_part_bytes) return error.PromptTooLong;
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
        .mime = api.ImageMime.fromName(mime_name) orelse return error.InvalidMime,
    };
}

const ParsedReference = struct {
    role: api_edit.ReferenceRole,
    label: ?[]const u8,
    image: api_edit.UploadedImage,
};

fn parseReference(value: []const u8) ParseError!ParsedReference {
    if (value.len == 0) return error.EmptyReference;

    const equal = std.mem.indexOfScalar(u8, value, '=') orelse return error.InvalidReference;
    const role_and_label = value[0..equal];
    const image_value = value[equal + 1 ..];
    if (role_and_label.len == 0) return error.InvalidReference;

    const colon = std.mem.indexOfScalar(u8, role_and_label, ':');
    const role_name = if (colon) |index| role_and_label[0..index] else role_and_label;
    const label: ?[]const u8 = if (colon) |index| role_and_label[index + 1 ..] else null;

    const role = api_edit.ReferenceRole.fromName(role_name) orelse return error.InvalidReference;

    return .{
        .role = role,
        .label = label,
        .image = try parseImageInput(image_value, error.EmptyReference),
    };
}

fn addReference(
    references: *[api_edit.max_references]api_edit.Reference,
    reference_count: *usize,
    reference: ParsedReference,
) ParseError!void {
    if (reference_count.* >= references.len) return error.TooManyReferences;

    const label = if (reference.label) |custom_label| label: {
        if (!api_edit.isValidLabel(custom_label)) return error.InvalidLabel;
        break :label custom_label;
    } else try autoLabelForRole(reference.role, countReferencesWithRole(references[0..reference_count.*], reference.role));

    if (hasLabel(references[0..reference_count.*], label)) return error.DuplicateLabel;

    references[reference_count.*] = .{
        .role = reference.role,
        .label = label,
        .image = reference.image,
    };
    reference_count.* += 1;
}

fn addConstraint(
    constraints: *[max_edit_constraints][]const u8,
    constraint_count: *usize,
    value: []const u8,
) ParseError!void {
    if (constraint_count.* >= constraints.len) return error.TooManyConstraints;
    assert(value.len > 0);
    assert(value.len <= api.max_generate_text_part_bytes);

    constraints[constraint_count.*] = value;
    constraint_count.* += 1;
}

fn validateEditReferenceLimits(
    base_role: api_edit.ReferenceRole,
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
        .scene => &scene_labels,
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

const scene_labels = [_][]const u8{
    "SCENE_REFERENCE_A",
    "SCENE_REFERENCE_B",
    "SCENE_REFERENCE_C",
    "SCENE_REFERENCE_D",
    "SCENE_REFERENCE_E",
    "SCENE_REFERENCE_F",
    "SCENE_REFERENCE_G",
    "SCENE_REFERENCE_H",
    "SCENE_REFERENCE_I",
    "SCENE_REFERENCE_J",
    "SCENE_REFERENCE_K",
    "SCENE_REFERENCE_L",
    "SCENE_REFERENCE_M",
};

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

    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--out-dir")) {
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
    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--out-dir")) {
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

fn parseBatchSubmitCommand(command_args: *CommandArgs) ParseError!BatchSubmitCommand {
    var path: ?[]const u8 = null;
    var display_name: ?[]const u8 = null;

    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--out-dir")) {
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

    const input_path = path orelse return error.MissingPath;
    const effective_display_name = display_name orelse std.fs.path.basename(input_path);
    try validateDisplayName(effective_display_name);

    return .{
        .path = input_path,
        .display_name = effective_display_name,
    };
}

fn parseBatchStatusCommand(command_args: *CommandArgs) ParseError!BatchStatusCommand {
    return .{
        .name = try parseRequiredBatchName(command_args),
    };
}

fn parseBatchCancelCommand(command_args: *CommandArgs) ParseError!BatchCancelCommand {
    return .{
        .name = try parseRequiredBatchName(command_args),
    };
}

fn parseBatchDownloadCommand(command_args: *CommandArgs) ParseError!BatchDownloadCommand {
    var name: ?[]const u8 = null;
    var out_dir: ?[]const u8 = null;

    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--name")) {
            if (name != null) return error.DuplicateName;

            const value = try command_args.nextValue(error.MissingName);
            if (value.len == 0) return error.EmptyName;
            if (!api_batch.isCanonicalBatchName(value)) return error.InvalidBatchName;
            name = value;
        } else if (std.mem.eql(u8, arg, "--out-dir")) {
            if (out_dir != null) return error.DuplicateOutDir;

            const value = try command_args.nextValue(error.MissingOutDir);
            if (value.len == 0) return error.EmptyOutDir;
            out_dir = value;
        } else {
            return error.UnknownFlag;
        }
    }

    return .{
        .name = name orelse return error.MissingName,
        .out_dir = out_dir,
    };
}

fn parseRequiredBatchName(command_args: *CommandArgs) ParseError![]const u8 {
    var name: ?[]const u8 = null;
    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--out-dir")) {
            return error.OutDirUnsupported;
        } else if (std.mem.eql(u8, arg, "--name")) {
            if (name != null) return error.DuplicateName;

            const value = try command_args.nextValue(error.MissingName);
            if (value.len == 0) return error.EmptyName;
            if (!api_batch.isCanonicalBatchName(value)) return error.InvalidBatchName;
            name = value;
        } else {
            return error.UnknownFlag;
        }
    }

    return name orelse return error.MissingName;
}

fn parseBatchListCommand(command_args: *CommandArgs) ParseError!BatchListCommand {
    const arg = try command_args.nextOption() orelse return .{};
    if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

    return error.UnknownFlag;
}

fn parseRequiredFileName(command_args: *CommandArgs) ParseError![]const u8 {
    var name: ?[]const u8 = null;
    while (try command_args.nextOption()) |arg| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnexpectedArgument;

        if (std.mem.eql(u8, arg, "--out-dir")) {
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

fn writeGeneratedFiles(io: std.Io, out_dir: ?[]const u8, files: api.GeneratedFiles) !void {
    assert(files.items.len > 0);

    const output_dir = try openOutputDir(io, out_dir);
    defer output_dir.close(io);

    for (files.items) |file| {
        var name_buffer: [128]u8 = undefined;
        const name = try std.fmt.bufPrint(
            &name_buffer,
            "{s}-{d}-{d}.{s}",
            .{ files.response_id, file.candidate_index, file.part_index, file.mime.extension() },
        );
        try output_dir.dir.writeFile(io, .{
            .sub_path = name,
            .data = file.bytes,
            .flags = .{ .exclusive = true },
        });
    }
}

fn writeGenerationResult(
    io: std.Io,
    out_dir: ?[]const u8,
    result: client.GenerationResult,
) !void {
    assert(result.images.len > 0);

    const output_dir = try openOutputDir(io, out_dir);
    defer output_dir.close(io);

    for (result.images) |image| {
        var name_buffer: [128]u8 = undefined;
        const name = try generationResultFileName(&name_buffer, result.response_id, image);
        try output_dir.dir.writeFile(io, .{
            .sub_path = name,
            .data = image.bytes,
            .flags = .{ .exclusive = true },
        });
    }
}

fn generationResultFileName(
    buffer: []u8,
    response_id: []const u8,
    image: client.GeneratedImage,
) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{s}-{d}-{d}.{s}",
        .{
            response_id,
            image.candidate_position,
            image.part_position,
            generationOutputExtension(image.mime),
        },
    );
}

fn generationOutputExtension(mime: client.OutputMime) []const u8 {
    return switch (mime) {
        .png => "png",
        .jpeg => "jpg",
        .webp => "webp",
    };
}

const BatchOutputSummary = struct {
    written_files: [][]u8,
    existing_files: [][]u8,
    failed_keys: [][]u8,

    fn deinit(summary: *BatchOutputSummary, gpa: std.mem.Allocator) void {
        for (summary.written_files) |name| gpa.free(name);
        for (summary.existing_files) |name| gpa.free(name);
        for (summary.failed_keys) |key| gpa.free(key);
        gpa.free(summary.written_files);
        gpa.free(summary.existing_files);
        gpa.free(summary.failed_keys);
        summary.* = undefined;
    }
};

fn processBatchOutput(
    gpa: std.mem.Allocator,
    io: std.Io,
    out_dir: ?[]const u8,
    jsonl: []const u8,
) !BatchOutputSummary {
    _ = try api_batch.validateOutputJsonl(jsonl);

    const output_dir = try openOutputDir(io, out_dir);
    defer output_dir.close(io);

    var seen_keys = std.BufSet.init(gpa);
    defer seen_keys.deinit();

    var written_files: std.ArrayList([]u8) = .empty;
    errdefer {
        for (written_files.items) |name| gpa.free(name);
        written_files.deinit(gpa);
    }
    var existing_files: std.ArrayList([]u8) = .empty;
    errdefer {
        for (existing_files.items) |name| gpa.free(name);
        existing_files.deinit(gpa);
    }
    var failed_keys: std.ArrayList([]u8) = .empty;
    errdefer {
        for (failed_keys.items) |key| gpa.free(key);
        failed_keys.deinit(gpa);
    }

    var iterator = api_batch.OutputLineIterator{ .bytes = jsonl };
    var line_number: usize = 0;
    while (try iterator.next()) |line| {
        line_number += 1;
        try processBatchOutputLine(
            gpa,
            io,
            output_dir.dir,
            &seen_keys,
            &written_files,
            &existing_files,
            &failed_keys,
            line_number,
            line,
        );
    }

    const owned_written_files = try written_files.toOwnedSlice(gpa);
    errdefer {
        for (owned_written_files) |name| gpa.free(name);
        gpa.free(owned_written_files);
    }
    const owned_existing_files = try existing_files.toOwnedSlice(gpa);
    errdefer {
        for (owned_existing_files) |name| gpa.free(name);
        gpa.free(owned_existing_files);
    }
    const owned_failed_keys = try failed_keys.toOwnedSlice(gpa);
    return .{
        .written_files = owned_written_files,
        .existing_files = owned_existing_files,
        .failed_keys = owned_failed_keys,
    };
}

fn processBatchOutputLine(
    gpa: std.mem.Allocator,
    io: std.Io,
    output_dir: std.Io.Dir,
    seen_keys: *std.BufSet,
    written_files: *std.ArrayList([]u8),
    existing_files: *std.ArrayList([]u8),
    failed_keys: *std.ArrayList([]u8),
    line_number: usize,
    line: []const u8,
) !void {
    var record = api_batch.decodeOutputRecord(gpa, line) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {
            const line_key = try std.fmt.allocPrint(gpa, "line-{d}", .{line_number});
            errdefer gpa.free(line_key);
            try failed_keys.append(gpa, line_key);
            return;
        },
    };
    defer record.deinit(gpa);

    const safe_key = try api_batch.safeOutputKey(gpa, record.key);
    defer gpa.free(safe_key);

    if (seen_keys.contains(record.key)) {
        try appendFailedKey(gpa, failed_keys, safe_key);
        return;
    }
    try seen_keys.insert(record.key);

    const response_json = record.response_json orelse {
        try appendFailedKey(gpa, failed_keys, safe_key);
        return;
    };

    var files = api.decodeGeneratedFiles(gpa, response_json) catch {
        try appendFailedKey(gpa, failed_keys, safe_key);
        return;
    };
    defer files.deinit(gpa);

    try written_files.ensureUnusedCapacity(gpa, files.items.len);
    try existing_files.ensureUnusedCapacity(gpa, files.items.len);
    var record_failed = false;
    for (files.items) |file| {
        const name = try std.fmt.allocPrint(
            gpa,
            "{s}-{d}-{d}.{s}",
            .{ safe_key, file.candidate_index, file.part_index, file.mime.extension() },
        );
        errdefer gpa.free(name);

        output_dir.writeFile(io, .{
            .sub_path = name,
            .data = file.bytes,
            .flags = .{ .exclusive = true },
        }) catch |err| {
            switch (err) {
                error.PathAlreadyExists => {
                    existing_files.appendAssumeCapacity(name);
                    continue;
                },
                else => {
                    gpa.free(name);
                    record_failed = true;
                    continue;
                },
            }
        };
        written_files.appendAssumeCapacity(name);
    }

    if (record_failed) try appendFailedKey(gpa, failed_keys, safe_key);
}

fn appendFailedKey(
    gpa: std.mem.Allocator,
    failed_keys: *std.ArrayList([]u8),
    key: []const u8,
) !void {
    const owned_key = try gpa.dupe(u8, key);
    errdefer gpa.free(owned_key);
    try failed_keys.append(gpa, owned_key);
}

test "writeGeneratedFiles writes generated images under relative output directory" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp_dir.sub_path});
    defer gpa.free(out_dir);

    var items = [_]api.GeneratedFile{
        .{
            .candidate_index = 0,
            .part_index = 0,
            .mime = .png,
            .bytes = @constCast(&[_]u8{1}),
        },
    };
    const files = api.GeneratedFiles{
        .response_id = @constCast("test-response"),
        .items = &items,
    };

    try writeGeneratedFiles(std.testing.io, out_dir, files);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "test-response-0-0.png",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualSlices(u8, &.{1}, written);
}

test "generation CLI adapter maps every option and borrows stop sequences" {
    var generation_options = api.GenerationOptions{
        .max_output_tokens = 4096,
        .temperature = 0.7,
        .top_p = 0.95,
        .seed = -42,
        .presence_penalty = -1.5,
        .frequency_penalty = 1.25,
        .response_logprobs = true,
        .logprobs = 5,
    };
    generation_options.appendStopSequence("END");
    generation_options.appendStopSequence("STOP");
    const command = GenCommand{
        .prompt = "My fair lady",
        .output_options = .{ .aspect_ratio = .r16_9, .image_size = .k2 },
        .grounding_options = .{ .web = true, .image = true },
        .thinking_options = .{ .level = .high, .include_thoughts = true },
        .safety_options = .{ .threshold = .off },
        .generation_options = generation_options,
        .request_options = .{
            .system_instruction = "Use editorial lighting.",
            .cached_content = "cachedContents/brand",
            .service_tier = .priority,
            .store = false,
        },
    };

    const request = generationRequestFromCommand(&command);
    try std.testing.expectEqualStrings(command.prompt, request.prompt);
    try std.testing.expectEqual(client.ImageAspectRatio.r16_9, request.output_options.aspect_ratio.?);
    try std.testing.expectEqual(client.ImageSize.k2, request.output_options.image_size.?);
    try std.testing.expect(request.grounding_options.web);
    try std.testing.expect(request.grounding_options.image);
    try std.testing.expectEqual(client.ThinkingLevel.high, request.thinking_options.level.?);
    try std.testing.expect(request.thinking_options.include_thoughts);
    try std.testing.expectEqual(client.HarmBlockThreshold.off, request.safety_options.?.threshold);
    try std.testing.expectEqual(@as(?u32, 4096), request.generation_options.max_output_tokens);
    try std.testing.expectEqual(@as(?f64, 0.7), request.generation_options.temperature);
    try std.testing.expectEqual(@as(?f64, 0.95), request.generation_options.top_p);
    try std.testing.expectEqual(@as(?i32, -42), request.generation_options.seed);
    try std.testing.expectEqual(@as(?f64, -1.5), request.generation_options.presence_penalty);
    try std.testing.expectEqual(@as(?f64, 1.25), request.generation_options.frequency_penalty);
    try std.testing.expect(request.generation_options.response_logprobs);
    try std.testing.expectEqual(@as(?u8, 5), request.generation_options.logprobs);
    try std.testing.expectEqual(@as(usize, 2), request.generation_options.stop_sequences.len);
    try std.testing.expectEqual(
        command.generation_options.stopSequenceSlice().ptr,
        request.generation_options.stop_sequences.ptr,
    );
    try std.testing.expectEqualStrings("END", request.generation_options.stop_sequences[0]);
    try std.testing.expectEqualStrings("STOP", request.generation_options.stop_sequences[1]);
    try std.testing.expectEqualStrings(
        command.request_options.system_instruction.?,
        request.request_options.system_instruction.?,
    );
    try std.testing.expectEqualStrings(
        command.request_options.cached_content.?,
        request.request_options.cached_content.?,
    );
    try std.testing.expectEqual(client.ServiceTier.priority, request.request_options.service_tier.?);
    try std.testing.expectEqual(@as(?bool, false), request.request_options.store);
}

test "writeGenerationResult writes PNG JPEG and WebP names exclusively" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp_dir.sub_path});
    defer gpa.free(out_dir);
    var images = [_]client.GeneratedImage{
        .{ .candidate_position = 0, .part_position = 1, .mime = .png, .bytes = @constCast("png") },
        .{ .candidate_position = 2, .part_position = 3, .mime = .jpeg, .bytes = @constCast("jpeg") },
        .{ .candidate_position = 4, .part_position = 5, .mime = .webp, .bytes = @constCast("webp") },
    };
    const result = client.GenerationResult{
        .response_id = @constCast("response"),
        .images = &images,
        .reported_service_tier = null,
    };

    try writeGenerationResult(std.testing.io, out_dir, result);
    try std.testing.expectError(
        error.PathAlreadyExists,
        writeGenerationResult(std.testing.io, out_dir, result),
    );

    inline for (.{
        .{ "response-0-1.png", "png" },
        .{ "response-2-3.jpg", "jpeg" },
        .{ "response-4-5.webp", "webp" },
    }) |expected| {
        const written = try tmp_dir.dir.readFileAlloc(
            std.testing.io,
            expected[0],
            gpa,
            .limited(1024),
        );
        defer gpa.free(written);
        try std.testing.expectEqualStrings(expected[1], written);
    }
}

test "generation priority downgrade detection requires requested priority and reported standard" {
    const result = client.GenerationResult{
        .response_id = @constCast("response"),
        .images = &.{},
        .reported_service_tier = .standard,
    };
    try std.testing.expect(generationPriorityDowngraded(
        .{ .service_tier = .priority },
        result,
    ));
    try std.testing.expect(!generationPriorityDowngraded(
        .{ .service_tier = .standard },
        result,
    ));

    var absent = result;
    absent.reported_service_tier = null;
    try std.testing.expect(!generationPriorityDowngraded(
        .{ .service_tier = .priority },
        absent,
    ));
}

test "processBatchOutput writes valid images and reports malformed error and duplicate records" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp_dir.sub_path});
    defer gpa.free(out_dir);

    const jsonl =
        "not-json\n" ++
        "{\"key\":\"../hero\",\"response\":{\"responseId\":\"ignored\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}}\n" ++
        "{\"key\":\"failed\",\"error\":{\"code\":400,\"message\":\"bad request\"}}\n" ++
        "{\"key\":\"../hero\",\"response\":{\"responseId\":\"ignored-two\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"BAUG\"}}]}}]}}\n";

    var summary = try processBatchOutput(gpa, std.testing.io, out_dir, jsonl);
    defer summary.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), summary.written_files.len);
    try std.testing.expectEqualStrings("~2E~2E~2Fhero-0-0.png", summary.written_files[0]);
    try std.testing.expectEqual(@as(usize, 0), summary.existing_files.len);
    try std.testing.expectEqual(@as(usize, 3), summary.failed_keys.len);
    try std.testing.expectEqualStrings("line-1", summary.failed_keys[0]);
    try std.testing.expectEqualStrings("failed", summary.failed_keys[1]);
    try std.testing.expectEqualStrings("~2E~2E~2Fhero", summary.failed_keys[2]);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "~2E~2E~2Fhero-0-0.png",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, written);
}

test "processBatchOutput reports and preserves existing output files" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    try tmp_dir.dir.writeFile(std.testing.io, .{
        .sub_path = "hero-0-0.png",
        .data = "existing",
    });
    const out_dir = try std.fmt.allocPrint(gpa, ".zig-cache/tmp/{s}", .{tmp_dir.sub_path});
    defer gpa.free(out_dir);

    const jsonl =
        "{\"key\":\"hero\",\"response\":{\"responseId\":\"ignored\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}}\n";
    var summary = try processBatchOutput(gpa, std.testing.io, out_dir, jsonl);
    defer summary.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 0), summary.written_files.len);
    try std.testing.expectEqual(@as(usize, 1), summary.existing_files.len);
    try std.testing.expectEqualStrings("hero-0-0.png", summary.existing_files[0]);
    try std.testing.expectEqual(@as(usize, 0), summary.failed_keys.len);

    const written = try tmp_dir.dir.readFileAlloc(
        std.testing.io,
        "hero-0-0.png",
        gpa,
        .limited(1024),
    );
    defer gpa.free(written);
    try std.testing.expectEqualStrings("existing", written);
}

test "processBatchOutput rejects a missing output directory" {
    const gpa = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const out_dir = try std.fmt.allocPrint(
        gpa,
        ".zig-cache/tmp/{s}/missing",
        .{tmp_dir.sub_path},
    );
    defer gpa.free(out_dir);

    const jsonl =
        "{\"key\":\"hero\",\"response\":{\"responseId\":\"ignored\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}}\n";
    try std.testing.expectError(
        error.FileNotFound,
        processBatchOutput(gpa, std.testing.io, out_dir, jsonl),
    );
}

test "batch output diagnostics identify missing output directory and existing target path" {
    const gpa = std.testing.allocator;

    const missing_directory = try batchOutputProcessingDiagnostic(
        gpa,
        "missing",
        error.FileNotFound,
    );
    defer gpa.free(missing_directory);
    try std.testing.expectEqualStrings(
        "error: batch output directory does not exist\n",
        missing_directory,
    );

    const existing_file = try batchOutputExistingFileDiagnostic(
        gpa,
        "outputs",
        "hero-0-0.png",
    );
    defer gpa.free(existing_file);
    const expected_existing_file = "error: batch output file already exists and was not overwritten: outputs" ++
        std.fs.path.sep_str ++ "hero-0-0.png\n";
    try std.testing.expectEqualStrings(expected_existing_file, existing_file);
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

fn takeBatchPageOperations(
    gpa: std.mem.Allocator,
    operations: *std.ArrayList([]u8),
    page: *api_batch.ListPage,
) !void {
    try operations.ensureUnusedCapacity(gpa, page.operations.len);

    const page_operations = page.operations;
    for (page_operations) |operation| operations.appendAssumeCapacity(operation);
    page.operations = &.{};
    gpa.free(page_operations);
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
        error.MissingApiKey => std.debug.print("error: missing API key\n", .{}),
        error.EmptyApiKey => std.debug.print("error: API key must not be empty\n", .{}),
        error.DuplicateApiKey => std.debug.print("error: API key specified more than once\n", .{}),
        error.MissingFilesCommand => std.debug.print("error: missing files subcommand\n", .{}),
        error.UnknownFilesCommand => std.debug.print("error: unknown files subcommand\n", .{}),
        error.MissingBatchCommand => std.debug.print("error: missing batch subcommand\n", .{}),
        error.UnknownBatchCommand => std.debug.print("error: unknown batch subcommand\n", .{}),
        error.MissingPrompt => std.debug.print("error: missing prompt\n", .{}),
        error.EmptyPrompt => std.debug.print("error: prompt must not be empty\n", .{}),
        error.PromptTooLong => std.debug.print("error: prompt must be at most 16 KiB\n", .{}),
        error.SplitPrompt => std.debug.print("error: prompt must be one quoted argument\n", .{}),
        error.DuplicatePrompt => std.debug.print("error: prompt specified more than once\n", .{}),
        error.MissingBase => std.debug.print("error: missing base reference; the first --ref is the base image\n", .{}),
        error.LabeledBaseReference => std.debug.print("error: base reference must use BASE_IMAGE; omit LABEL on the first --ref\n", .{}),
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
        error.EmptyPreserve => std.debug.print("error: preserve text must not be empty\n", .{}),
        error.PreserveTooLong => std.debug.print("error: preserve text must be at most 16 KiB\n", .{}),
        error.MissingDoNot => std.debug.print("error: missing do-not text\n", .{}),
        error.EmptyDoNot => std.debug.print("error: do-not text must not be empty\n", .{}),
        error.DoNotTooLong => std.debug.print("error: do-not text must be at most 16 KiB\n", .{}),
        error.TooManyConstraints => std.debug.print("error: too many edit constraints\n", .{}),
        error.MissingPath => std.debug.print("error: missing input path\n", .{}),
        error.EmptyPath => std.debug.print("error: input path must not be empty\n", .{}),
        error.DuplicatePath => std.debug.print("error: input path specified more than once\n", .{}),
        error.MissingName => std.debug.print("error: missing resource name\n", .{}),
        error.EmptyName => std.debug.print("error: resource name must not be empty\n", .{}),
        error.DuplicateName => std.debug.print("error: resource name specified more than once\n", .{}),
        error.InvalidName => std.debug.print("error: file name must use canonical files/... form\n", .{}),
        error.InvalidBatchName => std.debug.print("error: batch name must use canonical batches/... form\n", .{}),
        error.MissingDisplayName => std.debug.print("error: missing display name\n", .{}),
        error.EmptyDisplayName => std.debug.print("error: display name must not be empty\n", .{}),
        error.DuplicateDisplayName => std.debug.print("error: display name specified more than once\n", .{}),
        error.InvalidDisplayNameUtf8 => std.debug.print("error: display name must be valid UTF-8\n", .{}),
        error.DisplayNameTooLong => std.debug.print("error: display name must be at most 512 Unicode code points\n", .{}),
        error.MissingAspectRatio => std.debug.print("error: missing aspect ratio\n", .{}),
        error.EmptyAspectRatio => std.debug.print("error: aspect ratio must not be empty\n", .{}),
        error.DuplicateAspectRatio => std.debug.print("error: aspect ratio specified more than once\n", .{}),
        error.InvalidAspectRatio => std.debug.print("error: aspect ratio must be one of 1:1, 1:4, 1:8, 2:3, 3:2, 3:4, 4:1, 4:3, 4:5, 5:4, 8:1, 9:16, 16:9, or 21:9\n", .{}),
        error.MissingImageSize => std.debug.print("error: missing image size\n", .{}),
        error.EmptyImageSize => std.debug.print("error: image size must not be empty\n", .{}),
        error.DuplicateImageSize => std.debug.print("error: image size specified more than once\n", .{}),
        error.InvalidImageSize => std.debug.print("error: image size must be 512, 1K, 2K, or 4K\n", .{}),
        error.MissingGrounding => std.debug.print("error: missing grounding mode\n", .{}),
        error.EmptyGrounding => std.debug.print("error: grounding mode must not be empty\n", .{}),
        error.DuplicateGrounding => std.debug.print("error: grounding mode specified more than once\n", .{}),
        error.InvalidGrounding => std.debug.print("error: grounding mode must be none, web, image, or web,image\n", .{}),
        error.MissingThinkingLevel => std.debug.print("error: missing thinking level\n", .{}),
        error.EmptyThinkingLevel => std.debug.print("error: thinking level must not be empty\n", .{}),
        error.DuplicateThinkingLevel => std.debug.print("error: thinking level specified more than once\n", .{}),
        error.InvalidThinkingLevel => std.debug.print("error: thinking level must be minimal or high\n", .{}),
        error.DuplicateIncludeThoughts => std.debug.print("error: include thoughts specified more than once\n", .{}),
        error.MissingSafety => std.debug.print("error: missing safety level\n", .{}),
        error.EmptySafety => std.debug.print("error: safety level must not be empty\n", .{}),
        error.DuplicateSafety => std.debug.print("error: safety level specified more than once\n", .{}),
        error.InvalidSafety => std.debug.print("error: safety level must be none, off, permissive, balanced, or strict\n", .{}),
        error.MissingTemperature => std.debug.print("error: missing temperature\n", .{}),
        error.EmptyTemperature => std.debug.print("error: temperature must not be empty\n", .{}),
        error.DuplicateTemperature => std.debug.print("error: temperature specified more than once\n", .{}),
        error.InvalidTemperature => std.debug.print("error: temperature must be a finite number from 0.0 to 2.0\n", .{}),
        error.MissingTopP => std.debug.print("error: missing top-p\n", .{}),
        error.EmptyTopP => std.debug.print("error: top-p must not be empty\n", .{}),
        error.DuplicateTopP => std.debug.print("error: top-p specified more than once\n", .{}),
        error.InvalidTopP => std.debug.print("error: top-p must be a finite number from 0.0 to 1.0\n", .{}),
        error.MissingSeed => std.debug.print("error: missing seed\n", .{}),
        error.EmptySeed => std.debug.print("error: seed must not be empty\n", .{}),
        error.DuplicateSeed => std.debug.print("error: seed specified more than once\n", .{}),
        error.InvalidSeed => std.debug.print("error: seed must be a signed 32-bit decimal integer\n", .{}),
        error.MissingMaxOutputTokens => std.debug.print("error: missing max output tokens\n", .{}),
        error.EmptyMaxOutputTokens => std.debug.print("error: max output tokens must not be empty\n", .{}),
        error.DuplicateMaxOutputTokens => std.debug.print("error: max output tokens specified more than once\n", .{}),
        error.InvalidMaxOutputTokens => std.debug.print("error: max output tokens must be an integer from 1 to 32768\n", .{}),
        error.MissingPresencePenalty => std.debug.print("error: missing presence penalty\n", .{}),
        error.EmptyPresencePenalty => std.debug.print("error: presence penalty must not be empty\n", .{}),
        error.DuplicatePresencePenalty => std.debug.print("error: presence penalty specified more than once\n", .{}),
        error.InvalidPresencePenalty => std.debug.print("error: presence penalty must be a finite number from -2.0 up to but not including 2.0\n", .{}),
        error.MissingFrequencyPenalty => std.debug.print("error: missing frequency penalty\n", .{}),
        error.EmptyFrequencyPenalty => std.debug.print("error: frequency penalty must not be empty\n", .{}),
        error.DuplicateFrequencyPenalty => std.debug.print("error: frequency penalty specified more than once\n", .{}),
        error.InvalidFrequencyPenalty => std.debug.print("error: frequency penalty must be a finite number from -2.0 up to but not including 2.0\n", .{}),
        error.MissingStop => std.debug.print("error: missing stop sequence\n", .{}),
        error.EmptyStop => std.debug.print("error: stop sequence must not be empty\n", .{}),
        error.TooManyStops => std.debug.print("error: at most 5 stop sequences are supported\n", .{}),
        error.DuplicateStop => std.debug.print("error: stop sequence specified more than once\n", .{}),
        error.DuplicateResponseLogprobs => std.debug.print("error: response logprobs specified more than once\n", .{}),
        error.MissingLogprobs => std.debug.print("error: missing logprobs count\n", .{}),
        error.EmptyLogprobs => std.debug.print("error: logprobs count must not be empty\n", .{}),
        error.DuplicateLogprobs => std.debug.print("error: logprobs count specified more than once\n", .{}),
        error.InvalidLogprobs => std.debug.print("error: logprobs count must be an integer from 1 to 20\n", .{}),
        error.LogprobsRequiresResponseLogprobs => std.debug.print("error: --logprobs requires --response-logprobs\n", .{}),
        error.MissingSystem => std.debug.print("error: missing system instruction\n", .{}),
        error.EmptySystem => std.debug.print("error: system instruction must not be empty\n", .{}),
        error.SystemTooLong => std.debug.print("error: system instruction must be at most 16 KiB\n", .{}),
        error.DuplicateSystem => std.debug.print("error: system instruction specified more than once\n", .{}),
        error.MissingCachedContent => std.debug.print("error: missing cached content name\n", .{}),
        error.EmptyCachedContent => std.debug.print("error: cached content name must not be empty\n", .{}),
        error.DuplicateCachedContent => std.debug.print("error: cached content specified more than once\n", .{}),
        error.InvalidCachedContent => std.debug.print("error: cached content name must use canonical cachedContents/... form\n", .{}),
        error.MissingServiceTier => std.debug.print("error: missing service tier\n", .{}),
        error.EmptyServiceTier => std.debug.print("error: service tier must not be empty\n", .{}),
        error.DuplicateServiceTier => std.debug.print("error: service tier specified more than once\n", .{}),
        error.InvalidServiceTier => std.debug.print("error: service tier must be flex, standard, or priority\n", .{}),
        error.DuplicateStore => std.debug.print("error: store option specified more than once\n", .{}),
        error.UnknownFlag => std.debug.print("error: unknown flag\n", .{}),
        error.UnexpectedArgument => std.debug.print("error: unexpected positional argument\n", .{}),
        error.MissingOutDir => std.debug.print("error: missing output directory\n", .{}),
        error.EmptyOutDir => std.debug.print("error: output directory must not be empty\n", .{}),
        error.DuplicateOutDir => std.debug.print("error: output directory specified more than once\n", .{}),
        error.OutDirUnsupported => std.debug.print("error: --out-dir is only supported for gen, edit, and batch download\n", .{}),
        error.MissingBatchFile => std.debug.print("error: missing batch file path\n", .{}),
        error.EmptyBatchFile => std.debug.print("error: batch file path must not be empty\n", .{}),
        error.DuplicateBatchFile => std.debug.print("error: batch file specified more than once\n", .{}),
        error.MissingBatchKey => std.debug.print("error: missing batch key\n", .{}),
        error.EmptyBatchKey => std.debug.print("error: batch key must not be empty\n", .{}),
        error.DuplicateBatchKey => std.debug.print("error: batch key specified more than once\n", .{}),
        error.BatchKeyRequiresBatchFile => std.debug.print("error: --batch-key requires --batch-file\n", .{}),
        error.BatchFileConflictsOutDir => std.debug.print("error: --batch-file cannot be combined with --out-dir\n", .{}),
    }
    std.debug.print("{s}", .{usageText()});
}

fn usageText() []const u8 {
    return "usage: nbimg gen [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] [--prompt \"PROMPT\"]\n" ++
        "       nbimg edit [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt \"PROMPT\"]\n" ++
        "       nbimg files upload [--api-key KEY] [--print-request] [--display-name NAME] --path PATH\n" ++
        "       nbimg files list [--api-key KEY] [--print-request]\n" ++
        "       nbimg files get [--api-key KEY] [--print-request] --name files/ID\n" ++
        "       nbimg files delete [--api-key KEY] [--print-request] --name files/ID\n" ++
        "       nbimg batch submit [--api-key KEY] [--print-request] [--display-name NAME] --path PATH\n" ++
        "       nbimg batch status [--api-key KEY] [--print-request] --name batches/ID\n" ++
        "       nbimg batch cancel [--api-key KEY] [--print-request] --name batches/ID\n" ++
        "       nbimg batch download [--api-key KEY] [--print-request] --name batches/ID [--out-dir DIR]\n" ++
        "       nbimg batch list [--api-key KEY] [--print-request]\n" ++
        "\n" ++
        "authentication options:\n" ++
        "       --api-key overrides GEMINI_API_KEY; otherwise GEMINI_API_KEY must be set and non-empty\n" ++
        "\n" ++
        "edit reference details:\n" ++
        "       first --ref is the BASE_IMAGE and must omit LABEL\n" ++
        "       later --ref ROLE[:LABEL]=files/ID,MIME references may include LABEL\n" ++
        "       valid ROLE values: scene|character|object|style|pose|composition|background|texture|image\n" ++
        "       omitted LABEL auto-assigns by role: SCENE_REFERENCE_A, CHARACTER_A, OBJECT_A, STYLE_REFERENCE_A, POSE_REFERENCE_A, COMPOSITION_REFERENCE_A, BACKGROUND_REFERENCE_A, TEXTURE_REFERENCE_A, IMAGE_REFERENCE_A\n" ++
        "       MIME must be image/jpeg, image/png, or image/webp\n" ++
        "\n" ++
        "output image options:\n" ++
        "       --aspect-ratio accepts 1:1, 1:4, 1:8, 2:3, 3:2, 3:4, 4:1, 4:3, 4:5, 5:4, 8:1, 9:16, 16:9, or 21:9\n" ++
        "       --image-size accepts 512, 1K, 2K, or 4K\n" ++
        "\n" ++
        "batch file options:\n" ++
        "       --batch-file validates with countTokens, then appends a Batch API JSONL request instead of generating\n" ++
        "       --batch-key sets the response-correlation key; otherwise nbimg derives one from the append offset\n" ++
        "       batch keys must be unique within the file; --batch-file cannot be combined with --out-dir\n" ++
        "       batch submit checks JSONL size and count, uploads JSONL, then creates exactly one non-idempotent Batch job\n" ++
        "       batch status performs one GET and requires the canonical batches/ID name\n" ++
        "       batch cancel requests best-effort cancellation and prints OK when Gemini accepts it\n" ++
        "       batch download checks status once, then writes successful output images without overwriting\n" ++
        "       batch list follows all pages of recent jobs and prints complete operation objects\n" ++
        "\n" ++
        "advanced generation options:\n" ++
        "       --temperature accepts 0.0 to 2.0\n" ++
        "       --top-p accepts 0.0 to 1.0\n" ++
        "       --seed accepts a signed 32-bit decimal integer\n" ++
        "       --max-output-tokens accepts 1 to 32768\n" ++
        "       --presence-penalty and --frequency-penalty accept -2.0 up to but not including 2.0\n" ++
        "       --stop accepts up to 5 non-empty unique stop sequences and may be repeated\n" ++
        "       --response-logprobs enables chosen-token log probability diagnostics\n" ++
        "       --logprobs accepts 1 to 20 and requires --response-logprobs\n" ++
        "\n" ++
        "request-level options:\n" ++
        "       --system sends a text-only Gemini systemInstruction\n" ++
        "       --cached-content requires canonical cachedContents/ID form\n" ++
        "       --service-tier accepts flex, standard, or priority\n" ++
        "       --store sends store:true; --no-store sends store:false; omit both to use project defaults\n" ++
        "\n" ++
        "grounding options:\n" ++
        "       --grounding accepts none, web, image, or web,image\n" ++
        "\n" ++
        "thinking options:\n" ++
        "       --thinking-level accepts minimal or high\n" ++
        "       --include-thoughts requests returned thought parts; thought parts stay in the response log only\n" ++
        "\n" ++
        "safety options:\n" ++
        "       --safety accepts none, off, permissive, balanced, or strict\n";
}

test "usageText documents edit reference roles and defaults" {
    const usage = usageText();
    const expected = [_][]const u8{
        "--api-key KEY",
        "--api-key overrides GEMINI_API_KEY",
        "--aspect-ratio RATIO",
        "--image-size SIZE",
        "--system TEXT",
        "--cached-content cachedContents/ID",
        "--service-tier TIER",
        "--store|--no-store",
        "--temperature FLOAT",
        "--top-p FLOAT",
        "--seed INT",
        "--max-output-tokens INT",
        "--presence-penalty FLOAT",
        "--frequency-penalty FLOAT",
        "--stop TEXT",
        "--response-logprobs",
        "--logprobs INT",
        "--grounding MODE",
        "--thinking-level LEVEL",
        "--include-thoughts",
        "--safety LEVEL",
        "--out-dir DIR",
        "--ref ROLE=files/ID,MIME",
        "nbimg batch cancel",
        "first --ref is the BASE_IMAGE and must omit LABEL",
        "later --ref ROLE[:LABEL]=files/ID,MIME references may include LABEL",
        "scene|character|object|style|pose|composition|background|texture|image",
        "SCENE_REFERENCE_A",
        "CHARACTER_A",
        "OBJECT_A",
        "STYLE_REFERENCE_A",
        "POSE_REFERENCE_A",
        "COMPOSITION_REFERENCE_A",
        "BACKGROUND_REFERENCE_A",
        "TEXTURE_REFERENCE_A",
        "IMAGE_REFERENCE_A",
        "image/jpeg, image/png, or image/webp",
        "1:1, 1:4, 1:8, 2:3, 3:2, 3:4, 4:1, 4:3, 4:5, 5:4, 8:1, 9:16, 16:9, or 21:9",
        "512, 1K, 2K, or 4K",
        "--batch-file validates with countTokens",
        "--batch-key sets the response-correlation key",
        "batch keys must be unique within the file",
        "nbimg batch submit",
        "nbimg batch status",
        "nbimg batch download",
        "nbimg batch list",
        "creates exactly one non-idempotent Batch job",
        "requires the canonical batches/ID name",
        "follows all pages of recent jobs",
        "0.0 to 2.0",
        "0.0 to 1.0",
        "signed 32-bit decimal integer",
        "1 to 32768",
        "-2.0 up to but not including 2.0",
        "up to 5 non-empty unique stop sequences",
        "chosen-token log probability diagnostics",
        "1 to 20 and requires --response-logprobs",
        "text-only Gemini systemInstruction",
        "canonical cachedContents/ID form",
        "flex, standard, or priority",
        "store:true",
        "store:false",
        "none, web, image, or web,image",
        "minimal or high",
        "thought parts stay in the response log only",
        "none, off, permissive, balanced, or strict",
    };

    for (expected) |needle| {
        try std.testing.expect(std.mem.indexOf(u8, usage, needle) != null);
    }
}

test "parseArgs accepts prompt flag" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed_command.api_key);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expectEqual(@as(?api.ImageAspectRatio, null), gen.output_options.aspect_ratio);
    try std.testing.expectEqual(@as(?api.ImageSize, null), gen.output_options.image_size);
    try std.testing.expect(!gen.grounding_options.hasAny());
    try std.testing.expect(!gen.thinking_options.hasAny());
    try std.testing.expectEqual(@as(?api.SafetyOptions, null), gen.safety_options);
    try std.testing.expect(!gen.generation_options.hasAny());
    try std.testing.expect(!gen.request_options.hasAny());
    try std.testing.expectEqual(@as(?[]const u8, null), gen.out_dir);
    try std.testing.expectEqual(@as(?[]const u8, null), gen.batch_file);
    try std.testing.expectEqual(@as(?[]const u8, null), gen.batch_key);
}

test "parseArgs accepts explicit prompts at max text bytes" {
    const max_prompt = "a" ** api.max_generate_text_part_bytes;

    const gen_command = try parseArgs(&.{ "nbimg", "gen", "--prompt", max_prompt });
    const gen = expectGenCommand(gen_command);
    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), gen.prompt.len);

    const edit_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        max_prompt,
    });
    const edit = expectEditCommand(edit_command);
    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), edit.prompt.len);
}

test "parseArgs accepts stdin fallback prompt for gen" {
    const parsed_command = try parseArgsWithPrompt(&.{ "nbimg", "gen" }, "My fair lady");
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
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
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts API key for all command families" {
    const gen_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--prompt",
        "My fair lady",
        "--api-key",
        "gen-key",
        "--print-request",
    });
    try std.testing.expectEqualStrings("gen-key", gen_command.api_key.?);
    try std.testing.expect(gen_command.traffic_log_options.print_request);

    const edit_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--api-key",
        "edit-key",
        "--ref",
        "scene=files/test,image/jpeg",
        "--prompt",
        "Change the style",
    });
    try std.testing.expectEqualStrings("edit-key", edit_command.api_key.?);

    const files_command = try parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--api-key",
        "files-key",
    });
    try std.testing.expectEqualStrings("files-key", files_command.api_key.?);

    const batch_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "status",
        "--name",
        "batches/test",
        "--api-key",
        "batch-key",
    });
    try std.testing.expectEqualStrings("batch-key", batch_command.api_key.?);
}

test "parseArgs rejects invalid API key arguments" {
    try std.testing.expectError(error.MissingApiKey, parseArgs(&.{
        "nbimg",
        "gen",
        "--api-key",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.EmptyApiKey, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--api-key",
        "",
    }));
    try std.testing.expectError(error.DuplicateApiKey, parseArgs(&.{
        "nbimg",
        "batch",
        "list",
        "--api-key",
        "one",
        "--api-key",
        "two",
    }));
}

test "resolveApiKey prefers explicit API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api.api_key_env_name, "environment-key");
    try std.testing.expectEqualStrings("argument-key", try resolveApiKey("argument-key", &environ_map));

    try environ_map.put(api.api_key_env_name, "");
    try std.testing.expectEqualStrings("argument-key", try resolveApiKey("argument-key", &environ_map));
}

test "resolveApiKey falls back to environment" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api.api_key_env_name, "environment-key");
    try std.testing.expectEqualStrings("environment-key", try resolveApiKey(null, &environ_map));

    try environ_map.put(api.api_key_env_name, "");
    try std.testing.expectError(error.EmptyApiKey, resolveApiKey(null, &environ_map));
}

test "resolveApiKey rejects missing or empty explicit API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try std.testing.expectError(error.MissingApiKey, resolveApiKey(null, &environ_map));
    try std.testing.expectError(error.EmptyApiKey, resolveApiKey("", &environ_map));
}

test "parseArgs accepts gen output directory" {
    const parsed_command = try parseArgs(&.{ "nbimg", "gen", "--out-dir", "outputs", "--prompt", "My fair lady" });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expectEqualStrings("outputs", gen.out_dir.?);
}

test "parseArgs accepts gen batch file options" {
    const automatic_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-file",
        "requests.jsonl",
        "--prompt",
        "My fair lady",
    });
    const automatic = expectGenCommand(automatic_command);
    try std.testing.expectEqualStrings("requests.jsonl", automatic.batch_file.?);
    try std.testing.expectEqual(@as(?[]const u8, null), automatic.batch_key);

    const explicit_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-key",
        "hero-001",
        "--batch-file",
        "requests.jsonl",
        "--prompt",
        "My fair lady",
    });
    const explicit = expectGenCommand(explicit_command);
    try std.testing.expectEqualStrings("requests.jsonl", explicit.batch_file.?);
    try std.testing.expectEqualStrings("hero-001", explicit.batch_key.?);
}

test "parseArgs rejects invalid gen batch file options" {
    try std.testing.expectError(error.MissingBatchFile, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-file",
    }));
    try std.testing.expectError(error.EmptyBatchFile, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-file",
        "",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.DuplicateBatchFile, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-file",
        "one.jsonl",
        "--batch-file",
        "two.jsonl",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.MissingBatchKey, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-key",
    }));
    try std.testing.expectError(error.EmptyBatchKey, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-key",
        "",
        "--batch-file",
        "requests.jsonl",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.DuplicateBatchKey, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-key",
        "one",
        "--batch-key",
        "two",
        "--batch-file",
        "requests.jsonl",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.BatchKeyRequiresBatchFile, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-key",
        "hero-001",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.BatchFileConflictsOutDir, parseArgs(&.{
        "nbimg",
        "gen",
        "--batch-file",
        "requests.jsonl",
        "--out-dir",
        "outputs",
        "--prompt",
        "My fair lady",
    }));
}

test "parseArgs accepts gen image output options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--aspect-ratio",
        "16:9",
        "--image-size",
        "2K",
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expectEqual(api.ImageAspectRatio.r16_9, gen.output_options.aspect_ratio.?);
    try std.testing.expectEqual(api.ImageSize.k2, gen.output_options.image_size.?);
}

test "parseArgs accepts partial gen image output options" {
    const aspect_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--aspect-ratio",
        "9:16",
        "--prompt",
        "My fair lady",
    });
    const aspect_gen = expectGenCommand(aspect_command);
    try std.testing.expectEqual(api.ImageAspectRatio.r9_16, aspect_gen.output_options.aspect_ratio.?);
    try std.testing.expectEqual(@as(?api.ImageSize, null), aspect_gen.output_options.image_size);

    const size_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--image-size",
        "512",
        "--prompt",
        "My fair lady",
    });
    const size_gen = expectGenCommand(size_command);
    try std.testing.expectEqual(@as(?api.ImageAspectRatio, null), size_gen.output_options.aspect_ratio);
    try std.testing.expectEqual(api.ImageSize.px512, size_gen.output_options.image_size.?);
}

test "parseArgs accepts gen grounding modes" {
    const web_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--grounding",
        "web",
        "--prompt",
        "My fair lady",
    });
    const web_gen = expectGenCommand(web_command);
    try std.testing.expect(web_gen.grounding_options.web);
    try std.testing.expect(!web_gen.grounding_options.image);

    const image_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--grounding",
        "image",
        "--prompt",
        "My fair lady",
    });
    const image_gen = expectGenCommand(image_command);
    try std.testing.expect(!image_gen.grounding_options.web);
    try std.testing.expect(image_gen.grounding_options.image);

    const combined_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--grounding",
        "web,image",
        "--prompt",
        "My fair lady",
    });
    const combined_gen = expectGenCommand(combined_command);
    try std.testing.expect(combined_gen.grounding_options.web);
    try std.testing.expect(combined_gen.grounding_options.image);

    const none_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--grounding",
        "none",
        "--prompt",
        "My fair lady",
    });
    const none_gen = expectGenCommand(none_command);
    try std.testing.expect(!none_gen.grounding_options.hasAny());
}

test "parseArgs accepts gen thinking options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--thinking-level",
        "high",
        "--include-thoughts",
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expectEqual(api.ThinkingLevel.high, gen.thinking_options.level.?);
    try std.testing.expect(gen.thinking_options.include_thoughts);
}

test "parseArgs accepts gen safety options" {
    const none_command = try parseArgs(&.{ "nbimg", "gen", "--safety", "none", "--prompt", "My fair lady" });
    try std.testing.expectEqual(api.HarmBlockThreshold.block_none, expectGenCommand(none_command).safety_options.?.threshold);

    const off_command = try parseArgs(&.{ "nbimg", "gen", "--safety", "off", "--prompt", "My fair lady" });
    try std.testing.expectEqual(api.HarmBlockThreshold.off, expectGenCommand(off_command).safety_options.?.threshold);

    const permissive_command = try parseArgs(&.{ "nbimg", "gen", "--safety", "permissive", "--prompt", "My fair lady" });
    try std.testing.expectEqual(api.HarmBlockThreshold.block_only_high, expectGenCommand(permissive_command).safety_options.?.threshold);

    const balanced_command = try parseArgs(&.{ "nbimg", "gen", "--safety", "balanced", "--prompt", "My fair lady" });
    try std.testing.expectEqual(api.HarmBlockThreshold.block_medium_and_above, expectGenCommand(balanced_command).safety_options.?.threshold);

    const strict_command = try parseArgs(&.{ "nbimg", "gen", "--safety", "strict", "--prompt", "My fair lady" });
    try std.testing.expectEqual(api.HarmBlockThreshold.block_low_and_above, expectGenCommand(strict_command).safety_options.?.threshold);
}

test "parseArgs accepts print request flag in any order" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--prompt",
        "My fair lady",
        "--print-request",
    });
    const gen = expectGenCommand(parsed_command);
    try std.testing.expectEqualStrings("My fair lady", gen.prompt);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
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

test "parseArgs rejects invalid gen image output option arguments" {
    try std.testing.expectError(error.MissingAspectRatio, parseArgs(&.{ "nbimg", "gen", "--aspect-ratio" }));
    try std.testing.expectError(error.MissingAspectRatio, parseArgs(&.{ "nbimg", "gen", "--aspect-ratio", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyAspectRatio, parseArgs(&.{ "nbimg", "gen", "--aspect-ratio", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateAspectRatio, parseArgs(&.{
        "nbimg",
        "gen",
        "--aspect-ratio",
        "1:1",
        "--aspect-ratio",
        "16:9",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.InvalidAspectRatio, parseArgs(&.{ "nbimg", "gen", "--aspect-ratio", "10:10", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidAspectRatio, parseArgs(&.{ "nbimg", "gen", "--aspect-ratio", "1920x1080", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size" }));
    try std.testing.expectError(error.MissingImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateImageSize, parseArgs(&.{
        "nbimg",
        "gen",
        "--image-size",
        "1K",
        "--image-size",
        "2K",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.InvalidImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size", "1k", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size", "0.5K", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidImageSize, parseArgs(&.{ "nbimg", "gen", "--image-size", "1024x1024", "--prompt", "My fair lady" }));
}

test "parseArgs rejects invalid gen grounding arguments" {
    try std.testing.expectError(error.MissingGrounding, parseArgs(&.{ "nbimg", "gen", "--grounding" }));
    try std.testing.expectError(error.MissingGrounding, parseArgs(&.{ "nbimg", "gen", "--grounding", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyGrounding, parseArgs(&.{ "nbimg", "gen", "--grounding", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateGrounding, parseArgs(&.{
        "nbimg",
        "gen",
        "--grounding",
        "web",
        "--grounding",
        "image",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.InvalidGrounding, parseArgs(&.{ "nbimg", "gen", "--grounding", "search", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidGrounding, parseArgs(&.{ "nbimg", "gen", "--grounding", "image,web", "--prompt", "My fair lady" }));
}

test "parseArgs rejects invalid gen thinking arguments" {
    try std.testing.expectError(error.MissingThinkingLevel, parseArgs(&.{ "nbimg", "gen", "--thinking-level" }));
    try std.testing.expectError(error.MissingThinkingLevel, parseArgs(&.{ "nbimg", "gen", "--thinking-level", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyThinkingLevel, parseArgs(&.{ "nbimg", "gen", "--thinking-level", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateThinkingLevel, parseArgs(&.{
        "nbimg",
        "gen",
        "--thinking-level",
        "minimal",
        "--thinking-level",
        "high",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.InvalidThinkingLevel, parseArgs(&.{ "nbimg", "gen", "--thinking-level", "low", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateIncludeThoughts, parseArgs(&.{
        "nbimg",
        "gen",
        "--include-thoughts",
        "--include-thoughts",
        "--prompt",
        "My fair lady",
    }));
}

test "parseArgs rejects invalid gen safety arguments" {
    try std.testing.expectError(error.MissingSafety, parseArgs(&.{ "nbimg", "gen", "--safety" }));
    try std.testing.expectError(error.MissingSafety, parseArgs(&.{ "nbimg", "gen", "--safety", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptySafety, parseArgs(&.{ "nbimg", "gen", "--safety", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateSafety, parseArgs(&.{
        "nbimg",
        "gen",
        "--safety",
        "none",
        "--safety",
        "strict",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.InvalidSafety, parseArgs(&.{ "nbimg", "gen", "--safety", "block-none", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidSafety, parseArgs(&.{ "nbimg", "gen", "--safety", "high", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidSafety, parseArgs(&.{ "nbimg", "gen", "--safety", "medium", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidSafety, parseArgs(&.{ "nbimg", "gen", "--safety", "low", "--prompt", "My fair lady" }));
}

test "parseArgs accepts gen advanced generation options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--temperature",
        "0.7",
        "--top-p",
        "0.95",
        "--seed",
        "-42",
        "--max-output-tokens",
        "4096",
        "--presence-penalty",
        "-1.5",
        "--frequency-penalty",
        "1.999",
        "--stop",
        "END",
        "--stop",
        "STOP",
        "--response-logprobs",
        "--logprobs",
        "5",
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);
    const options = gen.generation_options;

    try std.testing.expectApproxEqAbs(@as(f64, 0.7), options.temperature.?, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.95), options.top_p.?, 0.000001);
    try std.testing.expectEqual(@as(i32, -42), options.seed.?);
    try std.testing.expectEqual(@as(u32, 4096), options.max_output_tokens.?);
    try std.testing.expectApproxEqAbs(@as(f64, -1.5), options.presence_penalty.?, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 1.999), options.frequency_penalty.?, 0.000001);
    try std.testing.expect(options.response_logprobs);
    try std.testing.expectEqual(@as(u8, 5), options.logprobs.?);
    try std.testing.expectEqual(@as(usize, 2), options.stop_sequence_count);
    try std.testing.expectEqualStrings("END", options.stopSequenceSlice()[0]);
    try std.testing.expectEqualStrings("STOP", options.stopSequenceSlice()[1]);
}

test "parseArgs accepts response logprobs without top candidate logprobs" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--response-logprobs",
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expect(gen.generation_options.response_logprobs);
    try std.testing.expectEqual(@as(?u8, null), gen.generation_options.logprobs);
}

test "parseArgs accepts gen request-level controls" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--system",
        "Use editorial lighting.",
        "--cached-content",
        "cachedContents/brand",
        "--service-tier",
        "priority",
        "--no-store",
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);
    const options = gen.request_options;

    try std.testing.expectEqualStrings("Use editorial lighting.", options.system_instruction.?);
    try std.testing.expectEqualStrings("cachedContents/brand", options.cached_content.?);
    try std.testing.expectEqual(api.ServiceTier.priority, options.service_tier.?);
    try std.testing.expectEqual(false, options.store.?);
}

test "parseArgs accepts system instruction at max text bytes" {
    const max_system = "s" ** api.max_generate_text_part_bytes;
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--system",
        max_system,
        "--prompt",
        "My fair lady",
    });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), gen.request_options.system_instruction.?.len);
}

test "parseArgs accepts edit request-level controls" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--system",
        "Preserve subject identity.",
        "--cached-content",
        "cachedContents/edit-context",
        "--service-tier",
        "flex",
        "--store",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);
    const options = edit.request_options;

    try std.testing.expectEqualStrings("Preserve subject identity.", options.system_instruction.?);
    try std.testing.expectEqualStrings("cachedContents/edit-context", options.cached_content.?);
    try std.testing.expectEqual(api.ServiceTier.flex, options.service_tier.?);
    try std.testing.expectEqual(true, options.store.?);
}

test "parseArgs rejects invalid request-level controls" {
    try std.testing.expectError(error.MissingSystem, parseArgs(&.{ "nbimg", "gen", "--system" }));
    try std.testing.expectError(error.MissingSystem, parseArgs(&.{ "nbimg", "gen", "--system", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptySystem, parseArgs(&.{ "nbimg", "gen", "--system", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.SystemTooLong, parseArgs(&.{ "nbimg", "gen", "--system", "s" ** (api.max_generate_text_part_bytes + 1), "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateSystem, parseArgs(&.{ "nbimg", "gen", "--system", "one", "--system", "two", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingCachedContent, parseArgs(&.{ "nbimg", "gen", "--cached-content" }));
    try std.testing.expectError(error.EmptyCachedContent, parseArgs(&.{ "nbimg", "gen", "--cached-content", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidCachedContent, parseArgs(&.{ "nbimg", "gen", "--cached-content", "brand", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidCachedContent, parseArgs(&.{ "nbimg", "gen", "--cached-content", "cachedContents/", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateCachedContent, parseArgs(&.{ "nbimg", "gen", "--cached-content", "cachedContents/one", "--cached-content", "cachedContents/two", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingServiceTier, parseArgs(&.{ "nbimg", "gen", "--service-tier" }));
    try std.testing.expectError(error.EmptyServiceTier, parseArgs(&.{ "nbimg", "gen", "--service-tier", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidServiceTier, parseArgs(&.{ "nbimg", "gen", "--service-tier", "unspecified", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateServiceTier, parseArgs(&.{ "nbimg", "gen", "--service-tier", "standard", "--service-tier", "priority", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.DuplicateStore, parseArgs(&.{ "nbimg", "gen", "--store", "--store", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateStore, parseArgs(&.{ "nbimg", "gen", "--store", "--no-store", "--prompt", "My fair lady" }));
}

test "parseArgs accepts advanced generation options in any order" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "gen",
        "--logprobs",
        "1",
        "--prompt",
        "My fair lady",
        "--response-logprobs",
        "--stop",
        "END",
    });
    const gen = expectGenCommand(parsed_command);

    try std.testing.expect(gen.generation_options.response_logprobs);
    try std.testing.expectEqual(@as(u8, 1), gen.generation_options.logprobs.?);
    try std.testing.expectEqualStrings("END", gen.generation_options.stopSequenceSlice()[0]);
}

test "parseArgs rejects invalid gen advanced generation arguments" {
    try std.testing.expectError(error.MissingTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature" }));
    try std.testing.expectError(error.MissingTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.EmptyTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "1", "--temperature", "2", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "-0.1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "2.1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidTemperature, parseArgs(&.{ "nbimg", "gen", "--temperature", "nan", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingTopP, parseArgs(&.{ "nbimg", "gen", "--top-p" }));
    try std.testing.expectError(error.EmptyTopP, parseArgs(&.{ "nbimg", "gen", "--top-p", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateTopP, parseArgs(&.{ "nbimg", "gen", "--top-p", "0.5", "--top-p", "1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidTopP, parseArgs(&.{ "nbimg", "gen", "--top-p", "-0.1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidTopP, parseArgs(&.{ "nbimg", "gen", "--top-p", "1.1", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingSeed, parseArgs(&.{ "nbimg", "gen", "--seed" }));
    try std.testing.expectError(error.EmptySeed, parseArgs(&.{ "nbimg", "gen", "--seed", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateSeed, parseArgs(&.{ "nbimg", "gen", "--seed", "1", "--seed", "2", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidSeed, parseArgs(&.{ "nbimg", "gen", "--seed", "2147483648", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidSeed, parseArgs(&.{ "nbimg", "gen", "--seed", "1.5", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingMaxOutputTokens, parseArgs(&.{ "nbimg", "gen", "--max-output-tokens" }));
    try std.testing.expectError(error.EmptyMaxOutputTokens, parseArgs(&.{ "nbimg", "gen", "--max-output-tokens", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateMaxOutputTokens, parseArgs(&.{ "nbimg", "gen", "--max-output-tokens", "1", "--max-output-tokens", "2", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidMaxOutputTokens, parseArgs(&.{ "nbimg", "gen", "--max-output-tokens", "0", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidMaxOutputTokens, parseArgs(&.{ "nbimg", "gen", "--max-output-tokens", "32769", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingPresencePenalty, parseArgs(&.{ "nbimg", "gen", "--presence-penalty" }));
    try std.testing.expectError(error.EmptyPresencePenalty, parseArgs(&.{ "nbimg", "gen", "--presence-penalty", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicatePresencePenalty, parseArgs(&.{ "nbimg", "gen", "--presence-penalty", "0", "--presence-penalty", "1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidPresencePenalty, parseArgs(&.{ "nbimg", "gen", "--presence-penalty", "-2.1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidPresencePenalty, parseArgs(&.{ "nbimg", "gen", "--presence-penalty", "2", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingFrequencyPenalty, parseArgs(&.{ "nbimg", "gen", "--frequency-penalty" }));
    try std.testing.expectError(error.EmptyFrequencyPenalty, parseArgs(&.{ "nbimg", "gen", "--frequency-penalty", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateFrequencyPenalty, parseArgs(&.{ "nbimg", "gen", "--frequency-penalty", "0", "--frequency-penalty", "1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidFrequencyPenalty, parseArgs(&.{ "nbimg", "gen", "--frequency-penalty", "-2.1", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidFrequencyPenalty, parseArgs(&.{ "nbimg", "gen", "--frequency-penalty", "2", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.MissingStop, parseArgs(&.{ "nbimg", "gen", "--stop" }));
    try std.testing.expectError(error.EmptyStop, parseArgs(&.{ "nbimg", "gen", "--stop", "", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateStop, parseArgs(&.{ "nbimg", "gen", "--stop", "END", "--stop", "END", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.TooManyStops, parseArgs(&.{ "nbimg", "gen", "--stop", "1", "--stop", "2", "--stop", "3", "--stop", "4", "--stop", "5", "--stop", "6", "--prompt", "My fair lady" }));

    try std.testing.expectError(error.DuplicateResponseLogprobs, parseArgs(&.{ "nbimg", "gen", "--response-logprobs", "--response-logprobs", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.MissingLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs" }));
    try std.testing.expectError(error.EmptyLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs", "", "--response-logprobs", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.DuplicateLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs", "1", "--logprobs", "2", "--response-logprobs", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs", "0", "--response-logprobs", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.InvalidLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs", "21", "--response-logprobs", "--prompt", "My fair lady" }));
    try std.testing.expectError(error.LogprobsRequiresResponseLogprobs, parseArgs(&.{ "nbimg", "gen", "--logprobs", "1", "--prompt", "My fair lady" }));
}

test "parseArgs accepts minimal edit command" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("change visual style to Broadway musical", edit.prompt);
    try std.testing.expectEqualStrings("files/tjtj5me9i96c", edit.base.name);
    try std.testing.expectEqual(api.ImageMime.jpeg, edit.base.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.scene, edit.base_role);
    try std.testing.expectEqual(@as(usize, 0), edit.reference_count);
    try std.testing.expectEqual(@as(usize, 0), edit.preserve_count);
    try std.testing.expectEqual(@as(usize, 0), edit.do_not_count);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expectEqual(@as(?api.ImageAspectRatio, null), edit.output_options.aspect_ratio);
    try std.testing.expectEqual(@as(?api.ImageSize, null), edit.output_options.image_size);
    try std.testing.expect(!edit.grounding_options.hasAny());
    try std.testing.expect(!edit.thinking_options.hasAny());
    try std.testing.expectEqual(@as(?api.SafetyOptions, null), edit.safety_options);
    try std.testing.expect(!edit.generation_options.hasAny());
    try std.testing.expect(!edit.request_options.hasAny());
    try std.testing.expectEqual(@as(?[]const u8, null), edit.out_dir);
    try std.testing.expectEqual(@as(?[]const u8, null), edit.batch_file);
    try std.testing.expectEqual(@as(?[]const u8, null), edit.batch_key);
}

test "parseArgs accepts edit output directory" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--out-dir",
        "outputs",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("outputs", edit.out_dir.?);
}

test "parseArgs accepts edit batch file options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--batch-file",
        "requests.jsonl",
        "--batch-key",
        "edit-001",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("requests.jsonl", edit.batch_file.?);
    try std.testing.expectEqualStrings("edit-001", edit.batch_key.?);
}

test "parseArgs rejects edit batch file with output directory" {
    try std.testing.expectError(error.BatchFileConflictsOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--out-dir",
        "outputs",
        "--batch-file",
        "requests.jsonl",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs accepts edit image output options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--aspect-ratio",
        "4:5",
        "--image-size",
        "4K",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(api.ImageAspectRatio.r4_5, edit.output_options.aspect_ratio.?);
    try std.testing.expectEqual(api.ImageSize.k4, edit.output_options.image_size.?);
}

test "parseArgs accepts edit grounding modes" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--grounding",
        "web,image",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expect(edit.grounding_options.web);
    try std.testing.expect(edit.grounding_options.image);
}

test "parseArgs accepts edit thinking options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--thinking-level",
        "minimal",
        "--include-thoughts",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(api.ThinkingLevel.minimal, edit.thinking_options.level.?);
    try std.testing.expect(edit.thinking_options.include_thoughts);
}

test "parseArgs accepts edit safety options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--safety",
        "strict",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(api.HarmBlockThreshold.block_low_and_above, edit.safety_options.?.threshold);
}

test "parseArgs accepts edit advanced generation options" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--temperature",
        "2",
        "--top-p",
        "0",
        "--seed",
        "42",
        "--max-output-tokens",
        "32768",
        "--presence-penalty",
        "-2",
        "--frequency-penalty",
        "0",
        "--stop",
        "END",
        "--response-logprobs",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);
    const options = edit.generation_options;

    try std.testing.expectApproxEqAbs(@as(f64, 2.0), options.temperature.?, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), options.top_p.?, 0.000001);
    try std.testing.expectEqual(@as(i32, 42), options.seed.?);
    try std.testing.expectEqual(@as(u32, api.max_output_tokens), options.max_output_tokens.?);
    try std.testing.expectApproxEqAbs(@as(f64, -2.0), options.presence_penalty.?, 0.000001);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), options.frequency_penalty.?, 0.000001);
    try std.testing.expect(options.response_logprobs);
    try std.testing.expectEqual(@as(?u8, null), options.logprobs);
    try std.testing.expectEqualStrings("END", options.stopSequenceSlice()[0]);
}

test "parseArgs rejects invalid edit grounding arguments" {
    try std.testing.expectError(error.MissingGrounding, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--grounding",
    }));
    try std.testing.expectError(error.InvalidGrounding, parseArgs(&.{
        "nbimg",
        "edit",
        "--grounding",
        "image,web",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.DuplicateGrounding, parseArgs(&.{
        "nbimg",
        "edit",
        "--grounding",
        "web",
        "--grounding",
        "image",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects invalid edit thinking arguments" {
    try std.testing.expectError(error.MissingThinkingLevel, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--thinking-level",
    }));
    try std.testing.expectError(error.InvalidThinkingLevel, parseArgs(&.{
        "nbimg",
        "edit",
        "--thinking-level",
        "medium",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.DuplicateIncludeThoughts, parseArgs(&.{
        "nbimg",
        "edit",
        "--include-thoughts",
        "--include-thoughts",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects invalid edit safety arguments" {
    try std.testing.expectError(error.MissingSafety, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--safety",
    }));
    try std.testing.expectError(error.InvalidSafety, parseArgs(&.{
        "nbimg",
        "edit",
        "--safety",
        "high",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.DuplicateSafety, parseArgs(&.{
        "nbimg",
        "edit",
        "--safety",
        "balanced",
        "--safety",
        "strict",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects invalid edit output directory arguments" {
    try std.testing.expectError(error.MissingOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--out-dir",
    }));
    try std.testing.expectError(error.EmptyOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--out-dir",
        "",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.DuplicateOutDir, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
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
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
    }, "change visual style to Broadway musical");
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("change visual style to Broadway musical", edit.prompt);
    try std.testing.expectEqualStrings("files/tjtj5me9i96c", edit.base.name);
    try std.testing.expectEqual(api.ImageMime.jpeg, edit.base.mime);
}

test "parseArgs accepts edit base reference role constraints and request log flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--print-request",
        "--ref",
        "character=files/tjtj5me9i96c,image/jpeg",
        "--preserve",
        "preserve her facial identity",
        "--do-not",
        "do not change the crop",
        "--prompt",
        "change visual style to Broadway musical",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
    try std.testing.expectEqual(@as(?[]const u8, null), edit.out_dir);
    try std.testing.expectEqual(api_edit.ReferenceRole.character, edit.base_role);
    try std.testing.expectEqual(@as(usize, 1), edit.preserve_count);
    try std.testing.expectEqualStrings("preserve her facial identity", edit.preserves[0]);
    try std.testing.expectEqual(@as(usize, 1), edit.do_not_count);
    try std.testing.expectEqualStrings("do not change the crop", edit.do_nots[0]);
}

test "parseArgs accepts first ref as base and later generic references" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--ref",
        "character=files/person,image/jpeg",
        "--ref",
        "object:OBJECT_PRODUCT=files/product,image/png",
        "--ref",
        "style=files/style,image/webp",
        "--ref",
        "pose:POSE_MAIN=files/pose,image/jpeg",
        "--prompt",
        "edit BASE_IMAGE using references",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("files/base", edit.base.name);
    try std.testing.expectEqual(api_edit.ReferenceRole.scene, edit.base_role);
    try std.testing.expectEqual(@as(usize, 4), edit.reference_count);
    try std.testing.expectEqual(api_edit.ReferenceRole.character, edit.references[0].role);
    try std.testing.expectEqualStrings("CHARACTER_A", edit.references[0].label);
    try std.testing.expectEqualStrings("files/person", edit.references[0].image.name);
    try std.testing.expectEqual(api.ImageMime.jpeg, edit.references[0].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.object, edit.references[1].role);
    try std.testing.expectEqualStrings("OBJECT_PRODUCT", edit.references[1].label);
    try std.testing.expectEqual(api.ImageMime.png, edit.references[1].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.style, edit.references[2].role);
    try std.testing.expectEqualStrings("STYLE_REFERENCE_A", edit.references[2].label);
    try std.testing.expectEqual(api.ImageMime.webp, edit.references[2].image.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.pose, edit.references[3].role);
    try std.testing.expectEqualStrings("POSE_MAIN", edit.references[3].label);
}

test "parseArgs accepts generic edit reference without custom label" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
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

test "parseArgs accepts first edit reference with non-scene role" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "style=files/base-style,image/webp",
        "--prompt",
        "keep the current style",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqualStrings("files/base-style", edit.base.name);
    try std.testing.expectEqual(api.ImageMime.webp, edit.base.mime);
    try std.testing.expectEqual(api_edit.ReferenceRole.style, edit.base_role);
    try std.testing.expectEqual(@as(usize, 0), edit.reference_count);
}

test "parseArgs accepts non-base scene reference without custom label" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "image=files/base,image/jpeg",
        "--ref",
        "scene=files/scene,image/png",
        "--prompt",
        "use the scene reference",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 1), edit.reference_count);
    try std.testing.expectEqual(api_edit.ReferenceRole.scene, edit.references[0].role);
    try std.testing.expectEqualStrings("SCENE_REFERENCE_A", edit.references[0].label);
    try std.testing.expectEqualStrings("files/scene", edit.references[0].image.name);
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
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
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

test "parseArgs accepts files upload request log flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "upload",
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
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files list request log flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "list",
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
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files get request log flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "get",
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
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts files delete request log flag" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--print-request",
    });
    const files_delete = expectFilesDeleteCommand(parsed_command);
    try std.testing.expectEqualStrings("files/abc123", files_delete.name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts batch submit and defaults display name to complete basename" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "submit",
        "--path",
        "batch/requests.jsonl",
    });
    const batch_submit = expectBatchSubmitCommand(parsed_command);
    try std.testing.expectEqualStrings("batch/requests.jsonl", batch_submit.path);
    try std.testing.expectEqualStrings("requests.jsonl", batch_submit.display_name);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts batch submit display name and request logging" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "submit",
        "--print-request",
        "--display-name",
        "image batch",
        "--path",
        "requests.jsonl",
    });
    const batch_submit = expectBatchSubmitCommand(parsed_command);
    try std.testing.expectEqualStrings("requests.jsonl", batch_submit.path);
    try std.testing.expectEqualStrings("image batch", batch_submit.display_name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
}

test "parseArgs accepts batch status canonical name" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "status",
        "--name",
        "batches/abc123",
        "--print-request",
    });
    const batch_status = expectBatchStatusCommand(parsed_command);
    try std.testing.expectEqualStrings("batches/abc123", batch_status.name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
}

test "parseArgs accepts batch cancel canonical name" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--name",
        "batches/abc123",
        "--print-request",
    });
    const batch_cancel = expectBatchCancelCommand(parsed_command);
    try std.testing.expectEqualStrings("batches/abc123", batch_cancel.name);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts batch download with optional output directory" {
    const default_output = try parseArgs(&.{
        "nbimg",
        "batch",
        "download",
        "--name",
        "batches/abc123",
    });
    const default_download = expectBatchDownloadCommand(default_output);
    try std.testing.expectEqualStrings("batches/abc123", default_download.name);
    try std.testing.expectEqual(@as(?[]const u8, null), default_download.out_dir);

    const selected_output = try parseArgs(&.{
        "nbimg",
        "batch",
        "download",
        "--out-dir",
        "outputs",
        "--name",
        "batches/abc123",
        "--print-request",
    });
    const selected_download = expectBatchDownloadCommand(selected_output);
    try std.testing.expectEqualStrings("batches/abc123", selected_download.name);
    try std.testing.expectEqualStrings("outputs", selected_download.out_dir.?);
    try std.testing.expect(selected_output.traffic_log_options.print_request);
}

test "parseArgs accepts batch list" {
    const parsed_command = try parseArgs(&.{ "nbimg", "batch", "list" });
    _ = expectBatchListCommand(parsed_command);
    try std.testing.expect(!parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs accepts batch list request logging" {
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "batch",
        "list",
        "--print-request",
    });
    _ = expectBatchListCommand(parsed_command);
    try std.testing.expect(parsed_command.traffic_log_options.print_request);
    try std.testing.expect(parsed_command.traffic_log_options.print_response);
}

test "parseArgs rejects invalid batch command arguments" {
    try std.testing.expectError(error.MissingBatchCommand, parseArgs(&.{ "nbimg", "batch" }));
    try std.testing.expectError(error.UnknownBatchCommand, parseArgs(&.{ "nbimg", "batch", "remove" }));
    try std.testing.expectError(error.MissingPath, parseArgs(&.{ "nbimg", "batch", "submit" }));
    try std.testing.expectError(error.DuplicatePath, parseArgs(&.{
        "nbimg",
        "batch",
        "submit",
        "--path",
        "one.jsonl",
        "--path",
        "two.jsonl",
    }));
    try std.testing.expectError(error.DuplicateDisplayName, parseArgs(&.{
        "nbimg",
        "batch",
        "submit",
        "--path",
        "one.jsonl",
        "--display-name",
        "one",
        "--display-name",
        "two",
    }));
    try std.testing.expectError(error.MissingName, parseArgs(&.{ "nbimg", "batch", "status" }));
    try std.testing.expectError(error.InvalidBatchName, parseArgs(&.{
        "nbimg",
        "batch",
        "status",
        "--name",
        "abc123",
    }));
    try std.testing.expectError(error.InvalidBatchName, parseArgs(&.{
        "nbimg",
        "batch",
        "status",
        "--name",
        "batches/",
    }));
    try std.testing.expectError(error.MissingName, parseArgs(&.{ "nbimg", "batch", "cancel" }));
    try std.testing.expectError(error.DuplicateName, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--name",
        "batches/one",
        "--name",
        "batches/two",
    }));
    try std.testing.expectError(error.InvalidBatchName, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--name",
        "abc123",
    }));
    try std.testing.expectError(error.InvalidBatchName, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--name",
        "batches/",
    }));
    try std.testing.expectError(error.MissingName, parseArgs(&.{
        "nbimg",
        "batch",
        "download",
    }));
    try std.testing.expectError(error.InvalidBatchName, parseArgs(&.{
        "nbimg",
        "batch",
        "download",
        "--name",
        "abc123",
    }));
    try std.testing.expectError(error.DuplicateOutDir, parseArgs(&.{
        "nbimg",
        "batch",
        "download",
        "--name",
        "batches/one",
        "--out-dir",
        "one",
        "--out-dir",
        "two",
    }));
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "batches/abc123",
    }));
    try std.testing.expectError(error.OutDirUnsupported, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--out-dir",
        "output",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "batch",
        "cancel",
        "--force",
    }));
    try std.testing.expectError(error.UnexpectedArgument, parseArgs(&.{
        "nbimg",
        "batch",
        "list",
        "extra",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "batch",
        "list",
        "--filter",
        "state=RUNNING",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "batch",
        "list",
        "--out-dir",
        "output",
    }));
}

test "ambiguous batch creation failure reports uploaded file and no retry" {
    const gpa = std.testing.allocator;
    const message = try ambiguousBatchCreationFailureText(gpa, "files/input123", error.Timeout);
    defer gpa.free(message);

    try std.testing.expectEqualStrings(
        "error: batch creation transport failed after uploading files/input123: Timeout\n" ++
            "warning: batch creation is non-idempotent; a job may have been created, so nbimg did not retry\n",
        message,
    );
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

test "parseArgs rejects explicit prompts over max text bytes" {
    const too_long_prompt = "a" ** (api.max_generate_text_part_bytes + 1);

    try std.testing.expectError(error.PromptTooLong, parseArgs(&.{ "nbimg", "gen", "--prompt", too_long_prompt }));
    try std.testing.expectError(error.PromptTooLong, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        too_long_prompt,
    }));
}

test "parseArgs rejects stdin fallback prompt over max text bytes" {
    const too_long_prompt = "a" ** (api.max_generate_text_part_bytes + 1);

    try std.testing.expectError(error.PromptTooLong, parseArgsWithPrompt(&.{ "nbimg", "gen" }, too_long_prompt));
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
}

test "parseArgs rejects removed edit reference flags" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--base",
        "files/one,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));

    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--base-role",
        "character",
    }));

    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--character",
        "files/person,image/jpeg",
        "--prompt",
        "edit",
    }));

    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--object",
        "files/object,image/png",
        "--prompt",
        "edit",
    }));

    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--style",
        "files/style,image/webp",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit missing MIME" {
    try std.testing.expectError(error.MissingMime, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit invalid MIME" {
    try std.testing.expectError(error.InvalidMime, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/gif",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit malformed image input" {
    try std.testing.expectError(error.MalformedImageInput, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg,extra",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects edit invalid reference role" {
    try std.testing.expectError(error.InvalidReference, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "portrait=files/tjtj5me9i96c,image/jpeg",
        "--prompt",
        "change visual style to Broadway musical",
    }));
}

test "parseArgs rejects labeled first edit reference" {
    try std.testing.expectError(error.LabeledBaseReference, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene:BASE_SCENE=files/base,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit invalid label" {
    try std.testing.expectError(error.InvalidLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--ref",
        "character:character_a=files/person,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit duplicate label" {
    try std.testing.expectError(error.DuplicateLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--ref",
        "character:CHARACTER_A=files/person,image/jpeg",
        "--ref",
        "object:CHARACTER_A=files/object,image/png",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit reserved base image label" {
    try std.testing.expectError(error.DuplicateLabel, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--ref",
        "character:BASE_IMAGE=files/person,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many character references including character base" {
    try std.testing.expectError(error.TooManyCharacterReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "character=files/base,image/jpeg",
        "--ref",
        "character=files/one,image/jpeg",
        "--ref",
        "character=files/two,image/jpeg",
        "--ref",
        "character=files/three,image/jpeg",
        "--ref",
        "character=files/four,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many object references including object base" {
    try std.testing.expectError(error.TooManyObjectReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "object=files/base,image/jpeg",
        "--ref",
        "object=files/one,image/png",
        "--ref",
        "object=files/two,image/png",
        "--ref",
        "object=files/three,image/png",
        "--ref",
        "object=files/four,image/png",
        "--ref",
        "object=files/five,image/png",
        "--ref",
        "object=files/six,image/png",
        "--ref",
        "object=files/seven,image/png",
        "--ref",
        "object=files/eight,image/png",
        "--ref",
        "object=files/nine,image/png",
        "--ref",
        "object=files/ten,image/png",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects edit too many references" {
    try std.testing.expectError(error.TooManyReferences, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--ref",
        "style=files/one,image/jpeg",
        "--ref",
        "style=files/two,image/jpeg",
        "--ref",
        "style=files/three,image/jpeg",
        "--ref",
        "style=files/four,image/jpeg",
        "--ref",
        "style=files/five,image/jpeg",
        "--ref",
        "style=files/six,image/jpeg",
        "--ref",
        "style=files/seven,image/jpeg",
        "--ref",
        "style=files/eight,image/jpeg",
        "--ref",
        "style=files/nine,image/jpeg",
        "--ref",
        "style=files/ten,image/jpeg",
        "--ref",
        "style=files/eleven,image/jpeg",
        "--ref",
        "style=files/twelve,image/jpeg",
        "--ref",
        "style=files/thirteen,image/jpeg",
        "--ref",
        "style=files/fourteen,image/jpeg",
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects empty edit constraints" {
    try std.testing.expectError(error.EmptyPreserve, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--preserve",
        "",
        "--prompt",
        "edit",
    }));
    try std.testing.expectError(error.EmptyDoNot, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--do-not",
        "",
        "--prompt",
        "edit",
    }));
}

test "parseArgs accepts edit constraints at max text bytes" {
    const max_preserve = "p" ** api.max_generate_text_part_bytes;
    const max_do_not = "d" ** api.max_generate_text_part_bytes;
    const parsed_command = try parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--preserve",
        max_preserve,
        "--do-not",
        max_do_not,
        "--prompt",
        "edit",
    });
    const edit = expectEditCommand(parsed_command);

    try std.testing.expectEqual(@as(usize, 1), edit.preserve_count);
    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), edit.preserves[0].len);
    try std.testing.expectEqual(@as(usize, 1), edit.do_not_count);
    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), edit.do_nots[0].len);
}

test "parseArgs rejects edit constraints over max text bytes" {
    const too_long_preserve = "p" ** (api.max_generate_text_part_bytes + 1);
    const too_long_do_not = "d" ** (api.max_generate_text_part_bytes + 1);

    try std.testing.expectError(error.PreserveTooLong, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--preserve",
        too_long_preserve,
        "--prompt",
        "edit",
    }));
    try std.testing.expectError(error.DoNotTooLong, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--do-not",
        too_long_do_not,
        "--prompt",
        "edit",
    }));
}

test "parseArgs rejects empty edit constraints mixed with non-empty values" {
    try std.testing.expectError(error.EmptyPreserve, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
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
    }));
    try std.testing.expectError(error.EmptyDoNot, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/base,image/jpeg",
        "--preserve",
        "keep the crop",
        "--do-not",
        "",
        "--prompt",
        "edit",
    }));
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

test "parseArgs rejects write response as unknown flag" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "gen",
        "--write-response",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--write-response",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--write-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--write-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--write-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--write-response",
    }));
}

test "parseArgs rejects print response as unknown flag" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "gen",
        "--print-response",
        "--prompt",
        "My fair lady",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "edit",
        "--ref",
        "scene=files/tjtj5me9i96c,image/jpeg",
        "--print-response",
        "--prompt",
        "change visual style to Broadway musical",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--print-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--print-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--print-response",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--print-response",
    }));
}

test "parseArgs rejects image output options for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--aspect-ratio",
        "1:1",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--image-size",
        "1K",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--aspect-ratio",
        "16:9",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--image-size",
        "2K",
    }));
}

test "parseArgs rejects grounding for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--grounding",
        "web",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--grounding",
        "image",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--grounding",
        "web,image",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--grounding",
        "web",
    }));
}

test "parseArgs rejects thinking options for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--thinking-level",
        "high",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--include-thoughts",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--thinking-level",
        "minimal",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--include-thoughts",
    }));
}

test "parseArgs rejects safety options for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--safety",
        "none",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--safety",
        "off",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--safety",
        "permissive",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--safety",
        "strict",
    }));
}

test "parseArgs rejects advanced generation options for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--temperature",
        "1",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--top-p",
        "0.95",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--seed",
        "42",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--response-logprobs",
    }));
}

test "parseArgs rejects request-level controls for files commands" {
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "upload",
        "--path",
        "sample_images/good_night.jpeg",
        "--system",
        "Use editorial lighting.",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "list",
        "--cached-content",
        "cachedContents/brand",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "get",
        "--name",
        "files/abc123",
        "--service-tier",
        "standard",
    }));
    try std.testing.expectError(error.UnknownFlag, parseArgs(&.{
        "nbimg",
        "files",
        "delete",
        "--name",
        "files/abc123",
        "--store",
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
    const context = api.RequestContext{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = api_key,
        .traffic_log_options = .{
            .print_request = true,
            .print_response = true,
        },
    };

    const upload_mime = api.ImageMime.fromPath(live_edit_sample_image_path) orelse return error.UnsupportedInputMime;
    var uploaded_file = try uploadLiveEditSampleImage(&context, upload_mime);
    defer uploaded_file.deinit(gpa);
    defer deleteLiveEditSampleImage(&context, uploaded_file.name);

    const typed_client = try client.Client.init(gpa, std.testing.io, .{
        .api_key = api_key,
    });
    var outcome = try typed_client.countEditTokens(.{
        .prompt = live_edit_prompt,
        .output_options = .{
            .aspect_ratio = .r4_5,
            .image_size = .k1,
        },
        .grounding_options = .{
            .web = true,
            .image = true,
        },
        .thinking_options = .{
            .level = .high,
            .include_thoughts = true,
        },
        .generation_options = .{
            .max_output_tokens = 4096,
            .temperature = 0.7,
            .top_p = 0.95,
            .seed = 42,
            .presence_penalty = 0.0,
            .frequency_penalty = 0.0,
            .response_logprobs = true,
            .logprobs = 1,
            .stop_sequences = &.{"END"},
        },
        .request_options = .{
            .system_instruction = "Follow the edit request exactly.",
            .service_tier = .standard,
            .store = false,
        },
        .base = .{
            .name = uploaded_file.name,
            .mime = switch (upload_mime) {
                .jpeg => .jpeg,
                .png => .png,
                .webp => .webp,
            },
        },
        .base_role = .scene,
    });

    switch (outcome) {
        .success => |result| try std.testing.expect(result.total_tokens > 0),
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: countTokens edit request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            return error.CountTokensRequestFailed;
        },
    }
}

fn uploadLiveEditSampleImage(
    context: *const api.RequestContext,
    mime: api.ImageMime,
) !api_files.File {
    const gpa = context.gpa;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        live_edit_sample_image_path,
        gpa,
        .limited(api_files.max_upload_bytes),
    );
    defer gpa.free(bytes);
    if (bytes.len == 0) return error.EmptyUploadFile;

    var response = try api_files.uploadFile(context, .{
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

fn deleteLiveEditSampleImage(context: *const api.RequestContext, name: []const u8) void {
    var response = api_files.deleteFile(context, name) catch |err| {
        std.debug.print(
            "warning: failed to delete live edit fixture {s}: {s}\n",
            .{ name, @errorName(err) },
        );
        return;
    };
    defer response.deinit(context.gpa);

    if (response.status != .ok) {
        std.debug.print(
            "warning: live edit fixture delete for {s} returned HTTP {d}\n{s}\n",
            .{ name, @intFromEnum(response.status), response.body },
        );
    }
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
    const max_prompt = "a" ** api.max_generate_text_part_bytes;
    var reader = std.Io.Reader.fixed(max_prompt);
    const prompt = try readPromptFromReader(gpa, &reader);
    defer gpa.free(prompt);

    try std.testing.expectEqual(@as(usize, api.max_generate_text_part_bytes), prompt.len);
}

test "readPromptFromReader rejects stdin over max prompt bytes" {
    const too_long_prompt = "a" ** (api.max_generate_text_part_bytes + 1);
    var reader = std.Io.Reader.fixed(too_long_prompt);
    try std.testing.expectError(error.PromptTooLong, readPromptFromReader(std.testing.allocator, &reader));
}

fn testBatchInputJsonl(gpa: std.mem.Allocator, entry_count: usize) ![]u8 {
    assert(entry_count > 0);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    for (0..entry_count) |index| {
        try output.writer.print(
            "{{\"key\":\"key-{d}\",\"request\":{{\"contents\":[{{\"parts\":[{{\"text\":\"prompt-{d}\"}}]}}]}}}}\n",
            .{ index, index },
        );
    }
    return output.toOwnedSlice();
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

fn expectBatchSubmitCommand(parsed_command: ParsedCommand) BatchSubmitCommand {
    return switch (parsed_command.command) {
        .batch_submit => |batch_submit| batch_submit,
        else => unreachable,
    };
}

fn expectBatchStatusCommand(parsed_command: ParsedCommand) BatchStatusCommand {
    return switch (parsed_command.command) {
        .batch_status => |batch_status| batch_status,
        else => unreachable,
    };
}

fn expectBatchCancelCommand(parsed_command: ParsedCommand) BatchCancelCommand {
    return switch (parsed_command.command) {
        .batch_cancel => |batch_cancel| batch_cancel,
        else => unreachable,
    };
}

fn expectBatchDownloadCommand(parsed_command: ParsedCommand) BatchDownloadCommand {
    return switch (parsed_command.command) {
        .batch_download => |batch_download| batch_download,
        else => unreachable,
    };
}

fn expectBatchListCommand(parsed_command: ParsedCommand) BatchListCommand {
    return switch (parsed_command.command) {
        .batch_list => |batch_list| batch_list,
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
