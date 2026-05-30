//! Gemini native image generation request and response handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");

const live_prompt = "My fair lady";

pub const CountTokensResult = api.CountTokensResult;
pub const decodeCountTokensResponse = api.decodeCountTokensResponse;

pub fn generateContent(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
    safety_options: ?api.SafetyOptions,
    generation_options: api.GenerationOptions,
    request_options: api.RequestOptions,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);
    api.assertValidRequestOptions(request_options);

    const request_json = try buildGenerateRequest(
        gpa,
        prompt,
        output_options,
        grounding_options,
        thinking_options,
        safety_options,
        generation_options,
        request_options,
    );
    defer gpa.free(request_json);

    return api.postGenerateContentJson(gpa, io, api_key, .nano2, request_json);
}

pub fn countGenerateContentRequestTokens(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
    safety_options: ?api.SafetyOptions,
    generation_options: api.GenerationOptions,
    request_options: api.RequestOptions,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);
    api.assertValidRequestOptions(request_options);

    const request_json = try buildCountTokensRequest(
        gpa,
        prompt,
        output_options,
        grounding_options,
        thinking_options,
        safety_options,
        generation_options,
        request_options,
    );
    defer gpa.free(request_json);

    return api.postCountTokensJson(gpa, io, api_key, .nano2, request_json);
}

pub fn buildGenerateRequest(
    gpa: std.mem.Allocator,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
    safety_options: ?api.SafetyOptions,
    generation_options: api.GenerationOptions,
    request_options: api.RequestOptions,
) ![]u8 {
    assert(prompt.len > 0);
    api.assertValidRequestOptions(request_options);

    const parts = [_]api.GeneratePart{.{ .text = prompt }};
    const contents = [_]api.GenerateContent{.{ .parts = &parts }};
    return api.buildGenerateContentRequestJson(gpa, &contents, .{
        .output_options = output_options,
        .grounding_options = grounding_options,
        .thinking_options = thinking_options,
        .safety_options = safety_options,
        .generation_options = generation_options,
        .request_options = request_options,
    });
}

pub fn buildCountTokensRequest(
    gpa: std.mem.Allocator,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
    safety_options: ?api.SafetyOptions,
    generation_options: api.GenerationOptions,
    request_options: api.RequestOptions,
) ![]u8 {
    assert(prompt.len > 0);
    api.assertValidRequestOptions(request_options);

    const generate_request_json = try buildGenerateRequest(
        gpa,
        prompt,
        output_options,
        grounding_options,
        thinking_options,
        safety_options,
        generation_options,
        request_options,
    );
    defer gpa.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(gpa, .nano2, generate_request_json);
}

const expected_block_none_safety_settings_json =
    "\"safetySettings\":[{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_SEXUALLY_EXPLICIT\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_DANGEROUS_CONTENT\",\"threshold\":\"BLOCK_NONE\"}]";

test "buildGenerateRequest uses fixed Nano Banana 2 image request" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}",
        request,
    );
}

test "buildGenerateRequest includes image output options" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{
        .aspect_ratio = .r16_9,
        .image_size = .k2,
    }, .{}, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"],\"responseFormat\":{\"image\":{\"aspectRatio\":\"ASPECT_RATIO_SIXTEEN_BY_NINE\",\"imageSize\":\"IMAGE_SIZE_TWO_K\"}}}}",
        request,
    );
}

test "buildGenerateRequest includes partial image output options" {
    const gpa = std.testing.allocator;
    const aspect_request = try buildGenerateRequest(gpa, "My fair lady", .{
        .aspect_ratio = .r9_16,
    }, .{}, .{}, null, .{}, .{});
    defer gpa.free(aspect_request);

    try std.testing.expect(std.mem.indexOf(u8, aspect_request, "\"aspectRatio\":\"ASPECT_RATIO_NINE_BY_SIXTEEN\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, aspect_request, "\"imageSize\"") == null);

    const size_request = try buildGenerateRequest(gpa, "My fair lady", .{
        .image_size = .px512,
    }, .{}, .{}, null, .{}, .{});
    defer gpa.free(size_request);

    try std.testing.expect(std.mem.indexOf(u8, size_request, "\"imageSize\":\"IMAGE_SIZE_FIVE_TWELVE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, size_request, "\"aspectRatio\"") == null);
}

