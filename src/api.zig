//! Shared Gemini API model constants, transport, and traffic logging.

const std = @import("std");
const assert = std.debug.assert;

pub const max_response_bytes = 64 * 1024 * 1024;
pub const api_key_env_name = "GEMINI_API_KEY";
pub const canonical_file_name_prefix = "files/";
pub const canonical_cached_content_name_prefix = "cachedContents/";

pub const ApiKeyError = error{
    MissingApiKey,
    EmptyApiKey,
};

pub const Model = enum {
    nano2,

    pub fn apiName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "gemini-3.1-flash-image-preview",
        };
    }

    pub fn resourceName(model: Model) []const u8 {
        return switch (model) {
            .nano2 => "models/gemini-3.1-flash-image-preview",
        };
    }
};

pub const ResponseModality = enum {
    text,
    image,

    pub fn apiName(modality: ResponseModality) []const u8 {
        return switch (modality) {
            .text => "TEXT",
            .image => "IMAGE",
        };
    }

    pub fn jsonStringify(modality: ResponseModality, writer: anytype) !void {
        try writer.write(modality.apiName());
    }
};

pub const default_response_modalities = [_]ResponseModality{ .text, .image };

pub const TextPart = struct {
    text: []const u8,
};

pub const TextContent = struct {
    parts: []const TextPart,
};

pub const GenerateFileData = struct {
    mime_type: []const u8,
    file_uri: []const u8,
};

pub const GeneratePart = struct {
    text: ?[]const u8 = null,
    file_data: ?GenerateFileData = null,
};

pub const GenerateContent = struct {
    parts: []const GeneratePart,
};

pub const ServiceTier = enum {
    flex,
    standard,
    priority,

    pub fn fromName(name: []const u8) ?ServiceTier {
        if (std.mem.eql(u8, name, "flex")) return .flex;
        if (std.mem.eql(u8, name, "standard")) return .standard;
        if (std.mem.eql(u8, name, "priority")) return .priority;
        return null;
    }

    pub fn apiName(service_tier: ServiceTier) []const u8 {
        return switch (service_tier) {
            .flex => "flex",
            .standard => "standard",
            .priority => "priority",
        };
    }

    pub fn jsonStringify(service_tier: ServiceTier, writer: anytype) !void {
        try writer.write(service_tier.apiName());
    }
};

