---
name: nbimg-director-styles
description: Create same-language director-style image sets with nbimg Batch edits.
---

# Nbimg Director Styles

Run one translation pass across selected film-director aesthetics. Preserve the user's subject and constraints while adapting the scene through each director's visual relationships, atmosphere, and storytelling instincts.

## 1. Lock the request

Confirm these inputs:

- Base text prompt, or general instructions for the intended future scene.
- One or more local `.jpg`, `.jpeg`, `.png`, or `.webp` references, or canonical `files/ID,MIME` references.
- Images per director.
- Image size: `512`, `1K`, `2K`, or `4K`.
- Aspect ratio or framing, such as `16:9 landscape`, `1:1 square`, or `9:16 portrait`.
- Download directory. Default: `images/`.
- Batch JSONL path. Default: `director-styles-batch.jsonl`.

Default to all supported directors unless the user selects a subset. Treat the first reference as `BASE_IMAGE`. Ask only for required inputs that have no default.

This step is complete when every required input has a value and the two output paths are known.

## 2. Resolve directors

Read [`references/directors/index.md`](references/directors/index.md) before resolving any director name or slug. The index is authoritative for the supported set, exact slugs, short essences, and profile paths.

Resolve the requested directors to exact slugs, then read only their `references/directors/<slug>.md` profiles. For an all-directors request, load profiles in manageable groups. Compute `selected_directors * images_per_director`; stop and ask the user to reduce or split the work when the result exceeds the Batch limit of 100 entries.

This step is complete when every selected director has one supported slug and loaded profile, and the requested entry count is at most 100.

## 3. Resolve references behind a firewall

Before Files or Batch operations, read the sibling [`nbimg` contract](../nbimg/SKILL.md) and its [Batch Operations reference](../nbimg/references/batch-operations.md). Those files are the source of truth for generic CLI mechanics; the rules below are the director-pass constraints.

Resolve local or remote references with `nbimg files list`, `get`, or `upload`. Record each reference's purpose, path, role, label, canonical file ID, MIME type, and expiration. Put the edit target first without a custom label. Give later references clear ASCII `SCREAMING_SNAKE_CASE` labels when useful.

Assign each role from the user's stated intent before considering image content. If multiple roles remain genuinely plausible and the choice would materially change the permitted contribution, ask the user. Use the narrowest applicable contract:

| Role | Allowed contribution |
| --- | --- |
| `character` | Recognizable identity |
| `scene` | Scene structure and setting |
| `object` | The referenced object's recognizable identity |
| `style` | Visual style |
| `pose` | Pose |
| `composition` | Composition |
| `background` | Background |
| `texture` | Texture |
| `image` | The general visual contribution explicitly assigned by the user |

Use `image` only when its broad contribution is intentional and can be stated without inspecting the reference; otherwise use a specific role or ask.

The reference firewall makes pixels opaque during prompt writing. Reference images contribute to Gemini only as typed image inputs. Prompt language comes from the user, director profile, deliberate scene composition, and generic role contracts.

Repeat the exact same resolved `--ref` arguments on every Batch entry: the same first `ROLE=files/ID,MIME` reference and the same later `ROLE:LABEL=files/ID,MIME` references in the same order.

This step is complete when every reference has canonical metadata, one intent-derived role, a stable label where applicable, and an explicit allowed contribution; the first reference is the unlabeled `BASE_IMAGE` target.

## 4. Translate and preflight prompts

Classify the user's text before writing:

- **Source prompt:** Reformulate text already intended for image generation. Preserve its details, relationships, constraints, intentional nuances, and concrete visual facts. User-supplied facts take precedence over a conflicting profile cue.
- **General instructions:** Compose a complete scene from the user's goals and the selected profile.

Treat detailed scene prose as a source prompt when classification is ambiguous.

Write each prompt in the source text's language. Preserve intentional mixed-language text, established proper names, and conventional film titles unless the user supplied localized forms. Follow the dominant source language when ambiguous. Latin-script identifiers may remain unchanged, including `BASE_IMAGE`, ASCII labels, slugs, filenames, CLI/model names, and established camera or film-stock names.

Build each prompt in this semantic order, completing items 1 through 4 without reference-pixel content:

1. **Rewritten scene:** State the intended final image clearly.
2. **Aspect ratio:** Express the requested ratio or framing in natural language, preserving the exact ratio.
3. **Visual direction:** Translate the profile's worldview into a few mutually reinforcing visible choices suited to this subject, setting, period, and emotional purpose.
4. **Aesthetic context:** Name the director, summarize the relevant visual essence in fresh language, and list representative films only as analytical context.
5. **Reference boundaries:** State each symbolic label, assigned role, and role-scoped allowed contribution.

