//! Shared Gemini API model constants, transport, and traffic logging.

const std = @import("std");
const assert = std.debug.assert;

pub const max_response_bytes = 64 * 1024 * 1024;
pub const api_key_env_name = "GEMINI_API_KEY";
pub const canonical_file_name_prefix = "files/";

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

pub fn thinkingConfigFromOptions(options: ThinkingOptions) ?ThinkingConfig {
    if (!options.hasAny()) return null;
    return .{
        .thinkingLevel = options.level,
        .includeThoughts = if (options.include_thoughts) true else null,
    };
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

pub const default_safety_settings = [_]SafetySetting{
    .{
        .category = .harassment,
        .threshold = .block_none,
    },
    .{
        .category = .hate_speech,
        .threshold = .block_none,
    },
    .{
        .category = .sexually_explicit,
        .threshold = .block_none,
    },
    .{
        .category = .dangerous_content,
        .threshold = .block_none,
    },
};

pub const CountTokensResult = struct {
    total_tokens: u64,
    cached_content_token_count: ?u64 = null,
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

pub fn isCanonicalFileName(name: []const u8) bool {
    if (!std.mem.startsWith(u8, name, canonical_file_name_prefix)) return false;
    return name.len > canonical_file_name_prefix.len;
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

test "isCanonicalFileName requires files prefix and id" {
    try std.testing.expect(isCanonicalFileName("files/abc123"));
    try std.testing.expect(!isCanonicalFileName("abc123"));
    try std.testing.expect(!isCanonicalFileName("files/"));
    try std.testing.expect(!isCanonicalFileName(""));
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

test "default safety settings serialize all supported harm categories as block none" {
    const gpa = std.testing.allocator;
    var output: std.Io.Writer.Allocating = .init(gpa);
    defer output.deinit();

    try std.json.Stringify.value(default_safety_settings, .{}, &output.writer);
    const json = output.written();

    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HARASSMENT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_HATE_SPEECH\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_SEXUALLY_EXPLICIT\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"HARM_CATEGORY_DANGEROUS_CONTENT\"") != null);
    try std.testing.expectEqual(@as(usize, 4), countOccurrences(json, "\"threshold\":\"BLOCK_NONE\""));
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
