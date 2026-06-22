//! Gemini Files API upload and list handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");
const file_domain = @import("files_domain.zig");
const operation = @import("operation.zig");

pub const max_upload_bytes = 64 * 1024 * 1024;
const sample_image_path = "sample_images/good_night.jpeg";
const live_upload_display_name = "nbimg live api sample";

comptime {
    assert(max_upload_bytes == file_domain.max_file_upload_bytes);
}

const WireRemoteError = struct {
    code: ?i64 = null,
    message: ?[]const u8 = null,
    details: ?std.json.Value = null,
};

const WireFile = struct {
    name: ?[]const u8 = null,
    displayName: ?[]const u8 = null,
    mimeType: ?[]const u8 = null,
    sizeBytes: ?[]const u8 = null,
    createTime: ?[]const u8 = null,
    updateTime: ?[]const u8 = null,
    expirationTime: ?[]const u8 = null,
    sha256Hash: ?[]const u8 = null,
    uri: ?[]const u8 = null,
    downloadUri: ?[]const u8 = null,
    state: ?[]const u8 = null,
    source: ?[]const u8 = null,
    @"error": ?WireRemoteError = null,
};

/// Describes borrowed image bytes and metadata for a Files API upload.
///
/// - All slices remain caller-owned and must outlive the upload call.
/// - The value allocates nothing and mutates no state.
pub const FileUpload = struct {
    mime: api.ImageMime,
    bytes: []const u8,
    display_name: ?[]const u8 = null,
};

/// Owns a decoded Files API resource and its optional metadata strings.
///
/// - Every populated slice must be released with `deinit` using the originating allocator.
/// - The value otherwise owns no external state.
pub const File = struct {
    name: []u8,
    display_name: ?[]u8 = null,
    mime_type: ?[]u8 = null,
    size_bytes: ?[]u8 = null,
    create_time: ?[]u8 = null,
    update_time: ?[]u8 = null,
    expiration_time: ?[]u8 = null,
    sha256_hash: ?[]u8 = null,
    uri: ?[]u8 = null,
    state: ?[]u8 = null,
    source: ?[]u8 = null,

    /// Frees a decoded file and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `file` and allocator state.
    pub fn deinit(file: *File, gpa: std.mem.Allocator) void {
        gpa.free(file.name);
        file.deinitMetadata(gpa);
        file.* = undefined;
    }

    fn deinitMetadata(file: *File, gpa: std.mem.Allocator) void {
        freeOptional(gpa, file.display_name);
        freeOptional(gpa, file.mime_type);
        freeOptional(gpa, file.size_bytes);
        freeOptional(gpa, file.create_time);
        freeOptional(gpa, file.update_time);
        freeOptional(gpa, file.expiration_time);
        freeOptional(gpa, file.sha256_hash);
        freeOptional(gpa, file.uri);
        freeOptional(gpa, file.state);
        freeOptional(gpa, file.source);

        file.display_name = null;
        file.mime_type = null;
        file.size_bytes = null;
        file.create_time = null;
        file.update_time = null;
        file.expiration_time = null;
        file.sha256_hash = null;
        file.uri = null;
        file.state = null;
        file.source = null;
    }
};

/// Owns one page of decoded file resources and an optional continuation token.
///
/// - All nested allocations must be released with `deinit` using their originating allocator.
/// - The value otherwise owns no external state.
pub const FileListPage = struct {
    files: []File,
    next_page_token: ?[]u8 = null,

    /// Frees a file-list page and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `page` and allocator state.
    pub fn deinit(page: *FileListPage, gpa: std.mem.Allocator) void {
        for (page.files) |*file| file.deinit(gpa);
        gpa.free(page.files);
        if (page.next_page_token) |token| gpa.free(token);
        page.* = undefined;
    }
};

/// Uploads borrowed image bytes through the Gemini Files API.
///
/// - Borrows upload fields for the call; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, protocol, timeout, or logging errors and creates remote file state.
pub fn uploadFile(
    context: *const api.RequestContext,
    file: FileUpload,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(file.bytes.len > 0);
    if (file.display_name) |display_name| assert(isValidDisplayName(display_name));

    return api.uploadResumableBytes(context, .{
        .content_type = file.mime.apiName(),
        .bytes = file.bytes,
        .display_name = file.display_name,
    });
}

/// Fetches one Files API page using an optional borrowed continuation token.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates no input or remote state.
pub fn listFilesPage(
    context: *const api.RequestContext,
    page_token: ?[]const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    if (page_token) |token| assert(token.len > 0);

    const url = try buildListFilesUrl(context.gpa, page_token);
    defer context.gpa.free(url);

    return api.getJson(context, url);
}

/// Fetches one canonical Files API resource.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates no input or remote state.
pub fn getFile(
    context: *const api.RequestContext,
    name: []const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(api.isCanonicalFileName(name));

    const url = try buildGetFileUrl(context.gpa, name);
    defer context.gpa.free(url);

    return api.getJson(context, url);
}

/// Deletes one canonical Files API resource.
///
/// - Borrows inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP, timeout, or logging errors and mutates remote file state.
pub fn deleteFile(
    context: *const api.RequestContext,
    name: []const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(api.isCanonicalFileName(name));

    const url = try buildFileResourceUrl(context.gpa, name);
    defer context.gpa.free(url);

    return api.deleteJson(context, url);
}

/// Uploads and decodes one typed File using an explicit request context.
pub fn uploadFileWithContext(
    context: *const api.RequestContext,
    upload: file_domain.FileUpload,
) !operation.OperationOutcome(file_domain.File) {
    try validateUpload(upload);

    var response = try uploadFile(context, .{
        .mime = wireImageMime(upload.mime),
        .bytes = upload.bytes,
        .display_name = upload.display_name,
    });
    return typedFileOutcomeFromResponse(
        file_domain.File,
        context.gpa,
        &response,
        decodeTypedUploadedFile,
    );
}

