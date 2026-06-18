//! Gemini Batch API JSONL validation, upload, submission, listing, status, and cancellation.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");

pub const max_entry_bytes = api.max_generate_request_field_bytes;
pub const max_input_bytes = 512 * 1024 * 1024;
pub const max_output_bytes = 512 * 1024 * 1024;
pub const max_entries = 100;
const input_content_type = "application/jsonl";
const canonical_batch_name_prefix = "batches/";
const max_safe_key_bytes = 160;
const truncated_safe_key_prefix_bytes = 120;

pub const SubmitRequest = struct {
    file_name: []const u8,
    display_name: []const u8,
};

pub const DownloadInfo = struct {
    file_name: []u8,
    request_count: ?usize,

    pub fn deinit(info: *DownloadInfo, gpa: std.mem.Allocator) void {
        gpa.free(info.file_name);
        info.* = undefined;
    }
};

pub const OutputRecord = struct {
    key: []u8,
    response_json: ?[]u8,

    pub fn deinit(record: *OutputRecord, gpa: std.mem.Allocator) void {
        gpa.free(record.key);
        if (record.response_json) |response_json| gpa.free(response_json);
        record.* = undefined;
    }
};

pub const OutputLineIterator = struct {
    bytes: []const u8,
    offset: usize = 0,
    line_count: usize = 0,

    pub fn next(iterator: *OutputLineIterator) !?[]const u8 {
        if (iterator.offset >= iterator.bytes.len) return null;

        const newline_relative = std.mem.indexOfScalar(u8, iterator.bytes[iterator.offset..], '\n');
        const line_end = if (newline_relative) |relative| iterator.offset + relative else iterator.bytes.len;
        var line = iterator.bytes[iterator.offset..line_end];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

        iterator.line_count += 1;
        if (iterator.line_count > max_entries) return error.BatchTooManyEntries;

        iterator.offset = if (newline_relative == null) iterator.bytes.len else line_end + 1;
        return line;
    }
};

pub const ListPage = struct {
    operations: [][]u8,
    next_page_token: ?[]u8 = null,

    pub fn deinit(page: *ListPage, gpa: std.mem.Allocator) void {
        for (page.operations) |operation| gpa.free(operation);
        gpa.free(page.operations);
        if (page.next_page_token) |token| gpa.free(token);
        page.* = undefined;
    }
};

