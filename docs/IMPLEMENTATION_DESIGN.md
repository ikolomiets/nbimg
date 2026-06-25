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

The code is split into eleven source files:

- `src/main.zig` is the executable entrypoint. It imports `src/cli.zig`
  directly, calls `cli.run(init)`, and exits with the returned process status.
- `src/root.zig` exposes the supported typed client declarations and retains
  the legacy package modules as `api` and `batch`.
  CLI implementation declarations are not package-accessible.
- `src/client.zig` owns the supported public client, generation and edit
  request domain types, shared option types, generated result ownership,
  returned validation errors, public Files and Batch-preparation methods,
  retained phase-one Batch request ownership, and conversion to and from the
  existing command wire paths.
- `src/operation.zig` owns shared `ApiFailure`, `Outcome(T)`, and internal
  stage-aware `OperationOutcome(T)` response types.
- `src/files_domain.zig` owns the public Files request, result, state, source,
  remote-error, validation-error, and upload-limit declarations.
- `src/cli.zig` owns user-facing command parsing, diagnostics, environment
  lookup, request dispatch, response handling, generated file writing, and
  locked Batch JSONL appends.
- `src/api.zig` owns shared Gemini API infrastructure: model constants, common
  HTTP response ownership, canonical `files/...` name validation, explicit
  request contexts, transport helpers, image MIME parsing and serialization,
  Thinking/output/generation/grounding wire helpers, shared generateContent
  request bounds and envelope assembly, generateContent/countTokens JSON posting,
  generic resumable byte uploads, generated response decoding, and response log
  sanitization.
- `src/batch.zig` owns public Batch input validation and prepared-entry value
  types, stable admission limits, legacy JSONL entry serialization, Batch input
  upload configuration, create/status/cancel/list request construction,
  canonical `batches/...` validation, response-name and list-page decoding,
  bounded output download, output-record decoding, safe output keys,
  pagination token handling, and full JSON pretty-printing.
- `src/gen.zig` owns `gen`-specific API behavior: prompt content construction
  for generateContent and countTokens requests.
- `src/edit.zig` owns `edit`-specific API behavior: uploaded image reference
  validation and content construction, edit manifest text, and File API URI
  derivation.
- `src/files.zig` owns Files API behavior: upload/list/get/delete request
  construction, typed response decoding and classification, and Files API
  endpoint handling.

The supported package API is a typed client:

```zig
const client = try nbimg.Client.init(allocator, io, .{
    .api_key = api_key,
});
var outcome = try client.generate(.{
    .prompt = "Create a cinematic product image",
});
```

`Client.init` borrows the API key and stores the allocator, `std.Io`, and a
positive timeout without allocating. The default timeout is 180 seconds.
Client operations create a quiet internal `api.RequestContext`; traffic
logging remains CLI-only.

`GenerationRequest` borrows the prompt, optional request strings, and stop
sequences. Public enums and option structs are separate from the legacy
`api.zig` wire types and expose no CLI spelling parsers, JSON serializers, or
wire helper methods. Validation returns `GenerationValidationError` before
allocation or network IO. It covers prompt/request bounds, generation numeric
ranges and dependencies, stop-sequence invariants, cached-content names, and
the shared 5 MiB aggregate variable-field bound.

`Client.generate` returns `Outcome(GenerationResult)`.
`GenerationResult` owns one response ID, an image slice, and every decoded
image byte buffer. `GeneratedImage.candidate_position` and `part_position` are
zero-based positions in the Gemini response arrays, independent of optional
candidate index metadata. The public MIME enum supports PNG, JPEG, and WebP.
The optional reported service tier is mapped to the public `ServiceTier` enum;
an unknown service-tier spelling returns `error.UnsupportedServiceTier`.
`GenerationResult.deinit` releases all nested storage.

`Client.countGenerateTokens` returns `Outcome(CountTokensResult)`. Both
operations reuse one private public-request-to-wire builder.

