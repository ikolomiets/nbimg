# Public API Analysis

## Scope and classification

This analysis covers every declaration and public container method allowlisted
by `src/public_api_test.zig`. It evaluates the API against the repository's
currently documented product: an executable CLI. The README does not document
`nbimg` as an embeddable Zig library, and `build.zig` creates the `nbimg`
module only to link `src/main.zig`.

The most important distinction is:

- **Package contract**: declarations intentionally supported for users that
  import `nbimg`.
- **Internal module seam**: declarations that must be `pub` only because one
  source file calls another source file in Zig.

`src/public_api_test.zig` currently conflates these concepts. It imports every
source module directly and verifies its `pub` declarations, while
`src/root.zig` re-exports every module. Consequently, declarations needed only
as internal module seams also become reachable through the package root.

The tables use these recommendations:

- **Keep**: essential to the current package/executable boundary.
- **Library candidate**: reasonable in a future explicitly supported
  embeddable API, but not part of the documented contract today.
- **Hide**: implementation, wire, transport, parsing, formatting, or CLI
  orchestration detail that should not be package-accessible.

Declarations marked **Hide** may still need to remain `pub` inside their
source module until the module graph is changed. The recommendation is about
package exposure, not blindly changing every `pub` to `const` or `fn`.

## Executive findings

Under the current CLI-only product contract, the only essential root path is
`nbimg.cli.run`, used by `src/main.zig`. Even that is executable assembly
rather than a documented third-party library API.

The broadest accidental exposure is `nbimg.api.*`. It publishes:

- raw HTTP response ownership;
- arbitrary authenticated URL request functions;
- resumable upload mechanics;
- Gemini wire-shape structs and serializers;
- assertion-based invariant checks;
- environment lookup and mutable global logging state;
- response decoders and CLI output-naming helpers.

The command modules contain plausible future library operations, but their
current signatures expose transport bodies and require consumers to reproduce
CLI workflows by calling builders, transports, status checks, and decoders in
the right order. They should not be declared stable until a deliberate
library contract is designed.

## Root and CLI

| Item | Current role | Recommendation |
| --- | --- | --- |
| `root.api` | Re-exports shared wire, transport, decoding, and option internals. | **Hide.** This is the main source of accidental package exposure. |
| `root.batch` | Re-exports the full Batch implementation module. | **Hide today; library candidate as a narrower façade.** |
| `root.cli` | Gives `src/main.zig` access to the CLI entry point. | **Keep.** It is the only root export required by the current executable wiring. |
| `root.edit` | Re-exports the full edit implementation module. | **Hide today; library candidate as a narrower façade.** |
| `root.files` | Re-exports the full Files implementation module. | **Hide today; library candidate as a narrower façade.** |
| `root.gen` | Re-exports the full generation implementation module. | **Hide today; library candidate as a narrower façade.** |
| `cli.run` | Top-level command execution called by `src/main.zig`. | **Keep for executable assembly.** Do not promise it as a stable embedding API without documenting its process-exit, IO, environment, and diagnostic behavior. |

Recommended immediate root contract:

```zig
pub const cli = @import("cli.zig");
```

If a library API is desired later, expose a separate façade rather than
re-exporting implementation modules wholesale.

## `api` module

### Models and option containers

