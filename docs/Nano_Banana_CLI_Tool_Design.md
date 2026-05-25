# General design of CLI binary tool for Google Gemini Image API.

Tool will be implemented in Zig language without any dependency but its stdlib.

## 1. Scope: what “Nano Banana image API” should mean

I’d design the tool around Google’s Gemini native image generation API, where “Nano Banana” refers to a small family of image-capable Gemini models rather than one fixed endpoint. The current relevant model IDs are:

| CLI alias | API model ID                     | Best use                                                                 |
| --------- | -------------------------------- | ------------------------------------------------------------------------ |
| `nano`    | `gemini-2.5-flash-image`         | Fast, low-latency image generation/editing                               |
| `nano2`   | `gemini-3.1-flash-image-preview` | High-volume generation with newer Gemini 3 image features                |
| `pro`     | `gemini-3-pro-image-preview`     | Professional asset generation, better text rendering, stronger reasoning |

Google’s docs describe Nano Banana as Gemini native image generation, list these three models, and state that generated images include SynthID watermarking. ([Google AI for Developers][1])

The CLI should treat **all image tasks as variants of `models.generateContent`**. The REST endpoint is `POST .../{model}:generateContent`; the request contains `contents[]`, optional `tools`, `safetySettings`, `systemInstruction`, `generationConfig`, and related controls. ([Google AI for Developers][2])

So the core design principle is:

> Build a Zig CLI that compiles user-friendly flags into a full `GenerateContentRequest`, while also allowing exact raw JSON pass-through for future or obscure API fields.

That is the only robust way to “control each aspect” without depending on a Google SDK.

---

## 2. CLI name and overall command model

Use a single binary, for example:

```sh
nbimg
```

The tool should expose high-level commands, but internally they should all build the same request object.

```sh
nbimg gen       # text-to-image
nbimg edit      # image + text to image
nbimg chat      # multi-turn image editing / conversational generation
nbimg files     # upload, register, inspect files
nbimg batch     # submit many generation jobs
nbimg request   # print, validate, or send raw GenerateContentRequest JSON
nbimg models    # show local capability matrix / optionally call API
```

The most important commands are `gen`, `edit`, and `chat`.

### Example: text-to-image

```sh
nbimg gen \
  "A cinematic product photo of a matte black mechanical keyboard on a walnut desk" \
  --model nano2 \
  --aspect 16:9 \
  --size 2K \
  --out ./out/keyboard
```

### Example: image editing

```sh
nbimg edit \
  --image ./input/chair.jpg \
  --prompt "Change the fabric to deep green velvet, keep the chair shape identical" \
  --model pro \
  --aspect 4:5 \
  --size 4K \
  --out ./out/chair
```

There is no need for a separate “edit API” internally. Google’s image editing flow is text-and-image-to-image through `generateContent`, where image parts and text parts are included together in `contents`. ([Google AI for Developers][1])

### Example: multi-turn editing

```sh
nbimg chat new storyboard --model nano2 --aspect 16:9 --size 2K

nbimg chat send storyboard \
  "Create a rainy cyberpunk street scene with a red delivery robot" \
  --out ./out/turn1

nbimg chat send storyboard \
  "Make the robot blue and add a neon sign that says OPEN" \
  --out ./out/turn2
```

Multi-turn image editing is explicitly recommended by Google for iterative generation/editing; the request history can include prior user prompts, prior model image parts, and new user instructions. ([Google AI for Developers][1])

---

## 3. Model capability matrix

The CLI needs a compile-time capability table, because not every flag is valid for every model.

```zig
const ModelId = enum {
    nano_25_flash_image,
    nano_31_flash_image_preview,
    pro_3_image_preview,
};

const ModelCapabilities = struct {
    api_name: []const u8,
    aliases: []const []const u8,
    supports_image_size: bool,
    supported_sizes: []const []const u8,
    supported_aspects: []const []const u8,
    supports_thinking_level: bool,
    supported_thinking_levels: []const []const u8,
    supports_google_web_search: bool,
    supports_google_image_search: bool,
    max_reference_images: u8,
    max_object_refs: ?u8,
    max_character_refs: ?u8,
};
```

A practical matrix:

