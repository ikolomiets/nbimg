//! Gemini Batch API JSONL validation, upload, submission, listing, status, and cancellation.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");
const file_domain = @import("files_domain.zig");
const operation_api = @import("operation.zig");

pub const max_batch_entry_bytes = api.max_generate_request_field_bytes;
pub const max_batch_entries = 100;
pub const max_batch_input_bytes = 512 * 1024 * 1024;
pub const max_entry_bytes = max_batch_entry_bytes;
pub const max_input_bytes = max_batch_input_bytes;
pub const max_output_bytes = 512 * 1024 * 1024;
pub const max_batch_output_bytes = max_output_bytes;
pub const max_entries = max_batch_entries;
const input_content_type = "application/jsonl";
const canonical_batch_name_prefix = "batches/";
const max_safe_key_bytes = 160;
const truncated_safe_key_prefix_bytes = 120;

/// Reports invalid caller-controlled Batch keys and JSONL input.
pub const BatchValidationError = error{
    EmptyBatchKey,
    EmptyBatchInput,
    InvalidBatchInput,
    BatchEntryTooLong,
    BatchTooManyEntries,
    BatchInputTooLong,
    InvalidBatchName,
    InvalidFileName,
    InvalidDisplayName,
    EmptyPageToken,
};

const BatchInputValidationError = error{
    EmptyBatchInput,
    InvalidBatchInput,
    BatchEntryTooLong,
    BatchTooManyEntries,
    BatchInputTooLong,
};

/// Summarizes one structurally valid borrowed Batch JSONL input.
pub const BatchInputSummary = struct {
    entry_count: usize,
    byte_count: usize,
};

/// Owns one prepared Batch JSONL record and its response-correlation key.
pub const PreparedBatchEntry = struct {
    key: []u8,
    jsonl_record: []u8,
    total_tokens: u64,

    /// Frees the key and JSONL record, then invalidates the value.
    pub fn deinit(entry: *PreparedBatchEntry, gpa: std.mem.Allocator) void {
        gpa.free(entry.key);
        gpa.free(entry.jsonl_record);
        entry.* = undefined;
    }
};

/// Describes borrowed JSONL bytes and optional Files API display metadata for a Batch input upload.
pub const BatchInputUpload = struct {
    bytes: []const u8,
    display_name: ?[]const u8 = null,
};

/// Describes a borrowed file-backed Batch creation request.
pub const BatchCreateRequest = struct {
    file_name: []const u8,
    display_name: []const u8,
    priority: ?i64 = null,
};

/// Describes borrowed input and display names for a batch submission.
///
/// - Both fields remain caller-owned through request construction and submission.
/// - The value allocates nothing and mutates no state.
pub const SubmitRequest = BatchCreateRequest;

/// Owns only unrecognized Gemini Batch state spellings.
pub const BatchState = union(enum) {
    unspecified,
    pending,
    running,
    succeeded,
    failed,
    cancelled,
    expired,
    unknown: []u8,

    /// Frees an unknown spelling, if present, and invalidates the value.
    pub fn deinit(state: *BatchState, allocator: std.mem.Allocator) void {
        switch (state.*) {
            .unknown => |name| allocator.free(name),
            else => {},
        }
        state.* = undefined;
    }
};

/// Holds decoded non-negative Batch request counters.
pub const BatchStats = struct {
    request_count: ?u64 = null,
    successful_request_count: ?u64 = null,
    failed_request_count: ?u64 = null,
    pending_request_count: ?u64 = null,
};

/// Owns a decoded Gemini Batch operation or resource view.
pub const BatchJob = struct {
    name: []u8,
    model: ?[]u8 = null,
    display_name: ?[]u8 = null,
    input_file_name: ?[]u8 = null,
    output_file_name: ?[]u8 = null,
    create_time: ?[]u8 = null,
    end_time: ?[]u8 = null,
    update_time: ?[]u8 = null,
    state: BatchState = .unspecified,
    stats: BatchStats = .{},
    priority: ?i64 = null,
    done: ?bool = null,
    remote_error: ?file_domain.RemoteError = null,

    /// Frees all nested owned data and invalidates the value.
    pub fn deinit(job: *BatchJob, allocator: std.mem.Allocator) void {
        allocator.free(job.name);
        freeOptional(allocator, job.model);
        freeOptional(allocator, job.display_name);
        freeOptional(allocator, job.input_file_name);
        freeOptional(allocator, job.output_file_name);
        freeOptional(allocator, job.create_time);
        freeOptional(allocator, job.end_time);
        freeOptional(allocator, job.update_time);
        job.state.deinit(allocator);
        if (job.remote_error) |*remote_error| remote_error.deinit(allocator);
        job.* = undefined;
    }
};

/// Owns one page of decoded Batch jobs and an optional continuation token.
pub const BatchListPage = struct {
    jobs: []BatchJob,
    next_page_token: ?[]u8 = null,

    /// Frees all nested jobs and pagination storage, then invalidates the page.
    pub fn deinit(page: *BatchListPage, allocator: std.mem.Allocator) void {
        for (page.jobs) |*job| job.deinit(allocator);
        allocator.free(page.jobs);
        if (page.next_page_token) |token| allocator.free(token);
        page.* = undefined;
    }
};

/// Owns decoded output-file information for a completed batch.
///
/// - `file_name` must be released with `deinit` using the allocator that created it.
/// - The value otherwise owns no external state.
pub const DownloadInfo = struct {
    file_name: []u8,
    request_count: ?usize,

    /// Frees decoded batch download information and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created `file_name`; no errors are returned.
    /// - Mutates only `info` and allocator state.
    pub fn deinit(info: *DownloadInfo, gpa: std.mem.Allocator) void {
        gpa.free(info.file_name);
        info.* = undefined;
    }
};

/// Owns a decoded batch output key and optional compact response JSON.
///
/// - All populated slices must be released with `deinit` using the originating allocator.
/// - The value otherwise owns no external state.
pub const OutputRecord = struct {
    key: []u8,
    response_json: ?[]u8,

    /// Frees a decoded output record and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `record` and allocator state.
    pub fn deinit(record: *OutputRecord, gpa: std.mem.Allocator) void {
        gpa.free(record.key);
        if (record.response_json) |response_json| gpa.free(response_json);
        record.* = undefined;
    }
};

/// Owns one typed batch output key and either compact response JSON or a remote error.
///
/// - All populated slices must be released with `deinit` using the originating allocator.
/// - The value otherwise owns no external state.
pub const DecodedBatchOutputRecord = struct {
    key: []u8,
    result: union(enum) {
        response_json: []u8,
        remote_error: file_domain.RemoteError,
    },

    /// Frees a decoded typed output record and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `record` and allocator state.
    pub fn deinit(record: *DecodedBatchOutputRecord, gpa: std.mem.Allocator) void {
        gpa.free(record.key);
        switch (record.result) {
            .response_json => |response_json| gpa.free(response_json),
            .remote_error => |*remote_error| remote_error.deinit(gpa),
        }
        record.* = undefined;
    }
};

