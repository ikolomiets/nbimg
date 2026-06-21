//! Shared Gemini API model constants, transport, and traffic logging.

const std = @import("std");
const assert = std.debug.assert;

const max_response_bytes = 64 * 1024 * 1024;
const default_request_timeout = std.Io.Duration.fromSeconds(180);
pub const api_key_env_name = "GEMINI_API_KEY";
pub const canonical_file_name_prefix = "files/";
const canonical_cached_content_name_prefix = "cachedContents/";
const max_display_name_codepoints = 512;
const max_generate_content_count = 1;
pub const max_generate_request_parts_total = 32;
pub const max_generate_text_part_bytes = 16 * 1024;
const max_generate_file_uri_bytes = 512;
const max_generate_mime_type_bytes = 64;
pub const max_generate_request_field_bytes = 5 * 1024 * 1024;

pub const ApiKeyError = error{
    MissingApiKey,
    EmptyApiKey,
};

pub const Model = enum {
    nano2,

    fn apiName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "gemini-3.1-flash-image",
        };
    }

    fn resourceName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "models/gemini-3.1-flash-image",
        };
    }
};

const ResponseModality = enum {
    text,
    image,

    fn apiName(modality: ResponseModality) []const u8 {
        return switch (modality) {
            .text => "TEXT",
            .image => "IMAGE",
        };
    }

    pub fn jsonStringify(modality: ResponseModality, writer: anytype) !void {
        try writer.write(modality.apiName());
    }
};

const default_response_modalities = [_]ResponseModality{ .text, .image };

const TextPart = struct {
    text: []const u8,
};

const TextContent = struct {
    parts: []const TextPart,
};

/// Identifies an uploaded file part by MIME type and URI.
///
/// - Both fields borrow caller-owned strings for the lifetime of the request.
/// - The value allocates nothing and mutates no state.
pub const GenerateFileData = struct {
    mime_type: []const u8,
    file_uri: []const u8,
};

/// Describes one borrowed text or uploaded-file request part.
///
/// - Any populated slice borrows caller-owned storage for the lifetime of the request.
/// - The value allocates nothing and mutates no state.
pub const GeneratePart = struct {
    text: ?[]const u8 = null,
    file_data: ?GenerateFileData = null,
};

/// Groups borrowed request parts into one Gemini content entry.
///
/// - `parts` and its nested slices must remain valid while the request is serialized.
/// - The value allocates nothing and mutates no state.
pub const GenerateContent = struct {
    parts: []const GeneratePart,
};

pub const ServiceTier = enum {
    flex,
    standard,
    priority,

    /// Parses a CLI service-tier name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?ServiceTier {
        if (std.mem.eql(u8, name, "flex")) return .flex;
        if (std.mem.eql(u8, name, "standard")) return .standard;
        if (std.mem.eql(u8, name, "priority")) return .priority;
        return null;
    }

    fn apiName(service_tier: ServiceTier) []const u8 {
        return switch (service_tier) {
            .flex => "flex",
            .standard => "standard",
            .priority => "priority",
        };
    }

    /// Writes the Gemini API spelling of a service tier.
    ///
    /// - Borrows the writer, allocates only if the writer does, propagates writer errors, and mutates only the writer.
    pub fn jsonStringify(service_tier: ServiceTier, writer: anytype) !void {
        try writer.write(service_tier.apiName());
    }
};

/// Configures request-level Gemini options.
///
/// - Optional string fields borrow caller-owned storage through request serialization.
/// - The value allocates nothing and mutates no state.
pub const RequestOptions = struct {
    system_instruction: ?[]const u8 = null,
    cached_content: ?[]const u8 = null,
    service_tier: ?ServiceTier = null,
    store: ?bool = null,

    /// Reports whether any request-level option is set.
    ///
    /// - Borrows no storage, allocates nothing, returns no errors, and mutates no state.
    pub fn hasAny(options: RequestOptions) bool {
        return options.system_instruction != null or
            options.cached_content != null or
            options.service_tier != null or
            options.store != null;
    }
};

pub const ImageAspectRatio = enum {
    r1_1,
    r1_4,
    r1_8,
    r2_3,
    r3_2,
    r3_4,
    r4_1,
    r4_3,
    r4_5,
    r5_4,
    r8_1,
    r9_16,
    r16_9,
    r21_9,

    /// Parses a CLI image aspect-ratio name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?ImageAspectRatio {
        if (std.mem.eql(u8, name, "1:1")) return .r1_1;
        if (std.mem.eql(u8, name, "1:4")) return .r1_4;
        if (std.mem.eql(u8, name, "1:8")) return .r1_8;
        if (std.mem.eql(u8, name, "2:3")) return .r2_3;
        if (std.mem.eql(u8, name, "3:2")) return .r3_2;
        if (std.mem.eql(u8, name, "3:4")) return .r3_4;
        if (std.mem.eql(u8, name, "4:1")) return .r4_1;
        if (std.mem.eql(u8, name, "4:3")) return .r4_3;
        if (std.mem.eql(u8, name, "4:5")) return .r4_5;
        if (std.mem.eql(u8, name, "5:4")) return .r5_4;
        if (std.mem.eql(u8, name, "8:1")) return .r8_1;
        if (std.mem.eql(u8, name, "9:16")) return .r9_16;
        if (std.mem.eql(u8, name, "16:9")) return .r16_9;
        if (std.mem.eql(u8, name, "21:9")) return .r21_9;
        return null;
    }

    fn apiName(aspect_ratio: ImageAspectRatio) []const u8 {
        return switch (aspect_ratio) {
            .r1_1 => "1:1",
            .r1_4 => "1:4",
            .r1_8 => "1:8",
            .r2_3 => "2:3",
            .r3_2 => "3:2",
            .r3_4 => "3:4",
            .r4_1 => "4:1",
            .r4_3 => "4:3",
            .r4_5 => "4:5",
            .r5_4 => "5:4",
            .r8_1 => "8:1",
            .r9_16 => "9:16",
            .r16_9 => "16:9",
            .r21_9 => "21:9",
        };
    }

    fn jsonStringify(aspect_ratio: ImageAspectRatio, writer: anytype) !void {
        try writer.write(aspect_ratio.apiName());
    }
};

pub const ImageSize = enum {
    px512,
    k1,
    k2,
    k4,

    /// Parses a CLI image-size name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?ImageSize {
        if (std.mem.eql(u8, name, "512")) return .px512;
        if (std.mem.eql(u8, name, "1K")) return .k1;
        if (std.mem.eql(u8, name, "2K")) return .k2;
        if (std.mem.eql(u8, name, "4K")) return .k4;
        return null;
    }

    fn apiName(image_size: ImageSize) []const u8 {
        return switch (image_size) {
            .px512 => "512",
            .k1 => "1K",
            .k2 => "2K",
            .k4 => "4K",
        };
    }

    fn jsonStringify(image_size: ImageSize, writer: anytype) !void {
        try writer.write(image_size.apiName());
    }
};

/// Configures image dimensions for generated output.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const ImageOutputOptions = struct {
    aspect_ratio: ?ImageAspectRatio = null,
    image_size: ?ImageSize = null,

    /// Reports whether any image output option is set.
    ///
    /// - Allocates nothing, returns no errors, and mutates no state.
    pub fn hasAny(options: ImageOutputOptions) bool {
        return options.aspect_ratio != null or options.image_size != null;
    }
};

/// Selects optional web and image grounding sources.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const GroundingOptions = struct {
    web: bool = false,
    image: bool = false,

    /// Reports whether any grounding source is enabled.
    ///
    /// - Allocates nothing, returns no errors, and mutates no state.
    pub fn hasAny(options: GroundingOptions) bool {
        return options.web or options.image;
    }

    /// Parses a CLI grounding-source name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?GroundingOptions {
        if (std.mem.eql(u8, name, "none")) return .{};
        if (std.mem.eql(u8, name, "web")) return .{ .web = true };
        if (std.mem.eql(u8, name, "image")) return .{ .image = true };
        if (std.mem.eql(u8, name, "web,image")) return .{ .web = true, .image = true };
        return null;
    }
};

pub const ThinkingLevel = enum {
    minimal,
    high,

    /// Parses a CLI thinking-level name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?ThinkingLevel {
        if (std.mem.eql(u8, name, "minimal")) return .minimal;
        if (std.mem.eql(u8, name, "high")) return .high;
        return null;
    }

    fn apiName(level: ThinkingLevel) []const u8 {
        return switch (level) {
            .minimal => "minimal",
            .high => "high",
        };
    }

    /// Writes the Gemini API spelling of a thinking level.
    ///
    /// - Borrows the writer, allocates only if the writer does, propagates writer errors, and mutates only the writer.
    pub fn jsonStringify(level: ThinkingLevel, writer: anytype) !void {
        try writer.write(level.apiName());
    }
};

/// Configures model thinking behavior.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const ThinkingOptions = struct {
    level: ?ThinkingLevel = null,
    include_thoughts: bool = false,

    /// Reports whether any thinking option is set.
    ///
    /// - Allocates nothing, returns no errors, and mutates no state.
    pub fn hasAny(options: ThinkingOptions) bool {
        return options.level != null or options.include_thoughts;
    }
};

const ThinkingConfig = struct {
    thinkingLevel: ?ThinkingLevel = null,
    includeThoughts: ?bool = null,
};

pub const max_stop_sequences = 5;
pub const max_output_tokens = 32768;

/// Configures sampling, token limits, and borrowed stop sequences.
///
/// - Appended stop-sequence slices remain caller-owned and must outlive request serialization.
/// - The value allocates nothing; only its explicit mutating methods change it.
pub const GenerationOptions = struct {
    max_output_tokens: ?u32 = null,
    temperature: ?f64 = null,
    top_p: ?f64 = null,
    seed: ?i32 = null,
    presence_penalty: ?f64 = null,
    frequency_penalty: ?f64 = null,
    response_logprobs: bool = false,
    logprobs: ?u8 = null,
    stop_sequences: [max_stop_sequences][]const u8 = [_][]const u8{""} ** max_stop_sequences,
    stop_sequence_count: usize = 0,

    /// Reports whether any advanced generation option is set.
    ///
    /// - Borrows nested stop-sequence slices, allocates nothing, returns no errors, and mutates no state.
    pub fn hasAny(options: GenerationOptions) bool {
        return options.max_output_tokens != null or
            options.temperature != null or
            options.top_p != null or
            options.seed != null or
            options.presence_penalty != null or
            options.frequency_penalty != null or
            options.response_logprobs or
            options.logprobs != null or
            options.stop_sequence_count > 0;
    }

    /// Returns a borrowed view of the configured stop sequences.
    ///
    /// - The returned slice and strings remain owned by `options`; no allocation or mutation occurs.
    /// - Asserts that the stored count is within capacity.
    pub fn stopSequenceSlice(options: *const GenerationOptions) []const []const u8 {
        assert(options.stop_sequence_count <= max_stop_sequences);
        return options.stop_sequences[0..options.stop_sequence_count];
    }

    /// Appends a borrowed stop sequence to the fixed-capacity options value.
    ///
    /// - `value` remains caller-owned and must outlive uses of `options`; no allocation occurs.
    /// - Asserts that `value` is non-empty and capacity remains; mutates only `options`.
    pub fn appendStopSequence(options: *GenerationOptions, value: []const u8) void {
        assert(value.len > 0);
        assert(options.stop_sequence_count < max_stop_sequences);

        options.stop_sequences[options.stop_sequence_count] = value;
        options.stop_sequence_count += 1;
    }
};

const GenerationConfig = struct {
    responseModalities: []const ResponseModality,
    thinkingConfig: ?ThinkingConfig = null,
    responseFormat: ?ResponseFormatConfig = null,
    maxOutputTokens: ?u32 = null,
    temperature: ?f64 = null,
    topP: ?f64 = null,
    seed: ?i32 = null,
    presencePenalty: ?f64 = null,
    frequencyPenalty: ?f64 = null,
    responseLogprobs: ?bool = null,
    logprobs: ?u8 = null,
    stopSequences: ?[]const []const u8 = null,
};

fn thinkingConfigFromOptions(options: ThinkingOptions) ?ThinkingConfig {
    if (!options.hasAny()) return null;
    return .{
        .thinkingLevel = options.level,
        .includeThoughts = if (options.include_thoughts) true else null,
    };
}

fn generationConfigFromOptions(
    output_options: ImageOutputOptions,
    thinking_options: ThinkingOptions,
    generation_options: *const GenerationOptions,
) GenerationConfig {
    assertValidGenerationOptions(generation_options.*);

    return .{
        .responseModalities = &default_response_modalities,
        .thinkingConfig = thinkingConfigFromOptions(thinking_options),
        .responseFormat = responseFormatFromOutputOptions(output_options),
        .maxOutputTokens = generation_options.max_output_tokens,
        .temperature = generation_options.temperature,
        .topP = generation_options.top_p,
        .seed = generation_options.seed,
        .presencePenalty = generation_options.presence_penalty,
        .frequencyPenalty = generation_options.frequency_penalty,
        .responseLogprobs = if (generation_options.response_logprobs) true else null,
        .logprobs = generation_options.logprobs,
        .stopSequences = if (generation_options.stop_sequence_count > 0)
            generation_options.stopSequenceSlice()
        else
            null,
    };
}

