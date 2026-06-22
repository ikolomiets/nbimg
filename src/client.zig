//! Supported typed client API for Gemini image-generation workflows.

const std = @import("std");
const api = @import("api.zig");
const batch_api = @import("batch.zig");
const edit_api = @import("edit.zig");
const file_domain = @import("files_domain.zig");
const files_api = @import("files.zig");
const gen = @import("gen.zig");
const operation = @import("operation.zig");

const default_request_timeout = std.Io.Duration.fromSeconds(180);

pub const max_edit_references = 13;
pub const max_edit_character_images = 4;
pub const max_edit_object_images = 10;
pub const max_edit_reference_label_bytes = 64;
pub const max_edit_preserve_constraints = 16;
pub const max_edit_do_not_constraints = 16;

comptime {
    std.debug.assert(max_edit_references == edit_api.max_references);
    std.debug.assert(max_edit_character_images == edit_api.max_character_references);
    std.debug.assert(max_edit_object_images == edit_api.max_object_references);
    std.debug.assert(max_edit_reference_label_bytes == edit_api.max_label_bytes);
    std.debug.assert(max_edit_preserve_constraints == edit_api.max_preserve_constraints);
    std.debug.assert(max_edit_do_not_constraints == edit_api.max_do_not_constraints);
}

/// Configures a client with an explicit borrowed Gemini API key and timeout.
///
/// - `api_key` remains caller-owned and must outlive the client and its requests.
/// - The value owns no resources and allocates nothing.
pub const ClientOptions = struct {
    api_key: []const u8,
    timeout: std.Io.Duration = default_request_timeout,
};

pub const ApiFailure = operation.ApiFailure;

/// Represents either a decoded operation result or a completed API failure.
pub fn Outcome(comptime T: type) type {
    return operation.Outcome(T);
}

/// Separates completed responses by transport and decoding stage.
pub fn OperationOutcome(comptime T: type) type {
    return operation.OperationOutcome(T);
}

pub const ImageAspectRatio = enum {
    r1_1,
    r1_4,
    r1_8,
    r2_3,
    r3_2,
    r3_4,
    r4_1,
    r4_3,
    r4_5,
    r5_4,
    r8_1,
    r9_16,
    r16_9,
    r21_9,
};

pub const ImageSize = enum {
    px512,
    k1,
    k2,
    k4,
};

/// Configures image dimensions for generated output.
pub const ImageOutputOptions = struct {
    aspect_ratio: ?ImageAspectRatio = null,
    image_size: ?ImageSize = null,
};

/// Selects optional web and image grounding sources.
pub const GroundingOptions = struct {
    web: bool = false,
    image: bool = false,
};

pub const ThinkingLevel = enum {
    minimal,
    high,
};

/// Configures model thinking behavior.
pub const ThinkingOptions = struct {
    level: ?ThinkingLevel = null,
    include_thoughts: bool = false,
};

pub const HarmBlockThreshold = enum {
    block_low_and_above,
    block_medium_and_above,
    block_only_high,
    block_none,
    off,
    harm_block_threshold_unspecified,
};

/// Applies one harm-block threshold to every supported category.
pub const SafetyOptions = struct {
    threshold: HarmBlockThreshold = .block_none,
};

/// Configures sampling, token limits, and borrowed stop sequences.
pub const GenerationOptions = struct {
    max_output_tokens: ?u32 = null,
    temperature: ?f64 = null,
    top_p: ?f64 = null,
    seed: ?i32 = null,
    presence_penalty: ?f64 = null,
    frequency_penalty: ?f64 = null,
    response_logprobs: bool = false,
    logprobs: ?u8 = null,
    stop_sequences: []const []const u8 = &.{},
};

pub const ServiceTier = enum {
    flex,
    standard,
    priority,
};

pub const OutputMime = enum {
    png,
    jpeg,
    webp,
};

/// Owns one generated image returned by Gemini.
pub const GeneratedImage = struct {
    candidate_position: usize,
    part_position: usize,
    mime: OutputMime,
    bytes: []u8,

    /// Frees the image bytes and invalidates the value.
    pub fn deinit(image: *GeneratedImage, allocator: std.mem.Allocator) void {
        allocator.free(image.bytes);
        image.* = undefined;
    }
};

/// Owns the decoded images and response metadata from one generation request.
pub const GenerationResult = struct {
    response_id: []u8,
    images: []GeneratedImage,
    reported_service_tier: ?ServiceTier,

    /// Frees all nested image bytes and result storage, then invalidates the value.
    pub fn deinit(result: *GenerationResult, allocator: std.mem.Allocator) void {
        for (result.images) |*image| image.deinit(allocator);
        allocator.free(result.images);
        allocator.free(result.response_id);
        result.* = undefined;
    }
};

/// Configures request-level Gemini options.
pub const RequestOptions = struct {
    system_instruction: ?[]const u8 = null,
    cached_content: ?[]const u8 = null,
    service_tier: ?ServiceTier = null,
    store: ?bool = null,
};

/// Describes one borrowed generation token-count request.
pub const GenerationRequest = struct {
    prompt: []const u8,
    output_options: ImageOutputOptions = .{},
    grounding_options: GroundingOptions = .{},
    thinking_options: ThinkingOptions = .{},
    safety_options: ?SafetyOptions = null,
    generation_options: GenerationOptions = .{},
    request_options: RequestOptions = .{},
};

pub const InputImageMime = file_domain.InputImageMime;

pub const FileUpload = file_domain.FileUpload;
pub const File = file_domain.File;
pub const FileListPage = file_domain.FileListPage;
pub const FileState = file_domain.FileState;
pub const FileSource = file_domain.FileSource;
pub const RemoteError = file_domain.RemoteError;
pub const FileValidationError = file_domain.FileValidationError;
pub const max_file_upload_bytes = file_domain.max_file_upload_bytes;

pub const BatchValidationError = batch_api.BatchValidationError;
pub const BatchInputSummary = batch_api.BatchInputSummary;
pub const PreparedBatchEntry = batch_api.PreparedBatchEntry;
pub const max_batch_entry_bytes = batch_api.max_batch_entry_bytes;
pub const max_batch_entries = batch_api.max_batch_entries;
pub const max_batch_input_bytes = batch_api.max_batch_input_bytes;
pub const validateBatchInput = batch_api.validateBatchInput;

pub const ReferenceRole = enum {
    scene,
    character,
    object,
    style,
    pose,
    composition,
    background,
    texture,
    image,
};

/// Identifies one borrowed Gemini Files API image.
pub const UploadedImage = struct {
    name: []const u8,
    mime: InputImageMime,
};

/// Associates a borrowed uploaded image with an edit role and manifest label.
pub const Reference = struct {
    role: ReferenceRole,
    label: []const u8,
    image: UploadedImage,
};

/// Describes one borrowed image-edit request.
pub const EditRequest = struct {
    prompt: []const u8,
    output_options: ImageOutputOptions = .{},
    grounding_options: GroundingOptions = .{},
    thinking_options: ThinkingOptions = .{},
    safety_options: ?SafetyOptions = null,
    generation_options: GenerationOptions = .{},
    request_options: RequestOptions = .{},
    base: UploadedImage,
    base_role: ReferenceRole = .scene,
    references: []const Reference = &.{},
    preserves: []const []const u8 = &.{},
    do_nots: []const []const u8 = &.{},
};

/// Reports invalid caller-controlled generation request fields.
pub const GenerationValidationError = error{
    EmptyPrompt,
    PromptTooLong,
    InvalidMaxOutputTokens,
    InvalidTemperature,
    InvalidTopP,
    InvalidPresencePenalty,
    InvalidFrequencyPenalty,
    LogprobsRequireResponseLogprobs,
    InvalidLogprobs,
    TooManyStopSequences,
    EmptyStopSequence,
    DuplicateStopSequence,
    EmptySystemInstruction,
    SystemInstructionTooLong,
    InvalidCachedContentName,
    RequestTooLong,
};

