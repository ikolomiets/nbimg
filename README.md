# nbimg

`nbimg` is a small Zig CLI for experimenting with Gemini native image
generation and the Gemini Files API.

The current implementation is intentionally narrow:

- generate image and text output from a text prompt
- edit an uploaded Gemini File API image with a text prompt
- enable Google Search or Image Search grounding for generation and edit
- configure Gemini Thinking level and request returned thought parts
- configure one Gemini safety threshold across all emitted safety categories
- configure advanced Gemini generation controls such as sampling, seed,
  output-token budget, stop sequences, and logprob diagnostics
- configure request-level controls such as system instructions, cached
  content, service tier, and request storage
- validate generation and edit requests with `countTokens` and append them to
  Gemini Batch API JSONL input files
- validate and upload Batch JSONL input, submit one Batch job, fetch one
  current Batch operation status, request cancellation, and list recent jobs
- upload supported image files to Gemini Files API
- list, get, and delete uploaded Gemini files
- print whole-second response timing and sanitized response traffic by default,
  with optional request traffic

See [docs/IMPLEMENTATION_DESIGN.md](docs/IMPLEMENTATION_DESIGN.md) for the
current implementation details.

## Requirements

- Zig 0.16.0
- a non-empty Gemini API key supplied through `GEMINI_API_KEY` or `--api-key`

The project currently uses only the Zig standard library.

## Build

```sh
zig build
```

The installed executable is always built with `ReleaseSafe`, which keeps Zig
safety checks and `std.debug.assert` active.

The executable is written to:

```sh
zig-out/bin/nbimg
```

Development executions through `zig build run -- <args>` compile and run a
separate Debug artifact from the build cache.

## Zig Library API

The package registers a supported module named `nbimg`. Its typed client can
generate owned images:

```zig
const std = @import("std");
const nbimg = @import("nbimg");

fn generate(
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
) !void {
    const client = try nbimg.Client.init(allocator, io, .{
        .api_key = api_key,
    });

    var outcome = try client.generate(.{
        .prompt = "Create a cinematic product hero image",
        .output_options = .{
            .aspect_ratio = .r16_9,
            .image_size = .k2,
        },
    });

    switch (outcome) {
        .success => |*result| {
            defer result.deinit(allocator);
            for (result.images) |image| {
                std.debug.print(
                    "candidate {d}, part {d}: {d} bytes\n",
                    .{ image.candidate_position, image.part_position, image.bytes.len },
                );
            }
        },
        .api_failure => |*failure| {
            defer failure.deinit(allocator);
            std.debug.print(
                "Gemini returned HTTP {d}: {s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
        },
    }
}
```

`GenerationResult` owns its response ID, image slice, and every image byte
buffer. Release it with `GenerationResult.deinit` using the client allocator.
Candidate and part positions are zero-based response-array positions. Output
MIME values are `png`, `jpeg`, and `webp`; the optional reported service tier
uses the public `ServiceTier` enum.

The same request types support non-generating token counting:

```zig
const std = @import("std");
const nbimg = @import("nbimg");

fn countTokens(
    allocator: std.mem.Allocator,
    io: std.Io,
    api_key: []const u8,
) !void {
    const client = try nbimg.Client.init(allocator, io, .{
        .api_key = api_key,
    });

    var outcome = try client.countGenerateTokens(.{
        .prompt = "Create a cinematic product hero image",
        .output_options = .{
            .aspect_ratio = .r16_9,
            .image_size = .k2,
        },
        .generation_options = .{
            .temperature = 0.7,
            .stop_sequences = &.{"END"},
        },
    });

    switch (outcome) {
        .success => |result| {
            std.debug.print("total tokens: {d}\n", .{result.total_tokens});
        },
        .api_failure => |*failure| {
            defer failure.deinit(allocator);
            std.debug.print(
                "Gemini returned HTTP {d}: {s}\n",
                .{ @intFromEnum(failure.status), failure.body },
            );
        },
    }
}
```

`Client` borrows the API key and does not allocate during initialization. The
key must remain valid for the client lifetime. The default request timeout is
180 seconds and can be replaced through `ClientOptions.timeout`. Public client
requests are quiet: CLI request and response traffic logging is not part of
the library contract.