/// Iterates borrowed batch-output bytes as bounded CRLF-aware lines.
///
/// - `bytes` remains caller-owned and must outlive the iterator.
/// - The iterator allocates nothing; `next` mutates only its offset and line count.
pub const OutputLineIterator = struct {
    bytes: []const u8,
    offset: usize = 0,
    line_count: usize = 0,

    /// Returns the next line as a borrowed slice.
    ///
    /// - The result aliases `iterator.bytes`; no allocation occurs.
    /// - Returns `BatchTooManyEntries` after the configured limit and mutates only iterator progress.
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

/// Owns compact operation JSON objects and an optional batch-list continuation token.
///
/// - All nested allocations must be released with `deinit` using their originating allocator.
/// - The value otherwise owns no external state.
pub const ListPage = struct {
    operations: [][]u8,
    next_page_token: ?[]u8 = null,

    /// Frees a decoded batch-list page and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `page` and allocator state.
    pub fn deinit(page: *ListPage, gpa: std.mem.Allocator) void {
        for (page.operations) |operation| gpa.free(operation);
        gpa.free(page.operations);
        if (page.next_page_token) |token| gpa.free(token);
        page.* = undefined;
    }
};

/// Wraps a borrowed generate-content JSON object as one owned batch JSONL entry.
///
/// - Borrows `key` and request JSON for the call; the returned slice is owned by `gpa`.
/// - Returns allocation or writer errors and mutates no input or global state.
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

/// Validates Batch input byte, line, entry-size, and entry-count limits.
///
/// - Borrows `bytes`, allocates nothing, and mutates no state.
/// - Returns a non-owning summary or a specific structural validation error.
pub fn validateBatchInput(bytes: []const u8) BatchValidationError!BatchInputSummary {
    return validateBatchInputInternal(bytes);
}

fn validateBatchInputInternal(bytes: []const u8) BatchInputValidationError!BatchInputSummary {
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
    return .{
        .entry_count = entry_count,
        .byte_count = bytes.len,
    };
}

/// Compatibility wrapper for the legacy Batch module API.
pub fn validateInputJsonl(bytes: []const u8) BatchInputValidationError!void {
    _ = try validateBatchInputInternal(bytes);
}

fn validateInputByteCount(byte_count: usize) BatchInputValidationError!void {
    if (byte_count == 0) return error.EmptyBatchInput;
    if (byte_count > max_input_bytes) return error.BatchInputTooLong;
}

/// Uploads borrowed batch JSONL bytes through the Gemini Files API.
///
/// - Borrows upload fields for the call; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, protocol, timeout, or logging errors and creates remote file state.
pub fn uploadInput(
    context: *const api.RequestContext,
    bytes: []const u8,
    display_name: ?[]const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(bytes.len > 0);
    assert(bytes.len <= max_input_bytes);
    if (display_name) |name| assert(api.isValidDisplayName(name));

    return api.uploadResumableBytes(context, .{
        .content_type = input_content_type,
        .bytes = bytes,
        .display_name = display_name,
    });
}

fn buildSubmitRequestJson(gpa: std.mem.Allocator, request: SubmitRequest) ![]u8 {
    assert(api.isCanonicalFileName(request.file_name));
    assert(api.isValidDisplayName(request.display_name));

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try output.writer.writeAll("{\"batch\":{\"displayName\":");
    try std.json.Stringify.value(request.display_name, .{}, &output.writer);
    try output.writer.writeAll(",\"inputConfig\":{\"fileName\":");
    try std.json.Stringify.value(request.file_name, .{}, &output.writer);
    try output.writer.writeByte('}');
    if (request.priority) |priority| {
        try output.writer.writeAll(",\"priority\":");
        try writeJsonIntString(&output.writer, priority);
    }
    try output.writer.writeAll("}}");

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

/// Creates a remote batch from a borrowed uploaded-file request.
///
/// - Borrows request fields; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns serialization, allocation, I/O, HTTP, timeout, or logging errors and creates non-idempotent remote state.
pub fn submit(
    context: *const api.RequestContext,
    request: SubmitRequest,
) !api.HttpResponse {
    const request_json = try buildSubmitRequestJson(context.gpa, request);
    defer context.gpa.free(request_json);

    // Batch creation is non-idempotent. This call is intentionally made once.
    return api.postJson(context, submitUrl(), request_json);
}

/// Fetches the status of a canonical batch resource.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates no input or remote state.
pub fn status(
    context: *const api.RequestContext,
    name: []const u8,
) !api.HttpResponse {
    assert(isCanonicalBatchName(name));

    const url = try buildStatusUrl(context.gpa, name);
    defer context.gpa.free(url);
    return api.getJson(context, url);
}

/// Decodes completed-batch output metadata into an owned result.
///
/// - Borrows `response_json`; `file_name` is owned by `gpa` and requires `DownloadInfo.deinit`.
/// - Returns allocation, invalid-status, not-succeeded, limit, or missing-output errors and mutates no state.
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

/// Downloads a canonical batch output file with a fixed response-size bound.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, size-limit, or logging errors and mutates no input or remote state.
pub fn downloadOutput(
    context: *const api.RequestContext,
    file_name: []const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(api.isCanonicalFileName(file_name));

    const url = try buildOutputDownloadUrl(context.gpa, file_name);
    defer context.gpa.free(url);
    return api.getBytesBounded(context, url, max_output_bytes);
}

/// Cancels a canonical remote batch.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates remote batch state.
pub fn cancel(
    context: *const api.RequestContext,
    name: []const u8,
) !api.HttpResponse {
    assert(isCanonicalBatchName(name));

    const url = try buildCancelUrl(context.gpa, name);
    defer context.gpa.free(url);
    return api.postJsonWithoutBody(context, url);
}

/// Fetches one batch-list page using an optional borrowed continuation token.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates no input or remote state.
pub fn listPage(
    context: *const api.RequestContext,
    page_token: ?[]const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    if (page_token) |token| assert(token.len > 0);

    const url = try buildListUrl(context.gpa, page_token);
    defer context.gpa.free(url);
    return api.getJson(context, url);
}

/// Uploads and decodes one Batch JSONL input File using an explicit request context.
pub fn uploadBatchInputWithContext(
    context: *const api.RequestContext,
    upload: BatchInputUpload,
) !operation_api.OperationOutcome(file_domain.File) {
    try validateBatchInputUpload(upload);

    var response = try uploadInput(context, upload.bytes, upload.display_name);
    return typedBatchOutcomeFromResponse(
        file_domain.File,
        context.gpa,
        &response,
        decodeUploadedBatchInput,
    );
}

/// Creates and decodes one file-backed Batch job using an explicit request context.
pub fn createBatchWithContext(
    context: *const api.RequestContext,
    request: BatchCreateRequest,
) !operation_api.OperationOutcome(BatchJob) {
    try validateBatchCreateRequest(request);

    var response = try submit(context, request);
    return typedBatchOutcomeFromResponse(
        BatchJob,
        context.gpa,
        &response,
        decodeBatchJob,
    );
}

/// Fetches and decodes one Batch job using an explicit request context.
pub fn getBatchWithContext(
    context: *const api.RequestContext,
    name: []const u8,
) !operation_api.OperationOutcome(BatchJob) {
    try validateBatchName(name);

    var response = try status(context, name);
    return typedBatchOutcomeFromResponse(
        BatchJob,
        context.gpa,
        &response,
        decodeBatchJob,
    );
}

/// Requests cancellation for one Batch job using an explicit request context.
pub fn cancelBatchWithContext(
    context: *const api.RequestContext,
    name: []const u8,
) !operation_api.OperationOutcome(void) {
    try validateBatchName(name);

    var response = try cancel(context, name);
    return emptyBatchOutcomeFromResponse(context.gpa, &response);
}

/// Fetches and decodes one Batch list page using an explicit request context.
pub fn listBatchesPageWithContext(
    context: *const api.RequestContext,
    page_token: ?[]const u8,
) !operation_api.OperationOutcome(BatchListPage) {
    try validatePageToken(page_token);

    var response = try listPage(context, page_token);
    return typedBatchOutcomeFromResponse(
        BatchListPage,
        context.gpa,
        &response,
        decodeBatchListPage,
    );
}

/// Reports whether a string is a canonical non-empty batch resource name.
///
/// - Borrows `name`, allocates nothing, returns no errors, and mutates no state.
pub fn isCanonicalBatchName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_batch_name_prefix)) return false;
    return name.len > canonical_batch_name_prefix.len;
}