/// Asserts all generation-option invariants.
///
/// - Borrows nested stop-sequence strings, allocates nothing, returns no errors, and mutates no state.
pub fn assertValidGenerationOptions(options: GenerationOptions) void {
    assert(options.stop_sequence_count <= max_stop_sequences);

    if (options.max_output_tokens) |tokens| {
        assert(tokens >= 1);
        assert(tokens <= max_output_tokens);
    }

    if (options.temperature) |temperature| {
        assert(std.math.isFinite(temperature));
        assert(temperature >= 0.0);
        assert(temperature <= 2.0);
    }

    if (options.top_p) |top_p| {
        assert(std.math.isFinite(top_p));
        assert(top_p >= 0.0);
        assert(top_p <= 1.0);
    }

    if (options.presence_penalty) |presence_penalty| {
        assert(std.math.isFinite(presence_penalty));
        assert(presence_penalty >= -2.0);
        assert(presence_penalty < 2.0);
    }

    if (options.frequency_penalty) |frequency_penalty| {
        assert(std.math.isFinite(frequency_penalty));
        assert(frequency_penalty >= -2.0);
        assert(frequency_penalty < 2.0);
    }

    if (options.logprobs) |logprobs| {
        assert(options.response_logprobs);
        assert(logprobs >= 1);
        assert(logprobs <= 20);
    }

    const stops = options.stopSequenceSlice();
    for (stops, 0..) |stop, index| {
        assert(stop.len > 0);
        for (stops[index + 1 ..]) |other| {
            assert(!std.mem.eql(u8, stop, other));
        }
    }
}

/// Asserts all request-option invariants.
///
/// - Borrows optional strings, allocates nothing, returns no errors, and mutates no state.
pub fn assertValidRequestOptions(options: RequestOptions) void {
    if (options.system_instruction) |system_instruction| {
        assert(system_instruction.len > 0);
        assert(system_instruction.len <= max_generate_text_part_bytes);
    }

    if (options.cached_content) |cached_content| {
        assert(isCanonicalCachedContentName(cached_content));
    }
}

const SearchType = struct {};

const SearchTypes = struct {
    webSearch: ?SearchType = null,
    imageSearch: ?SearchType = null,
};

const GoogleSearch = struct {
    searchTypes: ?SearchTypes = null,
};

const Tool = struct {
    google_search: GoogleSearch,
};

fn googleSearchToolFromGroundingOptions(options: GroundingOptions) ?Tool {
    if (!options.hasAny()) return null;

    if (options.web and !options.image) {
        return .{
            .google_search = .{},
        };
    }

    return .{
        .google_search = .{
            .searchTypes = .{
                .webSearch = if (options.web) SearchType{} else null,
                .imageSearch = if (options.image) SearchType{} else null,
            },
        },
    };
}

/// Combines all option groups used to build a generate-content request.
///
/// - Nested string slices remain caller-owned through request serialization.
/// - The value allocates nothing and mutates no state.
pub const GenerateContentRequestOptions = struct {
    output_options: ImageOutputOptions = .{},
    grounding_options: GroundingOptions = .{},
    thinking_options: ThinkingOptions = .{},
    safety_options: ?SafetyOptions = null,
    generation_options: GenerationOptions = .{},
    request_options: RequestOptions = .{},
};

const GenerateContentRequest = struct {
    contents: []const GenerateContent,
    tools: ?[]const Tool = null,
    generationConfig: GenerationConfig,
    safetySettings: ?[]const SafetySetting = null,
    systemInstruction: ?TextContent = null,
    cachedContent: ?[]const u8 = null,
    serviceTier: ?ServiceTier = null,
    store: ?bool = null,
};

/// Serializes generate-content inputs into an owned JSON request.
///
/// - Borrows all inputs for the call; the returned slice is owned by `gpa`.
/// - Allocates with `gpa`, returns allocation or writer errors, and mutates no input or global state.
pub fn buildGenerateContentRequestJson(
    gpa: std.mem.Allocator,
    contents: []const GenerateContent,
    options: GenerateContentRequestOptions,
) ![]u8 {
    assertValidGenerateContentRequest(contents, options);

    var system_instruction_parts_buffer: [1]TextPart = undefined;
    const system_instruction: ?TextContent = if (options.request_options.system_instruction) |text| system_instruction: {
        system_instruction_parts_buffer[0] = .{ .text = text };
        break :system_instruction .{ .parts = system_instruction_parts_buffer[0..1] };
    } else null;
    const maybe_grounding_tool = googleSearchToolFromGroundingOptions(options.grounding_options);
    var tools_buffer: [1]Tool = undefined;
    const tools: ?[]const Tool = if (maybe_grounding_tool) |tool| tools: {
        tools_buffer[0] = tool;
        break :tools tools_buffer[0..1];
    } else null;
    var safety_settings_buffer: [supported_harm_categories.len]SafetySetting = undefined;
    const safety_settings: ?[]const SafetySetting = if (options.safety_options) |safety_options| safety_settings: {
        safety_settings_buffer = safetySettingsFromOptions(safety_options);
        break :safety_settings safety_settings_buffer[0..];
    } else null;
    const request = GenerateContentRequest{
        .contents = contents,
        .tools = tools,
        .generationConfig = generationConfigFromOptions(
            options.output_options,
            options.thinking_options,
            &options.generation_options,
        ),
        .safetySettings = safety_settings,
        .systemInstruction = system_instruction,
        .cachedContent = options.request_options.cached_content,
        .serviceTier = options.request_options.service_tier,
        .store = options.request_options.store,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(request, .{ .emit_null_optional_fields = false }, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn assertValidGenerateContentRequest(contents: []const GenerateContent, options: GenerateContentRequestOptions) void {
    const validation = validateGenerateContentRequest(
        contents,
        options.request_options,
        &options.generation_options,
    );
    assert(validation.has_contents);
    assert(validation.content_count_within_limit);
    assert(validation.every_content_has_parts);
    assert(validation.part_count_within_limit);
    assert(validation.every_part_has_one_payload);
    assert(validation.text_parts_non_empty);
    assert(validation.text_parts_within_limit);
    assert(validation.file_mime_types_non_empty);
    assert(validation.file_mime_types_within_limit);
    assert(validation.file_uris_non_empty);
    assert(validation.file_uris_within_limit);
    assert(validation.system_instruction_non_empty);
    assert(validation.system_instruction_within_limit);
    assert(validation.cached_content_canonical);
    assert(validation.field_bytes_within_limit);
}

const GenerateContentRequestValidation = struct {
    has_contents: bool,
    content_count_within_limit: bool,
    every_content_has_parts: bool = true,
    part_count_within_limit: bool = true,
    every_part_has_one_payload: bool = true,
    text_parts_non_empty: bool = true,
    text_parts_within_limit: bool = true,
    file_mime_types_non_empty: bool = true,
    file_mime_types_within_limit: bool = true,
    file_uris_non_empty: bool = true,
    file_uris_within_limit: bool = true,
    system_instruction_non_empty: bool = true,
    system_instruction_within_limit: bool = true,
    cached_content_canonical: bool = true,
    field_bytes_within_limit: bool = true,

    fn valid(validation: GenerateContentRequestValidation) bool {
        return validation.has_contents and
            validation.content_count_within_limit and
            validation.every_content_has_parts and
            validation.part_count_within_limit and
            validation.every_part_has_one_payload and
            validation.text_parts_non_empty and
            validation.text_parts_within_limit and
            validation.file_mime_types_non_empty and
            validation.file_mime_types_within_limit and
            validation.file_uris_non_empty and
            validation.file_uris_within_limit and
            validation.system_instruction_non_empty and
            validation.system_instruction_within_limit and
            validation.cached_content_canonical and
            validation.field_bytes_within_limit;
    }
};

fn validateGenerateContentRequest(
    contents: []const GenerateContent,
    request_options: RequestOptions,
    generation_options: *const GenerationOptions,
) GenerateContentRequestValidation {
    assertValidGenerationOptions(generation_options.*);

    var validation = GenerateContentRequestValidation{
        .has_contents = contents.len > 0,
        .content_count_within_limit = contents.len <= max_generate_content_count,
    };
    var part_count: usize = 0;
    var field_bytes: usize = 0;

    for (contents) |content| {
        if (content.parts.len == 0) validation.every_content_has_parts = false;
        part_count +|= content.parts.len;

        for (content.parts) |part| {
            const has_text = part.text != null;
            const has_file_data = part.file_data != null;
            if (has_text == has_file_data) validation.every_part_has_one_payload = false;

            if (part.text) |text| {
                if (text.len == 0) validation.text_parts_non_empty = false;
                if (text.len > max_generate_text_part_bytes) validation.text_parts_within_limit = false;
                field_bytes +|= text.len;
            }

            if (part.file_data) |file_data| {
                if (file_data.mime_type.len == 0) validation.file_mime_types_non_empty = false;
                if (file_data.mime_type.len > max_generate_mime_type_bytes) validation.file_mime_types_within_limit = false;
                if (file_data.file_uri.len == 0) validation.file_uris_non_empty = false;
                if (file_data.file_uri.len > max_generate_file_uri_bytes) validation.file_uris_within_limit = false;
                field_bytes +|= file_data.mime_type.len;
                field_bytes +|= file_data.file_uri.len;
            }
        }
    }

    if (request_options.system_instruction) |system_instruction| {
        part_count +|= 1;
        if (system_instruction.len == 0) validation.system_instruction_non_empty = false;
        if (system_instruction.len > max_generate_text_part_bytes) validation.system_instruction_within_limit = false;
        field_bytes +|= system_instruction.len;
    }

    if (request_options.cached_content) |cached_content| {
        if (!isCanonicalCachedContentName(cached_content)) validation.cached_content_canonical = false;
        field_bytes +|= cached_content.len;
    }

    for (generation_options.stopSequenceSlice()) |stop_sequence| {
        field_bytes +|= stop_sequence.len;
    }

    validation.part_count_within_limit = part_count <= max_generate_request_parts_total;
    validation.field_bytes_within_limit = field_bytes <= max_generate_request_field_bytes;
    return validation;
}

const ResponseFormatConfig = struct {
    image: ?ImageResponseFormat = null,
};

const ImageResponseFormat = struct {
    aspectRatio: ?ImageResponseAspectRatio = null,
    imageSize: ?ImageResponseSize = null,
};

const ImageResponseAspectRatio = enum {
    one_by_one,
    one_by_four,
    one_by_eight,
    two_by_three,
    three_by_two,
    three_by_four,
    four_by_one,
    four_by_three,
    four_by_five,
    five_by_four,
    eight_by_one,
    nine_by_sixteen,
    sixteen_by_nine,
    twenty_one_by_nine,

    fn fromImageAspectRatio(aspect_ratio: ImageAspectRatio) ImageResponseAspectRatio {
        return switch (aspect_ratio) {
            .r1_1 => .one_by_one,
            .r1_4 => .one_by_four,
            .r1_8 => .one_by_eight,
            .r2_3 => .two_by_three,
            .r3_2 => .three_by_two,
            .r3_4 => .three_by_four,
            .r4_1 => .four_by_one,
            .r4_3 => .four_by_three,
            .r4_5 => .four_by_five,
            .r5_4 => .five_by_four,
            .r8_1 => .eight_by_one,
            .r9_16 => .nine_by_sixteen,
            .r16_9 => .sixteen_by_nine,
            .r21_9 => .twenty_one_by_nine,
        };
    }

    fn apiName(aspect_ratio: ImageResponseAspectRatio) []const u8 {
        return switch (aspect_ratio) {
            .one_by_one => "ASPECT_RATIO_ONE_BY_ONE",
            .one_by_four => "ASPECT_RATIO_ONE_BY_FOUR",
            .one_by_eight => "ASPECT_RATIO_ONE_BY_EIGHT",
            .two_by_three => "ASPECT_RATIO_TWO_BY_THREE",
            .three_by_two => "ASPECT_RATIO_THREE_BY_TWO",
            .three_by_four => "ASPECT_RATIO_THREE_BY_FOUR",
            .four_by_one => "ASPECT_RATIO_FOUR_BY_ONE",
            .four_by_three => "ASPECT_RATIO_FOUR_BY_THREE",
            .four_by_five => "ASPECT_RATIO_FOUR_BY_FIVE",
            .five_by_four => "ASPECT_RATIO_FIVE_BY_FOUR",
            .eight_by_one => "ASPECT_RATIO_EIGHT_BY_ONE",
            .nine_by_sixteen => "ASPECT_RATIO_NINE_BY_SIXTEEN",
            .sixteen_by_nine => "ASPECT_RATIO_SIXTEEN_BY_NINE",
            .twenty_one_by_nine => "ASPECT_RATIO_TWENTY_ONE_BY_NINE",
        };
    }

    pub fn jsonStringify(aspect_ratio: ImageResponseAspectRatio, writer: anytype) !void {
        try writer.write(aspect_ratio.apiName());
    }
};

const ImageResponseSize = enum {
    five_twelve,
    one_k,
    two_k,
    four_k,

    fn fromImageSize(image_size: ImageSize) ImageResponseSize {
        return switch (image_size) {
            .px512 => .five_twelve,
            .k1 => .one_k,
            .k2 => .two_k,
            .k4 => .four_k,
        };
    }

    fn apiName(image_size: ImageResponseSize) []const u8 {
        return switch (image_size) {
            .five_twelve => "IMAGE_SIZE_FIVE_TWELVE",
            .one_k => "IMAGE_SIZE_ONE_K",
            .two_k => "IMAGE_SIZE_TWO_K",
            .four_k => "IMAGE_SIZE_FOUR_K",
        };
    }

    pub fn jsonStringify(image_size: ImageResponseSize, writer: anytype) !void {
        try writer.write(image_size.apiName());
    }
};

fn responseFormatFromOutputOptions(options: ImageOutputOptions) ?ResponseFormatConfig {
    if (!options.hasAny()) return null;
    return .{
        .image = .{
            .aspectRatio = if (options.aspect_ratio) |aspect_ratio|
                ImageResponseAspectRatio.fromImageAspectRatio(aspect_ratio)
            else
                null,
            .imageSize = if (options.image_size) |image_size|
                ImageResponseSize.fromImageSize(image_size)
            else
                null,
        },
    };
}

const HarmCategory = enum {
    harassment,
    hate_speech,
    sexually_explicit,
    dangerous_content,

    fn apiName(category: HarmCategory) []const u8 {
        return switch (category) {
            .harassment => "HARM_CATEGORY_HARASSMENT",
            .hate_speech => "HARM_CATEGORY_HATE_SPEECH",
            .sexually_explicit => "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            .dangerous_content => "HARM_CATEGORY_DANGEROUS_CONTENT",
        };
    }

    pub fn jsonStringify(category: HarmCategory, writer: anytype) !void {
        try writer.write(category.apiName());
    }
};

pub const HarmBlockThreshold = enum {
    block_low_and_above,
    block_medium_and_above,
    block_only_high,
    block_none,
    off,
    harm_block_threshold_unspecified,

    fn apiName(threshold: HarmBlockThreshold) []const u8 {
        return switch (threshold) {
            .block_low_and_above => "BLOCK_LOW_AND_ABOVE",
            .block_medium_and_above => "BLOCK_MEDIUM_AND_ABOVE",
            .block_only_high => "BLOCK_ONLY_HIGH",
            .block_none => "BLOCK_NONE",
            .off => "OFF",
            .harm_block_threshold_unspecified => "HARM_BLOCK_THRESHOLD_UNSPECIFIED",
        };
    }

    /// Writes the Gemini API spelling of a harm-block threshold.
    ///
    /// - Borrows the writer, allocates only if the writer does, propagates writer errors, and mutates only the writer.
    pub fn jsonStringify(threshold: HarmBlockThreshold, writer: anytype) !void {
        try writer.write(threshold.apiName());
    }
};

const SafetySetting = struct {
    category: HarmCategory,
    threshold: HarmBlockThreshold,
};

/// Applies one harm-block threshold to every supported category.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const SafetyOptions = struct {
    threshold: HarmBlockThreshold = .block_none,

    /// Parses a CLI safety preset name.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unknown names, and mutates no state.
    pub fn fromName(name: []const u8) ?SafetyOptions {
        if (std.mem.eql(u8, name, "none")) return .{ .threshold = .block_none };
        if (std.mem.eql(u8, name, "off")) return .{ .threshold = .off };
        if (std.mem.eql(u8, name, "permissive")) return .{ .threshold = .block_only_high };
        if (std.mem.eql(u8, name, "balanced")) return .{ .threshold = .block_medium_and_above };
        if (std.mem.eql(u8, name, "strict")) return .{ .threshold = .block_low_and_above };
        return null;
    }
};

const supported_harm_categories = [_]HarmCategory{
    .harassment,
    .hate_speech,
    .sexually_explicit,
    .dangerous_content,
};

fn safetySettingsFromOptions(options: SafetyOptions) [supported_harm_categories.len]SafetySetting {
    var settings: [supported_harm_categories.len]SafetySetting = undefined;

    for (supported_harm_categories, 0..) |category, index| {
        settings[index] = .{
            .category = category,
            .threshold = options.threshold,
        };
    }

    return settings;
}

/// Holds token counts decoded from a count-tokens response.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
};

pub const ImageMime = enum {
    jpeg,
    png,
    webp,

    /// Parses a supported image MIME type.
    ///
    /// - Borrows `name`, allocates nothing, returns `null` for unsupported names, and mutates no state.
    pub fn fromName(name: []const u8) ?ImageMime {
        if (std.mem.eql(u8, name, "image/jpeg")) return .jpeg;
        if (std.mem.eql(u8, name, "image/png")) return .png;
        if (std.mem.eql(u8, name, "image/webp")) return .webp;
        return null;
    }

    /// Infers a supported image MIME type from a path extension.
    ///
    /// - Borrows `path`, allocates nothing, returns `null` for unsupported extensions, and mutates no state.
    pub fn fromPath(path: []const u8) ?ImageMime {
        const extension = std.fs.path.extension(path);
        if (std.ascii.eqlIgnoreCase(extension, ".jpg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".jpeg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".png")) return .png;
        if (std.ascii.eqlIgnoreCase(extension, ".webp")) return .webp;
        return null;
    }

    /// Returns the static Gemini API name for an image MIME type.
    ///
    /// - Returns static storage, allocates nothing, returns no errors, and mutates no state.
    pub fn apiName(mime: ImageMime) []const u8 {
        return switch (mime) {
            .jpeg => "image/jpeg",
            .png => "image/png",
            .webp => "image/webp",
        };
    }
};

pub const OutputMime = enum {
    png,
    jpeg,
    webp,

    fn fromName(name: []const u8) ?OutputMime {
        if (std.mem.eql(u8, name, "image/png")) return .png;
        if (std.mem.eql(u8, name, "image/jpeg")) return .jpeg;
        if (std.mem.eql(u8, name, "image/webp")) return .webp;
        return null;
    }

    /// Returns the static filename extension for an output MIME type.
    ///
    /// - Returns static storage, allocates nothing, returns no errors, and mutates no state.
    pub fn extension(mime: OutputMime) []const u8 {
        return switch (mime) {
            .png => "png",
            .jpeg => "jpg",
            .webp => "webp",
        };
    }
};

/// Owns one decoded generated-image byte buffer.
///
/// - `bytes` must be released with `deinit` using the allocator that created it.
/// - The value otherwise owns no external state.
pub const GeneratedFile = struct {
    candidate_index: usize,
    part_index: usize,
    mime: OutputMime,
    bytes: []u8,

    /// Frees a generated file's bytes and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created `bytes`; no errors are returned.
    /// - Mutates only `file` and allocator state.
    pub fn deinit(file: *GeneratedFile, gpa: std.mem.Allocator) void {
        gpa.free(file.bytes);
        file.* = undefined;
    }
};

/// Owns a response ID and all decoded generated files.
///
/// - All owned slices must be released with `deinit` using their originating allocator.
/// - The value otherwise owns no external state.
pub const GeneratedFiles = struct {
    response_id: []u8,
    items: []GeneratedFile,

    /// Frees a generated-files result and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created every owned slice; no errors are returned.
    /// - Mutates only `files` and allocator state.
    pub fn deinit(files: *GeneratedFiles, gpa: std.mem.Allocator) void {
        for (files.items) |*file| file.deinit(gpa);
        gpa.free(files.items);
        gpa.free(files.response_id);
        files.* = undefined;
    }
};

/// Owns an HTTP status and response body.
///
/// - `body` must be released with `deinit` using the allocator that created it.
/// - The value does not itself mutate global state.
pub const HttpResponse = struct {
    status: std.http.Status,
    body: []u8,

    /// Frees an HTTP response body and invalidates the value.
    ///
    /// - `gpa` must match the allocator that created `body`; no errors are returned.
    /// - Mutates only `response` and allocator state.
    pub fn deinit(response: *HttpResponse, gpa: std.mem.Allocator) void {
        gpa.free(response.body);
        response.* = undefined;
    }
};

const HttpResponseWithUploadUrl = struct {
    response: HttpResponse,
    upload_url: ?[]u8 = null,

    fn deinit(response: *HttpResponseWithUploadUrl, gpa: std.mem.Allocator) void {
        response.response.deinit(gpa);
        if (response.upload_url) |upload_url| gpa.free(upload_url);
        response.* = undefined;
    }
};

/// Describes borrowed content for a resumable Files API upload.
///
/// - All slices remain caller-owned and must outlive the upload call.
/// - The value allocates nothing and mutates no state.
pub const ResumableUpload = struct {
    content_type: []const u8,
    bytes: []const u8,
    display_name: ?[]const u8 = null,
};

/// Selects whether HTTP request and response details are printed.
///
/// - The value owns no heap storage, allocates nothing, and mutates no state.
pub const TrafficLogOptions = struct {
    print_request: bool = false,
    print_response: bool = false,
};

/// Supplies explicit dependencies and options for one or more HTTP requests.
///
/// - `api_key` remains caller-owned and must outlive every request using the context.
/// - The value owns no resources and may be shared by concurrent requests.
pub const RequestContext = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    timeout: std.Io.Duration = default_request_timeout,
    traffic_log_options: TrafficLogOptions = .{},
};

