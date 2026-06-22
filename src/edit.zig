//! Gemini native image editing request handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");

const max_total_images = 14;
pub const max_references = max_total_images - 1;
pub const max_character_references = 4;
pub const max_object_references = 10;
pub const max_label_bytes = 64;
pub const max_preserve_constraints = 16;
pub const max_do_not_constraints = 16;

const max_edit_content_parts = 2 + max_references * 2 + 1;
const max_edit_total_parts_with_system = max_edit_content_parts + 1;
const file_uri_prefix = "https://generativelanguage.googleapis.com/v1beta/";
const live_base_name = "files/tjtj5me9i96c";
const live_prompt = "change visual style to Broadway musical";

comptime {
    assert(max_edit_content_parts == 29);
    assert(max_edit_total_parts_with_system == 30);
    assert(max_edit_total_parts_with_system <= api.max_generate_request_parts_total);
}

pub const ReferenceRole = enum {
    scene,
    character,
    object,
    style,
    pose,
    composition,
    background,
    texture,
    image,

    /// Parses a CLI image-reference role name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?ReferenceRole {
        if (std.mem.eql(u8, name, "scene")) return .scene;
        if (std.mem.eql(u8, name, "character")) return .character;
        if (std.mem.eql(u8, name, "object")) return .object;
        if (std.mem.eql(u8, name, "style")) return .style;
        if (std.mem.eql(u8, name, "pose")) return .pose;
        if (std.mem.eql(u8, name, "composition")) return .composition;
        if (std.mem.eql(u8, name, "background")) return .background;
        if (std.mem.eql(u8, name, "texture")) return .texture;
        if (std.mem.eql(u8, name, "image")) return .image;
        return null;
    }
};

/// Identifies a borrowed uploaded image for an edit request.
///
/// - `name` remains caller-owned and must outlive request construction.
/// - The value allocates nothing and mutates no state.
pub const UploadedImage = struct {
    name: []const u8,
    mime: api.ImageMime,
};

/// Associates a borrowed uploaded image with an edit role and label.
///
/// - `label` and nested image data remain caller-owned through request construction.
/// - The value allocates nothing and mutates no state.
pub const Reference = struct {
    role: ReferenceRole,
    label: []const u8,
    image: UploadedImage,
};

/// Describes a complete image-edit request using borrowed prompts and references.
///
/// - All slices and nested values remain caller-owned through request construction or submission.
/// - The value allocates nothing and mutates no state.
pub const EditRequest = struct {
    prompt: []const u8,
    output_options: api.ImageOutputOptions = .{},
    grounding_options: api.GroundingOptions = .{},
    thinking_options: api.ThinkingOptions = .{},
    safety_options: ?api.SafetyOptions = null,
    generation_options: api.GenerationOptions = .{},
    request_options: api.RequestOptions = .{},
    base: UploadedImage,
    base_role: ReferenceRole = .scene,
    references: []const Reference = &.{},
    preserves: []const []const u8 = &.{},
    do_nots: []const []const u8 = &.{},
};

pub const ValidationError = error{
    EmptyPrompt,
    PromptTooLong,
    InvalidBaseFileName,
    InvalidReferenceFileName,
    FileUriTooLong,
    InvalidReferenceLabel,
    ReservedReferenceLabel,
    DuplicateReferenceLabel,
    TooManyReferences,
    TooManyCharacterImages,
    TooManyObjectImages,
    TooManyPreserveConstraints,
    TooManyDoNotConstraints,
    EmptyPreserveConstraint,
    PreserveConstraintTooLong,
    EmptyDoNotConstraint,
    DoNotConstraintTooLong,
    EditTaskTooLong,
    RequestTooLong,
};