/// Decodes and copies a canonical batch name from a submission response.
///
/// - Borrows `response_json`; the returned slice is owned by `gpa`.
/// - Returns allocation, JSON parsing, or `MissingBatchName` errors and mutates no input or global state.
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

/// Validates batch output line count and returns the number of records.
///
/// - Borrows `bytes`, allocates nothing, and mutates no state.
/// - Returns `EmptyBatchOutput` or `BatchTooManyEntries` for invalid bounds.
pub fn validateOutputJsonl(bytes: []const u8) !usize {
    if (bytes.len == 0) return error.EmptyBatchOutput;

    var iterator = OutputLineIterator{ .bytes = bytes };
    while (try iterator.next()) |_| {}
    assert(iterator.line_count > 0);
    assert(iterator.line_count <= max_entries);
    return iterator.line_count;
}

/// Decodes one borrowed batch output line into an owned record.
///
/// - Allocates returned strings with `gpa`; the caller must invoke `OutputRecord.deinit`.
/// - Returns allocation or `InvalidBatchOutput` errors and mutates no input or global state.
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

/// Decodes one borrowed batch output line into an owned typed record.
///
/// - Allocates returned data with `gpa`; the caller must invoke `DecodedBatchOutputRecord.deinit`.
/// - Returns allocation, JSON, remote-error, or `InvalidBatchOutput` errors and mutates no input.
pub fn decodeBatchOutputRecord(gpa: std.mem.Allocator, line: []const u8) !DecodedBatchOutputRecord {
    if (line.len == 0) return error.InvalidBatchOutput;

    var parsed = std.json.parseFromSlice(std.json.Value, gpa, line, .{
        .parse_numbers = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBatchOutput,
    };
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidBatchOutput,
    };

    const key_value = root.get("key") orelse return error.InvalidBatchOutput;
    const key = switch (key_value) {
        .string => |string| string,
        else => return error.InvalidBatchOutput,
    };
    if (key.len == 0) return error.InvalidBatchOutput;

    const response_value = root.get("response");
    const error_value = root.get("error");
    if (response_value != null and error_value != null) return error.InvalidBatchOutput;
    if (response_value == null and error_value == null) return error.InvalidBatchOutput;

    const owned_key = try gpa.dupe(u8, key);
    errdefer gpa.free(owned_key);

    if (response_value) |response| {
        if (response != .object) return error.InvalidBatchOutput;
        const response_json = try stringifyJson(gpa, response, .{});
        errdefer gpa.free(response_json);
        return .{
            .key = owned_key,
            .result = .{ .response_json = response_json },
        };
    }

    var remote_error = try file_domain.remoteErrorFromJsonValue(gpa, error_value.?);
    errdefer remote_error.deinit(gpa);
    return .{
        .key = owned_key,
        .result = .{ .remote_error = remote_error },
    };
}

/// Encodes a borrowed batch key as a bounded filesystem-safe owned string.
///
/// - Borrows `key`; the returned slice is owned by `gpa`.
/// - Returns allocation, writer, invalid-key, or overflow errors and mutates no input or global state.
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

/// Decodes a batch-list response into an owned page.
///
/// - Borrows `response_json`; all returned slices are owned by `gpa` and require `ListPage.deinit`.
/// - Returns allocation, JSON, invalid-response, or missing-name errors and mutates no input or global state.
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