fn assertValidRequestContext(context: *const RequestContext) void {
    assert(context.api_key.len > 0);
    assert(context.timeout.nanoseconds > 0);
}

/// Returns the borrowed Gemini API key stored in an environment map.
///
/// - The returned slice remains owned by `environ_map`; no allocation or mutation occurs.
/// - Returns `MissingApiKey` or `EmptyApiKey` when the configured entry is unusable.
pub fn apiKeyFromMap(environ_map: *const std.process.Environ.Map) ApiKeyError![]const u8 {
    const api_key = environ_map.get(api_key_env_name) orelse return error.MissingApiKey;
    if (api_key.len == 0) return error.EmptyApiKey;
    return api_key;
}

fn generateContentUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent",
    };
}

fn countTokensUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:countTokens",
    };
}

/// Posts a borrowed JSON body to the selected model's generate-content endpoint.
///
/// - Borrows request inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and may update remote service state.
pub fn postGenerateContentJson(
    context: *const RequestContext,
    model: Model,
    request_json: []const u8,
) !HttpResponse {
    assertValidRequestContext(context);
    assert(request_json.len > 0);

    return postJson(context, generateContentUrl(model), request_json);
}

/// Posts a borrowed JSON body to the selected model's count-tokens endpoint.
///
/// - Borrows request inputs; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and performs a remote request.
pub fn postCountTokensJson(
    context: *const RequestContext,
    model: Model,
    request_json: []const u8,
) !HttpResponse {
    assertValidRequestContext(context);
    assert(request_json.len > 0);

    return postJson(context, countTokensUrl(model), request_json);
}

/// Reports whether a string is a canonical non-empty Files API resource name.
///
/// - Borrows `name`, allocates nothing, returns no errors, and mutates no state.
pub fn isCanonicalFileName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_file_name_prefix)) return false;
    return name.len > canonical_file_name_prefix.len;
}

/// Reports whether a string is a canonical non-empty cached-content resource name.
///
/// - Borrows `name`, allocates nothing, returns no errors, and mutates no state.
pub fn isCanonicalCachedContentName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_cached_content_name_prefix)) return false;
    return name.len > canonical_cached_content_name_prefix.len;
}

/// Reports whether a display name is non-empty, valid UTF-8, and within the API limit.
///
/// - Borrows `display_name`, allocates nothing, returns no errors, and mutates no state.
pub fn isValidDisplayName(display_name: []const u8) bool {
    if (display_name.len == 0) return false;
    const codepoints = std.unicode.utf8CountCodepoints(display_name) catch return false;
    return codepoints <= max_display_name_codepoints;
}