/// Fetches and decodes one typed File using an explicit request context.
pub fn getFileWithContext(
    context: *const api.RequestContext,
    name: []const u8,
) !operation.OperationOutcome(file_domain.File) {
    try validateFileName(name);

    var response = try getFile(context, name);
    return typedFileOutcomeFromResponse(
        file_domain.File,
        context.gpa,
        &response,
        decodeTypedFile,
    );
}

/// Fetches and decodes one typed File page using an explicit request context.
pub fn listFilesPageWithContext(
    context: *const api.RequestContext,
    page_token: ?[]const u8,
) !operation.OperationOutcome(file_domain.FileListPage) {
    try validatePageToken(page_token);

    var response = try listFilesPage(context, page_token);
    return typedFileOutcomeFromResponse(
        file_domain.FileListPage,
        context.gpa,
        &response,
        decodeTypedFileListPage,
    );
}

/// Deletes one File using an explicit request context.
pub fn deleteFileWithContext(
    context: *const api.RequestContext,
    name: []const u8,
) !operation.OperationOutcome(void) {
    try validateFileName(name);

    var response = try deleteFile(context, name);
    return deleteOutcomeFromResponse(context.gpa, &response);
}

fn deleteOutcomeFromResponse(
    gpa: std.mem.Allocator,
    response: *api.HttpResponse,
) operation.OperationOutcome(void) {
    if (response.status.class() != .success) {
        const failure = operation.ApiFailure{
            .status = response.status,
            .body = response.body,
        };
        response.* = undefined;
        return .{ .api_failure = failure };
    }
    response.deinit(gpa);
    return .{ .success = {} };
}

fn decodeUploadedFileName(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    return api.decodeUploadedFileName(gpa, response_json);
}