Invalid `GenerationRequest` values return `GenerationValidationError` before
network IO. Transport, allocation, timeout, oversized-response, and malformed
successful-response failures are Zig errors. A completed non-success HTTP
response is returned as `.api_failure`; its complete bounded body is owned and
must be released with `ApiFailure.deinit`.

The existing `api`, `gen`, `edit`, `files`, and `batch` package paths remain
available temporarily for compatibility. They are implementation-oriented
legacy APIs rather than the supported typed client contract.

## Usage

The CLI accepts these command forms:

```sh
nbimg gen [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier flex|standard|priority] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] [--prompt "PROMPT"]
nbimg edit [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier flex|standard|priority] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
nbimg files upload [--api-key KEY] [--print-request] [--display-name NAME] --path PATH
nbimg files list [--api-key KEY] [--print-request]
nbimg files get [--api-key KEY] [--print-request] --name files/ID
nbimg files delete [--api-key KEY] [--print-request] --name files/ID
nbimg batch submit [--api-key KEY] [--print-request] [--display-name NAME] --path PATH
nbimg batch status [--api-key KEY] [--print-request] --name batches/ID
nbimg batch cancel [--api-key KEY] [--print-request] --name batches/ID
nbimg batch download [--api-key KEY] [--print-request] --name batches/ID [--out-dir DIR]
nbimg batch list [--api-key KEY] [--print-request]
```

`--api-key` is accepted after the leaf command or subcommand in any option
order. For example:

```sh
zig-out/bin/nbimg files list --api-key "$GEMINI_API_KEY"
```

Prefer the environment variable for routine use because command-line values
may be retained in shell history or exposed through process inspection.

Generate an image from a prompt:

```sh
printf '%s\n' "Create a photo of my fair lady" | zig-out/bin/nbimg gen
```

You can also pass the prompt explicitly:

```sh
zig-out/bin/nbimg gen \
  --aspect-ratio 16:9 \
  --image-size 2K \
  --prompt "Create a photo of my fair lady"
```

Upload an image:

```sh
zig-out/bin/nbimg files upload --path sample_images/good_night.jpeg
```

By default, uploads use the local file name as the Gemini display name. Override
it with `--display-name`:

```sh
zig-out/bin/nbimg files upload \
  --path sample_images/good_night.jpeg \
  --display-name "nbimg sample image"
```

`--path` is required once for `files upload`. The path must be non-empty, the
file must be non-empty, and the supported upload extensions are `.jpg`, `.jpeg`,
`.png`, and `.webp`. Upload reads are capped at `64 MiB`.

Explicit and path-derived display names must be non-empty valid UTF-8 and at
most 512 Unicode code points.

Edit an uploaded image:

```sh
printf '%s\n' "change visual style to Broadway musical" | zig-out/bin/nbimg edit \
  --ref character=files/tjtj5me9i96c,image/jpeg
```

If `gen` or `edit` omits `--prompt`, `nbimg` reads the prompt from stdin.
Stdin prompts are preserved exactly, including trailing newlines, and are
limited to `16 KiB`. Explicit `--prompt` values use the same `16 KiB` limit and
must be one shell argument, so quote prompts that contain spaces. Empty prompts
are rejected, and prompts are not accepted as positional arguments.

Use `--out-dir DIR` with `gen` or `edit` to write generated outputs to an
existing relative or absolute directory instead of the current directory. The
flag may be used at most once, and the directory must already exist. Gemini text
response parts are not written as sidecar files; they remain visible in the raw
response JSON logged to stderr. `gen` and `edit` request both text and image
response parts by default; there is no flag for changing response modalities.

Use `--batch-file PATH` with `gen` or `edit` to prepare a Gemini Batch API
JSONL input file instead of generating immediately:

```sh
zig-out/bin/nbimg gen \
  --batch-file requests.jsonl \
  --batch-key hero-001 \
  --aspect-ratio 16:9 \
  --prompt "Create a cinematic product hero image"
```