/// Validates edit-specific fields and exact serialized request bounds.
pub fn validateRequest(request: EditRequest) ValidationError!void {
    if (request.prompt.len == 0) return error.EmptyPrompt;
    if (request.prompt.len > api.max_generate_text_part_bytes) return error.PromptTooLong;
    if (!api.isCanonicalFileName(request.base.name)) return error.InvalidBaseFileName;
    if (fileUriLength(request.base.name) > api.max_generate_file_uri_bytes) {
        return error.FileUriTooLong;
    }
    if (request.references.len > max_references) return error.TooManyReferences;
    if (request.preserves.len > max_preserve_constraints) {
        return error.TooManyPreserveConstraints;
    }
    if (request.do_nots.len > max_do_not_constraints) {
        return error.TooManyDoNotConstraints;
    }

    var character_count: usize = if (request.base_role == .character) 1 else 0;
    var object_count: usize = if (request.base_role == .object) 1 else 0;
    var field_bytes: usize = baseAnchorLength(request.base_role);
    field_bytes +|= request.base.mime.apiName().len;
    field_bytes +|= fileUriLength(request.base.name);

    for (request.references, 0..) |reference, index| {
        if (!api.isCanonicalFileName(reference.image.name)) {
            return error.InvalidReferenceFileName;
        }
        if (fileUriLength(reference.image.name) > api.max_generate_file_uri_bytes) {
            return error.FileUriTooLong;
        }
        if (!isValidLabel(reference.label)) return error.InvalidReferenceLabel;
        if (std.mem.eql(u8, reference.label, "BASE_IMAGE")) {
            return error.ReservedReferenceLabel;
        }
        for (request.references[0..index]) |previous| {
            if (std.mem.eql(u8, reference.label, previous.label)) {
                return error.DuplicateReferenceLabel;
            }
        }
        if (reference.role == .character) character_count += 1;
        if (reference.role == .object) object_count += 1;

        field_bytes +|= referenceAnchorLength(reference);
        field_bytes +|= reference.image.mime.apiName().len;
        field_bytes +|= fileUriLength(reference.image.name);
    }

    if (character_count > max_character_references) {
        return error.TooManyCharacterImages;
    }
    if (object_count > max_object_references) return error.TooManyObjectImages;

    var edit_task_bytes: usize = editTaskPrefix().len +| request.prompt.len;
    if (request.preserves.len > 0) edit_task_bytes +|= preserveSectionPrefix().len;
    for (request.preserves) |preserve| {
        if (preserve.len == 0) return error.EmptyPreserveConstraint;
        if (preserve.len > api.max_generate_text_part_bytes) {
            return error.PreserveConstraintTooLong;
        }
        edit_task_bytes +|= "\n- ".len;
        edit_task_bytes +|= preserve.len;
    }
    if (request.do_nots.len > 0) edit_task_bytes +|= doNotSectionPrefix().len;
    for (request.do_nots) |do_not| {
        if (do_not.len == 0) return error.EmptyDoNotConstraint;
        if (do_not.len > api.max_generate_text_part_bytes) {
            return error.DoNotConstraintTooLong;
        }
        edit_task_bytes +|= "\n- ".len;
        edit_task_bytes +|= do_not.len;
    }
    if (edit_task_bytes > api.max_generate_text_part_bytes) {
        return error.EditTaskTooLong;
    }
    field_bytes +|= edit_task_bytes;

    if (request.request_options.system_instruction) |value| field_bytes +|= value.len;
    if (request.request_options.cached_content) |value| field_bytes +|= value.len;
    for (request.generation_options.stopSequenceSlice()) |value| field_bytes +|= value.len;
    if (field_bytes > api.max_generate_request_field_bytes) return error.RequestTooLong;
}

/// Builds an owned Gemini generate-content JSON request for an image edit.
///
/// - Borrows all request slices for the call; the returned JSON is owned by `gpa`.
/// - Returns allocation or serialization errors and mutates no input or global state.
pub fn buildGenerateRequest(gpa: std.mem.Allocator, request: EditRequest) ![]u8 {
    assertValidEditRequest(request);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const part_count = 2 + request.references.len * 2 + 1;
    const parts = try arena.alloc(api.GeneratePart, part_count);
    var part_index: usize = 0;

    parts[part_index] = .{ .text = try buildBaseAnchor(arena, request.base_role) };
    part_index += 1;
    parts[part_index] = .{ .file_data = try buildFileData(arena, request.base) };
    part_index += 1;

    for (request.references) |reference| {
        parts[part_index] = .{ .text = try buildReferenceAnchor(arena, reference) };
        part_index += 1;
        parts[part_index] = .{ .file_data = try buildFileData(arena, reference.image) };
        part_index += 1;
    }

    parts[part_index] = .{ .text = try buildEditTask(arena, request) };
    part_index += 1;
    assert(part_index == parts.len);

    const contents = [_]api.GenerateContent{.{ .parts = parts }};
    return api.buildGenerateContentRequestJson(gpa, &contents, .{
        .output_options = request.output_options,
        .grounding_options = request.grounding_options,
        .thinking_options = request.thinking_options,
        .safety_options = request.safety_options,
        .generation_options = request.generation_options,
        .request_options = request.request_options,
    });
}