/// Decodes an upload response into an owned file resource.
///
/// - Borrows `response_json`; all returned strings are owned by `gpa` and require `File.deinit`.
/// - Returns allocation, JSON parsing, or `MissingFileName` errors and mutates no input or global state.
pub fn decodeUploadedFile(gpa: std.mem.Allocator, response_json: []const u8) !File {
    const Response = struct {
        file: ?WireFile = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const file = parsed.value.file orelse return error.MissingFileName;
    const name = file.name orelse return error.MissingFileName;
    if (name.len == 0) return error.MissingFileName;

    return ownedFileFromResponse(gpa, file);
}

/// Decodes a file response into an owned file resource.
///
/// - Borrows `response_json`; all returned strings are owned by `gpa` and require `File.deinit`.
/// - Returns allocation, JSON parsing, or `MissingFileName` errors and mutates no input or global state.
pub fn decodeFile(gpa: std.mem.Allocator, response_json: []const u8) !File {
    var parsed = try std.json.parseFromSlice(WireFile, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return ownedFileFromResponse(gpa, parsed.value);
}

/// Decodes a file-list response into an owned page.
///
/// - Borrows `response_json`; all returned slices are owned by `gpa` and require `FileListPage.deinit`.
/// - Returns allocation, JSON parsing, or missing-name errors and mutates no input or global state.
pub fn decodeFileListPage(gpa: std.mem.Allocator, response_json: []const u8) !FileListPage {
    const Response = struct {
        files: []const WireFile = &.{},
        nextPageToken: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    try files.ensureTotalCapacity(gpa, parsed.value.files.len);
    for (parsed.value.files) |response_file| {
        files.appendAssumeCapacity(try ownedFileFromResponse(gpa, response_file));
    }

    const next_page_token: ?[]u8 = if (parsed.value.nextPageToken) |token| token: {
        if (token.len == 0) break :token null;
        break :token try gpa.dupe(u8, token);
    } else null;
    errdefer if (next_page_token) |token| gpa.free(token);

    return .{
        .files = try files.toOwnedSlice(gpa),
        .next_page_token = next_page_token,
    };
}

fn ownedFileFromResponse(gpa: std.mem.Allocator, response_file: anytype) !File {
    const name = response_file.name orelse return error.MissingFileName;
    if (name.len == 0) return error.MissingFileName;

    var owned_file = File{
        .name = try gpa.dupe(u8, name),
    };
    errdefer owned_file.deinit(gpa);

    owned_file.display_name = try dupeOptional(gpa, response_file.displayName);
    owned_file.mime_type = try dupeOptional(gpa, response_file.mimeType);
    owned_file.size_bytes = try dupeOptional(gpa, response_file.sizeBytes);
    owned_file.create_time = try dupeOptional(gpa, response_file.createTime);
    owned_file.update_time = try dupeOptional(gpa, response_file.updateTime);
    owned_file.expiration_time = try dupeOptional(gpa, response_file.expirationTime);
    owned_file.sha256_hash = try dupeOptional(gpa, response_file.sha256Hash);
    owned_file.uri = try dupeOptional(gpa, response_file.uri);
    owned_file.state = try dupeOptional(gpa, response_file.state);
    owned_file.source = try dupeOptional(gpa, response_file.source);

    return owned_file;
}

fn decodeTypedUploadedFile(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.File {
    const Response = struct {
        file: ?WireFile = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const response_file = parsed.value.file orelse return error.MissingFileName;
    return ownedTypedFileFromResponse(gpa, response_file);
}

fn decodeTypedFile(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.File {
    var parsed = try std.json.parseFromSlice(WireFile, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return ownedTypedFileFromResponse(gpa, parsed.value);
}

fn decodeTypedFileListPage(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.FileListPage {
    const Response = struct {
        files: []const WireFile = &.{},
        nextPageToken: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var files: std.ArrayList(file_domain.File) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    try files.ensureTotalCapacity(gpa, parsed.value.files.len);
    for (parsed.value.files) |response_file| {
        files.appendAssumeCapacity(try ownedTypedFileFromResponse(gpa, response_file));
    }

    const next_page_token = try dupeNonEmptyOptional(gpa, parsed.value.nextPageToken);
    errdefer if (next_page_token) |token| gpa.free(token);

    return .{
        .files = try files.toOwnedSlice(gpa),
        .next_page_token = next_page_token,
    };
}

fn ownedTypedFileFromResponse(
    gpa: std.mem.Allocator,
    response_file: WireFile,
) !file_domain.File {
    const name = response_file.name orelse return error.MissingFileName;
    if (!api.isCanonicalFileName(name)) return error.InvalidFileName;

    var file = file_domain.File{
        .name = try gpa.dupe(u8, name),
    };
    errdefer file.deinit(gpa);

    file.display_name = try dupeOptional(gpa, response_file.displayName);
    file.mime_type = try dupeOptional(gpa, response_file.mimeType);
    file.size_bytes = try parseOptionalSizeBytes(response_file.sizeBytes);
    file.create_time = try dupeOptional(gpa, response_file.createTime);
    file.update_time = try dupeOptional(gpa, response_file.updateTime);
    file.expiration_time = try dupeOptional(gpa, response_file.expirationTime);
    file.sha256_hash = try dupeOptional(gpa, response_file.sha256Hash);
    file.uri = try dupeOptional(gpa, response_file.uri);
    file.download_uri = try dupeOptional(gpa, response_file.downloadUri);
    file.state = try ownedFileState(gpa, response_file.state);
    file.source = try ownedFileSource(gpa, response_file.source);
    file.processing_error = try ownedRemoteError(gpa, response_file.@"error");

    return file;
}

fn ownedFileState(
    gpa: std.mem.Allocator,
    wire_name: ?[]const u8,
) !file_domain.FileState {
    const name = wire_name orelse return .unspecified;
    if (std.mem.eql(u8, name, "STATE_UNSPECIFIED")) return .unspecified;
    if (std.mem.eql(u8, name, "PROCESSING")) return .processing;
    if (std.mem.eql(u8, name, "ACTIVE")) return .active;
    if (std.mem.eql(u8, name, "FAILED")) return .failed;
    return .{ .unknown = try gpa.dupe(u8, name) };
}

fn ownedFileSource(
    gpa: std.mem.Allocator,
    wire_name: ?[]const u8,
) !file_domain.FileSource {
    const name = wire_name orelse return .unspecified;
    if (std.mem.eql(u8, name, "SOURCE_UNSPECIFIED")) return .unspecified;
    if (std.mem.eql(u8, name, "UPLOADED")) return .uploaded;
    if (std.mem.eql(u8, name, "GENERATED")) return .generated;
    if (std.mem.eql(u8, name, "REGISTERED")) return .registered;
    return .{ .unknown = try gpa.dupe(u8, name) };
}

fn ownedRemoteError(
    gpa: std.mem.Allocator,
    wire_error: ?WireRemoteError,
) !?file_domain.RemoteError {
    const remote_error = wire_error orelse return null;
    const message = remote_error.message orelse return error.MissingRemoteErrorMessage;

    const owned_message = try gpa.dupe(u8, message);
    errdefer gpa.free(owned_message);

    const details_json = if (remote_error.details) |details| details_json: {
        if (details == .null) break :details_json null;
        break :details_json try stringifyJson(gpa, details);
    } else null;
    errdefer if (details_json) |details| gpa.free(details);

    return .{
        .code = remote_error.code,
        .message = owned_message,
        .details_json = details_json,
    };
}

fn parseOptionalSizeBytes(value: ?[]const u8) !?u64 {
    const bytes = value orelse return null;
    return std.fmt.parseInt(u64, bytes, 10) catch return error.InvalidFileSize;
}

fn stringifyJson(gpa: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn typedFileOutcomeFromResponse(
    comptime T: type,
    gpa: std.mem.Allocator,
    response: *api.HttpResponse,
    comptime decode: fn (std.mem.Allocator, []const u8) anyerror!T,
) operation.OperationOutcome(T) {
    if (response.status.class() != .success) {
        const failure = operation.ApiFailure{
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

fn validateUpload(upload: file_domain.FileUpload) file_domain.FileValidationError!void {
    if (upload.bytes.len == 0) return error.EmptyFileBytes;
    if (upload.bytes.len > file_domain.max_file_upload_bytes) return error.FileTooLarge;
    if (upload.display_name) |display_name| {
        if (!api.isValidDisplayName(display_name)) return error.InvalidDisplayName;
    }
}

fn validateFileName(name: []const u8) file_domain.FileValidationError!void {
    if (!api.isCanonicalFileName(name)) return error.InvalidFileName;
}

fn validatePageToken(page_token: ?[]const u8) file_domain.FileValidationError!void {
    if (page_token) |token| {
        if (token.len == 0) return error.EmptyPageToken;
    }
}

fn wireImageMime(mime: file_domain.InputImageMime) api.ImageMime {
    return switch (mime) {
        .jpeg => .jpeg,
        .png => .png,
        .webp => .webp,
    };
}

fn dupeNonEmptyOptional(
    gpa: std.mem.Allocator,
    value: ?[]const u8,
) !?[]u8 {
    const bytes = value orelse return null;
    if (bytes.len == 0) return null;
    return try gpa.dupe(u8, bytes);
}

fn buildListFilesUrl(gpa: std.mem.Allocator, page_token: ?[]const u8) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll(filesListBaseUrl());
    try output.writer.writeAll("?pageSize=100");
    if (page_token) |token| {
        assert(token.len > 0);
        try output.writer.writeAll("&pageToken=");
        try (std.Uri.Component{ .raw = token }).formatQuery(&output.writer);
    }

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn buildGetFileUrl(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    return buildFileResourceUrl(gpa, name);
}

fn buildFileResourceUrl(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    assert(api.isCanonicalFileName(name));

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll(filesListBaseUrl());
    try output.writer.writeByte('/');
    try formatFileIdPathSegment(&output.writer, name[api.canonical_file_name_prefix.len..]);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn formatFileIdPathSegment(writer: *std.Io.Writer, file_id: []const u8) !void {
    assert(file_id.len > 0);

    for (file_id) |byte| {
        if (isFileIdPathSegmentChar(byte)) {
            try writer.writeByte(byte);
        } else {
            try writer.print("%{X:0>2}", .{byte});
        }
    }
}

fn isFileIdPathSegmentChar(byte: u8) bool {
    return switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~' => true,
        else => false,
    };
}

fn isValidDisplayName(display_name: []const u8) bool {
    return api.isValidDisplayName(display_name);
}

fn dupeOptional(gpa: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try gpa.dupe(u8, bytes) else null;
}

fn freeOptional(gpa: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| gpa.free(bytes);
}

fn filesListBaseUrl() []const u8 {
    return "https://generativelanguage.googleapis.com/v1beta/files";
}

test "typed upload maps every admitted image MIME" {
    try std.testing.expectEqual(api.ImageMime.jpeg, wireImageMime(.jpeg));
    try std.testing.expectEqual(api.ImageMime.png, wireImageMime(.png));
    try std.testing.expectEqual(api.ImageMime.webp, wireImageMime(.webp));
}

test "typed Files validation reports every named error" {
    try std.testing.expectError(
        error.EmptyFileBytes,
        validateUpload(.{ .mime = .jpeg, .bytes = "" }),
    );

    const oversized_bytes = @as([*]const u8, @ptrFromInt(1))[0 .. file_domain.max_file_upload_bytes + 1];
    try std.testing.expectError(
        error.FileTooLarge,
        validateUpload(.{ .mime = .png, .bytes = oversized_bytes }),
    );
    const maximum_bytes = oversized_bytes[0..file_domain.max_file_upload_bytes];
    try validateUpload(.{ .mime = .png, .bytes = maximum_bytes });
    try std.testing.expectError(
        error.InvalidDisplayName,
        validateUpload(.{ .mime = .webp, .bytes = "x", .display_name = "" }),
    );
    try std.testing.expectError(error.InvalidFileName, validateFileName(""));
    try std.testing.expectError(error.InvalidFileName, validateFileName("abc123"));
    try std.testing.expectError(error.InvalidFileName, validateFileName("files/"));
    try std.testing.expectError(error.EmptyPageToken, validatePageToken(""));

    try validateUpload(.{
        .mime = .jpeg,
        .bytes = "x",
        .display_name = "valid",
    });
    try validateFileName("files/abc123");
    try validatePageToken(null);
    try validatePageToken("next");
}

test "typed File decoder returns complete owned metadata" {
    const gpa = std.testing.allocator;
    var file = try decodeTypedFile(
        gpa,
        "{\"name\":\"files/abc123\",\"displayName\":\"sample\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":\"18446744073709551615\",\"createTime\":\"2026-05-18T08:14:20Z\",\"updateTime\":\"2026-05-18T08:15:20Z\",\"expirationTime\":\"2026-05-20T08:14:20Z\",\"sha256Hash\":\"hash\",\"uri\":\"https://example.test/files/abc123\",\"downloadUri\":\"https://example.test/download/abc123\",\"state\":\"FAILED\",\"source\":\"GENERATED\",\"error\":{\"code\":-7,\"message\":\"processing failed\",\"details\":[{\"reason\":\"bad input\"}]}}",
    );
    defer file.deinit(gpa);

    try std.testing.expectEqualStrings("files/abc123", file.name);
    try std.testing.expectEqualStrings("sample", file.display_name.?);
    try std.testing.expectEqualStrings("image/jpeg", file.mime_type.?);
    try std.testing.expectEqual(std.math.maxInt(u64), file.size_bytes.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20Z", file.create_time.?);
    try std.testing.expectEqualStrings("2026-05-18T08:15:20Z", file.update_time.?);
    try std.testing.expectEqualStrings("2026-05-20T08:14:20Z", file.expiration_time.?);
    try std.testing.expectEqualStrings("hash", file.sha256_hash.?);
    try std.testing.expectEqualStrings("https://example.test/files/abc123", file.uri.?);
    try std.testing.expectEqualStrings("https://example.test/download/abc123", file.download_uri.?);
    try std.testing.expect(file.state == .failed);
    try std.testing.expect(file.source == .generated);
    try std.testing.expectEqual(@as(?i64, -7), file.processing_error.?.code);
    try std.testing.expectEqualStrings("processing failed", file.processing_error.?.message);
    try std.testing.expectEqualStrings(
        "[{\"reason\":\"bad input\"}]",
        file.processing_error.?.details_json.?,
    );
}

test "typed uploaded File decoder removes the upload response wrapper" {
    var file = try decodeTypedUploadedFile(
        std.testing.allocator,
        "{\"file\":{\"name\":\"files/uploaded\",\"mimeType\":\"image/png\",\"state\":\"ACTIVE\",\"source\":\"UPLOADED\"}}",
    );
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("files/uploaded", file.name);
    try std.testing.expectEqualStrings("image/png", file.mime_type.?);
    try std.testing.expect(file.state == .active);
    try std.testing.expect(file.source == .uploaded);
}

test "typed File decoder maps every known state and source without unknown storage" {
    const state_cases = .{
        .{ "STATE_UNSPECIFIED", file_domain.FileState.unspecified },
        .{ "PROCESSING", file_domain.FileState.processing },
        .{ "ACTIVE", file_domain.FileState.active },
        .{ "FAILED", file_domain.FileState.failed },
    };
    inline for (state_cases) |entry| {
        var state = try ownedFileState(std.testing.allocator, entry[0]);
        defer state.deinit(std.testing.allocator);
        try std.testing.expectEqual(entry[1], state);
    }

    const source_cases = .{
        .{ "SOURCE_UNSPECIFIED", file_domain.FileSource.unspecified },
        .{ "UPLOADED", file_domain.FileSource.uploaded },
        .{ "GENERATED", file_domain.FileSource.generated },
        .{ "REGISTERED", file_domain.FileSource.registered },
    };
    inline for (source_cases) |entry| {
        var source = try ownedFileSource(std.testing.allocator, entry[0]);
        defer source.deinit(std.testing.allocator);
        try std.testing.expectEqual(entry[1], source);
    }
}

test "typed File decoder defaults absent state source and error" {
    var file = try decodeTypedFile(
        std.testing.allocator,
        "{\"name\":\"files/abc123\",\"mimeType\":\"application/jsonl\"}",
    );
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("application/jsonl", file.mime_type.?);
    try std.testing.expect(file.state == .unspecified);
    try std.testing.expect(file.source == .unspecified);
    try std.testing.expectEqual(@as(?file_domain.RemoteError, null), file.processing_error);
}

test "typed File decoder preserves unknown state and source spellings" {
    var file = try decodeTypedFile(
        std.testing.allocator,
        "{\"name\":\"files/abc123\",\"state\":\"PAUSED\",\"source\":\"IMPORTED\"}",
    );
    defer file.deinit(std.testing.allocator);

    switch (file.state) {
        .unknown => |name| try std.testing.expectEqualStrings("PAUSED", name),
        else => return error.ExpectedUnknownState,
    }
    switch (file.source) {
        .unknown => |name| try std.testing.expectEqualStrings("IMPORTED", name),
        else => return error.ExpectedUnknownSource,
    }
}

test "typed File decoder treats null remote details as absent" {
    var file = try decodeTypedFile(
        std.testing.allocator,
        "{\"name\":\"files/abc123\",\"error\":{\"message\":\"failed\",\"details\":null}}",
    );
    defer file.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("failed", file.processing_error.?.message);
    try std.testing.expectEqual(@as(?[]u8, null), file.processing_error.?.details_json);
}

test "typed File decoder rejects malformed populated remote error" {
    try std.testing.expectError(
        error.MissingRemoteErrorMessage,
        decodeTypedFile(
            std.testing.allocator,
            "{\"name\":\"files/abc123\",\"error\":{\"code\":3}}",
        ),
    );
}

test "typed File decoder validates canonical names and byte sizes" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeTypedFile(std.testing.allocator, "{}"),
    );
    try std.testing.expectError(
        error.InvalidFileName,
        decodeTypedFile(std.testing.allocator, "{\"name\":\"abc123\"}"),
    );
    try std.testing.expectError(
        error.InvalidFileSize,
        decodeTypedFile(
            std.testing.allocator,
            "{\"name\":\"files/abc123\",\"sizeBytes\":\"-1\"}",
        ),
    );
    try std.testing.expectError(
        error.InvalidFileSize,
        decodeTypedFile(
            std.testing.allocator,
            "{\"name\":\"files/abc123\",\"sizeBytes\":\"18446744073709551616\"}",
        ),
    );
    try std.testing.expectError(
        error.InvalidFileSize,
        decodeTypedFile(
            std.testing.allocator,
            "{\"name\":\"files/abc123\",\"sizeBytes\":\"one\"}",
        ),
    );
}

test "typed File list decoder owns pagination and image or opaque MIME metadata" {
    var page = try decodeTypedFileListPage(
        std.testing.allocator,
        "{\"files\":[{\"name\":\"files/image\",\"mimeType\":\"image/webp\",\"sizeBytes\":\"3\"},{\"name\":\"files/batch\",\"mimeType\":\"application/jsonl\"}],\"nextPageToken\":\"next-token\"}",
    );
    defer page.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), page.files.len);
    try std.testing.expectEqualStrings("image/webp", page.files[0].mime_type.?);
    try std.testing.expectEqual(@as(?u64, 3), page.files[0].size_bytes);
    try std.testing.expectEqualStrings("application/jsonl", page.files[1].mime_type.?);
    try std.testing.expectEqualStrings("next-token", page.next_page_token.?);
}

test "typed File list decoder accepts an empty page and normalizes an empty token" {
    var page = try decodeTypedFileListPage(
        std.testing.allocator,
        "{\"nextPageToken\":\"\"}",
    );
    defer page.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), page.files.len);
    try std.testing.expectEqual(@as(?[]u8, null), page.next_page_token);
}

test "typed File list decoder cleans up after partial page failure" {
    try std.testing.expectError(
        error.InvalidFileSize,
        decodeTypedFileListPage(
            std.testing.allocator,
            "{\"files\":[{\"name\":\"files/one\",\"displayName\":\"allocated\",\"state\":\"FUTURE\"},{\"name\":\"files/two\",\"sizeBytes\":\"invalid\"}]}",
        ),
    );
}

test "typed File response classification accepts success and preserves failures" {
    var code: u16 = 200;
    while (code <= 299) : (code += 1) {
        var success_response = api.HttpResponse{
            .status = @enumFromInt(code),
            .body = try std.testing.allocator.dupe(u8, "{\"name\":\"files/abc123\"}"),
        };
        var success = typedFileOutcomeFromResponse(
            file_domain.File,
            std.testing.allocator,
            &success_response,
            decodeTypedFile,
        );
        switch (success) {
            .success => |*file| file.deinit(std.testing.allocator),
            .api_failure, .response_decoding_failure => return error.UnexpectedFileFailure,
        }
    }

    var malformed_response = api.HttpResponse{
        .status = .accepted,
        .body = try std.testing.allocator.dupe(u8, "{}"),
    };
    var malformed = typedFileOutcomeFromResponse(
        file_domain.File,
        std.testing.allocator,
        &malformed_response,
        decodeTypedFile,
    );
    switch (malformed) {
        .response_decoding_failure => |err| try std.testing.expectEqual(error.MissingFileName, err),
        .success => |*file| {
            file.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedApiFailure;
        },
    }

    var failure_response = api.HttpResponse{
        .status = .too_many_requests,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"complete body\"}"),
    };
    var failure = typedFileOutcomeFromResponse(
        file_domain.File,
        std.testing.allocator,
        &failure_response,
        decodeTypedFile,
    );
    switch (failure) {
        .api_failure => |*api_failure| {
            try std.testing.expectEqual(std.http.Status.too_many_requests, api_failure.status);
            try std.testing.expectEqualStrings("{\"error\":\"complete body\"}", api_failure.body);
            api_failure.deinit(std.testing.allocator);
        },
        .success => |*file| {
            file.deinit(std.testing.allocator);
            return error.UnexpectedSuccess;
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

test "typed File delete accepts every 2xx status and arbitrary bodies" {
    var code: u16 = 200;
    while (code <= 299) : (code += 1) {
        var response = api.HttpResponse{
            .status = @enumFromInt(code),
            .body = try std.testing.allocator.dupe(u8, "not JSON"),
        };
        const outcome = deleteOutcomeFromResponse(std.testing.allocator, &response);
        switch (outcome) {
            .success => {},
            .api_failure, .response_decoding_failure => return error.UnexpectedDeleteFailure,
        }
    }
}

test "typed File delete preserves non-success response bodies" {
    var response = api.HttpResponse{
        .status = .forbidden,
        .body = try std.testing.allocator.dupe(u8, "{\"error\":\"denied\"}"),
    };
    var outcome = deleteOutcomeFromResponse(std.testing.allocator, &response);
    switch (outcome) {
        .api_failure => |*failure| {
            try std.testing.expectEqualStrings("{\"error\":\"denied\"}", failure.body);
            failure.deinit(std.testing.allocator);
        },
        .success => return error.UnexpectedSuccess,
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

test "decodeUploadedFileName returns owned file name" {
    const gpa = std.testing.allocator;
    const name = try decodeUploadedFileName(
        gpa,
        "{\"file\":{\"name\":\"files/abc123\",\"displayName\":\"good_night.jpeg\"}}",
    );
    defer gpa.free(name);

    try std.testing.expectEqualStrings("files/abc123", name);
}

test "decodeUploadedFile returns observed Gemini file fields" {
    const gpa = std.testing.allocator;
    var file = try decodeUploadedFile(
        gpa,
        "{\"file\":{\"name\":\"files/abc123\",\"displayName\":\"good_night.jpeg\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":\"229046\",\"createTime\":\"2026-05-18T08:14:20.799526Z\",\"updateTime\":\"2026-05-18T08:14:20.799526Z\",\"expirationTime\":\"2026-05-20T08:14:20.425492423Z\",\"sha256Hash\":\"hash\",\"uri\":\"https://generativelanguage.googleapis.com/v1beta/files/abc123\",\"state\":\"ACTIVE\",\"source\":\"UPLOADED\"}}",
    );
    defer file.deinit(gpa);

    try std.testing.expectEqualStrings("files/abc123", file.name);
    try std.testing.expectEqualStrings("good_night.jpeg", file.display_name.?);
    try std.testing.expectEqualStrings("image/jpeg", file.mime_type.?);
    try std.testing.expectEqualStrings("229046", file.size_bytes.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", file.create_time.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", file.update_time.?);
    try std.testing.expectEqualStrings("2026-05-20T08:14:20.425492423Z", file.expiration_time.?);
    try std.testing.expectEqualStrings("hash", file.sha256_hash.?);
    try std.testing.expectEqualStrings("https://generativelanguage.googleapis.com/v1beta/files/abc123", file.uri.?);
    try std.testing.expectEqualStrings("ACTIVE", file.state.?);
    try std.testing.expectEqualStrings("UPLOADED", file.source.?);
}

test "decodeFile returns observed Gemini file fields" {
    const gpa = std.testing.allocator;
    var file = try decodeFile(
        gpa,
        "{\"name\":\"files/abc123\",\"displayName\":\"good_night.jpeg\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":\"229046\",\"createTime\":\"2026-05-18T08:14:20.799526Z\",\"updateTime\":\"2026-05-18T08:14:20.799526Z\",\"expirationTime\":\"2026-05-20T08:14:20.425492423Z\",\"sha256Hash\":\"hash\",\"uri\":\"https://generativelanguage.googleapis.com/v1beta/files/abc123\",\"state\":\"ACTIVE\",\"source\":\"UPLOADED\"}",
    );
    defer file.deinit(gpa);

    try std.testing.expectEqualStrings("files/abc123", file.name);
    try std.testing.expectEqualStrings("good_night.jpeg", file.display_name.?);
    try std.testing.expectEqualStrings("image/jpeg", file.mime_type.?);
    try std.testing.expectEqualStrings("229046", file.size_bytes.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", file.create_time.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", file.update_time.?);
    try std.testing.expectEqualStrings("2026-05-20T08:14:20.425492423Z", file.expiration_time.?);
    try std.testing.expectEqualStrings("hash", file.sha256_hash.?);
    try std.testing.expectEqualStrings("https://generativelanguage.googleapis.com/v1beta/files/abc123", file.uri.?);
    try std.testing.expectEqualStrings("ACTIVE", file.state.?);
    try std.testing.expectEqualStrings("UPLOADED", file.source.?);
}

test "decodeUploadedFileName rejects missing file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeUploadedFileName(std.testing.allocator, "{\"file\":{}}"),
    );
}

test "decodeFile rejects missing file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeFile(std.testing.allocator, "{}"),
    );
}

test "decodeFile rejects empty file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeFile(std.testing.allocator, "{\"name\":\"\"}"),
    );
}

test "decodeUploadedFileName rejects empty file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeUploadedFileName(std.testing.allocator, "{\"file\":{\"name\":\"\"}}"),
    );
}

test "decodeFileListPage decodes file metadata and next page token" {
    const gpa = std.testing.allocator;
    var page = try decodeFileListPage(
        gpa,
        "{\"files\":[{\"name\":\"files/one\",\"displayName\":\"one\",\"mimeType\":\"image/jpeg\",\"sizeBytes\":\"229046\",\"createTime\":\"2026-05-18T08:14:20.799526Z\",\"updateTime\":\"2026-05-18T08:14:20.799526Z\",\"expirationTime\":\"2026-05-20T08:14:20.425492423Z\",\"sha256Hash\":\"hash-one\",\"uri\":\"https://generativelanguage.googleapis.com/v1beta/files/one\",\"state\":\"ACTIVE\",\"source\":\"UPLOADED\"},{\"name\":\"files/two\",\"displayName\":\"two\",\"mimeType\":\"image/png\",\"sizeBytes\":\"123\"}],\"nextPageToken\":\"next-token\"}",
    );
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), page.files.len);
    try std.testing.expectEqualStrings("files/one", page.files[0].name);
    try std.testing.expectEqualStrings("one", page.files[0].display_name.?);
    try std.testing.expectEqualStrings("image/jpeg", page.files[0].mime_type.?);
    try std.testing.expectEqualStrings("229046", page.files[0].size_bytes.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", page.files[0].create_time.?);
    try std.testing.expectEqualStrings("2026-05-18T08:14:20.799526Z", page.files[0].update_time.?);
    try std.testing.expectEqualStrings("2026-05-20T08:14:20.425492423Z", page.files[0].expiration_time.?);
    try std.testing.expectEqualStrings("hash-one", page.files[0].sha256_hash.?);
    try std.testing.expectEqualStrings("https://generativelanguage.googleapis.com/v1beta/files/one", page.files[0].uri.?);
    try std.testing.expectEqualStrings("ACTIVE", page.files[0].state.?);
    try std.testing.expectEqualStrings("UPLOADED", page.files[0].source.?);
    try std.testing.expectEqualStrings("files/two", page.files[1].name);
    try std.testing.expectEqualStrings("two", page.files[1].display_name.?);
    try std.testing.expectEqualStrings("image/png", page.files[1].mime_type.?);
    try std.testing.expectEqualStrings("123", page.files[1].size_bytes.?);
    try std.testing.expectEqual(@as(?[]u8, null), page.files[1].create_time);
    try std.testing.expectEqualStrings("next-token", page.next_page_token.?);
}

test "decodeFileListPage accepts empty response" {
    const gpa = std.testing.allocator;
    var page = try decodeFileListPage(gpa, "{}");
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 0), page.files.len);
    try std.testing.expectEqual(@as(?[]u8, null), page.next_page_token);
}

test "decodeFileListPage rejects missing listed file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeFileListPage(std.testing.allocator, "{\"files\":[{}]}"),
    );
}

