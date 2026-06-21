//! Supported typed client API for Gemini image-generation workflows.

const std = @import("std");
const api = @import("api.zig");
const gen = @import("gen.zig");

const default_request_timeout = std.Io.Duration.fromSeconds(180);

/// Configures a client with an explicit borrowed Gemini API key and timeout.
///
/// - `api_key` remains caller-owned and must outlive the client and its requests.
/// - The value owns no resources and allocates nothing.
pub const ClientOptions = struct {
    api_key: []const u8,
    timeout: std.Io.Duration = default_request_timeout,
};

/// Owns a completed non-success HTTP response body.
pub const ApiFailure = struct {
    status: std.http.Status,
    body: []u8,

    /// Frees the response body and invalidates the value.
    pub fn deinit(failure: *ApiFailure, allocator: std.mem.Allocator) void {
        allocator.free(failure.body);
        failure.* = undefined;
    }
};

/// Represents either a decoded operation result or a completed API failure.
pub fn Outcome(comptime T: type) type {
    return union(enum) {
        success: T,
        api_failure: ApiFailure,
    };
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

/// Holds decoded token counts without owning heap storage.
pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
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

        const request_json = try buildCountTokensRequest(client.allocator, request);
        defer client.allocator.free(request_json);

        const context = api.RequestContext{
            .gpa = client.allocator,
            .io = client.io,
            .api_key = client.api_key,
            .timeout = client.timeout,
        };
        var response = try api.postCountTokensJson(&context, .nano2, request_json);
        return countTokensOutcomeFromResponse(client.allocator, &response);
    }

    /// Generates and returns owned decoded images for a borrowed request.
    ///
    /// Completed non-success HTTP responses are returned as owned API failures.
    pub fn generate(
        client: *const Client,
        request: GenerationRequest,
    ) !Outcome(GenerationResult) {
        const context = api.RequestContext{
            .gpa = client.allocator,
            .io = client.io,
            .api_key = client.api_key,
            .timeout = client.timeout,
        };
        return generateWithContext(&context, request);
    }
};

/// Generates images using an explicit internal request context.
///
/// This seam allows CLI callers to supply traffic logging without changing the
/// supported public client contract.
pub fn generateWithContext(
    context: *const api.RequestContext,
    request: GenerationRequest,
) !Outcome(GenerationResult) {
    try validateGenerationRequest(request);

    const request_json = try buildGenerateRequest(context.gpa, request);
    defer context.gpa.free(request_json);

    var response = try api.postGenerateContentJson(context, .nano2, request_json);
    return generationOutcomeFromResponse(context.gpa, &response);
}

fn countTokensOutcomeFromResponse(
    allocator: std.mem.Allocator,
    response: *api.HttpResponse,
) !Outcome(CountTokensResult) {
    if (response.status.class() != .success) {
        const failure = ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    defer response.deinit(allocator);

    const result = try api.decodeCountTokensResponse(allocator, response.body);
    return .{ .success = .{
        .total_tokens = result.total_tokens,
        .cached_content_token_count = result.cached_content_token_count,
    } };
}

fn generationOutcomeFromResponse(
    allocator: std.mem.Allocator,
    response: *api.HttpResponse,
) !Outcome(GenerationResult) {
    if (response.status.class() != .success) {
        const failure = ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    defer response.deinit(allocator);

    var files = try api.decodeGeneratedFiles(allocator, response.body);
    errdefer files.deinit(allocator);

    return .{ .success = try generationResultFromGeneratedFiles(allocator, &files) };
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

    const generation_options = request.generation_options;
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

    if (request.request_options.system_instruction) |system_instruction| {
        if (system_instruction.len == 0) return error.EmptySystemInstruction;
        if (system_instruction.len > api.max_generate_text_part_bytes) {
            return error.SystemInstructionTooLong;
        }
    }
    if (request.request_options.cached_content) |cached_content| {
        if (!api.isCanonicalCachedContentName(cached_content)) {
            return error.InvalidCachedContentName;
        }
    }

    var field_bytes = request.prompt.len;
    if (request.request_options.system_instruction) |value| field_bytes +|= value.len;
    if (request.request_options.cached_content) |value| field_bytes +|= value.len;
    for (generation_options.stop_sequences) |value| field_bytes +|= value.len;
    if (field_bytes > api.max_generate_request_field_bytes) return error.RequestTooLong;
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
    var outcome = try generationOutcomeFromResponse(std.testing.allocator, &response);

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
        .api_failure => return error.UnexpectedApiFailure,
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

    var result = try generationResultFromGeneratedFiles(std.testing.allocator, &files);
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
    var outcome = try generationOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => |*result| {
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(?ServiceTier, null), result.reported_service_tier);
        },
        .api_failure => return error.UnexpectedApiFailure,
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

    try std.testing.expectError(
        error.UnsupportedServiceTier,
        generationOutcomeFromResponse(std.testing.allocator, &response),
    );
}

test "generation response classification preserves API failure body" {
    var response = api.HttpResponse{
        .status = .service_unavailable,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"complete body\"}"),
    };
    var outcome = try generationOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => return error.UnexpectedSuccess,
        .api_failure => |*failure| {
            try std.testing.expectEqual(std.http.Status.service_unavailable, failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"complete body\"}", failure.body);
            failure.deinit(std.testing.allocator);
        },
    }
}

test "generation response frees malformed and unsupported successes" {
    var malformed = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, "{"),
    };
    try std.testing.expectError(
        error.UnexpectedEndOfInput,
        generationOutcomeFromResponse(std.testing.allocator, &malformed),
    );

    var unsupported = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"responseId\":\"response\",\"candidates\":[{\"content\":{\"parts\":[{}]}}]}",
        ),
    };
    try std.testing.expectError(
        error.UnsupportedPart,
        generationOutcomeFromResponse(std.testing.allocator, &unsupported),
    );
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
    const outcome = try countTokensOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => |result| {
            try std.testing.expectEqual(@as(u64, 42), result.total_tokens);
            try std.testing.expectEqual(@as(?u64, 7), result.cached_content_token_count);
        },
        .api_failure => return error.UnexpectedApiFailure,
    }
}

test "count token response classification preserves API failure body" {
    var response = api.HttpResponse{
        .status = .too_many_requests,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"quota\"}"),
    };
    var outcome = try countTokensOutcomeFromResponse(std.testing.allocator, &response);

    switch (outcome) {
        .success => return error.UnexpectedSuccess,
        .api_failure => |*failure| {
            try std.testing.expectEqual(std.http.Status.too_many_requests, failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"quota\"}", failure.body);
            failure.deinit(std.testing.allocator);
        },
    }
}

test "count token response classification frees malformed success body" {
    var response = api.HttpResponse{
        .status = .ok,
        .body = try std.testing.allocator.dupe(u8, "{}"),
    };

    try std.testing.expectError(
        error.MissingTotalTokens,
        countTokensOutcomeFromResponse(std.testing.allocator, &response),
    );
}
