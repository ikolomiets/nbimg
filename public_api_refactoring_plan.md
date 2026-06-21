# Public API Refactoring Plan

## Purpose

This document proposes a sequence of incremental refactorings based on
`public_api_analysis.md`. It does not implement or authorize those
refactorings.

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

   **Result:** Consumers can generate images through the public client and
   receive owned domain results instead of raw HTTP responses.

   **Proposed changes:**

   - Export `GenerationResult`, `GeneratedImage`, and the public output MIME
     enum. `GeneratedImage` contains candidate index, part index, output MIME,
     and owned bytes. `GenerationResult` contains an owned response ID, owned
     image slice, and optional reported service tier.
   - Provide allocator-based `deinit` methods on both owning types.
   - Add `Client.generate`, returning `Outcome(GenerationResult)` and reusing
     the request validation and domain-to-wire conversion introduced by Item
     4.
   - Decode successful responses internally, including the optional reported
     service tier. Return successful-response JSON, base64, missing-field,
     unsupported-part, and unsupported-MIME failures as Zig errors.
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

   **Validation:** Cover generated-image ownership and cleanup after partial
   decode failures, response IDs, candidate and part indexes, supported and
   unsupported MIME types, thought/text part handling, reported service tier,
   API failures, oversized bodies, malformed successful responses, exact
   allowlists, and external-consumer compilation. Run the non-billable live
   generation request-validity target only if request fields change.

   **Complete when:** A dependency consumer can generate images and count
   generation tokens through `Client` without raw JSON, `HttpResponse`, or
   implementation modules.

6. **Migrate immediate CLI generation to the typed core**

   **Depends on:** Item 5.

   **Result:** The immediate `nbimg gen` path and public client share one typed
   operation core, allowing the legacy package-level `gen` export to be
   removed.

   **Proposed changes:**

   - Add an internal typed generation entry point that accepts an explicit
     request context. Public client methods use a quiet context; the CLI uses
     its existing logging-enabled context.
   - Migrate only immediate CLI generation to the typed operation core.
     Preserve output files, exclusive writes, diagnostics, traffic logging,
     timeout reporting, the priority-tier downgrade warning, and exit codes.
   - Keep Batch-file generation on the existing raw request-building path
     until Item 9.
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

   **Validation:** Add CLI parity tests for typed success, API failure,
   malformed success, priority-tier downgrade, file writing, timeout
   diagnostics, and exit-code mapping. Run exact package/internal allowlists,
   the external-consumer compile test, all offline validation, and the
   ReleaseSafe build. Live validation is unnecessary unless request fields or
   transport behavior change.

   **Complete when:** Immediate CLI generation and `Client.generate` share the
   typed operation core, Batch preparation still works, and `nbimg.gen` is no
   longer package-accessible.

7. **Add typed edit operations**

   **Depends on:** Item 5.

   **Result:** Consumers can construct and submit edit requests through domain
   types rather than implementation modules.

   **Proposed changes:**

   - Export deliberate `EditRequest`, `UploadedImage`, `Reference`, and
     `ReferenceRole` types using the public generation option types.
   - Add `Client.edit` returning `Outcome(GenerationResult)` and
     `Client.countEditTokens` returning `Outcome(CountTokensResult)`. Reuse
     the public generation result and token-count types. Batch preparation
     remains deferred to Item 9.
   - Return errors for invalid prompts, file names, labels, reference counts,
     role-specific limits, constraints, and option combinations.
   - Keep CLI role-name parsing, Gemini prompt-manifest construction, File URI
     construction, and wire serialization private.
   - Migrate immediate CLI edit execution to the same typed operation core
     without changing output, diagnostics, traffic logging, or exit codes.
   - Remove `edit` from the package root after the replacement is in use and
     extend the external-consumer compile tests.
   - Add README and implementation-design examples for edit requests,
     ownership, validation errors, and API failures.

   **Compatibility:** The undocumented `nbimg.edit` path may be removed after
   all supported replacement types and operations exist.

   **Validation:** Cover every role, label and constraint rule, reference
   limits, public invariant, ownership path, API failure, malformed success
   response, and CLI parity. Run the non-billable live edit request-validity
   target when request construction changes.

   **Complete when:** Edit consumers and the immediate CLI edit path require no
   internal builders, validators, serializers, or transport responses.