pub fn buildEntryJson(
    gpa: std.mem.Allocator,
    key: []const u8,
    generate_request_json: []const u8,
) ![]u8 {
    assert(key.len > 0);
    assert(generate_request_json.len >= 2);
    assert(generate_request_json[0] == '{');
    assert(generate_request_json[generate_request_json.len - 1] == '}');

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll("{\"key\":");
    try std.json.Stringify.value(key, .{}, &output.writer);
    try output.writer.writeAll(",\"request\":");
    try output.writer.writeAll(generate_request_json);
    try output.writer.writeByte('}');

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn validateInputJsonl(bytes: []const u8) !void {
    try validateInputByteCount(bytes.len);

    var entry_count: usize = 0;
    var offset: usize = 0;
    while (offset < bytes.len) {
        const newline_relative = std.mem.indexOfScalar(u8, bytes[offset..], '\n');
        const line_end = if (newline_relative) |relative| offset + relative else bytes.len;
        var line = bytes[offset..line_end];
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

        if (line.len == 0) return error.InvalidBatchInput;
        if (line.len > max_entry_bytes) return error.BatchEntryTooLong;
        if (entry_count == max_entries) return error.BatchTooManyEntries;
        entry_count += 1;

        if (newline_relative == null) break;
        offset = line_end + 1;
    }

    if (entry_count == 0) return error.EmptyBatchInput;
}

fn validateInputByteCount(byte_count: usize) !void {
    if (byte_count == 0) return error.EmptyBatchInput;
    if (byte_count > max_input_bytes) return error.BatchInputTooLong;
}

pub fn uploadInput(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    bytes: []const u8,
    display_name: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(bytes.len > 0);
    assert(bytes.len <= max_input_bytes);
    assert(api.isValidDisplayName(display_name));

    return api.uploadResumableBytes(gpa, io, api_key, .{
        .content_type = input_content_type,
        .bytes = bytes,
        .display_name = display_name,
    });
}

fn buildSubmitRequestJson(gpa: std.mem.Allocator, request: SubmitRequest) ![]u8 {
    assert(api.isCanonicalFileName(request.file_name));
    assert(api.isValidDisplayName(request.display_name));

    const InputConfig = struct {
        fileName: []const u8,
    };
    const Batch = struct {
        displayName: []const u8,
        inputConfig: InputConfig,
    };
    const Request = struct {
        batch: Batch,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(Request{
        .batch = .{
            .displayName = request.display_name,
            .inputConfig = .{
                .fileName = request.file_name,
            },
        },
    }, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn submit(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    request: SubmitRequest,
) !api.HttpResponse {
    const request_json = try buildSubmitRequestJson(gpa, request);
    defer gpa.free(request_json);

    // Batch creation is non-idempotent. This call is intentionally made once.
    return api.postJson(gpa, io, api_key, submitUrl(), request_json);
}

pub fn status(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    name: []const u8,
) !api.HttpResponse {
    assert(isCanonicalBatchName(name));

    const url = try buildStatusUrl(gpa, name);
    defer gpa.free(url);
    return api.getJson(gpa, io, api_key, url);
}

pub fn decodeDownloadInfo(gpa: std.mem.Allocator, response_json: []const u8) !DownloadInfo {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, response_json, .{
        .parse_numbers = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBatchStatusResponse,
    };
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidBatchStatusResponse,
    };

    var candidate_objects: [4]std.json.ObjectMap = undefined;
    var candidate_count: usize = 0;
    candidate_objects[candidate_count] = root;
    candidate_count += 1;

    if (objectField(root, "metadata")) |metadata| {
        candidate_objects[candidate_count] = metadata;
        candidate_count += 1;
    }
    if (objectField(root, "response")) |response| {
        candidate_objects[candidate_count] = response;
        candidate_count += 1;
        if (candidate_count < candidate_objects.len) {
            if (objectField(response, "batch")) |batch| {
                candidate_objects[candidate_count] = batch;
                candidate_count += 1;
            }
        }
    }

    const candidates = candidate_objects[0..candidate_count];
    const state = findStringField(candidates, "state") orelse return error.InvalidBatchStatusResponse;
    if (!isSucceededState(state)) return error.BatchNotSucceeded;

    const request_count = try findRequestCount(candidates);
    if (request_count) |count| {
        if (count > max_entries) return error.BatchTooManyEntries;
    }

    const file_name = findOutputFileName(candidates) orelse return error.MissingBatchOutputFile;
    if (!api.isCanonicalFileName(file_name)) return error.MissingBatchOutputFile;

    return .{
        .file_name = try gpa.dupe(u8, file_name),
        .request_count = request_count,
    };
}

pub fn downloadOutput(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    file_name: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(api.isCanonicalFileName(file_name));

    const url = try buildOutputDownloadUrl(gpa, file_name);
    defer gpa.free(url);
    return api.getBytesBounded(gpa, io, api_key, url, max_output_bytes);
}

pub fn cancel(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    name: []const u8,
) !api.HttpResponse {
    assert(isCanonicalBatchName(name));

    const url = try buildCancelUrl(gpa, name);
    defer gpa.free(url);
    return api.postJsonWithoutBody(gpa, io, api_key, url);
}

pub fn listPage(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    page_token: ?[]const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    if (page_token) |token| assert(token.len > 0);

    const url = try buildListUrl(gpa, page_token);
    defer gpa.free(url);
    return api.getJson(gpa, io, api_key, url);
}

pub fn isCanonicalBatchName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_batch_name_prefix)) return false;
    return name.len > canonical_batch_name_prefix.len;
}

