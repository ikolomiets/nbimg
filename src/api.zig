//! Shared Gemini API model constants, transport, and traffic logging.

const std = @import("std");
const assert = std.debug.assert;

pub const max_response_bytes = 64 * 1024 * 1024;
pub const api_key_env_name = "GEMINI_API_KEY";
pub const canonical_file_name_prefix = "files/";

pub const ApiKeyError = error{
    MissingApiKey,
    EmptyApiKey,
};

pub const Model = enum {
    nano2,

    pub fn apiName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "gemini-3.1-flash-image-preview",
        };
    }

    pub fn resourceName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "models/gemini-3.1-flash-image-preview",
        };
    }
};

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

pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
};

pub const HttpResponse = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(response: *HttpResponse, gpa: std.mem.Allocator) void {
        gpa.free(response.body);
        response.* = undefined;
    }
};

pub const HttpResponseWithUploadUrl = struct {
    response: HttpResponse,
    upload_url: ?[]u8 = null,
};

pub const TrafficLogOptions = struct {
    print_request: bool = false,
    print_response: bool = false,
};

pub var traffic_log_options: TrafficLogOptions = .{};

pub fn apiKeyFromMap(environ_map: *const std.process.Environ.Map) ApiKeyError![]const u8 {
    const api_key = environ_map.get(api_key_env_name) orelse return error.MissingApiKey;
    if (api_key.len == 0) return error.EmptyApiKey;
    return api_key;
}

pub fn generateContentUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent",
    };
}

pub fn countTokensUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:countTokens",
    };
}

pub fn isCanonicalFileName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_file_name_prefix)) return false;
    return name.len > canonical_file_name_prefix.len;
}

pub fn buildCountTokensRequestFromGenerateContentJson(
    gpa: std.mem.Allocator,
    model: Model,
    generate_request_json: []const u8,
) ![]u8 {
    assert(generate_request_json.len >= 2);
    assert(generate_request_json[0] == '{');
    assert(generate_request_json[generate_request_json.len - 1] == '}');

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll("{\"generateContentRequest\":{\"model\":\"");
    try output.writer.writeAll(model.resourceName());
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

test "isCanonicalFileName requires files prefix and id" {
    try std.testing.expect(isCanonicalFileName("files/abc123"));
    try std.testing.expect(!isCanonicalFileName("abc123"));
    try std.testing.expect(!isCanonicalFileName("files/"));
    try std.testing.expect(!isCanonicalFileName(""));
}

test "buildCountTokensRequestFromGenerateContentJson wraps generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequestFromGenerateContentJson(
        gpa,
        .nano2,
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}]}",
    );
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}]}}",
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

test "command modules import only shared api module" {
    try expectAllowedCommandModuleImports("src/gen.zig");
    try expectAllowedCommandModuleImports("src/edit.zig");
    try expectAllowedCommandModuleImports("src/files.zig");
}

fn expectAllowedCommandModuleImports(path: []const u8) !void {
    const gpa = std.testing.allocator;
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(64 * 1024));
    defer gpa.free(source);

    const import_prefix = "@import(\"";
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, source, index, import_prefix)) |import_start| {
        const name_start = import_start + import_prefix.len;
        const name_end_relative = std.mem.indexOfScalar(u8, source[name_start..], '"') orelse {
            std.debug.print("error: malformed import in {s}\n", .{path});
            return error.MalformedImport;
        };
        const name_end = name_start + name_end_relative;
        const name = source[name_start..name_end];

        if (std.mem.endsWith(u8, name, ".zig") and !std.mem.eql(u8, name, "api.zig")) {
            std.debug.print(
                "error: command module {s} imports forbidden local module {s}\n",
                .{ path, name },
            );
            return error.ForbiddenCommandModuleImport;
        }

        index = name_end + 1;
    }
}

pub const RequestBodyLog = union(enum) {
    empty,
    text: []const u8,
    binary: BinaryRequestBodyLog,
};

pub const BinaryRequestBodyLog = struct {
    byte_count: usize,
    mime: []const u8,
};

pub const RequestWithBodyOptions = struct {
    capture_upload_url: bool = false,
    request_body_log: RequestBodyLog = .empty,
};

pub fn postJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
    request_json: []const u8,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(url.len > 0);
    assert(request_json.len > 0);

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
    };

    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    try logRequest(io, url, .{ .text = request_json });

    var response_writer: std.Io.Writer = .fixed(response_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = request_json,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .user_agent = .{ .override = "nbimg/0.0.0" },
        },
        .extra_headers = &headers,
        .response_writer = &response_writer,
    });

    const response_body = response_writer.buffered();
    try logResponseBody(gpa, io, result.status, response_body);

    return .{
        .status = result.status,
        .body = try gpa.dupe(u8, response_body),
    };
}

