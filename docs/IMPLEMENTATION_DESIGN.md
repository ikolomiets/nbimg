# Implementation Design

This document describes the current implementation of `nbimg`. It is a
snapshot of the code that exists today, not the full product design in
`docs/Nano_Banana_CLI_Tool_Design.md`.

## Current Scope

`nbimg` is a minimal Zig 0.16.0 command line tool for Gemini native image
generation. The implemented command surface is:

```sh
nbimg gen [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] [--prompt "PROMPT"]
nbimg edit [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
nbimg files upload [--print-request] [--display-name NAME] --path PATH
nbimg files list [--print-request]
nbimg files get [--print-request] --name files/ID
nbimg files delete [--print-request] --name files/ID
```

The current build stays stdlib-only and keeps the module layout flat. The
binary accepts one prompt through `--prompt` or stdin fallback, sends fixed
generation or edit requests to the Gemini API, decodes image or text parts from
the response, and writes each generated part to the selected output directory
or current working directory. Generation and edit requests can optionally
enable Google Search or Image Search grounding, set Gemini Thinking level, and
request returned thought parts. It can also upload image files to Gemini's
Files API, list or get uploaded file metadata, and delete uploaded files.

The current implementation does not yet support chat, model selection, output
file naming controls, local image inputs for `edit`, or response snapshots.

## Module Layout

The code is split into seven source files:

- `src/main.zig` is the executable entrypoint. It calls `nbimg.cli.run(init)`
  and exits with the returned process status.
- `src/root.zig` exposes the package modules as `api`, `cli`, `gen`, `edit`,
  and `files`.
- `src/cli.zig` owns user-facing command parsing, diagnostics, environment
  lookup, request dispatch, response handling, and file writing.
- `src/api.zig` owns shared Gemini API infrastructure: model constants, common
  HTTP response ownership, canonical `files/...` name validation, traffic
  logging options, transport helpers, Thinking/output/grounding wire helpers,
  and response log sanitization.
- `src/gen.zig` owns `gen`-specific API behavior: generateContent and
  countTokens request construction, generated response decoding, generated file
  metadata, and output naming.
- `src/edit.zig` owns `edit`-specific API behavior: uploaded image reference
  request construction, edit manifest text, File API URI derivation, and
  countTokens wrapping.
- `src/files.zig` owns Files API behavior: upload/list/get/delete request
  construction, upload MIME detection, upload/list/get response decoding, and
  Files API endpoint handling.

The public API namespace is intentionally split by command domain:

```zig
nbimg.gen.*
nbimg.edit.*
nbimg.files.*
```

Shared controls such as `nbimg.api.traffic_log_options` remain directly under
`nbimg.api`.

### API Module Boundaries

The CLI module owns user interaction and filesystem effects: reading upload
files, writing generated files, printing uploaded file
IDs, and translating parse or API errors into process exit codes. API modules
own only request/response wire shapes and HTTP transport.

Command-domain modules must not depend on each other. `src/gen.zig`,
`src/edit.zig`, and `src/files.zig` may import only `api.zig`, `std`, and
`build_options` for project-local/shared functionality. Cross-command workflows
such as uploading a file and then validating an edit request belong in
`src/cli.zig`.

`src/gen.zig` owns Gemini native image generation semantics for the fixed
`nano2` model. It builds the `GenerateContentRequest` JSON, wraps that shape
for `countTokens`, decodes generated image/text parts, and formats response-ID
based output names.

`src/edit.zig` owns Gemini native image editing semantics for the fixed `nano2`
model. It accepts uploaded File API resource names plus MIME types, derives
their model-facing `file_uri` values from the common Gemini File API prefix,
interleaves role anchor text and `file_data` parts, and wraps the same request
shape for `countTokens`.

`src/files.zig` owns Gemini Files API semantics. It maps upload path extensions
to MIME types, performs resumable upload start/finalize calls, builds
paginated list URLs and file-resource get/delete URLs, and decodes
uploaded/listed/fetched File metadata.