pub const RequestOptions = struct {
    system_instruction: ?[]const u8 = null,
    cached_content: ?[]const u8 = null,
    service_tier: ?ServiceTier = null,
    store: ?bool = null,

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

    pub fn apiName(aspect_ratio: ImageAspectRatio) []const u8 {
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

    pub fn jsonStringify(aspect_ratio: ImageAspectRatio, writer: anytype) !void {
        try writer.write(aspect_ratio.apiName());
    }
};

pub const ImageSize = enum {
    px512,
    k1,
    k2,
    k4,

    pub fn fromName(name: []const u8) ?ImageSize {
        if (std.mem.eql(u8, name, "512")) return .px512;
        if (std.mem.eql(u8, name, "1K")) return .k1;
        if (std.mem.eql(u8, name, "2K")) return .k2;
        if (std.mem.eql(u8, name, "4K")) return .k4;
        return null;
    }

    pub fn apiName(image_size: ImageSize) []const u8 {
        return switch (image_size) {
            .px512 => "512",
            .k1 => "1K",
            .k2 => "2K",
            .k4 => "4K",
        };
    }

    pub fn jsonStringify(image_size: ImageSize, writer: anytype) !void {
        try writer.write(image_size.apiName());
    }
};

pub const ImageOutputOptions = struct {
    aspect_ratio: ?ImageAspectRatio = null,
    image_size: ?ImageSize = null,

    pub fn hasAny(options: ImageOutputOptions) bool {
        return options.aspect_ratio != null or options.image_size != null;
    }
};

pub const GroundingOptions = struct {
    web: bool = false,
    image: bool = false,

    pub fn hasAny(options: GroundingOptions) bool {
        return options.web or options.image;
    }

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

    pub fn fromName(name: []const u8) ?ThinkingLevel {
        if (std.mem.eql(u8, name, "minimal")) return .minimal;
        if (std.mem.eql(u8, name, "high")) return .high;
        return null;
    }

    pub fn apiName(level: ThinkingLevel) []const u8 {
        return switch (level) {
            .minimal => "minimal",
            .high => "high",
        };
    }

    pub fn jsonStringify(level: ThinkingLevel, writer: anytype) !void {
        try writer.write(level.apiName());
    }
};

pub const ThinkingOptions = struct {
    level: ?ThinkingLevel = null,
    include_thoughts: bool = false,

    pub fn hasAny(options: ThinkingOptions) bool {
        return options.level != null or options.include_thoughts;
    }
};

pub const ThinkingConfig = struct {
    thinkingLevel: ?ThinkingLevel = null,
    includeThoughts: ?bool = null,
};

pub const max_stop_sequences = 5;
pub const max_output_tokens = 32768;

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

    pub fn stopSequenceSlice(options: *const GenerationOptions) []const []const u8 {
        assert(options.stop_sequence_count <= max_stop_sequences);
        return options.stop_sequences[0..options.stop_sequence_count];
    }

    pub fn appendStopSequence(options: *GenerationOptions, value: []const u8) void {
        assert(value.len > 0);
        assert(options.stop_sequence_count < max_stop_sequences);

        options.stop_sequences[options.stop_sequence_count] = value;
        options.stop_sequence_count += 1;
    }
};