| Item | Assessment | Recommendation |
| --- | --- | --- |
| `Model` | Fixed endpoint-selection detail with only `.nano2`; consumers cannot select a model through the CLI. | **Hide.** It is a transport implementation choice. |
| `GenerateFileData`, `GeneratePart`, `GenerateContent` | Gemini request wire-building shapes used by `gen`, `edit`, and Batch tests. | **Hide.** They expose serialization structure rather than a product-level request. |
| `ServiceTier` | User-visible request option. | **Library candidate.** Keep the value type in a future request API, but hide `jsonStringify`; consider moving CLI spelling parsing out of the domain type. |
| `RequestOptions` | Coherent request-level options used by generation and edit. | **Library candidate.** Its public fields are useful, while `hasAny` is an internal serialization convenience. |
| `ImageAspectRatio`, `ImageSize` | User-visible generation controls. | **Library candidates.** `fromName` is CLI parsing policy and need not be public in a library. |
| `ImageOutputOptions` | Coherent public request options. | **Library candidate.** `hasAny` is an internal serialization helper. |
| `GroundingOptions` | Coherent public request options. | **Library candidate.** `fromName` and `hasAny` are CLI/serialization conveniences. |
| `ThinkingLevel`, `ThinkingOptions` | User-visible request controls. | **Library candidates.** Hide `ThinkingLevel.jsonStringify`; `fromName` and `hasAny` need not be package API. |
| `GenerationOptions` | User-visible controls, but its public fixed array and count expose representation and permit invalid states. | **Library candidate after redesign.** Prefer an API that cannot create inconsistent `stop_sequences`/`stop_sequence_count` values. |
| `GenerateContentRequestOptions` | Aggregate used by the shared wire serializer, not directly by a command-level operation. | **Hide.** A future public request type should belong to the high-level generation API. |
| `HarmBlockThreshold`, `SafetyOptions` | User-visible safety controls. | **Library candidates.** Hide `jsonStringify`; `SafetyOptions.fromName` is CLI preset parsing rather than core API. |
| `CountTokensResult` | Useful domain result currently produced only by a separate decoder. | **Library candidate.** A high-level count-tokens operation should return it directly. |
| `ImageMime` | Shared input-image type used by Files and edit requests. | **Library candidate.** `apiName` is wire detail; `fromPath` may belong in a file-oriented convenience layer; `fromName` is parser policy. |
| `OutputMime` | Generated-output representation used by decoded files and naming. | **Library candidate only as part of a generated-file result.** `extension` is a reasonable result convenience. |
| `GeneratedFile`, `GeneratedFiles` | Coherent owned generation result types with required `deinit` methods. | **Library candidates.** High-level generate/edit calls should return these or a richer result instead of raw `HttpResponse`. |
| `HttpResponse` | Raw transport status and body returned by nearly every command operation. | **Hide.** It couples consumers to HTTP and forces them to know response schemas and success policy. |
| `ResumableUpload` | Generic Files upload protocol input. | **Hide.** It is a transport mechanism. |
| `TrafficLogOptions` | CLI diagnostic configuration. | **Hide from a library contract** or pass it through an explicit client/context. |

### Container methods

| Item(s) | Recommendation |
| --- | --- |
| `ServiceTier.fromName`, `ImageAspectRatio.fromName`, `ImageSize.fromName`, `GroundingOptions.fromName`, `ThinkingLevel.fromName`, `SafetyOptions.fromName`, `ImageMime.fromName` | **Hide or move to CLI parsing.** These encode command-line spellings. |
| `ServiceTier.jsonStringify`, `ThinkingLevel.jsonStringify`, `HarmBlockThreshold.jsonStringify` | **Hide.** They exist for Gemini wire serialization. |
| `RequestOptions.hasAny`, `ImageOutputOptions.hasAny`, `GroundingOptions.hasAny`, `ThinkingOptions.hasAny`, `GenerationOptions.hasAny` | **Hide.** They are serializer/tests conveniences, not essential consumer operations. |
| `GenerationOptions.appendStopSequence`, `GenerationOptions.stopSequenceSlice` | **Library candidates only if the current fixed-capacity representation remains public.** A redesigned invariant-preserving options type would make these part of its deliberate construction API. |
| `ImageMime.fromPath` | **Library candidate** for path-based upload convenience. |
| `ImageMime.apiName` | **Hide.** It exposes Gemini wire spelling. |
| `OutputMime.extension` | **Library candidate** because it is useful when persisting generated bytes. |
| `GeneratedFile.deinit`, `GeneratedFiles.deinit`, `HttpResponse.deinit` | Required whenever their owning types are exposed. Keep the first two with a future result API; hide `HttpResponse` and its method. |

