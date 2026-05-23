# Repository Guidelines

## Project Structure & Module Organization

This is a minimal Zig 0.16.0 CLI for `nbimg`. Root build/configuration files live at the repository root, Zig source modules live under `src/`, and design documentation lives under `docs/`. Use `docs/Nano_Banana_CLI_Tool_Design.md` for broad direction, `docs/IMPLEMENTATION_DESIGN.md` for current behavior, and TigerStyle/Zig notes for style. Keep the project flat while small.

## Build, Test, and Development Commands

- `zig build`: build the ReleaseSafe `nbimg` executable into `zig-out/bin/nbimg`.
- `zig build run -- <args>`: compile and run a Debug executable through the build graph.
- `zig build test`: compile and run package and executable tests in Debug mode.
- `zig fmt --check build.zig src`: verify Zig formatting.
- `zig build test-live-api-generate-content-request-validity`: validate the `gen` request shape through Gemini `countTokens`.
- `zig build test-live-api-edit-request-validity`: validate the `edit` request shape through Gemini `countTokens`.
- `zig build test-live-api-files-upload-list`, `zig build test-live-api-files-get`, `zig build test-live-api-files-delete`: run targeted Gemini Files API live checks.
- `rg "term" README.md AGENTS.md build.zig docs src`: search project text quickly.

## Coding Style & Zig Practices

Use `zig fmt`, 4-space indentation, `snake_case`, and descriptive names. Follow `docs/TIGER_STYLE.md` and `docs/zig-programming-notes.md`: simple control flow, small scopes, bounded resources, explicit ownership, and safety before performance before developer experience.

Make dependencies visible. Pass `gpa`, `arena`, `scratch`, `io`, options, and time values explicitly; do not hide IO, clocks, randomness, environment lookup, or allocation behind globals. Pass allocators only to operations that can allocate.

At public boundaries, prefer complete signatures, explicit error sets when callers need stable cases, and `Options` structs for behavioral knobs. Reserve capacity before mutation; use `AssumeCapacity` only after capacity is proven. Use `defer`/`errdefer` intentionally, keep `comptime` small, and stay stdlib-only unless the design changes.

Use TigerStyle assertions consistently for programmer errors: preconditions, postconditions, invariants, and boundary assumptions. Expected operating errors still use Zig errors. Split compound assertions (`assert(a); assert(b);`), write implications as `if (a) assert(b);`, add compile-time assertions for constant/layout relationships, and pair important checks across boundaries such as request serialization and response parsing.

## Testing Guidelines

Add tests with each functional change, close to the module they exercise. Favor golden CLI-to-JSON tests, response fixtures, and snapshots for verbose output. Cover invalid states when assertions encode invariants. For randomized or stateful tests, record replay data such as seed and size. Always run `zig build test`.

Prefer offline tests first, then use live API tests as targeted agentic feedback for request JSON shape or endpoint behavior changes. Run only the relevant live API target or filtered test for the API request being changed, and use the result to confirm whether the actual Gemini API accepts the request. Avoid billable endpoints for routine live tests: before using a billable API path, look for workarounds such as `countTokens`, metadata endpoints, request validation endpoints, dry-run equivalents, or other non-generation probes. `generateContent` is billable and costs money to execute, so validate generation and edit request shapes through the dedicated `countTokens` live targets instead of content generation unless the user intentionally requests generated output. For Files API upload/list/get/delete changes, the dedicated live Files API targets are encouraged because they provide real service feedback without invoking content generation. Treat all live API calls as intentional external side effects: they require `GEMINI_API_KEY`, perform network IO, may create or delete remote files, and can fail due to quota or remote API behavior. If no non-billable workaround exists, document the gap and ask before running a billable live check.

## Commit & Pull Request Guidelines

Follow the existing history with short imperative subjects such as `Add image edit command`. For non-trivial or cross-cutting changes, include a descriptive commit body that explains why the change exists, important behavior/API/docs changes, and verification run. Pull requests should describe the reason, affected files, and manual verification.

## Agent-Specific Instructions

Keep changes scoped. Preserve the flat module layout unless the task requires a split. Update `docs/IMPLEMENTATION_DESIGN.md` with CLI behavior, API handling, output naming, or module-boundary changes. Update `README.md` when user-facing commands, flags, workflows, or testing instructions change. Avoid hidden effects, premature utility modules, unrelated prose rewrites, and undocumented tooling.
