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
    if (@hasDecl(nbimg, "gen")) {
        @compileError("public package exposes the legacy generation module");
    }
}

test "dependency consumer compiles against typed generation APIs" {
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
    var generation_result = nbimg.GenerationResult{
        .response_id = try std.testing.allocator.dupe(u8, "response"),
        .images = try std.testing.allocator.alloc(nbimg.GeneratedImage, 1),
        .reported_service_tier = .standard,
    };
    generation_result.images[0] = .{
        .candidate_position = 0,
        .part_position = 1,
        .mime = .png,
        .bytes = try std.testing.allocator.dupe(u8, "image"),
    };
    defer generation_result.deinit(std.testing.allocator);
    const generate = nbimg.Client.generate;
    _ = generate;

    try std.testing.expectEqualStrings("borrowed-key", client.api_key);
    try std.testing.expectEqualStrings(
        "Create a cinematic product image",
        request.prompt,
    );
    switch (outcome) {
        .success => |result| try std.testing.expectEqual(@as(u64, 42), result.total_tokens),
        .api_failure => |*failure| failure.deinit(std.testing.allocator),
    }
    try std.testing.expectEqual(nbimg.OutputMime.png, generation_result.images[0].mime);
}
