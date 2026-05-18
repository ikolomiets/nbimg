//! Gemini native image generation request and response handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");

const live_prompt = "My fair lady";

pub const ResponseModality = enum {
    image,

    pub fn apiName(modality: ResponseModality) []const u8 {
        return switch (modality) {
            .image => "IMAGE",
        };
    }

    pub fn jsonStringify(modality: ResponseModality, writer: anytype) !void {
        try writer.write(modality.apiName());
    }
};

pub const OutputMime = enum {
    png,
    jpeg,
    webp,
    text,

    pub fn fromName(name: []const u8) ?OutputMime {
        if (std.mem.eql(u8, name, "image/png")) return .png;
        if (std.mem.eql(u8, name, "image/jpeg")) return .jpeg;
        if (std.mem.eql(u8, name, "image/webp")) return .webp;
        if (std.mem.eql(u8, name, "text/plain")) return .text;
        return null;
    }

    pub fn extension(mime: OutputMime) []const u8 {
        return switch (mime) {
            .png => "png",
            .jpeg => "jpg",
            .webp => "webp",
            .text => "txt",
        };
    }
};

pub const GeneratedFile = struct {
    candidate_index: usize,
    part_index: usize,
    mime: OutputMime,
    bytes: []u8,

    pub fn deinit(file: *GeneratedFile, gpa: std.mem.Allocator) void {
        gpa.free(file.bytes);
        file.* = undefined;
    }
};

pub const GeneratedFiles = struct {
    response_id: []u8,
    items: []GeneratedFile,

    pub fn deinit(files: *GeneratedFiles, gpa: std.mem.Allocator) void {
        for (files.items) |*file| file.deinit(gpa);
        gpa.free(files.items);
        gpa.free(files.response_id);
        files.* = undefined;
    }
};

pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
};

pub fn generateContent(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    prompt: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);

    const request_json = try buildGenerateRequest(gpa, prompt);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, generateContentUrl(.nano2), request_json);
}

pub fn countGenerateContentRequestTokens(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    prompt: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(prompt.len > 0);

    const request_json = try buildCountTokensRequest(gpa, prompt);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, countTokensUrl(.nano2), request_json);
}