Batch mode builds the normal `GenerateContentRequest`, sends that exact request
to Gemini's non-generation `countTokens` endpoint, and appends it only after an
HTTP success and a valid token-count response. Each line has the Batch API
shape `{"key":"...","request":{...}}`. The file is created when absent and
locked while existing keys are checked and the new line is appended.
Each batch file is limited to 100 entries. An attempted 101st append is rejected
before the locked file is modified.

`--batch-key KEY` is optional and requires `--batch-file`. Explicit keys must
be unique within that JSONL file. If omitted, `nbimg` derives a deterministic
key such as `nbimg-0` from the locked byte offset where the entry begins.
`--batch-file` and `--out-dir` are mutually exclusive.

On success, stdout receives a compact receipt suitable for scripts:

```json
{"key":"hero-001","totalTokens":42,"batchFile":"requests.jsonl"}
```

`--print-request` remains independent and prints the `countTokens` validation
request to stderr.

Submit a prepared JSONL input file:

```sh
zig-out/bin/nbimg batch submit --path requests.jsonl
```

`batch submit` performs only local admission checks before network IO. The
input must contain at least one non-empty JSONL entry, each entry is capped at
`5 MiB`, the complete local file is capped at `512 MiB`, and one batch is
capped at 100 entries. Submit does not parse entry JSON, check keys, or validate
the nested request shape; malformed entries are left for Gemini to reject.
Inputs over local limits are rejected before upload or job creation.

The command uploads the input through the Gemini Files API as
`application/jsonl`, then creates exactly one job for
`models/gemini-3.1-flash-image:batchGenerateContent`. By default, both the
uploaded File and Batch job use the complete local basename, including the
`.jsonl` extension, as `displayName`. `--display-name NAME` overrides both.

Job creation is non-idempotent and is never retried. If its transport fails
after upload, `nbimg` reports the uploaded `files/...` name and warns that a
job may already have been created. The uploaded JSONL remains in Gemini Files
storage after submission.

Successful submission prints the complete Batch response as pretty JSON. Use
the returned canonical name for a single status request:

```sh
zig-out/bin/nbimg batch status --name batches/123456789
```

`batch status` performs one GET without polling or retries and prints every
returned response field as pretty JSON.

Request best-effort cancellation of an existing Batch job:

```sh
zig-out/bin/nbimg batch cancel --name batches/123456789
```

`batch cancel` performs one bodyless POST without polling or retries and
prints `OK` when Gemini accepts the request. Acceptance does not guarantee the
job has already reached `JOB_STATE_CANCELLED`; use `batch status` to inspect
the current state. Cancellation does not delete the Batch job or its uploaded
JSONL input.

Download image results from a completed Batch job:

```sh
zig-out/bin/nbimg batch download \
  --name batches/123456789 \
  --out-dir outputs
```

`batch download` checks status exactly once and proceeds only for a succeeded
job. It rejects a reported `batchStats.requestCount` over 100, downloads the
output JSONL with a separate `512 MiB` limit, and independently enforces at
most 100 output records. A known oversized `Content-Length` is rejected before
body allocation; unknown lengths grow incrementally and accept exactly
`512 MiB`.

The complete JSONL stays in memory, while records are decoded one at a time.
Successful inline images are written to the current directory by default or
to an existing `--out-dir`. A missing output directory is reported clearly.
Names use
`{safe_key}-{candidate}-{part}.{extension}`. Writes are exclusive and never
overwrite existing files. Every successfully written filename is printed to
stdout. Error records, malformed records, duplicate keys, decode failures, and
write failures are reported while later records continue processing. Existing
target files are reported with their destination paths and left untouched. Any
such failure makes the command exit nonzero.

List all recent Batch jobs currently exposed by Gemini:

```sh
zig-out/bin/nbimg batch list
```

`batch list` requests 100 operations per page, follows every returned
`nextPageToken`, and prints one pretty JSON object containing the aggregated
`operations` array. Each operation must have a canonical `batches/...` name,
and all other returned operation fields are preserved. Gemini does not return
deleted jobs from this recent-job history. The API's undocumented `filter`
parameter is intentionally not exposed.