pub fn decodeBatchName(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    const Response = struct {
        name: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const name = parsed.value.name orelse return error.MissingBatchName;
    if (!isCanonicalBatchName(name)) return error.MissingBatchName;
    return gpa.dupe(u8, name);
}

pub fn validateOutputJsonl(bytes: []const u8) !usize {
    if (bytes.len == 0) return error.EmptyBatchOutput;

    var iterator = OutputLineIterator{ .bytes = bytes };
    while (try iterator.next()) |_| {}
    assert(iterator.line_count > 0);
    assert(iterator.line_count <= max_entries);
    return iterator.line_count;
}

pub fn decodeOutputRecord(gpa: std.mem.Allocator, line: []const u8) !OutputRecord {
    if (line.len == 0) return error.InvalidBatchOutput;

    const Record = struct {
        key: ?[]const u8 = null,
        response: ?std.json.Value = null,
        @"error": ?std.json.Value = null,
    };

    var parsed = std.json.parseFromSlice(Record, gpa, line, .{
        .ignore_unknown_fields = true,
        .parse_numbers = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBatchOutput,
    };
    defer parsed.deinit();

    const key = parsed.value.key orelse return error.InvalidBatchOutput;
    if (key.len == 0) return error.InvalidBatchOutput;

    if (parsed.value.response != null and parsed.value.@"error" != null) {
        return error.InvalidBatchOutput;
    }
    if (parsed.value.response == null and parsed.value.@"error" == null) {
        return error.InvalidBatchOutput;
    }

    const owned_key = try gpa.dupe(u8, key);
    errdefer gpa.free(owned_key);

    const response_json = if (parsed.value.response) |response| response_json: {
        if (response != .object) return error.InvalidBatchOutput;
        break :response_json try stringifyJson(gpa, response, .{});
    } else null;
    errdefer if (response_json) |json| gpa.free(json);

    return .{
        .key = owned_key,
        .response_json = response_json,
    };
}

pub fn safeOutputKey(gpa: std.mem.Allocator, key: []const u8) ![]u8 {
    if (key.len == 0) return error.InvalidBatchOutput;

    var encoded_length: usize = 0;
    for (key) |byte| {
        encoded_length = std.math.add(
            usize,
            encoded_length,
            if (isSafeOutputKeyByte(byte)) 1 else 3,
        ) catch return error.BatchOutputKeyTooLong;
    }

    if (encoded_length <= max_safe_key_bytes) {
        var output = try std.Io.Writer.Allocating.initCapacity(gpa, encoded_length);
        errdefer output.deinit();
        for (key) |byte| try writeSafeOutputKeyByte(&output.writer, byte);
        return output.toOwnedSlice();
    }

    var output = try std.Io.Writer.Allocating.initCapacity(
        gpa,
        truncated_safe_key_prefix_bytes + 1 + 32,
    );
    errdefer output.deinit();

    for (key) |byte| {
        const byte_length: usize = if (isSafeOutputKeyByte(byte)) 1 else 3;
        if (output.writer.end + byte_length > truncated_safe_key_prefix_bytes) break;
        try writeSafeOutputKeyByte(&output.writer, byte);
    }
    assert(output.writer.end > 0);

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(key, &digest, .{});
    try output.writer.writeByte('-');
    for (digest[0..16]) |byte| try output.writer.print("{x:0>2}", .{byte});

    assert(output.writer.end <= max_safe_key_bytes);
    return output.toOwnedSlice();
}

pub fn decodeListPage(gpa: std.mem.Allocator, response_json: []const u8) !ListPage {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{
        .parse_numbers = false,
    });
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidBatchListResponse,
    };

    const operation_values: []const std.json.Value = if (root.get("operations")) |value| switch (value) {
        .array => |array| array.items,
        else => return error.InvalidBatchListResponse,
    } else &.{};

    const operations = try gpa.alloc([]u8, operation_values.len);
    var operation_count: usize = 0;
    errdefer {
        for (operations[0..operation_count]) |operation| gpa.free(operation);
        gpa.free(operations);
    }

    for (operation_values) |operation_value| {
        const operation = switch (operation_value) {
            .object => |object| object,
            else => return error.InvalidBatchListResponse,
        };
        const name_value = operation.get("name") orelse return error.MissingBatchName;
        const name = switch (name_value) {
            .string => |string| string,
            else => return error.MissingBatchName,
        };
        if (!isCanonicalBatchName(name)) return error.MissingBatchName;

        operations[operation_count] = try stringifyJson(gpa, operation_value, .{});
        operation_count += 1;
    }
    assert(operation_count == operations.len);

    const next_page_token: ?[]u8 = if (root.get("nextPageToken")) |value| switch (value) {
        .string => |token| if (token.len == 0) null else try gpa.dupe(u8, token),
        else => return error.InvalidBatchListResponse,
    } else null;
    errdefer if (next_page_token) |token| gpa.free(token);

    return .{
        .operations = operations,
        .next_page_token = next_page_token,
    };
}

pub fn listJson(gpa: std.mem.Allocator, operations: []const []const u8) ![]u8 {
    var compact: std.Io.Writer.Allocating = .init(gpa);
    defer compact.deinit();

    try compact.writer.writeAll("{\"operations\":[");
    for (operations, 0..) |operation, index| {
        assert(operation.len >= 2);
        assert(operation[0] == '{');
        assert(operation[operation.len - 1] == '}');

        if (index > 0) try compact.writer.writeByte(',');
        try compact.writer.writeAll(operation);
    }
    try compact.writer.writeAll("]}");

    return prettyJson(gpa, compact.written());
}

pub fn prettyJson(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{
        .parse_numbers = false,
    });
    defer parsed.deinit();

    return stringifyJson(gpa, parsed.value, .{
        .whitespace = .indent_2,
    });
}

fn submitUrl() []const u8 {
    return "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:batchGenerateContent";
}

fn buildStatusUrl(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return buildBatchUrl(gpa, name, "");
}