pub fn getJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(gpa, io, api_key, url, .GET);
}

pub fn deleteJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(gpa, io, api_key, url, .DELETE);
}

fn requestJsonWithoutBody(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
    method: std.http.Method,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(url.len > 0);

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
    };

    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    try logRequest(io, url, .empty);

    var response_writer: std.Io.Writer = .fixed(response_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
        },
        .extra_headers = &headers,
        .response_writer = &response_writer,
    });

    const response_body = response_writer.buffered();
    try logResponseBody(gpa, io, result.status, response_body);

    return .{
        .status = result.status,
        .body = try gpa.dupe(u8, response_body),
    };
}

pub fn requestWithBody(
    gpa: std.mem.Allocator,
    client: *std.http.Client,
    method: std.http.Method,
    url: []const u8,
    content_type: []const u8,
    extra_headers: []const std.http.Header,
    body: []const u8,
    options: RequestWithBodyOptions,
) !HttpResponseWithUploadUrl {
    assert(url.len > 0);
    assert(content_type.len > 0);
    assert(body.len > 0);

    const uri = try std.Uri.parse(url);
    var req = try client.request(method, uri, .{
        .redirect_behavior = .unhandled,
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = content_type },
        },
        .extra_headers = extra_headers,
    });
    defer req.deinit();

    try logRequest(client.io, url, options.request_body_log);

    req.transfer_encoding = .{ .content_length = body.len };
    var body_writer = try req.sendBodyUnflushed(&.{});
    try body_writer.writer.writeAll(body);
    try body_writer.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});
    const status = response.head.status;

    var upload_url: ?[]u8 = null;
    errdefer if (upload_url) |url_copy| gpa.free(url_copy);

    if (options.capture_upload_url) {
        var header_iterator = response.head.iterateHeaders();
        while (header_iterator.next()) |header| {
            if (!std.ascii.eqlIgnoreCase(header.name, "x-goog-upload-url")) continue;
            const value = std.mem.trim(u8, header.value, " \t");
            if (value.len == 0) return error.MissingUploadUrl;
            upload_url = try gpa.dupe(u8, value);
            break;
        }
    }

    const response_body = try readHttpBody(gpa, &response);
    errdefer gpa.free(response_body);

    try logResponseBody(gpa, client.io, status, response_body);

    return .{
        .response = .{
            .status = status,
            .body = response_body,
        },
        .upload_url = upload_url,
    };
}

fn readHttpBody(gpa: std.mem.Allocator, response: *std.http.Client.Response) ![]u8 {
    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    var response_writer: std.Io.Writer = .fixed(response_buffer);
    var transfer_buffer: [64]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    _ = reader.streamRemaining(&response_writer) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };

    return gpa.dupe(u8, response_writer.buffered());
}

fn logRequest(io: std.Io, url: []const u8, body: RequestBodyLog) !void {
    if (!traffic_log_options.print_request) return;

    try writeStderr(io, "--- nbimg api request ---\nurl: ");
    try writeStderr(io, url);
    try writeStderr(io, "\nbody:\n");
    switch (body) {
        .empty => try writeStderr(io, "<none>\n"),
        .text => |text| {
            try writeStderr(io, text);
            try writeStderr(io, "\n");
        },
        .binary => |binary| try writeStderrFormat(
            io,
            "<binary omitted: {d} bytes; mime: {s}>\n",
            .{ binary.byte_count, binary.mime },
        ),
    }
}

fn logResponseBody(
    gpa: std.mem.Allocator,
    io: std.Io,
    status: std.http.Status,
    response_body: []const u8,
) !void {
    if (!traffic_log_options.print_response) return;

    try writeStderrFormat(
        io,
        "--- nbimg api response ---\nstatus: {d}\nbody:\n",
        .{@intFromEnum(status)},
    );
    if (response_body.len == 0) {
        try writeStderr(io, "<empty>\n");
        return;
    }

    const log_body = sanitizeResponseLogBody(gpa, response_body) catch |err| {
        try writeStderrFormat(
            io,
            "<response body omitted: {d} bytes; failed to sanitize JSON: {s}>\n",
            .{ response_body.len, @errorName(err) },
        );
        return;
    };
    defer gpa.free(log_body);
    try writeStderr(io, log_body);
    try writeStderr(io, "\n");
}

fn writeStderr(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, bytes);
}

fn writeStderrFormat(io: std.Io, comptime format: []const u8, args: anytype) !void {
    var buffer: [512]u8 = undefined;
    const bytes = try std.fmt.bufPrint(&buffer, format, args);
    try writeStderr(io, bytes);
}