/// Wraps a generate-content JSON object in an owned count-tokens request.
///
/// - Borrows the input JSON for the call; the returned slice is owned by `gpa`.
/// - Allocates with `gpa`, returns allocation or writer errors, and mutates no input or global state.
pub fn buildCountTokensRequestFromGenerateContentJson(
    gpa: std.mem.Allocator,
    model: Model,
    generate_request_json: []const u8,
) ![]u8 {
    assert(generate_request_json.len >= 2);
    assert(generate_request_json[0] == '{');
    assert(generate_request_json[generate_request_json.len - 1] == '}');

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try output.writer.writeAll("{\"generateContentRequest\":{\"model\":\"");
    try output.writer.writeAll(model.resourceName());
    try output.writer.writeAll("\",");
    try output.writer.writeAll(generate_request_json[1..]);
    try output.writer.writeAll("}");

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

/// Decodes token counts from a borrowed JSON response.
///
/// - Uses `gpa` only for temporary parsing storage and returns no owned allocation.
/// - Returns allocation, JSON parsing, or `MissingTotalTokens` errors and mutates no input or global state.
pub fn decodeCountTokensResponse(gpa: std.mem.Allocator, response_json: []const u8) !CountTokensResult {
    const Response = struct {
        totalTokens: ?u64 = null,
        cachedContentTokenCount: ?u64 = null,
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    return .{
        .total_tokens = parsed.value.totalTokens orelse return error.MissingTotalTokens,
        .cached_content_token_count = parsed.value.cachedContentTokenCount,
    };
}

/// Decodes an optional service tier from a borrowed response body.
///
/// - Uses `gpa` only for temporary parsing storage and returns no owned allocation.
/// - Returns allocation or JSON parsing errors and mutates no input or global state.
pub fn decodeResponseServiceTier(gpa: std.mem.Allocator, response_json: []const u8) !?ServiceTier {
    const Response = struct {
        usageMetadata: ?UsageMetadata = null,

        const UsageMetadata = struct {
            serviceTier: ?[]const u8 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const usage_metadata = parsed.value.usageMetadata orelse return null;
    const service_tier_name = usage_metadata.serviceTier orelse return null;
    return ServiceTier.fromName(service_tier_name);
}

/// Decodes and owns generated image files from a borrowed JSON response.
///
/// - Allocates the result with `gpa`; the caller must invoke `GeneratedFiles.deinit`.
/// - Returns allocation, JSON, base64, or unsupported-response errors and mutates no input or global state.
pub fn decodeGeneratedFiles(gpa: std.mem.Allocator, response_json: []const u8) !GeneratedFiles {
    const Response = struct {
        candidates: []const Candidate = &.{},
        usageMetadata: ?UsageMetadata = null,
        modelVersion: ?[]const u8 = null,
        responseId: ?[]const u8 = null,

        const Candidate = struct {
            content: ?Content = null,
            finishReason: ?[]const u8 = null,
            index: ?usize = null,
        };
        const Content = struct {
            parts: []const Part = &.{},
            role: ?[]const u8 = null,
        };
        const Part = struct {
            text: ?[]const u8 = null,
            inlineData: ?InlineData = null,
            thought: bool = false,
            thoughtSignature: ?[]const u8 = null,
        };
        const InlineData = struct {
            mimeType: ?[]const u8 = null,
            data: ?[]const u8 = null,
        };
        const UsageMetadata = struct {
            promptTokenCount: ?u64 = null,
            candidatesTokenCount: ?u64 = null,
            totalTokenCount: ?u64 = null,
            promptTokensDetails: []const TokenDetail = &.{},
            candidatesTokensDetails: []const TokenDetail = &.{},
            serviceTier: ?[]const u8 = null,
        };
        const TokenDetail = struct {
            modality: ?[]const u8 = null,
            tokenCount: ?u64 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const response_id = parsed.value.responseId orelse return error.MissingResponseId;
    if (response_id.len == 0) return error.MissingResponseId;

    const owned_response_id = try gpa.dupe(u8, response_id);
    errdefer gpa.free(owned_response_id);

    var files: std.ArrayList(GeneratedFile) = .empty;
    errdefer {
        for (files.items) |*file| file.deinit(gpa);
        files.deinit(gpa);
    }

    for (parsed.value.candidates, 0..) |candidate, candidate_index| {
        const content = candidate.content orelse continue;
        for (content.parts, 0..) |part, part_index| {
            if (part.thought) continue;

            var file = (try decodeGeneratedPart(gpa, candidate_index, part_index, part)) orelse continue;
            files.append(gpa, file) catch |err| {
                file.deinit(gpa);
                return err;
            };
        }
    }

    if (files.items.len == 0) return error.NoGeneratedParts;

    return .{
        .response_id = owned_response_id,
        .items = try files.toOwnedSlice(gpa),
    };
}

fn decodeGeneratedPart(
    gpa: std.mem.Allocator,
    candidate_index: usize,
    part_index: usize,
    part: anytype,
) !?GeneratedFile {
    if (part.text != null) return null;

    const inline_payload = part.inlineData orelse return error.UnsupportedPart;
    const mime_name = inline_payload.mimeType orelse return error.MissingMimeType;
    const mime = OutputMime.fromName(mime_name) orelse return error.UnsupportedMime;

    const encoded = inline_payload.data orelse return error.MissingInlineData;
    const decoded_size = try std.base64.standard.Decoder.calcSizeForSlice(encoded);
    const decoded = try gpa.alloc(u8, decoded_size);
    errdefer gpa.free(decoded);

    try std.base64.standard.Decoder.decode(decoded, encoded);

    return .{
        .candidate_index = candidate_index,
        .part_index = part_index,
        .mime = mime,
        .bytes = decoded,
    };
}

/// Formats a generated file's deterministic name into caller-provided storage.
///
/// - Returns a slice borrowed from `buffer`; allocates nothing.
/// - Returns formatting errors such as insufficient buffer space and mutates only the written portion of `buffer`.
pub fn generatedFileName(buffer: []u8, response_id: []const u8, file: GeneratedFile) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{s}-{d}-{d}.{s}",
        .{ response_id, file.candidate_index, file.part_index, file.mime.extension() },
    );
}

test "isCanonicalFileName requires files prefix and id" {
    try std.testing.expect(isCanonicalFileName("files/abc123"));
    try std.testing.expect(!isCanonicalFileName("abc123"));
    try std.testing.expect(!isCanonicalFileName("files/"));
    try std.testing.expect(!isCanonicalFileName(""));
}

test "isCanonicalCachedContentName requires cached contents prefix and id" {
    try std.testing.expect(isCanonicalCachedContentName("cachedContents/abc123"));
    try std.testing.expect(!isCanonicalCachedContentName("abc123"));
    try std.testing.expect(!isCanonicalCachedContentName("cachedContents/"));
    try std.testing.expect(!isCanonicalCachedContentName(""));
}

test "ServiceTier parses and serializes exposed request tiers" {
    try std.testing.expectEqual(ServiceTier.flex, ServiceTier.fromName("flex").?);
    try std.testing.expectEqual(ServiceTier.standard, ServiceTier.fromName("standard").?);
    try std.testing.expectEqual(ServiceTier.priority, ServiceTier.fromName("priority").?);
    try std.testing.expectEqual(@as(?ServiceTier, null), ServiceTier.fromName("unspecified"));
    try std.testing.expectEqualStrings("flex", ServiceTier.flex.apiName());
    try std.testing.expectEqualStrings("standard", ServiceTier.standard.apiName());
    try std.testing.expectEqualStrings("priority", ServiceTier.priority.apiName());
}

test "buildCountTokensRequestFromGenerateContentJson wraps generate content request" {
    const gpa = std.testing.allocator;
    const request = try buildCountTokensRequestFromGenerateContentJson(
        gpa,
        .nano2,
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}]}",
    );
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}]}}",
        request,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateContentRequestJson serializes shared text request" {
    const gpa = std.testing.allocator;
    const parts = [_]GeneratePart{.{ .text = "My fair lady" }};
    const contents = [_]GenerateContent{.{ .parts = &parts }};
    const request = try buildGenerateContentRequestJson(gpa, &contents, .{});
    defer gpa.free(request);

    try std.testing.expectEqualStrings(
        "{\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}],\"generationConfig\":{\"responseModalities\":[\"TEXT\",\"IMAGE\"]}}",
        request,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "buildGenerateContentRequestJson serializes shared request controls" {
    const gpa = std.testing.allocator;
    const parts = [_]GeneratePart{.{ .text = "My fair lady" }};
    const contents = [_]GenerateContent{.{ .parts = &parts }};
    const request = try buildGenerateContentRequestJson(gpa, &contents, .{
        .grounding_options = .{ .web = true },
        .safety_options = .{ .threshold = .block_none },
        .request_options = .{
            .system_instruction = "Use a precise editorial style.",
            .cached_content = "cachedContents/brand",
            .service_tier = .standard,
            .store = true,
        },
    });
    defer gpa.free(request);

    try std.testing.expect(std.mem.indexOf(u8, request, "\"tools\":[{\"google_search\":{}}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"safetySettings\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"systemInstruction\":{\"parts\":[{\"text\":\"Use a precise editorial style.\"}]}") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"cachedContent\":\"cachedContents/brand\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"serviceTier\":\"standard\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"store\":true") != null);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, request, .{});
    defer parsed.deinit();
}

test "generateContent request validation accepts maximum text fields" {
    const max_text = "a" ** max_generate_text_part_bytes;
    const parts = [_]GeneratePart{.{ .text = max_text }};
    const contents = [_]GenerateContent{.{ .parts = &parts }};

    try std.testing.expect(validateGenerateContentRequest(contents[0..], .{
        .system_instruction = max_text,
    }, &.{}).valid());
}

test "generateContent request validation rejects too many contents" {
    const parts = [_]GeneratePart{.{ .text = "x" }};
    const contents = [_]GenerateContent{
        .{ .parts = &parts },
        .{ .parts = &parts },
    };

    try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{}, &.{}).valid());
}

test "generateContent request validation rejects 33 total parts" {
    var parts: [max_generate_request_parts_total]GeneratePart = undefined;
    for (&parts) |*part| {
        part.* = .{ .text = "x" };
    }
    const contents = [_]GenerateContent{.{ .parts = &parts }};

    try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{
        .system_instruction = "system",
    }, &.{}).valid());
}

test "generateContent request validation rejects oversized text part" {
    const too_long_text = "a" ** (max_generate_text_part_bytes + 1);
    const parts = [_]GeneratePart{.{ .text = too_long_text }};
    const contents = [_]GenerateContent{.{ .parts = &parts }};

    try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{}, &.{}).valid());
}

test "generateContent request validation rejects oversized file data fields" {
    const too_long_file_uri = "u" ** (max_generate_file_uri_bytes + 1);
    const too_long_mime_type = "m" ** (max_generate_mime_type_bytes + 1);

    {
        const parts = [_]GeneratePart{.{ .file_data = .{
            .mime_type = "image/jpeg",
            .file_uri = too_long_file_uri,
        } }};
        const contents = [_]GenerateContent{.{ .parts = &parts }};
        try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{}, &.{}).valid());
    }

    {
        const parts = [_]GeneratePart{.{ .file_data = .{
            .mime_type = too_long_mime_type,
            .file_uri = "https://generativelanguage.googleapis.com/v1beta/files/abc123",
        } }};
        const contents = [_]GenerateContent{.{ .parts = &parts }};
        try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{}, &.{}).valid());
    }
}

test "generateContent request validation rejects oversized request field total" {
    const gpa = std.testing.allocator;
    const cached_content = try gpa.alloc(u8, max_generate_request_field_bytes + 1);
    defer gpa.free(cached_content);
    @memcpy(cached_content[0..canonical_cached_content_name_prefix.len], canonical_cached_content_name_prefix);
    @memset(cached_content[canonical_cached_content_name_prefix.len..], 'a');

    const parts = [_]GeneratePart{.{ .text = "x" }};
    const contents = [_]GenerateContent{.{ .parts = &parts }};

    try std.testing.expect(!validateGenerateContentRequest(contents[0..], .{
        .cached_content = cached_content,
    }, &.{}).valid());
}

test "explicit block none safety settings serialize all supported harm categories" {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(safetySettingsFromOptions(.{ .threshold = .block_none }), .{}, &output.writer);
    const json = output.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HARASSMENT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HATE_SPEECH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_SEXUALLY_EXPLICIT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_DANGEROUS_CONTENT\"") != null);
    try std.testing.expectEqual(@as(usize, 4), countOccurrences(json, "\"threshold\":\"BLOCK_NONE\""));
}

test "SafetyOptions parses supported CLI names" {
    try std.testing.expectEqual(HarmBlockThreshold.block_none, SafetyOptions.fromName("none").?.threshold);
    try std.testing.expectEqual(HarmBlockThreshold.off, SafetyOptions.fromName("off").?.threshold);
    try std.testing.expectEqual(HarmBlockThreshold.block_only_high, SafetyOptions.fromName("permissive").?.threshold);
    try std.testing.expectEqual(HarmBlockThreshold.block_medium_and_above, SafetyOptions.fromName("balanced").?.threshold);
    try std.testing.expectEqual(HarmBlockThreshold.block_low_and_above, SafetyOptions.fromName("strict").?.threshold);
    try std.testing.expect(SafetyOptions.fromName("block-none") == null);
    try std.testing.expect(SafetyOptions.fromName("high") == null);
    try std.testing.expect(SafetyOptions.fromName("medium") == null);
    try std.testing.expect(SafetyOptions.fromName("low") == null);
}

test "safetySettingsFromOptions applies one threshold to all supported categories" {
    const gpa = std.testing.allocator;
    const settings = safetySettingsFromOptions(.{ .threshold = .off });

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(settings, .{}, &output.writer);
    const json = output.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HARASSMENT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HATE_SPEECH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_SEXUALLY_EXPLICIT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_DANGEROUS_CONTENT\"") != null);
    try std.testing.expectEqual(@as(usize, 4), countOccurrences(json, "\"threshold\":\"OFF\""));
}

test "default response modalities request text and image output" {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(default_response_modalities, .{}, &output.writer);

    try std.testing.expectEqualStrings("[\"TEXT\",\"IMAGE\"]", output.written());
}

test "responseFormatFromOutputOptions serializes Gemini image response enum names" {
    const gpa = std.testing.allocator;
    const response_format = responseFormatFromOutputOptions(.{
        .aspect_ratio = .r16_9,
        .image_size = .k2,
    }).?;

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(response_format, .{ .emit_null_optional_fields = false }, &output.writer);

    try std.testing.expectEqualStrings(
        "{\"image\":{\"aspectRatio\":\"ASPECT_RATIO_SIXTEEN_BY_NINE\",\"imageSize\":\"IMAGE_SIZE_TWO_K\"}}",
        output.written(),
    );
}

test "ImageMime parses supported API MIME names" {
    try std.testing.expectEqual(ImageMime.jpeg, ImageMime.fromName("image/jpeg").?);
    try std.testing.expectEqual(ImageMime.png, ImageMime.fromName("image/png").?);
    try std.testing.expectEqual(ImageMime.webp, ImageMime.fromName("image/webp").?);
    try std.testing.expectEqual(@as(?ImageMime, null), ImageMime.fromName("image/gif"));
    try std.testing.expectEqualStrings("image/jpeg", ImageMime.jpeg.apiName());
    try std.testing.expectEqualStrings("image/png", ImageMime.png.apiName());
    try std.testing.expectEqualStrings("image/webp", ImageMime.webp.apiName());
}

test "ImageMime detects supported image extensions" {
    try std.testing.expectEqual(ImageMime.jpeg, ImageMime.fromPath("sample_images/good_night.jpeg").?);
    try std.testing.expectEqual(ImageMime.jpeg, ImageMime.fromPath("photo.JPG").?);
    try std.testing.expectEqual(ImageMime.png, ImageMime.fromPath("photo.png").?);
    try std.testing.expectEqual(ImageMime.webp, ImageMime.fromPath("photo.webp").?);
    try std.testing.expectEqual(@as(?ImageMime, null), ImageMime.fromPath("photo.gif"));
}

test "GroundingOptions parses supported CLI names" {
    try std.testing.expect(!GroundingOptions.fromName("none").?.hasAny());
    try std.testing.expect(GroundingOptions.fromName("web").?.web);
    try std.testing.expect(!GroundingOptions.fromName("web").?.image);
    try std.testing.expect(!GroundingOptions.fromName("image").?.web);
    try std.testing.expect(GroundingOptions.fromName("image").?.image);
    try std.testing.expect(GroundingOptions.fromName("web,image").?.web);
    try std.testing.expect(GroundingOptions.fromName("web,image").?.image);
    try std.testing.expectEqual(@as(?GroundingOptions, null), GroundingOptions.fromName("image,web"));
}