fn decodeUploadedBatchInput(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.File {
    return file_domain.decodeUploadedFile(gpa, response_json);
}

fn decodeBatchJob(gpa: std.mem.Allocator, response_json: []const u8) !BatchJob {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, response_json, .{
        .parse_numbers = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBatchResponse,
    };
    defer parsed.deinit();

    return ownedBatchJobFromValue(gpa, parsed.value);
}

fn decodeBatchListPage(gpa: std.mem.Allocator, response_json: []const u8) !BatchListPage {
    var parsed = std.json.parseFromSlice(std.json.Value, gpa, response_json, .{
        .parse_numbers = false,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBatchListResponse,
    };
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidBatchListResponse,
    };

    const operation_values: []const std.json.Value = if (root.get("operations")) |value| switch (value) {
        .array => |array| array.items,
        else => return error.InvalidBatchListResponse,
    } else &.{};

    const jobs = try gpa.alloc(BatchJob, operation_values.len);
    var job_count: usize = 0;
    errdefer {
        for (jobs[0..job_count]) |*job| job.deinit(gpa);
        gpa.free(jobs);
    }

    for (operation_values) |operation_value| {
        jobs[job_count] = try ownedBatchJobFromValue(gpa, operation_value);
        job_count += 1;
    }
    assert(job_count == jobs.len);

    const next_page_token: ?[]u8 = if (root.get("nextPageToken")) |value| switch (value) {
        .string => |token| if (token.len == 0) null else try gpa.dupe(u8, token),
        else => return error.InvalidBatchListResponse,
    } else null;
    errdefer if (next_page_token) |token| gpa.free(token);

    return .{
        .jobs = jobs,
        .next_page_token = next_page_token,
    };
}

fn ownedBatchJobFromValue(gpa: std.mem.Allocator, value: std.json.Value) !BatchJob {
    const root = switch (value) {
        .object => |object| object,
        else => return error.InvalidBatchResponse,
    };

    var candidate_objects: [4]std.json.ObjectMap = undefined;
    const candidates = try batchCandidateObjects(root, &candidate_objects);

    const name = try findBatchName(candidates);
    var job = BatchJob{
        .name = try gpa.dupe(u8, name),
    };
    errdefer job.deinit(gpa);

    job.model = try dupeCanonicalModelName(gpa, try findTypedStringField(candidates, "model"));
    job.display_name = try dupeOptional(gpa, try findTypedStringField(candidates, "displayName"));
    job.input_file_name = try dupeCanonicalFileName(gpa, try findInputFileName(candidates));
    job.output_file_name = try dupeCanonicalFileName(gpa, try findBatchOutputFileName(candidates));
    job.create_time = try dupeOptional(gpa, try findTypedStringField(candidates, "createTime"));
    job.end_time = try dupeOptional(gpa, try findTypedStringField(candidates, "endTime"));
    job.update_time = try dupeOptional(gpa, try findTypedStringField(candidates, "updateTime"));
    job.state = try ownedBatchState(gpa, try findTypedStringField(candidates, "state"));
    job.stats = try findBatchStats(candidates);
    job.priority = try findBatchPriority(candidates);
    job.done = try boolField(root, "done");
    job.remote_error = try ownedOperationError(gpa, root);

    return job;
}

fn batchCandidateObjects(
    root: std.json.ObjectMap,
    candidate_objects: *[4]std.json.ObjectMap,
) ![]const std.json.ObjectMap {
    var candidate_count: usize = 0;
    candidate_objects[candidate_count] = root;
    candidate_count += 1;

    if (try typedObjectField(root, "metadata")) |metadata| {
        candidate_objects[candidate_count] = metadata;
        candidate_count += 1;
    }
    if (try typedObjectField(root, "response")) |response| {
        candidate_objects[candidate_count] = response;
        candidate_count += 1;
        if (try typedObjectField(response, "batch")) |batch| {
            candidate_objects[candidate_count] = batch;
            candidate_count += 1;
        }
    }

    assert(candidate_count <= candidate_objects.len);
    return candidate_objects[0..candidate_count];
}

fn findBatchName(objects: []const std.json.ObjectMap) ![]const u8 {
    for (objects) |object| {
        const value = object.get("name") orelse continue;
        const name = switch (value) {
            .string => |string| string,
            else => return error.InvalidBatchName,
        };
        if (!isCanonicalBatchName(name)) return error.InvalidBatchName;
        return name;
    }
    return error.MissingBatchName;
}

fn findTypedStringField(
    objects: []const std.json.ObjectMap,
    name: []const u8,
) !?[]const u8 {
    for (objects) |object| {
        const value = object.get(name) orelse continue;
        return switch (value) {
            .string => |string| string,
            else => error.InvalidBatchResponse,
        };
    }
    return null;
}

fn findInputFileName(objects: []const std.json.ObjectMap) !?[]const u8 {
    for (objects) |object| {
        const input_config = try typedObjectField(object, "inputConfig") orelse continue;
        if (try typedStringField(input_config, "fileName")) |file_name| return file_name;
    }
    return null;
}

fn findBatchOutputFileName(objects: []const std.json.ObjectMap) !?[]const u8 {
    for (objects) |object| {
        if (try typedObjectField(object, "dest")) |dest| {
            if (try typedStringField(dest, "fileName")) |file_name| return file_name;
        }
        if (try typedObjectField(object, "output")) |output| {
            if (try typedStringField(output, "responsesFile")) |file_name| return file_name;
        }
        if (try typedStringField(object, "responsesFile")) |file_name| return file_name;
    }
    return null;
}

fn findBatchStats(objects: []const std.json.ObjectMap) !BatchStats {
    for (objects) |object| {
        const stats = try typedObjectField(object, "batchStats") orelse continue;
        return .{
            .request_count = try optionalUnsignedField(stats, "requestCount"),
            .successful_request_count = try optionalUnsignedField(stats, "successfulRequestCount"),
            .failed_request_count = try optionalUnsignedField(stats, "failedRequestCount"),
            .pending_request_count = try optionalUnsignedField(stats, "pendingRequestCount"),
        };
    }
    return .{};
}

fn findBatchPriority(objects: []const std.json.ObjectMap) !?i64 {
    for (objects) |object| {
        const value = object.get("priority") orelse continue;
        return try parseSignedJsonInteger(value);
    }
    return null;
}

fn ownedBatchState(
    gpa: std.mem.Allocator,
    wire_name: ?[]const u8,
) !BatchState {
    const name = wire_name orelse return .unspecified;
    if (std.mem.eql(u8, name, "BATCH_STATE_UNSPECIFIED") or
        std.mem.eql(u8, name, "JOB_STATE_UNSPECIFIED"))
    {
        return .unspecified;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_PENDING") or
        std.mem.eql(u8, name, "JOB_STATE_PENDING"))
    {
        return .pending;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_RUNNING") or
        std.mem.eql(u8, name, "JOB_STATE_RUNNING"))
    {
        return .running;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_SUCCEEDED") or
        std.mem.eql(u8, name, "JOB_STATE_SUCCEEDED"))
    {
        return .succeeded;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_FAILED") or
        std.mem.eql(u8, name, "JOB_STATE_FAILED"))
    {
        return .failed;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_CANCELLED") or
        std.mem.eql(u8, name, "JOB_STATE_CANCELLED"))
    {
        return .cancelled;
    }
    if (std.mem.eql(u8, name, "BATCH_STATE_EXPIRED") or
        std.mem.eql(u8, name, "JOB_STATE_EXPIRED"))
    {
        return .expired;
    }
    return .{ .unknown = try gpa.dupe(u8, name) };
}

fn ownedOperationError(gpa: std.mem.Allocator, root: std.json.ObjectMap) !?file_domain.RemoteError {
    const value = root.get("error") orelse return null;
    return try file_domain.remoteErrorFromJsonValue(gpa, value);
}

fn typedObjectField(object: std.json.ObjectMap, name: []const u8) !?std.json.ObjectMap {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .object => |nested| nested,
        else => error.InvalidBatchResponse,
    };
}

fn typedStringField(object: std.json.ObjectMap, name: []const u8) !?[]const u8 {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .string => |string| string,
        else => error.InvalidBatchResponse,
    };
}

fn boolField(object: std.json.ObjectMap, name: []const u8) !?bool {
    const value = object.get(name) orelse return null;
    return switch (value) {
        .bool => |boolean| boolean,
        else => error.InvalidBatchResponse,
    };
}

fn optionalUnsignedField(object: std.json.ObjectMap, name: []const u8) !?u64 {
    const value = object.get(name) orelse return null;
    return try parseUnsignedJsonInteger(value);
}

fn parseUnsignedJsonInteger(value: std.json.Value) !u64 {
    return switch (value) {
        .string => |string| parseUnsignedJsonIntegerText(string),
        .number_string => |number| parseUnsignedJsonIntegerText(number),
        .integer => |integer| if (integer >= 0)
            @intCast(integer)
        else
            error.InvalidBatchCounter,
        else => error.InvalidBatchCounter,
    };
}

