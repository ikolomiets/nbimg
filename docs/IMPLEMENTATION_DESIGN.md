# Implementation Design

This document describes the current implementation of `nbimg`. It is a
snapshot of the code that exists today, not the full product design in
`docs/Nano_Banana_CLI_Tool_Design.md`.

## Current Scope

`nbimg` is a minimal Zig 0.16.0 command line tool for Gemini native image
generation. The implemented command surface is:

```sh
nbimg gen [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] [--prompt "PROMPT"]
nbimg edit [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
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

The current build stays stdlib-only and keeps the module layout flat. The
binary accepts one prompt through `--prompt` or stdin fallback, sends fixed
generation or edit requests to the Gemini API, decodes image or text parts from
the response, and writes each generated part to the selected output directory
or current working directory. Generation and edit requests can optionally
enable Google Search or Image Search grounding, set Gemini Thinking level, and
request returned thought parts, set one Gemini safety threshold across all
emitted safety categories, or set advanced generation controls such as
sampling, seed, output-token budget, stop sequences, and logprob diagnostics,
or set request-level controls such as system instructions, cached content,
service tier, and request storage.
Instead of immediate generation, `gen` and `edit` can validate the same
`GenerateContentRequest` through `countTokens` and append it to a Batch API
JSONL input file.
It can also upload image files to Gemini's Files API, list or get uploaded file
metadata, delete uploaded files, validate and upload Batch JSONL, create one
Batch job, fetch one current Batch operation, request cancellation, and list
all recent Batch jobs. It can also check a completed Batch once, download its
bounded output JSONL, and write decoded inline images.

The current implementation does not yet support chat, model selection, output
file naming controls, local image inputs for `edit`, response snapshots, or
Batch streaming uploads.

## Module Layout

The code is split into eight source files:

- `src/main.zig` is the executable entrypoint. It calls `nbimg.cli.run(init)`
  and exits with the returned process status.
- `src/root.zig` exposes the package modules as `api`, `batch`, `cli`, `gen`,
  `edit`, and `files`.
- `src/cli.zig` owns user-facing command parsing, diagnostics, environment
  lookup, request dispatch, response handling, generated file writing, and
  locked Batch JSONL appends.
- `src/api.zig` owns shared Gemini API infrastructure: model constants, common
  HTTP response ownership, canonical `files/...` name validation, traffic
  logging options, transport helpers, image MIME parsing and serialization,
  Thinking/output/generation/grounding wire helpers, shared generateContent
  request bounds and envelope assembly, generateContent/countTokens JSON posting,
  generic resumable byte uploads, generated response decoding and output
  naming, and response log sanitization.
- `src/batch.zig` owns Batch JSONL entry serialization and validation, Batch
  input upload configuration, create/status/cancel/list request construction,
  canonical `batches/...` validation, response-name and list-page decoding,
  bounded output download, output-record decoding, safe output keys, pagination
  token handling, and full JSON pretty-printing.
- `src/gen.zig` owns `gen`-specific API behavior: prompt content construction
  for generateContent and countTokens requests.
- `src/edit.zig` owns `edit`-specific API behavior: uploaded image reference
  content construction, edit manifest text, File API URI derivation, and
  countTokens wrapping.
- `src/files.zig` owns Files API behavior: upload/list/get/delete request
  construction, upload/list/get response decoding, and
  Files API endpoint handling.

The public API namespace is intentionally split by command domain:

```zig
nbimg.gen.*
nbimg.edit.*
nbimg.files.*
nbimg.batch.*
```

Shared controls such as `nbimg.api.traffic_log_options` remain directly under
`nbimg.api`.

### API Module Boundaries

The CLI module owns user interaction and filesystem effects: reading upload
files, writing generated files, appending Batch JSONL entries, printing
receipts or uploaded file IDs, and translating parse or API errors into process
exit codes. API modules own only request/response wire shapes and HTTP
transport.

Command-domain modules must not depend on each other. `src/gen.zig`,
`src/edit.zig`, `src/files.zig`, and `src/batch.zig` may import only
`api.zig`, `std`, and `build_options` for project-local/shared functionality.
Cross-command workflows
such as uploading a file and then validating an edit request belong in
`src/cli.zig`.

Treat these module boundaries as part of the implementation design, not as
descriptive afterthoughts. Before adding a type, parser, serializer, endpoint
helper, or response decoder, pick the owning module and check sibling command
modules for the same concept. Repeated Gemini wire rules, MIME handling,
canonical resource-name handling, transport behavior, logging behavior, or
response decoding logic should be centralized in `src/api.zig` instead of
copied into command modules. Command modules should remain narrow so duplicate
internal enums and conversion helpers do not accumulate.

`src/gen.zig` owns Gemini native image generation semantics for the fixed
`nano2` model. It builds the prompt content for the shared
`GenerateContentRequest` JSON, wraps that shape for `countTokens`, and uses
shared API helpers to send generation and token-count requests.

`src/edit.zig` owns Gemini native image editing semantics for the fixed `nano2`
model. It accepts uploaded File API resource names plus MIME types, derives
their model-facing `file_uri` values from the common Gemini File API prefix,
interleaves role anchor text and `file_data` parts, and wraps the same request
shape for `countTokens`.

`src/files.zig` owns Gemini Files API semantics. It receives shared image MIME
types from `src/api.zig`, applies image extension and size policy, invokes the
shared resumable byte-upload transport, builds paginated list URLs and
file-resource get/delete URLs, and decodes uploaded/listed/fetched File
metadata.

`src/batch.zig` owns Gemini Batch API semantics. It validates complete JSONL
input and unique keys, enforces the 5 MiB serialized-entry and 512 MiB local
file limits, requires object-valued request JSON without semantically
validating the nested generateContent request, uploads bytes as
`application/jsonl`, submits the uploaded `files/...` name to the fixed image
model, builds status URLs from canonical `batches/...` names, builds paginated
list URLs, validates listed operation names, preserves complete operation
objects, and pretty-prints successful JSON responses.

`src/api.zig` owns shared transport, canonical File API resource-name
validation, canonical cached content name validation, shared
generateContent/countTokens endpoint URLs, countTokens
request envelope construction, countTokens response decoding, shared
generateContent request bounds and envelope construction, shared
generateContent/countTokens JSON posting helpers, generic resumable byte-upload
transport, shared response
modality values, image MIME
parsing/serialization for edit references and file uploads, generation config
helpers, request-level control wire helpers, grounding tool wire structures,
generated response decoding, generated file metadata, output naming, safety
setting helpers, and logging.
`gen`, `edit`, and `files` reuse its JSON GET/POST/DELETE helpers, lower-level
request-with-body helper for resumable uploads, common `HttpResponse`
ownership type, `Model` constants, and global traffic logging switch. Headers
are not exposed through the logging path, so API keys stay out of diagnostic
output.

`build.zig` defines separate `nbimg` modules and executables for installed and
development artifacts. The installed `zig-out/bin/nbimg` executable is built in
ReleaseSafe. The `run` step builds and executes a separate Debug executable from
the build cache. The normal offline `test` step and dedicated live API test
steps also compile Debug artifacts for faster feedback.

The `test` step builds test roots from `src/api.zig`, `src/batch.zig`,
`src/gen.zig`, `src/edit.zig`, `src/files.zig`, and `src/cli.zig` so tests
stay close to their owning modules. Tests receive a generated `build_options` module with
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
nbimg gen [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] [--prompt "PROMPT"]
nbimg edit [--api-key KEY] [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
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

Argument rules are intentionally narrow:

- The command name must be `gen`, `edit`, `files`, or `batch`.
- The `files` command requires an `upload`, `list`, `get`, or `delete`
  subcommand.
- The `batch` command requires a `submit`, `status`, `cancel`, `download`, or `list`
  subcommand.
- Every leaf command accepts one non-empty `--api-key KEY` option in any option
  order. The option is not accepted before `gen`, `edit`, or a `files`/`batch`
  subcommand.
- For `gen` and `edit`, `--prompt` is optional. If omitted, `cli.run` reads the
  prompt from stdin until EOF.
- Stdin prompts are preserved exactly, including trailing newlines, and are
  limited to `16 KiB`.
- Zero-byte stdin prompts report the same missing-prompt usage error as the old
  missing `--prompt` path.
- Explicit `--prompt` values must be one argument, so shell users need quotes
  for prompts with spaces. Quote presence is not visible to the process, so
  single-token prompts are accepted. Explicit prompt values are also limited to
  `16 KiB`.
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
- For `gen` and `edit`, advanced generation options are optional and omitted
  from JSON unless explicitly set. Supported controls are `--temperature`
  (`0.0..2.0`), `--top-p` (`0.0..1.0`), `--seed` (signed 32-bit decimal
  integer), `--max-output-tokens` (`1..32768`), `--presence-penalty` and
  `--frequency-penalty` (`-2.0 <= value < 2.0`), repeatable `--stop TEXT`
  (non-empty, unique, at most 5), `--response-logprobs`, and `--logprobs`
  (`1..20`).
- `--response-logprobs` is valid by itself and requests chosen-token log
  probability diagnostics. `--logprobs` requests top-token alternatives and is
  valid only when `--response-logprobs` is also explicitly present. These
  diagnostics are not image confidence scores.
- For `gen` and `edit`, request-level controls are optional and omitted from
  JSON unless explicitly set. `--system TEXT` sends a non-empty text-only
  `systemInstruction` capped at `16 KiB`. `--cached-content cachedContents/ID`
  attaches an existing cached content resource and requires the canonical
  `cachedContents/...` form; raw cache IDs are rejected.
- `--service-tier TIER` accepts `flex`, `standard`, or `priority`. If omitted,
  `nbimg` does not serialize `serviceTier`, so Gemini uses the project and
  model default. If `priority` is requested and the successful response reports
  `usageMetadata.serviceTier` as `standard`, `nbimg` prints a non-fatal
  warning.
- `--store` and `--no-store` are mutually exclusive request-level flags.
  `--store` serializes `store: true`; `--no-store` serializes `store: false`.
  If both are omitted, `nbimg` omits `store` and leaves project-level logging
  behavior unchanged.
- `--batch-file PATH` is optional for `gen` and `edit`. It is accepted at most
  once, cannot be combined with `--out-dir`, and changes execution from
  immediate `generateContent` to `countTokens` validation followed by a JSONL
  append.
- `--batch-key KEY` is optional, non-empty, accepted at most once, and valid
  only with `--batch-file`. Explicit keys must be unique within the target
  file. If omitted, the key is `nbimg-<offset>`, where `offset` is the locked
  byte position at which the JSON entry starts.
- Batch appends create the file when absent and hold an exclusive advisory lock
  while scanning existing entries and writing. Existing lines must be valid
  objects with a non-empty `key` and an object-valued `request`; the nested
  request is not semantically revalidated during append. Each serialized JSONL
  entry is capped at `5 MiB` during local validation.
- The appended line is `{"key":"...","request":{...}}`, using the exact
  `GenerateContentRequest` validated by `countTokens`. HTTP failure or an
  invalid token-count response leaves the file untouched.
- A successful append prints
  `{"key":"...","totalTokens":N,"batchFile":"..."}` to stdout. In batch mode,
  `--print-request` logs the `countTokens` envelope to stderr.
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
  only visible in the existing stderr response log. Thought image parts are not
  written as sidecar files.
- For `gen` and `edit`, `--safety LEVEL` is optional and accepted at most
  once. Valid levels are `none`, `off`, `permissive`, `balanced`, and
  `strict`. If omitted, `nbimg` does not send `safetySettings`. The levels
  serialize as `BLOCK_NONE`, `OFF`, `BLOCK_ONLY_HIGH`,
  `BLOCK_MEDIUM_AND_ABOVE`, and `BLOCK_LOW_AND_ABOVE` respectively, and the
  selected threshold is applied to every safety category that `nbimg` emits.
- `--safety` controls only Gemini's adjustable request-level
  `safetySettings`. Google's Gemini safety documentation describes additional
  built-in protections that are not controlled by client safety settings and
  may still block prompts, responses, or image generation. `nbimg` exposes both
  `none` and `off` for API coverage without defining the exact image-generation
  behavior difference between those two thresholds.
- For `edit`, at least one `--ref ROLE=files/ID,MIME` is required. The first
  `--ref` is the base image to edit and is always labeled `BASE_IMAGE`; it
  must not include a custom label.
- Image `files/...` resource names must be canonical and MIME values must be
  `image/jpeg`, `image/png`, or `image/webp`.
- `edit` does not call `files get` before generation. The CLI derives
  `file_uri` by appending the canonical resource name to
  `https://generativelanguage.googleapis.com/v1beta/`.