| Feature                       |                            `nano` / 2.5 Flash Image |                                         `nano2` / 3.1 Flash Image |                                      `pro` / 3 Pro Image |
| ----------------------------- | --------------------------------------------------: | ----------------------------------------------------------------: | -------------------------------------------------------: |
| Model ID                      |                            `gemini-2.5-flash-image` |                                  `gemini-3.1-flash-image-preview` |                             `gemini-3-pro-image-preview` |
| Image sizes                   |                               Fixed 1K-style output |                                           `512`, `1K`, `2K`, `4K` |                                         `1K`, `2K`, `4K` |
| Aspect ratios                 | Common ratios such as `1:1`, `16:9`, `9:16`, `21:9` | Common ratios plus extreme ratios like `1:4`, `4:1`, `1:8`, `8:1` |     Common ratios, excluding the extreme 3.1-only ratios |
| Google Search grounding       |                                                  No |                                                               Yes |                                                          |
| Google Image Search grounding |                                                  No |                                                               Yes |                                                          |
| Thinking controls             |                                                  No |                                                `minimal` / `high` |                                                          |
| Max reference images          |                           Best up to 3 input images |         Up to 14 total; up to 10 object refs and 4 character refs | Up to 14 total; up to 6 object refs and 5 character refs |

Google’s current image docs describe the 3.1 and Pro models as supporting 1K/2K/4K output, with 3.1 also supporting 512 output; they also describe Google Search grounding, Image Search for 3.1, Thinking, interim thought images, and up to 14 reference images. ([Google AI for Developers][1]) The documented aspect-ratio and size tables differ by model, so these should be validated before sending a request. ([Google AI for Developers][1])

The CLI should support both friendly aliases and exact model names:

```sh
--model nano
--model nano2
--model pro
--model gemini-3.1-flash-image-preview
```

---

## 4. Request compiler architecture

The binary should not hand-build JSON strings. It should build an internal request tree and serialize it through `std.json`.

Conceptually:

```zig
const GenerateContentRequest = struct {
    contents: []Content,
    systemInstruction: ?Content = null,
    tools: ?[]Tool = null,
    safetySettings: ?[]SafetySetting = null,
    generationConfig: ?GenerationConfig = null,
    cachedContent: ?[]const u8 = null,
    serviceTier: ?[]const u8 = null,
    store: ?bool = null,
};
```

The request compiler should have three layers:

1. **CLI layer** parses flags and arguments.
2. **Semantic layer** validates model capabilities and constructs a normalized request.
3. **Wire layer** serializes exactly the JSON expected by the API.

This separation matters because the public docs use SDK-style field names in some places and REST examples in others. For example, image options are represented in API reference material as `imageConfig` with `aspectRatio` and `imageSize`, while REST examples in the image guide show image settings under `generationConfig.responseFormat.image`. The CLI should expose stable flags like `--aspect` and `--size`, then let the serializer target the currently supported REST shape. ([Google AI for Developers][2])

---

## 5. Core flags

### 5.1 Authentication and transport

```sh
--api-key VALUE
--api-key-file PATH
--base-url URL
--api-version v1beta|v1alpha
--timeout-ms N
--dry-run
--print-request
--save-request PATH
--save-response PATH
--verbose
```

Default API key lookup:

```sh
GEMINI_API_KEY
GOOGLE_API_KEY
```

The key should never be written into saved request JSON or logs.

For normal API-key authentication:

```http
POST /v1beta/models/{model}:generateContent?key=...
```

The Zig implementation can use `std.http.Client` and `std.Uri` without external dependencies.

---

### 5.2 Prompt and content flags

The CLI must preserve part ordering, because multimodal prompts are ordered sequences.

```sh
--prompt TEXT
--prompt-file PATH
--system TEXT
--system-file PATH

--image PATH
--image PATH:mime=image/jpeg
--image PATH:role=user
--image PATH:mime=image/png:resolution=high

--file-uri URI:mime=image/png
--url URL:mime=image/jpeg
--part-json PATH
--contents-json PATH
```

Recommended behavior:

```sh
nbimg gen "A watercolor fox reading a book"
```

is equivalent to:

```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        { "text": "A watercolor fox reading a book" }
      ]
    }
  ]
}
```

For editing:

```sh
nbimg edit --image cat.png --prompt "Put a tiny wizard hat on the cat"
```

becomes one user content with an image part and a text part.

The API supports inline media, File API uploads, Google Cloud Storage registration, and external URLs. Inline files are appropriate for smaller payloads; the File API stores files temporarily; GCS registration supports larger object reuse; and direct URLs can be used for externally hosted files within documented limits. ([Google AI for Developers][3])

---

### 5.3 Image output controls

Expose the image controls directly:

```sh
--modality image
--modality text,image
--aspect 1:1|16:9|9:16|4:5|...
--size 512|1K|2K|4K
--out PATH
--out-dir DIR
--name-template 'candidate-{candidate}-part-{part}'
```

Default:

```sh
--modality image
```

For text plus image:

```sh
--modality text,image
```

Google’s image docs state that responses can be configured for image-only output using `responseModalities`, while the default can include both text and image. ([Google AI for Developers][1]) The general API reference also defines `responseModalities` as the requested output modalities. ([Google AI for Developers][2])

Important validation:

```text
--size 4K  -> valid for nano2 and pro
--size 512 -> valid for nano2 only
--size 4K with --model nano -> reject unless --force
```

Also, `1K`, `2K`, and `4K` should be uppercase because Google documents uppercase values and notes that lowercase values are rejected. ([Google AI for Developers][1])

---

### 5.4 Reference image controls

The CLI should support explicit reference roles, not just anonymous `--image`.

```sh
--ref object:./shoe.png
--ref object:./logo.png
--ref character:./person.png
--ref style:./moodboard.jpg
--ref image:./general-reference.png
```

Internally these can still be ordinary image parts plus prompt text, but the CLI can synthesize clearer instructions:

```text
Use the first image as the object reference.
Use the second image as the character identity reference.
Use the third image as style reference.
```

Model validation should enforce limits:

```text
nano:  warn after 3 input images
nano2: max 14 total, max 10 object refs, max 4 character refs
pro:   max 14 total, max 6 object refs, max 5 character refs
```

Google’s docs describe these per-model reference limits for Gemini 3 image models and note that Gemini 2.5 Flash Image works best with up to three input images. ([Google AI for Developers][1])

---

### 5.5 Thinking controls

For Gemini 3 image models, the CLI should expose Thinking as a first-class group:

```sh
--thinking-level minimal
--thinking-level high
--include-thoughts
```

For example:

```sh
nbimg gen \
  "Design a clear infographic explaining orbital mechanics" \
  --model nano2 \
  --thinking-level high \
  --include-thoughts \
  --out ./out/orbits
```

Google documents that Gemini 3 image models are thinking models; Thinking is enabled by default and cannot be disabled. For Gemini 3.1 Flash Image, the documented thinking levels are `minimal` and `high`, and `includeThoughts` controls whether thoughts are returned. ([Google AI for Developers][1])

The chat state must also preserve **thought signatures** exactly when present. Google describes thought signatures as encrypted representations used to preserve reasoning context in multi-turn interactions and states that they should be passed back exactly. ([Google AI for Developers][1])

For one-shot generation and edit commands, thought output should not have a
separate destination flag. Returned thought text stays visible in the raw
response log, and returned thought images are saved beside final images in the
normal output directory with a `thought` marker in the filename.

---

### 5.6 Google Search and Image Search grounding

Expose grounding like this:

```sh
--grounding none
--grounding web
--grounding image
--grounding web,image

--save-grounding-json PATH
--save-grounding-html PATH
```

Examples:

```sh
nbimg gen \
  "Create an image of the latest design of the Eiffel Tower lighting installation" \
  --model nano2 \
  --grounding web \
  --out ./out/eiffel
```

```sh
nbimg gen \
  "Create a mood board based on current images of modern Scandinavian kitchens" \
  --model nano2 \
  --grounding web,image \
  --save-grounding-html ./out/attribution.html \
  --out ./out/kitchen
```

The request compiler would emit:

```json
{
  "tools": [
    {
      "google_search": {
        "searchTypes": {
          "webSearch": {},
          "imageSearch": {}
        }
      }
    }
  ]
}
```

