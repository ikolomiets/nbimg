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
     until Item 11.
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
     remains deferred to Item 11.
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

   **Result:** Immediate `nbimg edit` and the public client share one typed
   operation core, allowing the legacy package-level `edit` export to be
   removed.

   **Proposed changes:**

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
     path until Item 11.
   - Remove `edit` from `src/root.zig` and the package allowlist. Remove the
     obsolete edit transport operations after migration; retain only internal
     request construction and validation declarations still required by the
     typed client and Batch preparation.
   - Update README and implementation-design architecture text to distinguish
     the supported typed edit API from the temporary internal Batch
     preparation seam.

   **Compatibility:** Removes the undocumented `nbimg.edit` package path. CLI
   behavior remains unchanged.

   **Validation:** Add CLI parity tests for HTTP 200 success, non-200 responses
   including other 2xx statuses, malformed success, absent/known/unknown
   reported service tiers, priority-tier downgrade, file writing, timeout
   diagnostics, and exit-code mapping. Run exact package/internal allowlists,
   the external-consumer compile test, all offline validation, and the
   ReleaseSafe build. Live validation is unnecessary unless request fields or
   transport behavior change.

   **Complete when:** Immediate CLI edit and `Client.edit` share the typed
   operation core, Batch preparation still works, and `nbimg.edit` is no
   longer package-accessible.

9. **Add typed Files operations**

   **Depends on:** Item 7.

   **Result:** Consumers can upload, get, list, and delete Gemini files through
   typed methods without changing CLI execution.

   **Proposed changes:**

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
   - Introduce one internal `HttpStatusPolicy` with `any_2xx` and `ok_only`,
     plus a generic stage-aware `OperationOutcome(T)` that distinguishes typed
     success, owned API failure, and successful-response decoding failure.
     Refactor the existing generated-content seam to use this shared outcome
     and status policy while retaining a separate generated-content decoding
     policy for strict versus unknown-service-tier-tolerant decoding. Reuse
     these internal primitives for Files, countTokens preparation, and Batch
     operations rather than adding operation-specific policy/outcome unions.
   - Add context-taking internal typed Files operations so public methods use
     quiet contexts with `any_2xx`, and Item 10 can reuse them with CLI logging
     and `ok_only`.
   - Keep CLI Files commands and the legacy package export unchanged. Extend
     the exact package allowlist and external-consumer compile tests for the
     additive API.
   - Add README and implementation-design examples for upload, get, explicit
     pagination, delete, ownership, and API failures.

   **Compatibility:** Additive. The undocumented `nbimg.files` path remains
   temporarily available.

   **Validation:** Test every input MIME; image and non-image returned MIME
   metadata; every known and unknown state/source case; absent and populated
   processing errors; download URI; valid, overflowing, negative, and malformed
   size values; canonical decoded names; successful and malformed response
   decoding; all 2xx delete statuses and arbitrary successful delete bodies;
   pagination; ownership and partial cleanup; exact validation errors before
   allocation/network IO; API failures; oversized failure bodies; the shared
   response-policy seam; exact allowlists; and external-consumer compilation.
   Run affected Files live targets only when transport, request behavior, or
   decoded schema fields change.

   **Complete when:** Files consumers require no public response decoders or
   resumable-upload mechanics.