/// Reports invalid caller-controlled edit request fields.
pub const EditValidationError = error{
    EmptyPrompt,
    PromptTooLong,
    InvalidBaseFileName,
    InvalidReferenceFileName,
    FileUriTooLong,
    InvalidReferenceLabel,
    ReservedReferenceLabel,
    DuplicateReferenceLabel,
    TooManyReferences,
    TooManyCharacterImages,
    TooManyObjectImages,
    TooManyPreserveConstraints,
    TooManyDoNotConstraints,
    EmptyPreserveConstraint,
    PreserveConstraintTooLong,
    EmptyDoNotConstraint,
    DoNotConstraintTooLong,
    EditTaskTooLong,
    InvalidMaxOutputTokens,
    InvalidTemperature,
    InvalidTopP,
    InvalidPresencePenalty,
    InvalidFrequencyPenalty,
    LogprobsRequireResponseLogprobs,
    InvalidLogprobs,
    TooManyStopSequences,
    EmptyStopSequence,
    DuplicateStopSequence,
    EmptySystemInstruction,
    SystemInstructionTooLong,
    InvalidCachedContentName,
    RequestTooLong,
};

/// Holds decoded token counts without owning heap storage.
pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
};

/// Owns the exact generate-content request retained through countTokens validation.
///
/// This is an internal cross-module seam for CLI Batch preparation.
pub const PreparedBatchRequest = struct {
    generate_request_json: []u8,
    total_tokens: u64,

    /// Frees the retained generate-content JSON and invalidates the value.
    pub fn deinit(request: *PreparedBatchRequest, allocator: std.mem.Allocator) void {
        allocator.free(request.generate_request_json);
        request.* = undefined;
    }
};

/// Stores explicit dependencies for supported Gemini operations.
///
/// The API key remains caller-owned for the complete client lifetime.
pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    timeout: std.Io.Duration,

    /// Initializes a client without allocating or copying the API key.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        options: ClientOptions,
    ) !Client {
        if (options.api_key.len == 0) return error.EmptyApiKey;
        if (options.timeout.nanoseconds <= 0) return error.InvalidTimeout;

        return .{
            .allocator = allocator,
            .io = io,
            .api_key = options.api_key,
            .timeout = options.timeout,
        };
    }

    /// Validates and counts tokens for a borrowed generation request.
    ///
    /// Completed non-success HTTP responses are returned as owned API failures.
    pub fn countGenerateTokens(
        client: *const Client,
        request: GenerationRequest,
    ) !Outcome(CountTokensResult) {
        try validateGenerationRequest(request);

        const generate_request_json = try buildGenerateRequest(client.allocator, request);
        defer client.allocator.free(generate_request_json);

        const context = client.requestContext();
        return publicOutcome(
            CountTokensResult,
            try countTokensWithContext(&context, generate_request_json),
        );
    }

    /// Validates and counts tokens for a borrowed edit request.
    ///
    /// Completed non-success HTTP responses are returned as owned API failures.
    pub fn countEditTokens(
        client: *const Client,
        request: EditRequest,
    ) !Outcome(CountTokensResult) {
        try validateEditRequest(request);

        const generate_request_json = try buildEditGenerateRequest(client.allocator, request);
        defer client.allocator.free(generate_request_json);

        const context = client.requestContext();
        return publicOutcome(
            CountTokensResult,
            try countTokensWithContext(&context, generate_request_json),
        );
    }

    /// Validates and prepares one owned generation Batch JSONL record.
    ///
    /// The explicit key is validated before request validation, allocation, or network IO.
    pub fn prepareGenerationBatchEntry(
        client: *const Client,
        key: []const u8,
        request: GenerationRequest,
    ) !Outcome(PreparedBatchEntry) {
        if (key.len == 0) return error.EmptyBatchKey;

        const context = client.requestContext();
        return preparedBatchEntryPublicOutcome(
            client.allocator,
            key,
            try prepareGenerationBatchRequestWithContext(&context, request),
        );
    }

    /// Validates and prepares one owned edit Batch JSONL record.
    ///
    /// The explicit key is validated before request validation, allocation, or network IO.
    pub fn prepareEditBatchEntry(
        client: *const Client,
        key: []const u8,
        request: EditRequest,
    ) !Outcome(PreparedBatchEntry) {
        if (key.len == 0) return error.EmptyBatchKey;

        const context = client.requestContext();
        return preparedBatchEntryPublicOutcome(
            client.allocator,
            key,
            try prepareEditBatchRequestWithContext(&context, request),
        );
    }

    /// Generates and returns owned decoded images for a borrowed request.
    ///
    /// Completed non-success HTTP responses are returned as owned API failures.
    pub fn generate(
        client: *const Client,
        request: GenerationRequest,
    ) !Outcome(GenerationResult) {
        const context = client.requestContext();
        return publicOutcome(
            GenerationResult,
            try generateWithContext(&context, request),
        );
    }

    /// Edits an uploaded image and returns owned decoded images.
    ///
    /// Completed non-success HTTP responses are returned as owned API failures.
    pub fn edit(
        client: *const Client,
        request: EditRequest,
    ) !Outcome(GenerationResult) {
        const context = client.requestContext();
        return publicOutcome(
            GenerationResult,
            try editWithContext(&context, request),
        );
    }

    /// Uploads borrowed image bytes and returns owned File metadata.
    pub fn uploadFile(
        client: *const Client,
        upload: FileUpload,
    ) !Outcome(File) {
        const context = client.requestContext();
        return publicOutcome(
            File,
            try files_api.uploadFileWithContext(&context, upload),
        );
    }

    /// Fetches one canonical File resource and returns owned metadata.
    pub fn getFile(
        client: *const Client,
        name: []const u8,
    ) !Outcome(File) {
        const context = client.requestContext();
        return publicOutcome(
            File,
            try files_api.getFileWithContext(&context, name),
        );
    }

    /// Fetches one fixed-size File page using an optional continuation token.
    pub fn listFilesPage(
        client: *const Client,
        page_token: ?[]const u8,
    ) !Outcome(FileListPage) {
        const context = client.requestContext();
        return publicOutcome(
            FileListPage,
            try files_api.listFilesPageWithContext(&context, page_token),
        );
    }

    /// Deletes one canonical File resource.
    pub fn deleteFile(
        client: *const Client,
        name: []const u8,
    ) !Outcome(void) {
        const context = client.requestContext();
        return publicOutcome(
            void,
            try files_api.deleteFileWithContext(&context, name),
        );
    }

    fn requestContext(client: *const Client) api.RequestContext {
        return .{
            .gpa = client.allocator,
            .io = client.io,
            .api_key = client.api_key,
            .timeout = client.timeout,
        };
    }
};

/// Generates images using an explicit internal request context.
///
/// This seam allows CLI callers to supply traffic logging without changing the
/// supported public client contract.
pub fn generateWithContext(
    context: *const api.RequestContext,
    request: GenerationRequest,
) !OperationOutcome(GenerationResult) {
    try validateGenerationRequest(request);

    const request_json = try buildGenerateRequest(context.gpa, request);
    defer context.gpa.free(request_json);

    var response = try api.postGenerateContentJson(context, .nano2, request_json);
    return generatedContentOutcomeFromResponse(context.gpa, &response);
}

/// Edits an image using an explicit internal request context.
pub fn editWithContext(
    context: *const api.RequestContext,
    request: EditRequest,
) !OperationOutcome(GenerationResult) {
    try validateEditRequest(request);

    const request_json = try buildEditGenerateRequest(context.gpa, request);
    defer context.gpa.free(request_json);

    var response = try api.postGenerateContentJson(context, .nano2, request_json);
    return generatedContentOutcomeFromResponse(context.gpa, &response);
}