### Functions

| Item | Current role | Recommendation |
| --- | --- | --- |
| `apiKeyFromMap` | Reads `GEMINI_API_KEY` for CLI and live tests. | **Hide.** Environment policy belongs to the CLI; a library should accept a key or client configuration explicitly. |
| `assertValidGenerationOptions`, `assertValidRequestOptions` | Assert programmer invariants before serialization. | **Hide.** Public assertion-based validation is unsafe as an input-validation contract; a public API should prevent invalid states or return typed errors. |
| `buildGenerateContentRequestJson` | Serializes shared Gemini request wire shapes. | **Hide.** |
| `buildCountTokensRequestFromGenerateContentJson` | Performs textual JSON envelope composition. | **Hide.** It is especially brittle as a public contract because it assumes an object-shaped serialized input. |
| `decodeCountTokensResponse` | Parses a wire response into `CountTokensResult`. | **Hide behind a high-level operation.** |
| `decodeResponseServiceTier` | Extracts optional response metadata for a CLI warning. | **Hide.** |
| `decodeGeneratedFiles` | Parses and base64-decodes generated response parts. | **Hide behind high-level generate/edit operations.** |
| `decodeUploadedFileName` | Extracts a Files resource name after upload. | **Hide behind Files/Batch operations.** |
| `generatedFileName` | Applies the CLI's output filename policy. | **Hide or move to CLI.** Filename policy is not Gemini API behavior. |
| `postGenerateContentJson`, `postCountTokensJson` | Endpoint-specific raw JSON transports. | **Hide.** |
| `postJson`, `getJson`, `getBytesBounded`, `postJsonWithoutBody`, `deleteJson` | Generic authenticated requests to caller-provided URLs. | **Hide.** Besides being implementation detail, these unnecessarily expand the package into a generic HTTP client using the Gemini API key. |
| `uploadResumableBytes` | Implements generic resumable upload transport. | **Hide.** |
| `isCanonicalFileName`, `isCanonicalCachedContentName`, `isValidDisplayName` | Shared validation rules used across command modules and CLI parsing. | **Internal seam today; library candidates** if resource-name/value validation is deliberately supported. |

### Constants and mutable state

| Item(s) | Recommendation |
| --- | --- |
| `api_key_env_name` | **Hide or move to CLI.** Environment lookup is CLI policy. |
| `http_request_timeout_seconds` | **Hide.** It is an implementation default currently used for diagnostics. A future client should accept an explicit timeout option. |
| `canonical_file_name_prefix` | **Hide.** Other modules use it to slice resource IDs, but consumers should use validators or typed names rather than depend on prefix layout. |
| `max_generate_request_parts_total`, `max_generate_request_field_bytes` | **Hide.** These are request/wire implementation bounds. |
| `max_generate_text_part_bytes`, `max_stop_sequences`, `max_output_tokens` | **Library candidates** because callers may need admission limits, but only after they are documented as stable product policy rather than current implementation constants. |
| `ApiKeyError` | **Hide with `apiKeyFromMap`.** |
| `traffic_log_options` | **Hide and redesign.** Public mutable global state is the clearest accidental exposure; it prevents per-client isolation and hides an effect from function signatures. |

## `gen` module

| Item | Assessment | Recommendation |
| --- | --- | --- |
| `generateContent` | High-level command-domain operation, but returns raw `api.HttpResponse`. | **Library candidate after redesign.** Return a decoded owned result and structured response metadata; accept explicit client/configuration rather than relying on global logging. |
| `buildGenerateRequest` | Exposes exact Gemini request JSON and duplicates most parameters of `generateContent`. It is used by CLI Batch preparation. | **Hide as an internal seam.** A future Batch API should accept the same typed generation request instead of requiring consumers to build raw JSON. |