- Expired, deleted, missing, or cross-project `files/...` references are not
  detected locally. Gemini commonly reports inaccessible file resources as HTTP
  403 with `PERMISSION_DENIED`; callers should check `expirationTime` and
  re-upload stale references.
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
  implementation currently caps each list at 16 non-empty entries. Each
  non-empty constraint value is capped at `16 KiB`.
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
- For `batch submit`, `--path` is required exactly once and
  `--display-name NAME` is optional at most once. The default is the complete
  basename, including `.jsonl`.
- For `batch status` and `batch cancel`, `--name` is required exactly once and
  must use canonical `batches/...` form; bare IDs are rejected.
- `batch download` has the same `--name` rule and optionally accepts one
  non-empty `--out-dir DIR`.
- `batch list` accepts no command-specific flags or positional arguments. It
  does not expose the Batch API's undocumented `filter` parameter.
- Response traffic is logged by default for all CLI commands.
- `--print-request` is an optional boolean flag on all commands. Its default
  value is `false`.
- `--out-dir DIR` is supported by `gen`, `edit`, and `batch download`; other
  files and batch commands reject it.
  The directory path may be relative or absolute, must be non-empty, must be
  specified at most once, and must already exist. It is mutually exclusive with
  `--batch-file`.
- Flags may appear in any order.
- Unknown flags and positional prompt arguments are rejected.