10. **Migrate CLI Files commands to typed operations**

   **Depends on:** Item 9.

   **Result:** CLI Files commands and the public client share typed operation
   cores, allowing the legacy package-level `files` export to be removed.

   **Proposed changes:**

   - Migrate upload, get, list, and delete commands to the context-taking typed
     operations introduced by Item 9.
   - Add narrow CLI adapters from parsed command values and path-derived MIME
     into public Files request values. Keep local path parsing and complete
     file reads in the CLI.
   - Preserve pagination, printed JSON shape, diagnostics, traffic logging,
     timeout reporting, and exit codes. The current CLI has no upload-progress
     UI, so this migration introduces none.
   - Preserve the CLI's exact HTTP policy independently of the public methods:
     CLI Files commands continue to require HTTP 200 even though the public
     typed operations accept any 2xx response. Use the shared internal
     `ok_only` policy rather than changing CLI behavior.
   - Keep local path-extension MIME inference and presentation formatting in
     the CLI. Preserve the current CLI metadata field set and omission rules;
     newly supported public fields such as download URI and processing error
     do not change CLI JSON output in this migration.
   - Remove `files` from `src/root.zig` and the package allowlist after all CLI
     callers use the typed core. Tighten the internal module allowlists.
   - Update README and implementation-design architecture text for the
     supported Files API and CLI-owned presentation.

   **Compatibility:** Removes the undocumented `nbimg.files` package path. CLI
   behavior remains unchanged.

   **Validation:** Add CLI parity tests for every Files command, HTTP 200 and
   other 2xx responses, pagination, API failures, malformed successes, upload
   behavior, timeout diagnostics, and exit-code mapping. Run exact
   package/internal allowlists, the external-consumer compile test, all offline
   validation, and the ReleaseSafe build. Run affected live Files targets only
   when transport or request behavior changes.

   **Complete when:** CLI Files commands and public methods share typed
   operation cores and `nbimg.files` is no longer package-accessible.

11. **Introduce deliberate Batch-input preparation**

   **Depends on:** Items 6, 8, and 9.

   **Result:** Generation and edit requests can be validated and written as
   Batch JSONL without exposing generate-content JSON or count-token
   envelopes.

   **Proposed changes:**

   - Add `Client.prepareGenerationBatchEntry` and
     `Client.prepareEditBatchEntry` for explicit non-empty caller-provided
     keys. Each operation performs count-token validation and returns an owned
     `Outcome(PreparedBatchEntry)` so completed count-token API failures remain
     distinguishable from Zig errors. `PreparedBatchEntry` contains the owned
     key, one complete JSONL record without a trailing newline, and token count,
     and provides `deinit(allocator)`.
   - Introduce private context-taking preparation operations so public methods
     use quiet contexts and CLI Batch-file preparation retains its existing
     request/response traffic logging.
   - Reuse the shared `HttpStatusPolicy` and `OperationOutcome(T)` from Item 9.
     Public preparation uses `any_2xx`; CLI Batch-file preparation uses
     `ok_only`, prints the complete non-200 body, maps malformed successful
     countTokens responses to exit code 3, and preserves timeout diagnostics.
   - Implement preparation as an explicit two-phase internal workflow. Phase
     one converts and validates the typed generation or edit request, retains
     the exact owned generate-content JSON, and validates that request through
     `countTokens`. Phase two wraps those retained bytes with a caller-provided
     or CLI-generated key. Do not rebuild the request between validation and
     JSONL entry construction.
   - Keep automatic CLI key generation separate from public preparation.
     Automatic keys depend on the locked file offset and must be generated
     while the destination file is exclusively locked.
   - Refactor the CLI append path so it can generate the automatic key under
     lock, wrap the phase-one retained request bytes with internal helpers,
     preserve duplicate-key detection, and emit the existing receipt without
     exposing raw request JSON publicly. Count-token validation remains outside
     the file lock; key derivation, duplicate inspection, entry formatting, and
     append/rollback remain inside the lock.
   - Expose `validateBatchInput(bytes) !BatchInputSummary`, returning a
     non-owning summary with entry count and byte count. Preserve the existing
     structural validation: byte, line, entry-size, and entry-count limits
     without parsing JSON or revalidating the semantics of existing request
     objects.
   - Export `BatchValidationError` containing `EmptyBatchKey`,
     `EmptyBatchInput`, `InvalidBatchInput`, `BatchEntryTooLong`,
     `BatchTooManyEntries`, and `BatchInputTooLong`. Generation/edit request
     validation errors remain their existing named errors. Preparation rejects
     an empty explicit key before request allocation or network IO.
   - Export stable admission limits as `max_batch_entry_bytes`,
     `max_batch_entries`, and `max_batch_input_bytes`. Keep JSON builders,
     envelope composition, locking helpers, and output-download limits
     internal until their owning public workflows are introduced.
   - Add README and implementation-design examples for explicit-key
     preparation, ownership, validation summaries, and writing JSONL lines.

   **Compatibility:** Additive until package access to the old Batch helpers is
   removed by Item 13. CLI Batch-file output, generated keys, locking, and
   receipts remain unchanged.

   **Validation:** Test explicit-key ownership, context logging and response
   policy selection, public acceptance of all 2xx statuses, CLI rejection of
   non-200 statuses including other 2xx responses, complete count-token API
   failure bodies, malformed count-token success responses and CLI exit-code-3
   mapping, timeout diagnostics, byte-for-byte reuse of the validated
   generate-content JSON, exact JSONL shape, structural validation summaries
   without JSON parsing, generated keys under lock, all limits, duplicate
   handling, rollback after partial writes, and CLI receipts.

   **Complete when:** Public Batch preparation requires no raw Gemini JSON, and
   CLI automatic keys are still derived atomically from the locked file
   offset.

