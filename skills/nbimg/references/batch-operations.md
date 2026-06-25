# Batch Operations

Use this reference before preparing JSONL with `gen --batch-file` or `edit --batch-file`, or before operating `nbimg batch submit/status/cancel/download/list`.

## Prepare Batch JSONL

Prepare JSONL with `gen --batch-file` or `edit --batch-file`, then submit it:

```sh
nbimg gen \
  --batch-file requests.jsonl \
  --batch-key hero-001 \
  --image-size 512 \
  --prompt "Create a clean product hero image."

nbimg batch submit --path requests.jsonl
```

`gen --batch-file` and `edit --batch-file` build the normal `GenerateContentRequest`, validate that shape through Gemini's non-generation `countTokens` endpoint, and append only after HTTP success. Each JSONL line has Batch API shape `{"key":"...","request":{...}}`.

The file is created when absent and locked while existing keys are checked. Explicit `--batch-key KEY` values must be unique within the JSONL file. If omitted, `nbimg` derives a deterministic key such as `nbimg-0` from the locked byte offset where the entry begins.

Each batch file is capped at 100 entries. `--batch-file` and `--out-dir` are mutually exclusive.

On append success, stdout receives a compact receipt:

```json
{"key":"hero-001","totalTokens":42,"batchFile":"requests.jsonl"}
```

`--print-request` remains independent and prints the `countTokens` validation request to stderr.

## Submit

```sh
nbimg batch submit --path requests.jsonl
```

`batch submit` performs local admission checks before network IO. The input must contain at least one non-empty JSONL entry, each entry is capped at 5 MiB, the complete local file is capped at 512 MiB, and one batch is capped at 100 entries.

Submit does not parse entry JSON, check keys, or validate nested request objects; malformed entries are left for Gemini to reject. Inputs over local limits are rejected before upload or job creation.

The command uploads the input through the Gemini Files API as `application/jsonl`, then creates exactly one job for `models/gemini-3.1-flash-image:batchGenerateContent`. By default, both the uploaded File and Batch job use the complete local basename, including the `.jsonl` extension, as `displayName`. `--display-name NAME` overrides both.

Job creation is non-idempotent and is never retried. If its transport fails after upload, `nbimg` reports the uploaded `files/...` name and warns that a job may already have been created. The uploaded JSONL remains in Gemini Files storage after submission.

Successful submission prints one pretty JSON Batch job object serialized from typed fields. Copy the returned canonical `batches/...` name for status, cancel, or download commands. The object always includes `name`; optional typed fields include `model`, `displayName`, `inputConfig.fileName`, `output.responsesFile`, timestamps, `state`, `batchStats`, `priority`, `done`, and `error`. Unknown raw API fields are not preserved.

## Status

```sh
nbimg batch status --name batches/123456789
```

`batch status` performs one GET without polling or retries and prints the same typed Batch job JSON shape as `batch submit`.

To determine completion, inspect the returned `state` field. Known states render as `BATCH_STATE_*`; unknown state strings are preserved.

Treat these states as terminal:

| State | Meaning | Next step |
| --- | --- | --- |
| `BATCH_STATE_SUCCEEDED` | Completed successfully; results are available. | Run `nbimg batch download --name batches/ID [--out-dir DIR]`. |
| `BATCH_STATE_FAILED` | The Batch job failed. | Inspect the status JSON `error` field. |
| `BATCH_STATE_CANCELLED` | The Batch job was cancelled by the user. | Do not expect output results. |
| `BATCH_STATE_EXPIRED` | The job expired after waiting or running too long. | Resubmit, usually with fewer or smaller requests. |

Treat these states as unfinished:

| State | Meaning |
| --- | --- |
| `BATCH_STATE_PENDING` | The job has been created and is waiting for service processing. |
| `BATCH_STATE_RUNNING` | The job is currently processing. |

If a response includes `done:false`, the job is not complete. Do not use `done:true` alone as a success signal; use the `state` value and require `BATCH_STATE_SUCCEEDED` before downloading. `batch download` performs this status check once and refuses to proceed unless the typed status is succeeded.

## Cancel

```sh
nbimg batch cancel --name batches/123456789
```

`batch cancel` performs one bodyless POST without polling or retries and prints `OK` when Gemini accepts the request. Acceptance does not guarantee the job has already reached `BATCH_STATE_CANCELLED`; use `batch status` to inspect current state.

Cancellation does not delete the Batch job or its uploaded JSONL input.

## Download

```sh
nbimg batch download \
  --name batches/123456789 \
  --out-dir outputs
```

`batch download` checks status exactly once and proceeds only for a succeeded job. It rejects a reported `batchStats.requestCount` over 100, downloads the output JSONL with a separate 512 MiB limit, and independently enforces at most 100 output records.

A known oversized `Content-Length` is rejected before body allocation. Unknown lengths grow incrementally and accept exactly 512 MiB.

The complete JSONL stays in memory while records are decoded one at a time. Successful inline images are written to the current directory by default or to an existing `--out-dir`. A missing output directory is reported clearly.

Output filenames use `{safe_key}-{candidate}-{part}.{extension}`. Writes are exclusive and never overwrite existing files. Every successfully written filename is printed to stdout.

Remote-error records and duplicate keys are valid records; they are reported by key while later records continue processing. Existing target files are reported with their destination paths and left untouched. File write failures are recorded for their key and processing continues. Malformed output JSONL, malformed remote errors, or malformed generated images stop the command with exit code 3. Any remote-error record, duplicate key, existing file, or file write failure makes the completed command exit nonzero.

## List

```sh
nbimg batch list
```

`batch list` requests 100 operations per page, follows every returned `nextPageToken`, and prints one pretty JSON object containing the aggregated `batches` array.

Each job must have a canonical `batches/...` name and uses the same typed field serialization as `batch status`; unknown raw API fields are not preserved. Gemini does not return deleted jobs from recent-job history. The API's undocumented `filter` parameter is intentionally not exposed.