`cli.run` returns explicit status codes:

- `0` for success.
- `1` for operational failure, such as an HTTP failure or file write failure.
- `2` for usage and configuration errors, such as bad arguments or a missing
  API key.
- `3` for successful HTTP responses whose JSON body cannot be parsed for
  generated files, File metadata, Batch operation JSON, or a Batch list page.

Diagnostics are written with `std.debug.print`. Usage errors print a short
specific error followed by:

```text
usage: nbimg gen [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] [--prompt "PROMPT"]
       nbimg edit [--print-request] [--batch-file PATH [--batch-key KEY] | --out-dir DIR] [--system TEXT] [--cached-content cachedContents/ID] [--service-tier TIER] [--store|--no-store] [--aspect-ratio RATIO] [--image-size SIZE] [--temperature FLOAT] [--top-p FLOAT] [--seed INT] [--max-output-tokens INT] [--presence-penalty FLOAT] [--frequency-penalty FLOAT] [--stop TEXT] [--response-logprobs] [--logprobs INT] [--grounding MODE] [--thinking-level LEVEL] [--include-thoughts] [--safety LEVEL] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
       nbimg files upload [--print-request] [--display-name NAME] --path PATH
       nbimg files list [--print-request]
       nbimg files get [--print-request] --name files/ID
       nbimg files delete [--print-request] --name files/ID
       nbimg batch submit [--print-request] [--display-name NAME] --path PATH
       nbimg batch status [--print-request] --name batches/ID
       nbimg batch cancel [--print-request] --name batches/ID
       nbimg batch download [--print-request] --name batches/ID [--out-dir DIR]
       nbimg batch list [--print-request]

edit reference details:
       first --ref is the BASE_IMAGE and must omit LABEL
       later --ref ROLE[:LABEL]=files/ID,MIME references may include LABEL
       valid ROLE values: scene|character|object|style|pose|composition|background|texture|image
       omitted LABEL auto-assigns by role: SCENE_REFERENCE_A, CHARACTER_A, OBJECT_A, STYLE_REFERENCE_A, POSE_REFERENCE_A, COMPOSITION_REFERENCE_A, BACKGROUND_REFERENCE_A, TEXTURE_REFERENCE_A, IMAGE_REFERENCE_A
       MIME must be image/jpeg, image/png, or image/webp

output image options:
       --aspect-ratio accepts 1:1, 1:4, 1:8, 2:3, 3:2, 3:4, 4:1, 4:3, 4:5, 5:4, 8:1, 9:16, 16:9, or 21:9
       --image-size accepts 512, 1K, 2K, or 4K

advanced generation options:
       --temperature accepts 0.0 to 2.0
       --top-p accepts 0.0 to 1.0
       --seed accepts a signed 32-bit decimal integer
       --max-output-tokens accepts 1 to 32768
       --presence-penalty and --frequency-penalty accept -2.0 up to but not including 2.0
       --stop accepts up to 5 non-empty unique stop sequences and may be repeated
       --response-logprobs enables chosen-token log probability diagnostics
       --logprobs accepts 1 to 20 and requires --response-logprobs

request-level options:
       --system sends a text-only Gemini systemInstruction
       --cached-content requires canonical cachedContents/ID form
       --service-tier accepts flex, standard, or priority
       --store sends store:true; --no-store sends store:false; omit both to use project defaults

grounding options:
       --grounding accepts none, web, image, or web,image

thinking options:
       --thinking-level accepts minimal or high
       --include-thoughts requests returned thought parts; thought parts stay in the response log only

safety options:
       --safety accepts none, off, permissive, balanced, or strict
```

