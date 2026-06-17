---
name: nbimg
description: Use when Codex needs to operate the nbimg CLI for Gemini image generation, image editing, uploaded Gemini Files API image reference management, Gemini Batch JSONL preparation/submission/status/cancel/download/list, or command construction involving nbimg gen, nbimg edit, nbimg files upload/list/get/delete, nbimg batch submit/status/cancel/download/list, --ref ROLE[:LABEL]=files/ID,MIME references, --batch-file workflows, generation controls, edit constraints, or output handling. Assumes the nbimg executable is available on PATH.
---

# nbimg CLI

Use `nbimg` directly from `PATH` for Gemini native image generation, image editing with uploaded file references, Gemini Files API image-reference management, and Gemini Batch API JSONL workflows.

## Preconditions

- Require a Gemini API key via `GEMINI_API_KEY` or command-level `--api-key KEY`; prefer the environment variable for routine use.
- Treat `gen`, `edit`, `files`, and `batch` commands as external API operations. Files upload/delete and Batch submit/cancel affect remote state; Files list/get and Batch status/list/download inspect remote state; generation/edit produce live model output; Batch submit creates one billable, non-idempotent job.
- Use only the `nbimg` CLI interface. Do not infer behavior from anything outside the CLI contract.

## Command Forms

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

`gen` creates new image output from text. `edit` edits a base uploaded image with optional additional uploaded references. `files` manages uploaded Gemini file resources used by `edit`. `batch` submits prepared JSONL, checks job state, requests cancellation, downloads successful image outputs, and lists recent jobs.

## Shared Behavior

- `--prompt "PROMPT"` is optional for `gen` and `edit`; if omitted, `nbimg` reads the prompt from stdin until EOF.
- Use stdin for long structured prompts:
  ```sh
  nbimg gen --out-dir outputs < prompt.txt
  ```
- Prompts must be non-empty and at most 16 KiB. Prompt text is not accepted as a positional argument.
- `--api-key KEY` is accepted after each leaf command or subcommand. Prefer `GEMINI_API_KEY` because command-line keys can leak through shell history or process inspection.
- `--print-request` logs sanitized request traffic for debugging. Response traffic is logged to stderr by default and includes whole-second response timing.
- Command results go to stdout: generated filenames, file metadata JSON, compact batch-file receipts, Batch operation/list JSON, downloaded Batch filenames, or `OK` for delete/cancel success.
- Generated image parts are written to the current directory unless `--out-dir DIR` is supplied. `--out-dir` is supported only for `gen`, `edit`, and `batch download`, must be used at most once, and must name an existing directory.
- Text response parts are not written as separate files; inspect stderr response logs when text metadata matters.

## Generation

Use `gen` for text-to-image requests.

```sh
nbimg gen \
  --aspect-ratio 16:9 \
  --image-size 2K \
  --out-dir outputs \
  --prompt "Create a crisp editorial product photo on a neutral studio background."
```

Use common image and thinking controls only when they serve the task. These flags are available on both `gen` and `edit`:

- `--aspect-ratio RATIO`: output shape. Values: `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`.
- `--image-size SIZE`: output resolution tier. Values: `512`, `1K`, `2K`, `4K`.
- `--thinking-level minimal|high`: request Gemini thinking effort. Omit it to use Gemini's default.

## Detailed Guides

- Read [Batch Operations](references/batch-operations.md) before using `--batch-file` or `nbimg batch submit/status/cancel/download/list`.
- Read [Advanced Parameters](references/advanced-parameters.md) before using sampling, seed, token/logprob, request-level, grounding, safety, or returned-thought controls.
- Read [Debugging Patterns](references/debugging-patterns.md) before validating command shape with `--print-request` or troubleshooting failed edit references.

## Files Workflow