/// Builds and validates one generation request while retaining its exact JSON bytes.
///
/// This is an internal cross-module seam for the CLI migration in Item #12.
pub fn prepareGenerationBatchRequestWithContext(
    context: *const api.RequestContext,
    request: GenerationRequest,
) !OperationOutcome(PreparedBatchRequest) {
    try validateGenerationRequest(request);

    const generate_request_json = try buildGenerateRequest(context.gpa, request);
    return prepareBatchRequestWithContext(context, generate_request_json);
}

/// Builds and validates one edit request while retaining its exact JSON bytes.
///
/// This is an internal cross-module seam for the CLI migration in Item #12.
pub fn prepareEditBatchRequestWithContext(
    context: *const api.RequestContext,
    request: EditRequest,
) !OperationOutcome(PreparedBatchRequest) {
    try validateEditRequest(request);

    const generate_request_json = try buildEditGenerateRequest(context.gpa, request);
    return prepareBatchRequestWithContext(context, generate_request_json);
}

fn publicOutcome(
    comptime T: type,
    outcome: OperationOutcome(T),
) !Outcome(T) {
    return switch (outcome) {
        .success => |result| .{ .success = result },
        .api_failure => |failure| .{ .api_failure = failure },
        .response_decoding_failure => |err| return err,
    };
}

fn preparedBatchEntryPublicOutcome(
    allocator: std.mem.Allocator,
    key: []const u8,
    outcome: OperationOutcome(PreparedBatchRequest),
) !Outcome(PreparedBatchEntry) {
    return switch (outcome) {
        .success => |prepared_value| {
            var prepared = prepared_value;
            defer prepared.deinit(allocator);
            return .{
                .success = try prepareBatchEntry(allocator, key, prepared),
            };
        },
        .api_failure => |failure| .{ .api_failure = failure },
        .response_decoding_failure => |err| return err,
    };
}

fn prepareBatchEntry(
    allocator: std.mem.Allocator,
    key: []const u8,
    request: PreparedBatchRequest,
) !PreparedBatchEntry {
    std.debug.assert(key.len > 0);

    const jsonl_record = try batch_api.buildEntryJson(
        allocator,
        key,
        request.generate_request_json,
    );
    errdefer allocator.free(jsonl_record);
    if (jsonl_record.len > max_batch_entry_bytes) return error.BatchEntryTooLong;

    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);

    return .{
        .key = owned_key,
        .jsonl_record = jsonl_record,
        .total_tokens = request.total_tokens,
    };
}

fn prepareBatchRequestWithContext(
    context: *const api.RequestContext,
    generate_request_json: []u8,
) !OperationOutcome(PreparedBatchRequest) {
    errdefer context.gpa.free(generate_request_json);

    const outcome = try countTokensWithContext(context, generate_request_json);
    return preparedBatchRequestOutcomeFromCountTokens(
        context.gpa,
        generate_request_json,
        outcome,
    );
}

fn preparedBatchRequestOutcomeFromCountTokens(
    allocator: std.mem.Allocator,
    generate_request_json: []u8,
    outcome: OperationOutcome(CountTokensResult),
) OperationOutcome(PreparedBatchRequest) {
    return switch (outcome) {
        .success => |result| .{
            .success = .{
                .generate_request_json = generate_request_json,
                .total_tokens = result.total_tokens,
            },
        },
        .api_failure => |failure| {
            allocator.free(generate_request_json);
            return .{ .api_failure = failure };
        },
        .response_decoding_failure => |err| {
            allocator.free(generate_request_json);
            return .{ .response_decoding_failure = err };
        },
    };
}

fn countTokensWithContext(
    context: *const api.RequestContext,
    generate_request_json: []const u8,
) !OperationOutcome(CountTokensResult) {
    const request_json = try api.buildCountTokensRequestFromGenerateContentJson(
        context.gpa,
        .nano2,
        generate_request_json,
    );
    defer context.gpa.free(request_json);

    var response = try api.postCountTokensJson(context, .nano2, request_json);
    return countTokensOutcomeFromResponse(context.gpa, &response);
}