12. **Add typed remote Batch operations**

   **Depends on:** Items 9 and 11.

   **Result:** Consumers can manage remote Batch jobs without raw HTTP
   responses or public response decoders.

   **Proposed changes:**

   - Limit the supported remote Batch API to the existing file-backed
     workflows: upload input, create, get, list, cancel, and download a
     file-backed output. Inline requests/responses and Batch deletion are
     explicitly out of scope for this refactoring sequence.
   - Add `Client.uploadBatchInput`, `Client.createBatch`, `Client.getBatch`,
     `Client.cancelBatch`, `Client.listBatchesPage`, and
     `Client.downloadBatchOutputRecords`.
   - Keep upload and creation separate so callers retain the uploaded file name
     when non-idempotent creation fails or has an ambiguous transport outcome.
     Treat every transport error from `Client.createBatch` as ambiguous: do not
     retry automatically, and document that a remote job may have been created.
   - Define `BatchState` as a tagged union with `unspecified`, `pending`,
     `running`, `succeeded`, `failed`, `cancelled`, `expired`, and
     `unknown: []u8`. Normalize equivalent documented `JOB_STATE_*` and
     observed legacy `BATCH_STATE_*` spellings to known tags; own the original
     spelling only for `.unknown`. Do not invent `queued` or `cancelling`
     states that are absent from the current API contract.
   - Reuse `RemoteError` from Item 9. Define owned `BatchOperation` with
     canonical name, optional display name, `BatchState`, optional request
     count, optional canonical output file name, and optional `RemoteError`.
     Define `BatchListPage` as owned operations plus an optional continuation
     token. Every owning type provides `deinit(allocator)`. Get/list decoding
     may observe batches created elsewhere with inline output; represent those
     with no output file rather than exposing inline responses.
   - Define borrowed `BatchOutputRecordView` with a borrowed key and a tagged
     result containing either `*const GenerationResult` or
     `*const RemoteError`. The view and all nested data are valid only for the
     visitor call. Preserve duplicate keys; duplicate handling remains caller
     or CLI policy.
   - Define `BatchOutputVisitor` as an opaque caller context plus a callback
     with the conceptual signature
     `fn (*anyopaque, BatchOutputRecordView) anyerror!void`. Define
     `BatchOutputSummary` with total, successful, and failed record counts.
     Visitor errors propagate unchanged and stop processing.
   - Return typed outcomes consistently: uploads return `Outcome(File)`,
     create/get return `Outcome(BatchOperation)`, cancel returns
     `Outcome(void)`, listing returns `Outcome(BatchListPage)`, and
     `downloadBatchOutputRecords(output_file_name, visitor)` returns
     `Outcome(BatchOutputSummary)`. Download accepts the canonical output
     `files/...` name from `BatchOperation` and performs one HTTP request; it
     does not repeat the Batch status request.
   - Export the stable output admission limit as `max_batch_output_bytes`.
   - Reuse the shared internal status policy and stage-aware outcome. Public
     methods accept any 2xx status; internal CLI callers select HTTP 200.
   - Keep safe local filenames, duplicate-key handling, output file writing,
     raw JSON presentation, and all current CLI Batch commands unchanged.
     Extend the exact package allowlist and external-consumer compile tests for
     the additive API.
   - Keep the current bounded download transport: retain at most the complete
     `max_batch_output_bytes` JSONL body plus one decoded record and its images.
     Decode records sequentially, invoke the visitor, then release that
     record before continuing. The public strict path stops on malformed JSONL,
     malformed records, or image decoding errors; it never returns an eager
     aggregate of all records or decoded images.
   - Add README and implementation-design examples for upload, creation,
     status, cancellation, listing, download, record-view lifetimes, visitor
     errors, and ambiguous creation failures.

   **Compatibility:** Additive. The undocumented `nbimg.batch` path and all CLI
   Batch command behavior remain unchanged.

   **Validation:** Cover pagination, canonical names, both known wire prefixes
   for every applicable state, unknown-state preservation, absent file output
   for externally created inline batches, every successful 2xx cancellation
   body shape, output bounds, full-body-plus-one-record peak ownership,
   callback errors and partial cleanup, typed success and failure views,
   preserved remote failure details, malformed JSONL/records/images,
   duplicate-key preservation, no automatic retry after ambiguous creation
   failure, exact allowlists, and external-consumer compilation. Never run the
   billable submit/status live target without explicit authorization.

   **Complete when:** Package consumers can use every remote Batch workflow
   without raw response bodies, public wire decoders, internal line iterators,
   or presentation helpers, while the record-visitor download contract and
   existing CLI Batch paths remain explicit and unchanged.

