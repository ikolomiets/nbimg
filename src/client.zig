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
};

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
    const generation_options = wireGenerationOptions(request.generation_options);
    const generate_request_json = try gen.buildGenerateRequest(
        allocator,
        request.prompt,
        wireImageOutputOptions(request.output_options),
        .{
            .web = request.grounding_options.web,
            .image = request.grounding_options.image,
        },
        wireThinkingOptions(request.thinking_options),
        if (request.safety_options) |options| wireSafetyOptions(options) else null,
        generation_options,
        wireRequestOptions(request.request_options),
    );
    defer allocator.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(
        allocator,
        .nano2,
        generate_request_json,
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