fn countTokensOutcomeFromResponse(
    allocator: std.mem.Allocator,
    response: *api.HttpResponse,
) OperationOutcome(CountTokensResult) {
    if (response.status.class() != .success) {
        const failure = ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    defer response.deinit(allocator);

    const result = api.decodeCountTokensResponse(allocator, response.body) catch |err| {
        return .{ .response_decoding_failure = err };
    };
    return .{ .success = .{
        .total_tokens = result.total_tokens,
        .cached_content_token_count = result.cached_content_token_count,
    } };
}

fn generatedContentOutcomeFromResponse(
    allocator: std.mem.Allocator,
    response: *api.HttpResponse,
) OperationOutcome(GenerationResult) {
    if (response.status.class() != .success) {
        const failure = ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    defer response.deinit(allocator);

    var files = api.decodeGeneratedFiles(allocator, response.body) catch |err| {
        return .{ .response_decoding_failure = err };
    };
    const result = generationResultFromGeneratedFiles(allocator, &files) catch |err| {
        files.deinit(allocator);
        return .{ .response_decoding_failure = err };
    };

    return .{ .success = result };
}

fn generationResultFromGeneratedFiles(
    allocator: std.mem.Allocator,
    files: *api.GeneratedFiles,
) !GenerationResult {
    const reported_service_tier = if (files.reported_service_tier_name) |name|
        serviceTierFromWireName(name) orelse return error.UnsupportedServiceTier
    else
        null;

    const images = try allocator.alloc(GeneratedImage, files.items.len);
    for (files.items, images) |file, *image| {
        image.* = .{
            .candidate_position = file.candidate_index,
            .part_position = file.part_index,
            .mime = switch (file.mime) {
                .png => .png,
                .jpeg => .jpeg,
                .webp => .webp,
            },
            .bytes = file.bytes,
        };
    }

    const result = GenerationResult{
        .response_id = files.response_id,
        .images = images,
        .reported_service_tier = reported_service_tier,
    };
    allocator.free(files.items);
    if (files.reported_service_tier_name) |name| allocator.free(name);
    files.* = undefined;
    return result;
}

fn serviceTierFromWireName(name: []const u8) ?ServiceTier {
    if (std.mem.eql(u8, name, "flex")) return .flex;
    if (std.mem.eql(u8, name, "standard")) return .standard;
    if (std.mem.eql(u8, name, "priority")) return .priority;
    return null;
}

fn validateGenerationRequest(request: GenerationRequest) GenerationValidationError!void {
    if (request.prompt.len == 0) return error.EmptyPrompt;
    if (request.prompt.len > api.max_generate_text_part_bytes) return error.PromptTooLong;

    try validateSharedRequestOptions(request.generation_options, request.request_options);

    var field_bytes = request.prompt.len;
    addSharedRequestFieldBytes(&field_bytes, request.generation_options, request.request_options);
    if (field_bytes > api.max_generate_request_field_bytes) return error.RequestTooLong;
}

const SharedValidationError = error{
    InvalidMaxOutputTokens,
    InvalidTemperature,
    InvalidTopP,
    InvalidPresencePenalty,
    InvalidFrequencyPenalty,
    LogprobsRequireResponseLogprobs,
    InvalidLogprobs,
    TooManyStopSequences,
    EmptyStopSequence,
    DuplicateStopSequence,
    EmptySystemInstruction,
    SystemInstructionTooLong,
    InvalidCachedContentName,
};

fn validateSharedRequestOptions(
    generation_options: GenerationOptions,
    request_options: RequestOptions,
) SharedValidationError!void {
    if (generation_options.max_output_tokens) |tokens| {
        if (tokens < 1 or tokens > api.max_output_tokens) return error.InvalidMaxOutputTokens;
    }
    if (generation_options.temperature) |temperature| {
        if (!std.math.isFinite(temperature) or temperature < 0.0 or temperature > 2.0) {
            return error.InvalidTemperature;
        }
    }
    if (generation_options.top_p) |top_p| {
        if (!std.math.isFinite(top_p) or top_p < 0.0 or top_p > 1.0) {
            return error.InvalidTopP;
        }
    }
    if (generation_options.presence_penalty) |penalty| {
        if (!std.math.isFinite(penalty) or penalty < -2.0 or penalty >= 2.0) {
            return error.InvalidPresencePenalty;
        }
    }
    if (generation_options.frequency_penalty) |penalty| {
        if (!std.math.isFinite(penalty) or penalty < -2.0 or penalty >= 2.0) {
            return error.InvalidFrequencyPenalty;
        }
    }
    if (generation_options.logprobs != null and !generation_options.response_logprobs) {
        return error.LogprobsRequireResponseLogprobs;
    }
    if (generation_options.logprobs) |logprobs| {
        if (logprobs < 1 or logprobs > 20) return error.InvalidLogprobs;
    }
    if (generation_options.stop_sequences.len > api.max_stop_sequences) {
        return error.TooManyStopSequences;
    }
    for (generation_options.stop_sequences, 0..) |stop, index| {
        if (stop.len == 0) return error.EmptyStopSequence;
        for (generation_options.stop_sequences[index + 1 ..]) |other| {
            if (std.mem.eql(u8, stop, other)) return error.DuplicateStopSequence;
        }
    }

    if (request_options.system_instruction) |system_instruction| {
        if (system_instruction.len == 0) return error.EmptySystemInstruction;
        if (system_instruction.len > api.max_generate_text_part_bytes) {
            return error.SystemInstructionTooLong;
        }
    }
    if (request_options.cached_content) |cached_content| {
        if (!api.isCanonicalCachedContentName(cached_content)) {
            return error.InvalidCachedContentName;
        }
    }
}

fn addSharedRequestFieldBytes(
    field_bytes: *usize,
    generation_options: GenerationOptions,
    request_options: RequestOptions,
) void {
    if (request_options.system_instruction) |value| field_bytes.* +|= value.len;
    if (request_options.cached_content) |value| field_bytes.* +|= value.len;
    for (generation_options.stop_sequences) |value| field_bytes.* +|= value.len;
}

fn validateEditRequest(request: EditRequest) EditValidationError!void {
    if (request.references.len > max_edit_references) return error.TooManyReferences;
    try validateSharedRequestOptions(request.generation_options, request.request_options);

    var references: [max_edit_references]edit_api.Reference = undefined;
    try edit_api.validateRequest(wireEditRequest(request, &references));
}

fn buildCountTokensRequest(
    allocator: std.mem.Allocator,
    request: GenerationRequest,
) ![]u8 {
    const generate_request_json = try buildGenerateRequest(allocator, request);
    defer allocator.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(
        allocator,
        .nano2,
        generate_request_json,
    );
}

fn buildEditCountTokensRequest(
    allocator: std.mem.Allocator,
    request: EditRequest,
) ![]u8 {
    const generate_request_json = try buildEditGenerateRequest(allocator, request);
    defer allocator.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(
        allocator,
        .nano2,
        generate_request_json,
    );
}

fn buildEditGenerateRequest(
    allocator: std.mem.Allocator,
    request: EditRequest,
) ![]u8 {
    var references: [max_edit_references]edit_api.Reference = undefined;
    return edit_api.buildGenerateRequest(
        allocator,
        wireEditRequest(request, &references),
    );
}

fn buildGenerateRequest(
    allocator: std.mem.Allocator,
    request: GenerationRequest,
) ![]u8 {
    return gen.buildGenerateRequest(
        allocator,
        request.prompt,
        wireImageOutputOptions(request.output_options),
        .{
            .web = request.grounding_options.web,
            .image = request.grounding_options.image,
        },
        wireThinkingOptions(request.thinking_options),
        if (request.safety_options) |options| wireSafetyOptions(options) else null,
        wireGenerationOptions(request.generation_options),
        wireRequestOptions(request.request_options),
    );
}

fn wireEditRequest(
    request: EditRequest,
    references: *[max_edit_references]edit_api.Reference,
) edit_api.EditRequest {
    std.debug.assert(request.references.len <= references.len);
    for (request.references, references[0..request.references.len]) |reference, *wire| {
        wire.* = .{
            .role = wireReferenceRole(reference.role),
            .label = reference.label,
            .image = wireUploadedImage(reference.image),
        };
    }

    return .{
        .prompt = request.prompt,
        .output_options = wireImageOutputOptions(request.output_options),
        .grounding_options = .{
            .web = request.grounding_options.web,
            .image = request.grounding_options.image,
        },
        .thinking_options = wireThinkingOptions(request.thinking_options),
        .safety_options = if (request.safety_options) |options|
            wireSafetyOptions(options)
        else
            null,
        .generation_options = wireGenerationOptions(request.generation_options),
        .request_options = wireRequestOptions(request.request_options),
        .base = wireUploadedImage(request.base),
        .base_role = wireReferenceRole(request.base_role),
        .references = references[0..request.references.len],
        .preserves = request.preserves,
        .do_nots = request.do_nots,
    };
}

fn wireUploadedImage(image: UploadedImage) edit_api.UploadedImage {
    return .{
        .name = image.name,
        .mime = switch (image.mime) {
            .jpeg => .jpeg,
            .png => .png,
            .webp => .webp,
        },
    };
}

fn wireReferenceRole(role: ReferenceRole) edit_api.ReferenceRole {
    return switch (role) {
        .scene => .scene,
        .character => .character,
        .object => .object,
        .style => .style,
        .pose => .pose,
        .composition => .composition,
        .background => .background,
        .texture => .texture,
        .image => .image,
    };
}

fn wireImageOutputOptions(options: ImageOutputOptions) api.ImageOutputOptions {
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

fn wireThinkingOptions(options: ThinkingOptions) api.ThinkingOptions {
    return .{
        .level = if (options.level) |value| switch (value) {
            .minimal => .minimal,
            .high => .high,
        } else null,
        .include_thoughts = options.include_thoughts,
    };
}

fn wireSafetyOptions(options: SafetyOptions) api.SafetyOptions {
    return .{ .threshold = switch (options.threshold) {
        .block_low_and_above => .block_low_and_above,
        .block_medium_and_above => .block_medium_and_above,
        .block_only_high => .block_only_high,
        .block_none => .block_none,
        .off => .off,
        .harm_block_threshold_unspecified => .harm_block_threshold_unspecified,
    } };
}

fn wireGenerationOptions(options: GenerationOptions) api.GenerationOptions {
    var wire = api.GenerationOptions{
        .max_output_tokens = options.max_output_tokens,
        .temperature = options.temperature,
        .top_p = options.top_p,
        .seed = options.seed,
        .presence_penalty = options.presence_penalty,
        .frequency_penalty = options.frequency_penalty,
        .response_logprobs = options.response_logprobs,
        .logprobs = options.logprobs,
    };
    for (options.stop_sequences) |stop| wire.appendStopSequence(stop);
    return wire;
}

fn wireRequestOptions(options: RequestOptions) api.RequestOptions {
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

test "Client.init borrows configuration without allocating" {
    var no_memory: [0]u8 = .{};
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&no_memory);
    const key = "borrowed-key";

    const client = try Client.init(fixed_allocator.allocator(), std.testing.io, .{
        .api_key = key,
    });

    try std.testing.expectEqual(key.ptr, client.api_key.ptr);
    try std.testing.expectEqual(key.len, client.api_key.len);
    try std.testing.expectEqual(@as(i64, 180), client.timeout.toSeconds());
}

test "Client.init validates key and timeout" {
    try std.testing.expectError(
        error.EmptyApiKey,
        Client.init(std.testing.allocator, std.testing.io, .{ .api_key = "" }),
    );
    try std.testing.expectError(
        error.InvalidTimeout,
        Client.init(std.testing.allocator, std.testing.io, .{
            .api_key = "key",
            .timeout = .fromNanoseconds(0),
        }),
    );
    try std.testing.expectError(
        error.InvalidTimeout,
        Client.init(std.testing.allocator, std.testing.io, .{
            .api_key = "key",
            .timeout = .fromNanoseconds(-1),
        }),
    );
}

test "clients keep independent borrowed configuration" {
    const first = try Client.init(std.testing.allocator, std.testing.io, .{
        .api_key = "first",
        .timeout = .fromMilliseconds(100),
    });
    const second = try Client.init(std.testing.allocator, std.testing.io, .{
        .api_key = "second",
        .timeout = .fromSeconds(7),
    });

    try std.testing.expectEqualStrings("first", first.api_key);
    try std.testing.expectEqual(@as(i64, 100), first.timeout.toMilliseconds());
    try std.testing.expectEqualStrings("second", second.api_key);
    try std.testing.expectEqual(@as(i64, 7), second.timeout.toSeconds());
}

test "generation request validation returns exact errors" {
    try std.testing.expectError(error.EmptyPrompt, validateGenerationRequest(.{ .prompt = "" }));
    try std.testing.expectError(error.PromptTooLong, validateGenerationRequest(.{
        .prompt = "x" ** (api.max_generate_text_part_bytes + 1),
    }));
    try std.testing.expectError(error.InvalidMaxOutputTokens, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .max_output_tokens = 0 },
    }));
    try std.testing.expectError(error.InvalidTemperature, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .temperature = std.math.nan(f64) },
    }));
    try std.testing.expectError(error.InvalidTopP, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .top_p = 1.1 },
    }));
    try std.testing.expectError(error.InvalidPresencePenalty, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .presence_penalty = 2.0 },
    }));
    try std.testing.expectError(error.InvalidFrequencyPenalty, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .frequency_penalty = -2.1 },
    }));
    try std.testing.expectError(error.LogprobsRequireResponseLogprobs, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .logprobs = 1 },
    }));
    try std.testing.expectError(error.InvalidLogprobs, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .response_logprobs = true, .logprobs = 21 },
    }));
    try std.testing.expectError(error.TooManyStopSequences, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .stop_sequences = &.{ "1", "2", "3", "4", "5", "6" } },
    }));
    try std.testing.expectError(error.EmptyStopSequence, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .stop_sequences = &.{""} },
    }));
    try std.testing.expectError(error.DuplicateStopSequence, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{ .stop_sequences = &.{ "same", "same" } },
    }));
    try std.testing.expectError(error.EmptySystemInstruction, validateGenerationRequest(.{
        .prompt = "x",
        .request_options = .{ .system_instruction = "" },
    }));
    try std.testing.expectError(error.SystemInstructionTooLong, validateGenerationRequest(.{
        .prompt = "x",
        .request_options = .{
            .system_instruction = "x" ** (api.max_generate_text_part_bytes + 1),
        },
    }));
    try std.testing.expectError(error.InvalidCachedContentName, validateGenerationRequest(.{
        .prompt = "x",
        .request_options = .{ .cached_content = "invalid" },
    }));
    const oversized_stop = try std.testing.allocator.alloc(
        u8,
        api.max_generate_request_field_bytes,
    );
    defer std.testing.allocator.free(oversized_stop);
    @memset(oversized_stop, 'x');
    try std.testing.expectError(error.RequestTooLong, validateGenerationRequest(.{
        .prompt = "x",
        .generation_options = .{
            .stop_sequences = &.{oversized_stop},
        },
    }));
}