test "ThinkingOptions parses and serializes supported CLI levels" {
    try std.testing.expectEqual(ThinkingLevel.minimal, ThinkingLevel.fromName("minimal").?);
    try std.testing.expectEqual(ThinkingLevel.high, ThinkingLevel.fromName("high").?);
    try std.testing.expectEqual(@as(?ThinkingLevel, null), ThinkingLevel.fromName("low"));

    const gpa = std.testing.allocator;
    const thinking_config = thinkingConfigFromOptions(.{
        .level = .minimal,
        .include_thoughts = true,
    }).?;

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(thinking_config, .{ .emit_null_optional_fields = false }, &output.writer);
    try std.testing.expectEqualStrings(
        "{\"thinkingLevel\":\"minimal\",\"includeThoughts\":true}",
        output.written(),
    );
}

test "thinkingConfigFromOptions omits absent thinking fields" {
    const gpa = std.testing.allocator;

    try std.testing.expectEqual(@as(?ThinkingConfig, null), thinkingConfigFromOptions(.{}));

    const level_only = thinkingConfigFromOptions(.{ .level = .high }).?;
    var level_output: std.Io.Writer.Allocating = .init(gpa);
    defer level_output.deinit();
    try std.json.Stringify.value(level_only, .{ .emit_null_optional_fields = false }, &level_output.writer);
    try std.testing.expectEqualStrings("{\"thinkingLevel\":\"high\"}", level_output.written());

    const thoughts_only = thinkingConfigFromOptions(.{ .include_thoughts = true }).?;
    var thoughts_output: std.Io.Writer.Allocating = .init(gpa);
    defer thoughts_output.deinit();
    try std.json.Stringify.value(thoughts_only, .{ .emit_null_optional_fields = false }, &thoughts_output.writer);
    try std.testing.expectEqualStrings("{\"includeThoughts\":true}", thoughts_output.written());
}

test "GenerationOptions tracks optional advanced controls" {
    var options = GenerationOptions{
        .max_output_tokens = 4096,
        .temperature = 0.7,
        .top_p = 0.95,
        .seed = -42,
        .presence_penalty = -1.5,
        .frequency_penalty = 1.25,
        .response_logprobs = true,
        .logprobs = 5,
    };
    options.appendStopSequence("END");
    options.appendStopSequence("STOP");

    assertValidGenerationOptions(options);
    try std.testing.expect(options.hasAny());
    try std.testing.expectEqual(@as(usize, 2), options.stopSequenceSlice().len);
    try std.testing.expectEqualStrings("END", options.stopSequenceSlice()[0]);
    try std.testing.expectEqualStrings("STOP", options.stopSequenceSlice()[1]);
}

test "generationConfigFromOptions serializes advanced generation controls" {
    const gpa = std.testing.allocator;
    var options = GenerationOptions{
        .max_output_tokens = 4096,
        .temperature = 0.7,
        .top_p = 0.95,
        .seed = -42,
        .presence_penalty = -1.5,
        .frequency_penalty = 1.25,
        .response_logprobs = true,
        .logprobs = 5,
    };
    options.appendStopSequence("END");
    options.appendStopSequence("STOP");

    const generation_config = generationConfigFromOptions(.{}, .{}, &options);

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(generation_config, .{ .emit_null_optional_fields = false }, &output.writer);
    const json = output.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"responseModalities\":[\"TEXT\",\"IMAGE\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"maxOutputTokens\":4096") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"temperature\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"topP\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"seed\":-42") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"presencePenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"frequencyPenalty\":") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"responseLogprobs\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"logprobs\":5") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stopSequences\":[\"END\",\"STOP\"]") != null);
}

test "generationConfigFromOptions omits unset advanced controls" {
    const gpa = std.testing.allocator;
    const options: GenerationOptions = .{};
    const generation_config = generationConfigFromOptions(.{}, .{}, &options);

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(generation_config, .{ .emit_null_optional_fields = false }, &output.writer);
    const json = output.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"maxOutputTokens\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"temperature\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"topP\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"seed\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"presencePenalty\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"frequencyPenalty\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"responseLogprobs\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"logprobs\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"stopSequences\"") == null);
}

test "googleSearchToolFromGroundingOptions serializes web search grounding" {
    try expectGroundingToolJson(
        .{ .web = true },
        "{\"google_search\":{}}",
    );
}

test "googleSearchToolFromGroundingOptions serializes image search grounding" {
    try expectGroundingToolJson(
        .{ .image = true },
        "{\"google_search\":{\"searchTypes\":{\"imageSearch\":{}}}}",
    );
}

test "googleSearchToolFromGroundingOptions serializes combined search grounding" {
    try expectGroundingToolJson(
        .{ .web = true, .image = true },
        "{\"google_search\":{\"searchTypes\":{\"webSearch\":{},\"imageSearch\":{}}}}",
    );
}

fn expectGroundingToolJson(options: GroundingOptions, expected_json: []const u8) !void {
    const gpa = std.testing.allocator;
    const tool = googleSearchToolFromGroundingOptions(options).?;

    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(tool, .{ .emit_null_optional_fields = false }, &output.writer);
    try std.testing.expectEqualStrings(expected_json, output.written());
}

test "ImageResponseAspectRatio maps all accepted CLI aspect ratios to Gemini enum names" {
    try expectImageResponseAspectRatio(.r1_1, "\"ASPECT_RATIO_ONE_BY_ONE\"");
    try expectImageResponseAspectRatio(.r1_4, "\"ASPECT_RATIO_ONE_BY_FOUR\"");
    try expectImageResponseAspectRatio(.r1_8, "\"ASPECT_RATIO_ONE_BY_EIGHT\"");
    try expectImageResponseAspectRatio(.r2_3, "\"ASPECT_RATIO_TWO_BY_THREE\"");
    try expectImageResponseAspectRatio(.r3_2, "\"ASPECT_RATIO_THREE_BY_TWO\"");
    try expectImageResponseAspectRatio(.r3_4, "\"ASPECT_RATIO_THREE_BY_FOUR\"");
    try expectImageResponseAspectRatio(.r4_1, "\"ASPECT_RATIO_FOUR_BY_ONE\"");
    try expectImageResponseAspectRatio(.r4_3, "\"ASPECT_RATIO_FOUR_BY_THREE\"");
    try expectImageResponseAspectRatio(.r4_5, "\"ASPECT_RATIO_FOUR_BY_FIVE\"");
    try expectImageResponseAspectRatio(.r5_4, "\"ASPECT_RATIO_FIVE_BY_FOUR\"");
    try expectImageResponseAspectRatio(.r8_1, "\"ASPECT_RATIO_EIGHT_BY_ONE\"");
    try expectImageResponseAspectRatio(.r9_16, "\"ASPECT_RATIO_NINE_BY_SIXTEEN\"");
    try expectImageResponseAspectRatio(.r16_9, "\"ASPECT_RATIO_SIXTEEN_BY_NINE\"");
    try expectImageResponseAspectRatio(.r21_9, "\"ASPECT_RATIO_TWENTY_ONE_BY_NINE\"");
}

test "ImageResponseSize maps all accepted CLI image sizes to Gemini enum names" {
    try expectImageResponseSize(.px512, "\"IMAGE_SIZE_FIVE_TWELVE\"");
    try expectImageResponseSize(.k1, "\"IMAGE_SIZE_ONE_K\"");
    try expectImageResponseSize(.k2, "\"IMAGE_SIZE_TWO_K\"");
    try expectImageResponseSize(.k4, "\"IMAGE_SIZE_FOUR_K\"");
}

test "HarmBlockThreshold serializes all API threshold names" {
    try expectHarmBlockThresholdJson(.block_low_and_above, "\"BLOCK_LOW_AND_ABOVE\"");
    try expectHarmBlockThresholdJson(.block_medium_and_above, "\"BLOCK_MEDIUM_AND_ABOVE\"");
    try expectHarmBlockThresholdJson(.block_only_high, "\"BLOCK_ONLY_HIGH\"");
    try expectHarmBlockThresholdJson(.block_none, "\"BLOCK_NONE\"");
    try expectHarmBlockThresholdJson(.off, "\"OFF\"");
    try expectHarmBlockThresholdJson(.harm_block_threshold_unspecified, "\"HARM_BLOCK_THRESHOLD_UNSPECIFIED\"");
}

test "decodeCountTokensResponse decodes total tokens" {
    const result = try decodeCountTokensResponse(
        std.testing.allocator,
        "{\"totalTokens\":7,\"unknown\":\"ignored\"}",
    );

    try std.testing.expectEqual(@as(u64, 7), result.total_tokens);
    try std.testing.expectEqual(@as(?u64, null), result.cached_content_token_count);
}

test "decodeCountTokensResponse decodes cached content token count" {
    const result = try decodeCountTokensResponse(
        std.testing.allocator,
        "{\"totalTokens\":7,\"cachedContentTokenCount\":3}",
    );

    try std.testing.expectEqual(@as(u64, 7), result.total_tokens);
    try std.testing.expectEqual(@as(?u64, 3), result.cached_content_token_count);
}

test "decodeCountTokensResponse rejects missing total token count" {
    try std.testing.expectError(
        error.MissingTotalTokens,
        decodeCountTokensResponse(std.testing.allocator, "{\"cachedContentTokenCount\":3}"),
    );
}

test "decodeResponseServiceTier decodes usage metadata service tier" {
    const result = try decodeResponseServiceTier(
        std.testing.allocator,
        "{\"usageMetadata\":{\"serviceTier\":\"standard\"}}",
    );

    try std.testing.expectEqual(ServiceTier.standard, result.?);
}

test "decodeResponseServiceTier returns null when usage metadata omits service tier" {
    const result = try decodeResponseServiceTier(
        std.testing.allocator,
        "{\"usageMetadata\":{\"totalTokenCount\":7}}",
    );

    try std.testing.expectEqual(@as(?ServiceTier, null), result);
}

fn expectImageResponseAspectRatio(aspect_ratio: ImageAspectRatio, expected_json: []const u8) !void {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(
        ImageResponseAspectRatio.fromImageAspectRatio(aspect_ratio),
        .{},
        &output.writer,
    );
    try std.testing.expectEqualStrings(expected_json, output.written());
}

fn expectImageResponseSize(image_size: ImageSize, expected_json: []const u8) !void {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(ImageResponseSize.fromImageSize(image_size), .{}, &output.writer);
    try std.testing.expectEqualStrings(expected_json, output.written());
}

fn expectHarmBlockThresholdJson(threshold: HarmBlockThreshold, expected_json: []const u8) !void {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(threshold, .{}, &output.writer);
    try std.testing.expectEqualStrings(expected_json, output.written());
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var count: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, index, needle)) |match_index| {
        count += 1;
        index = match_index + needle.len;
    }
    return count;
}

test "command modules import only shared api module" {
    try expectAllowedCommandModuleImports("src/gen.zig");
    try expectAllowedCommandModuleImports("src/edit.zig");
    try expectAllowedCommandModuleImports("src/files.zig");
    try expectAllowedCommandModuleImports("src/batch.zig");
}

fn expectAllowedCommandModuleImports(path: []const u8) !void {
    const gpa = std.testing.allocator;
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, gpa, .limited(64 * 1024));
    defer gpa.free(source);

    const import_prefix = "@import(\"";
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, source, index, import_prefix)) |import_start| {
        const name_start = import_start + import_prefix.len;
        const name_end_relative = std.mem.indexOfScalar(u8, source[name_start..], '"') orelse {
            std.debug.print("error: malformed import in {s}\n", .{path});
            return error.MalformedImport;
        };
        const name_end = name_start + name_end_relative;
        const name = source[name_start..name_end];

        if (std.mem.endsWith(u8, name, ".zig") and !std.mem.eql(u8, name, "api.zig")) {
            std.debug.print(
                "error: command module {s} imports forbidden local module {s}\n",
                .{ path, name },
            );
            return error.ForbiddenCommandModuleImport;
        }

        index = name_end + 1;
    }
}

const RequestBodyLog = union(enum) {
    empty,
    text: []const u8,
    binary: BinaryRequestBodyLog,
};

const BinaryRequestBodyLog = struct {
    byte_count: usize,
    mime: []const u8,
};

const RequestWithBodyOptions = struct {
    capture_upload_url: bool = false,
    request_body_log: RequestBodyLog = .empty,
};

/// Uploads borrowed bytes through the Gemini resumable upload protocol.
///
/// - Borrows upload fields for the call; the returned response body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, protocol, timeout, or logging errors and creates remote upload state.
pub fn uploadResumableBytes(
    context: *const RequestContext,
    upload: ResumableUpload,
) !HttpResponse {
    assertValidRequestContext(context);
    assert(upload.content_type.len > 0);
    assert(upload.bytes.len > 0);
    if (upload.display_name) |display_name| assert(isValidDisplayName(display_name));

    var client: std.http.Client = .{
        .allocator = context.gpa,
        .io = context.io,
    };
    defer client.deinit();

    var start = try startResumableUpload(context, &client, upload);
    if (start.response.status != .ok) {
        if (start.upload_url) |upload_url| context.gpa.free(upload_url);
        return start.response;
    }
    defer start.response.deinit(context.gpa);

    const upload_url = start.upload_url orelse return error.MissingUploadUrl;
    defer context.gpa.free(upload_url);

    return finalizeResumableUpload(context, &client, upload_url, upload);
}