`src/api.zig` owns shared transport, canonical File API resource-name
validation, shared generateContent/countTokens endpoint URLs, countTokens
request envelope construction, countTokens response decoding, shared response
modality values, grounding tool wire structures, static safety settings, and
logging. `gen`, `edit`, and `files` reuse its JSON GET/POST/DELETE helpers,
lower-level request-with-body helper for resumable uploads, common
`HttpResponse` ownership type, `Model` constants, and global traffic logging
switch. Headers are not exposed through the logging path, so API keys stay out
of diagnostic output.

`build.zig` defines separate `nbimg` modules and executables for installed and
development artifacts. The installed `zig-out/bin/nbimg` executable is built in
ReleaseSafe. The `run` step builds and executes a separate Debug executable from
the build cache. The normal offline `test` step and dedicated live API test
steps also compile Debug artifacts for faster feedback.

The `test` step builds test roots from `src/api.zig`, `src/gen.zig`,
`src/edit.zig`, `src/files.zig`, and `src/cli.zig` so tests stay close to
their owning modules. Tests receive a generated `build_options` module with
`live_api_tests = false` by default. Passing `-Dlive-api-tests` enables live
tests for a filtered test run.

Default builds produce the final ReleaseSafe executable:

```sh
zig build
```

Development runs compile Debug:

```sh
zig build run -- <args>
```

ReleaseSafe and Debug both keep `std.debug.assert` checks active. ReleaseFast
and ReleaseSmall are not used by this build graph because they optimize those
checks away.

## CLI Behavior

The CLI accepts:

```sh
nbimg gen [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] [--prompt "PROMPT"]
nbimg edit [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
nbimg files upload [--print-request] [--display-name NAME] --path PATH
nbimg files list [--print-request]
nbimg files get [--print-request] --name files/ID
nbimg files delete [--print-request] --name files/ID
```

Argument rules are intentionally narrow:

- The command name must be `gen`, `edit`, or `files`.
- The `files` command requires an `upload`, `list`, `get`, or `delete`
  subcommand.
- For `gen` and `edit`, `--prompt` is optional. If omitted, `cli.run` reads the
  prompt from stdin until EOF.
- Stdin prompts are preserved exactly, including trailing newlines, and are
  limited to `16 KiB`.
- Zero-byte stdin prompts report the same missing-prompt usage error as the old
  missing `--prompt` path.
- Explicit `--prompt` values must be one argument, so shell users need quotes
  for prompts with spaces. Quote presence is not visible to the process, so
  single-token prompts are accepted.
- Empty explicit prompt values are rejected.
- `gen` and `edit` accept optional `--aspect-ratio RATIO` and
  `--image-size SIZE` output controls. Aspect ratios must be one of `1:1`,
  `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`,
  `9:16`, `16:9`, or `21:9`. Image sizes must be `512`, `1K`, `2K`, or
  `4K`.
- The output controls may be provided independently. If both are omitted,
  `nbimg` omits `generationConfig.responseFormat` and leaves Gemini's output
  shape defaults unchanged.
- `gen` and `edit` request both text and image response parts by default with
  `generationConfig.responseModalities` set to `["TEXT", "IMAGE"]`. There is
  currently no user-facing flag for changing response modalities.
- For `gen` and `edit`, `--grounding MODE` is optional and accepted at most
  once. Valid modes are `none`, `web`, `image`, and `web,image`. If omitted or
  set to `none`, `nbimg` omits request `tools`.
- `--grounding web` enables Google Search grounding with a plain
  `google_search` tool. `--grounding image` enables Image Search grounding by
  sending `google_search.searchTypes.imageSearch`. `--grounding web,image`
  sends both `webSearch` and `imageSearch` under `searchTypes`.
- Grounding metadata is not separately decoded, saved, or printed. If Gemini
  returns `groundingMetadata`, it remains part of the raw response body and is
  visible through the default stderr response traffic log.
- Image Search grounding is for visual search context and currently cannot be
  used to search for people.