Google’s docs show `google_search` for Search grounding and describe Image Search grounding as available only for Gemini 3.1 Flash Image; they also document attribution/display requirements and response metadata such as `groundingMetadata`, `groundingChunks`, and `searchEntryPoint`. ([Google AI for Developers][1])

Validation:

```text
--grounding image with --model nano  -> reject
--grounding image with --model pro   -> reject
--grounding image with --model nano2 -> allow
```

---

### 5.7 Media resolution controls

Input media resolution should be available globally and per part.

Global:

```sh
--media-resolution low|medium|high|unspecified
```

Per input:

```sh
--image ./diagram.png:resolution=high
--image ./draft.jpg:resolution=low
```

Google documents `media_resolution` as a control for how Gemini processes media inputs such as images, video, and PDFs, with global support and experimental per-part support for Gemini 3 models. ([Google AI for Developers][4])

For this CLI:

```text
--media-resolution high
```

sets the global generation config field.

```text
--image file.png:resolution=high
```

sets a per-part override, but only when the selected API version and model support it.

---

### 5.8 Safety controls

Expose safety settings explicitly:

```sh
--safety harassment=BLOCK_ONLY_HIGH
--safety hate_speech=BLOCK_MEDIUM_AND_ABOVE
--safety sexually_explicit=BLOCK_LOW_AND_ABOVE
--safety dangerous_content=OFF
--safety civic_integrity=BLOCK_ONLY_HIGH
```

Use canonical categories internally:

```zig
const SafetyCategory = enum {
    harassment,
    hate_speech,
    sexually_explicit,
    dangerous_content,
    civic_integrity,
};
```

The Gemini API supports adjustable safety settings per request, while core built-in harms remain blocked and cannot be adjusted. Google documents thresholds such as `OFF`, `BLOCK_NONE`, `BLOCK_ONLY_HIGH`, `BLOCK_MEDIUM_AND_ABOVE`, and `BLOCK_LOW_AND_ABOVE`; it also notes that default thresholds differ by model family. ([Google AI for Developers][5])

The CLI should never imply that all safety behavior can be disabled.

---

### 5.9 Advanced generation config

Expose general `generationConfig` fields, but mark them as advanced because some are text-oriented or may have limited effect on image-only output.

```sh
--temperature FLOAT
--top-p FLOAT
--top-k INT
--seed INT
--candidate-count INT
--max-output-tokens INT
--stop TEXT
--presence-penalty FLOAT
--frequency-penalty FLOAT
--response-mime-type MIME
--response-schema PATH
--response-json-schema PATH
--logprobs
--response-logprobs
```

The API reference documents these generation fields, including `candidateCount`, `maxOutputTokens`, `temperature`, `topP`, `topK`, `seed`, penalties, logprob options, `thinkingConfig`, `imageConfig`, and `mediaResolution`. ([Google AI for Developers][2])

Recommended CLI behavior:

```text
default: validate known image-compatible fields
--force: forward advanced fields even if the CLI cannot prove compatibility
--strict: fail on unknown or suspicious combinations
```

---

## 6. Raw request escape hatch

Because the API evolves quickly, this is essential.

```sh
nbimg request send ./request.json --model nano2 --out ./out
nbimg request validate ./request.json --model nano2
nbimg gen "Prompt" --set generationConfig.temperature=0.7
nbimg gen "Prompt" --add-tool-json ./tool.json
```

The escape hatch should support:

```sh
--raw-request PATH
--set JSON_POINTER=VALUE
--merge-json PATH
--force
```

Examples:

```sh
nbimg gen "A poster with clean typography" \
  --model pro \
  --merge-json ./extra-generation-config.json \
  --print-request
```

This gives users full API coverage without waiting for the CLI to add a new flag.

---

## 7. Output parser

The response parser should walk:

```text
candidates[]
  content
    parts[]
```

For each part:

| Part kind                    | CLI behavior                                                   |
| ---------------------------- | -------------------------------------------------------------- |
| `text`                       | Print to stdout or save as `.txt`                              |
| `inlineData`                 | Base64-decode and write image file                             |
| thought part                 | Save thought images only when `--include-thoughts` is set; leave thought text in response logs |
| grounding metadata           | Save JSON and optional attribution HTML                        |
| safety / finish metadata     | Save in response metadata JSON                                 |
| thought signatures           | Store in chat state exactly                                    |