fn startResumableUpload(
    context: *const RequestContext,
    client: *std.http.Client,
    upload: ResumableUpload,
) !HttpResponseWithUploadUrl {
    assertValidRequestContext(context);
    assert(upload.content_type.len > 0);
    assert(upload.bytes.len > 0);
    if (upload.display_name) |display_name| assert(isValidDisplayName(display_name));

    var content_length_buffer: [32]u8 = undefined;
    const content_length = try std.fmt.bufPrint(&content_length_buffer, "{d}", .{upload.bytes.len});

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = context.api_key },
        .{ .name = "X-Goog-Upload-Protocol", .value = "resumable" },
        .{ .name = "X-Goog-Upload-Command", .value = "start" },
        .{ .name = "X-Goog-Upload-Header-Content-Length", .value = content_length },
        .{ .name = "X-Goog-Upload-Header-Content-Type", .value = upload.content_type },
    };

    const metadata_json = try buildResumableUploadMetadata(context.gpa, upload.display_name);
    defer context.gpa.free(metadata_json);

    return requestWithBody(
        context,
        client,
        .POST,
        fileUploadStartUrl(),
        "application/json",
        &headers,
        metadata_json,
        .{
            .capture_upload_url = true,
            .request_body_log = .{ .text = metadata_json },
        },
    );
}

fn finalizeResumableUpload(
    context: *const RequestContext,
    client: *std.http.Client,
    upload_url: []const u8,
    upload: ResumableUpload,
) !HttpResponse {
    assertValidRequestContext(context);
    assert(upload_url.len > 0);
    assert(upload.content_type.len > 0);
    assert(upload.bytes.len > 0);

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = context.api_key },
        .{ .name = "X-Goog-Upload-Offset", .value = "0" },
        .{ .name = "X-Goog-Upload-Command", .value = "upload, finalize" },
    };

    const result = try requestWithBody(
        context,
        client,
        .POST,
        upload_url,
        upload.content_type,
        &headers,
        upload.bytes,
        .{
            .request_body_log = .{
                .binary = .{
                    .byte_count = upload.bytes.len,
                    .mime = upload.content_type,
                },
            },
        },
    );
    assert(result.upload_url == null);
    return result.response;
}

fn buildResumableUploadMetadata(
    gpa: std.mem.Allocator,
    display_name: ?[]const u8,
) ![]u8 {
    if (display_name) |name| assert(isValidDisplayName(name));

    const FileMetadata = struct {
        displayName: ?[]const u8 = null,
    };
    const UploadStartMetadata = struct {
        file: FileMetadata,
    };

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();
    try std.json.Stringify.value(UploadStartMetadata{
        .file = .{
            .displayName = display_name,
        },
    }, .{ .emit_null_optional_fields = false }, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

test "resumable upload metadata defaults to empty file object" {
    const gpa = std.testing.allocator;
    const metadata = try buildResumableUploadMetadata(gpa, null);
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings("{\"file\":{}}", metadata);

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
}

test "resumable upload metadata includes displayName" {
    const gpa = std.testing.allocator;
    const metadata = try buildResumableUploadMetadata(gpa, "nbimg live api sample");
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"displayName\":\"nbimg live api sample\"}}",
        metadata,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
}

test "resumable upload metadata escapes JSON string content" {
    const gpa = std.testing.allocator;
    const metadata = try buildResumableUploadMetadata(gpa, "quote \" slash \\ newline \n");
    defer gpa.free(metadata);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"displayName\":\"quote \\\" slash \\\\ newline \\n\"}}",
        metadata,
    );

    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, metadata, .{});
    defer parsed.deinit();
}

/// Decodes and copies a canonical file name from an upload response.
///
/// - Borrows `response_json`; the returned slice is owned by `gpa`.
/// - Returns allocation, JSON parsing, or `MissingFileName` errors and mutates no input or global state.
pub fn decodeUploadedFileName(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    const Response = struct {
        file: ?ResponseFile = null,

        const ResponseFile = struct {
            name: ?[]const u8 = null,
        };
    };

    var parsed = try std.json.parseFromSlice(Response, gpa, response_json, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const file = parsed.value.file orelse return error.MissingFileName;
    const name = file.name orelse return error.MissingFileName;
    if (!isCanonicalFileName(name)) return error.MissingFileName;
    return gpa.dupe(u8, name);
}

fn fileUploadStartUrl() []const u8 {
    return "https://generativelanguage.googleapis.com/upload/v1beta/files";
}

/// Sends a JSON POST request and returns an owned response body.
///
/// - Borrows request inputs; the returned body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and may mutate remote service state.
pub fn postJson(
    context: *const RequestContext,
    url: []const u8,
    request_json: []const u8,
) !HttpResponse {
    assertValidRequestContext(context);

    var timed_response = try runRequestWithTimeout(
        context.gpa,
        context.io,
        context.timeout,
        postJsonRaw,
        .{ context, url, request_json },
    );
    errdefer timed_response.response.deinit(context.gpa);

    try logResponseBody(
        context,
        timed_response.response_time_seconds,
        timed_response.response.status,
        timed_response.response.body,
    );
    return timed_response.response;
}

fn postJsonRaw(
    context: *const RequestContext,
    url: []const u8,
    request_json: []const u8,
) !TimedHttpResponse {
    assertValidRequestContext(context);
    assert(url.len > 0);
    assert(request_json.len > 0);

    var client: std.http.Client = .{
        .allocator = context.gpa,
        .io = context.io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = context.api_key },
    };

    const response_buffer = try context.gpa.alloc(u8, max_response_bytes);
    defer context.gpa.free(response_buffer);

    try logRequest(context, url, .{ .text = request_json });

    const started = responseTimerStart(context.io);
    var response_writer: std.Io.Writer = .fixed(response_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = .POST,
        .payload = request_json,
        .headers = .{
            .content_type = .{ .override = "application/json" },
            .user_agent = .{ .override = "nbimg/0.0.0" },
        },
        .extra_headers = &headers,
        .response_writer = &response_writer,
    });

    const response_body = response_writer.buffered();
    const response_time_seconds = roundedResponseTimeSeconds(context.io, started);
    return .{
        .response = .{
            .status = result.status,
            .body = try context.gpa.dupe(u8, response_body),
        },
        .response_time_seconds = response_time_seconds,
    };
}

/// Sends a JSON GET request and returns an owned response body.
///
/// - Borrows request inputs; the returned body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and mutates no input or local global state.
pub fn getJson(
    context: *const RequestContext,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(context, url, .GET);
}

/// Sends a GET request and reads at most the configured number of body bytes.
///
/// - Borrows request inputs; the returned body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, size-limit, or logging errors and mutates no input.
pub fn getBytesBounded(
    context: *const RequestContext,
    url: []const u8,
    max_body_bytes: usize,
) !HttpResponse {
    assertValidRequestContext(context);
    assert(url.len > 0);
    assert(max_body_bytes > 0);

    var timed_response = try runRequestWithTimeout(
        context.gpa,
        context.io,
        context.timeout,
        getBytesBoundedRaw,
        .{ context, url, max_body_bytes },
    );
    errdefer timed_response.response.deinit(context.gpa);

    try logResponseBodyOmitted(
        context,
        timed_response.response_time_seconds,
        timed_response.response.status,
        timed_response.response.body.len,
    );
    return timed_response.response;
}

fn getBytesBoundedRaw(
    context: *const RequestContext,
    url: []const u8,
    max_body_bytes: usize,
) !TimedHttpResponse {
    assertValidRequestContext(context);
    assert(url.len > 0);
    assert(max_body_bytes > 0);

    var client: std.http.Client = .{
        .allocator = context.gpa,
        .io = context.io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = context.api_key },
    };
    const uri = try std.Uri.parse(url);
    var request = try client.request(.GET, uri, .{
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
            .accept_encoding = .{ .override = "identity" },
        },
        .extra_headers = &headers,
    });
    defer request.deinit();

    try logRequest(context, url, .empty);

    const started = responseTimerStart(context.io);
    try request.sendBodiless();

    var redirect_buffer: [8 * 1024]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);
    const status = response.head.status;
    const content_length = response.head.content_length;

    var transfer_buffer: [64 * 1024]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    const body_result = readBoundedBody(
        context.gpa,
        reader,
        content_length,
        max_body_bytes,
    ) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };

    return .{
        .response = .{
            .status = status,
            .body = body_result.bytes,
        },
        .response_time_seconds = roundedResponseTimeSeconds(context.io, started),
    };
}

/// Sends a bodyless POST request and returns an owned response body.
///
/// - Borrows request inputs; the returned body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and may mutate remote service state.
pub fn postJsonWithoutBody(
    context: *const RequestContext,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(context, url, .POST);
}

/// Sends a DELETE request and returns an owned response body.
///
/// - Borrows request inputs; the returned body is owned by `context.gpa` and requires `deinit`.
/// - Returns allocation, I/O, HTTP-client, timeout, or logging errors and mutates remote service state.
pub fn deleteJson(
    context: *const RequestContext,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(context, url, .DELETE);
}

fn requestJsonWithoutBody(
    context: *const RequestContext,
    url: []const u8,
    method: std.http.Method,
) !HttpResponse {
    assertValidRequestContext(context);

    var timed_response = try runRequestWithTimeout(
        context.gpa,
        context.io,
        context.timeout,
        requestJsonWithoutBodyRaw,
        .{ context, url, method },
    );
    errdefer timed_response.response.deinit(context.gpa);

    try logResponseBody(
        context,
        timed_response.response_time_seconds,
        timed_response.response.status,
        timed_response.response.body,
    );
    return timed_response.response;
}

fn requestJsonWithoutBodyRaw(
    context: *const RequestContext,
    url: []const u8,
    method: std.http.Method,
) !TimedHttpResponse {
    assertValidRequestContext(context);
    assert(url.len > 0);

    var client: std.http.Client = .{
        .allocator = context.gpa,
        .io = context.io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = context.api_key },
    };

    const response_buffer = try context.gpa.alloc(u8, max_response_bytes);
    defer context.gpa.free(response_buffer);

    try logRequest(context, url, .empty);

    const started = responseTimerStart(context.io);
    var response_writer: std.Io.Writer = .fixed(response_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .payload = if (method.requestHasBody()) "" else null,
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
        },
        .extra_headers = &headers,
        .response_writer = &response_writer,
    });

    const response_body = response_writer.buffered();
    const response_time_seconds = roundedResponseTimeSeconds(context.io, started);
    return .{
        .response = .{
            .status = result.status,
            .body = try context.gpa.dupe(u8, response_body),
        },
        .response_time_seconds = response_time_seconds,
    };
}

fn requestWithBody(
    context: *const RequestContext,
    client: *std.http.Client,
    method: std.http.Method,
    url: []const u8,
    content_type: []const u8,
    extra_headers: []const std.http.Header,
    body: []const u8,
    options: RequestWithBodyOptions,
) !HttpResponseWithUploadUrl {
    assertValidRequestContext(context);

    var timed_response = try runRequestWithTimeout(
        context.gpa,
        context.io,
        context.timeout,
        requestWithBodyRaw,
        .{ context, client, method, url, content_type, extra_headers, body, options },
    );
    errdefer timed_response.response.deinit(context.gpa);

    try logResponseBody(
        context,
        timed_response.response_time_seconds,
        timed_response.response.response.status,
        timed_response.response.response.body,
    );
    return timed_response.response;
}

fn requestWithBodyRaw(
    context: *const RequestContext,
    client: *std.http.Client,
    method: std.http.Method,
    url: []const u8,
    content_type: []const u8,
    extra_headers: []const std.http.Header,
    body: []const u8,
    options: RequestWithBodyOptions,
) !TimedHttpResponseWithUploadUrl {
    assertValidRequestContext(context);
    assert(url.len > 0);
    assert(content_type.len > 0);
    assert(body.len > 0);

    const uri = try std.Uri.parse(url);
    var req = try client.request(method, uri, .{
        .redirect_behavior = .unhandled,
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
            .accept_encoding = .{ .override = "identity" },
            .content_type = .{ .override = content_type },
        },
        .extra_headers = extra_headers,
    });
    defer req.deinit();

    try logRequest(context, url, options.request_body_log);

    const started = responseTimerStart(context.io);
    req.transfer_encoding = .{ .content_length = body.len };
    var body_writer = try req.sendBodyUnflushed(&.{});
    try body_writer.writer.writeAll(body);
    try body_writer.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});
    const status = response.head.status;

    var upload_url: ?[]u8 = null;
    errdefer if (upload_url) |url_copy| context.gpa.free(url_copy);

    if (options.capture_upload_url) {
        var header_iterator = response.head.iterateHeaders();
        while (header_iterator.next()) |header| {
            if (!std.ascii.eqlIgnoreCase(header.name, "x-goog-upload-url")) continue;
            const value = std.mem.trim(u8, header.value, " \t");
            if (value.len == 0) return error.MissingUploadUrl;
            upload_url = try context.gpa.dupe(u8, value);
            break;
        }
    }

    const response_body = try readHttpBody(context.gpa, &response);
    errdefer context.gpa.free(response_body);

    const response_time_seconds = roundedResponseTimeSeconds(context.io, started);
    return .{
        .response = .{
            .response = .{
                .status = status,
                .body = response_body,
            },
            .upload_url = upload_url,
        },
        .response_time_seconds = response_time_seconds,
    };
}

const TimedHttpResponse = struct {
    response: HttpResponse,
    response_time_seconds: u64,

    fn deinit(response: *TimedHttpResponse, gpa: std.mem.Allocator) void {
        response.response.deinit(gpa);
        response.* = undefined;
    }
};

const TimedHttpResponseWithUploadUrl = struct {
    response: HttpResponseWithUploadUrl,
    response_time_seconds: u64,

    fn deinit(response: *TimedHttpResponseWithUploadUrl, gpa: std.mem.Allocator) void {
        response.response.deinit(gpa);
        response.* = undefined;
    }
};

fn httpTimeoutTask(io: std.Io, timeout: std.Io.Duration) anyerror!void {
    try std.Io.sleep(io, timeout, .awake);
    return error.Timeout;
}