test "buildListFilesUrl percent-encodes page token" {
    const gpa = std.testing.allocator;
    const url = try buildListFilesUrl(gpa, "next token/1");
    defer gpa.free(url);

    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/files?pageSize=100&pageToken=next%20token/1",
        url,
    );
}

test "buildFileResourceUrl uses canonical file name" {
    const gpa = std.testing.allocator;
    const url = try buildFileResourceUrl(gpa, "files/abc123");
    defer gpa.free(url);

    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/files/abc123",
        url,
    );
}

test "buildFileResourceUrl percent-encodes file id path segment" {
    const gpa = std.testing.allocator;
    const url = try buildFileResourceUrl(gpa, "files/abc 123/one");
    defer gpa.free(url);

    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/files/abc%20123%2Fone",
        url,
    );
}

test "live API files upload is visible in file list" {
    if (!build_options.live_api_tests) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var environ_map = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ_map.deinit();
    const api_key = try api.apiKeyFromMap(&environ_map);
    const context = liveRequestContext(gpa, api_key);

    var uploaded_file = try uploadSampleImage(&context);
    defer uploaded_file.deinit(gpa);
    defer deleteUploadedFile(&context, uploaded_file.name);

    if (!std.mem.startsWith(u8, uploaded_file.name, "files/")) {
        std.debug.print("error: uploaded file id has unexpected shape: {s}\n", .{uploaded_file.name});
        return error.UnexpectedUploadedFileName;
    }

    if (uploaded_file.display_name) |display_name| {
        try std.testing.expectEqualStrings(live_upload_display_name, display_name);
    }

    const found_uploaded_file = try fileListContains(&context, uploaded_file.name);
    if (!found_uploaded_file) {
        std.debug.print("error: uploaded file id was not found by files list: {s}\n", .{uploaded_file.name});
        return error.UploadedFileNotListed;
    }
}

