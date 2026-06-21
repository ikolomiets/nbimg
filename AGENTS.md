# Repository Guidelines

## Repository and Sources of Truth

`nbimg` is a small, stdlib-only Zig 0.16.0 CLI. Build configuration lives at
the repository root, source modules under `src/`, implementation and style
documentation under `docs/`, and the agent-facing CLI contract under
`skills/nbimg/`. Keep the module layout flat while the project remains small;
add dependencies or new layers only as deliberate design changes.

Use these sources in order:

- `build.zig` and `build.zig.zon` define the supported Zig version, build
  graph, and test steps.
- `docs/IMPLEMENTATION_DESIGN.md` describes current behavior, architecture,
  module ownership, and known gaps.
- `README.md` is the user-facing CLI and workflow reference.
- `docs/TIGER_STYLE.md` and `docs/zig-programming-notes.md` define coding
  practices.

## Architecture and Zig Practices

Keep command-specific parsing, validation, prompt construction, and response
handling in the owning command module. Before adding command-module code,
check sibling modules for an existing shared Gemini rule. Put genuinely
cross-command transport, wire, MIME, resource-name, or response mechanics in
`src/api.zig`; do not create speculative utility abstractions.

Declarations default to private. Same-file tests, possible future use, and
convenience aliases do not justify `pub`. Public concrete structs expose their
fields, so keep implementation state and wire-only types private. Treat every
change to the package root, a module's public declarations, or public container
methods as an interface change. Update the package allowlist in
`src/public_api_test.zig` or the internal seam allowlists in
`src/internal_module_api_test.zig`, as applicable.

Follow the repository style documents: use `zig fmt`, `snake_case`, small
scopes, bounded resources, explicit ownership, and simple control flow. Pass
allocators, IO, options, clocks, randomness, and environment data explicitly;
do not hide effects behind globals. Pass allocators only to operations that can
allocate. Reserve capacity before `AssumeCapacity`, use `defer` and `errdefer`
intentionally, and keep `comptime` small.

Use assertions for programmer errors, invariants, and boundary assumptions;
use Zig errors for expected operating failures. Split compound assertions,
write implications as `if (condition) assert(consequence);`, and pair important
checks across serialization/parsing or other trust boundaries.

## Change-Impact Checklist

Keep changes scoped and update only affected artifacts:

- Functional changes: add focused tests near the owning module.
- Package exports: update `src/public_api_test.zig`.
- Internal module declarations or methods: update
  `src/internal_module_api_test.zig`.
- User-visible commands, flags, output, or workflows: update `README.md`.
- Architecture, API behavior, output naming, module ownership, or known gaps:
  update `docs/IMPLEMENTATION_DESIGN.md`.
- CLI usage or operational contract: update the relevant files under
  `skills/nbimg/`.
- Build steps or validation workflows: update their documentation here and in
  the README testing section.

Avoid unrelated prose rewrites, hidden effects, premature modules, and
undocumented tooling.

## Build and Validation

- `zig build`: build the ReleaseSafe executable at `zig-out/bin/nbimg`.
- `zig build run -- <args>`: build and run the Debug executable.
- `zig build test`: run all offline tests in Debug mode.
- `zig fmt --check build.zig src`: verify formatting.

For Zig changes, always run `zig fmt --check build.zig src` and
`zig build test`. Add `zig build` when the installed executable or build graph
is affected. For documentation-only changes, run `git diff --check` and verify
all referenced paths and commands.

Available focused live API targets are:

- `zig build test-live-api-generate-content-request-validity`
- `zig build test-live-api-edit-request-validity`
- `zig build test-live-api-files-upload-list`
- `zig build test-live-api-files-get`
- `zig build test-live-api-files-delete`
- `zig build test-live-api-batch-list`
- `zig build test-live-api-batch-submit-status`

Prefer offline tests first. New or changed Gemini request fields must then be
validated with the relevant live target before being considered complete.
Live tests require `GEMINI_API_KEY`, network access, and explicit awareness of
their external effects:

- Generation request validation uses non-generation `countTokens`.
- Edit and Files targets may upload and delete remote files.
- Batch list is read-only and non-billable.
- Batch submit/status is billable, non-idempotent, and leaves remote
  resources; run it only when the user explicitly requests or authorizes it.

Do not call billable `generateContent` for routine validation. If no
non-billable validation exists, ask before running it. If live validation
cannot run, report the unvalidated gap instead of claiming completion.

## Commits and Pull Requests

Use imperative commit subjects that describe behavior, such as
`Add generation sampling controls`. Functional, user-facing, API-shape,
documentation, and cross-module commits need a body explaining why, the
important changes, and validation performed. A tiny mechanical commit may omit
the body when its subject is complete. Pull requests should state the reason
for the change and the affected areas.