Gemini Files is temporary storage for image references. Uploaded files are available only for a few days; use `expirationTime` from upload/list/get output to decide whether a reference must be re-uploaded. If `nbimg edit`, `files get`, or `files delete` returns HTTP 403 with `PERMISSION_DENIED` for a `files/ID`, treat it as a strong signal that the upload is inaccessible, commonly because it expired or was deleted. It can also mean the file belongs to a different API key/project. Check current uploads, then re-upload the local image and replace the stale `files/ID`.

Check existing uploads before adding a new one:

```sh
nbimg files list
nbimg files get --name files/abc123
```

If a matching current upload exists, reuse its `name` and `mimeType`. If it is missing or expired, upload the local image:

```sh
nbimg files upload --path refs/base-scene.jpg
nbimg files upload --path refs/hero-face.jpg
nbimg files upload --path refs/leather-bag.png
```

Supported upload extensions are `.jpg`, `.jpeg`, `.png`, and `.webp`. Upload files must be non-empty and no larger than 64 MiB. `--display-name` is optional; if omitted, the local file name is used as display metadata. Do not use `--display-name` just to label references; display names are metadata, not prompt labels.

Local filenames and bare IDs are not valid edit references. To build `--ref`, copy both metadata fields from upload/list/get output:

- `name`: canonical Gemini file name such as `files/abc123`
- `mimeType`: `image/jpeg`, `image/png`, or `image/webp`

Keep a small working table with semantic purpose, local path, `name`, `mimeType`, and `expirationTime`.

Delete stale uploads:

```sh
nbimg files delete --name files/abc123
```

## Editing

Use `edit` when at least one uploaded image is the base image to modify. The first `--ref` is always the edit target and is labeled `BASE_IMAGE` by `nbimg`; do not put a custom label on the first reference.

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --out-dir outputs \
  --prompt "Change BASE_IMAGE into a rainy evening scene while preserving the camera angle and subject placement."
```

Reference syntax:

```text
--ref ROLE[:LABEL]=files/ID,MIME
```

- `ROLE`: one primary semantic role for the image.
- `LABEL`: optional for later references only. Use ASCII `SCREAMING_SNAKE_CASE`, start with an uppercase letter, keep it unique, and do not use `BASE_IMAGE`.
- `files/ID`: canonical file `name` from upload/list/get metadata.
- `MIME`: `image/jpeg`, `image/png`, or `image/webp`.

Use roles for model-facing reference binding:

- `scene`: environment, composition, camera angle, framing, placement, lighting direction, scene geometry.
- `character`: identity, apparent age, face, hair, skin tone, body proportions, recognizable presence.
- `object`: product or prop geometry, proportions, material, color, texture, markings, logo/text placement.
- `style`: palette, contrast, lighting mood, line weight, surface texture, grain, rendering technique.
- `pose`: body position, gesture, posture.
- `composition`: layout, negative space, camera angle, framing, subject placement.
- `background`: setting and background details.
- `texture`: material feel, surface texture, pattern, finish.
- `image`: general visual details explicitly requested by the task.

Use the base role to tell `nbimg` what the edit target primarily represents:

```sh
nbimg edit \
  --ref character=files/portrait_base,image/jpeg \
  --preserve "BASE_IMAGE facial identity, apparent age, hairstyle, and body proportions" \
  --prompt "Change BASE_IMAGE clothing and background while keeping the same recognizable person."