test "invalid public request returns before allocation or network IO" {
    var no_memory: [0]u8 = .{};
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&no_memory);
    const client = try Client.init(fixed_allocator.allocator(), std.testing.io, .{
        .api_key = "key",
    });

    try std.testing.expectError(
        error.EmptyPrompt,
        client.countGenerateTokens(.{ .prompt = "" }),
    );
    try std.testing.expectError(
        error.EmptyPrompt,
        client.generate(.{ .prompt = "" }),
    );
    try std.testing.expectError(
        error.EmptyBatchKey,
        client.prepareGenerationBatchEntry("", .{ .prompt = "" }),
    );
    try std.testing.expectError(
        error.EmptyPrompt,
        client.prepareGenerationBatchEntry("key", .{ .prompt = "" }),
    );
    const invalid_edit = EditRequest{
        .prompt = "",
        .base = .{ .name = "files/base", .mime = .jpeg },
    };
    try std.testing.expectError(error.EmptyPrompt, client.countEditTokens(invalid_edit));
    try std.testing.expectError(error.EmptyPrompt, client.edit(invalid_edit));
    try std.testing.expectError(
        error.EmptyBatchKey,
        client.prepareEditBatchEntry("", invalid_edit),
    );
    try std.testing.expectError(
        error.EmptyPrompt,
        client.prepareEditBatchEntry("key", invalid_edit),
    );
    try std.testing.expectError(
        error.EmptyFileBytes,
        client.uploadFile(.{ .mime = .jpeg, .bytes = "" }),
    );
    try std.testing.expectError(error.InvalidFileName, client.getFile("abc123"));
    try std.testing.expectError(error.EmptyPageToken, client.listFilesPage(""));
    try std.testing.expectError(error.InvalidFileName, client.deleteFile("files/"));
}

test "public clients construct quiet request contexts" {
    const client = try Client.init(std.testing.allocator, std.testing.io, .{
        .api_key = "key",
    });
    const context = client.requestContext();

    try std.testing.expect(!context.traffic_log_options.print_request);
    try std.testing.expect(!context.traffic_log_options.print_response);
}

test "public generation options convert to the existing wire request" {
    const request_json = try buildCountTokensRequest(std.testing.allocator, .{
        .prompt = "My fair lady",
        .output_options = .{
            .aspect_ratio = .r16_9,
            .image_size = .k2,
        },
        .grounding_options = .{ .web = true, .image = true },
        .thinking_options = .{ .level = .minimal, .include_thoughts = true },
        .safety_options = .{ .threshold = .off },
        .generation_options = .{
            .max_output_tokens = 4096,
            .temperature = 0.7,
            .top_p = 0.95,
            .seed = -42,
            .presence_penalty = -1.5,
            .frequency_penalty = 1.25,
            .response_logprobs = true,
            .logprobs = 5,
            .stop_sequences = &.{ "END", "STOP" },
        },
        .request_options = .{
            .system_instruction = "Use editorial lighting.",
            .cached_content = "cachedContents/brand",
            .service_tier = .priority,
            .store = false,
        },
    });
    defer std.testing.allocator.free(request_json);

    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"aspectRatio\":\"ASPECT_RATIO_SIXTEEN_BY_NINE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"imageSize\":\"IMAGE_SIZE_TWO_K\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"webSearch\":{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"imageSearch\":{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"thinkingLevel\":\"minimal\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"includeThoughts\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"threshold\":\"OFF\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"maxOutputTokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"temperature\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"topP\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"seed\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"presencePenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"frequencyPenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"responseLogprobs\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"logprobs\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"stopSequences\":[\"END\",\"STOP\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"systemInstruction\":{\"parts\":[{\"text\":\"Use editorial lighting.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"cachedContent\":\"cachedContents/brand\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"serviceTier\":\"priority\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"store\":false") != null);
}