Use `--aspect-ratio RATIO` and `--image-size SIZE` with `gen` or `edit` to
request a specific generated canvas shape or resolution tier. Valid aspect
ratios are `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`,
`5:4`, `8:1`, `9:16`, `16:9`, and `21:9`. Valid image sizes are `512`, `1K`,
`2K`, and `4K`. If both flags are omitted, `nbimg` leaves Gemini's output
shape defaults unchanged.

Advanced generation controls are available on both `gen` and `edit`. They are
token-generation controls sent under Gemini `generationConfig`; they do not
replace image-specific controls such as `--aspect-ratio` or `--image-size`.
All are omitted from the request unless explicitly set. Except for repeatable
`--stop`, each advanced generation option is accepted at most once.

Use `--temperature FLOAT` and `--top-p FLOAT` to tune sampling behavior.
`--temperature` accepts `0.0` through `2.0`; lower values are more
conservative, while higher values allow more variation. `--top-p` accepts
`0.0` through `1.0` and is mostly useful for controlled prompt experiments.

Use `--seed INT` for best-effort reproducibility. The seed must be a signed
32-bit decimal integer. Exact repeatability is not guaranteed by Gemini; keep
the same prompt, model, inputs, and generation settings when comparing runs.

Use `--max-output-tokens INT` as an output budget or termination guard. It
accepts `1` through `32768`. It does not select image resolution or visual
quality, and values that are too low can truncate generated text or stop
generation early.

Use `--presence-penalty FLOAT` and `--frequency-penalty FLOAT` for text-heavy
responses where repeated wording matters. Both accept values from `-2.0` up to
but not including `2.0`. Positive values discourage repetition; negative
values can encourage reuse. These are not reliable visual-diversity controls.

Use repeatable `--stop TEXT` to stop text generation when a literal sequence is
encountered. Up to five non-empty unique stop sequences are accepted. Stop
sequences are case-sensitive text controls, not negative prompts.

Use `--response-logprobs` for token-level diagnostics on chosen response
tokens. Add `--logprobs INT` with a value from `1` through `20` to request
top-token alternatives at each step; `--logprobs` requires
`--response-logprobs`. These diagnostics are not image confidence scores.

Request-level controls are available on both `gen` and `edit`. They are
top-level Gemini `GenerateContentRequest` fields and are omitted unless
explicitly set. Each request-level option is accepted at most once.

Use `--system TEXT` to send a text-only Gemini `systemInstruction` alongside
the user prompt. The value must be non-empty and at most `16 KiB`.

Use `--cached-content cachedContents/ID` to attach an existing Gemini cached
content resource. `nbimg` requires the canonical `cachedContents/...` form and
rejects raw cache IDs.

Use `--service-tier flex|standard|priority` to request a Gemini service tier.
If omitted, `nbimg` leaves the field unset so Gemini uses the project and
model default. If `priority` is requested and the response reports
`usageMetadata.serviceTier` as `standard`, `nbimg` prints a warning but still
handles the response normally.

Use `--store` to send `store:true`, or `--no-store` to send `store:false`.
The flags are mutually exclusive. Omit both flags to use the project-level
logging configuration.

Use `--thinking-level minimal|high` with `gen` or `edit` to control Gemini's
thinking effort. Omit it to use Gemini's default. Use `--include-thoughts` to
ask Gemini to return thought parts in the response. Response traffic is already
logged to stderr by default, so returned thought parts remain visible there.
Thought image parts are not written as sidecar files.

Use `--safety none|off|permissive|balanced|strict` with `gen` or `edit` to
choose one Gemini safety threshold for every safety category that `nbimg`
sends. If omitted, `nbimg` does not send `safetySettings`; explicit levels
serialize as `BLOCK_NONE`, `OFF`, `BLOCK_ONLY_HIGH`,
`BLOCK_MEDIUM_AND_ABOVE`, or `BLOCK_LOW_AND_ABOVE`.

`--safety` controls only Gemini's adjustable request-level `safetySettings`.
Google's Gemini safety documentation describes additional built-in protections
that are not controlled by client safety settings and may still block prompts,
responses, or image generation: <https://ai.google.dev/docs/safety_setting_gemini>.
The exact image-generation behavior of `BLOCK_NONE` versus `OFF` is not
defined by `nbimg`; both are exposed for API coverage.