`gen` has the right domain boundary, but the current API is transport-oriented
rather than consumer-oriented.

## `edit` module

### Types and methods

| Item | Assessment | Recommendation |
| --- | --- | --- |
| `ReferenceRole` | Core edit-domain concept. | **Library candidate.** `fromName` is CLI parsing policy and should be hidden or separated. |
| `UploadedImage`, `Reference`, `EditRequest` | Coherent borrowed edit request model. | **Library candidates.** They are the strongest existing basis for a future supported API. Consider a typed canonical file name and invariant-preserving request construction. |

### Functions and limits

| Item | Recommendation |
| --- | --- |
| `generateContent` | **Library candidate after redesign.** It should return decoded generated output rather than `HttpResponse`. |
| `countGenerateContentRequestTokens` | **Library candidate after redesign.** It should return `CountTokensResult` directly. |
| `buildGenerateRequest` | **Hide.** This is Gemini prompt/wire construction and exists primarily for immediate submission and Batch JSONL preparation. |
| `isValidLabel` | **Internal seam today; library candidate** if labels remain a user-constructible part of `Reference`. Prefer construction that returns a validation error rather than requiring callers to discover and invoke a separate predicate. |
| `max_references`, `max_character_references`, `max_object_references` | **Library candidates** because they constrain valid public edit requests. They should be documented as product limits if retained. |

## `files` module

### Types and methods

| Item | Assessment | Recommendation |
| --- | --- | --- |
| `FileUpload` | Coherent borrowed upload request. | **Library candidate.** Enforce the documented size/display-name constraints through a high-level operation. |
| `File` | Coherent owned Files resource with `deinit`. | **Library candidate.** The many optional strings mirror the remote schema and therefore carry compatibility cost, but they are useful result data. |
| `FileListPage` | Coherent owned pagination result with `deinit`. | **Library candidate.** A higher-level iterator could avoid exposing pagination mechanics. |

### Functions and limit

| Item | Recommendation |
| --- | --- |
| `uploadFile`, `listFilesPage`, `getFile`, `deleteFile` | **Library candidates after redesign.** They are domain operations, but should return decoded `File`/`FileListPage`/success results rather than raw `HttpResponse`. |
| `decodeUploadedFile`, `decodeFile`, `decodeFileListPage` | **Hide behind the corresponding operations.** Public decoders make the remote JSON schema part of the package contract and split one logical operation into transport plus decode steps. |
| `max_upload_bytes` | **Library candidate** because callers may need to reject oversized local inputs before allocation or IO. |

## `batch` module

### Types and methods

| Item | Assessment | Recommendation |
| --- | --- | --- |
| `SubmitRequest` | Coherent borrowed submission input, although it assumes the caller already uploaded JSONL. | **Library candidate** as part of either a low-level Batch client or a redesigned end-to-end submit operation. |
| `DownloadInfo` | Intermediate decoded status data used before downloading output. | **Hide in a high-level workflow; library candidate only for an explicitly low-level Batch API.** |
| `OutputRecord` | Useful decoded output-domain type with ownership. | **Library candidate.** It should ideally represent error records explicitly instead of using `response_json == null`. |
| `OutputLineIterator` | Bounded JSONL parsing mechanism with public progress fields. | **Hide.** It is an implementation iterator and exposes line-counting representation. |
| `ListPage` | Owned page of compact operation JSON strings. | **Library candidate after redesign.** Raw JSON operation strings are not a strong stable result model. |
| `DownloadInfo.deinit`, `OutputRecord.deinit`, `ListPage.deinit` | Required only if their owning types remain public. | Keep with any retained owned type. |
| `OutputLineIterator.next` | Parsing implementation. | **Hide with the iterator.** |

### Functions