fn buildOutputDownloadUrl(gpa: std.mem.Allocator, file_name: []const u8) ![]u8 {
    assert(api.isCanonicalFileName(file_name));

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try output.writer.writeAll("https://generativelanguage.googleapis.com/download/v1beta/files/");
    try formatPathSegment(&output.writer, file_name[api.canonical_file_name_prefix.len..]);
    try output.writer.writeAll(":download?alt=media");

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn buildCancelUrl(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return buildBatchUrl(gpa, name, ":cancel");
}

fn buildBatchUrl(gpa: std.mem.Allocator, name: []const u8, suffix: []const u8) ![]u8 {
    assert(isCanonicalBatchName(name));

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try output.writer.writeAll("https://generativelanguage.googleapis.com/v1beta/batches/");
    try formatPathSegment(&output.writer, name[canonical_batch_name_prefix.len..]);
    try output.writer.writeAll(suffix);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn buildListUrl(gpa: std.mem.Allocator, page_token: ?[]const u8) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll("https://generativelanguage.googleapis.com/v1beta/batches?pageSize=100");
    if (page_token) |token| {
        assert(token.len > 0);
        try output.writer.writeAll("&pageToken=");
        try (std.Uri.Component{ .raw = token }).formatEscaped(&output.writer);
    }

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn stringifyJson(
    gpa: std.mem.Allocator,
    value: std.json.Value,
    options: std.json.Stringify.Options,
) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(value, options, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn formatPathSegment(writer: *std.Io.Writer, value: []const u8) !void {
    assert(value.len > 0);

    for (value) |byte| {
        if (isPathSegmentChar(byte)) {
            try writer.writeByte(byte);
        } else {
            try writer.print("%{X:0>2}", .{byte});
        }
    }
}

fn isPathSegmentChar(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

fn objectField(object: std.json.ObjectMap, name: []const u8) ?std.json.ObjectMap {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .object => |nested| nested,
        else => null,
    };
}

fn findStringField(objects: []const std.json.ObjectMap, name: []const u8) ?[]const u8 {
    for (objects) |object| {
        const value = object.get(name) orelse continue;
        return switch (value) {
            .string => |string| string,
            else => null,
        };
    }
    return null;
}

fn isSucceededState(state: []const u8) bool {
    return std.mem.eql(u8, state, "BATCH_STATE_SUCCEEDED") or
        std.mem.eql(u8, state, "JOB_STATE_SUCCEEDED");
}

fn findRequestCount(objects: []const std.json.ObjectMap) !?usize {
    for (objects) |object| {
        const stats = objectField(object, "batchStats") orelse continue;
        const value = stats.get("requestCount") orelse continue;
        return try parseRequestCount(value);
    }
    return null;
}

fn parseRequestCount(value: std.json.Value) !usize {
    const parsed: u64 = switch (value) {
        .string => |string| std.fmt.parseInt(u64, string, 10) catch {
            return error.InvalidBatchStatusResponse;
        },
        .number_string => |number| std.fmt.parseInt(u64, number, 10) catch {
            return error.InvalidBatchStatusResponse;
        },
        .integer => |integer| if (integer >= 0)
            @intCast(integer)
        else
            return error.InvalidBatchStatusResponse,
        else => return error.InvalidBatchStatusResponse,
    };
    return std.math.cast(usize, parsed) orelse return error.InvalidBatchStatusResponse;
}

fn findOutputFileName(objects: []const std.json.ObjectMap) ?[]const u8 {
    for (objects) |object| {
        if (objectField(object, "dest")) |dest| {
            if (stringField(dest, "fileName")) |file_name| return file_name;
        }
        if (objectField(object, "output")) |output| {
            if (stringField(output, "responsesFile")) |file_name| return file_name;
        }
        if (stringField(object, "responsesFile")) |file_name| return file_name;
        if (stringField(object, "fileName")) |file_name| return file_name;
    }
    return null;
}

fn stringField(object: std.json.ObjectMap, name: []const u8) ?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |string| string,
        else => null,
    };
}

fn isSafeOutputKeyByte(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => true,
        else => false,
    };
}

fn writeSafeOutputKeyByte(writer: *std.Io.Writer, byte: u8) !void {
    if (isSafeOutputKeyByte(byte)) {
        try writer.writeByte(byte);
    } else {
        try writer.print("~{X:0>2}", .{byte});
    }
}

test "buildEntryJson wraps request and escapes key" {
    const gpa = std.testing.allocator;
    const entry = try buildEntryJson(
        gpa,
        "hero-\"001",
        "{\"contents\":[{\"parts\":[{\"text\":\"hello\"}]}]}",
    );
    defer gpa.free(entry);

    try std.testing.expectEqualStrings(
        "{\"key\":\"hero-\\\"001\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"hello\"}]}]}}",
        entry,
    );
}

test "validateInputJsonl accepts LF and CRLF entries" {
    const input =
        "{\"key\":\"one\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}]}}\r\n" ++
        "{\"key\":\"two\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}}\n";
    try validateInputJsonl(input);
}

test "validateInputJsonl accepts maximum entries and rejects one over maximum" {
    const gpa = std.testing.allocator;

    const one = try testInputJsonl(gpa, 1);
    defer gpa.free(one);
    try validateInputJsonl(one);

    const maximum = try testInputJsonl(gpa, max_entries);
    defer gpa.free(maximum);
    try validateInputJsonl(maximum);

    const over_maximum = try testInputJsonl(gpa, max_entries + 1);
    defer gpa.free(over_maximum);
    try std.testing.expectError(
        error.BatchTooManyEntries,
        validateInputJsonl(over_maximum),
    );
}

test "validateInputJsonl accepts entry contents without semantic validation" {
    const input =
        "not-json\n" ++
        "{\"key\":\"\",\"request\":{}}\n" ++
        "{\"key\":\"one\",\"request\":[]}\n" ++
        "{\"key\":\"one\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}]}}\n" ++
        "{\"key\":\"one\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}}\n";

    try validateInputJsonl(input);
}