`EditRequest` borrows a required uploaded base image, optional labeled
references, preserve/do-not constraints, and the same generation/request
options. `InputImageMime` distinguishes uploaded JPEG, PNG, and WebP inputs
from generated `OutputMime` values. Edit validation runs before allocation or
network IO and covers canonical names, exact File URI and generated edit-task
bounds, labels, duplicate/reserved labels, total and role-specific image
limits, constraint limits, shared option rules, and the aggregate 5 MiB field
bound. `Client.edit` returns `Outcome(GenerationResult)`;
`Client.countEditTokens` returns `Outcome(CountTokensResult)`.

`generateWithContext` and `editWithContext` are internal public seams that
accept an explicit `api.RequestContext`. Both public and CLI callers accept
every completed 2xx response and reject unknown reported service tiers. The
generic `OperationOutcome(T)` distinguishes typed success, completed API
failure, and successful-response decoding failure. Public methods convert the
last case into a Zig error; CLI callers retain the stage to select diagnostics
and exit codes. Both immediate commands share result ownership,
priority-downgrade warnings, output writing, diagnostics, and exit-code
handling. Public client response traffic is not logged.

`Client.uploadFile`, `Client.getFile`, `Client.listFilesPage`, and
`Client.deleteFile` use quiet request contexts and typed context-taking
operations in `src/files.zig`. Uploads borrow bytes and optional display
metadata. File and page results own their nested allocations. Input validation
runs before allocation or network IO. Completed non-2xx responses preserve
their bounded bodies as `ApiFailure`; malformed successful response bodies are
Zig errors at the public method boundary.

`Client.prepareGenerationBatchEntry` and `Client.prepareEditBatchEntry` require
an explicit non-empty key and return `Outcome(PreparedBatchEntry)`. The key and
complete JSONL record are owned and released with
`PreparedBatchEntry.deinit`. The record omits its trailing newline. Each
operation builds one exact generate-content request, retains it through
countTokens validation, and inserts those bytes unchanged into the Batch
record. Internal `prepareGenerationBatchRequestWithContext` and
`prepareEditBatchRequestWithContext` seams expose the retained phase-one
request to CLI Batch mode so filesystem locking, automatic-key derivation, and
append rollback remain CLI-owned. Public callers use quiet contexts.

`validateBatchInput` performs allocation-free structural validation and returns
`BatchInputSummary`. It counts LF/CRLF-aware non-empty records and enforces
`max_batch_entry_bytes`, `max_batch_entries`, and `max_batch_input_bytes`
without parsing JSON. Legacy `batch.validateInputJsonl` and limit names remain
compatibility wrappers.

The remaining command-domain namespace is temporarily available:

```zig
nbimg.batch.*
```

Network operations use an internal `nbimg.api.RequestContext`; pure builders
and decoders remain independent of transport configuration.

The internal module interfaces are intentionally narrow:

- `cli` exports only `run` for executable assembly.
- `client` exports only the deliberate supported client declarations and their
  ownership methods plus context-taking generated-content and Batch phase-one
  seams and the generic internal operation outcome.
- `operation` exports only shared typed-operation outcome and API-failure
  ownership declarations.
- `files_domain` exports only deliberate public Files domain declarations.
- `gen` exports only generation-request construction for the typed client and
  CLI Batch-file preparation. Token-count request helpers remain
  module-internal.
- `edit` exports the CLI/client-consumed wire request models and limits,
  edit-specific bounded validation, generation-request construction, and label
  validation. Prompt-fragment and File URI builders remain internal.
- `files` exports only the four typed context-taking upload/get/list/delete
  operations shared by the public client and CLI. Raw transport helpers and
  typed response decoders remain private. Shared uploaded-name decoding is
  exposed only by `api`.
- `batch` exports the deliberate Batch input types, validation function, stable
  limits, and the CLI-consumed compatibility models, limits,
  ownership/iteration methods, upload/submit/status/download/cancel/list
  operations, response decoders, and JSONL/output helpers. Wire constants,
  submit serialization, byte-count validation, and URL construction remain
  internal.