## Authentication

The CLI resolves one non-empty API key with this precedence:

1. `--api-key KEY` on the leaf command.
2. `GEMINI_API_KEY` from the inherited process environment.

An explicit key overrides the environment even when `GEMINI_API_KEY` is empty.
If `--api-key` is omitted, a missing or empty environment value is a usage
error. Missing, empty, and repeated `--api-key` values are also usage errors.

The selected key is a borrowed slice from either the process argument storage
or environment map, both of which remain alive during command dispatch.
Environment validation remains centralized in `api.apiKeyFromMap`; CLI
precedence is handled by `cli.resolveApiKey`.

The key is passed only as an `x-goog-api-key` HTTP header. It is not written
into request JSON, traffic logs, diagnostics, or output files. Environment
configuration remains preferable for routine use because command-line values
may appear in shell history or process listings.

`GOOGLE_API_KEY` fallback and key files are not implemented.

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
  }
}
```

The prompt is asserted to be non-empty before request construction. This is a
programmer boundary check; user-facing validation happens earlier in `cli.run`
and the CLI argument parser.

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

`nbimg` intentionally does not expose generated image `mimeType` or `delivery`
controls yet. Image MIME selection is not user-configurable because only
`IMAGE_JPEG` is currently useful for this model. URI delivery is also not
implemented because live billable `generateContent` validation rejected
explicit `responseFormat.image.delivery` values, including both `INLINE` and
`URI`, even though `countTokens` accepted those request shapes.

When advanced generation controls are set, `gen` and `edit` add the matching
lower-camel Gemini fields to the same `generationConfig` object:

```json
{
  "generationConfig": {
    "responseModalities": ["TEXT", "IMAGE"],
    "maxOutputTokens": 4096,
    "temperature": 0.7,
    "topP": 0.95,
    "seed": 42,
    "presencePenalty": 0.0,
    "frequencyPenalty": 0.0,
    "responseLogprobs": true,
    "logprobs": 1,
    "stopSequences": ["END"]
  }
}
```

Unset generation controls are omitted instead of serializing model defaults.
`--response-logprobs` serializes `responseLogprobs: true` even when
`--logprobs` is omitted. `--logprobs` serializes only after the parser has
confirmed that `--response-logprobs` was also explicitly provided.

Request-level controls are represented separately from `generationConfig` in
`api.RequestOptions` and serialize as top-level `GenerateContentRequest`
fields for both `gen` and `edit`:

```json
{
  "systemInstruction": {
    "parts": [
      {
        "text": "Use editorial lighting."
      }
    ]
  },
  "cachedContent": "cachedContents/brand",
  "serviceTier": "priority",
  "store": false
}
```

`--system` is text-only, non-empty, and capped at `16 KiB`.
`--cached-content` must already be in canonical `cachedContents/...` form.
`--service-tier` accepts only `flex`, `standard`, and `priority`;
`unspecified` is not exposed because omitting the flag already leaves Gemini's
default routing in effect. `--store` and `--no-store` are mutually exclusive
and are also omitted by default.

The CLI checks successful responses for `usageMetadata.serviceTier`. If the
request asked for `priority` but the response reports `standard`, it prints a
warning and continues response decoding normally.

`api.buildGenerateContentRequestJson` validates outgoing `generateContent`
request models before JSON serialization with shared TigerStyle assertions:

- at most 1 `contents[]` entry,
- at most 32 total request parts, counted as all `contents[].parts` plus an
  optional one-part `systemInstruction`,
- each text part and system instruction at most 16 KiB,
- each `file_data.file_uri` at most 512 bytes,
- each `file_data.mime_type` at most 64 bytes,
- at most 5 MiB of counted variable request fields.

The 5 MiB counted field total includes content text parts, system-instruction
text, File API URIs, MIME strings, `cachedContent` names, and stop sequences
before JSON serialization. Fixed JSON field names, enum literals, booleans,
and JSON escaping overhead are excluded. Uploaded file bytes are also excluded
because current edit requests send Gemini Files API URIs rather than inline
image data.
CLI parsing rejects oversized user-controlled text fields first; the shared API
assertions are paired programmer-error checks for request builders.

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

`api.safetySettingsFromOptions` supplies the top-level `safetySettings` array
when `--safety` is present. It configures harassment, hate speech, sexually
explicit, and dangerous content categories with the single threshold chosen by
`--safety`. If `--safety` is omitted, `safetySettings` is omitted from the
request.

```json
{
  "safetySettings": [
    { "category": "HARM_CATEGORY_HARASSMENT", "threshold": "OFF" },
    { "category": "HARM_CATEGORY_HATE_SPEECH", "threshold": "OFF" },
    { "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT", "threshold": "OFF" },
    { "category": "HARM_CATEGORY_DANGEROUS_CONTENT", "threshold": "OFF" }
  ]
}
```

The CLI intentionally does not expose per-category safety controls. Gemini's
public safety documentation describes these request-level settings as
adjustable filters and also describes built-in protections that are always
blocked and cannot be adjusted by the client. As a result, `--safety` should be
treated as request-level API coverage, not as a guarantee that image generation
will bypass every Google-controlled safety check.

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
  }
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
gemini-3.1-flash-image
```