test "validateInputJsonl rejects empty input and blank entries" {
    try std.testing.expectError(
        error.EmptyBatchInput,
        validateInputJsonl(""),
    );
    try std.testing.expectError(
        error.InvalidBatchInput,
        validateInputJsonl("\n"),
    );
    try std.testing.expectError(
        error.InvalidBatchInput,
        validateInputJsonl("{\"key\":\"one\",\"request\":{}}\n\n"),
    );
}

test "validateInputJsonl enforces per-entry limit" {
    const gpa = std.testing.allocator;
    const input = try gpa.alloc(u8, max_entry_bytes + 1);
    defer gpa.free(input);
    @memset(input, 'x');

    try std.testing.expectError(
        error.BatchEntryTooLong,
        validateInputJsonl(input),
    );
}

test "validateInputJsonl accepts serialized entry at exact limit" {
    const gpa = std.testing.allocator;
    const request_json = "{\"contents\":[{\"parts\":[{\"text\":\"hello\"}]}]}";
    const overhead = "{\"key\":\"".len + "\",\"request\":".len + request_json.len + "}".len;
    assert(overhead < max_entry_bytes);

    const key = try gpa.alloc(u8, max_entry_bytes - overhead);
    defer gpa.free(key);
    @memset(key, 'a');

    const entry = try buildEntryJson(gpa, key, request_json);
    defer gpa.free(entry);
    try std.testing.expectEqual(@as(usize, max_entry_bytes), entry.len);
    try validateInputJsonl(entry);
}

test "validateInputByteCount enforces local input limit" {
    try validateInputByteCount(max_input_bytes);
    try std.testing.expectError(
        error.BatchInputTooLong,
        validateInputByteCount(max_input_bytes + 1),
    );
}

test "buildSubmitRequestJson uses uploaded file and display name" {
    const gpa = std.testing.allocator;
    const request_json = try buildSubmitRequestJson(gpa, .{
        .file_name = "files/abc123",
        .display_name = "requests.jsonl",
    });
    defer gpa.free(request_json);

    try std.testing.expectEqualStrings(
        "{\"batch\":{\"displayName\":\"requests.jsonl\",\"inputConfig\":{\"fileName\":\"files/abc123\"}}}",
        request_json,
    );
}

test "batch URLs use fixed model and canonical resource names" {
    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:batchGenerateContent",
        submitUrl(),
    );

    const gpa = std.testing.allocator;
    const status_url = try buildStatusUrl(gpa, "batches/abc 123/one");
    defer gpa.free(status_url);
    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/batches/abc%20123%2Fone",
        status_url,
    );

    const cancel_url = try buildCancelUrl(gpa, "batches/abc 123/one");
    defer gpa.free(cancel_url);
    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/batches/abc%20123%2Fone:cancel",
        cancel_url,
    );
}

test "batch list URLs use page size and percent-encoded token" {
    const gpa = std.testing.allocator;

    const first_url = try buildListUrl(gpa, null);
    defer gpa.free(first_url);
    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/batches?pageSize=100",
        first_url,
    );

    const next_url = try buildListUrl(gpa, "next token&one");
    defer gpa.free(next_url);
    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/batches?pageSize=100&pageToken=next%20token%26one",
        next_url,
    );
}

test "canonical batch names require batches prefix and id" {
    try std.testing.expect(isCanonicalBatchName("batches/abc123"));
    try std.testing.expect(!isCanonicalBatchName("abc123"));
    try std.testing.expect(!isCanonicalBatchName("batches/"));
    try std.testing.expect(!isCanonicalBatchName(""));
}

test "decodeBatchName accepts canonical name" {
    const gpa = std.testing.allocator;
    const name = try decodeBatchName(gpa, "{\"name\":\"batches/abc123\",\"state\":\"JOB_STATE_PENDING\"}");
    defer gpa.free(name);
    try std.testing.expectEqualStrings("batches/abc123", name);
}

test "decodeDownloadInfo accepts flattened and operation status shapes" {
    const gpa = std.testing.allocator;

    var flattened = try decodeDownloadInfo(
        gpa,
        "{\"name\":\"batches/one\",\"state\":\"JOB_STATE_SUCCEEDED\",\"batchStats\":{\"requestCount\":\"50\"},\"dest\":{\"fileName\":\"files/output-one\"}}",
    );
    defer flattened.deinit(gpa);
    try std.testing.expectEqualStrings("files/output-one", flattened.file_name);
    try std.testing.expectEqual(@as(?usize, 50), flattened.request_count);

    var operation = try decodeDownloadInfo(
        gpa,
        "{\"name\":\"batches/two\",\"metadata\":{\"state\":\"BATCH_STATE_SUCCEEDED\",\"batchStats\":{\"requestCount\":1},\"output\":{\"responsesFile\":\"files/output-two\"}},\"done\":true}",
    );
    defer operation.deinit(gpa);
    try std.testing.expectEqualStrings("files/output-two", operation.file_name);
    try std.testing.expectEqual(@as(?usize, 1), operation.request_count);

    var response_wrapped = try decodeDownloadInfo(
        gpa,
        "{\"name\":\"batches/three\",\"response\":{\"batch\":{\"state\":\"BATCH_STATE_SUCCEEDED\",\"output\":{\"responsesFile\":\"files/output-three\"}}}}",
    );
    defer response_wrapped.deinit(gpa);
    try std.testing.expectEqualStrings("files/output-three", response_wrapped.file_name);
    try std.testing.expectEqual(@as(?usize, null), response_wrapped.request_count);
}

