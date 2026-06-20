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

   **Result:** Distinguish declarations supported for package consumers from
   declarations that are `pub` only so another source file can use them.

   **Proposed changes:**

   - Change `src/public_api_test.zig` to inspect the declarations reachable
     through `src/root.zig`.
   - Move the existing per-source-module allowlists into a separately named
     internal module API test.
   - Register both test roots in `build.zig`.
   - Initially preserve all existing allowlists and visibility. This
     refactoring changes classification and enforcement, not the API itself.
   - Update `docs/IMPLEMENTATION_DESIGN.md` to define the two kinds of tests.

   **Compatibility:** No source or CLI behavior changes.

   **Validation:** Run `zig fmt --check build.zig src`, `zig build test`, and
   `zig build`.

   **Complete when:** Package exports and internal cross-file declarations are
   guarded by separate exact allowlists with unambiguous names.

2. **Decouple executable assembly from the package contract**

   **Depends on:** Item 1.

   **Result:** The executable no longer requires `cli` to be exported through
   the package root.

   **Proposed changes:**

   - Change `src/main.zig` to import the CLI implementation directly.
   - Adjust the build graph so `main.zig` receives `build_options` and any
     required internal imports without importing the package façade.
   - Remove `cli` from `src/root.zig` and from the package-contract allowlist.
   - Keep `cli.run` public only if cross-file compilation still requires it;
     classify it as an internal seam.

   **Compatibility:** The undocumented `nbimg.cli` path is removed. CLI
   commands, output, diagnostics, and exit codes remain unchanged.

   **Validation:** Run all offline validation commands and focused CLI tests.

   **Complete when:** The executable builds and runs without any CLI
   implementation declaration being reachable through the package root.

3. **Replace mutable traffic logging state with explicit request context**

   **Result:** Network behavior no longer depends on
   `api.traffic_log_options`.

   **Proposed changes:**

   - Introduce an internal request context containing allocator, `std.Io`,
     borrowed API key, timeout, and traffic-log options.
   - Pass the context explicitly through command-domain and transport
     operations.
   - Remove the mutable `traffic_log_options` global.
   - Preserve current CLI defaults: response logging remains enabled and
     `--print-request` controls request logging.
   - Keep the current timeout value as the default while making it explicit in
     the context.

   **Compatibility:** Internal signatures change. CLI behavior and wire
   requests do not.

   **Validation:** Add tests proving independent contexts can select different
   logging options without shared state. Run offline validation; live tests
   are unnecessary unless transport behavior changes.

   **Complete when:** No request behavior reads or mutates process-global
   configuration.

4. **Introduce the public client and outcome foundation**

   **Depends on:** Item 3.

   **Result:** Establish the common shape used by all future supported library
   operations.

   **Proposed changes:**

   - Export a `Client` that contains explicit allocator, `std.Io`, borrowed
     API key, timeout, and traffic-log configuration.
   - Export `ClientOptions`, `TrafficLogOptions`, `Outcome(T)`, and
     `ApiFailure`.
   - Define `Outcome(T)` as a success value or an owned API failure containing
     HTTP status and a bounded response body.
   - Use Zig errors for allocation, IO, timeout, validation, and response
     decoding failures.
   - Add ownership methods for all public values that allocate.
   - Add package-contract tests for the exact new declarations and methods.

   **Compatibility:** This is additive. Existing implementation-module exports
   remain temporarily available.

   **Validation:** Test initialization, borrowed API-key lifetime assumptions,
   success/failure outcome ownership, deinitialization, and independent client
   configuration.

   **Complete when:** Later domain façades can use one stable client,
   configuration, failure, and ownership model.

5. **Add typed generation operations**

   **Depends on:** Item 4.

   **Result:** Consumers can generate images and count tokens without using
   raw JSON, transport functions, or `HttpResponse`.

   **Proposed changes:**

   - Introduce public generation request and option types separate from Gemini
     wire structures.
   - Represent stop sequences as borrowed slices rather than a public fixed
     array plus mutable count.
   - Add `Client.generate`, `Client.countGenerateTokens`, and a typed operation
     for preparing a generation request for Batch input.
   - Return owned generated files, response ID, and relevant response metadata.
   - Validate public inputs with returned errors rather than assertions.
   - Migrate the CLI generation path to the new operations without changing
     its output or file-writing policy.
   - Remove the `gen` module from the package root after the replacement is in
     use.

   **Compatibility:** The undocumented `nbimg.gen` path may be removed in this
   item. The new client API is its supported replacement.

   **Validation:** Cover every public generation option, invalid values,
   decoded image ownership, API failures, and CLI parity. Run the non-billable
   live generation request-validity target if request fields change.

   **Complete when:** Package consumers and the CLI do not require generation
   JSON builders, raw generation transports, or response decoders.