/// Reports whether a reference label follows the bounded uppercase identifier format.
///
/// - Borrows `label`, allocates nothing, returns no errors, and mutates no state.
pub fn isValidLabel(label: []const u8) bool {
    if (label.len == 0) return false;
    if (label.len > max_label_bytes) return false;
    if (!isAsciiUpper(label[0])) return false;

    for (label) |byte| {
        if (isAsciiUpper(byte)) continue;
        if (byte >= '0' and byte <= '9') continue;
        if (byte == '_') continue;
        return false;
    }

    return true;
}

fn buildFileUri(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
    assert(api.isCanonicalFileName(name));
    return std.fmt.allocPrint(gpa, "{s}{s}", .{ file_uri_prefix, name });
}

fn buildBaseAnchor(gpa: std.mem.Allocator, base_role: ReferenceRole) ![]u8 {
    return switch (base_role) {
        .scene => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseSceneAnchor()},
        ),
        .character => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseCharacterAnchor()},
        ),
        .object => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseObjectAnchor()},
        ),
        .style => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseStyleAnchor()},
        ),
        .pose => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{basePoseAnchor()},
        ),
        .composition => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseCompositionAnchor()},
        ),
        .background => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseBackgroundAnchor()},
        ),
        .texture => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseTextureAnchor()},
        ),
        .image => std.fmt.allocPrint(
            gpa,
            "REFERENCE MANIFEST\n\nBASE_IMAGE:\n{s}",
            .{baseImageAnchor()},
        ),
    };
}

fn buildReferenceAnchor(gpa: std.mem.Allocator, reference: Reference) ![]u8 {
    assert(isValidLabel(reference.label));

    return std.fmt.allocPrint(
        gpa,
        "{s}:\n{s}",
        .{ reference.label, referenceRoleAnchor(reference.role) },
    );
}

fn buildFileData(gpa: std.mem.Allocator, image: UploadedImage) !api.GenerateFileData {
    assert(api.isCanonicalFileName(image.name));

    return api.GenerateFileData{
        .mime_type = image.mime.apiName(),
        .file_uri = try buildFileUri(gpa, image.name),
    };
}

fn buildEditTask(gpa: std.mem.Allocator, request: EditRequest) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll(editTaskPrefix());
    try output.writer.writeAll(request.prompt);

    if (request.preserves.len > 0) {
        try output.writer.writeAll(preserveSectionPrefix());

        for (request.preserves) |preserve| {
            assert(preserve.len > 0);
            try output.writer.writeAll("\n- ");
            try output.writer.writeAll(preserve);
        }
    }

    if (request.do_nots.len > 0) {
        try output.writer.writeAll(doNotSectionPrefix());

        for (request.do_nots) |do_not| {
            assert(do_not.len > 0);
            try output.writer.writeAll("\n- ");
            try output.writer.writeAll(do_not);
        }
    }

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn assertValidEditRequest(request: EditRequest) void {
    validateRequest(request) catch unreachable;
    assert(request.prompt.len > 0);
    assert(request.prompt.len <= api.max_generate_text_part_bytes);
    assert(api.isCanonicalFileName(request.base.name));
    assert(request.references.len <= max_references);

    var character_count: usize = if (request.base_role == .character) 1 else 0;
    var object_count: usize = if (request.base_role == .object) 1 else 0;

    for (request.references) |reference| {
        assert(api.isCanonicalFileName(reference.image.name));
        assert(isValidLabel(reference.label));
        if (reference.role == .character) character_count += 1;
        if (reference.role == .object) object_count += 1;
    }

    assert(character_count <= max_character_references);
    assert(object_count <= max_object_references);

    assert(request.preserves.len <= max_preserve_constraints);
    for (request.preserves) |preserve| {
        assert(preserve.len > 0);
        assert(preserve.len <= api.max_generate_text_part_bytes);
    }
    assert(request.do_nots.len <= max_do_not_constraints);
    for (request.do_nots) |do_not| {
        assert(do_not.len > 0);
        assert(do_not.len <= api.max_generate_text_part_bytes);
    }
    api.assertValidGenerationOptions(request.generation_options);
    api.assertValidRequestOptions(request.request_options);
}