pub const GenerationConfig = struct {
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

pub fn thinkingConfigFromOptions(options: ThinkingOptions) ?ThinkingConfig {
    if (!options.hasAny()) return null;
    return .{
        .thinkingLevel = options.level,
        .includeThoughts = if (options.include_thoughts) true else null,
    };
}

pub fn generationConfigFromOptions(
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

pub fn assertValidRequestOptions(options: RequestOptions) void {
    if (options.system_instruction) |system_instruction| {
        assert(system_instruction.len > 0);
    }

    if (options.cached_content) |cached_content| {
        assert(isCanonicalCachedContentName(cached_content));
    }
}

pub const SearchType = struct {};

pub const SearchTypes = struct {
    webSearch: ?SearchType = null,
    imageSearch: ?SearchType = null,
};

pub const GoogleSearch = struct {
    searchTypes: ?SearchTypes = null,
};

pub const Tool = struct {
    google_search: GoogleSearch,
};

pub fn googleSearchToolFromGroundingOptions(options: GroundingOptions) ?Tool {
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

pub fn buildGenerateContentRequestJson(
    gpa: std.mem.Allocator,
    contents: []const GenerateContent,
    options: GenerateContentRequestOptions,
) ![]u8 {
    assertValidGenerateContents(contents);
    assertValidRequestOptions(options.request_options);

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

fn assertValidGenerateContents(contents: []const GenerateContent) void {
    assert(contents.len > 0);

    for (contents) |content| {
        assert(content.parts.len > 0);

        for (content.parts) |part| {
            assert((part.text != null) != (part.file_data != null));

            if (part.text) |text| {
                assert(text.len > 0);
            }

            if (part.file_data) |file_data| {
                assert(file_data.mime_type.len > 0);
                assert(file_data.file_uri.len > 0);
            }
        }
    }
}

pub const ResponseFormatConfig = struct {
    image: ?ImageResponseFormat = null,
};

pub const ImageResponseFormat = struct {
    aspectRatio: ?ImageResponseAspectRatio = null,
    imageSize: ?ImageResponseSize = null,
};

pub const ImageResponseAspectRatio = enum {
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

    pub fn fromImageAspectRatio(aspect_ratio: ImageAspectRatio) ImageResponseAspectRatio {
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

    pub fn apiName(aspect_ratio: ImageResponseAspectRatio) []const u8 {
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

pub const ImageResponseSize = enum {
    five_twelve,
    one_k,
    two_k,
    four_k,

    pub fn fromImageSize(image_size: ImageSize) ImageResponseSize {
        return switch (image_size) {
            .px512 => .five_twelve,
            .k1 => .one_k,
            .k2 => .two_k,
            .k4 => .four_k,
        };
    }

    pub fn apiName(image_size: ImageResponseSize) []const u8 {
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

pub fn responseFormatFromOutputOptions(options: ImageOutputOptions) ?ResponseFormatConfig {
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

pub const HarmCategory = enum {
    harassment,
    hate_speech,
    sexually_explicit,
    dangerous_content,

    pub fn apiName(category: HarmCategory) []const u8 {
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

    pub fn apiName(threshold: HarmBlockThreshold) []const u8 {
        return switch (threshold) {
            .block_low_and_above => "BLOCK_LOW_AND_ABOVE",
            .block_medium_and_above => "BLOCK_MEDIUM_AND_ABOVE",
            .block_only_high => "BLOCK_ONLY_HIGH",
            .block_none => "BLOCK_NONE",
            .off => "OFF",
            .harm_block_threshold_unspecified => "HARM_BLOCK_THRESHOLD_UNSPECIFIED",
        };
    }

    pub fn jsonStringify(threshold: HarmBlockThreshold, writer: anytype) !void {
        try writer.write(threshold.apiName());
    }
};

pub const SafetySetting = struct {
    category: HarmCategory,
    threshold: HarmBlockThreshold,
};

pub const SafetyOptions = struct {
    threshold: HarmBlockThreshold = .block_none,

    pub fn fromName(name: []const u8) ?SafetyOptions {
        if (std.mem.eql(u8, name, "none")) return .{ .threshold = .block_none };
        if (std.mem.eql(u8, name, "off")) return .{ .threshold = .off };
        if (std.mem.eql(u8, name, "permissive")) return .{ .threshold = .block_only_high };
        if (std.mem.eql(u8, name, "balanced")) return .{ .threshold = .block_medium_and_above };
        if (std.mem.eql(u8, name, "strict")) return .{ .threshold = .block_low_and_above };
        return null;
    }
};

pub const supported_harm_categories = [_]HarmCategory{
    .harassment,
    .hate_speech,
    .sexually_explicit,
    .dangerous_content,
};

pub fn safetySettingsFromOptions(options: SafetyOptions) [supported_harm_categories.len]SafetySetting {
    var settings: [supported_harm_categories.len]SafetySetting = undefined;

    for (supported_harm_categories, 0..) |category, index| {
        settings[index] = .{
            .category = category,
            .threshold = options.threshold,
        };
    }

    return settings;
}

pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
};

pub const ImageMime = enum {
    jpeg,
    png,
    webp,

    pub fn fromName(name: []const u8) ?ImageMime {
        if (std.mem.eql(u8, name, "image/jpeg")) return .jpeg;
        if (std.mem.eql(u8, name, "image/png")) return .png;
        if (std.mem.eql(u8, name, "image/webp")) return .webp;
        return null;
    }

    pub fn fromPath(path: []const u8) ?ImageMime {
        const extension = std.fs.path.extension(path);
        if (std.ascii.eqlIgnoreCase(extension, ".jpg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".jpeg")) return .jpeg;
        if (std.ascii.eqlIgnoreCase(extension, ".png")) return .png;
        if (std.ascii.eqlIgnoreCase(extension, ".webp")) return .webp;
        return null;
    }

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

    pub fn fromName(name: []const u8) ?OutputMime {
        if (std.mem.eql(u8, name, "image/png")) return .png;
        if (std.mem.eql(u8, name, "image/jpeg")) return .jpeg;
        if (std.mem.eql(u8, name, "image/webp")) return .webp;
        return null;
    }

    pub fn extension(mime: OutputMime) []const u8 {
        return switch (mime) {
            .png => "png",
            .jpeg => "jpg",
            .webp => "webp",
        };
    }
};

pub const GeneratedFile = struct {
    candidate_index: usize,
    part_index: usize,
    mime: OutputMime,
    bytes: []u8,

    pub fn deinit(file: *GeneratedFile, gpa: std.mem.Allocator) void {
        gpa.free(file.bytes);
        file.* = undefined;
    }
};

pub const GeneratedFiles = struct {
    response_id: []u8,
    items: []GeneratedFile,

    pub fn deinit(files: *GeneratedFiles, gpa: std.mem.Allocator) void {
        for (files.items) |*file| file.deinit(gpa);
        gpa.free(files.items);
        gpa.free(files.response_id);
        files.* = undefined;
    }
};

pub const HttpResponse = struct {
    status: std.http.Status,
    body: []u8,

    pub fn deinit(response: *HttpResponse, gpa: std.mem.Allocator) void {
        gpa.free(response.body);
        response.* = undefined;
    }
};

pub const HttpResponseWithUploadUrl = struct {
    response: HttpResponse,
    upload_url: ?[]u8 = null,
};

pub const TrafficLogOptions = struct {
    print_request: bool = false,
    print_response: bool = false,
};

pub var traffic_log_options: TrafficLogOptions = .{};

pub fn apiKeyFromMap(environ_map: *const std.process.Environ.Map) ApiKeyError![]const u8 {
    const api_key = environ_map.get(api_key_env_name) orelse return error.MissingApiKey;
    if (api_key.len == 0) return error.EmptyApiKey;
    return api_key;
}

pub fn generateContentUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent",
    };
}

pub fn countTokensUrl(model: Model) []const u8 {
    return switch (model) {
        .nano2 => "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:countTokens",
    };
}

pub fn postGenerateContentJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    model: Model,
    request_json: []const u8,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(request_json.len > 0);

    return postJson(gpa, io, api_key, generateContentUrl(model), request_json);
}

pub fn postCountTokensJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    model: Model,
    request_json: []const u8,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(request_json.len > 0);

    return postJson(gpa, io, api_key, countTokensUrl(model), request_json);
}

pub fn isCanonicalFileName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_file_name_prefix)) return false;
    return name.len > canonical_file_name_prefix.len;
}

pub fn isCanonicalCachedContentName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_cached_content_name_prefix)) return false;
    return name.len > canonical_cached_content_name_prefix.len;
}

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
        "{\"generateContentRequest\":{\"model\":\"models/gemini-3.1-flash-image-preview\",\"contents\":[{\"parts\":[{\"text\":\"My fair lady\"}]}]}}",
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

pub const RequestBodyLog = union(enum) {
    empty,
    text: []const u8,
    binary: BinaryRequestBodyLog,
};

pub const BinaryRequestBodyLog = struct {
    byte_count: usize,
    mime: []const u8,
};

pub const RequestWithBodyOptions = struct {
    capture_upload_url: bool = false,
    request_body_log: RequestBodyLog = .empty,
};

pub fn postJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
    request_json: []const u8,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(url.len > 0);
    assert(request_json.len > 0);

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
    };

    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    try logRequest(io, url, .{ .text = request_json });

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
    try logResponseBody(gpa, io, result.status, response_body);

    return .{
        .status = result.status,
        .body = try gpa.dupe(u8, response_body),
    };
}