The internal model enum names it `nano2`. `gen.generateContent` and
`edit.generateContent` send `POST` requests to:

```text
https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent
```

The HTTP request uses:

- `content-type: application/json`
- `user-agent: nbimg/0.0.0`
- `x-goog-api-key: <resolved API key>`

The full response body is buffered in memory. The current hard limit is:

```text
64 MiB
```

That limit is represented by `api.max_response_bytes`.

Each Gemini HTTP transaction has a hardcoded 180 second timeout, represented by
`api.http_request_timeout_seconds`. The timeout covers the network request and
response body read. If no complete response is available before the deadline,
transport helpers return `error.Timeout`.

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
response_time_seconds: 1
status: 200
body:
{...}
```

Only the endpoint URL, whole-second response time, and JSON bodies are logged.
Headers are not logged, so the `x-goog-api-key` value is not printed. Request
JSON is printed exactly. Response JSON is parsed for logging and known Gemini
base64 payload fields are redacted:

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

Non-OK responses are not parsed as File metadata. They are surfaced as normal
API failures with the HTTP status and raw response body, and the CLI exits with
failure. For inaccessible file resources, Gemini may return HTTP 403
`PERMISSION_DENIED`; this is a likely indication that a previously uploaded
reference has expired or been deleted, but it can also indicate a missing file
or a file from another API key/project.

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
for those cases. The same status is expected for expired uploads that are no
longer usable as edit references.

Files API traffic logging uses the same global logging switch as `gen`.
Headers are not logged. JSON request and response bodies are logged to stderr
with the same response sanitization path. Binary upload bodies are never
printed; the request log uses an omission marker containing the byte count and
MIME type. For `files upload`, `files list`, `files get`, and `files delete`,
traffic logs are separated from command results by using stderr for diagnostics
and stdout for metadata JSON or delete `OK`.

## Batch API

`nbimg batch submit --path PATH` reads one complete local JSONL input into
memory with a `512 MiB` limit. Before network IO, `batch.validateInputJsonl`
requires at least one non-empty line, valid JSON on every line, a non-empty
unique `key`, and an object-valued `request`. LF and CRLF separators are
accepted. Empty lines are rejected. The nested request object is not
semantically validated; its local bound is the `5 MiB` serialized JSONL entry
limit. The complete input is limited to `512 MiB`, and one batch is limited to
100 entries. `gen` and `edit` reject the 101st locked append before modifying
the file. `batch submit` rejects an input over 100 entries before upload or job
creation.

The validated bytes are uploaded through `api.uploadResumableBytes` with
`application/jsonl`. The shared transport owns the resumable upload start and
finalize requests. `files.zig` continues to own image extension/MIME validation
and image upload size policy; `batch.zig` owns Batch input MIME and limits.

By default, the complete `std.fs.path.basename(PATH)`, including `.jsonl`, is
used as both the uploaded File `displayName` and Batch job `displayName`.
`--display-name NAME` overrides both. Display-name UTF-8 and 512-code-point
validation is shared with Files uploads.

After a successful upload, submission sends exactly one request:

```text
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:batchGenerateContent
```

with:

```json
{
  "batch": {
    "displayName": "requests.jsonl",
    "inputConfig": {
      "fileName": "files/..."
    }
  }
}
```

Job creation is non-idempotent and has no retry loop. If transport fails after
the input upload, the CLI reports the uploaded `files/...` name and warns that
a job may have been created. A returned non-OK HTTP response is reported
without the ambiguous-creation warning. The uploaded JSONL remains in Gemini
Files storage in all cases.

A successful create response must be valid JSON and contain a canonical
`batches/...` name. The CLI then pretty-prints the complete response object
without reducing it to a local metadata struct.

`nbimg batch status --name batches/ID` validates the canonical resource name,
percent-encodes the ID path segment, and performs one request:

```text
GET https://generativelanguage.googleapis.com/v1beta/batches/{id}
```

Status does not poll or retry. A successful response is validated as JSON and
every returned field is printed as one pretty JSON document.

`nbimg batch cancel --name batches/ID` applies the same canonical-name
validation and path-segment encoding, then performs one bodyless request:

```text
POST https://generativelanguage.googleapis.com/v1beta/batches/{id}:cancel
```

Cancellation does not poll or retry. HTTP 200 prints `OK`; non-OK responses
include Gemini's response body in the diagnostic. Cancellation is best-effort,
so callers can use `batch status` to inspect whether the operation reached
`JOB_STATE_CANCELLED`. It does not delete the operation or its uploaded input.

`nbimg batch download --name batches/ID [--out-dir DIR]` performs exactly one
status GET. Status decoding accepts both the flattened API representation
(`JOB_STATE_SUCCEEDED`, `dest.fileName`) and the discovery-schema
representation (`BATCH_STATE_SUCCEEDED`, `output.responsesFile`), including
operation wrappers that place Batch fields under `metadata` or `response`.
Other states are rejected. If `batchStats.requestCount` is present and exceeds
100, the download is rejected before requesting the output file.

The output file is downloaded from:

```text
GET https://generativelanguage.googleapis.com/download/v1beta/files/{id}:download?alt=media
```

Batch output uses a separate `512 MiB` response limit, matching the Batch input
file limit. Normal non-Batch API responses remain limited to `64 MiB`. A known
`Content-Length` over the output limit fails before body allocation. A valid
known length reserves only that size. Without a length, the body starts with a
small allocation and grows incrementally without exceeding the configured
bound. Exactly `512 MiB` is accepted and the first byte beyond it is rejected.
Download traffic logging prints response metadata and an omitted-body byte
count instead of parsing or copying the complete JSONL for stderr.

The complete downloaded JSONL remains in memory. A preliminary line-count pass
rejects more than 100 records before file output, then records are decoded one
at a time. Each record requires a non-empty `key` and exactly one `response` or
`error`. Successful response objects reuse `api.decodeGeneratedFiles`; error
records, malformed records, duplicate keys, image decode failures, and write
failures are accumulated without stopping later records.

Output defaults to the current directory; `--out-dir` must already exist. A
missing output directory is reported clearly; a path that is not a directory
is reported with the supplied path. Filename keys percent-encode bytes outside
ASCII letters, digits, `-`, and `_`. Long encoded keys are bounded with a
SHA-256 suffix. Images use:

```text
{safe_key}-{candidate_index}-{part_index}.{extension}
```

Writes are exclusive. Successful filenames are printed to stdout. Existing
targets are reported to stderr with their destination paths and left
untouched; other failed records are reported by key. Any failed record or file
write makes the command exit nonzero after all records have been processed.

`nbimg batch list` repeatedly requests:

```text
GET https://generativelanguage.googleapis.com/v1beta/batches?pageSize=100
GET https://generativelanguage.googleapis.com/v1beta/batches?pageSize=100&pageToken={encoded-token}
```

The first request omits `pageToken`. Later requests percent-encode the opaque
`nextPageToken` using only RFC 3986 unreserved characters without escaping.
Listing follows pages until the service omits `nextPageToken` or returns it as
an empty string.

Each successful page must be a JSON object. An absent `operations` field is
treated as an empty array; when present it must be an array of objects. Every
operation must contain a canonical `batches/...` string name. Unknown operation
fields and number spellings are preserved by storing each complete operation
as owned JSON. After all pages are decoded, the CLI prints one pretty JSON
document:

```json
{
  "operations": []
}
```

The aggregated result never includes `nextPageToken`. Gemini's recent-job
history does not return deleted jobs. The API's undocumented `filter`
parameter is not exposed. Deletion of the uploaded input is not implemented.

## CountTokens Validation Helper

`gen.countGenerateContentRequestTokens` and
`edit.countGenerateContentRequestTokens` send the current generated request
shape to Gemini's `countTokens` endpoint:

```text
https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:countTokens
```

The command-level request body is built by `gen.buildCountTokensRequest` or
`edit.buildCountTokensRequest`. Both wrappers build their command-specific
`generateContent` JSON and then use the shared `api` countTokens envelope helper
to add the model field that Google requires inside nested
`generateContentRequest` payloads:

```json
{
  "generateContentRequest": {
    "model": "models/gemini-3.1-flash-image",
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
    }
  }
}
```

`api.decodeCountTokensResponse` extracts `totalTokens` and optional
`cachedContentTokenCount` from successful responses.

The live request-validity tests call these helpers directly. User-facing
`--batch-file` mode instead builds the command's `GenerateContentRequest` once,
wraps those exact bytes with
`api.buildCountTokensRequestFromGenerateContentJson`, posts the validation
request, and appends the original bytes with `batch.buildEntryJson` only
after a successful, decodable response.

A successful `countTokens` response means Google accepted the request for
tokenization; it does not prove that later Batch API execution will produce an
image or avoid safety, quota, billing, or output-shape failures.

The Batch input correlation key is supplied by `--batch-key` or derived from
the locked append offset. It is a per-input-file correlation key, not a
globally unique Gemini resource ID. `countTokens` does not return an identifier
suitable for this purpose.

This caveat applies directly to future `responseFormat.image` additions:
`countTokens` accepted explicit `delivery` values that billable
`generateContent` rejected. Before serializing future generated image
`mimeType` or `delivery` fields, validate them against billable
`generateContent` or a non-billable endpoint proven to match `generateContent`
for those fields.

## Response Decoding

`api.decodeGeneratedFiles` parses the response JSON with unknown fields
ignored. It looks for:

```text
responseId
candidates[].content.parts[]
```

Supported final image parts are converted into `GeneratedFile` values:

- Text parts are skipped for file output and remain visible only in the raw
  stderr response log.
- Inline image parts are base64-decoded and become image files.
- Parts with `thought: true` are treated as thought parts. Thought text is
  skipped for file output and remains visible only in the raw stderr response
  log. Thought inline image parts are skipped and are not written as sidecar
  files.
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

For example:

```text
PMMIapvKNtLj_uMPq8a8oQs-0-0.jpg
```

Writes are exclusive. If a target file already exists, the write fails instead
of overwriting it.

`cli.writeGeneratedFiles` asserts that at least one decoded file is present.
This assertion is paired with `api.decodeGeneratedFiles`, which rejects
responses that produce zero generated files.

Batch-file preparation does not write generated output. `cli.appendBatchRequest` opens or
creates the selected JSONL file with read/write access and an exclusive
advisory lock, validates existing entries while checking key uniqueness, and
writes the separator plus complete JSON line positionally at the locked file
end. Serialization and per-entry validation are owned by `batch.buildEntryJson`.
The locked scan also counts entries, and a full 50-entry file rejects another
append before writing. An `errdefer` truncates back to the original length if
the append fails partway through.

## Memory And Ownership

The executable receives `std.process.Init` and explicitly passes allocator and
IO handles through the call chain.

Allocator ownership is explicit:

- `cli.run` uses `init.arena.allocator()` to materialize process arguments.
- `gen.generateContent` receives `gpa` for request JSON, HTTP client state,
  response buffering, and the returned response body.
- `files.uploadFile` receives already-read file bytes; CLI filesystem IO
  stays in `src/cli.zig`.
- `batch.uploadInput` receives already-read validated JSONL bytes; CLI
  filesystem IO stays in `src/cli.zig`.
- `files.decodeUploadedFile` returns owned File metadata for upload
  responses. The CLI uses this for upload stdout.
  `files.decodeUploadedFileName` remains as a helper that returns only an
  owned copy of the uploaded `files/...` name.
- `files.decodeFile` and `files.decodeFileListPage` return owned File
  metadata. `decodeFileListPage` also returns an optional owned next page token.
- `batch.decodeListPage` returns owned JSON for every complete operation and
  an optional owned next page token. The CLI transfers those operation buffers
  into the aggregate list before deinitializing each page.
- `batch.decodeDownloadInfo` returns an owned generated `files/...` output name.
  `api.getBytesBounded` returns one owned output body while tracking the
  configured limit during incremental reads.
- `batch.decodeOutputRecord` owns one copied key and optional compact response
  object at a time. `cli.processBatchOutput` releases each record and decoded
  generated result before advancing to the next JSONL line.
- `api.decodeGeneratedFiles` receives `gpa` and returns owned decoded file
  buffers plus one owned response ID on the returned collection.
- `HttpResponse.deinit`, `FileListPage.deinit`, `batch.ListPage.deinit`,
  `GeneratedFile.deinit`, and `GeneratedFiles.deinit` release owned
  allocations.

Partial decode failures clean up already-decoded file buffers with `errdefer`.

## Tests

Current tests cover:

- Accepted and rejected CLI argument forms.
- The exact generated JSON request for `nbimg gen`.
- Request-level control parsing and JSON serialization for `gen` and `edit`.
- Grounding tool serialization for web, image, and combined web/image modes.
- The exact generated JSON request for `countTokens`.
- Decoding `countTokens` responses.
- Batch entry and receipt JSON serialization.
- Batch option parsing, output-directory conflicts, automatic offset keys,
  separator insertion, duplicate-key rejection, and malformed-file
  preservation.
- Batch submit/status/list parsing, canonical names, request JSON, endpoint
  URLs, list page-token encoding, arbitrary operation-field preservation,
  empty list responses, multi-page aggregation, malformed and duplicate JSONL
  rejection, local size limits, complete response pretty-printing, and
  ambiguous non-idempotent failure diagnostics.
- Shared image MIME name and upload path extension parsing.
- Files API upload display-name validation and upload-start metadata JSON,
  including JSON escaping.
- Decoding Files API upload, list, and get responses.
- Files API metadata JSON output shape, omitted optional fields, and string
  escaping.
- Files API file-resource URL construction and canonical file-name validation.
- Files API list URL page-token encoding.
- Redaction of known inline base64 fields in logged response JSON.
- Skipping text response parts while decoding mixed image and text responses.
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
zig build test-live-api-batch-list
zig build test-live-api-batch-submit-status
```