fn fileUriLength(name: []const u8) usize {
    return file_uri_prefix.len +| name.len;
}

fn baseAnchorLength(role: ReferenceRole) usize {
    return "REFERENCE MANIFEST\n\nBASE_IMAGE:\n".len + switch (role) {
        .scene => baseSceneAnchor().len,
        .character => baseCharacterAnchor().len,
        .object => baseObjectAnchor().len,
        .style => baseStyleAnchor().len,
        .pose => basePoseAnchor().len,
        .composition => baseCompositionAnchor().len,
        .background => baseBackgroundAnchor().len,
        .texture => baseTextureAnchor().len,
        .image => baseImageAnchor().len,
    };
}

fn referenceAnchorLength(reference: Reference) usize {
    return reference.label.len +| ":\n".len +| referenceRoleAnchor(reference.role).len;
}

fn editTaskPrefix() []const u8 {
    return "EDIT TASK:\nApply this edit to BASE_IMAGE using the labeled references above:\n";
}

fn preserveSectionPrefix() []const u8 {
    return "\n\nPRESERVE FROM BASE_IMAGE:";
}

fn doNotSectionPrefix() []const u8 {
    return "\n\nDO NOT:";
}

fn baseSceneAnchor() []const u8 {
    return "The next image is the image to edit. Preserve its composition, camera angle, framing, subject placement, lighting direction, and scene geometry unless the edit task explicitly says otherwise.";
}

fn baseCharacterAnchor() []const u8 {
    return "The next image is the image to edit and the primary character identity reference. Preserve the visible person's facial identity, apparent age, face shape, hairstyle, hair color, skin tone, body proportions, and recognizable presence unless the edit task explicitly says otherwise.";
}

fn baseObjectAnchor() []const u8 {
    return "The next image is the image to edit and the primary object/product reference. Preserve the visible object's geometry, proportions, material, color, texture, markings, logo placement, text placement, and distinctive details unless the edit task explicitly says otherwise.";
}

fn baseStyleAnchor() []const u8 {
    return "The next image is the image to edit and the primary style reference. Preserve its visible content as BASE_IMAGE while keeping its color palette, contrast, lighting mood, line weight, surface texture, grain, and rendering technique unless the edit task explicitly says otherwise.";
}

fn basePoseAnchor() []const u8 {
    return "The next image is the image to edit and the primary pose reference. Preserve body position, gesture, posture, camera framing, and subject placement unless the edit task explicitly says otherwise.";
}

fn baseCompositionAnchor() []const u8 {
    return "The next image is the image to edit and the primary composition reference. Preserve layout, subject placement, negative space, camera angle, framing, and scene geometry unless the edit task explicitly says otherwise.";
}

fn baseBackgroundAnchor() []const u8 {
    return "The next image is the image to edit and the primary background reference. Preserve environment, setting, background structure, and scene context unless the edit task explicitly says otherwise.";
}

fn baseTextureAnchor() []const u8 {
    return "The next image is the image to edit and the primary texture reference. Preserve material feel, surface texture, pattern, and finish unless the edit task explicitly says otherwise.";
}

fn baseImageAnchor() []const u8 {
    return "The next image is the image to edit and a general visual reference. Preserve only the details needed by the edit task, and keep BASE_IMAGE as the target image unless the edit task explicitly says otherwise.";
}