13. **Migrate CLI Batch commands to typed operations**

   **Depends on:** Item 12.

   **Result:** CLI Batch commands and the public client share typed operation
   cores, allowing the legacy package-level `batch` export to be removed
   without changing current CLI presentation.

   **Proposed changes:**

   - Migrate Batch input upload, create, get/status, cancel, list, and download
     to the context-taking typed cores introduced by Item 12.
   - Preserve the CLI's exact HTTP policy, diagnostics, traffic logging,
     timeout reporting, ambiguous-creation warning, exit codes, and
     non-idempotent no-retry behavior through internal policy-bearing seams.
   - Keep an internal raw-response presentation path for `batch submit`,
     `status`, and `list` so their complete pretty-printed JSON remains
     byte-for-byte equivalent after formatting. Implement this as an internal
     success-body capture policy on the shared request/transport core: public
     methods decode typed results, while CLI presentation callers retain the
     complete bounded successful body. The raw result variant is not
     package-visible and does not require a second network request.
   - Keep safe output keys, duplicate-key handling, local filename generation,
     exclusive file writes, and presentation formatting in `src/cli.zig`.
     Add an internal tolerant record-visitor policy for Batch download so the
     CLI preserves its current behavior of continuing after malformed records,
     remote error records, duplicate keys, image decode failures, and
     individual file-write failures. The supported public visitor remains
     strict.
   - Remove `batch` from `src/root.zig` and the package allowlist after every
     CLI command uses the typed operation cores. Tighten the internal Batch and
     shared API allowlists.
   - Update README and implementation-design architecture text to distinguish
     the supported typed Batch API, internal raw presentation seam, and
     CLI-owned filesystem policy.

   **Compatibility:** Removes the undocumented `nbimg.batch` package path. CLI
   commands retain their existing output, diagnostics, and side effects.

   **Validation:** Add CLI parity tests for upload/create ambiguity, HTTP 200
   versus other 2xx responses, status and list raw JSON formatting,
   cancellation, pagination, download bounds, malformed/error/duplicate
   records, existing files, write failures, timeout diagnostics, and exit-code
   mapping. Run exact package/internal allowlists, external-consumer tests, all
   offline validation, and the ReleaseSafe build. Never run the billable,
   non-idempotent submit/status live target without explicit authorization.

   **Complete when:** Every CLI Batch command shares typed operation cores with
   the public client, raw JSON presentation remains internal, and
   `nbimg.batch` is no longer package-accessible.

14. **Remove the legacy shared API namespace**

   **Depends on:** Items 8, 10, and 13.

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

   **Validation:** Run package and internal allowlist tests, compile-only
   consumer tests, all offline validation commands, and the ReleaseSafe build.

   **Complete when:** No package-visible declaration exposes transport or
   Gemini wire implementation details.