6. **Add typed edit operations**

   **Depends on:** Items 4 and 5.

   **Result:** Consumers can construct and submit edit requests through domain
   types rather than implementation modules.

   **Proposed changes:**

   - Export deliberate `EditRequest`, `UploadedImage`, `Reference`, and
     `ReferenceRole` types.
   - Add `Client.edit`, `Client.countEditTokens`, and a typed operation for
     preparing an edit request for Batch input.
   - Return errors for invalid prompts, file names, labels, reference counts,
     role-specific limits, and option combinations.
   - Keep CLI spellings such as role-name parsing in the CLI implementation.
   - Keep Gemini prompt-manifest and wire construction private.
   - Migrate the CLI edit path and remove the `edit` module from the package
     root.

   **Compatibility:** The undocumented `nbimg.edit` path may be removed after
   all supported replacement types and operations exist.

   **Validation:** Cover every role, label rules, reference limits, ownership,
   API failures, and CLI parity. Run the non-billable live edit
   request-validity target when request construction changes.

   **Complete when:** Edit consumers need no access to internal builders,
   validators, serializers, or transport responses.

7. **Add typed Files operations**

   **Depends on:** Item 4.

   **Result:** Consumers can upload, get, list, and delete Gemini files through
   typed methods.

   **Proposed changes:**

   - Export deliberate `FileUpload`, `File`, and `FileListPage` types with
     explicit ownership methods.
   - Add `Client.uploadFile`, `Client.getFile`, `Client.listFilesPage`, and
     `Client.deleteFile`.
   - Return typed outcomes and perform response decoding internally.
   - Validate MIME, display name, resource name, and upload size before network
     IO.
   - Keep pagination explicit initially; a convenience iterator can be a
     separate later proposal.
   - Migrate CLI Files commands and remove the `files` module from the package
     root.

   **Compatibility:** The undocumented `nbimg.files` path may be removed after
   the client methods replace it.

   **Validation:** Test successful and malformed response decoding, pagination,
   ownership, input validation, API failures, and CLI parity. Run affected
   Files live targets only when transport or request behavior changes.

   **Complete when:** Files response decoders and resumable upload mechanics
   are inaccessible through the package contract.

8. **Introduce a deliberate Batch-input preparation API**

   **Depends on:** Items 5 and 6.

   **Result:** Batch files can be prepared without exposing generate-content
   JSON or count-token envelopes.

   **Proposed changes:**

   - Add an owned `PreparedBatchEntry` containing its key, JSONL line, and
     token count.
   - Make generation and edit preparation operations produce this type after
     successful count-token validation.
   - Expose a local Batch-input validation operation that returns entry count
     and byte count.
   - Preserve current entry-size, entry-count, and total-input limits as
     documented public limits only where callers need them for admission.
   - Migrate CLI Batch-file append logic while preserving file locking,
     duplicate-key detection, deterministic generated keys, and receipts.
   - Keep all JSON builders and envelope composition internal.

   **Compatibility:** Additive until the old Batch helpers are removed by a
   later item.

   **Validation:** Test ownership, generated and explicit keys, exact JSONL
   shape, all limits, duplicate handling, locked append behavior, and CLI
   receipts.

   **Complete when:** Preparing Batch input never requires a consumer to build
   or manipulate Gemini request JSON.

