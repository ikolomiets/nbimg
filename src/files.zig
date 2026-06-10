//! Gemini Files API upload and list handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");

pub const max_upload_bytes = 64 * 1024 * 1024;
const sample_image_path = "sample_images/good_night.jpeg";
const live_upload_display_name = "nbimg live api sample";

pub const FileUpload = struct {
    mime: api.ImageMime,
    bytes: []const u8,
    display_name: ?[]const u8 = null,
};

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

pub const FileListPage = struct {
    files: []File,
    next_page_token: ?[]u8 = null,

    pub fn deinit(page: *FileListPage, gpa: std.mem.Allocator) void {
        for (page.files) |*file| file.deinit(gpa);
        gpa.free(page.files);
        if (page.next_page_token) |token| gpa.free(token);
        page.* = undefined;
    }
};

pub fn uploadFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    file: FileUpload,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(file.bytes.len > 0);
    if (file.display_name) |display_name| assert(isValidDisplayName(display_name));

    return api.uploadResumableBytes(gpa, io, api_key, .{
        .content_type = file.mime.apiName(),
        .bytes = file.bytes,
        .display_name = file.display_name,
    });
}

pub fn listFilesPage(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    page_token: ?[]const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    if (page_token) |token| assert(token.len > 0);

    const url = try buildListFilesUrl(gpa, page_token);
    defer gpa.free(url);

    return api.getJson(gpa, io, api_key, url);
}

pub fn getFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    name: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(api.isCanonicalFileName(name));

    const url = try buildGetFileUrl(gpa, name);
    defer gpa.free(url);

    return api.getJson(gpa, io, api_key, url);
}

pub fn deleteFile(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    name: []const u8,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(api.isCanonicalFileName(name));

    const url = try buildFileResourceUrl(gpa, name);
    defer gpa.free(url);

    return api.deleteJson(gpa, io, api_key, url);
}

pub fn decodeUploadedFileName(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    return api.decodeUploadedFileName(gpa, response_json);
}