test "live API files get returns uploaded file metadata" {
    if (!build_options.live_api_tests) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var environ_map = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ_map.deinit();
    const api_key = try api.apiKeyFromMap(&environ_map);
    const context = liveRequestContext(gpa, api_key);

    var uploaded_file = try uploadSampleImage(&context);
    defer uploaded_file.deinit(gpa);
    defer deleteUploadedFile(&context, uploaded_file.name);

    var outcome = try getFileWithContext(&context, uploaded_file.name);
    var fetched_file = switch (outcome) {
        .success => |file| file,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: files get request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            return error.FileGetRequestFailed;
        },
        .response_decoding_failure => |err| return err,
    };
    defer fetched_file.deinit(gpa);

    try std.testing.expectEqualStrings(uploaded_file.name, fetched_file.name);
    if (fetched_file.display_name) |display_name| {
        try std.testing.expectEqualStrings(live_upload_display_name, display_name);
    }
    if (fetched_file.mime_type) |mime_type| {
        try std.testing.expectEqualStrings(api.ImageMime.jpeg.apiName(), mime_type);
    }
}

test "live API files delete removes uploaded file and reports missing files" {
    if (!build_options.live_api_tests) return error.SkipZigTest;

    const gpa = std.testing.allocator;
    var environ_map = try std.process.Environ.createMap(std.testing.environ, gpa);
    defer environ_map.deinit();
    const api_key = try api.apiKeyFromMap(&environ_map);
    const context = liveRequestContext(gpa, api_key);

    var uploaded_file = try uploadSampleImage(&context);
    defer uploaded_file.deinit(gpa);

    var delete_outcome = try deleteFileWithContext(&context, uploaded_file.name);
    switch (delete_outcome) {
        .success => {},
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: files delete request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            return error.FileDeleteRequestFailed;
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }

    var get_deleted_outcome = try getFileWithContext(&context, uploaded_file.name);
    try expectApiFailureStatus(file_domain.File, gpa, &get_deleted_outcome, .forbidden);

    var delete_again_outcome = try deleteFileWithContext(&context, uploaded_file.name);
    try expectApiFailureStatus(void, gpa, &delete_again_outcome, .forbidden);

    const missing_file_name = "files/nbimg-delete-missing-probe";
    var missing_probe_outcome = try getFileWithContext(&context, missing_file_name);
    try expectApiFailureStatus(file_domain.File, gpa, &missing_probe_outcome, .forbidden);

    var delete_missing_outcome = try deleteFileWithContext(&context, missing_file_name);
    try expectApiFailureStatus(void, gpa, &delete_missing_outcome, .forbidden);
}