- For `gen` and `edit`, `--thinking-level LEVEL` is optional and accepted at
  most once. Valid levels are `minimal` and `high`. If omitted, `nbimg` omits
  `generationConfig.thinkingConfig.thinkingLevel`.
- `--include-thoughts` is optional and accepted at most once for `gen` and
  `edit`. It requests returned thought parts by setting
  `generationConfig.thinkingConfig.includeThoughts` to `true`. Thought text is
  only visible in the existing stderr response log. Thought image parts are
  saved beside final output files and use `thought` in the filename.
- For `edit`, at least one `--ref ROLE=files/ID,MIME` is required. The first
  `--ref` is the base image to edit and is always labeled `BASE_IMAGE`; it
  must not include a custom label.
- Image `files/...` resource names must be canonical and MIME values must be
  `image/jpeg`, `image/png`, or `image/webp`.
- `edit` does not call `files get` before generation. The CLI derives
  `file_uri` by appending the canonical resource name to
  `https://generativelanguage.googleapis.com/v1beta/`.
- `edit` accepts repeatable generic references with
  `--ref ROLE[:LABEL]=files/ID,MIME`, where `ROLE` is `scene`, `character`,
  `object`, `style`, `pose`, `composition`, `background`, `texture`, or
  `image`. Later references may include custom labels.
- If a later edit reference label is omitted, deterministic labels such as
  `SCENE_REFERENCE_A`, `CHARACTER_A`, `OBJECT_A`, and `STYLE_REFERENCE_A` are
  assigned. Custom labels must be unique ASCII `SCREAMING_SNAKE_CASE`, start
  with a letter, and be at most 64 bytes. `BASE_IMAGE` is reserved.
- `edit` enforces the Nano Banana 2 input image limits used by the current
  model: at most 14 total images including the first base reference, at most 4
  character references including a character base, and at most 10 object
  references including an object base.
- `edit` accepts repeatable `--preserve TEXT` and `--do-not TEXT` task-level
  constraints. Empty string values are accepted as no-ops. Omitted flags render
  no corresponding `PRESERVE FROM BASE_IMAGE` or `DO NOT` section, and the
  implementation currently caps each list at 16 non-empty entries.
- For `files upload`, the `--path` flag is required exactly once.
- Empty upload paths are rejected.
- For `files upload`, `--display-name NAME` is optional and accepted at most
  once. If omitted, the display name defaults to the local file name from
  `--path`.
- Display names are validated locally: explicit values and path-derived
  defaults must be non-empty, valid UTF-8, and at most 512 Unicode code points.
- `files upload` currently accepts `.jpg`, `.jpeg`, `.png`, and `.webp` paths.
- For `files get` and `files delete`, the `--name` flag is required exactly
  once.
- File names for `files get` and `files delete` must use canonical `files/...`
  resource names; bare IDs are rejected.
- Response traffic is logged by default for all CLI commands.
- `--print-request` is an optional boolean flag on all commands. Its default
  value is `false`.
- `--out-dir DIR` is supported by `gen` and `edit`; file commands reject it.
  The directory path may be relative or absolute, must be non-empty, must be
  specified at most once, and must already exist.
- Flags may appear in any order.
- Unknown flags and positional prompt arguments are rejected.

`cli.run` returns explicit status codes:

- `0` for success.
- `1` for operational failure, such as an HTTP failure or file write failure.
- `2` for usage and configuration errors, such as bad arguments or a missing
  API key.
- `3` for successful HTTP responses whose JSON body cannot be parsed for
  generated files.

Diagnostics are written with `std.debug.print`. Usage errors print a short
specific error followed by:

```text
usage: nbimg gen [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] [--prompt "PROMPT"]
       nbimg edit [--print-request] [--aspect-ratio RATIO] [--image-size SIZE] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--out-dir DIR] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
       nbimg files upload [--print-request] [--display-name NAME] --path PATH
       nbimg files list [--print-request]
       nbimg files get [--print-request] --name files/ID
       nbimg files delete [--print-request] --name files/ID

edit reference details:
       first --ref is the BASE_IMAGE and must omit LABEL
       later --ref ROLE[:LABEL]=files/ID,MIME references may include LABEL
       valid ROLE values: scene|character|object|style|pose|composition|background|texture|image
       omitted LABEL auto-assigns by role: SCENE_REFERENCE_A, CHARACTER_A, OBJECT_A, STYLE_REFERENCE_A, POSE_REFERENCE_A, COMPOSITION_REFERENCE_A, BACKGROUND_REFERENCE_A, TEXTURE_REFERENCE_A, IMAGE_REFERENCE_A
       MIME must be image/jpeg, image/png, or image/webp
```

## Authentication

The current implementation reads the API key from:

```text
GEMINI_API_KEY
```

The value must exist and must not be empty. The key is passed as an
`x-goog-api-key` HTTP header. It is not written into request JSON or output
files. Validation is centralized in `api.apiKeyFromMap`, which returns a
borrowed slice from the supplied environment map. Callers must keep that map
alive while the key is in use; the CLI uses `init.environ_map`, and live tests
create a temporary environment map from `std.testing.environ` in each live test
scope.

`GOOGLE_API_KEY`, key files, and explicit `--api-key` flags are not implemented
yet.

## Request Construction

`gen.buildGenerateRequest` builds the text-to-image request as Zig structs
and serializes it with `std.json.Stringify.value`. The request body currently
has this shape:

```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "PROMPT"
        }
      ]
    }
  ],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  },
  "safetySettings": [
    { "category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE" }
  ]
}
```

The prompt is asserted to be non-empty before request construction. This is a
programmer boundary check; user-facing validation happens earlier in `cli.run`
and `cli.parseArgs`.

When `--aspect-ratio`, `--image-size`, or both are provided, `gen` and `edit`
add `generationConfig.responseFormat.image` to the same request shape. CLI
values remain user-friendly (`16:9`, `2K`), but the REST payload uses Gemini's
accepted enum names:

```json
{
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"],
    "responseFormat": {
      "image": {
        "aspectRatio": "ASPECT_RATIO_SIXTEEN_BY_NINE",
        "imageSize": "IMAGE_SIZE_TWO_K"
      }
    }
  }
}
```

If only one output option is provided, only that field is emitted under
`responseFormat.image`.

When `--grounding` is `web`, `image`, or `web,image`, `gen` and `edit` add a
top-level `tools` array. The accepted grounding modes serialize as:

```json
{"tools":[{"google_search":{}}]}
```

```json
{"tools":[{"google_search":{"searchTypes":{"imageSearch":{}}}}]}
```

```json
{"tools":[{"google_search":{"searchTypes":{"webSearch":{},"imageSearch":{}}}}]}
```

Grounding metadata remains part of Gemini's ordinary response JSON. The
current implementation does not parse it into a separate type and does not
write sidecar attribution files.

When `--thinking-level`, `--include-thoughts`, or both are provided, `gen` and
`edit` add `generationConfig.thinkingConfig` to the same request shape:

```json
{
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"],
    "thinkingConfig": {
      "thinkingLevel": "high",
      "includeThoughts": true
    }
  }
}
```

`thinkingLevel` is omitted when `--thinking-level` is absent, and
`includeThoughts` is omitted unless `--include-thoughts` is set. `nbimg`
currently exposes only `minimal` and `high`.

`api.default_safety_settings` supplies the static top-level `safetySettings`
array for all `generateContent` requests. It configures harassment, hate
speech, sexually explicit, and dangerous content categories with `BLOCK_NONE`.
There are no CLI flags, environment variables, or command options to change
these settings.

`edit.buildGenerateRequest` builds image-editing requests with the same
`generateContent` endpoint and output config, but the user content contains an
ordered multimodal reference manifest. Every image is represented as nearby
role text followed by a `file_data` part. For example:

```json
{
  "contents": [
    {
      "parts": [
        {
          "text": "REFERENCE MANIFEST\n\nBASE_IMAGE:\nThe next image is the image to edit..."
        },
        {
          "file_data": {
            "mime_type": "image/jpeg",
            "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/tjtj5me9i96c"
          }
        },
        {
          "text": "EDIT TASK:\nApply this edit to BASE_IMAGE using the labeled references above:\nchange visual style to Broadway musical"
        }
      ]
    }
  ],
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"]
  },
  "safetySettings": [
    { "category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE" },
    { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE" }
  ]
}
```

For a parsed image input such as `files/tjtj5me9i96c,image/jpeg`, the edit
request builder derives:

```text
file_uri = "https://generativelanguage.googleapis.com/v1beta/" ++ "files/tjtj5me9i96c"
mime_type = "image/jpeg"
```

The builder does not validate file existence, state, expiration, or server-side
MIME metadata. Those remain Gemini API errors if the supplied `files/...` name
or MIME type is stale or wrong.

## Model And Endpoint

Only one model is currently wired:

```text
gemini-3.1-flash-image-preview
```

The internal model enum names it `nano2`. `gen.generateContent` and
`edit.generateContent` send `POST` requests to:

```text
https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:generateContent
```

The HTTP request uses:

- `content-type: application/json`
- `user-agent: nbimg/0.0.0`
- `x-goog-api-key: GEMINI_API_KEY`

The full response body is buffered in memory. The current hard limit is:

```text
64 MiB
```

That limit is represented by `api.max_response_bytes`.

`api.traffic_log_options` is a mutable global switch for API traffic logging.
The CLI enables response logging by default and request logging from
`--print-request`; API module defaults stay quiet for direct API callers and
tests. When enabled, the shared JSON transport logs framed request and response
data to stderr:

```text
--- nbimg api request ---
url: https://...
body:
{...}

--- nbimg api response ---
status: 200
body:
{...}
```

Only the endpoint URL and JSON bodies are logged. Headers are not logged, so the
`x-goog-api-key` value is not printed. Request JSON is printed exactly. Response
JSON is parsed for logging and known Gemini base64 payload fields are redacted:

```text
candidates[].content.parts[].inlineData.data
candidates[].content.parts[].thoughtSignature
```

For those known fields, only the JSON string value is replaced, for example:

```json
"data": "<base64 omitted: 123 decoded bytes>"
"thoughtSignature": "<base64 omitted: 456 decoded bytes>"
```

If base64 sizing fails, the value records the encoded byte count instead. The
original response body remains unchanged for decoding and file output.

## Files API

The `files` command uses Gemini's project-level Files API endpoints. It does
not take a model flag; the rest of the tool still uses the fixed internal
`nano2` model for generation and token validation.

Upload uses the resumable Files API flow:

```text
POST https://generativelanguage.googleapis.com/upload/v1beta/files
POST {x-goog-upload-url returned by the first response}
```

The first request starts the upload with JSON metadata. By default, the CLI uses
the local file name from `--path` as Gemini's `displayName` metadata field.
`--display-name NAME` overrides that value. The body is built through
`std.json.Stringify`:

```json
{"file":{"displayName":"NAME"}}
```

The second request uploads the file bytes and finalizes the upload. The CLI
reads the file into memory with a `64 MiB` limit represented by
`files.max_upload_bytes`. The accepted upload MIME types are:

- `.jpg` / `.jpeg` -> `image/jpeg`
- `.png` -> `image/png`
- `.webp` -> `image/webp`

On successful upload, `nbimg files upload` parses the upload response:

```json
{"file":{"name":"files/...","displayName":"..."}}
```

and prints normalized, pretty-printed File metadata JSON to stdout using the
same object shape as `files get`, without Gemini's outer `file` wrapper.
Callers that need the uploaded resource name should read the `name` field from
that JSON. Response decoding requires a non-empty `name`. The upload File
decoder also copies currently observed optional Gemini metadata fields when
present: `displayName`, `mimeType`, `sizeBytes`, `createTime`, `updateTime`,
`expirationTime`, `sha256Hash`, `uri`, `state`, and `source`.

Listing sends:

```text
GET https://generativelanguage.googleapis.com/v1beta/files?pageSize=100
```

and follows `nextPageToken` until exhausted. `nbimg files list` prints
pretty-printed JSON metadata to stdout with this shape:

```json
{
  "files": [
    {
      "name": "files/...",
      "displayName": "...",
      "mimeType": "image/jpeg"
    }
  ]
}
```

All pages are collected before stdout is written so the command emits one valid
JSON document. Optional metadata that Google omits is omitted from the output.
If the account has no files, the command prints the same object shape with an
empty `files` array.

Fetching one file sends:

```text
GET https://generativelanguage.googleapis.com/v1beta/files/{id}
```

`nbimg files get --name files/ID` requires the canonical `files/...` resource
name and strips the prefix internally when building the endpoint path. The file
ID path segment is percent-encoded. A successful response is decoded as one
File metadata object and printed to stdout as a pretty-printed JSON object with
the same camelCase field names returned by Gemini.

Deleting one file sends:

```text
DELETE https://generativelanguage.googleapis.com/v1beta/files/{id}
```

`nbimg files delete --name files/ID` uses the same canonical resource-name and
percent-encoded path behavior as `files get`. On HTTP 200 OK, the CLI prints
`OK` to stdout and exits 0. The success response body is not user-useful; the
live delete test asserts that Gemini currently returns an empty JSON object,
observed as `{}` plus trailing whitespace. Missing or already-deleted files are
surfaced as normal non-OK API failures, preserving the response body in
diagnostics; live validation currently observes HTTP 403 `PERMISSION_DENIED`
for those cases.

Files API traffic logging uses the same global logging switch as `gen`.
Headers are not logged. JSON request and response bodies are logged to stderr
with the same response sanitization path. Binary upload bodies are never
printed; the request log uses an omission marker containing the byte count and
MIME type. For `files upload`, `files list`, `files get`, and `files delete`,
traffic logs are separated from command results by using stderr for diagnostics
and stdout for metadata JSON or delete `OK`.

## CountTokens Validation Helper

`gen.countGenerateContentRequestTokens` and
`edit.countGenerateContentRequestTokens` send the current generated request
shape to Gemini's `countTokens` endpoint:

```text
https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image-preview:countTokens
```

The command-level request body is built by `gen.buildCountTokensRequest` or
`edit.buildCountTokensRequest`. Both wrappers build their command-specific
`generateContent` JSON and then use the shared `api` countTokens envelope helper
to add the model field that Google requires inside nested
`generateContentRequest` payloads:

```json
{
  "generateContentRequest": {
    "model": "models/gemini-3.1-flash-image-preview",
    "contents": [
      {
        "parts": [
          {
            "text": "PROMPT"
          }
        ]
      }
    ],
    "generationConfig": {
      "responseModalities": ["TEXT", "IMAGE"]
    },
    "safetySettings": [
      { "category": "HARM_CATEGORY_HARASSMENT", "threshold": "BLOCK_NONE" },
      { "category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "BLOCK_NONE" },
      { "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "BLOCK_NONE" },
      { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "BLOCK_NONE" }
    ]
  }
}
```

`api.decodeCountTokensResponse` extracts `totalTokens` and optional
`cachedContentTokenCount` from successful responses.

This helper is API-only. There is no user-facing CLI command for it yet. A
successful `countTokens` response means Google accepted the request for
tokenization; it does not prove that `generateContent` will produce an image or
avoid safety, quota, billing, or output-shape failures.

## Response Decoding

`gen.decodeGeneratedFiles` parses the response JSON with unknown fields
ignored. It looks for:

```text
responseId
candidates[].content.parts[]
```

Supported final parts and thought image parts are converted into
`GeneratedFile` values:

- Text parts become `.txt` files containing the returned UTF-8 text.
- Inline image parts are base64-decoded and become image files.
- Parts with `thought: true` are treated as thought parts. Thought text is
  skipped for file output and remains visible only in the raw stderr response
  log. Thought inline image parts are decoded, marked as thoughts, and written
  beside final output files.
