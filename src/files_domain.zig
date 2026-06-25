//! Shared typed Gemini Files domain models.

const std = @import("std");

pub const max_file_upload_bytes = 64 * 1024 * 1024;

pub const InputImageMime = enum {
    jpeg,
    png,
    webp,
};

/// Mirrors the shared google.rpc.Status shape used by Gemini resources.
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
pub const FileUpload = struct {
    mime: InputImageMime,
    bytes: []const u8,
    display_name: ?[]const u8 = null,
};

/// Owns only unrecognized Gemini File state spellings.
pub const FileState = union(enum) {
    unspecified,
    processing,
    active,
    failed,
    unknown: []u8,

    /// Frees an unknown spelling, if present, and invalidates the value.
    pub fn deinit(state: *FileState, allocator: std.mem.Allocator) void {
        switch (state.*) {
            .unknown => |name| allocator.free(name),
            else => {},
        }
        state.* = undefined;
    }
};

/// Owns only unrecognized Gemini File source spellings.
pub const FileSource = union(enum) {
    unspecified,
    uploaded,
    generated,
    registered,
    unknown: []u8,

    /// Frees an unknown spelling, if present, and invalidates the value.
    pub fn deinit(source: *FileSource, allocator: std.mem.Allocator) void {
        switch (source.*) {
            .unknown => |name| allocator.free(name),
            else => {},
        }
        source.* = undefined;
    }
};

/// Owns one structured error reported by a remote Gemini resource.
pub const RemoteError = struct {
    code: ?i64 = null,
    message: []u8,
    details_json: ?[]u8 = null,

    /// Frees all owned error data and invalidates the value.
    pub fn deinit(remote_error: *RemoteError, allocator: std.mem.Allocator) void {
        allocator.free(remote_error.message);
        if (remote_error.details_json) |details| allocator.free(details);
        remote_error.* = undefined;
    }
};

/// Owns a decoded Gemini File resource and optional metadata.
pub const File = struct {
    name: []u8,
    display_name: ?[]u8 = null,
    mime_type: ?[]u8 = null,
    size_bytes: ?u64 = null,
    create_time: ?[]u8 = null,
    update_time: ?[]u8 = null,
    expiration_time: ?[]u8 = null,
    sha256_hash: ?[]u8 = null,
    uri: ?[]u8 = null,
    download_uri: ?[]u8 = null,
    state: FileState = .unspecified,
    source: FileSource = .unspecified,
    processing_error: ?RemoteError = null,

    /// Frees all owned file data and invalidates the value.
    pub fn deinit(file: *File, allocator: std.mem.Allocator) void {
        allocator.free(file.name);
        freeOptional(allocator, file.display_name);
        freeOptional(allocator, file.mime_type);
        freeOptional(allocator, file.create_time);
        freeOptional(allocator, file.update_time);
        freeOptional(allocator, file.expiration_time);
        freeOptional(allocator, file.sha256_hash);
        freeOptional(allocator, file.uri);
        freeOptional(allocator, file.download_uri);
        file.state.deinit(allocator);
        file.source.deinit(allocator);
        if (file.processing_error) |*remote_error| remote_error.deinit(allocator);
        file.* = undefined;
    }
};

/// Owns one page of File resources and an optional continuation token.
pub const FileListPage = struct {
    files: []File,
    next_page_token: ?[]u8 = null,

    /// Frees all nested file data and invalidates the value.
    pub fn deinit(page: *FileListPage, allocator: std.mem.Allocator) void {
        for (page.files) |*file| file.deinit(allocator);
        allocator.free(page.files);
        if (page.next_page_token) |token| allocator.free(token);
        page.* = undefined;
    }
};

/// Reports invalid caller-controlled Files operation fields.
pub const FileValidationError = error{
    EmptyFileBytes,
    FileTooLarge,
    InvalidDisplayName,
    InvalidFileName,
    EmptyPageToken,
};

