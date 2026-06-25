# Public API Refactoring Plan

## Purpose

This document defines and records the incremental public-API refactoring
sequence based on the historical `public_api_analysis.md` snapshot. Completed
items describe implemented work; remaining items describe planned work and do
not by themselves authorize external side effects.

The current code uses `pub` both for declarations shared between source files
and for declarations reachable by package consumers. The proposed sequence
separates those concerns, preserves a working CLI after every increment, and
eventually establishes a deliberate client-based Zig library API.

Every numbered item is intended to be independently implementable,
reviewable, testable, and mergeable over an extended period. Later items may
depend on completed earlier items, but no item should leave the repository in
an intermediate state that requires the next item to build or pass tests.

## Proposed Incremental Refactorings

1. **Separate package-contract tests from internal module-seam tests**

   **Status:** Completed.

   **Result:** Distinguish declarations supported for package consumers from
   declarations that are `pub` only so another source file can use them.

   **Completed changes:**

   - Change `src/public_api_test.zig` to inspect the declarations reachable
     through `src/root.zig`.
   - Move the existing per-source-module allowlists into a separately named
     internal module API test.
   - Register both test roots in `build.zig`.
   - Initially preserve all existing allowlists and visibility. This
     refactoring changes classification and enforcement, not the API itself.
   - Update `docs/IMPLEMENTATION_DESIGN.md` to define the two kinds of tests.

   **Compatibility:** No source or CLI behavior changes.

   **Validation completed:** `zig fmt --check build.zig src`,
   `zig build test`, and `zig build`.

   **Complete when:** Package exports and internal cross-file declarations are
   guarded by separate exact allowlists with unambiguous names.

2. **Decouple executable assembly from the package contract**

   **Depends on:** Item 1.

   **Status:** Completed.

   **Result:** The executable no longer requires `cli` to be exported through
   the package root.

   **Completed changes:**

   - Change `src/main.zig` to import the CLI implementation directly.
   - Adjust the build graph so `main.zig` receives `build_options` and any
     required internal imports without importing the package façade.
   - Remove `cli` from `src/root.zig` and from the package-contract allowlist.
   - Keep `cli.run` public because executable assembly requires cross-file
     access, and classify it as an internal seam.

   **Compatibility:** The undocumented `nbimg.cli` path is removed. CLI
   commands, output, diagnostics, and exit codes remain unchanged.

   **Validation completed:** `zig fmt --check build.zig src`, focused package
   API, internal module API, and CLI tests, `zig build test`, `zig build`, and
   `git diff --check`.

   **Complete when:** The executable builds and runs without any CLI
   implementation declaration being reachable through the package root.

3. **Replace mutable traffic logging state with explicit request context**

   **Status:** Completed.

   **Result:** Network behavior no longer depends on
   `api.traffic_log_options`.

   **Completed changes:**

   - Introduce an internal request context containing allocator, `std.Io`,
     borrowed API key, positive `std.Io.Duration` timeout, and internal
     traffic-log options.
   - Pass `*const RequestContext` through command-domain and transport
     operations that perform network IO. Keep pure builders and decoders
     independent of the context.
   - Remove the mutable `traffic_log_options` global and make every transport
     timeout use the context value.
   - Preserve current CLI defaults: response logging remains enabled,
     `--print-request` controls request logging, and the timeout remains 180
     seconds.
   - Keep traffic logging internal and CLI-oriented. Do not make stderr logging
     part of the public client contract without a separately designed logging
     sink or callback.

   **Compatibility:** Internal signatures change. CLI behavior and wire
   requests do not.

   **Validation completed:** Added tests proving independent contexts select
   different logging and timeout options without shared state. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live tests were unnecessary because request fields and
   wire transport behavior did not change.

   **Complete when:** No request behavior reads or mutates process-global
   configuration, and every network timeout comes from an explicit context.

4. **Introduce the public client with typed generation token counting**

   **Depends on:** Item 3.

   **Status:** Completed.

   **Result:** Deliver the first complete supported library workflow through
   non-generating token counting, rather than exporting an unused client
   foundation.

   **Completed changes:**

   - Register the supported library with
     `b.addModule("nbimg", .{ .root_source_file = b.path("src/root.zig"), ... })`.
     Supply its required `build_options` import while legacy root exports still
     reach implementation modules that import it.
   - Export `Client`, `ClientOptions`, `Outcome(T)`, `ApiFailure`,
     `GenerationRequest`, `GenerationValidationError`, `CountTokensResult`,
     and the deliberate generation option and enum types.
   - Define `ClientOptions` with borrowed `api_key: []const u8` and
     `timeout: std.Io.Duration = .fromSeconds(180)`. Define
     `Client.init(allocator, io, options) !Client`; `Client` stores those
     values without allocating or copying the API key. Public traffic logging
     is out of scope.
   - Have public client methods create a quiet internal request context without
     exposing that context through `src/root.zig`.
   - Have `Client.init` return `error.EmptyApiKey` for an empty key and
     `error.InvalidTimeout` for a non-positive timeout. Document that the API
     key remains caller-owned for the client lifetime.
   - Define `Outcome(T)` as `.success: T` or `.api_failure: ApiFailure`.
     `ApiFailure` owns `status: std.http.Status` and `body: []u8` and provides
     `deinit(allocator)`. Operation success types that allocate provide their
     own `deinit(allocator)`; `Outcome(T)` has no generic deinitializer.
   - Apply the existing transport response limit to every response body. If a
     success or failure body exceeds the bound, return `error.ResponseTooLong`;
     never return a partial body. Preserve the complete bounded non-success
     body in `ApiFailure`.
   - Use Zig errors for allocation, IO, timeout, input validation, oversized
     responses, and successful-response decoding failures. Reserve
     `ApiFailure` for completed non-success HTTP responses.
   - Define `GenerationRequest` as a borrowed prompt plus public output,
     grounding, thinking, safety, generation, and request options. Represent
     stop sequences as `[]const []const u8`, and separate public domain enums
     from private wire serialization enums.
   - Export `GenerationValidationError` containing `EmptyPrompt`,
     `PromptTooLong`, `InvalidMaxOutputTokens`, `InvalidTemperature`,
     `InvalidTopP`, `InvalidPresencePenalty`, `InvalidFrequencyPenalty`,
     `LogprobsRequireResponseLogprobs`, `InvalidLogprobs`,
     `TooManyStopSequences`, `EmptyStopSequence`, `DuplicateStopSequence`,
     `EmptySystemInstruction`, `SystemInstructionTooLong`, and
     `InvalidCachedContentName`, plus `RequestTooLong` for the existing 5 MiB
     aggregate variable-field bound. Token counting returns these errors for
     invalid caller input before network IO.
   - Define `CountTokensResult` with total tokens and optional cached-content
     token count.
   - Add `Client.countGenerateTokens`, returning
     `Outcome(CountTokensResult)`.
   - Validate all public inputs with returned errors rather than assertions.
     Keep CLI spelling parsers in `src/cli.zig`.
   - Keep the current immediate generation and Batch preparation paths
     unchanged. This increment adds the public operation without migrating CLI
     orchestration.
   - Add exact package-root and public-container method allowlists. Add a
     compile-only consumer root that imports `nbimg` through the build graph,
     never by importing `src/root.zig` directly. Verify the façade does not
     expose `RequestContext`, Gemini wire types, raw transport types, or
     implementation modules beyond the explicitly retained legacy root paths.
   - Add README and implementation-design examples for client initialization,
     token counting, outcome handling, and API-failure deinitialization.

   **Compatibility:** This adds the first supported client API. Existing
   `api`, `gen`, `edit`, `files`, and `batch` package paths remain temporarily
   available.

   **Validation completed:** Covered initialization without allocation or
   API-key copying, independent configuration, generation-option conversion,
   exact validation errors, token-count success and API-failure ownership,
   oversized success and failure bodies, malformed successful responses, exact
   allowlists, and external-consumer compilation. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live validation was unnecessary because the public
   request types convert into the unchanged existing Gemini wire shape.

   **Complete when:** A dependency consumer can import `nbimg` and count
   generation tokens without raw JSON, `HttpResponse`, or implementation
   modules.