test "buildGenerateRequest includes web grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .web = true,
    }, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"tools\":[{\"google_search\":{}}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}",
        request,
    );
}

test "buildGenerateRequest includes image grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .image = true,
    }, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"imageSearch\":{}}}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"webSearch\"") == null);
}

test "buildGenerateRequest includes combined grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .web = true,
        .image = true,
    }, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"webSearch\":{},\"imageSearch\":{}}}}]") != null);
}

test "buildGenerateRequest includes thinking config" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{
        .level = .high,
        .include_thoughts = true,
    }, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"thinkingConfig\":{\"thinkingLevel\":\"high\",\"includeThoughts\":true}") != null);
}

test "buildGenerateRequest includes advanced generation options" {
    const gpa = std.testing.allocator;
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

    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{}, null, generation_options, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"maxOutputTokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"temperature\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"topP\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"seed\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"presencePenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"frequencyPenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseLogprobs\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"logprobs\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"stopSequences\":[\"END\",\"STOP\"]") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateRequest applies safety threshold to all categories" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{}, api.SafetyOptions{
        .threshold = .off,
    }, .{}, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"safetySettings\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"threshold\":\"OFF\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"threshold\":\"OFF\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_SEXUALLY_EXPLICIT\",\"threshold\":\"OFF\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_DANGEROUS_CONTENT\",\"threshold\":\"OFF\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"threshold\":\"BLOCK_NONE\"") == null);
}

test "buildGenerateRequest emits block none safety settings when requested" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{}, api.SafetyOptions{
        .threshold = .block_none,
    }, .{}, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, expected_block_none_safety_settings_json) != null);
}

test "buildGenerateRequest includes request-level controls" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{}, null, .{}, .{
        .system_instruction = "Use a precise editorial style.",
        .cached_content = "cachedContents/brand",
        .service_tier = .priority,
        .store = false,
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"systemInstruction\":{\"parts\":[{\"text\":\"Use a precise editorial style.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"cachedContent\":\"cachedContents/brand\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"serviceTier\":\"priority\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"store\":false") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildCountTokensRequest wraps fixed generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, "My fair lady", .{}, .{}, .{}, null, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}}",
        request,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildCountTokensRequest wraps request-level controls inside generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, "My fair lady", .{}, .{}, .{}, null, .{}, .{
        .system_instruction = "Use a precise editorial style.",
        .service_tier = .standard,
        .store = true,
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"generateContentRequest\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"model\":\"models/gemini-3.1-flash-image-preview\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"systemInstruction\":{\"parts\":[{\"text\":\"Use a precise editorial style.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"serviceTier\":\"standard\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"store\":true") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "live API generateContent request shape is valid" {
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

    var generation_options = api.GenerationOptions{
        .max_output_tokens = 4096,
        .temperature = 0.7,
        .top_p = 0.95,
        .seed = 42,
        .presence_penalty = 0.0,
        .frequency_penalty = 0.0,
        .response_logprobs = true,
        .logprobs = 1,
    };
    generation_options.appendStopSequence("END");

    var response = countGenerateContentRequestTokens(
        gpa,
        std.testing.io,
        api_key,
        live_prompt,
        .{
            .aspect_ratio = .r16_9,
            .image_size = .k2,
        },
        .{
            .web = true,
            .image = true,
        },
        .{
            .level = .minimal,
            .include_thoughts = true,
        },
        null,
        generation_options,
        .{
            .system_instruction = "Follow the user's visual request exactly.",
            .service_tier = .standard,
            .store = false,
        },
    ) catch |err| {
        std.debug.print("error: countTokens request failed: {s}\n", .{@errorName(err)});
        return err;
    };
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: countTokens request failed with HTTP {d}\n{s}\n",
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