- `api` exports only shared cross-module models, bounds, validators,
  generation/countTokens request assembly and transport, generic JSON
  transport, resumable upload support, response decoders, request context and
  traffic logging options, and ownership methods.
  Wire-only models, serializers, endpoint URL helpers, and lower-level request
  machinery remain internal.

The package contract and internal module seams have separate compile-time API
tests. `src/public_api_test.zig` imports `src/root.zig` and compares its
consumer-reachable package exports against an exact, order-independent
allowlist. `src/internal_module_api_test.zig` imports each implementation
module directly and applies separate exact allowlists to declarations and
public container methods that are visible for cross-file use. Both tests are
registered with `zig build test`, so a package export or internal seam change
requires an explicit decision in the corresponding allowlist. A separate
dependency-style compile test imports `nbimg` by module name through the build
graph and verifies that the typed workflow is usable without top-level raw
transport or request-context declarations.

### API Module Boundaries

The CLI module owns user interaction and filesystem effects: reading upload
files, writing generated files, appending Batch JSONL entries, printing
receipts or uploaded file IDs, and translating parse or API errors into process
exit codes. API modules own only request/response wire shapes and HTTP
transport.

Command-domain modules must not depend on each other. `src/gen.zig`,
`src/edit.zig`, and `src/batch.zig` may import only `api.zig`, `std`, and
`build_options` for project-local/shared functionality. `src/files.zig` may
additionally import the flat shared `files_domain.zig` and `operation.zig`
modules required by its typed operations. `src/client.zig` is the package
façade and may import `gen.zig`, `edit.zig`, `files.zig`, `files_domain.zig`,
`operation.zig`, and `api.zig` to convert validated public requests into the
existing internal request paths.
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
`nano2` model. It builds prompt content for the shared
`GenerateContentRequest` JSON used by the typed client and CLI Batch-file
preparation, and privately wraps that shape for countTokens live validation.

`src/edit.zig` owns Gemini native image editing semantics for the fixed `nano2`
model. It accepts uploaded File API resource names plus MIME types, derives
their model-facing `file_uri` values from the common Gemini File API prefix,
and interleaves role anchor text and `file_data` parts. The typed client uses
the resulting generateContent shape for immediate edits and countTokens; CLI
Batch-file preparation continues to call the internal builder directly.

`src/files.zig` owns Gemini Files API semantics. Its typed operations receive
public `FileUpload` values from `src/files_domain.zig`; the CLI converts
path-derived wire image MIME values before calling them. The module validates
typed uploads, canonical names, and page tokens, invokes the shared resumable
byte-upload transport, builds paginated list and file-resource URLs, and
decodes uploaded/listed/fetched File metadata.

`src/batch.zig` owns Gemini Batch API semantics. Its public structural validator
enforces the 5 MiB serialized-entry, 100-entry, and 512 MiB input limits and
returns byte and entry counts without parsing JSON. Prepared entries own their
explicit keys and complete newline-free JSONL records. Legacy submit validation
leaves entry JSON and key semantics to Gemini, uploads bytes as
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
generated response decoding, generated file metadata, safety setting helpers,
and logging. The CLI owns generated output naming.
`gen`, `edit`, and `files` reuse its JSON GET/POST/DELETE helpers, lower-level
request-with-body helper for resumable uploads, common `HttpResponse`
ownership type, `Model` constants, and explicit `RequestContext`. Headers are
not exposed through the logging path, so API keys stay out of diagnostic
output.

`build.zig` defines separate executable root modules for installed and
development artifacts. Each root is `src/main.zig`, receives `build_options`
directly, and imports `src/cli.zig` without going through the package root. The
installed `zig-out/bin/nbimg` executable is built in ReleaseSafe. The `run`
step builds and executes a separate Debug executable from the build cache. The
normal offline `test` step and dedicated live API test steps also compile Debug
artifacts for faster feedback.