test "edit request validation returns edit-specific errors" {
    const base = UploadedImage{ .name = "files/base", .mime = .jpeg };
    const uri_prefix = "https://generativelanguage.googleapis.com/v1beta/";

    try std.testing.expectError(error.EmptyPrompt, validateEditRequest(.{
        .prompt = "",
        .base = base,
    }));
    try std.testing.expectError(error.PromptTooLong, validateEditRequest(.{
        .prompt = "x" ** (api.max_generate_text_part_bytes + 1),
        .base = base,
    }));
    try std.testing.expectError(error.InvalidBaseFileName, validateEditRequest(.{
        .prompt = "x",
        .base = .{ .name = "base", .mime = .jpeg },
    }));
    try std.testing.expectError(error.FileUriTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = .{
            .name = "files/" ++ "a" ** api.max_generate_file_uri_bytes,
            .mime = .jpeg,
        },
    }));
    const max_file_name =
        "files/" ++ "a" ** (api.max_generate_file_uri_bytes - uri_prefix.len - "files/".len);
    const max_label_reference = [_]Reference{.{
        .role = .image,
        .label = "A" ** max_edit_reference_label_bytes,
        .image = .{ .name = max_file_name, .mime = .webp },
    }};
    try validateEditRequest(.{
        .prompt = "x",
        .base = .{ .name = max_file_name, .mime = .png },
        .references = &max_label_reference,
    });

    const invalid_name = [_]Reference{.{
        .role = .image,
        .label = "IMAGE_A",
        .image = .{ .name = "invalid", .mime = .png },
    }};
    try std.testing.expectError(error.InvalidReferenceFileName, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &invalid_name,
    }));
    const long_reference_uri = [_]Reference{.{
        .role = .image,
        .label = "IMAGE_A",
        .image = .{
            .name = "files/" ++ "a" ** api.max_generate_file_uri_bytes,
            .mime = .png,
        },
    }};
    try std.testing.expectError(error.FileUriTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &long_reference_uri,
    }));
    const invalid_label = [_]Reference{.{
        .role = .image,
        .label = "image-a",
        .image = .{ .name = "files/a", .mime = .png },
    }};
    try std.testing.expectError(error.InvalidReferenceLabel, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &invalid_label,
    }));
    const long_label = [_]Reference{.{
        .role = .image,
        .label = "A" ** (max_edit_reference_label_bytes + 1),
        .image = .{ .name = "files/a", .mime = .png },
    }};
    try std.testing.expectError(error.InvalidReferenceLabel, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &long_label,
    }));
    const reserved_label = [_]Reference{.{
        .role = .image,
        .label = "BASE_IMAGE",
        .image = .{ .name = "files/a", .mime = .png },
    }};
    try std.testing.expectError(error.ReservedReferenceLabel, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &reserved_label,
    }));
    const duplicate_labels = [_]Reference{
        .{
            .role = .image,
            .label = "IMAGE_A",
            .image = .{ .name = "files/a", .mime = .png },
        },
        .{
            .role = .style,
            .label = "IMAGE_A",
            .image = .{ .name = "files/b", .mime = .webp },
        },
    };
    try std.testing.expectError(error.DuplicateReferenceLabel, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &duplicate_labels,
    }));
}

test "edit request validation enforces image and constraint counts" {
    const base = UploadedImage{ .name = "files/base", .mime = .jpeg };
    var references: [max_edit_references + 1]Reference = undefined;
    for (&references, 0..) |*reference, index| {
        reference.* = .{
            .role = .style,
            .label = switch (index) {
                0 => "A",
                1 => "B",
                2 => "C",
                3 => "D",
                4 => "E",
                5 => "F",
                6 => "G",
                7 => "H",
                8 => "I",
                9 => "J",
                10 => "K",
                11 => "L",
                12 => "M",
                13 => "N",
                else => unreachable,
            },
            .image = .{ .name = "files/reference", .mime = .jpeg },
        };
    }
    try std.testing.expectError(error.TooManyReferences, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .references = &references,
    }));

    var characters: [max_edit_character_images]Reference = undefined;
    for (&characters, 0..) |*reference, index| {
        reference.* = .{
            .role = .character,
            .label = switch (index) {
                0 => "A",
                1 => "B",
                2 => "C",
                3 => "D",
                else => unreachable,
            },
            .image = .{ .name = "files/character", .mime = .jpeg },
        };
    }
    try std.testing.expectError(error.TooManyCharacterImages, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .base_role = .character,
        .references = &characters,
    }));

    var objects: [max_edit_object_images]Reference = undefined;
    for (&objects, 0..) |*reference, index| {
        reference.* = .{
            .role = .object,
            .label = switch (index) {
                0 => "A",
                1 => "B",
                2 => "C",
                3 => "D",
                4 => "E",
                5 => "F",
                6 => "G",
                7 => "H",
                8 => "I",
                9 => "J",
                else => unreachable,
            },
            .image = .{ .name = "files/object", .mime = .png },
        };
    }
    try std.testing.expectError(error.TooManyObjectImages, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .base_role = .object,
        .references = &objects,
    }));

    const too_many = [_][]const u8{"x"} ** (max_edit_preserve_constraints + 1);
    try std.testing.expectError(error.TooManyPreserveConstraints, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .preserves = &too_many,
    }));
    try std.testing.expectError(error.TooManyDoNotConstraints, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .do_nots = &too_many,
    }));
}

test "edit request validation enforces constraint and aggregate bounds" {
    const base = UploadedImage{ .name = "files/base", .mime = .jpeg };
    try std.testing.expectError(error.EmptyPreserveConstraint, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .preserves = &.{""},
    }));
    try std.testing.expectError(error.PreserveConstraintTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .preserves = &.{"x" ** (api.max_generate_text_part_bytes + 1)},
    }));
    try std.testing.expectError(error.EmptyDoNotConstraint, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .do_nots = &.{""},
    }));
    try std.testing.expectError(error.DoNotConstraintTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .do_nots = &.{"x" ** (api.max_generate_text_part_bytes + 1)},
    }));
    try std.testing.expectError(error.EditTaskTooLong, validateEditRequest(.{
        .prompt = "x" ** api.max_generate_text_part_bytes,
        .base = base,
    }));

    const oversized_stop = try std.testing.allocator.alloc(
        u8,
        api.max_generate_request_field_bytes,
    );
    defer std.testing.allocator.free(oversized_stop);
    @memset(oversized_stop, 'x');
    try std.testing.expectError(error.RequestTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .stop_sequences = &.{oversized_stop} },
    }));
}

test "edit request validation maps shared option errors" {
    const base = UploadedImage{ .name = "files/base", .mime = .jpeg };
    try std.testing.expectError(error.InvalidMaxOutputTokens, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .max_output_tokens = 0 },
    }));
    try std.testing.expectError(error.InvalidTemperature, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .temperature = std.math.inf(f64) },
    }));
    try std.testing.expectError(error.InvalidTopP, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .top_p = -0.1 },
    }));
    try std.testing.expectError(error.InvalidPresencePenalty, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .presence_penalty = 2.0 },
    }));
    try std.testing.expectError(error.InvalidFrequencyPenalty, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .frequency_penalty = -2.1 },
    }));
    try std.testing.expectError(error.LogprobsRequireResponseLogprobs, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .logprobs = 1 },
    }));
    try std.testing.expectError(error.InvalidLogprobs, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .response_logprobs = true, .logprobs = 21 },
    }));
    try std.testing.expectError(error.TooManyStopSequences, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .stop_sequences = &.{ "1", "2", "3", "4", "5", "6" } },
    }));
    try std.testing.expectError(error.EmptyStopSequence, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .stop_sequences = &.{""} },
    }));
    try std.testing.expectError(error.DuplicateStopSequence, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .generation_options = .{ .stop_sequences = &.{ "same", "same" } },
    }));
    try std.testing.expectError(error.EmptySystemInstruction, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .request_options = .{ .system_instruction = "" },
    }));
    try std.testing.expectError(error.SystemInstructionTooLong, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .request_options = .{
            .system_instruction = "x" ** (api.max_generate_text_part_bytes + 1),
        },
    }));
    try std.testing.expectError(error.InvalidCachedContentName, validateEditRequest(.{
        .prompt = "x",
        .base = base,
        .request_options = .{ .cached_content = "invalid" },
    }));
}

