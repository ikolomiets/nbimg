---
name: nbimg
description: Use when Codex needs to operate the nbimg CLI for Gemini image generation, image editing, uploaded Gemini Files API image reference management, or command construction involving nbimg gen, nbimg edit, nbimg files upload/list/get/delete, --ref ROLE[:LABEL]=files/ID,MIME references, generation controls, edit constraints, or output handling. Assumes the nbimg executable is available on PATH.
---

# nbimg CLI

Use `nbimg` directly from `PATH` for Gemini native image generation, image editing with uploaded file references, and Gemini Files API image-reference management.

## Preconditions

- Require `GEMINI_API_KEY` in the environment before live API calls.
- Treat `gen`, `edit`, and `files` commands as external API operations. Upload/list/get/delete affect remote Gemini Files API state; generation/edit produce live model output.
- Use only the `nbimg` CLI interface. Do not infer behavior from anything outside the CLI contract.

## Command Forms

```sh
nbimg gen [OPTIONS] [--prompt "PROMPT"]
nbimg edit [OPTIONS] --ref ROLE=files/ID,MIME [--ref ROLE[:LABEL]=files/ID,MIME] [--preserve TEXT] [--do-not TEXT] [--prompt "PROMPT"]
nbimg files upload [--print-request] [--display-name NAME] --path PATH
nbimg files list [--print-request]
nbimg files get [--print-request] --name files/ID
nbimg files delete [--print-request] --name files/ID
```

`gen` creates new image output from text. `edit` edits a base uploaded image with optional additional uploaded references. `files` manages uploaded Gemini file resources used by `edit`.

## Shared Behavior

- `--prompt "PROMPT"` is optional for `gen` and `edit`; if omitted, `nbimg` reads the prompt from stdin until EOF.
- Use stdin for long structured prompts:
  ```sh
  nbimg gen --out-dir outputs < prompt.txt
  ```
- Prompts must be non-empty and at most 16 KiB. Prompt text is not accepted as a positional argument.
- `--print-request` logs sanitized request traffic for debugging. Response traffic is logged to stderr by default.
- Command results go to stdout: generated filenames, file metadata JSON, or delete `OK`.
- Generated image parts are written to the current directory unless `--out-dir DIR` is supplied. `--out-dir` is supported only for `gen` and `edit`, must be used at most once, and must name an existing directory.
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

Use generation controls only when they serve the task:

- `--aspect-ratio RATIO`: output shape. Values: `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`, `5:4`, `8:1`, `9:16`, `16:9`, `21:9`.
- `--image-size SIZE`: output resolution tier. Values: `512`, `1K`, `2K`, `4K`.
- `--temperature FLOAT`: sampling variation, `0.0` to `2.0`.
- `--top-p FLOAT`: nucleus sampling, `0.0` to `1.0`.
- `--seed INT`: signed 32-bit decimal seed for best-effort reproducibility.
- `--max-output-tokens INT`: response token budget, `1` to `32768`; not an image-resolution control.
- `--presence-penalty FLOAT`: `-2.0` up to but not including `2.0`.
- `--frequency-penalty FLOAT`: `-2.0` up to but not including `2.0`.
- `--stop TEXT`: repeatable literal stop sequence; up to 5 non-empty unique values.
- `--response-logprobs`: request chosen-token log probability diagnostics.
- `--logprobs INT`: request top-token alternatives, `1` to `20`; requires `--response-logprobs`.

## Files Workflow

Gemini Files is temporary storage for image references. Uploaded files are available only for a few days; use `expirationTime` from upload/list/get output to decide whether a reference must be re-uploaded. If `nbimg edit` refers to a file that no longer exists, the Gemini Image API may report it as a `"permission denied"` error.

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

## Grounding, Thinking, Safety, and Request Controls

These flags are available on both `gen` and `edit`.

Grounding:

- `--grounding none`: no search grounding.
- `--grounding web`: use Google Search grounding for current factual context.
- `--grounding image`: use Image Search grounding for visual context; do not use it to search for people.
- `--grounding web,image`: use both web and image grounding.

Thinking:

- `--thinking-level minimal|high`: request Gemini thinking effort.
- `--include-thoughts`: request returned thought parts; they remain in response logs and are not written as separate sidecar files.

Safety:

- `--safety none|off|permissive|balanced|strict`: send one safety threshold across supported safety categories.
- Omit `--safety` to leave request-level safety settings unset.

Request-level controls:

- `--system TEXT`: text-only system instruction.
- `--cached-content cachedContents/ID`: attach existing cached content; raw IDs are invalid.
- `--service-tier flex|standard|priority`: request a Gemini service tier. A `priority` request may still report `standard` in the response, in which case `nbimg` warns but continues.
- `--store`: send `store:true`.
- `--no-store`: send `store:false`.
- Omit both `--store` and `--no-store` to use the service's default logging behavior.

## Debugging Pattern

Use `--print-request` when validating command shape before relying on output:

```sh
nbimg edit \
  --print-request \
  --ref scene=files/base123,image/jpeg \
  --ref object:OBJECT_BAG=files/bag789,image/png \
  --preserve "BASE_IMAGE composition and camera angle" \
  --do-not "copy OBJECT_BAG background or product-photo lighting" \
  --prompt "Place OBJECT_BAG on the chair in BASE_IMAGE."
```

Check stdout for command results and stderr for request/response diagnostics. If an edit reference fails, first verify:

- The reference uses canonical `files/ID` form, not a local path or bare ID.
- The MIME is exactly `image/jpeg`, `image/png`, or `image/webp`.
- The file still exists in Gemini Files API storage; expired or deleted files may trigger a Gemini Image API `"permission denied"` error.
- The first `--ref` has no custom label.
- Custom labels start with an ASCII uppercase letter and contain only ASCII uppercase letters, digits, and underscores.
- Role and label are not swapped; use `pose:POSE_MAIN=files/a,image/jpeg`, not `POSE_MAIN=files/a,image/jpeg`.

Common mistakes to avoid:

- Passing local paths to `edit`; upload first, then use `--ref scene=files/ID,image/jpeg`.
- Using `--display-name` as a prompt label; label references with `--ref role:LABEL=...`.
- Referring to first/second/third image; use `BASE_IMAGE`, auto-labels such as `CHARACTER_A`, or explicit labels.
- Labeling the first reference; it is always `BASE_IMAGE`.
- Not saying what to ignore; add repeatable `--do-not` boundaries.
- Mixing style and content; use `style` references only for style qualities and exclude subject/layout.
- Using too many unrelated references; keep only references that contribute to the output.
- Vague object constraints; preserve geometry, material, logo/text placement, markings, and scale.