```

Limits:

- Up to 14 total images including the base image.
- Up to 4 character references including a character base.
- Up to 10 object references including an object base.
- Up to 16 non-empty `--preserve` entries and 16 non-empty `--do-not` entries.

Prompts should refer to symbolic labels, not local filenames or upload display names. Later references may omit labels; `nbimg` assigns deterministic labels by role, such as `CHARACTER_A`, `OBJECT_A`, `STYLE_REFERENCE_A`, `SCENE_REFERENCE_A`, `POSE_REFERENCE_A`, `COMPOSITION_REFERENCE_A`, `BACKGROUND_REFERENCE_A`, `TEXTURE_REFERENCE_A`, or `IMAGE_REFERENCE_A`. Explicit labels are easier to read when multiple references are involved.

Use the preserve/change/do-not-copy pattern: say what stays from `BASE_IMAGE`, what is borrowed from each later reference, and what must not be copied.

```sh
nbimg edit \
  --ref scene=files/living_room_base,image/jpeg \
  --ref character:CHARACTER_HERO=files/hero_identity,image/jpeg \
  --ref object:OBJECT_DRESS=files/red_dress,image/png \
  --preserve "BASE_IMAGE composition, camera angle, room layout, and lighting direction" \
  --do-not "copy CHARACTER_HERO background, lighting, clothing, pose, or camera angle" \
  --do-not "copy OBJECT_DRESS mannequin, background, or product-photo lighting" \
  --out-dir outputs \
  --prompt "Edit BASE_IMAGE so the person in the scene has CHARACTER_HERO identity and wears OBJECT_DRESS. Match BASE_IMAGE perspective and lighting."
```

For character consistency, constrain references to identity traits unless the task explicitly wants clothing, pose, lighting, or background copied:

```sh
nbimg edit \
  --ref scene=files/group_base,image/jpeg \
  --ref character:CHARACTER_A=files/person_a,image/jpeg \
  --ref character:CHARACTER_B=files/person_b,image/jpeg \
  --preserve "BASE_IMAGE group composition, camera angle, lighting, and body placement" \
  --do-not "blend CHARACTER_A and CHARACTER_B facial features, hairstyles, clothing, or body proportions" \
  --prompt "Edit BASE_IMAGE so the left person has CHARACTER_A identity and the right person has CHARACTER_B identity."
```

For products or props, preserve exact object details and prevent unwanted context from leaking:

```sh
nbimg edit \
  --ref scene=files/desk_scene,image/jpeg \
  --ref object:OBJECT_SPEAKER=files/ceramic_speaker,image/png \
  --preserve "BASE_IMAGE desk, room, camera angle, light direction, and realistic perspective" \
  --do-not "copy OBJECT_SPEAKER background, tabletop, shadows, or surrounding props" \
  --prompt "Place OBJECT_SPEAKER on the desk in BASE_IMAGE. Preserve its geometry, material, color, texture, logo placement, proportions, and visible markings. Match scale, contact shadows, and lighting."
```

For style references, narrow the scope to palette, contrast, lighting mood, line weight, surface texture, grain, rendering technique, lens feel, or color grading:

```sh
nbimg edit \
  --ref scene=files/night_street_base,image/jpeg \
  --ref style:STYLE_CINEMA=files/cinema_reference,image/jpeg \
  --preserve "BASE_IMAGE street layout, subject placement, and camera angle" \
  --do-not "copy STYLE_CINEMA people, vehicles, location, or composition" \
  --prompt "Apply STYLE_CINEMA cinematic lighting, lens feel, film grain, contrast curve, and color grading to BASE_IMAGE."
```

Use `composition`, `pose`, `background`, `texture`, and `image` for references that are not identity, product, or style sources:

```sh
nbimg edit \
  --ref scene=files/portrait_base,image/jpeg \
  --ref background:BACKGROUND_CITY=files/city_background,image/webp \
  --ref image:IMAGE_BADGE=files/badge_reference,image/png \
  --preserve "BASE_IMAGE subject identity, pose, crop, and camera angle" \
  --do-not "copy BACKGROUND_CITY people, vehicles, foreground subjects, or unrelated objects" \
  --do-not "copy unrelated details from IMAGE_BADGE" \
  --prompt "Move BASE_IMAGE subject into BACKGROUND_CITY and add the badge design from IMAGE_BADGE to the jacket."
```

Bottom line: the model needs a clear base image, typed references, symbolic labels, and explicit boundaries. It does not need hidden reference metadata.