The `test` step builds test roots from `src/api.zig`, `src/batch.zig`,
`src/gen.zig`, `src/edit.zig`, `src/files.zig`, `src/cli.zig`,
`src/public_api_test.zig`, and `src/internal_module_api_test.zig` so tests stay
close to their owning modules while package and internal module API boundaries
are independently enforced. Tests receive a generated `build_options` module
with `live_api_tests = false` by default. Passing `-Dlive-api-tests` enables
live tests for a filtered test run.

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
  constraints. Empty string values are rejected. Omitted flags render no
  corresponding `PRESERVE FROM BASE_IMAGE` or `DO NOT` section, and the
  implementation currently caps each list at 16 entries. Each constraint value
  is capped at `16 KiB`.
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

The internal model enum names it `nano2`. Typed generation and edit operations
send `POST` requests to:

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
JSON POST transport maps a body that exceeds the bound to
`error.ResponseTooLong` for both successful and non-successful statuses. It
does not return the buffered prefix as a partial response.

Each Gemini HTTP transaction receives its timeout from an explicit
`api.RequestContext`. The context defaults to 180 seconds, and the timeout
covers the network request and response body read. If no complete response is
available before the deadline, transport helpers return `error.Timeout`.

`api.RequestContext` contains the allocator, `std.Io`, borrowed API key,
positive timeout, and per-context traffic logging options. The CLI constructs
one context per invocation, enables response logging by default, and enables
request logging from `--print-request`. Quiet contexts perform no traffic
logging, and independent contexts do not share configuration. When enabled,
the shared JSON transport logs framed request and response data to stderr:

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

The supported library exposes typed Files operations:

- `Client.uploadFile(FileUpload) !Outcome(File)`
- `Client.getFile([]const u8) !Outcome(File)`
- `Client.listFilesPage(?[]const u8) !Outcome(FileListPage)`
- `Client.deleteFile([]const u8) !Outcome(void)`

`FileUpload` admits JPEG, PNG, and WebP bytes up to
`max_file_upload_bytes`. Empty or oversized bytes, invalid display names,
noncanonical `files/...` names, and present empty page tokens return
`FileValidationError` before allocation or network IO. A null page token
requests the first fixed-size page.

Typed File decoding requires a canonical owned name. Optional display name,
MIME, timestamp, hash, URI, and download URI strings are owned; returned MIME
is opaque because list/get can include non-image resources. `sizeBytes` is
parsed from the wire string into `?u64`; negative, malformed, or overflowing
values fail successful-response decoding. Absent state/source values and
`STATE_UNSPECIFIED`/`SOURCE_UNSPECIFIED` map to allocation-free
`.unspecified` tags. Other documented values map to known tags, while unknown
spellings are preserved as owned bytes.

A populated File processing error becomes `RemoteError`: its signed code is
optional, its message is required and owned, and non-null details are retained
as compact owned JSON. `File`, `FileListPage`, `FileState`, `FileSource`, and
`RemoteError` provide allocator-based `deinit` methods. All typed Files
operations accept every 2xx response. Delete discards any bounded successful
body without requiring JSON.

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
reads the file into memory with the public `64 MiB`
`max_file_upload_bytes` limit. The accepted upload MIME types are:

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
that JSON. Typed response decoding requires a canonical `files/...` name. The
CLI presentation includes `displayName`, `mimeType`, decimal-string
`sizeBytes`, `createTime`, `updateTime`, `expirationTime`, `sha256Hash`, `uri`,
`state`, and `source` when present. It intentionally omits typed-only
`download_uri` and `processing_error` metadata. Known state/source tags render
with uppercase wire spellings, unknown spellings are preserved, and normalized
`.unspecified` values are omitted.

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