fn liveRequestContext(gpa: std.mem.Allocator, api_key: []const u8) api.RequestContext {
    return .{
        .gpa = gpa,
        .io = std.testing.io,
        .api_key = api_key,
        .traffic_log_options = .{
            .print_request = true,
            .print_response = true,
        },
    };
}

fn uploadSampleImage(context: *const api.RequestContext) !file_domain.File {
    const gpa = context.gpa;
    const mime = api.ImageMime.fromPath(sample_image_path) orelse return error.UnsupportedInputMime;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        sample_image_path,
        gpa,
        .limited(max_upload_bytes),
    );
    defer gpa.free(bytes);
    if (bytes.len == 0) return error.EmptyUploadFile;

    var outcome = try uploadFileWithContext(context, .{
        .mime = switch (mime) {
            .jpeg => .jpeg,
            .png => .png,
            .webp => .webp,
        },
        .bytes = bytes,
        .display_name = live_upload_display_name,
    });
    return switch (outcome) {
        .success => |file| file,
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            std.debug.print(
                "error: file upload request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
            return error.FileUploadRequestFailed;
        },
        .response_decoding_failure => |err| return err,
    };
}

fn deleteUploadedFile(context: *const api.RequestContext, name: []const u8) void {
    var outcome = deleteFileWithContext(context, name) catch return;
    switch (outcome) {
        .success => {},
        .api_failure => |*failure| failure.deinit(context.gpa),
        .response_decoding_failure => {},
    }
}