fn parseUnsignedJsonIntegerText(bytes: []const u8) !u64 {
    if (bytes.len == 0) return error.InvalidBatchCounter;
    return std.fmt.parseInt(u64, bytes, 10) catch return error.InvalidBatchCounter;
}

fn parseSignedJsonInteger(value: std.json.Value) !i64 {
    return switch (value) {
        .string => |string| parseSignedJsonIntegerText(string),
        .number_string => |number| parseSignedJsonIntegerText(number),
        .integer => |integer| std.math.cast(i64, integer) orelse return error.InvalidBatchPriority,
        else => error.InvalidBatchPriority,
    };
}

fn parseSignedJsonIntegerText(bytes: []const u8) !i64 {
    if (bytes.len == 0) return error.InvalidBatchPriority;
    return std.fmt.parseInt(i64, bytes, 10) catch return error.InvalidBatchPriority;
}

fn dupeCanonicalFileName(gpa: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    const name = value orelse return null;
    if (!api.isCanonicalFileName(name)) return error.InvalidFileName;
    return try gpa.dupe(u8, name);
}

fn dupeCanonicalModelName(gpa: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    const name = value orelse return null;
    if (!isCanonicalModelName(name)) return error.InvalidModelName;
    return try gpa.dupe(u8, name);
}

fn dupeOptional(gpa: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try gpa.dupe(u8, bytes) else null;
}

fn isCanonicalModelName(name: []const u8) bool {
    const prefix = "models/";
    if (!std.mem.startsWith(u8, name, prefix)) return false;
    return name.len > prefix.len;
}