15. **Audit public invariants and reduce internal seams**

   **Depends on:** Item 14.

   **Result:** Confirm the incrementally hardened public API and minimize
   remaining internal visibility.

   **Proposed changes:**

   - Audit that every public operation returns validation errors rather than
     asserting on caller input. Do not defer known public invariant work from
     Items 4 through 13 to this item.
   - Retain assertions only for internal programmer errors and paired
     trust-boundary invariants.
   - Verify that public domain enums expose no wire serialization or CLI
     parsing methods.
   - Verify that CLI name parsing, environment lookup, output naming, safe-key
     encoding, raw Batch JSON presentation, and filesystem effects are
     CLI-owned or internal-only.
   - Make cross-file declarations private where completed migrations removed
     their callers, and tighten internal module allowlists.

   **Compatibility:** Supported client APIs remain stable. Only internal seams
   and accidental visibility change.

   **Validation:** Run negative tests for every public validation rule and
   exact allowlist tests for every public container method and internal seam.

   **Complete when:** Every package declaration has a documented consumer use
   case and every remaining internal `pub` has a current cross-file caller.

16. **Finalize and document the stable package contract**

   **Depends on:** Items 1 through 15.

   **Result:** Declare the already usable client API stable and ensure all
   documentation and examples match it.

   **Proposed changes:**

   - Treat this as a documentation and contract-synchronization increment. Do
     not add, remove, or redesign supported operations after the invariant
     audit unless that audit finds a correctness defect.
   - Reduce the package allowlist to the exact `Client`, configuration,
     outcome, request/result, input/output MIME, enum, ownership, and
     documented-limit declarations.
   - Consolidate the incremental README examples added with Items 4 through 13
     into complete client initialization, ownership, API-failure handling,
     generation, edit, Files, Batch preparation, and remote Batch workflows.
   - Update `docs/IMPLEMENTATION_DESIGN.md` with the final façade and internal
     module boundaries.
   - Retain the historical pre-refactoring label on `public_api_analysis.md`
     and continue recording completed refactorings in this document.
   - Keep compile-only external-consumer examples synchronized with the
     supported named `nbimg` module.

   **Compatibility:** This item declares the replacement contract stable; it
   does not introduce the first usable documentation or remove additional
   supported declarations.

   **Validation:** Run formatting, all offline tests, the ReleaseSafe build,
   documentation path checks, package and internal allowlists, and
   compile-only consumer tests.

   **Complete when:** README examples, implementation documentation, exact
   allowlists, external-consumer tests, the build graph, and actual root
   exports describe the same supported API.

## Schema Baseline for Remaining Remote APIs

Items 9 through 13 use the current official
[Files API](https://ai.google.dev/api/files),
[Batch API reference](https://ai.google.dev/api/batch-api), and
[Batch guide](https://ai.google.dev/gemini-api/docs/batch-api) as their schema
baseline. Recheck these sources when starting each item because File metadata,
Batch operation wrappers, and state spellings are remote versioned behavior.
Schema drift may require additive unknown variants or decoder compatibility,
but must not silently expand the file-backed workflow scope selected above.

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
Batch submit/status target must run only with explicit user authorization.

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
- Typed generation and edit operations share context-taking internal cores
  with their eventual CLI migrations; public methods supply quiet contexts and
  CLI callers supply logging-enabled contexts.
- Public typed operations classify every completed 2xx response as successful;
  CLI migrations retain each command's current HTTP 200-only policy through
  internal response-policy seams.
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
  value before key generation; it never rebuilds the request between
  `countTokens` validation and JSONL wrapping.
- The first typed Batch download API eagerly owns the bounded raw JSONL during
  decoding and returns all decoded records and image bytes. Its documented
  peak memory can exceed `max_batch_output_bytes`; streaming is a separate
  future API.
- Transport failures from non-idempotent Batch creation are always reported as
  ambiguous and are never retried automatically.
- CLI behavior remains stable throughout the sequence unless a separate
  user-facing change is explicitly approved.
- The project remains Zig standard-library-only and retains a flat module
  layout unless a deliberate façade module is needed.