pub fn decodeUploadedFile(gpa: std.mem.Allocator, response_json: []const u8) !File {
    const Response = struct {
        file: ?ResponseFile = null,

        const ResponseFile = struct {
            name: ?[]const u8 = null,
            displayName: ?[]const u8 = null,
            mimeType: ?[]const u8 = null,
            sizeBytes: ?[]const u8 = null,
            createTime: ?[]const u8 = null,
            updateTime: ?[]const u8 = null,
            expirationTime: ?[]const u8 = null,
            sha256Hash: ?[]const u8 = null,
            uri: ?[]const u8 = null,
            state: ?[]const u8 = null,
            source: ?[]const u8 = null,
        };
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

pub fn decodeFile(gpa: std.mem.Allocator, response_json: []const u8) !File {
    const Response = struct {
        name: ?[]const u8 = null,
        displayName: ?[]const u8 = null,
        mimeType: ?[]const u8 = null,
        sizeBytes: ?[]const u8 = null,
        createTime: ?[]const u8 = null,
        updateTime: ?[]const u8 = null,
        expirationTime: ?[]const u8 = null,
        sha256Hash: ?[]const u8 = null,
        uri: ?[]const u8 = null,
        state: ?[]const u8 = null,
        source: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return ownedFileFromResponse(gpa, parsed.value);
}

pub fn decodeFileListPage(gpa: std.mem.Allocator, response_json: []const u8) !FileListPage {
    const Response = struct {
        files: []const ResponseFile = &.{},
        nextPageToken: ?[]const u8 = null,

        const ResponseFile = struct {
            name: ?[]const u8 = null,
            displayName: ?[]const u8 = null,
            mimeType: ?[]const u8 = null,
            sizeBytes: ?[]const u8 = null,
            createTime: ?[]const u8 = null,
            updateTime: ?[]const u8 = null,
            expirationTime: ?[]const u8 = null,
            sha256Hash: ?[]const u8 = null,
            uri: ?[]const u8 = null,
            state: ?[]const u8 = null,
            source: ?[]const u8 = null,
        };
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

fn buildFileUploadStartMetadata(gpa: std.mem.Allocator, display_name: ?[]const u8) ![]u8 {
    return api.buildResumableUploadMetadata(gpa, display_name);
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

test "files upload display name metadata defaults to empty file object" {
    const gpa = std.testing.allocator;
    const metadata = try buildFileUploadStartMetadata(gpa, null);
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings("{\"file\":{}}", metadata);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
}

test "files upload display name metadata includes displayName" {
    const gpa = std.testing.allocator;
    const metadata = try buildFileUploadStartMetadata(gpa, "nbimg live api sample");
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"displayName\":\"nbimg live api sample\"}}",
        metadata,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
}

test "files upload display name metadata escapes JSON string content" {
    const gpa = std.testing.allocator;
    const metadata = try buildFileUploadStartMetadata(gpa, "quote \" slash \\ newline \n");
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"displayName\":\"quote \\\" slash \\\\ newline \\n\"}}",
        metadata,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
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

    api.traffic_log_options = .{
        .print_request = true,
        .print_response = true,
    };
    defer api.traffic_log_options = .{};

    var uploaded_file = try uploadSampleImage(gpa, api_key);
    defer uploaded_file.deinit(gpa);

    if (!std.mem.startsWith(u8, uploaded_file.name, "files/")) {
        std.debug.print("error: uploaded file id has unexpected shape: {s}\n", .{uploaded_file.name});
        return error.UnexpectedUploadedFileName;
    }

    if (uploaded_file.display_name) |display_name| {
        try std.testing.expectEqualStrings(live_upload_display_name, display_name);
    }

    const found_uploaded_file = try fileListContains(gpa, api_key, uploaded_file.name);
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

    api.traffic_log_options = .{
        .print_request = true,
        .print_response = true,
    };
    defer api.traffic_log_options = .{};

    var uploaded_file = try uploadSampleImage(gpa, api_key);
    defer uploaded_file.deinit(gpa);

    var response = try getFile(gpa, std.testing.io, api_key, uploaded_file.name);
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: files get request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return error.FileGetRequestFailed;
    }

    var fetched_file = try decodeFile(gpa, response.body);
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

    api.traffic_log_options = .{
        .print_request = true,
        .print_response = true,
    };
    defer api.traffic_log_options = .{};

    var uploaded_file = try uploadSampleImage(gpa, api_key);
    defer uploaded_file.deinit(gpa);

    var delete_response = try deleteFile(gpa, std.testing.io, api_key, uploaded_file.name);
    defer delete_response.deinit(gpa);

    if (delete_response.status != .ok) {
        std.debug.print(
            "error: files delete request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(delete_response.status), delete_response.body },
        );
        return error.FileDeleteRequestFailed;
    }
    try expectEmptyJsonObjectBody(gpa, delete_response.body);

    var get_deleted_response = try getFile(gpa, std.testing.io, api_key, uploaded_file.name);
    defer get_deleted_response.deinit(gpa);
    if (get_deleted_response.status != .forbidden) {
        std.debug.print(
            "error: deleted file get returned HTTP {d}; expected 403\n{s}\n",
            .{ @intFromEnum(get_deleted_response.status), get_deleted_response.body },
        );
        return error.DeletedFileGetUnexpectedStatus;
    }

    var delete_again_response = try deleteFile(gpa, std.testing.io, api_key, uploaded_file.name);
    defer delete_again_response.deinit(gpa);
    if (delete_again_response.status != .forbidden) {
        std.debug.print(
            "error: already deleted file delete returned HTTP {d}; expected 403\n{s}\n",
            .{ @intFromEnum(delete_again_response.status), delete_again_response.body },
        );
        return error.AlreadyDeletedFileDeleteUnexpectedStatus;
    }

    const missing_file_name = "files/nbimg-delete-missing-probe";
    var missing_probe_response = try getFile(gpa, std.testing.io, api_key, missing_file_name);
    defer missing_probe_response.deinit(gpa);
    if (missing_probe_response.status != .forbidden) {
        std.debug.print(
            "error: missing-file probe for {s} returned HTTP {d}; refusing delete\n{s}\n",
            .{ missing_file_name, @intFromEnum(missing_probe_response.status), missing_probe_response.body },
        );
        return error.MissingFileProbeUnexpectedStatus;
    }

    var delete_missing_response = try deleteFile(gpa, std.testing.io, api_key, missing_file_name);
    defer delete_missing_response.deinit(gpa);
    if (delete_missing_response.status != .forbidden) {
        std.debug.print(
            "error: missing file delete returned HTTP {d}; expected 403\n{s}\n",
            .{ @intFromEnum(delete_missing_response.status), delete_missing_response.body },
        );
        return error.MissingFileDeleteUnexpectedStatus;
    }
}

fn uploadSampleImage(gpa: std.mem.Allocator, api_key: []const u8) !File {
    const mime = api.ImageMime.fromPath(sample_image_path) orelse return error.UnsupportedInputMime;
    const bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        sample_image_path,
        gpa,
        .limited(max_upload_bytes),
    );
    defer gpa.free(bytes);
    if (bytes.len == 0) return error.EmptyUploadFile;

    var response = try uploadFile(gpa, std.testing.io, api_key, .{
        .mime = mime,
        .bytes = bytes,
        .display_name = live_upload_display_name,
    });
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: file upload request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return error.FileUploadRequestFailed;
    }

    return decodeUploadedFile(gpa, response.body);
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

fn fileListContains(
    gpa: std.mem.Allocator,
    api_key: []const u8,
    wanted_name: []const u8,
) !bool {
    var page_token: ?[]u8 = null;
    defer if (page_token) |token| gpa.free(token);

    while (true) {
        var response = try listFilesPage(gpa, std.testing.io, api_key, page_token);
        defer response.deinit(gpa);

        if (page_token) |token| {
            gpa.free(token);
            page_token = null;
        }

        if (response.status != .ok) {
            std.debug.print(
                "error: files list request failed with HTTP {d}\n{s}\n",
                .{ @intFromEnum(response.status), response.body },
            );
            return error.FileListRequestFailed;
        }

        var page = try decodeFileListPage(gpa, response.body);
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
