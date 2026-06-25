//! Typed Gemini Files API operations and response decoding.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");
const file_domain = @import("files_domain.zig");
const operation = @import("operation.zig");

const sample_image_path = "sample_images/good_night.jpeg";
const live_upload_display_name = "nbimg live api sample";

fn uploadFile(
    context: *const api.RequestContext,
    file: file_domain.FileUpload,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(file.bytes.len > 0);
    if (file.display_name) |display_name| assert(api.isValidDisplayName(display_name));

    return api.uploadResumableBytes(context, .{
        .content_type = wireImageMime(file.mime).apiName(),
        .bytes = file.bytes,
        .display_name = file.display_name,
    });
}

fn listFilesPage(
    context: *const api.RequestContext,
    page_token: ?[]const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    if (page_token) |token| assert(token.len > 0);

    const url = try buildListFilesUrl(context.gpa, page_token);
    defer context.gpa.free(url);

    return api.getJson(context, url);
}

fn getFile(
    context: *const api.RequestContext,
    name: []const u8,
) !api.HttpResponse {
    assert(context.api_key.len > 0);
    assert(api.isCanonicalFileName(name));

    const url = try buildGetFileUrl(context.gpa, name);
    defer context.gpa.free(url);

    return api.getJson(context, url);
}

fn deleteFile(
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

    var response = try uploadFile(context, upload);
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

fn decodeTypedUploadedFile(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.File {
    return file_domain.decodeUploadedFile(gpa, response_json);
}

fn decodeTypedFile(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.File {
    return file_domain.decodeFile(gpa, response_json);
}

fn decodeTypedFileListPage(
    gpa: std.mem.Allocator,
    response_json: []const u8,
) !file_domain.FileListPage {
    return file_domain.decodeFileListPage(gpa, response_json);
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
        const json = try std.fmt.allocPrint(
            std.testing.allocator,
            "{{\"name\":\"files/state\",\"state\":\"{s}\"}}",
            .{entry[0]},
        );
        defer std.testing.allocator.free(json);
        var file = try decodeTypedFile(std.testing.allocator, json);
        defer file.deinit(std.testing.allocator);
        try std.testing.expectEqual(entry[1], file.state);
    }

    const source_cases = .{
        .{ "SOURCE_UNSPECIFIED", file_domain.FileSource.unspecified },
        .{ "UPLOADED", file_domain.FileSource.uploaded },
        .{ "GENERATED", file_domain.FileSource.generated },
        .{ "REGISTERED", file_domain.FileSource.registered },
    };
    inline for (source_cases) |entry| {
        const json = try std.fmt.allocPrint(
            std.testing.allocator,
            "{{\"name\":\"files/source\",\"source\":\"{s}\"}}",
            .{entry[0]},
        );
        defer std.testing.allocator.free(json);
        var file = try decodeTypedFile(std.testing.allocator, json);
        defer file.deinit(std.testing.allocator);
        try std.testing.expectEqual(entry[1], file.source);
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

test "typed upload get and list accept representative non-200 2xx responses" {
    var upload_response = api.HttpResponse{
        .status = .created,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"file\":{\"name\":\"files/uploaded\"}}",
        ),
    };
    var upload_outcome = typedFileOutcomeFromResponse(
        file_domain.File,
        std.testing.allocator,
        &upload_response,
        decodeTypedUploadedFile,
    );
    switch (upload_outcome) {
        .success => |*file| file.deinit(std.testing.allocator),
        .api_failure, .response_decoding_failure => return error.UnexpectedUploadFailure,
    }

    var get_response = api.HttpResponse{
        .status = .accepted,
        .body = try std.testing.allocator.dupe(u8, "{\"name\":\"files/fetched\"}"),
    };
    var get_outcome = typedFileOutcomeFromResponse(
        file_domain.File,
        std.testing.allocator,
        &get_response,
        decodeTypedFile,
    );
    switch (get_outcome) {
        .success => |*file| file.deinit(std.testing.allocator),
        .api_failure, .response_decoding_failure => return error.UnexpectedGetFailure,
    }

    var list_response = api.HttpResponse{
        .status = .partial_content,
        .body = try std.testing.allocator.dupe(
            u8,
            "{\"files\":[{\"name\":\"files/listed\"}]}",
        ),
    };
    var list_outcome = typedFileOutcomeFromResponse(
        file_domain.FileListPage,
        std.testing.allocator,
        &list_response,
        decodeTypedFileListPage,
    );
    switch (list_outcome) {
        .success => |*page| page.deinit(std.testing.allocator),
        .api_failure, .response_decoding_failure => return error.UnexpectedListFailure,
    }
}

test "typed upload and list report malformed successful responses" {
    var upload_response = api.HttpResponse{
        .status = .accepted,
        .body = try std.testing.allocator.dupe(u8, "{\"file\":{}}"),
    };
    var upload_outcome = typedFileOutcomeFromResponse(
        file_domain.File,
        std.testing.allocator,
        &upload_response,
        decodeTypedUploadedFile,
    );
    switch (upload_outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.MissingFileName, err);
        },
        .success => |*file| {
            file.deinit(std.testing.allocator);
            return error.UnexpectedUploadSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedUploadApiFailure;
        },
    }

    var list_response = api.HttpResponse{
        .status = .partial_content,
        .body = try std.testing.allocator.dupe(u8, "{\"files\":[{}]}"),
    };
    var list_outcome = typedFileOutcomeFromResponse(
        file_domain.FileListPage,
        std.testing.allocator,
        &list_response,
        decodeTypedFileListPage,
    );
    switch (list_outcome) {
        .response_decoding_failure => |err| {
            try std.testing.expectEqual(error.MissingFileName, err);
        },
        .success => |*page| {
            page.deinit(std.testing.allocator);
            return error.UnexpectedListSuccess;
        },
        .api_failure => |*failure| {
            failure.deinit(std.testing.allocator);
            return error.UnexpectedListApiFailure;
        },
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
        .limited(file_domain.max_file_upload_bytes),
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