| Item | Recommendation |
| --- | --- |
| `uploadInput`, `submit`, `status`, `downloadOutput`, `cancel`, `listPage` | **Library candidates after redesign.** They model real domain operations but expose raw `HttpResponse` and force consumers to orchestrate upload/create/status/download/decode steps manually. |
| `validateInputJsonl` | **Library candidate.** Local admission validation is useful before remote side effects, though returning structured validation information would be stronger than an inferred error set. |
| `buildEntryJson` | **Hide as a serialization helper** or replace it with a documented typed Batch-file writer API. |
| `decodeDownloadInfo`, `decodeBatchName`, `decodeOutputRecord`, `decodeListPage` | **Hide behind high-level operations.** These expose response schema and split transport from decoding. `decodeOutputRecord` could remain in a deliberate JSONL-processing API. |
| `validateOutputJsonl` | **Hide** unless raw downloaded JSONL is intentionally supported as a public data format. |
| `isCanonicalBatchName` | **Internal seam today; library candidate** if untyped resource-name strings remain public inputs. |
| `safeOutputKey` | **Hide or move to CLI.** It implements local filesystem naming policy, not Batch API behavior. |
| `listJson`, `prettyJson` | **Hide or move to CLI.** They are presentation helpers. `prettyJson` is generic and unrelated to the Batch domain. |

### Limits

| Item | Recommendation |
| --- | --- |
| `max_entries`, `max_entry_bytes`, `max_input_bytes`, `max_output_bytes` | **Library candidates** for a supported Batch-file API because callers need local admission and memory bounds. Otherwise keep them internal implementation policy. |

## Recommended target design

### 1. Separate package API tests from internal seam tests

Change the package-level test to import `root.zig` and allowlist only deliberate
consumer paths. Keep separate per-module allowlists if they remain useful for
detecting accidental cross-file `pub` declarations, but label them as internal
module-boundary tests rather than public package API tests.

This avoids the current false equivalence:

```text
needed by another source file == supported for external consumers
```

### 2. Narrow the root immediately

For the current CLI-only contract, export only `cli`. The command and `api`
modules can continue importing each other by file path without being reachable
as `nbimg.api`, `nbimg.batch`, and so on.

If direct library importing is not an intended product feature, also consider
making `main.zig` the executable root and importing `cli.zig` directly. That
would remove the need for a package-facing root API entirely.

### 3. Design a façade before promising a library API

A future library surface should expose typed operations such as:

- generate or edit and receive decoded generated files;
- count tokens and receive `CountTokensResult`;
- upload/get/list/delete files and receive typed results;
- submit/status/cancel/download batches through cohesive workflows.

It should not require consumers to:

- build Gemini JSON;
- choose endpoint URLs;
- call generic authenticated HTTP helpers;
- decode response bodies separately;
- mutate global logging options;
- use assertions as runtime input validation.

### 4. Remove public mutable global configuration

Replace `api.traffic_log_options` with explicit configuration passed through a
client or operation context. This follows the repository rule to pass IO,
options, clocks, environment data, and other effects explicitly.

### 5. Keep wire and presentation concerns private

The following groups should stay behind the façade:

- `GeneratePart`/`GenerateContent` wire assembly;
- JSON builders and response decoders;
- generic HTTP and resumable upload helpers;
- Gemini serializers such as `jsonStringify`;
- CLI parsers such as `fromName`;
- output filename, safe-key, and pretty-print formatting.

## Suggested priority

1. Narrow `src/root.zig` to the actual current package boundary.
2. Split or rename the allowlist tests so package API and internal module seams
   are checked independently.
3. Hide `traffic_log_options` behind explicit configuration.
4. Decide whether an embeddable Zig library is a supported product.
5. Only if it is supported, introduce a typed façade and then migrate the
   **Library candidate** items into that façade.

No source visibility should be changed mechanically before step 1: several
currently public declarations are legitimately required across source-file
boundaries even though they should not be accessible from the package root.