fn sanitizeResponseLogBody(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();

    try redactKnownResponseFields(parsed.arena.allocator(), &parsed.value);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(parsed.value, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn redactKnownResponseFields(arena: std.mem.Allocator, root: *std.json.Value) !void {
    switch (root.*) {
        .object => |*object| {
            if (object.getPtr("candidates")) |candidates| {
                try redactCandidateArray(arena, candidates);
            }
        },
        else => return,
    }
}

fn redactCandidateArray(arena: std.mem.Allocator, candidates: *std.json.Value) !void {
    switch (candidates.*) {
        .array => |*array| {
            for (array.items) |*candidate| {
                try redactCandidate(arena, candidate);
            }
        },
        else => return,
    }
}

fn redactCandidate(arena: std.mem.Allocator, candidate: *std.json.Value) !void {
    switch (candidate.*) {
        .object => |*object| {
            const content = object.getPtr("content") orelse return;
            try redactContent(arena, content);
        },
        else => return,
    }
}

fn redactContent(arena: std.mem.Allocator, content: *std.json.Value) !void {
    switch (content.*) {
        .object => |*object| {
            const parts = object.getPtr("parts") orelse return;
            try redactPartArray(arena, parts);
        },
        else => return,
    }
}

fn redactPartArray(arena: std.mem.Allocator, parts: *std.json.Value) !void {
    switch (parts.*) {
        .array => |*array| {
            for (array.items) |*part| {
                try redactPart(arena, part);
            }
        },
        else => return,
    }
}

fn redactPart(arena: std.mem.Allocator, part: *std.json.Value) !void {
    switch (part.*) {
        .object => |*object| {
            if (object.getPtr("inlineData")) |inline_payload| {
                try redactInlineData(arena, inline_payload);
            }
            if (object.getPtr("thoughtSignature")) |thought_signature| {
                try redactBase64StringValue(arena, thought_signature);
            }
        },
        else => return,
    }
}

fn redactInlineData(arena: std.mem.Allocator, inline_payload: *std.json.Value) !void {
    switch (inline_payload.*) {
        .object => |*object| {
            const data = object.getPtr("data") orelse return;
            try redactBase64StringValue(arena, data);
        },
        else => return,
    }
}

fn redactBase64StringValue(arena: std.mem.Allocator, value: *std.json.Value) !void {
    switch (value.*) {
        .string => |encoded| {
            value.* = .{ .string = try base64OmissionLabel(arena, encoded) };
        },
        else => return,
    }
}

fn base64OmissionLabel(arena: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
        return std.fmt.allocPrint(
            arena,
            "<base64 omitted: invalid base64, {d} encoded bytes>",
            .{encoded.len},
        );
    };

    return std.fmt.allocPrint(
        arena,
        "<base64 omitted: {d} decoded bytes>",
        .{decoded_size},
    );
}

test "apiKeyFromMap returns borrowed API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api_key_env_name, "test-key");

    const api_key = try apiKeyFromMap(&environ_map);
    try std.testing.expectEqualStrings("test-key", api_key);
}

test "apiKeyFromMap rejects missing API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try std.testing.expectError(error.MissingApiKey, apiKeyFromMap(&environ_map));
}

test "apiKeyFromMap rejects empty API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api_key_env_name, "");

    try std.testing.expectError(error.EmptyApiKey, apiKeyFromMap(&environ_map));
}

test "sanitizeResponseLogBody redacts inlineData data" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"<base64 omitted: 3 decoded bytes>\"}}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts multiple known data fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"AQID\"}},{\"inlineData\":{\"data\":\"AQIDBA==\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: 3 decoded bytes>\"}},{\"inlineData\":{\"data\":\"<base64 omitted: 4 decoded bytes>\"}}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts thoughtSignature" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"thoughtSignature\":\"AQID\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"thoughtSignature\":\"<base64 omitted: 3 decoded bytes>\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts inline data and thought signature" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"AQID\"},\"thoughtSignature\":\"AQIDBA==\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: 3 decoded bytes>\"},\"thoughtSignature\":\"<base64 omitted: 4 decoded bytes>\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated data fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"data\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"data\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated thoughtSignature fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"thoughtSignature\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"thoughtSignature\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves uploaded file sha256Hash" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"file\":{\"name\":\"files/abc\",\"sha256Hash\":\"AQIDBA==\"}}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"name\":\"files/abc\",\"sha256Hash\":\"AQIDBA==\"}}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves listed file sha256Hash" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"files\":[{\"name\":\"files/abc\",\"sha256Hash\":\"AQID\"}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"files\":[{\"name\":\"files/abc\",\"sha256Hash\":\"AQID\"}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated sha256Hash fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"sha256Hash\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"sha256Hash\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts invalid base64 data" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"not_base64\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: invalid base64, 10 encoded bytes>\"}}]}}]}",
        sanitized,
    );
}
