const std = @import("std");

const root = @import("root.zig");

fn contains(comptime names: []const []const u8, comptime candidate: []const u8) bool {
    inline for (names) |name| {
        if (std.mem.eql(u8, name, candidate)) return true;
    }
    return false;
}

fn assertExactPublicDecls(
    comptime namespace_name: []const u8,
    comptime namespace: type,
    comptime expected: []const []const u8,
) void {
    const declarations = switch (@typeInfo(namespace)) {
        .@"struct" => |info| info.decls,
        .@"enum" => |info| info.decls,
        .@"union" => |info| info.decls,
        else => @compileError(namespace_name ++ " is not a declaration container"),
    };

    if (declarations.len != expected.len) {
        @compileError(namespace_name ++ " public declaration count does not match its allowlist");
    }
    inline for (declarations) |declaration| {
        if (!contains(expected, declaration.name)) {
            @compileError(namespace_name ++ " has unexpected public declaration: " ++ declaration.name);
        }
    }
    inline for (expected) |name| {
        if (!containsDeclaration(declarations, name)) {
            @compileError(namespace_name ++ " is missing public declaration: " ++ name);
        }
    }
}

fn containsDeclaration(
    comptime declarations: []const std.builtin.Type.Declaration,
    comptime candidate: []const u8,
) bool {
    inline for (declarations) |declaration| {
        if (std.mem.eql(u8, declaration.name, candidate)) return true;
    }
    return false;
}

comptime {
    @setEvalBranchQuota(100_000);

    assertExactPublicDecls("root", root, &.{
        "ApiFailure",
        "Client",
        "ClientOptions",
        "CountTokensResult",
        "EditRequest",
        "EditValidationError",
        "File",
        "FileListPage",
        "FileSource",
        "FileState",
        "FileUpload",
        "FileValidationError",
        "GeneratedImage",
        "GenerationOptions",
        "GenerationRequest",
        "GenerationResult",
        "GenerationValidationError",
        "GroundingOptions",
        "HarmBlockThreshold",
        "ImageAspectRatio",
        "ImageOutputOptions",
        "ImageSize",
        "InputImageMime",
        "Outcome",
        "OutputMime",
        "Reference",
        "ReferenceRole",
        "RemoteError",
        "RequestOptions",
        "SafetyOptions",
        "ServiceTier",
        "ThinkingLevel",
        "ThinkingOptions",
        "UploadedImage",
        "api",
        "batch",
        "max_edit_character_images",
        "max_edit_do_not_constraints",
        "max_edit_object_images",
        "max_edit_preserve_constraints",
        "max_edit_reference_label_bytes",
        "max_edit_references",
        "max_file_upload_bytes",
    });

    assertExactPublicDecls("root.ApiFailure", root.ApiFailure, &.{
        "deinit",
    });
    assertExactPublicDecls("root.Client", root.Client, &.{
        "countEditTokens",
        "countGenerateTokens",
        "deleteFile",
        "edit",
        "generate",
        "getFile",
        "init",
        "listFilesPage",
        "uploadFile",
    });
    assertExactPublicDecls("root.ClientOptions", root.ClientOptions, &.{});
    assertExactPublicDecls("root.CountTokensResult", root.CountTokensResult, &.{});
    assertExactPublicDecls("root.EditRequest", root.EditRequest, &.{});
    assertExactPublicDecls("root.File", root.File, &.{
        "deinit",
    });
    assertExactPublicDecls("root.FileListPage", root.FileListPage, &.{
        "deinit",
    });
    assertExactPublicDecls("root.FileSource", root.FileSource, &.{
        "deinit",
    });
    assertExactPublicDecls("root.FileState", root.FileState, &.{
        "deinit",
    });
    assertExactPublicDecls("root.FileUpload", root.FileUpload, &.{});
    assertExactPublicDecls("root.GeneratedImage", root.GeneratedImage, &.{
        "deinit",
    });
    assertExactPublicDecls("root.GenerationOptions", root.GenerationOptions, &.{});
    assertExactPublicDecls("root.GenerationRequest", root.GenerationRequest, &.{});
    assertExactPublicDecls("root.GenerationResult", root.GenerationResult, &.{
        "deinit",
    });
    assertExactPublicDecls("root.GroundingOptions", root.GroundingOptions, &.{});
    assertExactPublicDecls("root.HarmBlockThreshold", root.HarmBlockThreshold, &.{});
    assertExactPublicDecls("root.ImageAspectRatio", root.ImageAspectRatio, &.{});
    assertExactPublicDecls("root.ImageOutputOptions", root.ImageOutputOptions, &.{});
    assertExactPublicDecls("root.ImageSize", root.ImageSize, &.{});
    assertExactPublicDecls("root.InputImageMime", root.InputImageMime, &.{});
    assertExactPublicDecls("root.Outcome(CountTokensResult)", root.Outcome(root.CountTokensResult), &.{});
    assertExactPublicDecls("root.Outcome(GenerationResult)", root.Outcome(root.GenerationResult), &.{});
    assertExactPublicDecls("root.Outcome(File)", root.Outcome(root.File), &.{});
    assertExactPublicDecls("root.Outcome(FileListPage)", root.Outcome(root.FileListPage), &.{});
    assertExactPublicDecls("root.Outcome(void)", root.Outcome(void), &.{});
    assertExactPublicDecls("root.OutputMime", root.OutputMime, &.{});
    assertExactPublicDecls("root.Reference", root.Reference, &.{});
    assertExactPublicDecls("root.ReferenceRole", root.ReferenceRole, &.{});
    assertExactPublicDecls("root.RemoteError", root.RemoteError, &.{
        "deinit",
    });
    assertExactPublicDecls("root.RequestOptions", root.RequestOptions, &.{});
    assertExactPublicDecls("root.SafetyOptions", root.SafetyOptions, &.{});
    assertExactPublicDecls("root.ServiceTier", root.ServiceTier, &.{});
    assertExactPublicDecls("root.ThinkingLevel", root.ThinkingLevel, &.{});
    assertExactPublicDecls("root.ThinkingOptions", root.ThinkingOptions, &.{});
    assertExactPublicDecls("root.UploadedImage", root.UploadedImage, &.{});
}

test "package API matches exact allowlist" {}