fn typedBatchOutcomeFromResponse(
    comptime T: type,
    gpa: std.mem.Allocator,
    response: *api.HttpResponse,
    comptime decode: fn (std.mem.Allocator, []const u8) anyerror!T,
) operation_api.OperationOutcome(T) {
    if (response.status.class() != .success) {
        const failure = operation_api.ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    defer response.deinit(gpa);

    const result = decode(gpa, response.body) catch |err| {
        return .{ .response_decoding_failure = err };
    };
    return .{ .success = result };
}

fn emptyBatchOutcomeFromResponse(
    gpa: std.mem.Allocator,
    response: *api.HttpResponse,
) operation_api.OperationOutcome(void) {
    if (response.status.class() != .success) {
        const failure = operation_api.ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    response.deinit(gpa);
    return .{ .success = {} };
}

fn validateBatchInputUpload(upload: BatchInputUpload) BatchValidationError!void {
    _ = try validateBatchInput(upload.bytes);
    if (upload.display_name) |display_name| {
        if (!api.isValidDisplayName(display_name)) return error.InvalidDisplayName;
    }
}

fn validateBatchCreateRequest(request: BatchCreateRequest) BatchValidationError!void {
    if (!api.isCanonicalFileName(request.file_name)) return error.InvalidFileName;
    if (!api.isValidDisplayName(request.display_name)) return error.InvalidDisplayName;
}

fn validateBatchName(name: []const u8) BatchValidationError!void {
    if (!isCanonicalBatchName(name)) return error.InvalidBatchName;
}

fn validatePageToken(page_token: ?[]const u8) BatchValidationError!void {
    if (page_token) |token| {
        if (token.len == 0) return error.EmptyPageToken;
    }
}

/// Combines borrowed operation JSON objects into one owned pretty-printed list.
///
/// - Borrows all operation slices for the call; the returned JSON is owned by `gpa`.
/// - Returns allocation, parsing, or writer errors and mutates no input or global state.
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

/// Pretty-prints borrowed JSON into an owned two-space-indented buffer.
///
/// - Borrows `response_json`; the returned slice is owned by `gpa`.
/// - Returns allocation, JSON parsing, or writer errors and mutates no input or global state.
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

fn writeJsonIntString(writer: *std.Io.Writer, value: i64) !void {
    try writer.writeByte('"');
    try writer.print("{d}", .{value});
    try writer.writeByte('"');
}

fn freeOptional(gpa: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| gpa.free(bytes);
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

test "PreparedBatchEntry owns and frees key and JSONL record" {
    var entry = PreparedBatchEntry{
        .key = try std.testing.allocator.dupe(u8, "hero-001"),
        .jsonl_record = try std.testing.allocator.dupe(
            u8,
            "{\"key\":\"hero-001\",\"request\":{}}",
        ),
        .total_tokens = 42,
    };

    try std.testing.expectEqualStrings("hero-001", entry.key);
    try std.testing.expectEqual(@as(u64, 42), entry.total_tokens);
    entry.deinit(std.testing.allocator);
}

test "validateBatchInput summarizes LF and CRLF entries" {
    const input =
        "{\"key\":\"one\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"one\"}]}]}}\r\n" ++
        "{\"key\":\"two\",\"request\":{\"contents\":[{\"parts\":[{\"text\":\"two\"}]}]}}\n";
    const summary = try validateBatchInput(input);
    try std.testing.expectEqual(@as(usize, 2), summary.entry_count);
    try std.testing.expectEqual(input.len, summary.byte_count);
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

    const summary = try validateBatchInput(input);
    try std.testing.expectEqual(@as(usize, 5), summary.entry_count);
    try std.testing.expectEqual(input.len, summary.byte_count);
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

test "stable Batch admission limits match legacy names" {
    try std.testing.expectEqual(max_batch_entry_bytes, max_entry_bytes);
    try std.testing.expectEqual(max_batch_entries, max_entries);
    try std.testing.expectEqual(max_batch_input_bytes, max_input_bytes);
}

test "BatchValidationError exposes deliberate validation errors" {
    const errors = [_]BatchValidationError{
        error.EmptyBatchKey,
        error.EmptyBatchInput,
        error.InvalidBatchInput,
        error.BatchEntryTooLong,
        error.BatchTooManyEntries,
        error.BatchInputTooLong,
        error.InvalidBatchName,
        error.InvalidFileName,
        error.InvalidDisplayName,
        error.EmptyPageToken,
    };
    try std.testing.expectEqual(@as(usize, 10), errors.len);
}

test "typed Batch validation runs before transport fields are used" {
    try std.testing.expectError(
        error.EmptyBatchInput,
        validateBatchInputUpload(.{ .bytes = "" }),
    );
    try std.testing.expectError(
        error.InvalidDisplayName,
        validateBatchInputUpload(.{ .bytes = "{\"key\":\"one\",\"request\":{}}", .display_name = "" }),
    );
    try validateBatchInputUpload(.{
        .bytes = "{\"key\":\"one\",\"request\":{}}",
        .display_name = "requests.jsonl",
    });

    try std.testing.expectError(
        error.InvalidFileName,
        validateBatchCreateRequest(.{ .file_name = "batch-input", .display_name = "requests.jsonl" }),
    );
    try std.testing.expectError(
        error.InvalidDisplayName,
        validateBatchCreateRequest(.{ .file_name = "files/input", .display_name = "" }),
    );
    try validateBatchCreateRequest(.{
        .file_name = "files/input",
        .display_name = "requests.jsonl",
        .priority = -7,
    });

    try std.testing.expectError(error.InvalidBatchName, validateBatchName("batch/one"));
    try std.testing.expectError(error.InvalidBatchName, validateBatchName("batches/"));
    try validateBatchName("batches/one");
    try std.testing.expectError(error.EmptyPageToken, validatePageToken(""));
    try validatePageToken(null);
    try validatePageToken("next");
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

test "buildSubmitRequestJson serializes optional priority as int64 string" {
    const gpa = std.testing.allocator;
    const request_json = try buildSubmitRequestJson(gpa, .{
        .file_name = "files/abc123",
        .display_name = "requests.jsonl",
        .priority = -9223372036854775808,
    });
    defer gpa.free(request_json);

    try std.testing.expectEqualStrings(
        "{\"batch\":{\"displayName\":\"requests.jsonl\",\"inputConfig\":{\"fileName\":\"files/abc123\"},\"priority\":\"-9223372036854775808\"}}",
        request_json,
    );
}

test "typed Batch input upload decoder accepts JSONL File metadata" {
    var file = try decodeUploadedBatchInput(
        std.testing.allocator,
        "{\"file\":{\"name\":\"files/input\",\"displayName\":\"requests.jsonl\",\"mimeType\":\"application/jsonl\",\"sizeBytes\":\"27\",\"state\":\"ACTIVE\",\"source\":\"UPLOADED\"}}",
    );
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("files/input", file.name);
    try std.testing.expectEqualStrings("requests.jsonl", file.display_name.?);
    try std.testing.expectEqualStrings("application/jsonl", file.mime_type.?);
    try std.testing.expectEqual(@as(?u64, 27), file.size_bytes);
    try std.testing.expect(file.state == .active);
    try std.testing.expect(file.source == .uploaded);
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

test "decodeBatchOutputRecord decodes success and remote error records" {
    const gpa = std.testing.allocator;

    var success = try decodeBatchOutputRecord(
        gpa,
        "{\"key\":\"hero\",\"response\":{\"responseId\":\"id\",\"candidates\":[],\"large\":12345678901234567890}}",
    );
    defer success.deinit(gpa);
    try std.testing.expectEqualStrings("hero", success.key);
    switch (success.result) {
        .response_json => |response_json| {
            try std.testing.expectEqualStrings(
                "{\"responseId\":\"id\",\"candidates\":[],\"large\":12345678901234567890}",
                response_json,
            );
        },
        .remote_error => return error.UnexpectedRemoteError,
    }

    var failed = try decodeBatchOutputRecord(
        gpa,
        "{\"key\":\"failed\",\"error\":{\"code\":\"400\",\"message\":\"bad request\",\"details\":[{\"reason\":\"invalid\"}]}}",
    );
    defer failed.deinit(gpa);
    try std.testing.expectEqualStrings("failed", failed.key);
    switch (failed.result) {
        .response_json => return error.UnexpectedResponseJson,
        .remote_error => |remote_error| {
            try std.testing.expectEqual(@as(?i64, 400), remote_error.code);
            try std.testing.expectEqualStrings("bad request", remote_error.message);
            try std.testing.expectEqualStrings("[{\"reason\":\"invalid\"}]", remote_error.details_json.?);
        },
    }
}

test "decodeBatchOutputRecord rejects malformed typed records" {
    const gpa = std.testing.allocator;

    try std.testing.expectError(error.InvalidBatchOutput, decodeBatchOutputRecord(gpa, ""));
    try std.testing.expectError(error.InvalidBatchOutput, decodeBatchOutputRecord(gpa, "not-json"));
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"key\":\"\",\"response\":{}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"response\":{}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"key\":7,\"response\":{}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"key\":\"both\",\"response\":{},\"error\":{\"message\":\"bad\"}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"key\":\"neither\"}"),
    );
    try std.testing.expectError(
        error.InvalidBatchOutput,
        decodeBatchOutputRecord(gpa, "{\"key\":\"bad-response\",\"response\":[]}"),
    );
    try std.testing.expectError(
        error.MissingRemoteErrorMessage,
        decodeBatchOutputRecord(gpa, "{\"key\":\"bad-error\",\"error\":{\"code\":400}}"),
    );
}

test "typed batch output iteration is CRLF aware and preserves duplicate keys" {
    const gpa = std.testing.allocator;
    const input =
        "{\"key\":\"same\",\"response\":{\"responseId\":\"one\",\"candidates\":[]}}\r\n" ++
        "{\"key\":\"same\",\"error\":{\"message\":\"failed\"}}\n";

    var iterator = OutputLineIterator{ .bytes = input };

    const first_line = (try iterator.next()).?;
    var first = try decodeBatchOutputRecord(gpa, first_line);
    defer first.deinit(gpa);
    try std.testing.expectEqualStrings("same", first.key);
    switch (first.result) {
        .response_json => |response_json| {
            try std.testing.expectEqualStrings(
                "{\"responseId\":\"one\",\"candidates\":[]}",
                response_json,
            );
        },
        .remote_error => return error.UnexpectedRemoteError,
    }

    const second_line = (try iterator.next()).?;
    var second = try decodeBatchOutputRecord(gpa, second_line);
    defer second.deinit(gpa);
    try std.testing.expectEqualStrings("same", second.key);
    switch (second.result) {
        .response_json => return error.UnexpectedResponseJson,
        .remote_error => |remote_error| {
            try std.testing.expectEqualStrings("failed", remote_error.message);
        },
    }

    try std.testing.expectEqual(@as(?[]const u8, null), try iterator.next());
    try std.testing.expectEqual(@as(usize, 2), iterator.line_count);
}

test "typed batch output iteration enforces record count limit" {
    const gpa = std.testing.allocator;

    const maximum = try testTypedOutputJsonl(gpa, max_entries);
    defer gpa.free(maximum);
    var maximum_iterator = OutputLineIterator{ .bytes = maximum };
    var maximum_count: usize = 0;
    while (try maximum_iterator.next()) |line| {
        var record = try decodeBatchOutputRecord(gpa, line);
        defer record.deinit(gpa);
        maximum_count += 1;
    }
    try std.testing.expectEqual(@as(usize, max_entries), maximum_count);

    const over_maximum = try testTypedOutputJsonl(gpa, max_entries + 1);
    defer gpa.free(over_maximum);
    var over_maximum_iterator = OutputLineIterator{ .bytes = over_maximum };
    var accepted_count: usize = 0;
    while (true) {
        const line = over_maximum_iterator.next() catch |err| {
            try std.testing.expectEqual(error.BatchTooManyEntries, err);
            break;
        };
        if (line == null) return error.ExpectedBatchTooManyEntries;
        var record = try decodeBatchOutputRecord(gpa, line.?);
        defer record.deinit(gpa);
        accepted_count += 1;
    }
    try std.testing.expectEqual(@as(usize, max_entries), accepted_count);
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

test "typed Batch decoder accepts operation wrappers and owns fields" {
    const gpa = std.testing.allocator;
    var job = try decodeBatchJob(
        gpa,
        "{\"name\":\"batches/one\",\"metadata\":{\"model\":\"models/gemini-3.1-flash-image\",\"displayName\":\"requests.jsonl\",\"inputConfig\":{\"fileName\":\"files/input\"},\"output\":{\"responsesFile\":\"files/output\"},\"createTime\":\"2026-06-24T00:00:00Z\",\"endTime\":\"2026-06-24T00:01:00Z\",\"updateTime\":\"2026-06-24T00:02:00Z\",\"batchStats\":{\"requestCount\":\"2\",\"successfulRequestCount\":1,\"failedRequestCount\":\"0\",\"pendingRequestCount\":0},\"state\":\"BATCH_STATE_SUCCEEDED\",\"priority\":\"-3\"},\"done\":true,\"error\":{\"code\":1,\"message\":\"cancelled\",\"details\":[{\"reason\":\"user\"}]}}",
    );
    defer job.deinit(gpa);

    try std.testing.expectEqualStrings("batches/one", job.name);
    try std.testing.expectEqualStrings("models/gemini-3.1-flash-image", job.model.?);
    try std.testing.expectEqualStrings("requests.jsonl", job.display_name.?);
    try std.testing.expectEqualStrings("files/input", job.input_file_name.?);
    try std.testing.expectEqualStrings("files/output", job.output_file_name.?);
    try std.testing.expectEqualStrings("2026-06-24T00:00:00Z", job.create_time.?);
    try std.testing.expectEqualStrings("2026-06-24T00:01:00Z", job.end_time.?);
    try std.testing.expectEqualStrings("2026-06-24T00:02:00Z", job.update_time.?);
    try std.testing.expect(job.state == .succeeded);
    try std.testing.expectEqual(@as(?u64, 2), job.stats.request_count);
    try std.testing.expectEqual(@as(?u64, 1), job.stats.successful_request_count);
    try std.testing.expectEqual(@as(?u64, 0), job.stats.failed_request_count);
    try std.testing.expectEqual(@as(?u64, 0), job.stats.pending_request_count);
    try std.testing.expectEqual(@as(?i64, -3), job.priority);
    try std.testing.expectEqual(@as(?bool, true), job.done);
    try std.testing.expectEqual(@as(?i64, 1), job.remote_error.?.code);
    try std.testing.expectEqualStrings("cancelled", job.remote_error.?.message);
    try std.testing.expectEqualStrings("[{\"reason\":\"user\"}]", job.remote_error.?.details_json.?);
}

test "typed Batch decoder accepts response and response batch placements" {
    const gpa = std.testing.allocator;

    var response = try decodeBatchJob(
        gpa,
        "{\"name\":\"batches/two\",\"response\":{\"state\":\"JOB_STATE_RUNNING\",\"responsesFile\":\"files/output-two\",\"priority\":4}}",
    );
    defer response.deinit(gpa);
    try std.testing.expect(response.state == .running);
    try std.testing.expectEqualStrings("files/output-two", response.output_file_name.?);
    try std.testing.expectEqual(@as(?i64, 4), response.priority);

    var response_batch = try decodeBatchJob(
        gpa,
        "{\"name\":\"batches/three\",\"response\":{\"batch\":{\"name\":\"batches/three\",\"state\":\"BATCH_STATE_CANCELLED\",\"dest\":{\"fileName\":\"files/output-three\"}}}}",
    );
    defer response_batch.deinit(gpa);
    try std.testing.expect(response_batch.state == .cancelled);
    try std.testing.expectEqualStrings("files/output-three", response_batch.output_file_name.?);
}

test "typed Batch decoder normalizes states and preserves unknown spellings" {
    const cases = .{
        .{ "BATCH_STATE_UNSPECIFIED", BatchState.unspecified },
        .{ "JOB_STATE_UNSPECIFIED", BatchState.unspecified },
        .{ "BATCH_STATE_PENDING", BatchState.pending },
        .{ "JOB_STATE_PENDING", BatchState.pending },
        .{ "BATCH_STATE_RUNNING", BatchState.running },
        .{ "JOB_STATE_RUNNING", BatchState.running },
        .{ "BATCH_STATE_SUCCEEDED", BatchState.succeeded },
        .{ "JOB_STATE_SUCCEEDED", BatchState.succeeded },
        .{ "BATCH_STATE_FAILED", BatchState.failed },
        .{ "JOB_STATE_FAILED", BatchState.failed },
        .{ "BATCH_STATE_CANCELLED", BatchState.cancelled },
        .{ "JOB_STATE_CANCELLED", BatchState.cancelled },
        .{ "BATCH_STATE_EXPIRED", BatchState.expired },
        .{ "JOB_STATE_EXPIRED", BatchState.expired },
    };
    inline for (cases) |entry| {
        var state = try ownedBatchState(std.testing.allocator, entry[0]);
        defer state.deinit(std.testing.allocator);
        try std.testing.expectEqual(entry[1], state);
    }

    var unknown = try ownedBatchState(std.testing.allocator, "BATCH_STATE_PAUSED");
    defer unknown.deinit(std.testing.allocator);
    switch (unknown) {
        .unknown => |name| try std.testing.expectEqualStrings("BATCH_STATE_PAUSED", name),
        else => return error.ExpectedUnknownBatchState,
    }
}

test "typed Batch decoder rejects malformed names files model counters and priority" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.MissingBatchName, decodeBatchJob(gpa, "{}"));
    try std.testing.expectError(
        error.InvalidBatchName,
        decodeBatchJob(gpa, "{\"name\":\"batch/one\"}"),
    );
    try std.testing.expectError(
        error.InvalidFileName,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"inputConfig\":{\"fileName\":\"input\"}}}"),
    );
    try std.testing.expectError(
        error.InvalidFileName,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"output\":{\"responsesFile\":\"output\"}}}"),
    );
    try std.testing.expectError(
        error.InvalidModelName,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"model\":\"gemini-3.1-flash-image\"}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchCounter,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"batchStats\":{\"requestCount\":\"-1\"}}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchCounter,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"batchStats\":{\"requestCount\":\"1.5\"}}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchCounter,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"batchStats\":{\"requestCount\":\"18446744073709551616\"}}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchPriority,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"priority\":\"1.5\"}}"),
    );
    try std.testing.expectError(
        error.InvalidBatchResponse,
        decodeBatchJob(gpa, "{\"name\":\"batches/one\",\"metadata\":{\"state\":3}}"),
    );
}

