//! Gemini Files API upload and list handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");
const build_options = @import("build_options");

pub const max_upload_bytes = 64 * 1024 * 1024;
const sample_image_path = "sample_images/good_night.jpeg";

pub const InputMime = enum {
    jpeg,
    png,
    webp,

    pub fn fromPath(path: []const u8) ?InputMime {
        const extension = std.fs.path.extension(path);
        if (std.ascii.eqlIgnoreCase(extension, ".jpg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".jpeg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".png")) return .png;
        if (std.ascii.eqlIgnoreCase(extension, ".webp")) return .webp;
        return null;
    }

    pub fn apiName(mime: InputMime) []const u8 {
        return switch (mime) {
            .jpeg => "image/jpeg",
            .png => "image/png",
            .webp => "image/webp",
        };
    }
};

pub const FileUpload = struct {
    mime: InputMime,
    bytes: []const u8,
};

pub const FileListPage = struct {
    names: [][]u8,
    next_page_token: ?[]u8 = null,

    pub fn deinit(page: *FileListPage, gpa: std.mem.Allocator) void {
        for (page.names) |name| gpa.free(name);
        gpa.free(page.names);
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

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    var start = try startFileUpload(gpa, &client, api_key, file);
    if (start.response.status != .ok) {
        if (start.upload_url) |upload_url| gpa.free(upload_url);
        return start.response;
    }
    defer start.response.deinit(gpa);

    const upload_url = start.upload_url orelse return error.MissingUploadUrl;
    defer gpa.free(upload_url);

    return uploadFileBytes(gpa, &client, api_key, upload_url, file);
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

fn startFileUpload(
    gpa: std.mem.Allocator,
    client: *std.http.Client,
    api_key: []const u8,
    file: FileUpload,
) !api.HttpResponseWithUploadUrl {
    assert(api_key.len > 0);
    assert(file.bytes.len > 0);

    var content_length_buffer: [32]u8 = undefined;
    const content_length = try std.fmt.bufPrint(&content_length_buffer, "{d}", .{file.bytes.len});

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
        .{ .name = "X-Goog-Upload-Protocol", .value = "resumable" },
        .{ .name = "X-Goog-Upload-Command", .value = "start" },
        .{ .name = "X-Goog-Upload-Header-Content-Length", .value = content_length },
        .{ .name = "X-Goog-Upload-Header-Content-Type", .value = file.mime.apiName() },
    };

    return api.requestWithBody(gpa, client, .POST, fileUploadStartUrl(), "application/json", &headers, "{\"file\":{}}", .{
        .capture_upload_url = true,
        .request_body_log = .{ .text = "{\"file\":{}}" },
    });
}

fn uploadFileBytes(
    gpa: std.mem.Allocator,
    client: *std.http.Client,
    api_key: []const u8,
    upload_url: []const u8,
    file: FileUpload,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assert(upload_url.len > 0);
    assert(file.bytes.len > 0);

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
        .{ .name = "X-Goog-Upload-Offset", .value = "0" },
        .{ .name = "X-Goog-Upload-Command", .value = "upload, finalize" },
    };

    const result = try api.requestWithBody(gpa, client, .POST, upload_url, file.mime.apiName(), &headers, file.bytes, .{
        .request_body_log = .{
            .binary = .{
                .byte_count = file.bytes.len,
                .mime = file.mime.apiName(),
            },
        },
    });
    assert(result.upload_url == null);
    return result.response;
}