test "public edit types convert every MIME and role through existing serializer" {
    const roles = [_]ReferenceRole{
        .scene,
        .character,
        .object,
        .style,
        .pose,
        .composition,
        .background,
        .texture,
        .image,
    };
    const labels = [_][]const u8{
        "SCENE_A",
        "CHARACTER_A",
        "OBJECT_A",
        "STYLE_A",
        "POSE_A",
        "COMPOSITION_A",
        "BACKGROUND_A",
        "TEXTURE_A",
        "IMAGE_A",
    };
    var references: [roles.len]Reference = undefined;
    for (&references, roles, labels, 0..) |*reference, role, label, index| {
        reference.* = .{
            .role = role,
            .label = label,
            .image = .{
                .name = "files/reference",
                .mime = switch (index % 3) {
                    0 => .jpeg,
                    1 => .png,
                    2 => .webp,
                    else => unreachable,
                },
            },
        };
    }

    const request_json = try buildEditCountTokensRequest(std.testing.allocator, .{
        .prompt = "Apply the references",
        .base = .{ .name = "files/base", .mime = .webp },
        .references = &references,
        .preserves = &.{"identity"},
        .do_nots = &.{"change crop"},
    });
    defer std.testing.allocator.free(request_json);

    try std.testing.expect(std.mem.startsWith(
        u8,
        request_json,
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image\",",
    ));
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"mime_type\":\"image/jpeg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"mime_type\":\"image/png\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"mime_type\":\"image/webp\"") != null);
    for (labels) |label| {
        try std.testing.expect(std.mem.indexOf(u8, request_json, label) != null);
    }
    try std.testing.expect(std.mem.indexOf(u8, request_json, "PRESERVE FROM BASE_IMAGE") != null);
    try std.testing.expect(std.mem.indexOf(u8, request_json, "DO NOT") != null);
}

test "prepared Batch entry owns escaped key and exact request bytes" {
    const gpa = std.testing.allocator;
    const generate_request_json =
        "{\"contents\": [{\"parts\": [{\"text\": \"exact bytes\"}]}]}";
    var request = PreparedBatchRequest{
        .generate_request_json = try gpa.dupe(u8, generate_request_json),
        .total_tokens = 37,
    };
    defer request.deinit(gpa);

    var entry = try prepareBatchEntry(gpa, "hero-\"001", request);
    defer entry.deinit(gpa);

    try std.testing.expectEqualStrings("hero-\"001", entry.key);
    try std.testing.expectEqualStrings(
        "{\"key\":\"hero-\\\"001\",\"request\":" ++ generate_request_json ++ "}",
        entry.jsonl_record,
    );
    try std.testing.expect(entry.jsonl_record[entry.jsonl_record.len - 1] != '\n');
    try std.testing.expectEqual(@as(u64, 37), entry.total_tokens);
}

test "prepared Batch entry enforces complete serialized record limit" {
    const gpa = std.testing.allocator;
    var request = PreparedBatchRequest{
        .generate_request_json = try gpa.dupe(u8, "{}"),
        .total_tokens = 1,
    };
    defer request.deinit(gpa);

    const overhead = "{\"key\":\"".len + "\",\"request\":".len +
        request.generate_request_json.len + "}".len;
    std.debug.assert(overhead < max_batch_entry_bytes);

    const exact_key = try gpa.alloc(u8, max_batch_entry_bytes - overhead);
    defer gpa.free(exact_key);
    @memset(exact_key, 'a');
    var exact = try prepareBatchEntry(gpa, exact_key, request);
    defer exact.deinit(gpa);
    try std.testing.expectEqual(max_batch_entry_bytes, exact.jsonl_record.len);

    const oversized_key = try gpa.alloc(u8, exact_key.len + 1);
    defer gpa.free(oversized_key);
    @memset(oversized_key, 'a');
    try std.testing.expectError(
        error.BatchEntryTooLong,
        prepareBatchEntry(gpa, oversized_key, request),
    );
}

test "prepared Batch request retains exact bytes on count success" {
    const gpa = std.testing.allocator;
    const generate_request_json = try gpa.dupe(u8, "{\"contents\": []}");
    const original_pointer = generate_request_json.ptr;
    var outcome = preparedBatchRequestOutcomeFromCountTokens(
        gpa,
        generate_request_json,
        .{ .success = .{ .total_tokens = 19 } },
    );

    switch (outcome) {
        .success => |*request| {
            defer request.deinit(gpa);
            try std.testing.expectEqual(original_pointer, request.generate_request_json.ptr);
            try std.testing.expectEqualStrings(
                "{\"contents\": []}",
                request.generate_request_json,
            );
            try std.testing.expectEqual(@as(u64, 19), request.total_tokens);
        },
        .api_failure, .response_decoding_failure => return error.UnexpectedBatchPreparationFailure,
    }
}

test "prepared Batch request cleans retained bytes on count failures" {
    const gpa = std.testing.allocator;
    var api_failure_outcome = preparedBatchRequestOutcomeFromCountTokens(
        gpa,
        try gpa.dupe(u8, "{}"),
        .{ .api_failure = .{
            .status = .bad_request,
            .body = try gpa.dupe(u8, "{\"error\":\"complete body\"}"),
        } },
    );
    switch (api_failure_outcome) {
        .api_failure => |*failure| {
            try std.testing.expectEqualStrings("{\"error\":\"complete body\"}", failure.body);
            failure.deinit(gpa);
        },
        .success, .response_decoding_failure => return error.UnexpectedBatchPreparationOutcome,
    }

    var decoding_outcome = preparedBatchRequestOutcomeFromCountTokens(
        gpa,
        try gpa.dupe(u8, "{}"),
        .{ .response_decoding_failure = error.MissingTotalTokens },
    );
    switch (decoding_outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.MissingTotalTokens, err);
        },
        .success => |*request| {
            request.deinit(gpa);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(gpa);
            return error.UnexpectedApiFailure;
        },
    }
}

test "prepared Batch public outcome surfaces malformed successes as Zig errors" {
    try std.testing.expectError(
        error.MissingTotalTokens,
        preparedBatchEntryPublicOutcome(
            std.testing.allocator,
            "key",
            .{ .response_decoding_failure = error.MissingTotalTokens },
        ),
    );
}

