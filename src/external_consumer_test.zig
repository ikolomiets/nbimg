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
    if (@hasDecl(nbimg, "edit")) {
        @compileError("public package exposes the legacy edit module");
    }
    if (@hasDecl(nbimg, "files")) {
        @compileError("public package exposes the legacy Files module");
    }
}

test "dependency consumer compiles against typed generation edit Files and Batch preparation APIs" {
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
    const edit = nbimg.Client.edit;
    const count_edit_tokens = nbimg.Client.countEditTokens;
    const prepare_generation_batch_entry = nbimg.Client.prepareGenerationBatchEntry;
    const prepare_edit_batch_entry = nbimg.Client.prepareEditBatchEntry;
    const upload_file = nbimg.Client.uploadFile;
    const get_file = nbimg.Client.getFile;
    const list_files_page = nbimg.Client.listFilesPage;
    const delete_file = nbimg.Client.deleteFile;
    const upload_batch_input = nbimg.Client.uploadBatchInput;
    const create_batch = nbimg.Client.createBatch;
    const get_batch = nbimg.Client.getBatch;
    const cancel_batch = nbimg.Client.cancelBatch;
    const list_batches_page = nbimg.Client.listBatchesPage;
    _ = generate;
    _ = edit;
    _ = count_edit_tokens;
    _ = prepare_generation_batch_entry;
    _ = prepare_edit_batch_entry;
    _ = upload_file;
    _ = get_file;
    _ = list_files_page;
    _ = delete_file;
    _ = upload_batch_input;
    _ = create_batch;
    _ = get_batch;
    _ = cancel_batch;
    _ = list_batches_page;

    const edit_request = nbimg.EditRequest{
        .prompt = "Apply the product style",
        .base = .{
            .name = "files/base",
            .mime = .jpeg,
        },
        .base_role = .object,
        .references = &.{.{
            .role = .style,
            .label = "STYLE_A",
            .image = .{
                .name = "files/style",
                .mime = .webp,
            },
        }},
        .preserves = &.{"product geometry"},
        .do_nots = &.{"change the logo"},
    };
    const upload = nbimg.FileUpload{
        .mime = .png,
        .bytes = "image bytes",
        .display_name = "sample",
    };
    var file = nbimg.File{
        .name = try std.testing.allocator.dupe(u8, "files/sample"),
        .mime_type = try std.testing.allocator.dupe(u8, "application/jsonl"),
        .size_bytes = 11,
        .state = .active,
        .source = .uploaded,
        .processing_error = .{
            .code = 3,
            .message = try std.testing.allocator.dupe(u8, "processing"),
            .details_json = try std.testing.allocator.dupe(u8, "[]"),
        },
    };
    defer file.deinit(std.testing.allocator);
    var page = nbimg.FileListPage{
        .files = try std.testing.allocator.alloc(nbimg.File, 0),
    };
    defer page.deinit(std.testing.allocator);
    var unknown_state = nbimg.FileState{
        .unknown = try std.testing.allocator.dupe(u8, "FUTURE"),
    };
    defer unknown_state.deinit(std.testing.allocator);
    var unknown_source = nbimg.FileSource{
        .unknown = try std.testing.allocator.dupe(u8, "IMPORTED"),
    };
    defer unknown_source.deinit(std.testing.allocator);
    var prepared_entry = nbimg.PreparedBatchEntry{
        .key = try std.testing.allocator.dupe(u8, "hero-001"),
        .jsonl_record = try std.testing.allocator.dupe(
            u8,
            "{\"key\":\"hero-001\",\"request\":{}}",
        ),
        .total_tokens = 42,
    };
    defer prepared_entry.deinit(std.testing.allocator);
    const batch_summary: nbimg.BatchInputSummary = try nbimg.validateBatchInput(
        prepared_entry.jsonl_record,
    );
    const batch_upload = nbimg.BatchInputUpload{
        .bytes = prepared_entry.jsonl_record,
        .display_name = "requests.jsonl",
    };
    const batch_create = nbimg.BatchCreateRequest{
        .file_name = "files/batch-input",
        .display_name = "requests.jsonl",
        .priority = -1,
    };
    var batch_job = nbimg.BatchJob{
        .name = try std.testing.allocator.dupe(u8, "batches/sample"),
        .model = try std.testing.allocator.dupe(u8, "models/gemini-3.1-flash-image"),
        .display_name = try std.testing.allocator.dupe(u8, "requests.jsonl"),
        .input_file_name = try std.testing.allocator.dupe(u8, "files/batch-input"),
        .output_file_name = try std.testing.allocator.dupe(u8, "files/batch-output"),
        .state = .succeeded,
        .stats = .{
            .request_count = 1,
            .successful_request_count = 1,
        },
        .priority = -1,
        .done = true,
        .remote_error = .{
            .code = 1,
            .message = try std.testing.allocator.dupe(u8, "cancelled"),
        },
    };
    defer batch_job.deinit(std.testing.allocator);
    var batch_page = nbimg.BatchListPage{
        .jobs = try std.testing.allocator.alloc(nbimg.BatchJob, 0),
        .next_page_token = try std.testing.allocator.dupe(u8, "next"),
    };
    defer batch_page.deinit(std.testing.allocator);
    var unknown_batch_state = nbimg.BatchState{
        .unknown = try std.testing.allocator.dupe(u8, "BATCH_STATE_PAUSED"),
    };
    defer unknown_batch_state.deinit(std.testing.allocator);
    const batch_validation_error: nbimg.BatchValidationError = error.EmptyBatchKey;

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
    try std.testing.expectEqualStrings("files/base", edit_request.base.name);
    try std.testing.expectEqual(nbimg.InputImageMime.png, upload.mime);
    try std.testing.expectEqualStrings("application/jsonl", file.mime_type.?);
    try std.testing.expect(file.state == .active);
    try std.testing.expect(file.source == .uploaded);
    try std.testing.expectEqual(@as(?i64, 3), file.processing_error.?.code);
    try std.testing.expectEqual(@as(usize, 0), page.files.len);
    switch (unknown_state) {
        .unknown => {},
        else => return error.ExpectedUnknownState,
    }
    switch (unknown_source) {
        .unknown => {},
        else => return error.ExpectedUnknownSource,
    }
    try std.testing.expectEqual(@as(usize, 64 * 1024 * 1024), nbimg.max_file_upload_bytes);
    try std.testing.expectEqual(@as(usize, 13), nbimg.max_edit_references);
    try std.testing.expectEqual(@as(usize, 4), nbimg.max_edit_character_images);
    try std.testing.expectEqual(@as(usize, 10), nbimg.max_edit_object_images);
    try std.testing.expectEqual(@as(usize, 64), nbimg.max_edit_reference_label_bytes);
    try std.testing.expectEqual(@as(usize, 16), nbimg.max_edit_preserve_constraints);
    try std.testing.expectEqual(@as(usize, 16), nbimg.max_edit_do_not_constraints);
    try std.testing.expectEqual(@as(usize, 1), batch_summary.entry_count);
    try std.testing.expectEqual(prepared_entry.jsonl_record.len, batch_summary.byte_count);
    try std.testing.expectEqualStrings(prepared_entry.jsonl_record, batch_upload.bytes);
    try std.testing.expectEqualStrings("files/batch-input", batch_create.file_name);
    try std.testing.expectEqualStrings("batches/sample", batch_job.name);
    try std.testing.expectEqualStrings("models/gemini-3.1-flash-image", batch_job.model.?);
    try std.testing.expect(batch_job.state == .succeeded);
    try std.testing.expectEqual(@as(?u64, 1), batch_job.stats.request_count);
    try std.testing.expectEqual(@as(?i64, -1), batch_job.priority);
    try std.testing.expectEqual(@as(usize, 0), batch_page.jobs.len);
    switch (unknown_batch_state) {
        .unknown => {},
        else => return error.ExpectedUnknownBatchState,
    }
    try std.testing.expectEqual(error.EmptyBatchKey, batch_validation_error);
    try std.testing.expectEqual(@as(usize, 5 * 1024 * 1024), nbimg.max_batch_entry_bytes);
    try std.testing.expectEqual(@as(usize, 100), nbimg.max_batch_entries);
    try std.testing.expectEqual(@as(usize, 512 * 1024 * 1024), nbimg.max_batch_input_bytes);
}