Completed non-2xx responses are not parsed as File metadata. They are surfaced
as normal API failures with the HTTP status and raw response body, and the CLI
exits with failure. Every 2xx response is decoded as File metadata; malformed
successful metadata exits with the response-parse status. For inaccessible
file resources, Gemini may return HTTP 403
`PERMISSION_DENIED`; this is a likely indication that a previously uploaded
reference has expired or been deleted, but it can also indicate a missing file
or a file from another API key/project.

Deleting one file sends:

```text
DELETE https://generativelanguage.googleapis.com/v1beta/files/{id}
```

`nbimg files delete --name files/ID` uses the same canonical resource-name and
percent-encoded path behavior as `files get`. On any completed 2xx response,
the CLI prints `OK` to stdout and exits 0. The success response body is
discarded without decoding. Missing or already-deleted files are surfaced as
normal non-2xx API failures, preserving the response body in diagnostics; live
validation currently observes HTTP 403 `PERMISSION_DENIED` for those cases.
The same status is expected for expired uploads that are no longer usable as
edit references.

Files API traffic logging uses the same request-context options as `gen`.
Headers are not logged. JSON request and response bodies are logged to stderr
with the same response sanitization path. Binary upload bodies are never
printed; the request log uses an omission marker containing the byte count and
MIME type. For `files upload`, `files list`, `files get`, and `files delete`,
traffic logs are separated from command results by using stderr for diagnostics
and stdout for metadata JSON or delete `OK`.

## Batch API

`nbimg batch submit --path PATH` reads one complete local JSONL input into
memory with a `512 MiB` limit. Before network IO, `batch.validateInputJsonl`
requires at least one non-empty line, accepts LF and CRLF separators, rejects
empty lines, caps each serialized entry at `5 MiB`, and limits one batch to 100
entries. It does not parse entry JSON, check keys, or validate object-valued
requests during submit. `gen` and `edit` still reject the 101st locked append
before modifying the file. `batch submit` rejects an input over 100 entries
before upload or job creation.

The admitted bytes are uploaded through `api.uploadResumableBytes` with
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

`Client.countGenerateTokens`, `Client.countEditTokens`, and CLI Batch-file
preparation send the current generated request shape to Gemini's `countTokens`
endpoint:

```text
https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:countTokens
```

The typed generation/edit core builds command-specific `generateContent` JSON
through the internal generation or edit builder, then uses the shared `api`
countTokens envelope helper to add the model field that Google requires inside
nested `generateContentRequest` payloads. CLI Batch preparation calls the
context-taking phase-one core, so request logging, timeout behavior,
countTokens envelopes, 2xx success classification, non-2xx body ownership, and
malformed-response handling are shared with public typed preparation:

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

Typed Batch preparation retains the exact generated request allocation through
countTokens classification. A successful phase-one result owns those bytes and
the total token count. Public explicit-key preparation wraps the same bytes in
the public JSONL record, enforces the complete serialized-record limit, and
then releases the phase-one allocation. CLI `--batch-file` mode passes the same
retained bytes into its locked append path, where automatic keys, duplicate-key
inspection, JSONL wrapping, separator insertion, file-size and entry-count
limits, append, and rollback stay in the CLI. Non-2xx bodies transfer into
`ApiFailure`, while malformed 2xx responses become Zig errors at the public
method boundary and exit code 3 in CLI Batch mode.

The live request-validity tests call these helpers directly.

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
`responseId` and the optional reported service-tier spelling is parsed for
shape compatibility but is not exposed to callers. The typed client validates
and maps that spelling to its public `ServiceTier`.

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

`cli.writeGenerationResult` asserts that at least one decoded image is present.
This assertion is paired with `api.decodeGeneratedFiles`, which rejects
responses that produce zero generated files, and the typed client transfers
those decoded images into `GenerationResult`.

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
- `client.generateWithContext` and `client.editWithContext` receive `gpa`
  through their request context for request JSON, HTTP client state, response
  buffering, decoded images, and result metadata.