Use `--grounding MODE` with `gen` or `edit` when the prompt should be grounded
with Google Search. Valid modes are `none`, `web`, `image`, and `web,image`.
The default is `none`.

Grounding adds the Gemini `google_search` tool to the request. The model may
then search before answering, use the retrieved context while generating, and
return `groundingMetadata` in the raw API response. `nbimg` does not save that
metadata separately; response traffic is logged to stderr by default, so the
metadata remains visible there when Gemini returns it.

Web grounding is for current factual or real-world context, such as recent
events, venue details, weather-aware scenes, or up-to-date product information:

```sh
zig-out/bin/nbimg gen \
  --grounding web \
  --prompt "Create a 16:9 editorial image of the current Toronto skyline at sunrise, using accurate recent landmark details"
```

Image Search grounding is for visual search context. It lets Gemini use Google
Image Search results for visual grounding before generating, which is useful
for current visual trends, real object appearance, species or location
references, mood boards, and visual research. Google's current image docs state
that Image Search grounding cannot be used to search for people.

```sh
zig-out/bin/nbimg gen \
  --grounding image \
  --prompt "Use image search to find accurate images of a resplendent quetzal bird, then create a clean 3:2 wallpaper inspired by its real colors and shape"
```

Use combined `web,image` grounding when the prompt benefits from both factual
web context and visual image-search context:

```sh
zig-out/bin/nbimg gen \
  --grounding web,image \
  --prompt "Create a magazine-style page about the latest Gemini image model news, with a current hero image style informed by recent visual coverage"
```

The `edit` command takes uploaded image references in `files/ID,MIME` form.
At least one `--ref` is required. The first `--ref` is the base image to edit
and is always labeled `BASE_IMAGE`; omit a custom label on that first reference.
Resource names must use canonical `files/...` form, and bare file IDs are
rejected. Supported MIME values are `image/jpeg`, `image/png`, and `image/webp`.
The command derives the Gemini File API URI from the `files/...` name and does
not call `files get` before generation. If a referenced upload is expired,
deleted, missing, or belongs to a different API key/project, Gemini may return
HTTP 403 with `PERMISSION_DENIED`; re-upload the local image and replace the
stale `files/ID` reference.

Generic edit references use this syntax:

```text
--ref ROLE[:LABEL]=files/ID,MIME
      |    |       |        |
      |    |       |        MIME type
      |    |       Gemini Files API resource name
      |    optional custom label
      reference role
```

Valid roles are `scene`, `character`, `object`, `style`, `pose`,
`composition`, `background`, `texture`, and `image`.

Later references may omit `LABEL`; `nbimg` then assigns deterministic labels
such as `SCENE_REFERENCE_A`, `CHARACTER_A`, `OBJECT_A`, and
`STYLE_REFERENCE_A`. Custom labels must be unique ASCII `SCREAMING_SNAKE_CASE`,
start with a letter, and be at most 64 bytes. `BASE_IMAGE` is reserved.

The current model limits edit inputs to 14 total images including the base
image, at most 4 character references including a character base, and at most 10
object references including an object base.

For example:

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --ref object:OBJECT_SHOE=files/shoe123,image/png \
  --ref style:STYLE_POSTER=files/poster789,image/webp \
  --prompt "Edit BASE_IMAGE so CHARACTER_HERO wears OBJECT_SHOE, using STYLE_POSTER only for the rendering style"