test "typed Batch list decoder owns jobs and pagination" {
    const gpa = std.testing.allocator;
    var page = try decodeBatchListPage(
        gpa,
        "{\"operations\":[{\"name\":\"batches/one\",\"metadata\":{\"state\":\"BATCH_STATE_PENDING\"}},{\"name\":\"batches/two\",\"response\":{\"batch\":{\"name\":\"batches/two\",\"state\":\"BATCH_STATE_SUCCEEDED\"}}}],\"nextPageToken\":\"next-token\"}",
    );
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), page.jobs.len);
    try std.testing.expectEqualStrings("batches/one", page.jobs[0].name);
    try std.testing.expect(page.jobs[0].state == .pending);
    try std.testing.expectEqualStrings("batches/two", page.jobs[1].name);
    try std.testing.expect(page.jobs[1].state == .succeeded);
    try std.testing.expectEqualStrings("next-token", page.next_page_token.?);

    var empty = try decodeBatchListPage(gpa, "{\"operations\":[],\"nextPageToken\":\"\"}");
    defer empty.deinit(gpa);
    try std.testing.expectEqual(@as(usize, 0), empty.jobs.len);
    try std.testing.expectEqual(@as(?[]u8, null), empty.next_page_token);
}

test "typed Batch response classification handles 2xx failures and cancel bodies" {
    var created_response = api.HttpResponse{
        .status = .created,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"name\":\"batches/created\",\"metadata\":{\"state\":\"BATCH_STATE_PENDING\"}}",
        ),
    };
    var created = typedBatchOutcomeFromResponse(
        BatchJob,
        std.testing.allocator,
        &created_response,
        decodeBatchJob,
    );
    switch (created) {
        .success => |*job| job.deinit(std.testing.allocator),
        .api_failure, .response_decoding_failure => return error.UnexpectedBatchCreateFailure,
    }

    var malformed_response = api.HttpResponse{
        .status = .accepted,
        .body = try std.testing.allocator.dupe(u8, "{}"),
    };
    var malformed = typedBatchOutcomeFromResponse(
        BatchJob,
        std.testing.allocator,
        &malformed_response,
        decodeBatchJob,
    );
    switch (malformed) {
        .response_decoding_failure => |err| try std.testing.expectEqual(error.MissingBatchName, err),
        .success => |*job| {
            job.deinit(std.testing.allocator);
            return error.UnexpectedBatchSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedBatchApiFailure;
        },
    }

    var failure_response = api.HttpResponse{
        .status = .bad_request,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"bad\"}"),
    };
    var failure = typedBatchOutcomeFromResponse(
        BatchJob,
        std.testing.allocator,
        &failure_response,
        decodeBatchJob,
    );
    switch (failure) {
        .api_failure => |*api_failure| {
            try std.testing.expectEqual(std.http.Status.bad_request, api_failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"bad\"}", api_failure.body);
            api_failure.deinit(std.testing.allocator);
        },
        .success => |*job| {
            job.deinit(std.testing.allocator);
            return error.UnexpectedBatchSuccess;
        },
        .response_decoding_failure => return error.UnexpectedBatchDecodingFailure,
    }

    var cancel_response = api.HttpResponse{
        .status = .no_content,
        .body = try std.testing.allocator.dupe(u8, "not json"),
    };
    const cancel_outcome = emptyBatchOutcomeFromResponse(std.testing.allocator, &cancel_response);
    switch (cancel_outcome) {
        .success => {},
        .api_failure, .response_decoding_failure => return error.UnexpectedBatchCancelFailure,
    }
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