- Typed Files context operations receive `gpa` through the same request
  context. `File` owns its canonical name, optional metadata strings, unknown
  state/source spellings, and optional `RemoteError`; `FileListPage` owns its
  File slice and continuation token.
- `files.uploadFile` receives already-read file bytes; CLI filesystem IO
  stays in `src/cli.zig`.
- `batch.uploadInput` receives already-read validated JSONL bytes; CLI
  filesystem IO stays in `src/cli.zig`.
- Typed Files operations return owned File metadata for upload, get, and list
  responses. A typed `FileListPage` also owns its optional next page token; the
  CLI transfers File ownership into its aggregate before deinitializing each
  page.
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
  buffers, one owned response ID, and an optional owned reported service-tier
  spelling. The typed client transfers the response ID and image buffers into
  `GenerationResult` without copying image bytes.
- `HttpResponse.deinit`, typed `FileListPage.deinit`, `File.deinit`,
  `FileState.deinit`, `FileSource.deinit`,
  `RemoteError.deinit`, `batch.ListPage.deinit`, `GeneratedFile.deinit`,
  `GeneratedFiles.deinit`, `GeneratedImage.deinit`, and
  `GenerationResult.deinit` release owned allocations.
- `PreparedBatchRequest.deinit` releases the internally retained exact
  generate-content JSON; `PreparedBatchEntry.deinit` releases the public key
  and complete JSONL record.

Partial decode and public-result conversion failures clean up already-decoded
file buffers and metadata with `errdefer`.

## Tests

Current tests cover:

- Accepted and rejected CLI argument forms.
- The exact generated JSON request for `nbimg gen`.
- Request-level control parsing and JSON serialization for `gen` and `edit`.
- Grounding tool serialization for web, image, and combined web/image modes.
- The exact generated JSON request for `countTokens`.
- Decoding `countTokens` responses.
- Typed generation/edit Batch preparation, retained request-byte reuse,
  explicit-key ownership, full-record limits, all 2xx countTokens statuses,
  complete API failures, and malformed successful responses.
- Structural Batch input summaries, LF/CRLF records, admission limits, blank
  records, and acceptance without JSON parsing.
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
- Typed Files validation, image and opaque MIME metadata, numeric size bounds,
  pagination, download URI, known and unknown state/source values, remote
  errors, all 2xx delete statuses, malformed successes, API failures, and
  partial-allocation cleanup.
- Files CLI outcome-to-exit mapping, pagination ownership transfer and
  aggregation, metadata JSON output shape, decimal size strings, known and
  unknown state/source rendering, unspecified and typed-only metadata
  omission, and string escaping.
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

The generation request-shape fixture uses the lowest supported image size,
`512`, while exercising the full generation option shape through countTokens.

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
orchestrates both Files API upload/delete and typed edit `countTokens`
validation. It uploads `sample_images/good_night.jpeg` with the fixed display name
`nbimg live edit request validity`, uses the returned `files/...` name as the
typed `EditRequest` base image with MIME `jpeg`, calls
`Client.countEditTokens`, and then deletes the uploaded file. The live edit
request uses
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
the typed context-taking get operation. The upload/list and get targets
best-effort delete their temporary upload. The live delete target deletes an
uploaded file, accepts its arbitrary successful body, checks that typed get
returns 403 afterward, checks a second delete returns 403, and probes a fixed
missing test name before asserting deleting that missing name also returns
403. Request logging confirms the upload-start body uses `displayName` and
file-resource endpoints use `/v1beta/files/{id}`; response logging shows the
actual File fields and delete response bodies returned by Gemini for the
current API behavior. Live tests construct logging-enabled
`api.RequestContext` values, require a non-empty `GEMINI_API_KEY`, perform
network IO, may leave an uploaded file in the Gemini Files API until Google
expires it if cleanup fails, intentionally retain Batch input uploads, and can
fail due to quota or remote API errors. The Batch list target is read-only and
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