`GEMINI_API_KEY` is read from the inherited process environment through the
same common borrowed-key validation helper, so an already-exported variable is
enough.

`test-live-api-batch-list` is non-billable and read-only. It follows every
returned page, validates canonical operation names, and formats the aggregated
operation list without creating a Batch job.

`test-live-api-batch-submit-status` is explicitly billable and non-idempotent.
It builds two generation entries with `imageSize=512` and no `thinkingConfig`,
uploads one JSONL input, creates exactly one Batch job, captures the returned
canonical name, performs one status GET, requests cancellation, validates the
empty JSON response, and confirms the operation remains retrievable. The
remote uploaded File and cancelled job are intentionally retained.

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
`web,image` grounding, `thinkingConfig` with returned thoughts requested, and
representative advanced generation controls including sampling, seed, token
budget, penalties, stop sequences, and logprob diagnostics to validate those
request shapes through the same non-generation endpoint. It also includes a
text-only `systemInstruction`, `serviceTier: "standard"`, and `store: false`.
Cached content is not included in the default live check because it requires an
existing `cachedContents/...` resource.

The live edit request validity check lives in `src/cli.zig` because it
orchestrates both Files API upload/delete and edit `countTokens` validation. It
uploads `sample_images/good_night.jpeg` with the fixed display name
`nbimg live edit request validity`, uses the returned `files/...` name as the
edit base image with MIME `image/jpeg`, sends the edit request to `countTokens`,
and then deletes the uploaded file. The live edit request uses
`aspectRatio: "4:5"` and `imageSize: "1K"` at the CLI/options layer, which are
serialized as `ASPECT_RATIO_FOUR_BY_FIVE` and `IMAGE_SIZE_ONE_K`, to validate
output options on edit requests. It also enables `web,image` grounding. It
also includes `thinkingConfig` with returned thoughts requested, the same
representative advanced generation controls, a text-only `systemInstruction`,
`serviceTier: "standard"`, and `store: false`. It does not call
`generateContent`.

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
fails before cleanup, intentionally retain Batch input uploads, and can fail
due to quota or remote API errors. The Batch list target is read-only and
non-billable. The Batch submit/status target creates one billable
non-idempotent job.

## Known Gaps

The following areas are intentionally not implemented yet:

- Model selection and capability validation.
- Local image inputs without prior Files API upload.
- Generated image output `mimeType` and `delivery` controls, including URI
  delivery.
- Output directory, file prefix, and overwrite controls.
- Prompt files and additional prompt sources.
- Response snapshots.
- Batch streaming upload and explicit cleanup of uploaded JSONL input.
- Timeout and retry policy.
- Structured verbose output.
- Response fixture tests for full API payloads.
- Golden CLI-to-JSON tests through the executable boundary.