Output naming:

```text
out/
  candidate-0-part-0.png
  candidate-0-part-1.txt
  candidate-0-grounding.json
  candidate-0-thought-0.png
  response.json
```

MIME-to-extension mapping can be implemented with a small static table:

```zig
const MimeExt = struct {
    mime: []const u8,
    ext: []const u8,
};

const mime_exts = [_]MimeExt{
    .{ .mime = "image/png", .ext = "png" },
    .{ .mime = "image/jpeg", .ext = "jpg" },
    .{ .mime = "image/webp", .ext = "webp" },
    .{ .mime = "text/plain", .ext = "txt" },
};
```

Generated image count should be treated as best-effort. Google’s docs note that the model may not always follow the exact requested number of image outputs. ([Google AI for Developers][1])

---

## 8. File API design

The `files` command should handle large or reusable inputs.

```sh
nbimg files upload ./reference.png --mime image/png --alias ref-chair
nbimg files list
nbimg files info ref-chair
nbimg files delete ref-chair
```

Then:

```sh
nbimg edit \
  --file ref-chair \
  --prompt "Use this chair as the exact shape reference, generate a studio catalog shot" \
  --model pro \
  --out ./out
```

File state:

```json
{
  "aliases": {
    "ref-chair": {
      "name": "files/abc123",
      "uri": "https://...",
      "mime": "image/png",
      "created_at": "2026-05-10T..."
    }
  }
}
```

The File API has separate media upload endpoints and is intended for larger or reused files; uploaded files are temporary. ([Google AI for Developers][6])

For GCS registration:

```sh
nbimg files register-gcs gs://bucket/path/image.png \
  --mime image/png \
  --oauth-token-env GOOGLE_OAUTH_ACCESS_TOKEN
```

Do **not** implement OAuth flows inside the no-dependency binary. Accept a bearer token from an environment variable or file.

---

## 9. Batch design

Batching should be built on top of the same request compiler.

```sh
nbimg batch make prompts.txt \
  --model nano2 \
  --aspect 1:1 \
  --size 1K \
  --out requests.jsonl

nbimg batch submit requests.jsonl --name product-renders
nbimg batch status product-renders
nbimg batch fetch product-renders --out ./batch-out
```

Each JSONL line should be a full request or a compact CLI-derived job:

```json
{"key":"hero-001","prompt":"A white sneaker on a blue background","aspect":"1:1","size":"1K"}
```

compiled into:

```json
{"request":{"contents":[...],"generationConfig":...}}
```

Google recommends the Batch API for generating many images, with higher rate limits in exchange for slower turnaround. ([Google AI for Developers][1])

---

## 10. Chat state design

A multi-turn image session needs exact replay, not a lossy summary.

State file:

```json
{
  "model": "gemini-3.1-flash-image-preview",
  "generation_config": {
    "responseModalities": ["IMAGE"],
    "responseFormat": {
      "image": {
        "aspectRatio": "16:9",
        "imageSize": "2K"
      }
    }
  },
  "contents": [
    {
      "role": "user",
      "parts": [
        {"text": "Create a rainy cyberpunk street scene"}
      ]
    },
    {
      "role": "model",
      "parts": [
        {
          "inlineData": {
            "mimeType": "image/png",
            "dataFile": "./.nbimg/chats/storyboard/turn-1-image-0.b64"
          },
          "thoughtSignature": "..."
        }
      ]
    }
  ]
}
```

Commands:

```sh
nbimg chat new NAME --model nano2 --aspect 16:9 --size 2K
nbimg chat send NAME "Make the sky darker" --out ./out
nbimg chat export NAME --out chat.json
nbimg chat import NAME chat.json
nbimg chat clear NAME
```

The state file must preserve:

```text
role
part ordering
image MIME types
inline image data or file references
thought signatures
grounding metadata when relevant
```

Thought signatures should not be regenerated, modified, or decoded.

---

## 11. Zig implementation layout

A clean no-dependency Zig project:

```text
src/
  main.zig
  args.zig
  cli_gen.zig
  cli_edit.zig
  cli_chat.zig
  cli_files.zig
  cli_batch.zig

  api/
    request.zig
    response.zig
    generate_content.zig
    files.zig
    batch.zig
    capabilities.zig
    safety.zig
    grounding.zig

  util/
    json.zig
    base64.zig
    mime.zig
    path.zig
    atomic_file.zig
    redact.zig
    diagnostics.zig
```

### Important stdlib-only choices

| Need               | Zig stdlib approach                                 |
| ------------------ | --------------------------------------------------- |
| HTTP client        | `std.http.Client`                                   |
| TLS                | stdlib TLS support through `std.http.Client`        |
| JSON serialization | `std.json.writeStream` / `std.json.stringify`       |
| JSON parsing       | `std.json.parseFromSlice`                           |
| Base64             | `std.base64`                                        |
| Filesystem         | `std.fs`                                            |
| CLI args           | `std.process.argsWithAllocator`                     |
| Environment        | `std.process.getEnvVarOwned`                        |
| Allocators         | `std.heap.ArenaAllocator` per command; GPA in debug |
| Atomic writes      | write temp file, then rename                        |

Avoid:

```text
curl
jq
openssl
third-party arg parsers
third-party JSON libraries
Google SDKs
```

---

## 12. Argument parser design

A custom parser is manageable because the command surface is structured.

```zig
const FlagValue = union(enum) {
    none,
    string: []const u8,
    repeated: [][]const u8,
};

const ParsedArgs = struct {
    command: Command,
    positionals: [][]const u8,
    flags: std.StringHashMap(FlagValue),
};
```

Support:

```text
--flag value
--flag=value
--no-flag
repeated flags
subcommand-specific validation
```

For typed options:

```zig
fn parseAspect(s: []const u8) !AspectRatio;
fn parseImageSize(s: []const u8) !ImageSize;
fn parseSafety(s: []const u8) !SafetySetting;
fn parseGrounding(s: []const u8) !GroundingMode;
fn parseMediaPartSpec(s: []const u8) !InputPartSpec;
```

Use excellent diagnostics:

```text
error: --size 512 is only supported by gemini-3.1-flash-image-preview

selected model:
  pro -> gemini-3-pro-image-preview

valid sizes:
  1K, 2K, 4K

hint:
  use --model nano2 for 512 output
```

---

## 13. HTTP layer

Create one low-level function:

```zig
pub fn postJson(
    allocator: std.mem.Allocator,
    client: *std.http.Client,
    url: std.Uri,
    api_key: []const u8,
    body: []const u8,
) !HttpResponse;
```

Responsibilities:

```text
append API key or Authorization header
set Content-Type: application/json
set User-Agent
send body
read response with a sane max limit
return status, headers, body
redact secrets in diagnostics
```

For uploads, implement the resumable upload protocol in `api/files.zig`:

```text
1. Start upload session with metadata.
2. Read returned upload URL header.
3. Upload file bytes to that URL.
4. Parse returned File object.
```

The File API upload endpoint is separate from `generateContent`, so keeping it in its own module is cleaner. ([Google AI for Developers][6])

---

## 14. Validation strategy

Use three validation levels:

```sh
--strict    # default for known flags
--relaxed   # warn but send
--force     # send even suspicious/unknown combinations
```

Validate before request serialization:

```text
model exists
aspect ratio supported by model
image size supported by model
grounding mode supported by model
image search only on nano2
thinking level only where supported
reference image count limits
input file size limits
MIME type known or explicitly supplied
safety categories valid
safety thresholds valid
media-resolution compatibility
```

Also validate things that are **not** controllable:

```text
transparent background is not supported
audio/video inputs are not supported for image generation
exact number of generated images is not guaranteed
output image MIME is determined by API response
```

Google’s docs explicitly state that transparent background is not supported, image generation does not support audio or video inputs, and exact image output count is not guaranteed. ([Google AI for Developers][1])

---

## 15. Proposed help output