8. **Add typed Files operations**

   **Depends on:** Item 4.

   **Result:** Consumers can upload, get, list, and delete Gemini files through
   typed methods.

   **Proposed changes:**

   - Export deliberate `FileUpload`, `File`, and `FileListPage` types with
     explicit allocator-based ownership methods.
   - Add `Client.uploadFile` and `Client.getFile` returning `Outcome(File)`,
     `Client.listFilesPage` returning `Outcome(FileListPage)`, and
     `Client.deleteFile` returning `Outcome(void)`.
   - Decode successful responses internally; successful delete discards the
     response body after validating the completed response.
   - Validate MIME, display name, resource name, page token, and upload size
     before network IO. Keep path-extension parsing in the CLI.
   - Keep pagination explicit; a convenience iterator remains a separate
     proposal.
   - Migrate CLI Files commands, remove `files` from the package root, and
     extend the external-consumer compile tests.
   - Add README and implementation-design examples for upload, get, explicit
     pagination, delete, ownership, and API failures.

   **Compatibility:** The undocumented `nbimg.files` path may be removed after
   the client methods replace it.

   **Validation:** Test successful and malformed response decoding, pagination,
   ownership, all input validation, API failures, oversized failure bodies,
   and CLI parity. Run affected Files live targets only when transport or
   request behavior changes.

   **Complete when:** Files consumers and CLI commands require no public
   response decoders or resumable-upload mechanics.

9. **Introduce deliberate Batch-input preparation**

   **Depends on:** Items 5 and 7.

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
   - Keep automatic CLI key generation separate from public preparation.
     Automatic keys depend on the locked file offset and must be generated
     while the destination file is exclusively locked.
   - Refactor the CLI append path so it can generate the automatic key under
     lock, format the entry with internal helpers, preserve duplicate-key
     detection, and emit the existing receipt without exposing raw request JSON
     publicly.
   - Expose `validateBatchInput(bytes) !BatchInputSummary`, returning a
     non-owning summary with entry count and byte count. Preserve the existing
     structural validation: byte, line, entry-size, and entry-count limits
     without revalidating the semantics of existing request objects.
   - Document only the entry-size, entry-count, and total-input limits callers
     need for admission. Keep JSON builders and envelope composition internal.
   - Add README and implementation-design examples for explicit-key
     preparation, ownership, validation summaries, and writing JSONL lines.

   **Compatibility:** Additive until the old Batch helpers are removed by
   Item 10. CLI Batch-file output, generated keys, locking, and receipts remain
   unchanged.

   **Validation:** Test explicit-key ownership, count-token API failures,
   malformed count-token success responses, exact JSONL shape, structural
   validation summaries, generated keys under lock, all limits, duplicate
   handling, rollback after partial writes, and CLI receipts.

   **Complete when:** Public Batch preparation requires no raw Gemini JSON, and
   CLI automatic keys are still derived atomically from the locked file
   offset.