pub fn buildGenerateRequest(gpa: std.mem.Allocator, prompt: []const u8) ![]u8 {
    assert(prompt.len > 0);

    const TextPart = struct {
        text: []const u8,
    };
    const Content = struct {
        parts: []const TextPart,
    };
    const GenerationConfig = struct {
        responseModalities: []const ResponseModality,
    };
    const GenerateContentRequest = struct {
        contents: []const Content,
        generationConfig: GenerationConfig,
    };

    const parts = [_]TextPart{.{ .text = prompt }};
    const contents = [_]Content{.{ .parts = &parts }};
    const modalities = [_]ResponseModality{.image};
    const request = GenerateContentRequest{
        .contents = &contents,
        .generationConfig = .{
            .responseModalities = &modalities,
        },
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(request, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn buildCountTokensRequest(gpa: std.mem.Allocator, prompt: []const u8) ![]u8 {
    assert(prompt.len > 0);

    const generate_request_json = try buildGenerateRequest(gpa, prompt);
    defer gpa.free(generate_request_json);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    assert(generate_request_json.len >= 2);
    assert(generate_request_json[0] == '{');
    assert(generate_request_json[generate_request_json.len - 1] == '}');

    try output.writer.writeAll("{\"generateContentRequest\":{\"model\":\"");
    try output.writer.writeAll(api.Model.nano2.resourceName());
    try output.writer.writeAll("\",");
    try output.writer.writeAll(generate_request_json[1..]);
    try output.writer.writeAll("}");

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn decodeCountTokensResponse(gpa: std.mem.Allocator, response_json: []const u8) !CountTokensResult {
    const Response = struct {
        totalTokens: ?u64 = null,
        cachedContentTokenCount: ?u64 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return .{
        .total_tokens = parsed.value.totalTokens orelse return error.MissingTotalTokens,
        .cached_content_token_count = parsed.value.cachedContentTokenCount,
    };
}

pub fn decodeResponseId(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    const Response = struct {
        responseId: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const response_id = parsed.value.responseId orelse return error.MissingResponseId;
    if (response_id.len == 0) return error.MissingResponseId;
    return gpa.dupe(u8, response_id);
}

pub fn decodeGeneratedFiles(gpa: std.mem.Allocator, response_json: []const u8) !GeneratedFiles {
    const Response = struct {
        candidates: []const Candidate = &.{},
        usageMetadata: ?UsageMetadata = null,
        modelVersion: ?[]const u8 = null,
        responseId: ?[]const u8 = null,

        const Candidate = struct {
            content: ?Content = null,
            finishReason: ?[]const u8 = null,
            index: ?usize = null,
        };
        const Content = struct {
            parts: []const Part = &.{},
            role: ?[]const u8 = null,
        };
        const Part = struct {
            text: ?[]const u8 = null,
            inlineData: ?InlineData = null,
            thoughtSignature: ?[]const u8 = null,
        };
        const InlineData = struct {
            mimeType: ?[]const u8 = null,
            data: ?[]const u8 = null,
        };
        const UsageMetadata = struct {
            promptTokenCount: ?u64 = null,
            candidatesTokenCount: ?u64 = null,
            totalTokenCount: ?u64 = null,
            promptTokensDetails: []const TokenDetail = &.{},
            candidatesTokensDetails: []const TokenDetail = &.{},
            serviceTier: ?[]const u8 = null,
        };
        const TokenDetail = struct {
            modality: ?[]const u8 = null,
            tokenCount: ?u64 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const response_id = parsed.value.responseId orelse return error.MissingResponseId;
    if (response_id.len == 0) return error.MissingResponseId;

    const owned_response_id = try gpa.dupe(u8, response_id);
    errdefer gpa.free(owned_response_id);

    var files: std.ArrayList(GeneratedFile) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    for (parsed.value.candidates, 0..) |candidate, candidate_index| {
        const content = candidate.content orelse continue;
        for (content.parts, 0..) |part, part_index| {
            var file = try decodePart(gpa, candidate_index, part_index, part);
            errdefer file.deinit(gpa);
            try files.append(gpa, file);
        }
    }

    if (files.items.len == 0) return error.NoGeneratedParts;

    return .{
        .response_id = owned_response_id,
        .items = try files.toOwnedSlice(gpa),
    };
}

fn decodePart(
    gpa: std.mem.Allocator,
    candidate_index: usize,
    part_index: usize,
    part: anytype,
) !GeneratedFile {
    if (part.text) |text| {
        const bytes = try gpa.dupe(u8, text);
        errdefer gpa.free(bytes);

        return .{
            .candidate_index = candidate_index,
            .part_index = part_index,
            .mime = .text,
            .bytes = bytes,
        };
    }

    const inline_payload = part.inlineData orelse return error.UnsupportedPart;
    const mime_name = inline_payload.mimeType orelse return error.MissingMimeType;
    const mime = OutputMime.fromName(mime_name) orelse return error.UnsupportedMime;
    if (mime == .text) return error.UnsupportedMime;

    const encoded = inline_payload.data orelse return error.MissingInlineData;
    const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const decoded = try gpa.alloc(u8, decoded_size);
    errdefer gpa.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, encoded);

    return .{
        .candidate_index = candidate_index,
        .part_index = part_index,
        .mime = mime,
        .bytes = decoded,
    };
}

pub fn generatedFileName(buffer: []u8, response_id: []const u8, file: GeneratedFile) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{s}-{d}-{d}.{s}",
        .{ response_id, file.candidate_index, file.part_index, file.mime.extension() },
    );
}

pub fn responseFileName(buffer: []u8, response_id: []const u8) ![]const u8 {
    return std.fmt.bufPrint(buffer, "{s}.json", .{response_id});
}

fn generateContentUrl(model: api.Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent",
    };
}

fn countTokensUrl(model: api.Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:countTokens",
    };
}

test "buildGenerateRequest uses fixed Nano Banana 2 image request" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, "My fair lady");
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"IMAGE\"]}}",
        request,
    );
}

test "buildCountTokensRequest wraps fixed generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, "My fair lady");
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"IMAGE\"]}}}",
        request,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "decodeCountTokensResponse decodes total tokens" {
    const result = try decodeCountTokensResponse(
        std.testing.allocator,
        "{\"totalTokens\":7,\"unknown\":\"ignored\"}",
    );

    try std.testing.expectEqual(@as(u64, 7), result.total_tokens);
    try std.testing.expectEqual(@as(?u64, null), result.cached_content_token_count);
}

test "decodeCountTokensResponse decodes cached content token count" {
    const result = try decodeCountTokensResponse(
        std.testing.allocator,
        "{\"totalTokens\":7,\"cachedContentTokenCount\":3}",
    );

    try std.testing.expectEqual(@as(u64, 7), result.total_tokens);
    try std.testing.expectEqual(@as(?u64, 3), result.cached_content_token_count);
}