- The root `responseId` is copied once into `GeneratedFiles` for output
  naming.

The decoder also accepts currently observed Gemini metadata fields such as
content `role`, part `thoughtSignature`, candidate `finishReason` and `index`,
root `usageMetadata`, `modelVersion`, and `responseId`. Metadata other than
`responseId` is parsed for shape compatibility but is not exposed to callers.

Supported inline MIME types are:

- `image/png` -> `.png`
- `image/jpeg` -> `.jpg`
- `image/webp` -> `.webp`

The decoder accepts the observed camelCase response field names for inline
data:

- `inlineData`
- `mimeType`

If root `responseId` is missing or empty, decoding fails with
`error.MissingResponseId`. If `responseId` is present but no supported final
parts are found, decoding fails with `error.NoGeneratedParts`, even when
thought parts were present. Unsupported part shapes, missing MIME types,
unsupported MIME types, missing inline data, invalid JSON, or invalid base64
are surfaced as parse failures by the CLI.

## Output Naming And Writes

Generated output is written to the current working directory by default, or to
the directory supplied with `--out-dir DIR`. `--out-dir` accepts relative and
absolute paths, and the directory must already exist. File names are derived
from the root response ID and response position:

```text
{responseId}-{candidate_index}-{part_index}.{extension}
```

Thought image filenames add a `thought` marker:

```text
{responseId}-{candidate_index}-thought-{part_index}.{extension}
```

For example:

```text
PMMIapvKNtLj_uMPq8a8oQs-0-0.jpg
PMMIapvKNtLj_uMPq8a8oQs-0-1.txt
PMMIapvKNtLj_uMPq8a8oQs-0-thought-2.jpg
```

Writes are exclusive. If a target file already exists, the write fails instead
of overwriting it.

`cli.writeGeneratedFiles` asserts that at least one decoded file is present.
This assertion is paired with `gen.decodeGeneratedFiles`, which rejects
responses that produce zero generated files.

## Memory And Ownership

The executable receives `std.process.Init` and explicitly passes allocator and
IO handles through the call chain.

Allocator ownership is explicit:

- `cli.run` uses `init.arena.allocator()` to materialize process arguments.
- `gen.generateContent` receives `gpa` for request JSON, HTTP client state,
  response buffering, and the returned response body.
- `files.uploadFile` receives already-read file bytes; CLI filesystem IO
  stays in `src/cli.zig`.
- `files.decodeUploadedFile` returns owned File metadata for upload
  responses. The CLI uses this for upload stdout.
  `files.decodeUploadedFileName` remains as a helper that returns only an
  owned copy of the uploaded `files/...` name.
- `files.decodeFile` and `files.decodeFileListPage` return owned File
  metadata. `decodeFileListPage` also returns an optional owned next page token.
- `gen.decodeGeneratedFiles` receives `gpa` and returns owned decoded file
  buffers plus one owned response ID on the returned collection.
- `HttpResponse.deinit`, `FileListPage.deinit`, `GeneratedFile.deinit`, and
  `GeneratedFiles.deinit` release owned allocations.

Partial decode failures clean up already-decoded file buffers with `errdefer`.

## Tests

Current tests cover:

- Accepted and rejected CLI argument forms.
- The exact generated JSON request for `nbimg gen`.
- Grounding tool serialization for web, image, and combined web/image modes.
- The exact generated JSON request for `countTokens`.
- Decoding `countTokens` responses.
- Files API upload MIME detection.
- Files API upload display-name validation and upload-start metadata JSON,
  including JSON escaping.
- Decoding Files API upload, list, and get responses.
- Files API metadata JSON output shape, omitted optional fields, and string
  escaping.
- Files API file-resource URL construction and canonical file-name validation.
- Files API list URL page-token encoding.
- Redaction of known inline base64 fields in logged response JSON.
- Decoding mixed image and text response parts.
- Rejection of empty candidate output.
- Rejection of unsupported image MIME types.
- Cleanup behavior when decoding fails after earlier parts succeed.
- Generated output filename formatting.