fn testTypedOutputJsonl(gpa: std.mem.Allocator, entry_count: usize) ![]u8 {
    assert(entry_count > 0);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    for (0..entry_count) |index| {
        try output.writer.print(
            "{{\"key\":\"key-{d}\",\"response\":{{\"responseId\":\"response-{d}\",\"candidates\":[]}}}}\n",
            .{ index, index },
        );
    }
    return output.toOwnedSlice();
}

test "live API batch submit status and cancel succeeds" {
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
    var upload_outcome = try uploadBatchInputWithContext(&context, .{
        .bytes = input,
        .display_name = display_name,
    });
    var uploaded_file = switch (upload_outcome) {
        .success => |file| file,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: live batch input upload failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            return error.BatchInputUploadFailed;
        },
        .response_decoding_failure => |err| return err,
    };
    defer uploaded_file.deinit(gpa);

    // BILLABLE and non-idempotent: this creates exactly one Batch job.
    var create_outcome = try createBatchWithContext(&context, .{
        .file_name = uploaded_file.name,
        .display_name = display_name,
    });
    var created_job = switch (create_outcome) {
        .success => |job| job,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: live batch creation failed with HTTP {d}; uploaded input remains as {s}\n{s}\n",
                .{ @intFromEnum(failure.status), uploaded_file.name, failure.body },
            );
            return error.BatchCreationFailed;
        },
        .response_decoding_failure => |err| return err,
    };
    defer created_job.deinit(gpa);
    try std.testing.expect(isCanonicalBatchName(created_job.name));

    var status_outcome = try getBatchWithContext(&context, created_job.name);
    var status_job = switch (status_outcome) {
        .success => |job| job,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: live batch status failed with HTTP {d} for {s}\n{s}\n",
                .{ @intFromEnum(failure.status), created_job.name, failure.body },
            );
            return error.BatchStatusFailed;
        },
        .response_decoding_failure => |err| return err,
    };
    defer status_job.deinit(gpa);
    try std.testing.expectEqualStrings(created_job.name, status_job.name);

    var cancel_outcome = try cancelBatchWithContext(&context, created_job.name);
    switch (cancel_outcome) {
        .success => {},
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: live batch cancel failed with HTTP {d} for {s}\n{s}\n",
                .{ @intFromEnum(failure.status), created_job.name, failure.body },
            );
            return error.BatchCancelFailed;
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }

    var cancelled_status_outcome = try getBatchWithContext(&context, created_job.name);
    var cancelled_status_job = switch (cancelled_status_outcome) {
        .success => |job| job,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: live cancelled batch status failed with HTTP {d} for {s}\n{s}\n",
                .{ @intFromEnum(failure.status), created_job.name, failure.body },
            );
            return error.BatchStatusFailed;
        },
        .response_decoding_failure => |err| return err,
    };
    defer cancelled_status_job.deinit(gpa);
    try std.testing.expectEqualStrings(created_job.name, cancelled_status_job.name);
}

test "live API batch list succeeds" {
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

    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    while (true) {
        var outcome = try listBatchesPageWithContext(&context, page_token);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        var page = switch (outcome) {
            .success => |page| page,
            .api_failure => |*failure| {
                defer failure.deinit(gpa);
                std.debug.print(
                    "error: live batch list failed with HTTP {d}\n{s}\n",
                    .{ @intFromEnum(failure.status), failure.body },
                );
                return error.BatchListFailed;
            },
            .response_decoding_failure => |err| return err,
        };
        defer page.deinit(gpa);

        for (page.jobs) |job| try std.testing.expect(isCanonicalBatchName(job.name));

        page_token = page.next_page_token orelse break;
        page.next_page_token = null;
    }
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