test "decodeDownloadInfo rejects unfinished oversized and missing output status" {
    try std.testing.expectError(
        error.BatchNotSucceeded,
        decodeDownloadInfo(
            std.testing.allocator,
            "{\"state\":\"BATCH_STATE_RUNNING\",\"output\":{\"responsesFile\":\"files/output\"}}",
        ),
    );
    try std.testing.expectError(
        error.BatchTooManyEntries,
        decodeDownloadInfo(
            std.testing.allocator,
            "{\"state\":\"BATCH_STATE_SUCCEEDED\",\"batchStats\":{\"requestCount\":\"101\"},\"output\":{\"responsesFile\":\"files/output\"}}",
        ),
    );
    try std.testing.expectError(
        error.MissingBatchOutputFile,
        decodeDownloadInfo(
            std.testing.allocator,
            "{\"state\":\"BATCH_STATE_SUCCEEDED\",\"batchStats\":{\"requestCount\":\"1\"}}",
        ),
    );
}

test "batch output JSONL accepts maximum records and rejects one over maximum" {
    const gpa = std.testing.allocator;

    const one = try testOutputJsonl(gpa, 1);
    defer gpa.free(one);
    try std.testing.expectEqual(@as(usize, 1), try validateOutputJsonl(one));

    const maximum = try testOutputJsonl(gpa, max_entries);
    defer gpa.free(maximum);
    try std.testing.expectEqual(@as(usize, max_entries), try validateOutputJsonl(maximum));

    const over_maximum = try testOutputJsonl(gpa, max_entries + 1);
    defer gpa.free(over_maximum);
    try std.testing.expectError(
        error.BatchTooManyEntries,
        validateOutputJsonl(over_maximum),
    );
}

test "decodeOutputRecord distinguishes responses errors and malformed records" {
    const gpa = std.testing.allocator;

    var success = try decodeOutputRecord(
        gpa,
        "{\"key\":\"hero\",\"response\":{\"responseId\":\"id\",\"candidates\":[]}}",
    );
    defer success.deinit(gpa);
    try std.testing.expectEqualStrings("hero", success.key);
    try std.testing.expectEqualStrings(
        "{\"responseId\":\"id\",\"candidates\":[]}",
        success.response_json.?,
    );

    var failed = try decodeOutputRecord(
        gpa,
        "{\"key\":\"failed\",\"error\":{\"code\":400,\"message\":\"bad request\"}}",
    );
    defer failed.deinit(gpa);
    try std.testing.expectEqualStrings("failed", failed.key);
    try std.testing.expectEqual(@as(?[]u8, null), failed.response_json);

    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeOutputRecord(gpa, "not-json"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeOutputRecord(gpa, "{\"key\":\"both\",\"response\":{},\"error\":{}}"),
    );
}

test "safeOutputKey prevents path traversal and bounds long keys" {
    const gpa = std.testing.allocator;

    const safe = try safeOutputKey(gpa, "../../hero image");
    defer gpa.free(safe);
    try std.testing.expectEqualStrings("~2E~2E~2F~2E~2E~2Fhero~20image", safe);
    try std.testing.expect(std.mem.indexOfScalar(u8, safe, '/') == null);

    const long_key = "unsafe/key?" ** 100;
    const bounded = try safeOutputKey(gpa, long_key);
    defer gpa.free(bounded);
    try std.testing.expect(bounded.len <= max_safe_key_bytes);
    try std.testing.expect(std.mem.indexOfScalar(u8, bounded, '/') == null);
}

test "decodeListPage preserves operation fields and next page token" {
    const gpa = std.testing.allocator;
    var page = try decodeListPage(
        gpa,
        "{\"operations\":[{\"name\":\"batches/one\",\"metadata\":{\"count\":\"2\"},\"done\":false,\"large\":12345678901234567890},{\"name\":\"batches/two\",\"response\":{\"ok\":true}}],\"nextPageToken\":\"next-token\",\"ignored\":true}",
    );
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), page.operations.len);
    try std.testing.expectEqualStrings(
        "{\"name\":\"batches/one\",\"metadata\":{\"count\":\"2\"},\"done\":false,\"large\":12345678901234567890}",
        page.operations[0],
    );
    try std.testing.expectEqualStrings(
        "{\"name\":\"batches/two\",\"response\":{\"ok\":true}}",
        page.operations[1],
    );
    try std.testing.expectEqualStrings("next-token", page.next_page_token.?);
}