fn referenceRoleAnchor(role: ReferenceRole) []const u8 {
    return switch (role) {
        .scene => "The next image is a scene reference. Use it only for environment, composition, camera angle, framing, subject placement, lighting direction, and scene geometry requested by the edit task. Do not copy unrelated people or objects.",
        .character => "The next image is an identity reference. Use it only for facial identity, apparent age, face shape, hairstyle, hair color, skin tone, body proportions, and recognizable presence. Do not copy its background, lighting, clothing, pose, or camera angle unless explicitly requested.",
        .object => "The next image is an object/product reference. Preserve its geometry, proportions, material, color, texture, visible markings, logo placement, text placement, and distinctive details. Do not copy its background, lighting, or surrounding props.",
        .style => "The next image is a style reference. Use it only for color palette, contrast, lighting mood, line weight, surface texture, grain, and rendering technique. Do not copy its subject, layout, objects, or background.",
        .pose => "The next image is a pose reference. Use it only for body position, gesture, and posture. Do not copy identity, clothing, background, lighting, camera angle, or style.",
        .composition => "The next image is a composition reference. Use it only for layout, subject placement, negative space, camera angle, and framing. Do not copy people, objects, colors, or background details.",
        .background => "The next image is a background reference. Use it only for environment, setting, and background details requested by the edit task. Do not copy people, foreground subjects, or unrelated objects.",
        .texture => "The next image is a texture reference. Use it only for material feel, surface texture, pattern, and finish. Do not copy object shape, layout, lighting, or background.",
        .image => "The next image is a general visual reference. Use only the details explicitly requested by the edit task. Do not copy unrelated subjects, background, lighting, composition, or style.",
    };
}

fn isAsciiUpper(byte: u8) bool {
    return byte >= 'A' and byte <= 'Z';
}

test "buildGenerateRequest builds edit request with base file data" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    const base_anchor = std.mem.indexOf(u8, request, "BASE_IMAGE").?;
    const file_part = std.mem.indexOf(u8, request, "\"file_data\"").?;
    const edit_task = std.mem.indexOf(u8, request, "EDIT TASK").?;

    try std.testing.expect(base_anchor < file_part);
    try std.testing.expect(file_part < edit_task);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"mime_type\":\"image/jpeg\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"file_uri\":\"https://generativelanguage.googleapis.com/v1beta/files/tjtj5me9i96c\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseModalities\":[\"TEXT\",\"IMAGE\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseFormat\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"imageConfig\"") == null);
    try expectNoSafetySettings(request);
    try std.testing.expect(std.mem.indexOf(u8, request, "PRESERVE FROM BASE_IMAGE") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "DO NOT") == null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateRequest includes edit image output options" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .output_options = .{
            .aspect_ratio = .r4_5,
            .image_size = .k4,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseFormat\":{\"image\":{\"aspectRatio\":\"ASPECT_RATIO_FOUR_BY_FIVE\",\"imageSize\":\"IMAGE_SIZE_FOUR_K\"}}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseModalities\":[\"TEXT\",\"IMAGE\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"imageConfig\"") == null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateRequest includes partial edit image output options" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .output_options = .{
            .image_size = .k1,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"imageSize\":\"IMAGE_SIZE_ONE_K\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"aspectRatio\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"imageConfig\"") == null);
}

test "buildGenerateRequest includes edit web grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .grounding_options = .{
            .web = true,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseModalities\":[\"TEXT\",\"IMAGE\"]") != null);
    try expectNoSafetySettings(request);
}

test "buildGenerateRequest includes edit image grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .grounding_options = .{
            .image = true,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"imageSearch\":{}}}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"webSearch\"") == null);
}

test "buildGenerateRequest includes edit combined grounding tool" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .grounding_options = .{
            .web = true,
            .image = true,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{\"searchTypes\":{\"webSearch\":{},\"imageSearch\":{}}}}]") != null);
}

test "buildGenerateRequest includes edit thinking config" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .thinking_options = .{
            .level = .minimal,
            .include_thoughts = true,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"thinkingConfig\":{\"thinkingLevel\":\"minimal\",\"includeThoughts\":true}") != null);
}

