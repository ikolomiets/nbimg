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
        "Outcome",
        "OutputMime",
        "RequestOptions",
        "SafetyOptions",
        "ServiceTier",
        "ThinkingLevel",
        "ThinkingOptions",
        "api",
        "batch",
        "edit",
        "files",
        "gen",
    });

    assertExactPublicDecls("root.ApiFailure", root.ApiFailure, &.{
        "deinit",
    });
    assertExactPublicDecls("root.Client", root.Client, &.{
        "countGenerateTokens",
        "generate",
        "init",
    });
    assertExactPublicDecls("root.ClientOptions", root.ClientOptions, &.{});
    assertExactPublicDecls("root.CountTokensResult", root.CountTokensResult, &.{});
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
    assertExactPublicDecls("root.Outcome(CountTokensResult)", root.Outcome(root.CountTokensResult), &.{});
    assertExactPublicDecls("root.Outcome(GenerationResult)", root.Outcome(root.GenerationResult), &.{});
    assertExactPublicDecls("root.OutputMime", root.OutputMime, &.{});
    assertExactPublicDecls("root.RequestOptions", root.RequestOptions, &.{});
    assertExactPublicDecls("root.SafetyOptions", root.SafetyOptions, &.{});
    assertExactPublicDecls("root.ServiceTier", root.ServiceTier, &.{});
    assertExactPublicDecls("root.ThinkingLevel", root.ThinkingLevel, &.{});
    assertExactPublicDecls("root.ThinkingOptions", root.ThinkingOptions, &.{});
}

test "package API matches exact allowlist" {}