pub fn getJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(gpa, io, api_key, url, .GET);
}

pub fn deleteJson(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
) !HttpResponse {
    return requestJsonWithoutBody(gpa, io, api_key, url, .DELETE);
}

fn requestJsonWithoutBody(
    gpa: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
    url: []const u8,
    method: std.http.Method,
) !HttpResponse {
    assert(api_key.len > 0);
    assert(url.len > 0);

    var client: std.http.Client = .{
        .allocator = gpa,
        .io = io,
    };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "x-goog-api-key", .value = api_key },
    };

    const response_buffer = try gpa.alloc(u8, max_response_bytes);
    defer gpa.free(response_buffer);

    try logRequest(io, url, .empty);

    var response_writer: std.Io.Writer = .fixed(response_buffer);
    const result = try client.fetch(.{
        .location = .{ .url = url },
        .method = method,
        .headers = .{
            .user_agent = .{ .override = "nbimg/0.0.0" },
        },
        .extra_headers = &headers,
        .response_writer = &response_writer,
    });

    const response_body = response_writer.buffered();
    try logResponseBody(gpa, io, result.status, response_body);

    return .{
        .status = result.status,
        .body = try gpa.dupe(u8, response_body),
    };
}

pub fn requestWithBody(
    gpa: std.mem.Allocator,
    client: *std.http.Client,
    method: std.http.Method,
    url: []const u8,
    content_type: []const u8,
    extra_headers: []const std.http.Header,
    body: []const u8,
    options: RequestWithBodyOptions,
) !HttpResponseWithUploadUrl {
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

    try logRequest(client.io, url, options.request_body_log);

    req.transfer_encoding = .{ .content_length = body.len };
    var body_writer = try req.sendBodyUnflushed(&.{});
    try body_writer.writer.writeAll(body);
    try body_writer.end();
    try req.connection.?.flush();

    var response = try req.receiveHead(&.{});
    const status = response.head.status;

    var upload_url: ?[]u8 = null;
    errdefer if (upload_url) |url_copy| gpa.free(url_copy);

    if (options.capture_upload_url) {
        var header_iterator = response.head.iterateHeaders();
        while (header_iterator.next()) |header| {
            if (!std.ascii.eqlIgnoreCase(header.name, "x-goog-upload-url")) continue;
            const value = std.mem.trim(u8, header.value, " \t");
            if (value.len == 0) return error.MissingUploadUrl;
            upload_url = try gpa.dupe(u8, value);
            break;
        }
    }

    const response_body = try readHttpBody(gpa, &response);
    errdefer gpa.free(response_body);

    try logResponseBody(gpa, client.io, status, response_body);

    return .{
        .response = .{
            .status = status,
            .body = response_body,
        },
        .upload_url = upload_url,
    };
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

fn logRequest(io: std.Io, url: []const u8, body: RequestBodyLog) !void {
    if (!traffic_log_options.print_request) return;

    try writeStderr(io, "--- nbimg api request ---\nurl: ");
    try writeStderr(io, url);
    try writeStderr(io, "\nbody:\n");
    switch (body) {
        .empty => try writeStderr(io, "<none>\n"),
        .text => |text| {
            try writeStderr(io, text);
            try writeStderr(io, "\n");
        },
        .binary => |binary| try writeStderrFormat(
            io,
            "<binary omitted: {d} bytes; mime: {s}>\n",
            .{ binary.byte_count, binary.mime },
        ),
    }
}

fn logResponseBody(
    gpa: std.mem.Allocator,
    io: std.Io,
    status: std.http.Status,
    response_body: []const u8,
) !void {
    if (!traffic_log_options.print_response) return;

    try writeStderrFormat(
        io,
        "--- nbimg api response ---\nstatus: {d}\nbody:\n",
        .{@intFromEnum(status)},
    );
    if (response_body.len == 0) {
        try writeStderr(io, "<empty>\n");
        return;
    }

    const log_body = sanitizeResponseLogBody(gpa, response_body) catch |err| {
        try writeStderrFormat(
            io,
            "<response body omitted: {d} bytes; failed to sanitize JSON: {s}>\n",
            .{ response_body.len, @errorName(err) },
        );
        return;
    };
    defer gpa.free(log_body);
    try writeStderr(io, log_body);
    try writeStderr(io, "\n");
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
