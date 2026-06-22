const std = @import("std");

const api = @import("api.zig");
const batch = @import("batch.zig");
const client = @import("client.zig");
const cli = @import("cli.zig");
const edit = @import("edit.zig");
const files = @import("files.zig");
const gen = @import("gen.zig");

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

    assertExactPublicDecls("cli", cli, &.{
        "run",
    });
    assertExactPublicDecls("client", client, &.{
        "ApiFailure",
        "Client",
        "ClientOptions",
        "CountTokensResult",
        "EditRequest",
        "EditValidationError",
        "GeneratedImage",
        "GeneratedContentOperationOutcome",
        "GeneratedContentResponsePolicy",
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
        "RequestOptions",
        "SafetyOptions",
        "ServiceTier",
        "ThinkingLevel",
        "ThinkingOptions",
        "UploadedImage",
        "editWithContext",
        "generateWithContext",
        "max_edit_character_images",
        "max_edit_do_not_constraints",
        "max_edit_object_images",
        "max_edit_preserve_constraints",
        "max_edit_reference_label_bytes",
        "max_edit_references",
    });
    assertExactPublicDecls("gen", gen, &.{
        "buildGenerateRequest",
    });
    assertExactPublicDecls("edit", edit, &.{
        "EditRequest",
        "Reference",
        "ReferenceRole",
        "UploadedImage",
        "buildGenerateRequest",
        "isValidLabel",
        "max_character_references",
        "max_do_not_constraints",
        "max_label_bytes",
        "max_object_references",
        "max_preserve_constraints",
        "max_references",
        "validateRequest",
        "ValidationError",
    });
    assertExactPublicDecls("files", files, &.{
        "File",
        "FileListPage",
        "FileUpload",
        "decodeFile",
        "decodeFileListPage",
        "decodeUploadedFile",
        "deleteFile",
        "getFile",
        "listFilesPage",
        "max_upload_bytes",
        "uploadFile",
    });
    assertExactPublicDecls("batch", batch, &.{
        "DownloadInfo",
        "ListPage",
        "OutputLineIterator",
        "OutputRecord",
        "SubmitRequest",
        "buildEntryJson",
        "cancel",
        "decodeBatchName",
        "decodeDownloadInfo",
        "decodeListPage",
        "decodeOutputRecord",
        "downloadOutput",
        "isCanonicalBatchName",
        "listJson",
        "listPage",
        "max_entries",
        "max_entry_bytes",
        "max_input_bytes",
        "max_output_bytes",
        "prettyJson",
        "safeOutputKey",
        "status",
        "submit",
        "uploadInput",
        "validateInputJsonl",
        "validateOutputJsonl",
    });
    assertExactPublicDecls("api", api, &.{
        "ApiKeyError",
        "CountTokensResult",
        "GenerateContent",
        "GenerateContentRequestOptions",
        "GenerateFileData",
        "GeneratePart",
        "GeneratedFile",
        "GeneratedFiles",
        "GenerationOptions",
        "GroundingOptions",
        "HarmBlockThreshold",
        "HttpResponse",
        "ImageAspectRatio",
        "ImageMime",
        "ImageOutputOptions",
        "ImageSize",
        "Model",
        "OutputMime",
        "RequestContext",
        "RequestOptions",
        "ResumableUpload",
        "SafetyOptions",
        "ServiceTier",
        "ThinkingLevel",
        "ThinkingOptions",
        "TrafficLogOptions",
        "apiKeyFromMap",
        "api_key_env_name",
        "assertValidGenerationOptions",
        "assertValidRequestOptions",
        "buildCountTokensRequestFromGenerateContentJson",
        "buildGenerateContentRequestJson",
        "canonical_file_name_prefix",
        "decodeCountTokensResponse",
        "decodeGeneratedFiles",
        "decodeUploadedFileName",
        "deleteJson",
        "getBytesBounded",
        "getJson",
        "isCanonicalCachedContentName",
        "isCanonicalFileName",
        "isValidDisplayName",
        "max_generate_request_field_bytes",
        "max_generate_file_uri_bytes",
        "max_generate_request_parts_total",
        "max_generate_text_part_bytes",
        "max_output_tokens",
        "max_stop_sequences",
        "postCountTokensJson",
        "postGenerateContentJson",
        "postJson",
        "postJsonWithoutBody",
        "uploadResumableBytes",
    });

    assertExactPublicDecls("api.Model", api.Model, &.{});
    assertExactPublicDecls("api.GenerateFileData", api.GenerateFileData, &.{});
    assertExactPublicDecls("api.GeneratePart", api.GeneratePart, &.{});
    assertExactPublicDecls("api.GenerateContent", api.GenerateContent, &.{});
    assertExactPublicDecls("api.ServiceTier", api.ServiceTier, &.{
        "fromName",
        "jsonStringify",
    });
    assertExactPublicDecls("api.RequestOptions", api.RequestOptions, &.{
        "hasAny",
    });
    assertExactPublicDecls("api.ImageAspectRatio", api.ImageAspectRatio, &.{
        "fromName",
    });
    assertExactPublicDecls("api.ImageSize", api.ImageSize, &.{
        "fromName",
    });
    assertExactPublicDecls("api.ImageOutputOptions", api.ImageOutputOptions, &.{
        "hasAny",
    });
    assertExactPublicDecls("api.GroundingOptions", api.GroundingOptions, &.{
        "fromName",
        "hasAny",
    });
    assertExactPublicDecls("api.ThinkingLevel", api.ThinkingLevel, &.{
        "fromName",
        "jsonStringify",
    });
    assertExactPublicDecls("api.ThinkingOptions", api.ThinkingOptions, &.{
        "hasAny",
    });
    assertExactPublicDecls("api.GenerationOptions", api.GenerationOptions, &.{
        "appendStopSequence",
        "hasAny",
        "stopSequenceSlice",
    });
    assertExactPublicDecls("api.GenerateContentRequestOptions", api.GenerateContentRequestOptions, &.{});
    assertExactPublicDecls("api.HarmBlockThreshold", api.HarmBlockThreshold, &.{
        "jsonStringify",
    });
    assertExactPublicDecls("api.SafetyOptions", api.SafetyOptions, &.{
        "fromName",
    });
    assertExactPublicDecls("api.CountTokensResult", api.CountTokensResult, &.{});
    assertExactPublicDecls("api.ImageMime", api.ImageMime, &.{
        "apiName",
        "fromName",
        "fromPath",
    });
    assertExactPublicDecls("api.OutputMime", api.OutputMime, &.{
        "extension",
    });
    assertExactPublicDecls("api.GeneratedFile", api.GeneratedFile, &.{
        "deinit",
    });
    assertExactPublicDecls("api.GeneratedFiles", api.GeneratedFiles, &.{
        "deinit",
    });
    assertExactPublicDecls("api.HttpResponse", api.HttpResponse, &.{
        "deinit",
    });
    assertExactPublicDecls("api.ResumableUpload", api.ResumableUpload, &.{});
    assertExactPublicDecls("api.RequestContext", api.RequestContext, &.{});
    assertExactPublicDecls("api.TrafficLogOptions", api.TrafficLogOptions, &.{});

    assertExactPublicDecls("client.ApiFailure", client.ApiFailure, &.{
        "deinit",
    });
    assertExactPublicDecls("client.Client", client.Client, &.{
        "countEditTokens",
        "countGenerateTokens",
        "edit",
        "generate",
        "init",
    });
    assertExactPublicDecls("client.ClientOptions", client.ClientOptions, &.{});
    assertExactPublicDecls("client.CountTokensResult", client.CountTokensResult, &.{});
    assertExactPublicDecls("client.EditRequest", client.EditRequest, &.{});
    assertExactPublicDecls("client.GeneratedImage", client.GeneratedImage, &.{
        "deinit",
    });
    assertExactPublicDecls("client.GenerationOptions", client.GenerationOptions, &.{});
    assertExactPublicDecls("client.GeneratedContentOperationOutcome", client.GeneratedContentOperationOutcome, &.{});
    assertExactPublicDecls("client.GenerationRequest", client.GenerationRequest, &.{});
    assertExactPublicDecls("client.GeneratedContentResponsePolicy", client.GeneratedContentResponsePolicy, &.{});
    assertExactPublicDecls("client.GenerationResult", client.GenerationResult, &.{
        "deinit",
    });
    assertExactPublicDecls("client.GroundingOptions", client.GroundingOptions, &.{});
    assertExactPublicDecls("client.HarmBlockThreshold", client.HarmBlockThreshold, &.{});
    assertExactPublicDecls("client.ImageAspectRatio", client.ImageAspectRatio, &.{});
    assertExactPublicDecls("client.ImageOutputOptions", client.ImageOutputOptions, &.{});
    assertExactPublicDecls("client.ImageSize", client.ImageSize, &.{});
    assertExactPublicDecls("client.InputImageMime", client.InputImageMime, &.{});
    assertExactPublicDecls("client.Outcome(CountTokensResult)", client.Outcome(client.CountTokensResult), &.{});
    assertExactPublicDecls("client.Outcome(GenerationResult)", client.Outcome(client.GenerationResult), &.{});
    assertExactPublicDecls("client.OutputMime", client.OutputMime, &.{});
    assertExactPublicDecls("client.Reference", client.Reference, &.{});
    assertExactPublicDecls("client.ReferenceRole", client.ReferenceRole, &.{});
    assertExactPublicDecls("client.RequestOptions", client.RequestOptions, &.{});
    assertExactPublicDecls("client.SafetyOptions", client.SafetyOptions, &.{});
    assertExactPublicDecls("client.ServiceTier", client.ServiceTier, &.{});
    assertExactPublicDecls("client.ThinkingLevel", client.ThinkingLevel, &.{});
    assertExactPublicDecls("client.ThinkingOptions", client.ThinkingOptions, &.{});
    assertExactPublicDecls("client.UploadedImage", client.UploadedImage, &.{});

    assertExactPublicDecls("edit.ReferenceRole", edit.ReferenceRole, &.{
        "fromName",
    });
    assertExactPublicDecls("edit.UploadedImage", edit.UploadedImage, &.{});
    assertExactPublicDecls("edit.Reference", edit.Reference, &.{});
    assertExactPublicDecls("edit.EditRequest", edit.EditRequest, &.{});

    assertExactPublicDecls("files.FileUpload", files.FileUpload, &.{});
    assertExactPublicDecls("files.File", files.File, &.{
        "deinit",
    });
    assertExactPublicDecls("files.FileListPage", files.FileListPage, &.{
        "deinit",
    });

    assertExactPublicDecls("batch.SubmitRequest", batch.SubmitRequest, &.{});
    assertExactPublicDecls("batch.DownloadInfo", batch.DownloadInfo, &.{
        "deinit",
    });
    assertExactPublicDecls("batch.OutputRecord", batch.OutputRecord, &.{
        "deinit",
    });
    assertExactPublicDecls("batch.OutputLineIterator", batch.OutputLineIterator, &.{
        "next",
    });
    assertExactPublicDecls("batch.ListPage", batch.ListPage, &.{
        "deinit",
    });
}

test "internal module APIs match exact allowlists" {}