fn runRequestWithTimeout(
    gpa: std.mem.Allocator,
    io: std.Io,
    timeout: std.Io.Duration,
    comptime request_fn: anytype,
    args: std.meta.ArgsTuple(@TypeOf(request_fn)),
) !@typeInfo(@typeInfo(@TypeOf(request_fn)).@"fn".return_type.?).error_union.payload {
    const RequestResult = @typeInfo(@TypeOf(request_fn)).@"fn".return_type.?;
    const TimeoutResult = anyerror!void;
    const SelectResult = union(enum) {
        request: RequestResult,
        timeout: TimeoutResult,
    };

    var select_buffer: [2]SelectResult = undefined;
    var select: std.Io.Select(SelectResult) = .init(io, &select_buffer);

    try select.concurrent(.request, request_fn, args);
    select.concurrent(.timeout, httpTimeoutTask, .{ io, timeout }) catch |err| {
        cancelTimedRequest(gpa, &select);
        return err;
    };

    const first = select.await() catch |err| {
        cancelTimedRequest(gpa, &select);
        return err;
    };

    switch (first) {
        .request => |request_result| {
            const response = request_result catch |err| {
                cancelTimedRequest(gpa, &select);
                return err;
            };
            cancelTimedRequest(gpa, &select);
            return response;
        },
        .timeout => |timeout_result| {
            timeout_result catch |err| {
                cancelTimedRequest(gpa, &select);
                return err;
            };
            unreachable;
        },
    }
}

fn cancelTimedRequest(gpa: std.mem.Allocator, select: anytype) void {
    while (select.cancel()) |result| {
        switch (result) {
            .request => |request_result| {
                if (request_result) |response| {
                    var mutable_response = response;
                    mutable_response.deinit(gpa);
                } else |_| {}
            },
            .timeout => {},
        }
    }
}

fn responseTimerStart(io: std.Io) std.Io.Clock.Timestamp {
    return .now(io, .awake);
}

fn roundedResponseTimeSeconds(io: std.Io, started: std.Io.Clock.Timestamp) u64 {
    const elapsed = started.untilNow(io).raw;
    return roundDurationToSeconds(elapsed);
}

fn roundDurationToSeconds(duration: std.Io.Duration) u64 {
    const half_second_ns: i96 = std.time.ns_per_s / 2;
    const duration_ns = @max(@as(i96, 0), duration.nanoseconds);
    const whole_seconds = @divTrunc(duration_ns, std.time.ns_per_s);
    const remainder_ns = @rem(duration_ns, std.time.ns_per_s);
    const rounded_seconds = whole_seconds + @intFromBool(remainder_ns >= half_second_ns);
    return std.math.cast(u64, rounded_seconds) orelse std.math.maxInt(u64);
}

fn readHttpBody(gpa: std.mem.Allocator, response: *std.http.Client.Response) ![]u8 {
    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    var response_writer: std.Io.Writer = .fixed(response_buffer);
    var transfer_buffer: [64]u8 = undefined;
    const reader = response.reader(&transfer_buffer);
    _ = reader.streamRemaining(&response_writer) catch |err| switch (err) {
        error.ReadFailed => return response.bodyErr().?,
        else => |e| return e,
    };

    return gpa.dupe(u8, response_writer.buffered());
}

const bounded_body_initial_capacity = 16 * 1024;
const bounded_body_read_chunk_bytes = 64 * 1024;

const BoundedBodyRead = struct {
    bytes: []u8,
    peak_capacity: usize,
};

fn readBoundedBody(
    gpa: std.mem.Allocator,
    reader: *std.Io.Reader,
    content_length: ?u64,
    max_body_bytes: usize,
) !BoundedBodyRead {
    assert(max_body_bytes > 0);

    const initial_capacity = if (content_length) |length| initial: {
        if (length > max_body_bytes) return error.ResponseTooLong;
        break :initial @as(usize, @intCast(length));
    } else @min(bounded_body_initial_capacity, max_body_bytes);

    var output = try std.Io.Writer.Allocating.initCapacity(gpa, initial_capacity);
    errdefer output.deinit();
    var peak_capacity = output.writer.buffer.len;
    var read_buffer: [bounded_body_read_chunk_bytes]u8 = undefined;

    while (true) {
        const written_count = output.writer.end;
        const remaining_bytes = max_body_bytes - written_count;
        const read_limit = if (remaining_bytes >= read_buffer.len)
            read_buffer.len
        else
            remaining_bytes + 1;
        const read_count = try reader.readSliceShort(read_buffer[0..read_limit]);
        if (read_count == 0) break;

        if (read_count > remaining_bytes) return error.ResponseTooLong;

        const required_capacity = written_count + read_count;
        if (required_capacity > output.writer.buffer.len) {
            const grown_capacity = std.ArrayList(u8).growCapacity(required_capacity);
            const bounded_capacity = @min(grown_capacity, max_body_bytes);
            assert(bounded_capacity >= required_capacity);
            try output.ensureTotalCapacityPrecise(bounded_capacity);
            peak_capacity = @max(peak_capacity, output.writer.buffer.len);
        }
        try output.writer.writeAll(read_buffer[0..read_count]);

        if (read_count < read_buffer.len) break;
    }

    return .{
        .bytes = try output.toOwnedSlice(),
        .peak_capacity = peak_capacity,
    };
}

test "readBoundedBody accepts known lengths below and at limit" {
    const gpa = std.testing.allocator;

    var below_reader = std.Io.Reader.fixed("abc");
    const below = try readBoundedBody(gpa, &below_reader, 3, 8);
    defer gpa.free(below.bytes);
    try std.testing.expectEqualStrings("abc", below.bytes);
    try std.testing.expectEqual(@as(usize, 3), below.peak_capacity);

    var exact_reader = std.Io.Reader.fixed("12345678");
    const exact = try readBoundedBody(gpa, &exact_reader, 8, 8);
    defer gpa.free(exact.bytes);
    try std.testing.expectEqualStrings("12345678", exact.bytes);
    try std.testing.expectEqual(@as(usize, 8), exact.peak_capacity);
}

test "readBoundedBody rejects oversized known length before allocation" {
    var no_memory: [0]u8 = .{};
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&no_memory);
    var reader = std.Io.Reader.fixed("123456789");

    try std.testing.expectError(
        error.ResponseTooLong,
        readBoundedBody(fixed_allocator.allocator(), &reader, 9, 8),
    );
}

test "readBoundedBody enforces absent content length incrementally" {
    const gpa = std.testing.allocator;

    var below_reader = std.Io.Reader.fixed("small");
    const below = try readBoundedBody(gpa, &below_reader, null, 512 * 1024 * 1024);
    defer gpa.free(below.bytes);
    try std.testing.expectEqualStrings("small", below.bytes);
    try std.testing.expect(below.peak_capacity < 512 * 1024 * 1024);

    var exact_reader = std.Io.Reader.fixed("12345678");
    const exact = try readBoundedBody(gpa, &exact_reader, null, 8);
    defer gpa.free(exact.bytes);
    try std.testing.expectEqualStrings("12345678", exact.bytes);

    var too_long_reader = std.Io.Reader.fixed("123456789");
    try std.testing.expectError(
        error.ResponseTooLong,
        readBoundedBody(gpa, &too_long_reader, null, 8),
    );
}

fn logRequest(context: *const RequestContext, url: []const u8, body: RequestBodyLog) !void {
    if (!context.traffic_log_options.print_request) return;

    try writeStderr(context.io, "--- nbimg api request ---\nurl: ");
    try writeStderr(context.io, url);
    try writeStderr(context.io, "\nbody:\n");
    switch (body) {
        .empty => try writeStderr(context.io, "<none>\n"),
        .text => |text| {
            try writeStderr(context.io, text);
            try writeStderr(context.io, "\n");
        },
        .binary => |binary| try writeStderrFormat(
            context.io,
            "<binary omitted: {d} bytes; mime: {s}>\n",
            .{ binary.byte_count, binary.mime },
        ),
    }
}

fn logResponseBody(
    context: *const RequestContext,
    response_time_seconds: u64,
    status: std.http.Status,
    response_body: []const u8,
) !void {
    if (!context.traffic_log_options.print_response) return;

    var response_log_header_buffer: [128]u8 = undefined;
    try writeStderr(context.io, responseLogHeader(&response_log_header_buffer, response_time_seconds, status));
    if (response_body.len == 0) {
        try writeStderr(context.io, "<empty>\n");
        return;
    }

    const log_body = sanitizeResponseLogBody(context.gpa, response_body) catch |err| {
        try writeStderrFormat(
            context.io,
            "<response body omitted: {d} bytes; failed to sanitize JSON: {s}>\n",
            .{ response_body.len, @errorName(err) },
        );
        return;
    };
    defer context.gpa.free(log_body);
    try writeStderr(context.io, log_body);
    try writeStderr(context.io, "\n");
}

fn logResponseBodyOmitted(
    context: *const RequestContext,
    response_time_seconds: u64,
    status: std.http.Status,
    body_bytes: usize,
) !void {
    if (!context.traffic_log_options.print_response) return;

    var response_log_header_buffer: [128]u8 = undefined;
    try writeStderr(context.io, responseLogHeader(&response_log_header_buffer, response_time_seconds, status));
    try writeStderrFormat(context.io, "<download body omitted: {d} bytes>\n", .{body_bytes});
}

fn responseLogHeader(
    buffer: []u8,
    response_time_seconds: u64,
    status: std.http.Status,
) []const u8 {
    return std.fmt.bufPrint(
        buffer,
        "--- nbimg api response ---\nresponse_time_seconds: {d}\nstatus: {d}\nbody:\n",
        .{ response_time_seconds, @intFromEnum(status) },
    ) catch unreachable;
}

fn writeStderr(io: std.Io, bytes: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, bytes);
}

fn writeStderrFormat(io: std.Io, comptime format: []const u8, args: anytype) !void {
    var buffer: [512]u8 = undefined;
    const bytes = try std.fmt.bufPrint(&buffer, format, args);
    try writeStderr(io, bytes);
}

fn sanitizeResponseLogBody(gpa: std.mem.Allocator, response_json: []const u8) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, gpa, response_json, .{});
    defer parsed.deinit();

    try redactKnownResponseFields(parsed.arena.allocator(), &parsed.value);

    var output: std.Io.Writer.Allocating = .init(gpa);
    errdefer output.deinit();

    try std.json.Stringify.value(parsed.value, .{}, &output.writer);

    var list = output.toArrayList();
    errdefer list.deinit(gpa);
    return list.toOwnedSlice(gpa);
}

fn redactKnownResponseFields(arena: std.mem.Allocator, root: *std.json.Value) !void {
    switch (root.*) {
        .object => |*object| {
            if (object.getPtr("candidates")) |candidates| {
                try redactCandidateArray(arena, candidates);
            }
        },
        else => return,
    }
}

fn redactCandidateArray(arena: std.mem.Allocator, candidates: *std.json.Value) !void {
    switch (candidates.*) {
        .array => |*array| {
            for (array.items) |*candidate| {
                try redactCandidate(arena, candidate);
            }
        },
        else => return,
    }
}

fn redactCandidate(arena: std.mem.Allocator, candidate: *std.json.Value) !void {
    switch (candidate.*) {
        .object => |*object| {
            const content = object.getPtr("content") orelse return;
            try redactContent(arena, content);
        },
        else => return,
    }
}

fn redactContent(arena: std.mem.Allocator, content: *std.json.Value) !void {
    switch (content.*) {
        .object => |*object| {
            const parts = object.getPtr("parts") orelse return;
            try redactPartArray(arena, parts);
        },
        else => return,
    }
}

fn redactPartArray(arena: std.mem.Allocator, parts: *std.json.Value) !void {
    switch (parts.*) {
        .array => |*array| {
            for (array.items) |*part| {
                try redactPart(arena, part);
            }
        },
        else => return,
    }
}

fn redactPart(arena: std.mem.Allocator, part: *std.json.Value) !void {
    switch (part.*) {
        .object => |*object| {
            if (object.getPtr("inlineData")) |inline_payload| {
                try redactInlineData(arena, inline_payload);
            }
            if (object.getPtr("thoughtSignature")) |thought_signature| {
                try redactBase64StringValue(arena, thought_signature);
            }
        },
        else => return,
    }
}

fn redactInlineData(arena: std.mem.Allocator, inline_payload: *std.json.Value) !void {
    switch (inline_payload.*) {
        .object => |*object| {
            const data = object.getPtr("data") orelse return;
            try redactBase64StringValue(arena, data);
        },
        else => return,
    }
}

fn redactBase64StringValue(arena: std.mem.Allocator, value: *std.json.Value) !void {
    switch (value.*) {
        .string => |encoded| {
            value.* = .{ .string = try base64OmissionLabel(arena, encoded) };
        },
        else => return,
    }
}

fn base64OmissionLabel(arena: std.mem.Allocator, encoded: []const u8) ![]const u8 {
    const decoded_size = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch {
        return std.fmt.allocPrint(
            arena,
            "<base64 omitted: invalid base64, {d} encoded bytes>",
            .{encoded.len},
        );
    };

    return std.fmt.allocPrint(
        arena,
        "<base64 omitted: {d} decoded bytes>",
        .{decoded_size},
    );
}

test "apiKeyFromMap returns borrowed API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api_key_env_name, "test-key");

    const api_key = try apiKeyFromMap(&environ_map);
    try std.testing.expectEqualStrings("test-key", api_key);
}

test "apiKeyFromMap rejects missing API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try std.testing.expectError(error.MissingApiKey, apiKeyFromMap(&environ_map));
}

test "apiKeyFromMap rejects empty API key" {
    var environ_map = std.process.Environ.Map.init(std.testing.allocator);
    defer environ_map.deinit();

    try environ_map.put(api_key_env_name, "");

    try std.testing.expectError(error.EmptyApiKey, apiKeyFromMap(&environ_map));
}

test "responseLogHeader prints response time before status" {
    var buffer: [128]u8 = undefined;
    const header = responseLogHeader(&buffer, 12, .ok);

    try std.testing.expectEqualStrings(
        "--- nbimg api response ---\nresponse_time_seconds: 12\nstatus: 200\nbody:\n",
        header,
    );
}

