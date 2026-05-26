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
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);

    const request_json = try buildGenerateRequest(gpa, prompt, output_options, grounding_options, thinking_options);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, api.generateContentUrl(.nano2), request_json);
}

pub fn countGenerateContentRequestTokens(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);

    const request_json = try buildCountTokensRequest(gpa, prompt, output_options, grounding_options, thinking_options);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, api.countTokensUrl(.nano2), request_json);
}

pub fn buildGenerateRequest(
    gpa: std.mem.Allocator,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
) ![]u8 {
    assert(prompt.len > 0);

    const TextPart = struct {
        text: []const u8,
    };
    const Content = struct {
        parts: []const TextPart,
    };
    const GenerationConfig = struct {
        responseModalities: []const api.ResponseModality,
        thinkingConfig: ?api.ThinkingConfig = null,
        responseFormat: ?api.ResponseFormatConfig = null,
    };
    const GenerateContentRequest = struct {
        contents: []const Content,
        tools: ?[]const api.Tool = null,
        generationConfig: GenerationConfig,
        safetySettings: []const api.SafetySetting,
    };

    const parts = [_]TextPart{.{ .text = prompt }};
    const contents = [_]Content{.{ .parts = &parts }};
    const maybe_grounding_tool = api.googleSearchToolFromGroundingOptions(grounding_options);
    var tools_buffer: [1]api.Tool = undefined;
    const tools: ?[]const api.Tool = if (maybe_grounding_tool) |tool| tools: {
        tools_buffer[0] = tool;
        break :tools tools_buffer[0..1];
    } else null;
    const request = GenerateContentRequest{
        .contents = &contents,
        .tools = tools,
        .generationConfig = .{
            .responseModalities = &api.default_response_modalities,
            .thinkingConfig = api.thinkingConfigFromOptions(thinking_options),
            .responseFormat = api.responseFormatFromOutputOptions(output_options),
        },
        .safetySettings = &api.default_safety_settings,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn buildCountTokensRequest(
    gpa: std.mem.Allocator,
    prompt: []const u8,
    output_options: api.ImageOutputOptions,
    grounding_options: api.GroundingOptions,
    thinking_options: api.ThinkingOptions,
) ![]u8 {
    assert(prompt.len > 0);

    const generate_request_json = try buildGenerateRequest(gpa, prompt, output_options, grounding_options, thinking_options);
    defer gpa.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(gpa, .nano2, generate_request_json);
}

const expected_safety_settings_json =
    "\"safetySettings\":[{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_SEXUALLY_EXPLICIT\",\"threshold\":\"BLOCK_NONE\"},{\"category\":\"HARM_CATEGORY_DANGEROUS_CONTENT\",\"threshold\":\"BLOCK_NONE\"}]";

test "buildGenerateRequest uses fixed Nano Banana 2 image request" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}," ++ expected_safety_settings_json ++ "}",
        request,
    );
}

test "buildGenerateRequest includes image output options" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{
        .aspect_ratio = .r16_9,
        .image_size = .k2,
    }, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"],\"responseFormat\":{\"image\":{\"aspectRatio\":\"ASPECT_RATIO_SIXTEEN_BY_NINE\",\"imageSize\":\"IMAGE_SIZE_TWO_K\"}}}," ++ expected_safety_settings_json ++ "}",
        request,
    );
}

test "buildGenerateRequest includes partial image output options" {
    const gpa = std.testing.allocator;
    const aspect_request = try buildGenerateRequest(gpa, "My fair lady", .{
        .aspect_ratio = .r9_16,
    }, .{}, .{});
    defer gpa.free(aspect_request);

    try std.testing.expect(std.mem.indexOf(u8, aspect_request, "\"aspectRatio\":\"ASPECT_RATIO_NINE_BY_SIXTEEN\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, aspect_request, "\"imageSize\"") == null);

    const size_request = try buildGenerateRequest(gpa, "My fair lady", .{
        .image_size = .px512,
    }, .{}, .{});
    defer gpa.free(size_request);

    try std.testing.expect(std.mem.indexOf(u8, size_request, "\"imageSize\":\"IMAGE_SIZE_FIVE_TWELVE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, size_request, "\"aspectRatio\"") == null);
}

test "buildGenerateRequest includes web grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .web = true,
    }, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"tools\":[{\"google_search\":{}}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}," ++ expected_safety_settings_json ++ "}",
        request,
    );
}

test "buildGenerateRequest includes image grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .image = true,
    }, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"imageSearch\":{}}}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"webSearch\"") == null);
}

test "buildGenerateRequest includes combined grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{
        .web = true,
        .image = true,
    }, .{});
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"webSearch\":{},\"imageSearch\":{}}}}]") != null);
}

test "buildGenerateRequest includes thinking config" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady", .{}, .{}, .{
        .level = .high,
        .include_thoughts = true,
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"thinkingConfig\":{\"thinkingLevel\":\"high\",\"includeThoughts\":true}") != null);
}

test "buildCountTokensRequest wraps fixed generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, "My fair lady", .{}, .{}, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}," ++ expected_safety_settings_json ++ "}}",
        request,
    );

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