Use:

```sh
zig build test
```

to run all offline module and executable tests.

Live API validation is opt-in. Normal tests compile the live API tests but skip
them because `build_options.live_api_tests` defaults to `false`:

```sh
zig build test
```

To run one live API test through the normal test step, pass both
`-Dlive-api-tests` and an explicit `-Dtest-filter`:

```sh
zig build test -Dlive-api-tests -Dtest-filter="live API generateContent request shape is valid"
```

`build.zig` also provides dedicated side-effecting live API targets. Each one
builds the owning module as the test root, applies an exact filter, and inherits
stdio so request and response diagnostics written to stderr remain visible:

```sh
zig build test-live-api-generate-content-request-validity
zig build test-live-api-edit-request-validity
zig build test-live-api-files-upload-list
zig build test-live-api-files-get
zig build test-live-api-files-delete
```

`GEMINI_API_KEY` is read from the inherited process environment through the
same common borrowed-key validation helper, so an already-exported variable is
enough.

Live generation checks live in `src/gen.zig`. They send a
`GenerateContentRequest` shape with `responseFormat.image` to `countTokens`
using the prompt:

```text
My fair lady
```

This does not test the CountTokens API itself. It uses CountTokens as a
lower-cost validation endpoint to confirm that Gemini accepts the current
`GenerateContentRequest` JSON shape without calling paid content generation.
The live request uses `aspectRatio: "16:9"` and `imageSize: "2K"` to confirm
Gemini accepts the output-option wire shape after those CLI values are mapped
to `ASPECT_RATIO_SIXTEEN_BY_NINE` and `IMAGE_SIZE_TWO_K`. It also enables
`web,image` grounding and `thinkingConfig` with returned thoughts requested to
validate those request shapes through the same non-generation endpoint.

The live edit request validity check lives in `src/cli.zig` because it
orchestrates both Files API upload/delete and edit `countTokens` validation. It
uploads `sample_images/good_night.jpeg` with the fixed display name
`nbimg live edit request validity`, uses the returned `files/...` name as the
edit base image with MIME `image/jpeg`, sends the edit request to `countTokens`,
and then deletes the uploaded file. The live edit request uses
`aspectRatio: "4:5"` and `imageSize: "1K"` at the CLI/options layer, which are
serialized as `ASPECT_RATIO_FOUR_BY_FIVE` and `IMAGE_SIZE_ONE_K`, to validate
output options on edit requests. It also enables `web,image` grounding. It
also includes `thinkingConfig` with returned thoughts requested. It does not
call `generateContent`.

Live Files API checks live in `src/files.zig`. They upload
`sample_images/good_night.jpeg` with the fixed display name
`nbimg live api sample`, assert the returned file ID starts with `files/`,
check the returned `displayName` when Google includes it, list Files API
entries, assert the uploaded ID appears, and fetch that uploaded File through
`files.get`. The live delete target deletes an uploaded file, asserts the
success body parses as an empty JSON object, checks that `files.get` returns
403 afterward, checks a second delete returns 403, and probes a fixed missing
test name before asserting deleting that missing name also returns 403. Request
logging confirms the upload-start body uses `displayName` and file-resource
endpoints use `/v1beta/files/{id}`; response logging shows the actual File
fields and delete response bodies returned by Gemini for the current API
behavior. Live tests enable `api.traffic_log_options` for request and response
logging, require a non-empty `GEMINI_API_KEY`, perform network IO, may leave an
uploaded file in the Gemini Files API until Google expires it if a delete test
fails before cleanup, and can fail due to quota or remote API errors.

## Known Gaps

The following areas are intentionally not implemented yet:

- Model selection and capability validation.
- Image editing and multimodal input parts.
- Output directory, file prefix, and overwrite controls.
- Prompt files and additional prompt sources.
- Response snapshots.
- Timeout and retry policy.
- Structured verbose output.
- Response fixture tests for full API payloads.
- Golden CLI-to-JSON tests through the executable boundary.