5. **Add typed image generation**

   **Depends on:** Item 4.

   **Status:** Completed.

   **Result:** Consumers can generate images through the public client and
   receive owned domain results instead of raw HTTP responses.

   **Completed changes:**

   - Export `GenerationResult`, `GeneratedImage`, and the public output MIME
     enum. `GeneratedImage` contains zero-based candidate position, zero-based
     part position, output MIME, and owned bytes. `GenerationResult` contains
     an owned response ID, owned image slice, and optional reported service
     tier.
   - Provide allocator-based `deinit` methods on both owning types.
   - Add `Client.generate`, returning `Outcome(GenerationResult)` and reusing
     the request validation and domain-to-wire conversion introduced by Item
     4.
   - Introduce one internal typed generation entry point that accepts an
     explicit request context. `Client.generate` uses it with a quiet context;
     Item 6 will reuse the same entry point with the CLI's logging-enabled
     context. Do not add a public-only operation path that Item 6 must
     immediately replace.
   - Decode successful responses internally, including the optional reported
     service tier. Return successful-response JSON, base64, missing-field,
     unsupported-part, and unsupported-MIME failures as Zig errors.
   - Treat an unrecognized reported service-tier spelling as
     `error.UnsupportedServiceTier`; do not collapse it into the same `null`
     value used when `usageMetadata.serviceTier` is absent.
   - Define generated image indexes as zero-based candidate and part positions
     in the response arrays. Keep those semantics aligned with existing CLI
     output naming; do not substitute the optional Gemini `candidate.index`
     metadata field.
   - Keep shared Gemini response-shape parsing and image decoding in
     `src/api.zig`. Convert the internal decoded representation to the public
     `GenerationResult` in `src/client.zig`, so edit and Batch operations can
     reuse one wire decoder without exposing its types.
   - Preserve complete bounded non-success response bodies in `ApiFailure`.
     Keep response classification and decoding available through internal pure
     helpers so success, failure, malformed, and ownership paths are testable
     without live network calls.
   - Keep immediate CLI generation and Batch preparation on their existing
     internal paths. This increment adds the supported generation workflow
     without changing CLI diagnostics or output handling.
   - Extend exact package and public-container allowlists, the compile-only
     external consumer, README examples, and implementation ownership
     documentation for generation and deinitialization.

   **Compatibility:** Additive. Existing package module paths and CLI behavior
   remain unchanged.

   **Validation completed:** Covered generated-image ownership and cleanup
   after partial decode and conversion failures, response IDs, candidate and
   part positions, all supported and unsupported MIME paths, thought/text part
   handling, absent, recognized, and unrecognized reported service tiers, API
   failures, malformed successful responses, exact allowlists, and
   external-consumer compilation. Ran `zig fmt --check build.zig src`,
   `zig build test`, `zig build`, and `git diff --check`. Live validation was
   unnecessary because request fields and wire shape did not change.

   **Complete when:** A dependency consumer can generate images and count
   generation tokens through `Client` without raw JSON, `HttpResponse`, or
   implementation modules.

6. **Migrate immediate CLI generation to the typed core**

   **Depends on:** Item 5.

   **Status:** Completed.

   **Result:** The immediate `nbimg gen` path and public client share one typed
   operation core, allowing the legacy package-level `gen` export to be
   removed.

   **Completed changes:**

   - Migrate only immediate CLI generation to the context-taking typed
     operation core introduced by Item 5.
     Preserve output files, exclusive writes, diagnostics, traffic logging,
     timeout reporting, the priority-tier downgrade warning, and exit codes.
   - Add a narrow CLI adapter that converts `GenCommand` fields into the public
     `GenerationRequest` at dispatch. Keep CLI spelling parsing and command
     storage unchanged in this increment.
   - Preserve the CLI's exact response policy while sharing transport and
     decoding mechanics: immediate CLI generation continues to require HTTP
     200, and an absent or unrecognized reported service tier does not by itself
     fail an otherwise decodable CLI response. Malformed response metadata
     remains a response-decoding failure. The public
     `Client.generate` contract continues to accept successful 2xx responses
     and reject an unrecognized reported tier with
     `error.UnsupportedServiceTier`. Implement this through an internal
     policy-bearing response conversion/classification seam rather than
     weakening either contract.
   - Keep Batch-file generation on the existing raw request-building path
     until Item 12.
   - Move generated-output filename formatting into `src/cli.zig`; filename
     policy remains a CLI concern rather than a public result method.
   - Remove `gen` from `src/root.zig` and the package allowlist after immediate
     generation no longer relies on the legacy package path. Keep the
     cross-file declarations needed by CLI Batch preparation in the internal
     module allowlist.
   - Update README and implementation-design architecture text to distinguish
     the supported typed generation API from the temporary internal Batch
     preparation seam.

   **Compatibility:** Removes the undocumented `nbimg.gen` package path. CLI
   commands, output naming, diagnostics, traffic logging, and exit codes remain
   unchanged. Existing `api`, `edit`, `files`, and `batch` paths remain
   temporarily available.

   **Validation completed:** Covered HTTP 200, other 2xx, and non-2xx response
   policy; absent, recognized, unknown, and malformed reported service tiers;
   complete CLI option adaptation with borrowed stop sequences; priority
   downgrade detection; PNG, JPEG, and WebP output names; exclusive-write
   failures; malformed-response classification; exact package/internal
   allowlists; and external-consumer compilation. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live validation was unnecessary because request fields
   and transport behavior did not change. A subsequent explicit live
   generation request-shape check passed through Gemini countTokens using the
   lowest supported image size, `512`.

   **Complete when:** Immediate CLI generation and `Client.generate` share the
   typed operation core, Batch preparation still works, and `nbimg.gen` is no
   longer package-accessible.

