//! Gemini native image editing request handling.

const std = @import("std");
const assert = std.debug.assert;
const api = @import("api.zig");

pub const max_total_images = 14;
pub const max_references = max_total_images - 1;
pub const max_character_references = 4;
pub const max_object_references = 10;
pub const max_label_bytes = 64;

const file_uri_prefix = "https://generativelanguage.googleapis.com/v1beta/";
const live_base_name = "files/tjtj5me9i96c";
const live_prompt = "change visual style to Broadway musical";

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

pub const UploadedImage = struct {
    name: []const u8,
    mime: api.ImageMime,
};

pub const Reference = struct {
    role: ReferenceRole,
    label: []const u8,
    image: UploadedImage,
};

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

const GenerateFileData = struct {
    mime_type: []const u8,
    file_uri: []const u8,
};

const GeneratePart = struct {
    text: ?[]const u8 = null,
    file_data: ?GenerateFileData = null,
};

const GenerateContent = struct {
    parts: []const GeneratePart,
};

const GenerateContentRequest = struct {
    contents: []const GenerateContent,
    tools: ?[]const api.Tool = null,
    generationConfig: api.GenerationConfig,
    safetySettings: ?[]const api.SafetySetting = null,
    systemInstruction: ?api.TextContent = null,
    cachedContent: ?[]const u8 = null,
    serviceTier: ?api.ServiceTier = null,
    store: ?bool = null,
};

pub fn generateContent(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    request: EditRequest,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assertValidEditRequest(request);

    const request_json = try buildGenerateRequest(gpa, request);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, api.generateContentUrl(.nano2), request_json);
}

pub fn countGenerateContentRequestTokens(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    request: EditRequest,
) !api.HttpResponse {
    assert(api_key.len > 0);
    assertValidEditRequest(request);

    const request_json = try buildCountTokensRequest(gpa, request);
    defer gpa.free(request_json);

    return api.postJson(gpa, io, api_key, api.countTokensUrl(.nano2), request_json);
}

pub fn buildGenerateRequest(gpa: std.mem.Allocator, request: EditRequest) ![]u8 {
    assertValidEditRequest(request);

    var arena_state = std.heap.ArenaAllocator.init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const part_count = 2 + request.references.len * 2 + 1;
    const parts = try arena.alloc(GeneratePart, part_count);
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

    const contents = [_]GenerateContent{.{ .parts = parts }};
    var system_instruction_parts_buffer: [1]api.TextPart = undefined;
    const system_instruction: ?api.TextContent = if (request.request_options.system_instruction) |text| system_instruction: {
        system_instruction_parts_buffer[0] = .{ .text = text };
        break :system_instruction .{ .parts = system_instruction_parts_buffer[0..1] };
    } else null;
    const maybe_grounding_tool = api.googleSearchToolFromGroundingOptions(request.grounding_options);
    var tools_buffer: [1]api.Tool = undefined;
    const tools: ?[]const api.Tool = if (maybe_grounding_tool) |tool| tools: {
        tools_buffer[0] = tool;
        break :tools tools_buffer[0..1];
    } else null;
    var safety_settings_buffer: [api.supported_harm_categories.len]api.SafetySetting = undefined;
    const safety_settings: ?[]const api.SafetySetting = if (request.safety_options) |options| safety_settings: {
        safety_settings_buffer = api.safetySettingsFromOptions(options);
        break :safety_settings safety_settings_buffer[0..];
    } else null;
    const generate_request = GenerateContentRequest{
        .contents = &contents,
        .tools = tools,
        .generationConfig = api.generationConfigFromOptions(
            request.output_options,
            request.thinking_options,
            &request.generation_options,
        ),
        .safetySettings = safety_settings,
        .systemInstruction = system_instruction,
        .cachedContent = request.request_options.cached_content,
        .serviceTier = request.request_options.service_tier,
        .store = request.request_options.store,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(generate_request, .{ .emit_null_optional_fields = false }, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

pub fn buildCountTokensRequest(gpa: std.mem.Allocator, request: EditRequest) ![]u8 {
    assertValidEditRequest(request);

    const generate_request_json = try buildGenerateRequest(gpa, request);
    defer gpa.free(generate_request_json);

    return api.buildCountTokensRequestFromGenerateContentJson(gpa, .nano2, generate_request_json);
}

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

pub fn buildFileUri(gpa: std.mem.Allocator, name: []const u8) ![]u8 {
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

fn buildFileData(gpa: std.mem.Allocator, image: UploadedImage) !GenerateFileData {
    assert(api.isCanonicalFileName(image.name));

    return GenerateFileData{
        .mime_type = image.mime.apiName(),
        .file_uri = try buildFileUri(gpa, image.name),
    };
}

fn buildEditTask(gpa: std.mem.Allocator, request: EditRequest) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll("EDIT TASK:\nApply this edit to BASE_IMAGE using the labeled references above:\n");
    try output.writer.writeAll(request.prompt);

    if (request.preserves.len > 0) {
        try output.writer.writeAll("\n\nPRESERVE FROM BASE_IMAGE:");

        for (request.preserves) |preserve| {
            assert(preserve.len > 0);
            try output.writer.writeAll("\n- ");
            try output.writer.writeAll(preserve);
        }
    }

    if (request.do_nots.len > 0) {
        try output.writer.writeAll("\n\nDO NOT:");

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
    assert(request.prompt.len > 0);
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

    for (request.preserves) |preserve| assert(preserve.len > 0);
    for (request.do_nots) |do_not| assert(do_not.len > 0);
    api.assertValidGenerationOptions(request.generation_options);
    api.assertValidRequestOptions(request.request_options);
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

fn expectNoSafetySettings(request_json: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, request_json, "\"safetySettings\"") == null);
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

test "buildCountTokensRequest wraps edit generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, .{
        .prompt = live_prompt,
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.startsWith(
        u8,
        request,
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",",
    ));
    try std.testing.expect(std.mem.indexOf(u8, request, "\"file_data\"") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildCountTokensRequest wraps edit request-level controls" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequest(gpa, .{
        .prompt = live_prompt,
        .request_options = .{
            .system_instruction = "Preserve the subject identity.",
            .service_tier = .standard,
            .store = false,
        },
        .base = .{
            .name = live_base_name,
            .mime = .jpeg,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"generateContentRequest\":{") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"systemInstruction\":{\"parts\":[{\"text\":\"Preserve the subject identity.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"serviceTier\":\"standard\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"store\":false") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
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