test "buildGenerateRequest includes edit advanced generation options" {
    const gpa = std.testing.allocator;
    var generation_options = api.GenerationOptions{
        .max_output_tokens = 4096,
        .temperature = 0.7,
        .top_p = 0.95,
        .seed = -42,
        .presence_penalty = -1.5,
        .frequency_penalty = 1.25,
        .response_logprobs = true,
        .logprobs = 5,
    };
    generation_options.appendStopSequence("END");
    generation_options.appendStopSequence("STOP");

    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .generation_options = generation_options,
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"maxOutputTokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"temperature\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"topP\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"seed\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"presencePenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"frequencyPenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"responseLogprobs\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"logprobs\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"stopSequences\":[\"END\",\"STOP\"]") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateRequest applies edit safety threshold to all categories" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .safety_options = api.SafetyOptions{
            .threshold = .block_low_and_above,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"safetySettings\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"threshold\":\"BLOCK_LOW_AND_ABOVE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"threshold\":\"BLOCK_LOW_AND_ABOVE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_SEXUALLY_EXPLICIT\",\"threshold\":\"BLOCK_LOW_AND_ABOVE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_DANGEROUS_CONTENT\",\"threshold\":\"BLOCK_LOW_AND_ABOVE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"threshold\":\"BLOCK_NONE\"") == null);
}

test "buildGenerateRequest emits edit block none safety settings when requested" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .safety_options = api.SafetyOptions{
            .threshold = .block_none,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"safetySettings\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"threshold\":\"BLOCK_NONE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"threshold\":\"BLOCK_NONE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_SEXUALLY_EXPLICIT\",\"threshold\":\"BLOCK_NONE\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "{\"category\":\"HARM_CATEGORY_DANGEROUS_CONTENT\",\"threshold\":\"BLOCK_NONE\"}") != null);
}

test "buildGenerateRequest includes edit request-level controls" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .request_options = .{
            .system_instruction = "Preserve the subject identity.",
            .cached_content = "cachedContents/edit-context",
            .service_tier = .flex,
            .store = true,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"systemInstruction\":{\"parts\":[{\"text\":\"Preserve the subject identity.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"cachedContent\":\"cachedContents/edit-context\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"serviceTier\":\"flex\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"store\":true") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateRequest keeps max-reference edit within generateContent part limit with system" {
    const gpa = std.testing.allocator;
    const labels = [_][]const u8{
        "STYLE_A",
        "STYLE_B",
        "STYLE_C",
        "STYLE_D",
        "STYLE_E",
        "STYLE_F",
        "STYLE_G",
        "STYLE_H",
        "STYLE_I",
        "STYLE_J",
        "STYLE_K",
        "STYLE_L",
        "STYLE_M",
    };
    const names = [_][]const u8{
        "files/reference-a",
        "files/reference-b",
        "files/reference-c",
        "files/reference-d",
        "files/reference-e",
        "files/reference-f",
        "files/reference-g",
        "files/reference-h",
        "files/reference-i",
        "files/reference-j",
        "files/reference-k",
        "files/reference-l",
        "files/reference-m",
    };
    var references: [max_references]Reference = undefined;
    for (&references, 0..) |*reference, index| {
        reference.* = .{
            .role = .style,
            .label = labels[index],
            .image = .{
                .name = names[index],
                .mime = .jpeg,
            },
        };
    }

    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .request_options = .{
            .system_instruction = "Preserve the subject identity.",
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
        .references = &references,
    });
    defer gpa.free(request);

    try expectGenerateRequestPartCounts(gpa, request, 29, 1);
}

fn expectNoSafetySettings(request_json: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"safetySettings\"") == null);
}

fn expectGenerateRequestPartCounts(
    gpa: std.mem.Allocator,
    request_json: []const u8,
    expected_content_parts: usize,
    expected_system_parts: usize,
) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request_json, .{});
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |object| object,
        else => return error.InvalidGenerateRequestJson,
    };
    const contents = switch (root.get("contents") orelse return error.MissingContents) {
        .array => |array| array.items,
        else => return error.InvalidContents,
    };
    try std.testing.expectEqual(@as(usize, 1), contents.len);

    const content = switch (contents[0]) {
        .object => |object| object,
        else => return error.InvalidContent,
    };
    const content_parts = switch (content.get("parts") orelse return error.MissingContentParts) {
        .array => |array| array.items,
        else => return error.InvalidContentParts,
    };
    try std.testing.expectEqual(expected_content_parts, content_parts.len);

    if (expected_system_parts == 0) {
        try std.testing.expect(root.get("systemInstruction") == null);
        return;
    }

    const system_instruction = switch (root.get("systemInstruction") orelse return error.MissingSystemInstruction) {
        .object => |object| object,
        else => return error.InvalidSystemInstruction,
    };
    const system_parts = switch (system_instruction.get("parts") orelse return error.MissingSystemParts) {
        .array => |array| array.items,
        else => return error.InvalidSystemParts,
    };
    try std.testing.expectEqual(expected_system_parts, system_parts.len);
    try std.testing.expect(expected_content_parts + expected_system_parts <= api.max_generate_request_parts_total);
}

