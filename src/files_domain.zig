//! Shared typed Gemini Files domain models.

const std = @import("std");

pub const max_file_upload_bytes = 64 * 1024 * 1024;

pub const InputImageMime = enum {
    jpeg,
    png,
    webp,
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

fn freeOptional(allocator: std.mem.Allocator, value: ?[]u8) void {
    if (value) |bytes| allocator.free(bytes);
}