test "roundDurationToSeconds rounds to nearest whole second" {
    try std.testing.expectEqual(@as(u64, 0), roundDurationToSeconds(.fromMilliseconds(499)));
    try std.testing.expectEqual(@as(u64, 1), roundDurationToSeconds(.fromMilliseconds(500)));
    try std.testing.expectEqual(@as(u64, 1), roundDurationToSeconds(.fromMilliseconds(1499)));
    try std.testing.expectEqual(@as(u64, 2), roundDurationToSeconds(.fromMilliseconds(1500)));
}

fn testImmediateTimedResponse(gpa: std.mem.Allocator) !TimedHttpResponse {
    return .{
        .response = .{
            .status = .ok,
            .body = try gpa.dupe(u8, "{}"),
        },
        .response_time_seconds = 0,
    };
}

fn testSleepingTimedResponse(gpa: std.mem.Allocator, io: std.Io) !TimedHttpResponse {
    try std.Io.sleep(io, .fromSeconds(60), .awake);
    return .{
        .response = .{
            .status = .ok,
            .body = try gpa.dupe(u8, "{}"),
        },
        .response_time_seconds = 60,
    };
}

fn testLateTimedResponse(gpa: std.mem.Allocator, io: std.Io) !TimedHttpResponse {
    const started = responseTimerStart(io);
    while (started.untilNow(io).raw.nanoseconds < 20 * std.time.ns_per_ms) {}

    return .{
        .response = .{
            .status = .ok,
            .body = try gpa.dupe(u8, "{}"),
        },
        .response_time_seconds = 0,
    };
}

test "runRequestWithTimeout returns response before timeout" {
    const gpa = std.testing.allocator;
    var response = try runRequestWithTimeout(
        gpa,
        std.testing.io,
        .fromSeconds(1),
        testImmediateTimedResponse,
        .{gpa},
    );
    defer response.deinit(gpa);

    try std.testing.expectEqual(std.http.Status.ok, response.response.status);
    try std.testing.expectEqualStrings("{}", response.response.body);
}

test "runRequestWithTimeout returns timeout before response" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.Timeout,
        runRequestWithTimeout(
            gpa,
            std.testing.io,
            .fromMilliseconds(1),
            testSleepingTimedResponse,
            .{ gpa, std.testing.io },
        ),
    );
}

test "runRequestWithTimeout deinitializes late response" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(
        error.Timeout,
        runRequestWithTimeout(
            gpa,
            std.testing.io,
            .fromMilliseconds(1),
            testLateTimedResponse,
            .{ gpa, std.testing.io },
        ),
    );
}

fn listenLocalHttp(io: std.Io) !std.Io.net.Server {
    const address = try std.Io.net.IpAddress.parse("127.0.0.1", 0);
    return address.listen(io, .{
        .kernel_backlog = 1,
        .reuse_address = true,
    });
}

fn localHttpUrl(buffer: []u8, server: *const std.Io.net.Server) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "http://127.0.0.1:{d}/test",
        .{server.socket.address.getPort()},
    );
}

fn acceptAndWriteHttpResponse(io: std.Io, server: *std.Io.net.Server) !void {
    var stream = try server.accept(io);
    defer stream.close(io);

    var write_buffer: [256]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);
    try writer.interface.writeAll(
        "HTTP/1.1 200 OK\r\n" ++
            "content-length: 2\r\n" ++
            "connection: close\r\n" ++
            "\r\n" ++
            "{}",
    );
    try writer.interface.flush();
}

fn acceptAndStaySilent(io: std.Io, server: *std.Io.net.Server) !void {
    var stream = try server.accept(io);
    defer stream.close(io);

    try std.Io.sleep(io, .fromSeconds(4), .awake);
}

fn cancelServerFuture(io: std.Io, future: anytype) void {
    future.cancel(io) catch |err| switch (err) {
        error.Canceled => {},
        else => {},
    };
}

test "runRequestWithTimeout completes against local HTTP response" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const context = RequestContext{
        .gpa = gpa,
        .io = io,
        .api_key = "test-key",
        .timeout = .fromSeconds(2),
    };

    var server = try listenLocalHttp(io);
    defer server.deinit(io);

    var server_future = try io.concurrent(acceptAndWriteHttpResponse, .{ io, &server });
    defer cancelServerFuture(io, &server_future);

    var url_buffer: [128]u8 = undefined;
    const url = try localHttpUrl(&url_buffer, &server);

    var response = try runRequestWithTimeout(
        gpa,
        io,
        context.timeout,
        postJsonRaw,
        .{ &context, url, "{}" },
    );
    defer response.deinit(gpa);

    try server_future.await(io);
    try std.testing.expectEqual(std.http.Status.ok, response.response.status);
    try std.testing.expectEqualStrings("{}", response.response.body);
}

test "postJsonWithoutBody sends zero-length POST payload" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const context = RequestContext{
        .gpa = gpa,
        .io = io,
        .api_key = "test-key",
    };

    var server = try listenLocalHttp(io);
    defer server.deinit(io);

    var server_future = try io.concurrent(acceptAndWriteHttpResponse, .{ io, &server });
    defer cancelServerFuture(io, &server_future);

    var url_buffer: [128]u8 = undefined;
    const url = try localHttpUrl(&url_buffer, &server);

    var response = try postJsonWithoutBody(&context, url);
    defer response.deinit(gpa);

    try server_future.await(io);
    try std.testing.expectEqual(std.http.Status.ok, response.status);
    try std.testing.expectEqualStrings("{}", response.body);
}

test "runRequestWithTimeout times out against silent local HTTP connection" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const context = RequestContext{
        .gpa = gpa,
        .io = io,
        .api_key = "test-key",
        .timeout = .fromMilliseconds(100),
    };

    var server = try listenLocalHttp(io);
    defer server.deinit(io);

    var server_future = try io.concurrent(acceptAndStaySilent, .{ io, &server });
    defer cancelServerFuture(io, &server_future);

    var url_buffer: [128]u8 = undefined;
    const url = try localHttpUrl(&url_buffer, &server);

    try std.testing.expectError(
        error.Timeout,
        runRequestWithTimeout(
            gpa,
            io,
            context.timeout,
            postJsonRaw,
            .{ &context, url, "{}" },
        ),
    );
}

test "request contexts keep independent timeout and traffic logging options" {
    const quiet = RequestContext{
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .api_key = "quiet-key",
        .timeout = .fromMilliseconds(100),
    };
    const verbose = RequestContext{
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .api_key = "verbose-key",
        .traffic_log_options = .{
            .print_request = true,
            .print_response = true,
        },
    };

    try std.testing.expectEqual(@as(i64, 100), quiet.timeout.toMilliseconds());
    try std.testing.expect(!quiet.traffic_log_options.print_request);
    try std.testing.expect(!quiet.traffic_log_options.print_response);
    try std.testing.expectEqual(@as(i64, 180), verbose.timeout.toSeconds());
    try std.testing.expect(verbose.traffic_log_options.print_request);
    try std.testing.expect(verbose.traffic_log_options.print_response);
}

test "sanitizeResponseLogBody redacts inlineData data" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AQID\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"<base64 omitted: 3 decoded bytes>\"}}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts multiple known data fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"AQID\"}},{\"inlineData\":{\"data\":\"AQIDBA==\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: 3 decoded bytes>\"}},{\"inlineData\":{\"data\":\"<base64 omitted: 4 decoded bytes>\"}}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts thoughtSignature" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"thoughtSignature\":\"AQID\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"thoughtSignature\":\"<base64 omitted: 3 decoded bytes>\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts inline data and thought signature" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"AQID\"},\"thoughtSignature\":\"AQIDBA==\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: 3 decoded bytes>\"},\"thoughtSignature\":\"<base64 omitted: 4 decoded bytes>\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated data fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"data\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"data\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated thoughtSignature fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"thoughtSignature\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"thoughtSignature\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves uploaded file sha256Hash" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"file\":{\"name\":\"files/abc\",\"sha256Hash\":\"AQIDBA==\"}}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"file\":{\"name\":\"files/abc\",\"sha256Hash\":\"AQIDBA==\"}}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves listed file sha256Hash" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"files\":[{\"name\":\"files/abc\",\"sha256Hash\":\"AQID\"}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"files\":[{\"name\":\"files/abc\",\"sha256Hash\":\"AQID\"}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody preserves unrelated sha256Hash fields" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"sha256Hash\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"sha256Hash\":\"AQID\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"My fair lady\"}]}}]}",
        sanitized,
    );
}

test "sanitizeResponseLogBody redacts invalid base64 data" {
    const gpa = std.testing.allocator;
    const sanitized = try sanitizeResponseLogBody(
        gpa,
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"not_base64\"}}]}}]}",
    );
    defer gpa.free(sanitized);

    try std.testing.expectEqualStrings(
        "{\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"data\":\"<base64 omitted: invalid base64, 10 encoded bytes>\"}}]}}]}",
        sanitized,
    );
}

test "decodeGeneratedFiles decodes image and skips text parts" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "responseId": "test-response",
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [
        \\        {"inlineData": {"mimeType": "image/png", "data": "AQID"}},
        \\        {"text": "hello"}
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    var files = try decodeGeneratedFiles(gpa, json);
    defer files.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), files.items.len);
    try std.testing.expectEqualStrings("test-response", files.response_id);
    try std.testing.expectEqual(OutputMime.png, files.items[0].mime);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, files.items[0].bytes);
}

test "decodeGeneratedFiles rejects text-only response" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "responseId": "test-response",
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [
        \\        {"text": "hello"}
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    try std.testing.expectError(error.NoGeneratedParts, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles skips thought parts and decodes final images" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "responseId": "test-response",
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [
        \\        {"text": "planning", "thought": true},
        \\        {"inlineData": {}, "thought": true},
        \\        {"inlineData": {"mimeType": "image/png", "data": "BAUG"}}
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    var files = try decodeGeneratedFiles(gpa, json);
    defer files.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), files.items.len);
    try std.testing.expectEqual(OutputMime.png, files.items[0].mime);
    try std.testing.expectEqualSlices(u8, &.{ 4, 5, 6 }, files.items[0].bytes);
}

test "decodeGeneratedFiles rejects response with only thought parts" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "responseId": "test-response",
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [
        \\        {"text": "planning", "thought": true},
        \\        {"inlineData": {"mimeType": "image/jpeg", "data": "AQID"}, "thought": true}
        \\      ]
        \\    }
        \\  }]
        \\}
    ;

    try std.testing.expectError(error.NoGeneratedParts, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles accepts observed Gemini image response shape" {
    const gpa = std.testing.allocator;
    const json =
        \\{
        \\  "candidates": [{
        \\    "content": {
        \\      "parts": [{
        \\        "inlineData": {
        \\          "mimeType": "image/jpeg",
        \\          "data": "AQID"
        \\        },
        \\        "thoughtSignature": "AQIDBA=="
        \\      }],
        \\      "role": "model"
        \\    },
        \\    "finishReason": "STOP",
        \\    "index": 0
        \\  }],
        \\  "usageMetadata": {
        \\    "promptTokenCount": 7,
        \\    "candidatesTokenCount": 1588,
        \\    "totalTokenCount": 1595,
        \\    "promptTokensDetails": [{
        \\      "modality": "TEXT",
        \\      "tokenCount": 7
        \\    }],
        \\    "candidatesTokensDetails": [{
        \\      "modality": "IMAGE",
        \\      "tokenCount": 1120
        \\    }],
        \\    "serviceTier": "standard"
        \\  },
        \\  "modelVersion": "gemini-3.1-flash-image-preview",
        \\  "responseId": "PMMIapvKNtLj_uMPq8a8oQs"
        \\}
    ;

    var files = try decodeGeneratedFiles(gpa, json);
    defer files.deinit(gpa);

    try std.testing.expectEqual(@as(usize, 1), files.items.len);
    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs", files.response_id);
    try std.testing.expectEqual(OutputMime.jpeg, files.items[0].mime);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, files.items[0].bytes);
}

test "decodeGeneratedFiles rejects generated output missing response id" {
    const gpa = std.testing.allocator;
    const json =
        \\{"candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingResponseId, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects generated output empty response id" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingResponseId, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects empty candidate output" {
    const gpa = std.testing.allocator;
    try std.testing.expectError(error.NoGeneratedParts, decodeGeneratedFiles(gpa, "{\"responseId\":\"test-response\",\"candidates\":[]}"));
}

test "decodeGeneratedFiles rejects unknown image MIME" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/gif","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.UnsupportedMime, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects text plain inline MIME" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"text/plain","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.UnsupportedMime, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles rejects snake case MIME type field" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mime_type":"image/png","data":"AQID"}}]}}]}
    ;

    try std.testing.expectError(error.MissingMimeType, decodeGeneratedFiles(gpa, json));
}

test "decodeGeneratedFiles cleans up partial output on later part failure" {
    const gpa = std.testing.allocator;
    const json =
        \\{"responseId":"test-response","candidates":[{"content":{"parts":[{"inlineData":{"mimeType":"image/png","data":"AQID"}},{}]}}]}
    ;

    try std.testing.expectError(error.UnsupportedPart, decodeGeneratedFiles(gpa, json));
}

test "generatedFileName uses response id candidate part template" {
    const file = GeneratedFile{
        .candidate_index = 12,
        .part_index = 3,
        .mime = .webp,
        .bytes = @constCast("x"),
    };
    var buffer: [64]u8 = undefined;
    const name = try generatedFileName(&buffer, "PMMIapvKNtLj_uMPq8a8oQs", file);
    try std.testing.expectEqualStrings("PMMIapvKNtLj_uMPq8a8oQs-12-3.webp", name);
}
