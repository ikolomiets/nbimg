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
    assertExactPublicDecls("root", root, &.{
        "api",
        "batch",
        "cli",
        "edit",
        "files",
        "gen",
    });
}

test "package API matches exact allowlist" {}