test "decodeCountTokensResponse rejects missing total token count" {
    try std.testing.expectError(
        error.MissingTotalTokens,
        decodeCountTokensResponse(std.testing.allocator, "{\"cachedContentTokenCount\":3}"),
    );
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

    const result = decodeCountTokensResponse(gpa, response.body) catch |err| {
        std.debug.print(
            "error: failed to parse countTokens response: {s}\n{s}\n",
            .{ @errorName(err), response.body },
        );
        return err;
    };

    try std.testing.expect(result.total_tokens > 0);
}

test "decodeResponseId returns owned response id" {
    const gpa = std.testing.allocator;
    const response_id = try decodeResponseId(
        gpa,
        "{\"responseId\":\"PMMIapvKNtLj_uMPq8a8oQs\",\"unknown\":\"ignored\"}",
    );
    defer gpa.free(response_id);

    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs", response_id);
}

test "decodeResponseId rejects missing response id" {
    try std.testing.expectError(
        error.MissingResponseId,
        decodeResponseId(std.testing.allocator, "{\"candidates\":[]}"),
    );
}

test "decodeResponseId rejects empty response id" {
    try std.testing.expectError(
        error.MissingResponseId,
        decodeResponseId(std.testing.allocator, "{\"responseId\":\"\"}"),
    );
}

test "responseFileName uses response id template" {
    var buffer: [64]u8 = undefined;
    const name = try responseFileName(&buffer, "PMMIapvKNtLj_uMPq8a8oQs");
    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs.json", name);
}

test "decodeGeneratedFiles decodes image and text parts" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "responseId": "test-response",
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [
        \\        {"inlineData": {"mimeType": "image/png", "data": "AQID"}},
        \\        {"text": "hello"}
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    var files = try decodeGeneratedFiles(gpa, json);
    defer files.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), files.items.len);
    try std.testing.expectEqualStrings("test-response", files.response_id);
    try std.testing.expectEqual(OutputMime.png, files.items[0].mime);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, files.items[0].bytes);
    try std.testing.expectEqual(OutputMime.text, files.items[1].mime);
    try std.testing.expectEqualStrings("hello", files.items[1].bytes);
}

test "decodeGeneratedFiles accepts observed Gemini image response shape" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [{
        \\        "inlineData": {
        \\          "mimeType": "image/jpeg",
        \\          "data": "AQID"
        \\        },
        \\        "thoughtSignature": "AQIDBA=="
        \\      }],
        \\      "role": "model"
        \\    },
        \\    "finishReason": "STOP",
        \\    "index": 0
        \\  }],
        \\  "usageMetadata": {
        \\    "promptTokenCount": 7,
        \\    "candidatesTokenCount": 1588,
        \\    "totalTokenCount": 1595,
        \\    "promptTokensDetails": [{
        \\      "modality": "TEXT",
        \\      "tokenCount": 7
        \\    }],
        \\    "candidatesTokensDetails": [{
        \\      "modality": "IMAGE",
        \\      "tokenCount": 1120
        \\    }],
        \\    "serviceTier": "standard"
        \\  },
        \\  "modelVersion": "gemini-3.1-flash-image-preview",
        \\  "responseId": "PMMIapvKNtLj_uMPq8a8oQs"
        \\}
    ;

    var files = try decodeGeneratedFiles(gpa, json);
    defer files.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), files.items.len);
    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs", files.response_id);
    try std.testing.expectEqual(OutputMime.jpeg, files.items[0].mime);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, files.items[0].bytes);
}

test "decodeGeneratedFiles rejects generated output missing response id" {
    const gpa = std.testing.allocator;
    const json =
        \\{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingResponseId, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects generated output empty response id" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingResponseId, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects text-only missing candidates" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.NoGeneratedParts, decodeGeneratedFiles(gpa, "{\"responseId\":\"test-response\",\"candidates\":[]}"));
}

test "decodeGeneratedFiles rejects unknown image MIME" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/gif","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.UnsupportedMime, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects snake case MIME type field" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mime_type":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingMimeType, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles cleans up partial output on later part failure" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}},{}]}}]}
    ;

    try std.testing.expectError(error.UnsupportedPart, decodeGeneratedFiles(gpa, json));
}

test "generatedFileName uses response id candidate part template" {
    const file = GeneratedFile{
        .candidate_index = 12,
        .part_index = 3,
        .mime = .webp,
        .bytes = @constCast("x"),
    };
    var buffer: [64]u8 = undefined;
    const name = try generatedFileName(&buffer, "PMMIapvKNtLj_uMPq8a8oQs", file);
    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs-12-3.webp", name);
}