test "buildGenerateRequest renders only explicit edit constraints" {
    const gpa = std.testing.allocator;
    const preserves = [_][]const u8{
        "keep the character identity",
        "keep the current crop",
    };
    const do_nots = [_][]const u8{
        "do not change the lighting",
    };
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
        .base_role = .character,
        .preserves = &preserves,
        .do_nots = &do_nots,
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "PRESERVE FROM BASE_IMAGE") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "keep the character identity") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "keep the current crop") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "DO NOT") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "do not change the lighting") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "Preserve the visible person's identity") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "Do not change the BASE_IMAGE character identity") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "Do not copy unrelated backgrounds") == null);
}

test "buildGenerateRequest interleaves labeled reference anchors and file parts" {
    const gpa = std.testing.allocator;
    const references = [_]Reference{
        .{
            .role = .object,
            .label = "OBJECT_A",
            .image = .{
                .name = "files/object",
                .mime = .png,
            },
        },
    };
    const request = try buildGenerateRequest(gpa, .{
        .prompt = "put OBJECT_A on the table",
        .base = .{
            .name = "files/base",
            .mime = .jpeg,
        },
        .references = &references,
    });
    defer gpa.free(request);

    const base_anchor = std.mem.indexOf(u8, request, "BASE_IMAGE").?;
    const base_file = std.mem.indexOf(u8, request, "https://generativelanguage.googleapis.com/v1beta/files/base").?;
    const object_anchor = std.mem.indexOf(u8, request, "OBJECT_A").?;
    const object_file = std.mem.indexOf(u8, request, "https://generativelanguage.googleapis.com/v1beta/files/object").?;
    const edit_task = std.mem.indexOf(u8, request, "EDIT TASK").?;

    try std.testing.expect(base_anchor < base_file);
    try std.testing.expect(base_file < object_anchor);
    try std.testing.expect(object_anchor < object_file);
    try std.testing.expect(object_file < edit_task);
    try std.testing.expect(std.mem.indexOf(u8, request, "object/product reference") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "PRESERVE FROM BASE_IMAGE") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "DO NOT") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "Do not copy unrelated backgrounds") == null);
}

test "buildGenerateRequest uses base character role language" {
    const gpa = std.testing.allocator;
    const request = try buildGenerateRequest(gpa, .{
        .prompt = live_prompt,
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
        .base_role = .character,
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "primary character identity reference") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "PRESERVE FROM BASE_IMAGE") == null);
    try std.testing.expect(std.mem.indexOf(u8, request, "DO NOT") == null);
}

test "isValidLabel accepts ASCII screaming snake case" {
    try std.testing.expect(isValidLabel("CHARACTER_A"));
    try std.testing.expect(isValidLabel("OBJECT_1"));
    try std.testing.expect(isValidLabel("STYLE_REFERENCE"));
}

test "isValidLabel rejects non screaming snake case labels" {
    try std.testing.expect(!isValidLabel(""));
    try std.testing.expect(!isValidLabel("character_a"));
    try std.testing.expect(!isValidLabel("Character_A"));
    try std.testing.expect(!isValidLabel("OBJECT-A"));
    try std.testing.expect(!isValidLabel("OBJECT A"));
    try std.testing.expect(!isValidLabel("1_OBJECT"));
}

test "buildFileUri derives Gemini File API URI" {
    const gpa = std.testing.allocator;
    const uri = try buildFileUri(gpa, live_base_name);
    defer gpa.free(uri);

    try std.testing.expectEqualStrings(
        "https://generativelanguage.googleapis.com/v1beta/files/tjtj5me9i96c",
        uri,
    );
}