7. **Add typed edit operations**

   **Depends on:** Items 5 and 6.

   **Status:** Completed.

   **Result:** Consumers can construct and submit edit requests through domain
   types rather than implementation modules, without changing CLI execution.

   **Completed changes:**

   - Export deliberate `EditRequest`, `UploadedImage`, `Reference`, and
     `ReferenceRole` types using the public generation option types.
   - Export a deliberate public `InputImageMime` enum with `jpeg`, `png`, and
     `webp`. Use it for edit inputs and the later Files upload API. Keep MIME
     spelling and path-extension parsing internal or CLI-owned. Do not reuse
     `OutputMime`; input and generated-output MIME roles are distinct.
   - Export a named `EditValidationError` covering empty or oversized prompt,
     invalid base/reference file names, invalid, reserved `BASE_IMAGE`, or
     duplicate labels, total and role-specific reference limits, preserve and
     do-not count limits, empty or oversized preserve/do-not constraints,
     generated edit-task text overflow, generated File URI overflow,
     generation/request option failures, and the aggregate request-field
     bound. Validate the complete public request before allocation or network
     IO.
   - Export the stable edit admission limits as `max_edit_references`,
     `max_edit_character_images`, `max_edit_object_images`, and
     `max_edit_reference_label_bytes`. Also export
     `max_edit_preserve_constraints` and `max_edit_do_not_constraints`; both
     are 16 in the current CLI contract.
   - Add `Client.edit` returning `Outcome(GenerationResult)` and
     `Client.countEditTokens` returning `Outcome(CountTokensResult)`. Reuse
     the public generation result and token-count types. Batch preparation
     remains deferred to Items 11 and 12.
   - Return errors for invalid prompts, file names, labels, reference counts,
     role-specific limits, constraints, and option combinations.
   - Keep CLI role-name parsing, Gemini prompt-manifest construction, File URI
     construction, and wire serialization private.
   - Generalize the policy-bearing generated-content response seam introduced
     by Item 6 so generation and edit share status classification, generated
     image decoding, service-tier handling, and stage-aware outcomes. Do not
     introduce parallel edit-only response-policy types.
   - Add an internal typed edit entry point accepting an explicit request
     context and the shared generated-content response policy. Public methods
     use a quiet context and the strict public policy; Item 8 will reuse the
     same operation with the CLI's logging-enabled context and HTTP-200 policy.
   - Keep immediate CLI edit execution and the legacy package export unchanged.
     Extend the exact package allowlist and external-consumer compile tests for
     the additive API.
   - Add README and implementation-design examples for edit requests,
     ownership, validation errors, and API failures.

   **Compatibility:** Additive. The undocumented `nbimg.edit` path remains
   temporarily available.

   **Validation completed:** Covered every input MIME, role, label, and
   constraint rule; reserved and duplicate labels; reference and separate
   preserve/do-not count limits; generated edit-task and File URI overflow;
   generation/request option error mapping; aggregate bound; request validation
   before allocation/network IO; ownership paths; both generated-content
   response policies; API failure; malformed success response; exact
   allowlists; and external-consumer compilation. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`,
   `git diff --check`, and the non-generating live edit request-validity target
   through `Client.countEditTokens`; the live fixture uploaded and deleted its
   temporary Files API image.

   **Complete when:** A dependency consumer can edit images and count edit
   tokens through `Client` without internal builders, validators, serializers,
   or transport responses.

8. **Migrate immediate CLI edit to the typed core**

   **Depends on:** Item 7.

   **Status:** Completed.

   **Result:** Immediate `nbimg edit` and the public client share one typed
   operation core, allowing the legacy package-level `edit` export to be
   removed.

   **Completed changes:**

   - Migrate immediate CLI edit execution to the context-taking typed edit
     operation introduced by Item 7.
   - Add a narrow CLI adapter that converts `EditCommand` and its nested
     internal reference values into the public edit request types at dispatch.
     Keep CLI spelling parsing and command storage unchanged in this increment.
   - Preserve output files, exclusive writes, diagnostics, traffic logging,
     timeout reporting, priority-tier downgrade warnings, and exit codes.
   - Apply the same explicit CLI response policy as Item 6: require HTTP 200,
     tolerate absent or unknown reported service-tier spellings when image
     decoding otherwise succeeds, and continue to reject malformed response
     metadata. Reuse the generalized generated-content response policy and
     stage-aware outcome from Item 7; do not duplicate generation response
     classification. Keep the stricter public typed response contract
     unchanged.
   - Keep Batch-file edit preparation on the existing raw request-building
     path until Item 12.
   - Remove `edit` from `src/root.zig` and the package allowlist. Remove the
     obsolete edit transport operations after migration; retain only internal
     request construction and validation declarations still required by the
     typed client and Batch preparation.
   - Update README and implementation-design architecture text to distinguish
     the supported typed edit API from the temporary internal Batch
     preparation seam.

   **Compatibility:** Removes the undocumented `nbimg.edit` package path. CLI
   behavior remains unchanged.

   **Validation completed:** Covered complete edit adaptation with borrowed
   prompts, image names, labels, stop sequences, and constraints; every image
   MIME and reference role; HTTP 200, other 2xx, and non-2xx response policy;
   malformed successes; absent, recognized, and unknown service tiers;
   priority downgrade detection; generated output naming and exclusive writes;
   timeout diagnostics; shared CLI outcome exit-code mapping; exact package
   and internal allowlists; and external-consumer compilation. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live validation was unnecessary because request fields
   and transport behavior did not change.

   **Complete when:** Immediate CLI edit and `Client.edit` share the typed
   operation core, Batch preparation still works, and `nbimg.edit` is no
   longer package-accessible.

## Response Contract for the Remaining Sequence

Items 6 and 8 preserved historical CLI response behavior while generation and
edit moved onto typed cores. That compatibility split is temporary. The
remaining CLI migrations define the replacement behavior rather than
preserving every legacy response-classification detail.

Items 9 through 17 use one response contract:

- Every completed HTTP 2xx response is eligible for success. Non-2xx responses
  become owned API failures.
- A successful response must decode according to the operation's typed result.
  Malformed successful responses remain successful-response decoding failures.
- An absent reported service tier is `null`; an unrecognized reported
  service-tier spelling is `error.UnsupportedServiceTier` for both library and
  CLI callers.
- Traffic logging remains a request-context concern. It does not affect status
  acceptance or response decoding.
- Internal typed operations use one generic stage-aware
  `OperationOutcome(T)`. Do not introduce runtime HTTP-status or decoding
  policy enums solely to distinguish CLI callers from public methods.
- Caller callbacks and local side effects can still fail through the outer Zig
  error channel. Do not misclassify visitor or filesystem errors as malformed
  successful API responses.
- Where the CLI needs a different presentation, duplicate-key decision, local
  filename rule, or filesystem failure strategy, keep that behavior in the CLI
  adapter or callback. Do not encode presentation or local side effects as
  transport response policies.

Item 9 removes the temporary `GeneratedContentResponsePolicy` and
`GeneratedContentOperationOutcome` declarations while introducing the generic
outcome used by later typed operations.

9. **Unify response semantics and add typed Files operations**

   **Depends on:** Items 7 and 8.

   **Status:** Completed.

   **Result:** Consumers can upload, get, list, and delete Gemini files through
   typed methods, and generation/edit no longer carry separate CLI and public
   response policies.

   **Completed changes:**

   - Reuse the public `InputImageMime` from Item 7. Export deliberate
     `FileUpload`, `File`, `FileListPage`, `FileState`, `FileSource`, and
     `RemoteError` types with explicit allocator-based ownership methods.
   - Keep `InputImageMime` limited to upload admission. Files list/get can
     return non-image resources, including Batch JSONL inputs, so returned
     `File.mime_type` is an optional owned opaque string rather than
     `InputImageMime`.
   - Define `FileState` as a tagged union with `unspecified`, `processing`,
     `active`, `failed`, and `unknown: []u8`. Define `FileSource` with
     `unspecified`, `uploaded`, `generated`, `registered`, and
     `unknown: []u8`. Known values allocate nothing; each unknown value owns
     the original wire spelling.
   - Define owned `RemoteError` with optional signed integer code, required
     message, and optional compact JSON details. Reuse this type for File
     processing errors and the later Batch API rather than creating
     Batch-specific remote-error ownership.
   - Define `File` with an owned canonical name; optional owned display name,
     MIME type, RFC 3339 timestamp strings, SHA-256 string, URI, and download
     URI; optional `u64` size; typed state and source; and optional
     `RemoteError`. Ignore specialized metadata such as video duration in this
     increment. A malformed numeric size or malformed populated remote error
     is a successful-response decoding failure.
   - Add `Client.uploadFile` and `Client.getFile` returning `Outcome(File)`,
     `Client.listFilesPage` returning `Outcome(FileListPage)`, and
     `Client.deleteFile` returning `Outcome(void)`.
   - Decode successful responses internally. Every public Files operation
     treats any completed 2xx response as success. A successful delete returns
     `Outcome(void)` and discards its bounded response body without requiring a
     particular JSON or empty-body shape.
   - Export `FileValidationError` containing `EmptyFileBytes`, `FileTooLarge`,
     `InvalidDisplayName`, `InvalidFileName`, and `EmptyPageToken`.
     `InputImageMime` is exhaustive, so there is no invalid-upload-MIME case.
     Validate before allocation or network IO and require decoded response
     resource names to be canonical. Keep path-extension parsing in the CLI.
   - Export the stable admission limit as `max_file_upload_bytes`; do not
     expose endpoint URLs, MIME spellings, or transport chunking limits.
   - Keep pagination explicit; a convenience iterator remains a separate
     proposal.
   - Introduce one generic stage-aware `OperationOutcome(T)` that distinguishes
     typed success, owned API failure, and successful-response decoding
     failure. Refactor generation and edit to use it, then remove
     `GeneratedContentResponsePolicy` and
     `GeneratedContentOperationOutcome`.
   - Apply the common response contract to generation and edit immediately:
     both public methods and CLI callers accept all 2xx statuses and reject an
     unknown reported service-tier spelling. Keep absent tiers as `null`.
   - Add context-taking internal typed Files operations so public methods use
     quiet contexts and Item 10 can reuse the same operations with CLI traffic
     logging. The context changes logging and timeout inputs only; it does not
     select response semantics.
   - Keep CLI Files commands and the legacy package export unchanged. Extend
     the exact package allowlist and external-consumer compile tests for the
     additive API.
   - Add README and implementation-design examples for upload, get, explicit
     pagination, delete, ownership, and API failures.

   **Compatibility:** The typed Files API is additive and the undocumented
   `nbimg.files` path remains temporarily available. Immediate `gen` and
   `edit` intentionally change to accept every 2xx response and to reject an
   unknown reported service tier instead of treating it as absent.

   **Validation completed:** Tested every input MIME; image and non-image returned MIME
   metadata; every known and unknown state/source case; absent and populated
   processing errors; download URI; valid, overflowing, negative, and malformed
   size values; canonical decoded names; successful and malformed response
   decoding; all 2xx delete statuses and arbitrary successful delete bodies;
   pagination; ownership and partial cleanup; exact validation errors before
   allocation/network IO; API failures; oversized failure bodies; unified
   generation/edit status and service-tier handling; removal of both temporary
   generated-content policy declarations; the generic stage-aware outcome;
   exact allowlists; and external-consumer compilation. Run affected Files live
   targets only when transport, request behavior, or decoded schema fields
   change. Ran `zig fmt --check build.zig src`, `zig build test`, `zig build`,
   `git diff --check`, and all three Files live targets. The live targets
   uploaded temporary images, validated typed upload/list/get/delete behavior,
   and deleted their temporary resources.

   **Complete when:** Files consumers require no public response decoders or
   resumable-upload mechanics, and generation/edit have no caller-selectable
   response policy.

10. **Migrate CLI Files commands to typed operations**

   **Depends on:** Item 9.

   **Status:** Completed.

   **Result:** CLI Files commands and the public client share typed operation
   cores, allowing the legacy package-level `files` export to be removed.

   **Completed changes:**

   - Migrated upload, get, list, and delete commands to the context-taking typed
     operations introduced by Item 9.
   - Called the context-taking operations directly from the CLI rather than
     constructing a public `Client`; this preserves the CLI logging-enabled
     request context without creating a second response path.
   - Added narrow CLI adapters from parsed command values and path-derived MIME
     into public Files request values. Local path parsing and complete file
     reads remain in the CLI.
   - Preserved pagination, printed JSON shape, diagnostics, traffic logging,
     timeout reporting, and exit codes. The migration added no upload-progress
     UI.
   - Applied the common response contract: every Files CLI command accepts all
     completed 2xx responses, matching the public methods, without a
     CLI-specific HTTP status policy.
   - Kept local path-extension MIME inference and presentation formatting in
     the CLI. The existing CLI metadata field set and omission rules remain
     where the typed model retains the distinction; newly supported public
     fields such as download URI and processing error do not change CLI JSON
     output in this migration.
   - Added explicit typed-to-CLI presentation adapters that format `size_bytes`
     as the existing decimal JSON string, render known state/source tags with
     their documented uppercase spellings, preserve unknown spellings, and
     omit `.unspecified` because Item 9 intentionally normalizes absent and
     explicit `*_UNSPECIFIED` values. Fields that the legacy CLI did not print
     remain omitted without reintroducing owned wire strings into the typed
     File model.
   - Deleted the legacy Files `FileUpload`, `File`, and `FileListPage` models and
     their public response decoders. Raw transport helpers remain private
     implementation details beneath the typed operations, and the
     command-module import/API allowlists are tightened.
   - Removed `files` from `src/root.zig` and the package allowlist after all CLI
     callers moved to the typed core, and tightened the internal module
     allowlists.
   - Updated README and implementation-design architecture text for the
     supported Files API and CLI-owned presentation.

   **Compatibility:** Removes the undocumented `nbimg.files` package path.
   Files commands intentionally broaden successful-status handling from HTTP
   200 to every 2xx response; command syntax and documented output remain
   unchanged. Explicit `STATE_UNSPECIFIED`/`SOURCE_UNSPECIFIED` metadata is
   omitted like absent metadata because the typed model deliberately
   normalizes those cases.

   **Validation completed:** Covered every Files CLI outcome type,
   representative non-200 2xx upload/get/list responses, all 2xx delete
   statuses, API failures, malformed successes, path-derived upload MIME
   conversion, decimal size formatting, every known and unknown state/source
   branch, unspecified and typed-only metadata omission, JSON escaping,
   pagination ownership transfer and aggregation, retained upload admission
   behavior, and timeout diagnostics. Exact package/internal allowlists and
   the external-consumer compile assertion verify that the legacy Files
   models, public decoders, and `nbimg.files` export are gone. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live Files targets were not run because transport,
   endpoints, request fields, and the decoded schema were unchanged.

   **Complete when:** CLI Files commands and public methods share typed
   operation cores and `nbimg.files` is no longer package-accessible.

11. **Introduce deliberate Batch-input validation and public preparation**

   **Depends on:** Items 6, 8, and 9.

   **Status:** Completed.

   **Result:** Consumers can validate Batch JSONL and prepare generation or
   edit entries without exposing generate-content JSON or count-token
   envelopes. CLI Batch-file preparation remains on its existing path until
   Item 12.

   **Proposed changes:**

   - Add `Client.prepareGenerationBatchEntry` and
     `Client.prepareEditBatchEntry` for explicit non-empty caller-provided
     keys. Each operation performs count-token validation and returns an owned
     `Outcome(PreparedBatchEntry)` so completed count-token API failures remain
     distinguishable from Zig errors. `PreparedBatchEntry` contains the owned
     key, one complete JSONL record without a trailing newline, and total token
     count, and provides `deinit(allocator)`.
   - Keep Batch-specific public value types and pure validation/entry helpers
     in `src/batch.zig`, then alias them through `client.zig` and `root.zig`.
     Do not add a separate Batch-domain module unless a real import cycle
     appears; unlike Item 9, the new names do not conflict with retained legacy
     Batch types.
   - Define an internal owned `PreparedBatchRequest` containing the exact
     generate-content JSON and total token count, with `deinit(allocator)`.
     Introduce context-taking generation and edit phase-one preparation
     operations in `client.zig` that return
     `OperationOutcome(PreparedBatchRequest)`. These functions are `pub` only
     as exact-allowlisted internal cross-module seams so Item 12 can call them;
     they are not re-exported through `src/root.zig`.
   - Before the two-phase workflow, validate the explicit public key before
     request allocation or network IO. Phase one converts and validates the
     typed generation or edit request, retains the exact owned
     generate-content JSON, and validates that request through `countTokens`.
     Phase two wraps those exact retained bytes, enforces the complete
     entry-size limit, and transfers the key, entry, and token count into
     `PreparedBatchEntry`. Do not rebuild the request between validation and
     JSONL entry construction.
   - Refactor `Client.countGenerateTokens` and `Client.countEditTokens` to use
     the same context-taking count-token classification used by phase one.
     Internal classification returns the shared stage-aware outcome; public
     methods convert malformed successful countTokens responses to Zig errors.
     Do not migrate the CLI Batch-file path in this item.
   - Expose `validateBatchInput(bytes) !BatchInputSummary`, returning a
     non-owning summary with `entry_count` and `byte_count`. Preserve the
     existing structural validation: total bytes, non-empty CRLF/LF-aware
     records, complete record size, and record count, without parsing JSON or
     revalidating the semantics of existing request objects.
   - Export `BatchValidationError` containing `EmptyBatchKey`,
     `EmptyBatchInput`, `InvalidBatchInput`, `BatchEntryTooLong`,
     `BatchTooManyEntries`, and `BatchInputTooLong`. Generation/edit request
     validation errors remain their existing named errors. Preparation rejects
     an empty explicit key before request allocation or network IO.
   - Export stable admission limits as `max_batch_entry_bytes`,
     `max_batch_entries`, and `max_batch_input_bytes`. Keep JSON builders,
     envelope composition, locking helpers, and output-download limits
     internal until their owning public workflows are introduced.
   - Keep existing CLI Batch-file output, countTokens handling, generated keys,
     locking, receipts, and direct internal builders unchanged in this item.
   - Add README and implementation-design examples for explicit-key
     preparation, ownership, validation summaries, and writing JSONL lines.

   **Compatibility:** Additive until package access to the old Batch helpers is
   removed by Item 15. CLI behavior remains unchanged.

   **Validation:** Test explicit-key ownership, phase-one ownership and
   cleanup, quiet-context behavior, every successful 2xx class, complete
   count-token API failure bodies, malformed count-token successes, validation
   before allocation/network IO, byte-for-byte reuse of the validated
   generate-content JSON, exact JSONL shape, complete-entry size enforcement,
   structural validation summaries without JSON parsing, all limits, exact
   allowlists, and external-consumer compilation. Run generation/edit
   request-validity live targets only if request construction or countTokens
   envelope behavior changes.

   **Validation completed:** Covered explicit-key and prepared-entry ownership,
   retained phase-one request ownership and cleanup, quiet public contexts,
   every 2xx countTokens status, complete API-failure bodies, malformed
   successes, validation before allocation or network IO, byte-for-byte
   request reuse, escaped keys, exact newline-free JSONL shape, exact and
   oversized complete-entry boundaries, LF/CRLF summaries, structural-only
   acceptance, blank records, and all admission limits. Exact package/internal
   allowlists and the external-consumer test cover the additive API. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. Live targets were not run because request construction,
   the countTokens envelope, transport, and endpoint behavior remain
   wire-compatible.

   **Complete when:** Public Batch preparation and structural validation
   require no raw Gemini builders or response decoders, while the CLI remains
   behaviorally unchanged for the next migration.

12. **Migrate CLI Batch-file preparation to the typed core**

   **Depends on:** Item 11.

   **Status:** Completed.

   **Result:** `gen --batch-file` and `edit --batch-file` share the validated
   preparation core with public methods while preserving atomic automatic-key
   generation and file rollback.

   **Proposed changes:**

   - Route generation and edit Batch-file preparation through the allowlisted
     phase-one context-taking operations introduced by Item 11. CLI contexts
     retain request/response traffic logging and configured timeout behavior.
     Use the existing `generationRequestFromCommand` and
     `editRequestFromCommand` adapters so immediate and Batch modes convert CLI
     options identically. Do not call the public explicit-key preparation
     methods: automatic keys must still be derived under the file lock.
   - Apply the common response contract: accept every completed 2xx
     countTokens response, print complete non-2xx bodies, map malformed
     successful responses to exit code 3, and keep transport/timeout
     diagnostics unchanged.
   - Keep count-token validation outside the file lock. Hold one
     `PreparedBatchRequest`, pass its exact retained generate-content JSON into
     the locked append phase, and release it after append/receipt handling; do
     not rebuild it.
     Split the current raw-response `runBatchRequest` orchestration into typed
     phase-one outcome handling and the existing locked append/receipt phase.
   - Generate automatic keys from the locked file offset. For explicit
     `--batch-key`, perform duplicate inspection under the same exclusive lock.
     Key derivation, existing-file inspection, JSONL wrapping, append, and
     rollback remain one locked transaction.
   - Preserve the current JSONL bytes, generated keys, duplicate-key behavior,
     separators, limits, receipts, and rollback semantics.
   - Remove direct CLI dependencies on generation/edit request JSON builders,
     countTokens envelope construction, and raw countTokens response decoding
     once the typed path has no remaining caller. Keep the command builders
     public internally only for their remaining `client.zig` caller, and
     tighten internal allowlists to reflect the removed CLI edges.
   - Update README and implementation-design ownership text for the shared
     preparation core and CLI-owned locking/filesystem behavior.

   **Compatibility:** CLI JSONL output, receipts, locking, and command syntax
   remain unchanged. Successful countTokens handling broadens from HTTP 200 to
   every 2xx response.

   **Validation:** Test context logging, all successful 2xx classes, complete
   API failures, malformed successful responses and exit code 3, timeout
   diagnostics, byte-for-byte request reuse, automatic keys under lock,
   explicit and duplicate keys, maximum limits, separator insertion, partial
   write rollback, malformed existing input preservation, and receipts. Run
   all offline validation and the ReleaseSafe build; run request-validity live
   targets only if request construction or countTokens envelopes change.

   **Validation completed:** Routed `gen --batch-file` and `edit --batch-file`
   through typed phase-one preparation, added CLI coverage for retained request
   bytes, token-count receipts, complete API-failure diagnostics, malformed
   countTokens exit code 3, parser traffic flags in Batch mode, and partial
   write rollback. Existing append tests continue to cover automatic offset
   keys, explicit and duplicate keys, separators, max limits, malformed input
   preservation, and no-rebuild JSONL wrapping. Exact allowlist tests ran as
   part of `zig build test`. Ran `zig fmt --check build.zig src`,
   `zig build test`, `zig build`, and `git diff --check`. Live targets were not
   run because request construction and countTokens envelopes were not changed.

   **Complete when:** Public and CLI Batch preparation share one typed
   validation core, and automatic keys are still derived atomically from the
   locked file offset.

13. **Add typed remote Batch job management**

   **Depends on:** Items 9 and 11.

   **Status:** Completed.

   Item 13 added remote Batch job management. Item 14 later added typed output
   download, and Item 15 later migrated CLI Batch commands to these typed
   cores.

   **Result:** Consumers can upload file-backed Batch input and create, get,
   list, or cancel remote Batch jobs without raw HTTP responses or public
   response decoders.

   **Proposed changes:**

   - Limit the supported remote Batch API to the existing file-backed
     management workflows: upload input, create, get, list, and cancel. Inline
     creation, embeddings Batch creation, Batch update/delete, and output
     download are out of scope for this item. Item 14 adds file-backed output
     download separately.
   - Add `Client.uploadBatchInput`, `Client.createBatch`, `Client.getBatch`,
     `Client.cancelBatch`, and `Client.listBatchesPage`.
   - Keep the public Batch request/result/state/stats types in `src/batch.zig`
     and alias them through `client.zig` and `root.zig`, following Item 11.
     Typed Batch cores in `batch.zig` may deliberately import
     `files_domain.zig` and `operation.zig`; update the documented module
     boundary rather than duplicating shared outcome or remote-error types.
   - Define borrowed `BatchInputUpload` with bytes and optional display name,
     and borrowed `BatchCreateRequest` with canonical input file name and
     display name. Creation continues to use the repository's fixed image
     model; this refactoring does not add a public model selector. Extend
     `BatchValidationError` in this item with remote
     operation errors `InvalidBatchName`, `InvalidFileName`,
     `InvalidDisplayName`, and `EmptyPageToken`. Validate every public input
     before allocation or network IO.
   - Keep listing explicit and narrow: `listBatchesPage` accepts only an
     optional continuation token and uses the existing fixed page size.
     Although the current REST reference documents standard `pageSize`,
     `filter`, and `returnPartialSuccess` query fields, exposing them is
     outside this refactoring's existing-workflow scope.
   - `Client.uploadBatchInput` structurally validates the complete JSONL input
     with `validateBatchInput` before upload. It does not parse or semantically
     revalidate nested request objects. Retain the current
     `max_batch_input_bytes` implementation limit even though the remote guide
     advertises a larger Batch input-file maximum; raising that bound needs a
     separate streaming and resource-budget design.
   - Generalize the internal typed Files upload core just enough to accept the
     Batch JSONL content type and return `OperationOutcome(File)`. Reuse the
     Item 9 upload response decoder and ownership; do not duplicate File wire
     parsing in `batch.zig` or expose arbitrary content-type strings publicly.
     The Batch upload path must use `max_batch_input_bytes` and
     `application/jsonl`; it must not inherit the image-only
     `max_file_upload_bytes` admission limit or require an `InputImageMime`.
     As with image upload, transport or decoding errors after dispatch may
     leave a remote File whose name is unavailable; do not retry
     automatically.
   - Move the currently private shared remote-error wire decoding out of the
     Files operation implementation into one exact-allowlisted internal helper
     in `files_domain.zig`, usable by both Files and Batch decoding. Keep the
     public `RemoteError` type unchanged and do not implement a second
     Status/details parser in `batch.zig`.
   - Keep upload and creation separate so callers retain the uploaded file name
     when non-idempotent creation fails. Treat every Zig error after dispatch
     from `Client.createBatch`—including transport and successful-response
     decoding failures—as ambiguous: do not retry automatically, and document
     that a remote job may have been created but its name may be unavailable.
     A completed non-2xx `ApiFailure` is a definitive service response rather
     than this ambiguous category.
   - Define `BatchState` as a tagged union with `unspecified`, `pending`,
     `running`, `succeeded`, `failed`, `cancelled`, `expired`, and
     `unknown: []u8`. Normalize equivalent REST `BATCH_STATE_*` and SDK-guide
     `JOB_STATE_*` spellings to known tags; own the original spelling only for
     `.unknown`. Do not invent `queued` or `cancelling` states that are absent
     from the current API contract.
   - Reuse `RemoteError` from Item 9. Define `BatchStats` with optional `u64`
     request, successful, failed, and pending counts. Define owned `BatchJob`
     with canonical name; optional owned display name, model, create/update/end
     timestamps, canonical input file name, and canonical output file name;
     optional signed priority; `BatchState`; `BatchStats`; optional operation
     `done` flag; and optional `RemoteError` as `remote_error`.
     Define `BatchListPage` as owned jobs plus an optional continuation token.
     Every owning type provides `deinit(allocator)`.
     Absent state maps to `.unspecified`. Accept integral counters and priority
     from either decimal JSON strings or integral JSON numbers; reject
     negative counters, fractional values, overflow, malformed present
     numeric values, noncanonical present File names, and malformed present
     model names. A present model must use canonical non-empty `models/...`
     form.
   - Decode the documented long-running `Operation` wrapper and the observed
     SDK/discovery placements already accepted by the legacy decoder: Batch
     fields may be at the operation root, directly under `metadata`, directly
     under `response`, or under `response.batch`. File-backed output may be
     represented as `output.responsesFile`, `response.responsesFile`, or the
     SDK-style `dest.fileName`. Get/list may observe inline input/output or jobs
     created for other models; preserve available model and common metadata
     while representing absent file input/output as null. Do not expose inline
     requests or responses. Decode a top-level long-running-operation `error`
     into `BatchJob.remote_error`, preserving code, message, and details.
     Creation decoding requires at least the canonical Batch name; all other
     fields may be absent in the initial operation response.
   - Return typed outcomes consistently: uploads return `Outcome(File)`,
     create/get return `Outcome(BatchJob)`, cancel returns
     `Outcome(void)`, and listing returns `Outcome(BatchListPage)`.
   - Add exact-allowlisted context-taking typed cores for upload, create, get,
     cancel, and list. Public methods supply quiet contexts; Item 15 reuses the
     same cores with CLI traffic logging. These seams are not package exports.
   - Reuse the shared generic stage-aware outcome. Every typed Batch operation
     accepts any completed 2xx status; there is no caller-selectable status
     policy.
   - Keep safe local filenames, duplicate-key handling, output file writing,
     raw JSON presentation, and all current CLI Batch commands unchanged.
     Extend the exact package allowlist and external-consumer compile tests for
     the additive API.
   - Add README and implementation-design examples for upload, creation,
     status, cancellation, listing, ownership, pagination, and ambiguous
     creation failures.

   **Compatibility:** Additive. The undocumented `nbimg.batch` path and all CLI
   Batch command behavior remain unchanged.

   **Completed changes:**

   - Added public typed Batch upload/create/get/cancel/list methods on
     `Client`, plus `BatchInputUpload`, `BatchCreateRequest`, `BatchState`,
     `BatchStats`, `BatchJob`, and `BatchListPage` re-exported through the
     package root.
   - Added context-taking typed Batch cores in `src/batch.zig`; public methods
     use quiet contexts, while CLI Batch commands continue to use the legacy raw
     JSON path.
   - Moved shared File and remote-error decoding into `src/files_domain.zig` so
     Batch JSONL upload and operation errors reuse the typed Files ownership
     rules without depending on `src/files.zig`.
   - Extended `BatchValidationError` with remote-management validation errors
     and validated Batch JSONL bytes, names, display names, and page tokens
     before allocation or network IO.
   - Decoded operation wrappers from root, `metadata`, `response`, and
     `response.batch`; normalized `BATCH_STATE_*` and `JOB_STATE_*`; decoded
     stats, signed priority, canonical model/file names, output-file placements,
     operation `done`, pagination, and operation `remote_error`.
   - Updated exact package and internal allowlists, external-consumer compile
     coverage, README API examples, and implementation design notes.

   **Validation:** Cover all public validation errors before
   allocation/network IO, pagination, canonical names, both known wire
   prefixes for every applicable state, every BatchStats field, signed
   priority, wrapper placements, unknown-state preservation, absent file
   input/output for inline jobs, malformed numeric and resource-name fields,
   structural upload validation, every successful 2xx cancellation body shape,
   preserved remote failure details, no automatic retry after ambiguous
   creation failure, exact allowlists, and external-consumer compilation.
   Update and run the read-only, non-billable Batch list live target against
   the typed decoder. Never run the billable submit/status live target without
   explicit authorization; if it is not authorized, report create-specific
   live validation as an explicit gap.

   **Complete when:** Package consumers can manage file-backed Batch jobs
   without raw response bodies or public wire decoders, while output download
   and all CLI Batch paths remain unchanged for the next items.

   **Validation completed:** Added focused offline tests for validation,
   request JSON priority serialization, JSONL upload decoding, wrapper
   placements, state normalization and unknown ownership, stats/priority
   parsing, malformed present fields, list pagination ownership, all 2xx and
   non-2xx outcome classification, cancellation bodies, and public ownership
   cleanup. Exact allowlist and external-consumer tests ran as part of
   `zig build test`. Ran `zig fmt --check build.zig src`, `zig build test`,
   `zig build`, and `git diff --check`. The task assumptions authorized the
   billable live target; live validation ran through
   `zig build test-live-api-batch-list` and
   `zig build test-live-api-batch-submit-status`.

14. **Add typed Batch output download**

   **Depends on:** Item 13.

   **Status:** Completed.

   Item 14 added the public typed output download workflow. CLI Batch download
   migration was later completed by Item 15.

   **Result:** Consumers can download and process file-backed Batch output
   through a bounded borrowed-record visitor without internal line iterators or
   eager retention of decoded results.

   **Proposed changes:**

   - Add `Client.downloadBatchOutputRecords(output_file_name, visitor)`,
     accepting the canonical output `files/...` name from `BatchJob`. It
     performs one Files download request and does not repeat the Batch status
     request.
   - Define borrowed `BatchOutputRecordView` with a borrowed key and a tagged
     result containing either `*const GenerationResult` or
     `*const RemoteError`. The view and all nested data are valid only for the
     visitor call. Invoke the visitor in downloaded JSONL order. Preserve
     duplicate keys; duplicate handling remains a caller or CLI decision.
   - Define `BatchOutputVisitor` as an opaque caller context plus a callback
     with the conceptual signature
     `fn (*anyopaque, BatchOutputRecordView) anyerror!void`. Define
     `BatchOutputSummary` with total, successful, and failed record counts.
     Visitor errors propagate unchanged as outer Zig errors and stop
     processing; they are not reclassified as successful-response decoding
     failures.
   - Avoid a `client.zig`/`batch.zig` cycle: keep bounded download transport,
     CRLF-aware JSONL iteration, and wire-record decoding in `batch.zig`; keep
     the public visitor types and orchestration that converts decoded generated
     files into `GenerationResult` in `client.zig`. Do not extract another
     shared generation-domain module unless a second non-client owner appears.
   - Add a new exact-allowlisted internal decoded-record type in `batch.zig`
     that owns the key and a tagged compact response-JSON or error-JSON
     payload. Keep the legacy `OutputRecord` shape unchanged until Item 15;
     it currently discards per-record error details and is therefore
     insufficient for the typed visitor. Decode the error JSON through the
     shared remote-error helper introduced by Item 13.
   - Export the stable output admission limit as `max_batch_output_bytes`.
     Retain at most the complete bounded raw JSONL body plus one decoded record
     and its images. Decode records sequentially, invoke the visitor, then
     release that record before continuing.
   - The typed decoder is strict: malformed JSONL, empty records, malformed
     response/error records, malformed remote errors, and generated-image
     decoding failures are successful-response decoding failures. A record
     must have exactly one of response or error. Remote error records and
     duplicate keys are valid records.
   - The public method returns `Outcome(BatchOutputSummary)`. The internal
     context-taking core uses the shared stage-aware outcome for HTTP and
     decoding stages, while visitor callback errors remain outer Zig errors.
     Every completed 2xx download response is eligible for decoding.
   - Keep safe local filenames, duplicate-key policy, output file writing, and
     all current CLI Batch download behavior unchanged.
   - Add README and implementation-design examples for download, record-view
     lifetimes, duplicate keys, remote errors, callback errors, and peak
     ownership.

   **Compatibility:** Additive. The undocumented `nbimg.batch` path and CLI
   Batch download behavior remain unchanged.

   **Validation:** Cover canonical output names before allocation/network IO,
   every completed 2xx class, complete API failures, output bounds,
   full-body-plus-one-record peak ownership, callback errors and partial
   cleanup, typed success and failure views, preserved remote failure details,
   malformed JSONL/records/errors/images, duplicate-key preservation, exact
   allowlists, and external-consumer compilation. A live output download
   requires a completed billable Batch job; do not create one without explicit
   authorization, and otherwise report live download validation as an explicit
   gap.

   **Complete when:** Package consumers can process file-backed Batch output
   without raw response bodies, public wire decoders, internal line iterators,
   or eager decoded-result aggregates.

   **Completed changes:**

   - Added `Client.downloadBatchOutputRecords`, `BatchOutputRecordView`,
     `BatchOutputVisitor`, and `BatchOutputSummary`, and re-exported them
     through the package root.
   - Added `downloadBatchOutputRecordsWithContext` as the exact-allowlisted
     internal seam for future CLI reuse.
   - Kept bounded download transport, CRLF-aware JSONL iteration, and
     compact typed record decoding in `src/batch.zig`; kept public visitor
     orchestration and generated-result conversion in `src/client.zig`.
   - Added strict typed Batch output decoding that preserves duplicate keys,
     supports remote-error records, treats malformed output as a
     successful-response decoding failure, and releases each decoded record
     after its visitor callback.
   - Extended exact package/internal allowlists, external-consumer coverage,
     README examples, and implementation-design notes for typed Batch output
     download.

   **Validation completed:** Covered canonical output-name validation before
   allocation/network IO, all 2xx and non-2xx download classifications, output
   bounds, callback error propagation, typed success and remote-error records,
   malformed JSONL/records/errors/images, duplicate-key preservation,
   ownership cleanup, exact allowlists, and external-consumer compilation. Ran
   `zig fmt --check build.zig src`, `zig build test`, `zig build`, and
   `git diff --check`. The completed Batch output fixture allowed live output
   download validation without creating a new billable job.

15. **Migrate CLI Batch commands to typed operations**

   **Depends on:** Items 12, 13, and 14.

   **Status:** Completed.

   Item 15 completed the CLI Batch command migration and removed the legacy
   package-level `batch` export. With this done, Item 16 is the recommended
   next implementation increment.

   **Result:** CLI Batch commands and the public client share typed operation
   cores, allowing the legacy package-level `batch` export and raw-response
   presentation seams to be removed.

   **Proposed changes:**

   - Migrate Batch input upload, create, get/status, and cancel/list to the
     context-taking typed cores introduced by Item 13, and download to the
     visitor core introduced by Item 14.
     `batch download` first calls the typed get/status core, requires a
     succeeded job with a canonical output file name, then passes that name to
     the typed visitor download core; it must not issue a second status request
     inside the download core.
   - Apply the common response contract while preserving diagnostics, traffic
     logging, timeout reporting, the ambiguous-creation warning, exit-code
     categories, and non-idempotent no-retry behavior.
     A create transport failure remains an ambiguous exit-1 failure; a
     malformed successful create response is also reported as ambiguous but
     retains exit code 3; a completed non-2xx response is definitive and exits
     1.
     Preserve the current `OK` stdout result for a successful `batch cancel`.
   - Replace raw successful-response presentation for `batch submit`, `status`,
     and `list` with deliberate CLI-owned JSON serialization of
     `BatchJob` and `BatchListPage`. Use camelCase field names. A job object
     always includes `name`; it includes `displayName`, `model`, `state`,
     `done`,
     `createTime`, `updateTime`, `endTime`, `priority`, `inputFileName`,
     `outputFileName`, `batchStats`, and `error` only when represented by the
     typed value. Render known states as documented uppercase
     `BATCH_STATE_*` spellings, preserve unknown spellings, and omit
     `.unspecified`. Render priority and all BatchStats counters as decimal
     JSON strings. Omit `batchStats` when every counter is absent; otherwise
     omit only absent counters inside it. Render `RemoteError` as `code`,
     `message`, and embedded `details`, omitting absent fields. `batch submit`
     and `batch status` print one job object; `batch list` prints
     `{"batches":[...]}`. Do not retain complete raw success bodies or expose
     unknown wire fields merely to preserve historical pretty-printed output.
   - Keep safe output keys, duplicate-key handling, local filename generation,
     exclusive file writes, and presentation formatting in `src/cli.zig`. Use
     the same strict Batch output decoder as the public visitor: malformed
     JSONL, malformed records, and image decode failures stop the command as
     successful-response decoding failures. Remote error records and duplicate
     keys are valid typed records and remain visible to the CLI callback.
     Decisions to continue after an individual file-write failure or to report
     duplicate output names remain CLI callback behavior, not a decoder policy.
     Decoder failures map to exit code 3; visitor/local filesystem failures
     remain outer Zig errors and map to exit code 1 unless the callback records
     them and intentionally continues.
   - Remove `batch` from `src/root.zig` and the package allowlist after every
     CLI command uses the typed operation cores. Tighten the internal Batch and
     shared API allowlists.
   - Update README and implementation-design architecture text to distinguish
     the supported typed Batch API, deliberate CLI JSON presentation, and
     CLI-owned filesystem behavior.

   **Compatibility:** Removes the undocumented `nbimg.batch` package path. CLI
   command syntax remains stable, but successful status handling broadens to
   every 2xx response, submit/status/list output moves from raw wire JSON to
   documented typed CLI JSON, and malformed downloaded output becomes a
   command failure instead of a tolerated record.

   **Completed changes:**

   - Routed Batch submit, status, cancel, and list through the context-taking
     typed cores introduced by Item 13, and routed download through the typed
     visitor core introduced by Item 14 after one typed status request.
   - Preserved diagnostics, traffic logging, timeout reporting, the
     ambiguous-creation warning, exit-code categories, non-idempotent no-retry
     behavior, and `OK` stdout for successful cancellation.
   - Replaced raw successful-response presentation for `batch submit`,
     `status`, and `list` with CLI-owned JSON serialization of `BatchJob` and
     `BatchListPage`, including deliberate state, stats, priority, and
     remote-error formatting.
   - Kept safe output keys, duplicate-key handling, local filename generation,
     exclusive writes, and per-record filesystem behavior in `src/cli.zig`.
     The CLI now uses the strict typed Batch output decoder while preserving
     callback-owned decisions for duplicate keys, remote-error records, and
     local write failures.
   - Removed `batch` from `src/root.zig` and the package allowlist. Tightened
     the internal Batch and shared API allowlists.
   - Updated README, implementation-design architecture text, and the nbimg
     skill Batch operations reference for the typed CLI Batch contract.

   **Validation:** Add CLI tests for upload/create ambiguity, multiple
   successful 2xx statuses, the documented typed submit/status/list JSON
   schemas, cancellation, pagination, download bounds, strict malformed-record
   handling, typed remote-error records, duplicate keys, existing files, write
   failures, timeout diagnostics, and exit-code mapping. Assert that no raw
   success-body capture or Batch decoder policy remains. Run exact
   package/internal allowlists, external-consumer tests, all offline validation,
   and the ReleaseSafe build. Run the read-only Batch list live target after
   changing list decoding/presentation. Never run the billable, non-idempotent
   submit/status live target without explicit authorization.

   **Complete when:** Every CLI Batch command shares typed operation cores with
   the public client, CLI JSON is produced from typed values, no raw
   successful-response or tolerant-decoder seam remains, and `nbimg.batch` is
   no longer package-accessible.

   **Validation completed:** Covered typed submit/status/list JSON
   presentation, cancellation, pagination, typed output visitor processing,
   safe output filenames, duplicate-key handling, existing targets, local
   write failures, strict malformed-record handling, timeout diagnostics,
   ambiguous create diagnostics, exact package/internal allowlists, and the
   external-consumer contract. Ran `zig fmt --check build.zig src`,
   `zig build test`, `zig build`, `git diff --check`,
   `zig build test-live-api-batch-list`, and
   `zig build test-live-api-batch-submit-status`.

16. **Remove the legacy shared API namespace**

   **Depends on:** Items 8, 10, 12, and 15.

   **Status:** Completed.

   **Result:** `api.zig` remains an internal shared implementation module and
   is no longer part of the package contract.

   **Proposed changes:**

   - Verify that every supported option, request, result, MIME, limit, and
     ownership operation has a deliberate root-level replacement.
   - Remove `api` from `src/root.zig` and the package allowlist.
   - Remove package access to raw HTTP types, model selectors, resumable-upload
     structures, wire shapes, JSON builders, response decoders, serializers,
     endpoint helpers, environment lookup, and generic HTTP functions.
   - Keep declarations `pub` internally only where cross-file access still
     requires it.
   - Keep the named `nbimg` build module and compile-only consumer tests
     passing with only supported root declarations.

   **Compatibility:** This is the final removal of the undocumented
   `nbimg.api` path.

   **Completed changes:**

   - Removed `api` from `src/root.zig` and the package allowlist.
   - Added an external-consumer guard proving the named `nbimg` module no
     longer exposes `nbimg.api`.
   - Updated README and implementation-design text so `api.zig` is described
     as an internal shared implementation module, not a package contract.

   **Validation:** Run package and internal allowlist tests, compile-only
   consumer tests, all offline validation commands, and the ReleaseSafe build.

   **Complete when:** No package-visible declaration exposes transport or
   Gemini wire implementation details.

   **Validation completed:** Ran `zig fmt --check build.zig src`,
   `zig build test -Dtest-filter="package API matches exact allowlist"`,
   `zig build test -Dtest-filter="internal module APIs match exact allowlists"`,
   `zig build test -Dtest-filter="dependency consumer compiles against typed generation edit Files and Batch preparation APIs"`,
   `zig build test`, `zig build`, and `git diff --check`. No live API target
   was required because no Gemini request or response behavior changed.

17. **Audit public invariants and reduce internal seams**

   **Depends on:** Item 16.

   **Status:** Completed.

   **Result:** Audited the current root package façade and kept the supported
   root declarations unchanged. Removed the unused internal
   `api.decodeUploadedFileName` seam, made the Files-only wire remote-error
   type and ownership helper private in `files_domain.zig`, and kept
   `remoteErrorFromJsonValue` public for Batch decoding.

   **Proposed changes:**

   - Inventory every root-level package declaration against the supported
     categories now exposed by `src/root.zig`: `Client`, client options,
     request/result values, response outcomes, validation error sets, MIME and
     option enums, ownership methods, documented limits, and deliberate pure
     validators. If a root declaration no longer has a current consumer use
     case, either remove it with matching allowlist/consumer-test updates or
     record why Item 18 should document it.
   - Audit that every public operation returns validation errors rather than
     asserting on caller input. Do not defer known public invariant work from
     Items 4 through 15 to this item.
   - Retain assertions only for internal programmer errors and paired
     trust-boundary invariants. Lower-level command builders may assert
     preconditions only when every public and CLI caller validates them first.
   - Verify that public domain enums expose no wire serialization or CLI
     parsing methods. Keep necessary CLI parsing and wire serialization helpers
     on internal modules only.
   - Verify that CLI name parsing, environment lookup, output naming, safe-key
     encoding, typed Batch JSON presentation, and filesystem effects are
     CLI-owned or internal-only.
   - Verify that no caller-selectable runtime HTTP-status or service-tier
     policy, raw-success-body presentation seam, or tolerant-record-decoding
     policy remains. Unknown reported service-tier spellings must consistently
     remain decoding errors. Distinct operations may retain distinct decoders
     only when their typed result contracts genuinely differ.
   - Make cross-file declarations private where completed migrations removed
     their callers, and tighten internal module allowlists.
     Same-file tests and possible future use are not sufficient reasons to
     keep an internal declaration `pub`.
   - Do not redesign the flat module graph or remove an internal seam that has
     a current cross-file caller merely because the seam is implementation
     detail; Item 18 will handle final contract documentation.

   **Compatibility:** Supported client APIs remain stable. Only internal seams
   and accidental visibility change.

   **Validation:** `zig fmt --check build.zig src`;
   `zig build test -Dtest-filter="package API matches exact allowlist"`;
   `zig build test -Dtest-filter="internal module APIs match exact allowlists"`;
   `zig build test -Dtest-filter="dependency consumer compiles against typed generation edit Files and Batch preparation APIs"`;
   `zig build test`; `zig build`; and `git diff --check`. No live API target
   was required because no Gemini request fields, response decoding behavior,
   transport behavior, or CLI workflows changed.

   **Complete when:** Public callers reject invalid caller input with typed
   validation errors before lower-level assertions, root-visible containers
   expose no CLI or wire helpers, and every remaining internal `pub` has a
   current cross-file caller or a written justification for Item 18.

18. **Finalize and document the stable package contract**

   **Depends on:** Items 1 through 17.

   **Status:** Completed.

   **Result:** The already usable client API is declared stable, and the
   README, implementation design, exact allowlists, external-consumer test, and
   root exports describe the same supported package contract.

   **Completed changes:**

   - Kept the Item 17 audit result: no root-level declarations were added,
     removed, or renamed.
   - Reconfirmed the package allowlist as the exact `Client`, configuration,
     outcome, request/result, input/output MIME, enum, ownership, documented
     limit, and deliberate pure-validator contract.
   - Updated the README `Zig Library API` section to explicitly name the
     stable root-level package contract and unsupported implementation-module,
     raw transport, wire, and CLI parser surfaces.
   - Updated `docs/IMPLEMENTATION_DESIGN.md` with the final package facade
     boundary, common public response contract, internal module boundaries,
     and CLI-owned JSON/output schemas.
   - Retained the historical pre-refactoring label on
     `public_api_analysis.md`.
   - Renamed and expanded the compile-only external-consumer test so it
     continues to import the supported named `nbimg` module and covers the full
     typed generation, edit, Files, Batch management, and Batch output surface.

   **Compatibility:** This item declares the replacement contract stable; it
   does not introduce the first usable documentation or remove additional
   supported declarations except for any unsupported declarations explicitly
   carried forward from Item 17.

   **Validation completed:** `zig fmt --check build.zig src`;
   `zig build test -Dtest-filter="package API matches exact allowlist"`;
   `zig build test -Dtest-filter="internal module APIs match exact allowlists"`;
   `zig build test -Dtest-filter="dependency consumer compiles against typed generation edit Files and Batch APIs"`;
   `zig build test`; `zig build`; and `git diff --check`. Also manually verify
   every README/design-doc path and command touched by this item. No live API
   target is required unless the item changes Gemini request fields, response
   decoding behavior, transport behavior, or CLI workflows.

   **Complete when:** README examples, implementation documentation, exact
   allowlists, external-consumer tests, the build graph, and actual root
   exports describe the same supported API.

## Schema Baseline for Remote Batch APIs

Items 13 through 15 used the current official
[Files API](https://ai.google.dev/api/files),
[Batch API reference](https://ai.google.dev/api/batch-api), and
[Batch guide](https://ai.google.dev/gemini-api/docs/batch-api) as their schema
baseline. Recheck these sources before future remote Batch or Files changes
because File metadata, Batch operation wrappers, and state spellings are remote
versioned behavior. Schema drift may require additive unknown variants or
decoder compatibility, but must not silently expand the file-backed workflow
scope selected above.
The June 25, 2026 review confirmed that the REST reference documents the
long-running `Operation` wrapper, `BATCH_STATE_*`, all four `BatchStats`
counters, signed priority, timestamps, and file-backed
`inputConfig.fileName`/`output.responsesFile`. Current REST guide examples
place state under `metadata` and file output directly under
`response.responsesFile`, while SDK guide examples still expose `JOB_STATE_*`
and `dest.fileName`. Item 13 deliberately accepts all listed representations,
and Item 15 preserved that compatibility. The REST reference states that
file-backed output records are written in input order, which Item 14 preserves
through visitor order. The guide currently advertises a 2 GB Batch input-file
maximum; this refactoring deliberately retains the repository's existing
512 MiB admission limit.
Raising that resource bound is a separate design change, not an incidental
API-refactoring side effect. The reference also documents Batch delete and
update methods, but they remain outside this plan because the current CLI has
no corresponding workflow.

## Validation Policy for Future Refactorings

Every Zig refactoring above should run:

```sh
zig fmt --check build.zig src
zig build test
```

Run `zig build` whenever root exports, executable wiring, installed artifacts,
or the build graph change.

Use focused offline tests before live validation. New or changed Gemini request
fields require the relevant non-billable live validity target. Files live
tests may create and delete remote resources. The billable, non-idempotent
Batch submit/status target must run only with explicit user authorization. If
a changed Batch create field has no non-billable validation path and live
creation is not authorized, report that validation gap instead of claiming
complete live coverage.

The offline transport tests bind ephemeral loopback sockets for local HTTP
servers. In a sandbox that blocks `bind`, run `zig build test` with the narrow
permission required for loopback socket binding. An `EPERM` failure from
`listenLocalHttp` is an environment restriction, not a substitute for a
passing test run; rerun with that permission before reporting validation.

Documentation-only increments should run `git diff --check` and verify every
referenced path and command.

## Planning Assumptions

- The long-term supported library API is organized around `nbimg.Client`
  methods.
- Existing module exports are undocumented and may be removed incrementally
  after supported replacements exist.
- API keys and request input slices remain caller-owned and borrowed for their
  documented lifetimes.
- `Client.init` stores its API key slice without allocating or copying it and
  rejects empty keys and non-positive timeouts with the named validation
  errors.
- Allocated success values and API-failure bodies use explicit allocator-based
  ownership.
- Non-success Gemini responses remain available to consumers through typed
  outcomes with HTTP status and a bounded owned body.
- The transport response bound applies equally to success and non-success
  bodies; oversized bodies return `error.ResponseTooLong` without truncation.
- Public client calls are quiet by default. Existing CLI traffic logging uses
  internal request-context configuration and is not a supported library
  interface.
- Typed operations share context-taking internal cores with their CLI callers;
  public methods supply quiet contexts and CLI callers supply logging-enabled
  contexts. Context selection does not change response semantics.
- Every typed operation and migrated CLI command classifies a completed 2xx
  response as eligible for success and a non-2xx response as an owned API
  failure. No runtime HTTP-status policy is part of the final internal design.
- `InputImageMime` is distinct from generated `OutputMime`; both support JPEG,
  PNG, and WebP without exposing MIME spellings or path parsing.
- Generated-image candidate and part fields are zero-based response-array
  positions used by existing output naming, not optional Gemini candidate
  metadata indexes.
- An absent reported service tier is represented as `null`; an unrecognized
  reported service-tier spelling is a decoding error rather than `null`.
- Oversized API-failure bodies return `error.ResponseTooLong`; failures are not
  silently truncated.
- The supported package is importable through a named `nbimg` build module from
  the first public client increment onward.
- External-consumer tests import that named module through the build graph and
  do not bypass the package boundary with direct source-file imports.
- Batch JSONL prepared-entry values omit the trailing newline; callers or the
  CLI writer add record separators when persisting multiple entries.
- Batch preparation validates and retains one exact generate-content JSON
  value before CLI automatic-key generation; public explicit keys are
  validated first. Neither path rebuilds the request between `countTokens`
  validation and JSONL wrapping.
- Typed Batch creation remains fixed to the repository's image model. Typed
  listing exposes explicit pagination only; standard Batch list filtering and
  partial-success controls remain out of scope.
- The typed Batch download API retains the bounded raw JSONL body, decodes one
  record at a time, invokes a borrowed visitor, and releases that record before
  continuing. It does not eagerly retain all decoded records or image bytes.
- Zig errors from non-idempotent Batch creation after dispatch, including
  transport and successful-response decoding failures, are treated as
  ambiguous and are never retried automatically. Completed non-2xx API
  failures remain definitive service responses.
- Items 9 through 15 deliberately replace historical CLI response semantics:
  all 2xx statuses are accepted, unknown reported service tiers are decoding
  failures, Batch submit/status/list output is serialized from typed values,
  and malformed downloaded Batch records fail the command. Command syntax,
  traffic logging, timeout reporting, and non-idempotent no-retry behavior
  remain stable unless an item states otherwise.
- The project remains Zig standard-library-only and retains a flat module
  layout unless a deliberate façade module is needed.