test "decodeListPage accepts empty results" {
    const gpa = std.testing.allocator;

    var absent = try decodeListPage(gpa, "{}");
    defer absent.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), absent.operations.len);
    try std.testing.expectEqual(@as(?[]u8, null), absent.next_page_token);

    var explicit = try decodeListPage(gpa, "{\"operations\":[],\"nextPageToken\":\"\"}");
    defer explicit.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), explicit.operations.len);
    try std.testing.expectEqual(@as(?[]u8, null), explicit.next_page_token);
}

test "decodeListPage rejects invalid batch operation names" {
    try std.testing.expectError(
        error.MissingBatchName,
        decodeListPage(std.testing.allocator, "{\"operations\":[{}]}"),
    );
    try std.testing.expectError(
        error.MissingBatchName,
        decodeListPage(std.testing.allocator, "{\"operations\":[{\"name\":\"batch/one\"}]}"),
    );
    try std.testing.expectError(
        error.MissingBatchName,
        decodeListPage(std.testing.allocator, "{\"operations\":[{\"name\":\"batches/\"}]}"),
    );
}

test "listJson aggregates pages and pretty prints operations" {
    const gpa = std.testing.allocator;
    var first = try decodeListPage(
        gpa,
        "{\"operations\":[{\"name\":\"batches/one\",\"done\":false}],\"nextPageToken\":\"next\"}",
    );
    defer first.deinit(gpa);
    var second = try decodeListPage(
        gpa,
        "{\"operations\":[{\"name\":\"batches/two\",\"metadata\":{\"state\":\"RUNNING\"}}]}",
    );
    defer second.deinit(gpa);

    var operations: std.ArrayList([]u8) = .empty;
    defer operations.deinit(gpa);
    try operations.appendSlice(gpa, first.operations);
    try operations.appendSlice(gpa, second.operations);

    const output = try listJson(gpa, operations.items);
    defer gpa.free(output);
    try std.testing.expectEqualStrings(
        "{\n  \"operations\": [\n    {\n      \"name\": \"batches/one\",\n      \"done\": false\n    },\n    {\n      \"name\": \"batches/two\",\n      \"metadata\": {\n        \"state\": \"RUNNING\"\n      }\n    }\n  ]\n}",
        output,
    );
}

test "listJson formats empty aggregate" {
    const gpa = std.testing.allocator;
    const output = try listJson(gpa, &.{});
    defer gpa.free(output);

    try std.testing.expectEqualStrings("{\n  \"operations\": []\n}", output);
}

test "prettyJson validates and preserves all response fields" {
    const gpa = std.testing.allocator;
    const output = try prettyJson(
        gpa,
        "{\"name\":\"batches/abc\",\"metadata\":{\"count\":\"2\"},\"done\":false,\"large\":12345678901234567890}",
    );
    defer gpa.free(output);

    try std.testing.expectEqualStrings(
        "{\n  \"name\": \"batches/abc\",\n  \"metadata\": {\n    \"count\": \"2\"\n  },\n  \"done\": false,\n  \"large\": 12345678901234567890\n}",
        output,
    );
}

test "prettyJson rejects malformed response" {
    try std.testing.expectError(
        error.UnexpectedEndOfInput,
        prettyJson(std.testing.allocator, "{"),
    );
}

test "batch download URL uses canonical generated file name" {
    const gpa = std.testing.allocator;
    const url = try buildOutputDownloadUrl(gpa, "files/output one");
    defer gpa.free(url);

    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/download/v1beta/files/output%20one:download?alt=media",
        url,
    );
}