```text
Usage:
  nbimg gen  PROMPT [options]
  nbimg edit --image PATH --prompt TEXT [options]
  nbimg chat new NAME [options]
  nbimg chat send NAME PROMPT [options]
  nbimg files upload PATH [options]
  nbimg batch submit PATH [options]
  nbimg request send PATH [options]

Common options:
  --model nano|nano2|pro|MODEL_ID
  --api-key VALUE
  --api-key-file PATH
  --out PATH
  --print-request
  --save-response PATH
  --dry-run

Image options:
  --aspect RATIO
  --size 512|1K|2K|4K
  --modality image|text,image

Input options:
  --prompt TEXT
  --prompt-file PATH
  --system TEXT
  --image PATH[:mime=TYPE][:resolution=LEVEL]
  --file-uri URI:mime=TYPE
  --url URL:mime=TYPE

Gemini 3 options:
  --thinking-level minimal|high
  --include-thoughts
  --grounding none|web|image|web,image
  --media-resolution low|medium|high

Safety options:
  --safety CATEGORY=THRESHOLD

Advanced:
  --temperature FLOAT
  --top-p FLOAT
  --top-k INT
  --seed INT
  --candidate-count INT
  --max-output-tokens INT
  --set JSON_POINTER=VALUE
  --merge-json PATH
  --raw-request PATH
  --force
```

---

## 16. Example compiled request

Command:

```sh
nbimg gen \
  "Create a 16:9 hero image of a futuristic Toronto skyline at sunrise" \
  --model nano2 \
  --aspect 16:9 \
  --size 2K \
  --grounding web \
  --thinking-level high \
  --include-thoughts \
  --print-request
```

Request shape:

```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        {
          "text": "Create a 16:9 hero image of a futuristic Toronto skyline at sunrise"
        }
      ]
    }
  ],
  "tools": [
    {
      "google_search": {}
    }
  ],
  "generationConfig": {
    "responseModalities": ["IMAGE"],
    "thinkingConfig": {
      "thinkingLevel": "high",
      "includeThoughts": true
    },
    "responseFormat": {
      "image": {
        "aspectRatio": "16:9",
        "imageSize": "2K"
      }
    }
  }
}
```

That request shape follows the documented `contents`, `tools`, and `generationConfig` structure for `generateContent`, with image generation settings, Search grounding, and Thinking configuration layered into the same call. ([Google AI for Developers][2])

---

## 17. Build and test strategy

`build.zig` should produce one static-ish CLI where possible:

```sh
zig build
zig build -Doptimize=ReleaseSafe
zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSmall
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseSafe
```

Test categories:

```text
unit tests:
  parse flags
  validate model capabilities
  serialize requests
  parse responses
  MIME detection
  base64 decode paths

golden tests:
  CLI args -> exact JSON request
  sample API response -> exact output files

integration tests:
  local HTTP fixture server
  no real API key required

manual live tests:
  guarded by GEMINI_API_KEY
```

The best tests for this tool are golden JSON tests. For example:

```text
input:
  nbimg gen "cat" --model nano2 --aspect 1:1 --size 1K

expected:
  request JSON exactly matches fixture
```

This is especially important because the whole value of the tool is accurate request construction.

---

## 18. Key design decisions

The strongest design is:

1. **One request compiler** for `gen`, `edit`, and `chat`.
2. **Model-aware validation** through a static capability matrix.
3. **Raw JSON escape hatches** so the CLI remains complete as the API evolves.
4. **Exact chat-state preservation**, especially for image parts and thought signatures.
5. **No SDK assumption**: only `std.http`, `std.json`, `std.base64`, and filesystem APIs.
6. **Clear unsupported controls**: no fake flags for transparent background, exact output count, audio/video image-generation input, or guaranteed output MIME.

That gives you a Zig binary that is small, portable, dependency-free, and still powerful enough to control the full Nano Banana image-generation surface.

[1]: https://ai.google.dev/gemini-api/docs/image-generation "Gemini API  |  Google AI for Developers"
[2]: https://ai.google.dev/api/generate-content "Generating content  |  Gemini API  |  Google AI for Developers"
[3]: https://ai.google.dev/gemini-api/docs/file-input-methods "Gemini generateContent API  |  Google AI for Developers"
[4]: https://ai.google.dev/gemini-api/docs/media-resolution "Gemini generateContent API  |  Google AI for Developers"
[5]: https://ai.google.dev/gemini-api/docs/safety-settings "Safety settings  |  Gemini API  |  Google AI for Developers"
[6]: https://ai.google.dev/api/files "Using files  |  Gemini API  |  Google AI for Developers"