10. **Add typed remote Batch operations**

   **Depends on:** Items 4, 8, and 9.

   **Result:** Consumers can manage remote Batch jobs without raw HTTP
   responses or public response decoders.

   **Proposed changes:**

   - Add `Client.uploadBatchInput`, `Client.createBatch`, `Client.getBatch`,
     `Client.cancelBatch`, `Client.listBatchesPage`, and
     `Client.downloadBatchOutput`.
   - Keep upload and creation separate so callers retain the uploaded file name
     when non-idempotent creation fails or has an ambiguous transport outcome.
     Treat every transport error from `Client.createBatch` as ambiguous: do not
     retry automatically, and document that a remote job may have been created.
   - Define `BatchState` as a tagged union with `queued`, `pending`, `running`,
     `succeeded`, `failed`, `cancelling`, `cancelled`, `expired`, and
     `unknown: []u8`. Normalize equivalent `JOB_STATE_*` and `BATCH_STATE_*`
     spellings to the known tags; own the original string only for `.unknown`.
   - Define owned `RemoteError` with optional integer code, required message,
     and optional compact JSON details. Define owned `BatchOperation` with
     canonical name, optional display name, `BatchState`, optional request
     count, optional output file name, and optional `RemoteError`. Define
     `BatchListPage` as owned operations plus optional continuation token.
     Define `BatchDownloadInfo` as owned output file name plus optional request
     count. Every owning type provides `deinit(allocator)`.
   - Define `BatchOutputRecord` with an owned key and a tagged result:
     `.success: GenerationResult` or `.failure: RemoteError`. Do not reduce a
     failed record to a missing response.
   - Return typed outcomes consistently: uploads return `Outcome(File)`,
     create/get return `Outcome(BatchOperation)`, cancel returns
     `Outcome(void)`, listing returns `Outcome(BatchListPage)`, and download
     returns `Outcome(BatchDownloadResult)`. `BatchDownloadResult` owns
     `BatchDownloadInfo` and a slice of decoded `BatchOutputRecord` values and
     provides `deinit(allocator)`.
   - Keep an internal raw-response path for CLI `batch submit`, `status`, and
     `list` presentation so their complete pretty-printed JSON remains
     unchanged. This path is not package-visible.
   - Keep safe local filenames, duplicate-key handling, output file writing,
     and presentation formatting in the CLI.
   - Migrate CLI Batch commands, remove `batch` from the package root, and
     extend the external-consumer compile tests.
   - Add README and implementation-design examples for upload, creation,
     status, cancellation, listing, download, typed output records, ownership,
     and ambiguous creation failures.

   **Compatibility:** The undocumented `nbimg.batch` path may be removed once
   the typed methods cover its supported workflows. CLI commands retain their
   current pretty-printed JSON output.

   **Validation:** Cover pagination, canonical names, both known wire prefixes
   for every applicable state, unknown-state preservation, bodyless successful
   cancellation, output bounds, typed success and failure records, preserved
   failure details, malformed records, duplicate keys, ownership, no automatic
   retry after ambiguous creation failure, internal raw-output parity, and CLI
   behavior. Never run the billable submit/status live target without explicit
   authorization.

   **Complete when:** Package consumers require no raw Batch response bodies,
   decoders, iterators, or presentation helpers, while the CLI retains its
   current raw JSON presentation through internal-only mechanics.

11. **Remove the legacy shared API namespace**

   **Depends on:** Items 4 through 10.

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

12. **Audit public invariants and reduce internal seams**

    **Depends on:** Item 11.

    **Result:** Confirm the incrementally hardened public API and minimize
    remaining internal visibility.

    **Proposed changes:**

    - Audit that every public operation returns validation errors rather than
      asserting on caller input. Do not defer known public invariant work from
      Items 4 through 10 to this item.
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

13. **Finalize and document the stable package contract**

    **Depends on:** Items 1 through 12.

    **Result:** Declare the already usable client API stable and ensure all
    documentation and examples match it.

    **Proposed changes:**

    - Reduce the package allowlist to the exact `Client`, configuration,
      outcome, request/result, enum, ownership, and documented-limit
      declarations.
    - Consolidate the incremental README examples added with Items 4 through 10
      into complete client initialization, ownership, API-failure handling,
      generation, edit, Files, Batch preparation, and remote Batch workflows.
    - Update `docs/IMPLEMENTATION_DESIGN.md` with the final façade and internal
      module boundaries.
    - Retain `public_api_analysis.md` as rationale and record completed
      refactorings in this document.
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
- Oversized API-failure bodies return `error.ResponseTooLong`; failures are not
  silently truncated.
- The supported package is importable through a named `nbimg` build module from
  the first public client increment onward.
- External-consumer tests import that named module through the build graph and
  do not bypass the package boundary with direct source-file imports.
- Batch JSONL prepared-entry values omit the trailing newline; callers or the
  CLI writer add record separators when persisting multiple entries.
- Transport failures from non-idempotent Batch creation are always reported as
  ambiguous and are never retried automatically.
- CLI behavior remains stable throughout the sequence unless a separate
  user-facing change is explicitly approved.
- The project remains Zig standard-library-only and retains a flat module
  layout unless a deliberate façade module is needed.