test "generation response classification transfers images and metadata" {
    const json =
        \\{
        \\  "responseId": "response-123",
        \\  "candidates": [
        \\    {
        \\      "index": 99,
        \\      "content": {
        \\        "parts": [
        \\          {"text": "planning", "thought": true},
        \\          {"inlineData": {"mimeType": "image/png", "data": "AQID"}},
        \\          {"text": "caption"}
        \\        ]
        \\      }
        \\    },
        \\    {
        \\      "content": {
        \\        "parts": [
        \\          {"inlineData": {}, "thought": true},
        \\          {"inlineData": {"mimeType": "image/jpeg", "data": "BAUG"}},
        \\          {"inlineData": {"mimeType": "image/webp", "data": "BwgJ"}}
        \\        ]
        \\      }
        \\    }
        \\  ],
        \\  "usageMetadata": {"serviceTier": "standard"}
        \\}
    ;
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, json),
    };
    var outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &response,
    );

    switch (outcome) {
        .success => |*result| {
            defer result.deinit(std.testing.allocator);

            try std.testing.expectEqualStrings("response-123", result.response_id);
            try std.testing.expectEqual(@as(?ServiceTier, .standard), result.reported_service_tier);
            try std.testing.expectEqual(@as(usize, 3), result.images.len);

            try std.testing.expectEqual(@as(usize, 0), result.images[0].candidate_position);
            try std.testing.expectEqual(@as(usize, 1), result.images[0].part_position);
            try std.testing.expectEqual(OutputMime.png, result.images[0].mime);
            try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, result.images[0].bytes);

            try std.testing.expectEqual(@as(usize, 1), result.images[1].candidate_position);
            try std.testing.expectEqual(@as(usize, 1), result.images[1].part_position);
            try std.testing.expectEqual(OutputMime.jpeg, result.images[1].mime);
            try std.testing.expectEqualSlices(u8, &.{ 4, 5, 6 }, result.images[1].bytes);

            try std.testing.expectEqual(@as(usize, 1), result.images[2].candidate_position);
            try std.testing.expectEqual(@as(usize, 2), result.images[2].part_position);
            try std.testing.expectEqual(OutputMime.webp, result.images[2].mime);
            try std.testing.expectEqualSlices(u8, &.{ 7, 8, 9 }, result.images[2].bytes);
        },
        .api_failure, .response_decoding_failure => return error.UnexpectedGenerationFailure,
    }
}

test "generation result conversion transfers image bytes without copying" {
    var files = api.GeneratedFiles{
        .response_id = try std.testing.allocator.dupe(u8, "response"),
        .items = try std.testing.allocator.alloc(api.GeneratedFile, 1),
        .reported_service_tier_name = try std.testing.allocator.dupe(u8, "priority"),
    };
    files.items[0] = .{
        .candidate_index = 2,
        .part_index = 4,
        .mime = .webp,
        .bytes = try std.testing.allocator.dupe(u8, "image bytes"),
    };
    const original_bytes = files.items[0].bytes.ptr;

    var result = try generationResultFromGeneratedFiles(
        std.testing.allocator,
        &files,
    );
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(original_bytes, result.images[0].bytes.ptr);
    try std.testing.expectEqual(@as(?ServiceTier, .priority), result.reported_service_tier);
}

test "generation response supports absent service tier" {
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}",
        ),
    };
    var outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &response,
    );

    switch (outcome) {
        .success => |*result| {
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(?ServiceTier, null), result.reported_service_tier);
        },
        .api_failure, .response_decoding_failure => return error.UnexpectedGenerationFailure,
    }
}

test "generation response rejects unknown service tier and cleans up" {
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}],\"usageMetadata\":{\"serviceTier\":\"future\"}}",
        ),
    };

    var outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &response,
    );
    switch (outcome) {
        .success => |*result| {
            result.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.UnsupportedServiceTier, err);
        },
    }
}

test "generation response accepts every successful HTTP status class" {
    const json =
        "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}";

    var code: u16 = 200;
    while (code <= 299) : (code += 1) {
        var response = api.HttpResponse{
            .status = @enumFromInt(code),
            .body = try std.testing.allocator.dupe(u8, json),
        };
        var outcome = generatedContentOutcomeFromResponse(
            std.testing.allocator,
            &response,
        );
        switch (outcome) {
            .success => |*result| result.deinit(std.testing.allocator),
            .api_failure, .response_decoding_failure => return error.UnexpectedGenerationFailure,
        }
    }
}

test "generation response supports recognized and absent service tiers" {
    const bodies = .{
        .{
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}],\"usageMetadata\":{\"serviceTier\":\"standard\"}}",
            @as(?ServiceTier, .standard),
        },
        .{
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}",
            @as(?ServiceTier, null),
        },
    };

    inline for (bodies) |entry| {
        var response = api.HttpResponse{
            .status = .ok,
            .body = try std.testing.allocator.dupe(u8, entry[0]),
        };
        var outcome = generatedContentOutcomeFromResponse(
            std.testing.allocator,
            &response,
        );
        switch (outcome) {
            .success => |*result| {
                defer result.deinit(std.testing.allocator);
                try std.testing.expectEqual(entry[1], result.reported_service_tier);
            },
            .api_failure, .response_decoding_failure => return error.UnexpectedGenerationFailure,
        }
    }
}

test "generation response rejects malformed service tier metadata" {
    const json =
        "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}],\"usageMetadata\":{\"serviceTier\":{}}}";

    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, json),
    };
    var outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &response,
    );
    switch (outcome) {
        .response_decoding_failure => {},
        .success => |*result| {
            result.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
    }
}

test "generation response classification preserves API failure body" {
    var response = api.HttpResponse{
        .status = .service_unavailable,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"complete body\"}"),
    };
    var outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &response,
    );

    switch (outcome) {
        .success => return error.UnexpectedSuccess,
        .api_failure => |*failure| {
            try std.testing.expectEqual(std.http.Status.service_unavailable, failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"complete body\"}", failure.body);
            failure.deinit(std.testing.allocator);
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

test "generation response frees malformed and unsupported successes" {
    var malformed = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, "{"),
    };
    var malformed_outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &malformed,
    );
    switch (malformed_outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.UnexpectedEndOfInput, err);
        },
        .success => |*result| {
            result.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
    }

    var unsupported = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{}]}}]}",
        ),
    };
    var unsupported_outcome = generatedContentOutcomeFromResponse(
        std.testing.allocator,
        &unsupported,
    );
    switch (unsupported_outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.UnsupportedPart, err);
        },
        .success => |*result| {
            result.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
    }
}

test "ApiFailure owns and frees the complete body" {
    var failure = ApiFailure{
        .status = .bad_request,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"bad request\"}"),
    };
    try std.testing.expectEqualStrings("{\"error\":\"bad request\"}", failure.body);
    failure.deinit(std.testing.allocator);
}

test "count token response classification decodes success" {
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"totalTokens\":42,\"cachedContentTokenCount\":7}",
        ),
    };
    const outcome = countTokensOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => |result| {
            try std.testing.expectEqual(@as(u64, 42), result.total_tokens);
            try std.testing.expectEqual(@as(?u64, 7), result.cached_content_token_count);
        },
        .api_failure => return error.UnexpectedApiFailure,
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

test "count token response classification accepts every 2xx status" {
    var code: u16 = 200;
    while (code <= 299) : (code += 1) {
        var response = api.HttpResponse{
            .status = @enumFromInt(code),
            .body = try std.testing.allocator.dupe(u8, "{\"totalTokens\":1}"),
        };
        const outcome = countTokensOutcomeFromResponse(std.testing.allocator, &response);
        switch (outcome) {
            .success => |result| try std.testing.expectEqual(@as(u64, 1), result.total_tokens),
            .api_failure, .response_decoding_failure => return error.UnexpectedCountTokensFailure,
        }
    }
}

test "count token response classification preserves API failure body" {
    var response = api.HttpResponse{
        .status = .too_many_requests,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"quota\"}"),
    };
    var outcome = countTokensOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => return error.UnexpectedSuccess,
        .api_failure => |*failure| {
            try std.testing.expectEqual(std.http.Status.too_many_requests, failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"quota\"}", failure.body);
            failure.deinit(std.testing.allocator);
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

test "count token response classification frees malformed success body" {
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, "{}"),
    };

    var outcome = countTokensOutcomeFromResponse(std.testing.allocator, &response);
    switch (outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.MissingTotalTokens, err);
        },
        .success => return error.UnexpectedSuccess,
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
    }
}
