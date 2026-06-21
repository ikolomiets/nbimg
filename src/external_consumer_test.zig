const std = @import("std");
const nbimg = @import("nbimg");

comptime {
    if (@hasDecl(nbimg, "RequestContext")) {
        @compileError("public package exposes internal RequestContext");
    }
    if (@hasDecl(nbimg, "HttpResponse")) {
        @compileError("public package exposes raw HttpResponse");
    }
    if (@hasDecl(nbimg, "client")) {
        @compileError("public package exposes the client implementation module");
    }
}

test "dependency consumer compiles against the typed token-count API" {
    const client = try nbimg.Client.init(std.testing.allocator, std.testing.io, .{
        .api_key = "borrowed-key",
    });
    const request = nbimg.GenerationRequest{
        .prompt = "Create a cinematic product image",
        .output_options = .{
            .aspect_ratio = .r16_9,
            .image_size = .k2,
        },
        .generation_options = .{
            .temperature = 0.7,
            .stop_sequences = &.{"END"},
        },
    };
    const outcome: nbimg.Outcome(nbimg.CountTokensResult) = .{
        .success = .{ .total_tokens = 42 },
    };

    try std.testing.expectEqualStrings("borrowed-key", client.api_key);
    try std.testing.expectEqualStrings(
        "Create a cinematic product image",
        request.prompt,
    );
    switch (outcome) {
        .success => |result| try std.testing.expectEqual(@as(u64, 42), result.total_tokens),
        .api_failure => |*failure| failure.deinit(std.testing.allocator),
    }
}