fn testInputJsonl(gpa: std.mem.Allocator, entry_count: usize) ![]u8 {
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

fn testOutputJsonl(gpa: std.mem.Allocator, entry_count: usize) ![]u8 {
    assert(entry_count > 0);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    for (0..entry_count) |index| {
        try output.writer.print("record-{d}\n", .{index});
    }
    return output.toOwnedSlice();
}

test "live API batch submit status and cancel succeeds" {
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

    const first_request = try buildLiveGenerateRequest(gpa, "Create a simple red circle on a white background.");
    defer gpa.free(first_request);
    const second_request = try buildLiveGenerateRequest(gpa, "Create a simple blue square on a white background.");
    defer gpa.free(second_request);

    try std.testing.expect(std.mem.indexOf(u8, first_request, "\"imageSize\":\"IMAGE_SIZE_FIVE_TWELVE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, first_request, "thinkingConfig") == null);
    try std.testing.expect(std.mem.indexOf(u8, second_request, "\"imageSize\":\"IMAGE_SIZE_FIVE_TWELVE\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, second_request, "thinkingConfig") == null);

    const first_entry = try buildEntryJson(gpa, "nbimg-live-one", first_request);
    defer gpa.free(first_entry);
    const second_entry = try buildEntryJson(gpa, "nbimg-live-two", second_request);
    defer gpa.free(second_entry);
    const input = try std.fmt.allocPrint(gpa, "{s}\n{s}\n", .{ first_entry, second_entry });
    defer gpa.free(input);
    try validateInputJsonl(input);

    const display_name = "nbimg-live-batch.jsonl";
    var upload_response = try uploadInput(gpa, std.testing.io, api_key, input, display_name);
    defer upload_response.deinit(gpa);
    if (upload_response.status != .ok) {
        std.debug.print(
            "error: live batch input upload failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(upload_response.status), upload_response.body },
        );
        return error.BatchInputUploadFailed;
    }

    const uploaded_file_name = try api.decodeUploadedFileName(gpa, upload_response.body);
    defer gpa.free(uploaded_file_name);

    // BILLABLE and non-idempotent: this creates exactly one Batch job.
    var submit_response = try submit(gpa, std.testing.io, api_key, .{
        .file_name = uploaded_file_name,
        .display_name = display_name,
    });
    defer submit_response.deinit(gpa);
    if (submit_response.status != .ok) {
        std.debug.print(
            "error: live batch creation failed with HTTP {d}; uploaded input remains as {s}\n{s}\n",
            .{ @intFromEnum(submit_response.status), uploaded_file_name, submit_response.body },
        );
        return error.BatchCreationFailed;
    }

    const batch_name = try decodeBatchName(gpa, submit_response.body);
    defer gpa.free(batch_name);
    const pretty_submit = try prettyJson(gpa, submit_response.body);
    defer gpa.free(pretty_submit);

    var status_response = try status(gpa, std.testing.io, api_key, batch_name);
    defer status_response.deinit(gpa);
    if (status_response.status != .ok) {
        std.debug.print(
            "error: live batch status failed with HTTP {d} for {s}\n{s}\n",
            .{ @intFromEnum(status_response.status), batch_name, status_response.body },
        );
        return error.BatchStatusFailed;
    }

    const pretty_status = try prettyJson(gpa, status_response.body);
    defer gpa.free(pretty_status);

    var cancel_response = try cancel(gpa, std.testing.io, api_key, batch_name);
    defer cancel_response.deinit(gpa);
    if (cancel_response.status != .ok) {
        std.debug.print(
            "error: live batch cancel failed with HTTP {d} for {s}\n{s}\n",
            .{ @intFromEnum(cancel_response.status), batch_name, cancel_response.body },
        );
        return error.BatchCancelFailed;
    }
    try expectEmptyJsonObjectBody(gpa, cancel_response.body);

    var cancelled_status_response = try status(gpa, std.testing.io, api_key, batch_name);
    defer cancelled_status_response.deinit(gpa);
    if (cancelled_status_response.status != .ok) {
        std.debug.print(
            "error: live cancelled batch status failed with HTTP {d} for {s}\n{s}\n",
            .{ @intFromEnum(cancelled_status_response.status), batch_name, cancelled_status_response.body },
        );
        return error.BatchStatusFailed;
    }

    const pretty_cancelled_status = try prettyJson(gpa, cancelled_status_response.body);
    defer gpa.free(pretty_cancelled_status);
}

test "live API batch list succeeds" {
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

    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    var operations: std.ArrayList([]u8) = .empty;
    defer {
        for (operations.items) |operation| gpa.free(operation);
        operations.deinit(gpa);
    }

    while (true) {
        var response = try listPage(gpa, std.testing.io, api_key, page_token);
        defer response.deinit(gpa);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        if (response.status != .ok) {
            std.debug.print(
                "error: live batch list failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(response.status), response.body },
            );
            return error.BatchListFailed;
        }

        var page = try decodeListPage(gpa, response.body);
        defer page.deinit(gpa);

        try operations.ensureUnusedCapacity(gpa, page.operations.len);
        const page_operations = page.operations;
        for (page_operations) |operation| operations.appendAssumeCapacity(operation);
        page.operations = &.{};
        gpa.free(page_operations);

        page_token = page.next_page_token orelse break;
        page.next_page_token = null;
    }

    const output = try listJson(gpa, operations.items);
    defer gpa.free(output);
}

fn buildLiveGenerateRequest(gpa: std.mem.Allocator, prompt: []const u8) ![]u8 {
    const parts = [_]api.GeneratePart{.{ .text = prompt }};
    const contents = [_]api.GenerateContent{.{ .parts = &parts }};
    return api.buildGenerateContentRequestJson(gpa, &contents, .{
        .output_options = .{
            .image_size = .px512,
        },
    });
}

fn expectEmptyJsonObjectBody(gpa: std.mem.Allocator, body: []const u8) !void {
    try std.testing.expectEqualStrings("{}", std.mem.trim(u8, body, " \t\r\n"));

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, body, .{});
    defer parsed.deinit();

    switch (parsed.value) {
        .object => |object| try std.testing.expectEqual(@as(usize, 0), object.count()),
        else => return error.ExpectedEmptyJsonObject,
    }
}