Use a profile as a visual worldview rather than a checklist. Let the requested scene determine palette, location, period, lens feeling, and composition. Translate cinema techniques into still-image evidence such as layered movement, suspended gesture, static tension, environmental motion, spatial depth, or a decisive instant. Favor visible outcomes and mention exact equipment only when it materially clarifies an image characteristic. The result must not recreate a recognizable shot or automatically import iconic props, costumes, characters, genres, or locations.

Add one neutral boundary per reference in the source language:

```text
Use BASE_IMAGE only for [allowed role contribution]. The rewritten scene determines every other visual property.
```

```text
Use [LABEL] only as a [role] reference for [allowed role contribution]. The rewritten scene determines every other visual property.
```

For `character`, the default contribution is only recognizable identity. A reference attribute enters prompt text only when the user explicitly names it; add that attribute to the corresponding boundary at exactly the user's specificity. Apply the same rule to every role. Boundary wording must remain invariant when a visually different reference replaces the original under the same role and user instructions.

Run a provenance preflight on every prompt. Every detail must originate from one of these sources:

- The user's text or an attribute the user explicitly named.
- The selected director profile.
- A deliberately invented part of the rewritten scene.
- A generic role contract, symbolic label, or assigned role.

Remove or rewrite details whose only source is reference pixels. Replacing a reference while preserving its role and user instructions must not change prompt wording or introduce different details.

Save each prompt as `<slug>.txt` containing only final prompt text, without Markdown fences, metadata, or commands. Continuous prose may omit section headings when headings would be unnatural in the source language. Keep every prompt non-empty and below the `nbimg` 16 KiB limit. Choose a new path rather than overwriting an existing prompt unless the user requested replacement.

Keep reference guidance inside the prompt boundaries. Do not pass `--preserve` or `--do-not`.

This step is complete when every selected director has one collision-safe prompt file in the source language, every required semantic element is present, every detail passes provenance preflight, every reference has one neutral boundary, and every prompt is below 16 KiB.

## 5. Prepare one Batch file

Use one collision-safe JSONL path for all requested outputs. Create the default `director-styles-batch.jsonl` when absent. When that path exists, choose a new path unless the user explicitly requested reuse; append to it only under that explicit instruction.

Append one entry per requested image with `nbimg edit --batch-file`. Always pass the requested image size, `--thinking-level high`, the same resolved reference list, and the corresponding prompt on stdin. `--batch-file` replaces `--out-dir` during preparation. The aspect ratio lives only in prompt text; do not pass `--aspect-ratio`.

```sh
nbimg edit \
  --batch-file director-styles-batch.jsonl \
  --batch-key david_lynch \
  --image-size 2K \
  --thinking-level high \
  --ref scene=files/base123,image/jpeg < david_lynch.txt
```

Use the director slug as the key for one image, such as `david_lynch`. For multiple images, suffix 1-based indexes, such as `david_lynch-1`, `david_lynch-2`, and `david_lynch-3`. Every key must be unique within the JSONL file.

This step is complete when each requested key has exactly one successful append receipt, all keys are unique, and the number of newly appended entries equals `selected_directors * images_per_director`.

## 6. Submit, poll, download, and report

After every append succeeds, submit exactly one Batch job:

```sh
nbimg batch submit --path director-styles-batch.jsonl
```

Copy the returned canonical `batches/...` name. Poll it every 30 seconds unless the user requested another interval:

```sh
nbimg batch status --name batches/ID
```

Interpret states according to the Batch Operations reference. Only `JOB_STATE_SUCCEEDED` or `BATCH_STATE_SUCCEEDED` permits download. Treat failed, cancelled, and expired states as terminal blockers and inspect the status JSON before reporting.

Create the download directory if needed, then download successful results:

```sh
mkdir -p images
nbimg batch download --name batches/ID --out-dir images
```

Retry only a failed operation when retrying is safe and preserves the prompt, references, flags, and Batch key. Operational failures never justify weakening or rewriting a prompt.

Stop and report the exact blocker for a missing API key, an inaccessible reference without a fix, invalid request shape, more than 100 entries, denied approval, user interruption, a failed/cancelled/expired job, repeated non-retryable errors, a download write conflict, or HTTP `429 RESOURCE_EXHAUSTED`.

The run is complete when the report names every prompt file, the Batch JSONL path, all Batch keys, the submitted `batches/...` name, polling interval, final state, download directory, downloaded filenames, append receipts, failed records, retries, skipped downloads, and exact blockers that apply.
