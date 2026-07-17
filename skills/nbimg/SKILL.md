---
name: nbimg
description: Operate the nbimg CLI for Gemini image generation, uploaded-reference editing, Files API management, Batch JSONL jobs, or request-shape debugging.
---

# nbimg CLI

Use `nbimg` directly from `PATH`. Follow this closed-loop runbook: select the
operation, load its reference, bound its effects, build the command, and verify
the requested result.

## 1. Select The Operation

Choose the smallest ordered sequence of leaf commands that can produce the
requested result. Load every reference named for that sequence before building
commands.

| Operation | Command | Required reference |
| --- | --- | --- |
| Generate an image | `nbimg gen` | Read [Advanced Parameters](references/advanced-parameters.md) when using sampling, seed, token/logprob, request-level, grounding, safety, or returned-thought controls. |
| Edit with uploaded images | `nbimg edit` | Read [Image References](references/advanced-image-references.md) for every edit. Also read [Advanced Parameters](references/advanced-parameters.md) when using its controls. |
| Manage uploaded references | `nbimg files upload/list/get/delete` | Read [Image References](references/advanced-image-references.md) when an upload or lookup will supply an edit reference. |
| Prepare or operate a Batch job | `gen/edit --batch-file` or `nbimg batch submit/status/cancel/download/list` | Read [Batch Operations](references/batch-operations.md) for every Batch workflow; also read [Image References](references/advanced-image-references.md) before Batch edits. |
| Inspect request shape or diagnose a failed reference | The affected leaf command with `--print-request`, or `files` lookup commands | Read [Debugging Patterns](references/debugging-patterns.md). |

Gate: every requested outcome maps to an ordered leaf-command sequence, and
every reference whose condition is true has been read.

## 2. Bound Inputs And Effects

- For live execution, supply a non-empty Gemini API key through
  `GEMINI_API_KEY` or command-level `--api-key KEY`. Prefer the environment
  variable because command-line keys can leak through shell history or process
  inspection.
- Match execution to the requested outcome: return a checked command for a
  command-construction task; run it when the task requests or requires live
  output, remote state, or downloaded files.
- Treat `gen` and `edit` as live model calls; `files upload/delete` and `batch
  submit/cancel` as remote mutations; `files list/get` and `batch status/list`
  as remote reads; and `batch download` as a remote read with local writes.
- Require explicit user request or authorization before `batch submit`: it is
  billable and non-idempotent, creates exactly one job, and leaves the uploaded
  JSONL in Gemini Files storage.
- Treat `--print-request` as diagnostic logging, not a dry run. The owning
  command still performs its normal network operation.
- For live execution, confirm every local input exists and every `--out-dir`
  names an existing directory. For command construction, mark unresolved
  runtime values as placeholders.

Gate: live commands have a ready API key, local inputs, and output
destinations; command-only results expose every placeholder; and every live
effect is within the requested scope.

## 3. Build The Command

Build commands only from these forms and the linked references. Treat syntax
that they do not cover as unsupported and surface that gap explicitly.

```sh
nbimg gen [OPTIONS] [--prompt "PROMPT"]
nbimg edit [OPTIONS] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
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

For `gen` and `edit`:

- Supply the prompt once with `--prompt "PROMPT"` or omit that flag and pipe a
  non-empty prompt of at most 16 KiB to stdin. Prompt text is never positional.
- Use `--out-dir DIR` for immediate output or `--batch-file PATH` for Batch
  preparation; they are mutually exclusive. Immediate output defaults to the
  current directory.
- Use `--aspect-ratio` with `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`,
  `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, or `21:9`.
- Use `--image-size` with `512`, `1K`, `2K`, or `4K`.
- Use `--thinking-level minimal|high` only when explicit thinking effort serves
  the task; omission uses Gemini's default.

Use stdin for long structured prompts:

```sh
nbimg gen --out-dir outputs < prompt.txt
```

`--api-key KEY` and `--print-request` are accepted after every leaf command.
Command results go to stdout. Sanitized request diagnostics, response traffic,
and whole-second response timing go to stderr. Generated image parts are saved
as files; text response parts remain only in response logs.

Gate: every leaf command matches one documented form; every `gen` or `edit`
prompt has exactly one source; all supplied flags satisfy the owning reference;
and every output destination already exists.

## 4. Close The Loop

Inspect the exit status and verify evidence for every requested operation:

- For command construction only, return the checked command and identify every
  placeholder or unresolved runtime input.
- For `gen` or `edit`, verify exit success and that every filename printed to
  stdout exists in the requested output directory or current directory.
- For `files upload/get`, verify the expected canonical `files/...` name and
  MIME type. For list, report the matching metadata or confirmed absence. For
  delete, require `OK`.
- For Batch preparation, verify the compact receipt and appended key. For
  submit/status/cancel/download/list, apply the command-specific evidence in
  Batch Operations; verify every downloaded filename on disk.
- On failure, preserve stderr diagnostics and use
  [Debugging Patterns](references/debugging-patterns.md). Report whether the
  operation failed before dispatch, during transport, or after a remote
  resource may have been created.

Done means every requested operation has verified evidence. State any command
that was not executed, remote state that was not confirmed, or artifact that
was not verified as an explicit gap.