pub fn decodeUploadedFileName(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    const Response = struct {
        file: ?File = null,

        const File = struct {
            name: ?[]const u8 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const file = parsed.value.file orelse return error.MissingFileName;
    const name = file.name orelse return error.MissingFileName;
    if (name.len == 0) return error.MissingFileName;
    return gpa.dupe(u8, name);
}

pub fn decodeFileListPage(gpa: std.mem.Allocator, response_json: []const u8) !FileListPage {
    const Response = struct {
        files: []const File = &.{},
        nextPageToken: ?[]const u8 = null,

        const File = struct {
            name: ?[]const u8 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var names: std.ArrayList([]u8) = .empty;
    errdefer {
        for (names.items) |name| gpa.free(name);
        names.deinit(gpa);
    }

    try names.ensureTotalCapacity(gpa, parsed.value.files.len);
    for (parsed.value.files) |file| {
        const name = file.name orelse return error.MissingFileName;
        if (name.len == 0) return error.MissingFileName;
        names.appendAssumeCapacity(try gpa.dupe(u8, name));
    }

    const next_page_token: ?[]u8 = if (parsed.value.nextPageToken) |token| token: {
        if (token.len == 0) break :token null;
        break :token try gpa.dupe(u8, token);
    } else null;
    errdefer if (next_page_token) |token| gpa.free(token);

    return .{
        .names = try names.toOwnedSlice(gpa),
        .next_page_token = next_page_token,
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

fn fileUploadStartUrl() []const u8 {
    return "https://generativelanguage.googleapis.com/upload/v1beta/files";
}

fn filesListBaseUrl() []const u8 {
    return "https://generativelanguage.googleapis.com/v1beta/files";
}

test "InputMime detects supported image extensions" {
    try std.testing.expectEqual(InputMime.jpeg, InputMime.fromPath("sample_images/good_night.jpeg").?);
    try std.testing.expectEqual(InputMime.jpeg, InputMime.fromPath("photo.JPG").?);
    try std.testing.expectEqual(InputMime.png, InputMime.fromPath("photo.png").?);
    try std.testing.expectEqual(InputMime.webp, InputMime.fromPath("photo.webp").?);
    try std.testing.expectEqual(@as(?InputMime, null), InputMime.fromPath("photo.gif"));
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

test "decodeUploadedFileName rejects missing file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeUploadedFileName(std.testing.allocator, "{\"file\":{}}"),
    );
}

test "decodeUploadedFileName rejects empty file name" {
    try std.testing.expectError(
        error.MissingFileName,
        decodeUploadedFileName(std.testing.allocator, "{\"file\":{\"name\":\"\"}}"),
    );
}

test "decodeFileListPage decodes names and next page token" {
    const gpa = std.testing.allocator;
    var page = try decodeFileListPage(
        gpa,
        "{\"files\":[{\"name\":\"files/one\"},{\"name\":\"files/two\"}],\"nextPageToken\":\"next-token\"}",
    );
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 2), page.names.len);
    try std.testing.expectEqualStrings("files/one", page.names[0]);
    try std.testing.expectEqualStrings("files/two", page.names[1]);
    try std.testing.expectEqualStrings("next-token", page.next_page_token.?);
}

test "decodeFileListPage accepts empty response" {
    const gpa = std.testing.allocator;
    var page = try decodeFileListPage(gpa, "{}");
    defer page.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 0), page.names.len);
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

    const uploaded_name = try uploadSampleImage(gpa, api_key);
    defer gpa.free(uploaded_name);

    if (!std.mem.startsWith(u8, uploaded_name, "files/")) {
        std.debug.print("error: uploaded file id has unexpected shape: {s}\n", .{uploaded_name});
        return error.UnexpectedUploadedFileName;
    }

    const found_uploaded_file = try fileListContains(gpa, api_key, uploaded_name);
    if (!found_uploaded_file) {
        std.debug.print("error: uploaded file id was not found by files list: {s}\n", .{uploaded_name});
        return error.UploadedFileNotListed;
    }
}

fn uploadSampleImage(gpa: std.mem.Allocator, api_key: []const u8) ![]u8 {
    const mime = InputMime.fromPath(sample_image_path) orelse return error.UnsupportedInputMime;
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
    });
    defer response.deinit(gpa);

    if (response.status != .ok) {
        std.debug.print(
            "error: file upload request failed with HTTP {d}\n{s}\n",
            .{ @intFromEnum(response.status), response.body },
        );
        return error.FileUploadRequestFailed;
    }

    return decodeUploadedFileName(gpa, response.body);
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

        for (page.names) |name| {
            if (std.mem.eql(u8, name, wanted_name)) return true;
        }

        page_token = page.next_page_token orelse return false;
        page.next_page_token = null;
    }
}