/// Decodes a Files upload response wrapper into owned File metadata.
pub fn decodeUploadedFile(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !File {
    const Response = struct {
        file: ?WireFile = null,
    };

    var parsed = try std.json.parseFromSlice(Response, allocator, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const response_file = parsed.value.file orelse return error.MissingFileName;
    return ownedFileFromResponse(allocator, response_file);
}

/// Decodes a Files resource response into owned File metadata.
pub fn decodeFile(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !File {
    var parsed = try std.json.parseFromSlice(WireFile, allocator, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return ownedFileFromResponse(allocator, parsed.value);
}

/// Decodes a Files list response into one owned page.
pub fn decodeFileListPage(
    allocator: std.mem.Allocator,
    response_json: []const u8,
) !FileListPage {
    const Response = struct {
        files: []const WireFile = &.{},
        nextPageToken: ?[]const u8 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, allocator, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit(allocator);
        files.deinit(allocator);
    }

    try files.ensureTotalCapacity(allocator, parsed.value.files.len);
    for (parsed.value.files) |response_file| {
        files.appendAssumeCapacity(try ownedFileFromResponse(allocator, response_file));
    }

    const next_page_token = try dupeNonEmptyOptional(allocator, parsed.value.nextPageToken);
    errdefer if (next_page_token) |token| allocator.free(token);

    return .{
        .files = try files.toOwnedSlice(allocator),
        .next_page_token = next_page_token,
    };
}

/// Copies one optional wire error into the public owned error shape.
fn ownedRemoteError(
    allocator: std.mem.Allocator,
    wire_error: ?WireRemoteError,
) !?RemoteError {
    const remote_error = wire_error orelse return null;
    return try remoteErrorFromWire(allocator, remote_error);
}

/// Decodes one JSON object into the public owned error shape.
pub fn remoteErrorFromJsonValue(
    allocator: std.mem.Allocator,
    value: std.json.Value,
) !RemoteError {
    const object = switch (value) {
        .object => |object| object,
        else => return error.InvalidRemoteError,
    };

    const code = if (object.get("code")) |code_value|
        try parseSignedInteger(code_value)
    else
        null;

    const message = if (object.get("message")) |message_value| switch (message_value) {
        .string => |message| message,
        else => return error.MissingRemoteErrorMessage,
    } else return error.MissingRemoteErrorMessage;

    const details_json = if (object.get("details")) |details| details_json: {
        if (details == .null) break :details_json null;
        break :details_json try stringifyJson(allocator, details);
    } else null;
    errdefer if (details_json) |details| allocator.free(details);

    const owned_message = try allocator.dupe(u8, message);
    errdefer allocator.free(owned_message);

    return .{
        .code = code,
        .message = owned_message,
        .details_json = details_json,
    };
}

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}

fn ownedFileFromResponse(
    allocator: std.mem.Allocator,
    response_file: WireFile,
) !File {
    const name = response_file.name orelse return error.MissingFileName;
    if (!isCanonicalFileName(name)) return error.InvalidFileName;

    var file = File{
        .name = try allocator.dupe(u8, name),
    };
    errdefer file.deinit(allocator);

    file.display_name = try dupeOptional(allocator, response_file.displayName);
    file.mime_type = try dupeOptional(allocator, response_file.mimeType);
    file.size_bytes = try parseOptionalSizeBytes(response_file.sizeBytes);
    file.create_time = try dupeOptional(allocator, response_file.createTime);
    file.update_time = try dupeOptional(allocator, response_file.updateTime);
    file.expiration_time = try dupeOptional(allocator, response_file.expirationTime);
    file.sha256_hash = try dupeOptional(allocator, response_file.sha256Hash);
    file.uri = try dupeOptional(allocator, response_file.uri);
    file.download_uri = try dupeOptional(allocator, response_file.downloadUri);
    file.state = try ownedFileState(allocator, response_file.state);
    file.source = try ownedFileSource(allocator, response_file.source);
    file.processing_error = try ownedRemoteError(allocator, response_file.@"error");

    return file;
}

fn ownedFileState(
    allocator: std.mem.Allocator,
    wire_name: ?[]const u8,
) !FileState {
    const name = wire_name orelse return .unspecified;
    if (std.mem.eql(u8, name, "STATE_UNSPECIFIED")) return .unspecified;
    if (std.mem.eql(u8, name, "PROCESSING")) return .processing;
    if (std.mem.eql(u8, name, "ACTIVE")) return .active;
    if (std.mem.eql(u8, name, "FAILED")) return .failed;
    return .{ .unknown = try allocator.dupe(u8, name) };
}

fn ownedFileSource(
    allocator: std.mem.Allocator,
    wire_name: ?[]const u8,
) !FileSource {
    const name = wire_name orelse return .unspecified;
    if (std.mem.eql(u8, name, "SOURCE_UNSPECIFIED")) return .unspecified;
    if (std.mem.eql(u8, name, "UPLOADED")) return .uploaded;
    if (std.mem.eql(u8, name, "GENERATED")) return .generated;
    if (std.mem.eql(u8, name, "REGISTERED")) return .registered;
    return .{ .unknown = try allocator.dupe(u8, name) };
}

fn parseOptionalSizeBytes(value: ?[]const u8) !?u64 {
    const bytes = value orelse return null;
    return std.fmt.parseInt(u64, bytes, 10) catch return error.InvalidFileSize;
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try allocator.dupe(u8, bytes) else null;
}

fn dupeNonEmptyOptional(
    allocator: std.mem.Allocator,
    value: ?[]const u8,
) !?[]u8 {
    const bytes = value orelse return null;
    if (bytes.len == 0) return null;
    return try allocator.dupe(u8, bytes);
}

fn isCanonicalFileName(name: []const u8) bool {
    const canonical_file_name_prefix = "files/";
    if (!std.mem.startsWith(u8, name, canonical_file_name_prefix)) return false;
    return name.len > canonical_file_name_prefix.len;
}

fn remoteErrorFromWire(
    allocator: std.mem.Allocator,
    remote_error: WireRemoteError,
) !RemoteError {
    const message = remote_error.message orelse return error.MissingRemoteErrorMessage;

    const owned_message = try allocator.dupe(u8, message);
    errdefer allocator.free(owned_message);

    const details_json = if (remote_error.details) |details| details_json: {
        if (details == .null) break :details_json null;
        break :details_json try stringifyJson(allocator, details);
    } else null;
    errdefer if (details_json) |details| allocator.free(details);

    return .{
        .code = remote_error.code,
        .message = owned_message,
        .details_json = details_json,
    };
}

fn parseSignedInteger(value: std.json.Value) !i64 {
    return switch (value) {
        .string => |string| parseSignedIntegerText(string),
        .number_string => |number| parseSignedIntegerText(number),
        .integer => |integer| std.math.cast(i64, integer) orelse return error.InvalidRemoteErrorCode,
        else => return error.InvalidRemoteErrorCode,
    };
}

fn parseSignedIntegerText(bytes: []const u8) !i64 {
    if (bytes.len == 0) return error.InvalidRemoteErrorCode;
    return std.fmt.parseInt(i64, bytes, 10) catch return error.InvalidRemoteErrorCode;
}

fn stringifyJson(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try std.json.Stringify.value(value, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(allocator);
    return list.toOwnedSlice(allocator);
}