```

More later-reference examples:

```sh
--ref style=files/watercolor789,image/webp
--ref pose:POSE_MAIN=files/pose123,image/jpeg
--ref background:BACKGROUND_CITY=files/city123,image/webp
--ref texture=files/fabric123,image/png
--ref image=files/general123,image/jpeg
```

Useful edit flags:

```sh
--ref ROLE[:LABEL]=files/ID,MIME
--preserve TEXT
--do-not TEXT
--aspect-ratio RATIO
--image-size SIZE
--temperature FLOAT
--top-p FLOAT
--seed INT
--max-output-tokens INT
--presence-penalty FLOAT
--frequency-penalty FLOAT
--stop TEXT
--response-logprobs
--logprobs INT
--system TEXT
--cached-content cachedContents/ID
--service-tier flex|standard|priority
--store
--no-store
--grounding none|web|image|web,image
--thinking-level minimal|high
--include-thoughts
--safety none|off|permissive|balanced|strict
--out-dir DIR
```

`--preserve TEXT` and `--do-not TEXT` are repeatable task-level constraints.
Empty `--preserve ""` and `--do-not ""` values are rejected. Omitting these
flags renders no extra preserve or do-not section. Each list is capped at 16
entries, and each value is capped at `16 KiB`.

Generated `generateContent` request envelopes are bounded before JSON
serialization: one content entry, 32 total content plus system-instruction
parts, 16 KiB text fields, 512-byte File API URIs, 64-byte MIME strings, and 5 MiB
of counted variable request fields including stop sequences. Uploaded file
bytes are not counted because edit requests reference Gemini Files by URI.

List uploaded file metadata:

```sh
zig-out/bin/nbimg files list
```

Get one uploaded file's metadata:

```sh
zig-out/bin/nbimg files get --name files/abc123
```

Delete one uploaded file:

```sh
zig-out/bin/nbimg files delete --name files/abc123
```

`--name` is required once for `files get` and `files delete`. It must use
canonical `files/...` form; bare file IDs are rejected. `files list` has no
command-specific options.

The upload, list, and get commands print JSON metadata to stdout.
The delete command prints `OK` on success.

Files API uploads are temporary. Treat `expirationTime` in upload/list/get
metadata as the deadline for reusing a `files/ID` reference. A response like
`{"error":{"code":403,...,"status":"PERMISSION_DENIED"}}` from `files get`,
`files delete`, or `edit` is a strong signal that the file is no longer
accessible; check current uploads with `files list` or upload the image again.

Debug traffic:

```sh
zig-out/bin/nbimg gen \
  --print-request \
  --prompt "Create a photo of my fair lady"
```

Response traffic logs go to stderr by default. Use `--print-request` to also
log request traffic. `--print-request` is accepted by all commands; for
`files`, place it after the `upload`, `list`, `get`, or `delete` subcommand.
Response logs include `response_time_seconds` before HTTP status and body.
Gemini HTTP transactions time out after 180 seconds.
Command results, such as generated filenames, Files API metadata JSON, Batch
operation JSON, or delete `OK`, go to stdout.

## Testing

Run offline tests:

```sh
zig build test
```

Live API tests are opt-in and intended for validating request JSON shapes
against the real Gemini API:

```sh
zig build test-live-api-generate-content-request-validity
zig build test-live-api-edit-request-validity
zig build test-live-api-files-upload-list
zig build test-live-api-files-get
zig build test-live-api-files-delete
zig build test-live-api-batch-list
zig build test-live-api-batch-submit-status
```

`generateContent` is billable, so the request-shape live tests for `gen` and
`edit` use `countTokens` as a lower-cost validation endpoint instead of
generating content. The `gen` and `edit` request-shape live tests include
`web,image` grounding, `thinkingConfig`, and representative advanced
generation and request-level controls to validate the tool-bearing, Thinking,
`generationConfig`, `systemInstruction`, `serviceTier`, and `store` request
shape. Cached-content live validation requires an existing
`cachedContents/...` resource and is not part of the default live tests. The
edit request-shape live test uploads `sample_images/good_night.jpeg` through
the Files API, validates the edit request with the uploaded `files/...` name,
and deletes the uploaded file after validation.

`test-live-api-batch-list` is non-billable and read-only. It follows all
available Batch list pages, validates canonical operation names, and formats
the aggregate response without creating a job.

`test-live-api-batch-submit-status` is explicitly billable and
non-idempotent. It builds two `512` image-generation JSONL entries without
`thinkingConfig`, uploads the input, creates exactly one Batch job, captures
the returned `batches/...` name, performs one status GET, requests
cancellation, and confirms the operation remains retrievable. The uploaded
JSONL File and cancelled Batch job are left in the remote service.