9. **Add typed remote Batch operations**

   **Depends on:** Items 4, 7, and 8.

   **Result:** Consumers can manage remote Batch jobs without raw HTTP
   responses or public response decoders.

   **Proposed changes:**

   - Add `Client.uploadBatchInput`, `Client.createBatch`, `Client.getBatch`,
     `Client.cancelBatch`, `Client.listBatchesPage`, and
     `Client.downloadBatchOutput`.
   - Keep upload and creation as separate operations so a caller retains the
     uploaded file name if non-idempotent creation fails ambiguously.
   - Export typed `BatchOperation`, `BatchListPage`, and Batch-output record
     types with explicit ownership.
   - Represent successful and failed output records explicitly rather than
     encoding failure as a missing response string.
   - Keep raw operation JSON formatting, safe local filenames, and output file
     writing in the CLI.
   - Migrate CLI Batch commands and remove the `batch` module from the package
     root.

   **Compatibility:** The undocumented `nbimg.batch` path may be removed once
   the typed methods cover its supported workflows.

   **Validation:** Cover pagination, canonical names, status states,
   cancellation, output limits, malformed records, duplicate keys, ownership,
   ambiguous creation failure, and CLI parity. Never run the billable
   submit/status live target without explicit authorization.

   **Complete when:** Package consumers require no raw Batch response bodies,
   decoders, iterators, or presentation helpers.

10. **Remove the legacy shared API namespace**

    **Depends on:** Items 4 through 9.

    **Result:** `api.zig` remains an internal shared implementation module and
    is no longer part of the package contract.

    **Proposed changes:**

    - Verify that every supported option, request, result, MIME, limit, and
      ownership operation has a deliberate root-level replacement.
    - Remove `api` from `src/root.zig` and the package allowlist.
    - Remove package access to raw HTTP types, model selectors, resumable
      upload structures, wire shapes, JSON builders, response decoders,
      serializers, endpoint helpers, environment lookup, and generic HTTP
      functions.
    - Keep declarations `pub` internally only where cross-file access still
      requires it.

    **Compatibility:** This is the final removal of the undocumented
    `nbimg.api` path.

    **Validation:** Add compile-only consumer tests using only supported root
    declarations. Run all offline validation commands.

    **Complete when:** No package-visible declaration exposes transport or
    Gemini wire implementation details.

11. **Harden public invariants and reduce internal seams**

    **Depends on:** Item 10.

    **Result:** Public values cannot be silently placed into invalid states,
    and remaining internal visibility is minimal.

    **Proposed changes:**

    - Replace assertions reachable from public methods with validation errors
      or invariant-preserving constructors.
    - Retain assertions only for internal programmer errors and trust-boundary
      invariants.
    - Separate public domain enums from private wire enums so serialization
      methods are not public.
    - Move CLI name parsing, environment lookup, output naming, safe-key
      encoding, and JSON presentation into CLI-owned code.
    - Make cross-file declarations private when refactoring eliminates their
      external module callers.
    - Tighten the internal module allowlists after every reduction.

    **Compatibility:** Supported client APIs remain stable. Only internal
    seams and undocumented implementation access change.

    **Validation:** Add negative tests for every public validation rule and
    exact allowlist tests for every public container method.

    **Complete when:** Every remaining package declaration has a documented
    consumer use case and every remaining internal `pub` has a current
    cross-file caller.

12. **Finalize and document the stable package contract**

    **Depends on:** Items 1 through 11.

    **Result:** The supported library boundary is explicit, documented, and
    protected from accidental growth.

    **Proposed changes:**

    - Reduce the package allowlist to the exact `Client`, configuration,
      outcome, request/result, enum, ownership, and documented-limit
      declarations.
    - Add README examples for client initialization, ownership, API-failure
      handling, generation, edit, Files, and Batch workflows.
    - Update `docs/IMPLEMENTATION_DESIGN.md` with the final façade and internal
      module boundaries.
    - Retain `public_api_analysis.md` as rationale and record completed
      refactorings in this document.
    - Add compile-only external-consumer examples that import only
      `src/root.zig`.

    **Compatibility:** This item declares the replacement contract stable; it
    should not remove additional supported declarations.

    **Validation:** Run formatting, all offline tests, the ReleaseSafe build,
    documentation path checks, and compile-only consumer tests.

    **Complete when:** Documentation, exact allowlists, examples, and actual
    root exports describe the same supported API.

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
- Allocated success values and API-failure bodies use explicit allocator-based
  ownership.
- Non-success Gemini responses remain available to consumers through typed
  outcomes with HTTP status and a bounded owned body.
- CLI behavior remains stable throughout the sequence unless a separate
  user-facing change is explicitly approved.
- The project remains Zig standard-library-only and retains a flat module
  layout unless a deliberate façade module is needed.