fn expectApiFailureStatus(
    comptime T: type,
    gpa: std.mem.Allocator,
    outcome: *operation.OperationOutcome(T),
    expected_status: std.http.Status,
) !void {
    switch (outcome.*) {
        .api_failure => |*failure| {
            defer failure.deinit(gpa);
            if (failure.status != expected_status) {
                std.debug.print(
                    "error: Files API returned HTTP {d}; expected {d}\n{s}\n",
                    .{
                        @intFromEnum(failure.status),
                        @intFromEnum(expected_status),
                        failure.body,
                    },
                );
                return error.UnexpectedFileApiStatus;
            }
        },
        .success => |*result| {
            if (T == file_domain.File) result.deinit(gpa);
            return error.UnexpectedFileApiSuccess;
        },
        .response_decoding_failure => return error.UnexpectedResponseDecodingFailure,
    }
}

fn fileListContains(
    context: *const api.RequestContext,
    wanted_name: []const u8,
) !bool {
    const gpa = context.gpa;
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    while (true) {
        var outcome = try listFilesPageWithContext(context, page_token);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        var page = switch (outcome) {
            .success => |page| page,
            .api_failure => |*failure| {
                defer failure.deinit(gpa);
                std.debug.print(
                    "error: files list request failed with HTTP {d}\n{s}\n",
                    .{ @intFromEnum(failure.status), failure.body },
                );
                return error.FileListRequestFailed;
            },
            .response_decoding_failure => |err| return err,
        };
        defer page.deinit(gpa);

        for (page.files) |file| {
            if (std.mem.eql(u8, file.name, wanted_name)) {
                if (file.display_name) |display_name| {
                    try std.testing.expectEqualStrings(live_upload_display_name, display_name);
                }
                return true;
            }
        }

        page_token = page.next_page_token orelse return false;
        page.next_page_token = null;
    }
}
