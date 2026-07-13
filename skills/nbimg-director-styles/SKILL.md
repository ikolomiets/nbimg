---
name: nbimg-director-styles
description: Use when agent needs to transform one input prompt and image references into nbimg batch edit image sets across film-director visual aesthetics. Creates one same-language rewritten prompt per selected director, embeds role-scoped reference boundaries in the prompt, appends all requested outputs to one nbimg Batch JSONL file, submits it, polls status, and downloads results.
---

# Nbimg Director Styles

Create one `nbimg` Batch edit image set across the requested directors. Keep the user's subject and constraints intact while translating the scene through the visual relationships, atmosphere, and storytelling instincts described in each selected director profile.

## Required Inputs

Confirm:

- Base text prompt, or general instructions/ideas for the intended future scene.
- One or more local `.jpg`, `.jpeg`, `.png`, or `.webp` references, or canonical `files/ID,MIME` refs.
- Images per director.
- `--image-size`: `512`, `1K`, `2K`, or `4K`.
- Requested aspect ratio or framing, such as `16:9 landscape`, `1:1 square`, or `9:16 portrait`; embed this in every prompt instead of passing an `nbimg` aspect-ratio flag.
- Output directory for downloaded Batch results. Default to `images/`.

Default to all directors below unless the user selects a subset. Treat the first reference as `BASE_IMAGE`.
Infer every reference role from the user's stated intent and surrounding request. Ask only when two or more roles remain genuinely plausible and choosing one would materially change the permitted contribution. Never infer a role from visible reference attributes.

## Language Consistency

Write every rewritten prompt in the same language as the original base prompt. This applies to the scene rewrite, visual direction, reference boundaries, aesthetic context, and user-requested exclusions.

- Do not switch to English because profiles are written in English.
- Preserve intentional mixed-language user text.
- Follow the dominant source language when it is ambiguous.
- Keep established proper names and film titles in their conventional forms unless the user supplied localized forms.
- Latin-script identifiers may remain unchanged: `BASE_IMAGE`, ASCII `SCREAMING_SNAKE_CASE` labels, slugs, filenames, CLI/model names, and established camera or film-stock names.

## File Layout

For each director, create `<slug>.txt`. Prompt files contain only final prompt text: no Markdown fences, metadata, or commands. Do not overwrite prompts or delete outputs unless requested.

Prepare a single Batch JSONL file for all requested outputs. Default to `director-styles-batch.jsonl` unless the user specifies a path. Do not overwrite or append to an existing Batch JSONL file unless the user explicitly requests reuse; choose a new path instead.

Download successful Batch results into one existing output directory. Default to `images/`. `nbimg batch download` writes filenames as `{safe_key}-{candidate}-{part}.{extension}`, so use stable batch keys to keep outputs attributable to directors.

## Profile Loading

The supported-director index is authoritative and visible below without loading profiles. For prompt writing, read only each selected `references/directors/<slug>.md` profile. For an all-directors request, process profiles in manageable batches.

## Prompt Construction

Reformulate rather than append generic style words. Preserve the requested subject, action, setting, identity, relationships, and explicit constraints. Compose the rewritten scene from the user's text and the selected director profile before writing any reference boundary. Reference image must never affect prompt language.

First classify the user's text:

- **Source prompt provided:** If the user supplied text that is already intended to work as an image-generation prompt, reformulate that prompt through the selected director profile. Preserve as many original details, relationships, constraints, intentional nuances, and concrete visual facts as possible. Draw on the profile's broader visual logic rather than copying every example or forcing a fixed palette, lens, setting, or composition onto the scene. Do not summarize away source-prompt detail or dump irrelevant profile content. Source-prompt fidelity takes precedence when a director cue conflicts with an explicit user detail.
- **General instructions only:** If the user supplied only high-level instructions, goals, or ideas about the future scene, compose the full scene prompt from those instructions and the selected director profile before adding the required role boundaries.

When classification is ambiguous, treat detailed scene prose as a source prompt so its specifics are preserved.

Build each prompt in this semantic order, translated into the base prompt's language. Complete steps 1 through 4 without using reference-image content:

1. **Rewritten scene:** Describe the intended final image clearly.
2. **Aspect ratio:** State the requested aspect ratio or framing in natural language, preserving the exact ratio the user requested.
3. **Visual direction:** Interpret the profile through the scene's own subject, setting, period, and emotional purpose. For general instructions, derive a small set of mutually reinforcing visible choices. For a source prompt, use only the profile ideas that meaningfully deepen the supplied scene.
4. **Aesthetic context:** Name the director, summarize the relevant visual essence in fresh language, and list representative films only as analytical context.
5. **Reference boundaries:** Add only the symbolic label, assigned role, and role-scoped allowed contribution for `BASE_IMAGE` and every additional reference.

Do not include section headings if they make the prompt unnatural in its language. Keep the requirements explicit even when rendered as continuous prose.
Always put the requested aspect ratio in the prompt text. Never pass `--aspect-ratio` to `nbimg`; the Batch request should rely on prompt guidance for framing.

### Profile Interpretation

- Treat a profile as a visual worldview, not a checklist. Re-create how the director tends to organize attention, emotion, space, light, texture, and movement without reproducing a specific shot or set.
- Let the requested scene determine the practical palette, location, period, lens feeling, and composition. Adapt the profile's relationships to those facts instead of replacing them.
- Prefer a few coherent choices over a dense inventory of signature traits. A result should remain plausible for a wide range of subjects, including scenes unlike the director's best-known films.
- Translate temporal cinema techniques into still-image evidence when useful: layered movement, suspended gesture, static tension, environmental motion, spatial depth, or a decisive instant.
- Do not automatically add iconic props, costumes, characters, genres, or locations from representative works. Do not recreate a recognizable shot.
- Describe visible outcomes rather than production trivia. Mention exact equipment only when it materially clarifies an image characteristic.
- Keep prompts below the `nbimg` 16 KiB limit.

### Reference Content Firewall

Treat each reference as an opaque input whose assigned role grants one limited contribution. Do not inspect a reference to mine prompt details, exclusions, or descriptive language. Use visible content only as image input to the model, never as a source for the rewritten text.

Include a neutral boundary for every reference in every generated prompt. Express the following meaning in the source language:

```text
Use BASE_IMAGE only for [allowed role contribution]. The rewritten scene determines every other visual property.
```

For every additional reference, include only its symbolic label, assigned role, and allowed contribution:

```text
Use [LABEL] only as a [role] reference for [allowed role contribution]. The rewritten scene determines every other visual property.
```

Use these generic role contracts:

- `character`: recognizable identity.
- `scene`: scene structure and setting.
- `object`: the referenced object's recognizable identity.
- `style`: visual style.
- `pose`: pose.
- `composition`: composition.
- `background`: background.
- `texture`: texture.
- `image`: the general visual contribution explicitly assigned by the user. Use this broad role only when that contribution is intentional and can be stated without inspecting the reference; otherwise choose a more specific role or ask.

For a `character` reference, state only that it preserves recognizable identity, except for user-named opt-ins as described below. Never enumerate inferred facial features, age, hair, eyes, skin, clothing, pose, or any other visible property. Apply the same rule to every role: never describe, list, negate, or react to attributes found only in a reference. Do not turn an observation into an exclusion such as "do not inherit" or "do not copy."

Permit a reference attribute in prompt text only when the user explicitly names that attribute. Add each user-named property to that reference's allowed contribution inside the neutral boundary; mentioning it elsewhere in the scene is not sufficient. Preserve only the named property and only at the specificity supplied by the user. For example, a request to preserve the earrings may produce "Use BASE_IMAGE only for recognizable identity and the earrings," while a request to use the dress may add only "the dress"; neither request authorizes any neighboring reference detail.

Keep boundary wording invariant when a reference is replaced by a visually different image with the same role and the same explicit user request.

### Preflight Prompt Provenance Audit

Before saving each prompt, audit every detail. Each detail must originate from one of these sources:

- The user's text or an attribute the user explicitly named.
- The selected director profile.
- A newly invented part of the rewritten scene.
- A generic role contract, symbolic reference label, or assigned role.

Remove or rewrite any detail whose only source is inspecting reference pixels. Replacing a reference with a visually different image under the same role and user instructions must not change the boundary wording or introduce different prompt details.

Never pass `--preserve` or `--do-not` for reference handling. Keep reference guidance inside the prompt file and limit it to the neutral role boundaries above plus explicit user-named opt-ins.

## Reference Handling

Follow the `nbimg` skill contract.

1. Resolve references with `nbimg files list`, `get`, or `upload`.
2. Use canonical `files/ID,MIME` metadata.
3. Put the edit target first with no custom label.
4. Give later references clear ASCII `SCREAMING_SNAKE_CASE` labels when useful.
5. Track purpose, path, role, label, file ID, MIME type, and expiration.

Choose `scene`, `character`, `object`, `style`, `pose`, `composition`, `background`, `texture`, or `image` according to the contribution permitted by user intent. Assign the role before considering reference-image content.

For Batch execution, repeat the exact same resolved reference arguments on every appended entry: the same first base `ROLE=files/ID,MIME` reference, the same later `ROLE:LABEL=files/ID,MIME` references, and the same labels.

## nbimg Execution

Use `nbimg edit --batch-file` to append every requested director output to the same JSONL file. Always pass `--thinking-level high` on every append; do not omit it or substitute another thinking level. Pass the requested image size, prompt file, and the same resolved `--ref` list for every entry. Do not pass `--aspect-ratio`; aspect-ratio guidance must already be present in the prompt file. `--batch-file` and `--out-dir` are mutually exclusive.

```sh
nbimg edit \
  --batch-file director-styles-batch.jsonl \
  --batch-key david_lynch \
  --image-size 2K \
  --thinking-level high \
  --ref scene=files/base123,image/jpeg < david_lynch.txt
```

Use supported-director slugs as Batch-safe director names for keys. If one image per director is requested, use the slug directly, such as `david_lynch`. If multiple images per director are requested, create one Batch entry per requested image and suffix keys with 1-based indexes, such as `david_lynch-1`, `david_lynch-2`, and `david_lynch-3`.

Before appending, compute `selected_directors * images_per_director`. Stop if the total exceeds 100 entries; ask the user to reduce the count or split the work into separate batches. Batch keys must be unique within the JSONL file.

After all JSONL entries have been appended successfully, submit exactly one Batch job:

```sh
nbimg batch submit --path director-styles-batch.jsonl
```

Copy the returned canonical `batches/...` name. Poll status with that name every 30 seconds by default unless the user requested a different interval:

```sh
nbimg batch status --name batches/ID
```

Treat `JOB_STATE_SUCCEEDED` and `BATCH_STATE_SUCCEEDED` as success. Treat `JOB_STATE_FAILED`, `JOB_STATE_CANCELLED`, and `JOB_STATE_EXPIRED` as terminal blockers and inspect the status JSON before reporting. If the job is pending or running, wait for the polling interval and check again.

Create the output directory if needed, then download successful results:

```sh
mkdir -p images
nbimg batch download --name batches/ID --out-dir images
```

Never weaken or rewrite a prompt because append, submission, status, or download failed. Retry only the failed operation when it is safe and keeps the same prompt, references, flags including `--thinking-level high`, and batch key.

Stop on missing `GEMINI_API_KEY`, inaccessible references without a fix, invalid request shape, more than 100 Batch entries, denied approval, user interruption, failed/cancelled/expired Batch jobs, repeated non-retryable errors, download write conflicts, or HTTP `429 RESOURCE_EXHAUSTED`.

## Completion Report

Report prompt files, Batch JSONL path, batch keys, submitted `batches/...` name, polling interval, final Batch state, download directory, downloaded filenames, and exact blockers. Include any append receipts, failed records, retries, or skipped downloads needed to explain the result.

## Supported Directors

| Slug | Director | Short essence | Profile |
| --- | --- | --- | --- |
| `jean_luc_godard` | Jean-Luc Godard | Everyday immediacy interrupted by graphic, reflective cinematic ideas | `references/directors/jean_luc_godard.md` |
| `stanley_kubrick` | Stanley Kubrick | Human behavior measured against systems, ritual, and controlled space | `references/directors/stanley_kubrick.md` |
| `federico_fellini` | Federico Fellini | Private memory and desire expanding into affectionate public theater | `references/directors/federico_fellini.md` |
| `ingmar_bergman` | Ingmar Bergman | Faces and intimate spaces carrying existential and emotional pressure | `references/directors/ingmar_bergman.md` |
| `michelangelo_antonioni` | Michelangelo Antonioni | Emotional distance expressed through environment, absence, and modern life | `references/directors/michelangelo_antonioni.md` |
| `akira_kurosawa` | Akira Kurosawa | Moral and emotional force made physical through space and movement | `references/directors/akira_kurosawa.md` |
| `sergio_leone` | Sergio Leone | Mythic anticipation built from vast scale and decisive human detail | `references/directors/sergio_leone.md` |
| `andrei_tarkovsky` | Andrei Tarkovsky | Memory and spiritual longing made tangible through time-worn environments | `references/directors/andrei_tarkovsky.md` |
| `francis_ford_coppola` | Francis Ford Coppola | Operatic scale joined to intimate consequence and visual reinvention | `references/directors/francis_ford_coppola.md` |
| `martin_scorsese` | Martin Scorsese | Subjective energy, moral tension, and lived social worlds | `references/directors/martin_scorsese.md` |
| `steven_spielberg` | Steven Spielberg | Fluid visual discovery, emotional clarity, and human reaction to scale | `references/directors/steven_spielberg.md` |
| `brian_de_palma` | Brian De Palma | Suspense shaped through looking, divided attention, and cinematic artifice | `references/directors/brian_de_palma.md` |
| `terrence_malick` | Terrence Malick | Fleeting human experience held inside a larger living world | `references/directors/terrence_malick.md` |
| `ridley_scott` | Ridley Scott | Tactile, functional worlds carrying history, atmosphere, and scale | `references/directors/ridley_scott.md` |
| `david_lynch` | David Lynch | Familiar life opening into emotionally charged dream and uncertainty | `references/directors/david_lynch.md` |
| `david_cronenberg` | David Cronenberg | Identity and technology made physical through credible material unease | `references/directors/david_cronenberg.md` |
| `michael_mann` | Michael Mann | Procedural precision meeting romantic light, solitude, and sudden action | `references/directors/michael_mann.md` |
| `george_miller` | George Miller | Mythic visual storytelling through lucid movement and expressive scale | `references/directors/george_miller.md` |
| `peter_greenaway` | Peter Greenaway | Painterly systems of bodies, objects, pattern, sensuality, and decay | `references/directors/peter_greenaway.md` |
| `chantal_akerman` | Chantal Akerman | Everyday space and duration observed with directness and quiet intensity | `references/directors/chantal_akerman.md` |
| `abbas_kiarostami` | Abbas Kiarostami | Ordinary life and landscape revealing open-ended philosophical mystery | `references/directors/abbas_kiarostami.md` |
| `hou_hsiao_hsien` | Hou Hsiao-hsien | Intimate and historical life unfolding across layered, patient spaces | `references/directors/hou_hsiao_hsien.md` |
| `wong_kar_wai` | Wong Kar-wai | Intimacy and missed connection experienced as subjective time and place | `references/directors/wong_kar_wai.md` |
| `zhang_yimou` | Zhang Yimou | Private feeling magnified through color, landscape, ritual, and groups | `references/directors/zhang_yimou.md` |
| `hayao_miyazaki` | Hayao Miyazaki | Humane wonder grounded in ecology, labor, weather, and everyday life | `references/directors/hayao_miyazaki.md` |
| `dario_argento` | Dario Argento | Fear transformed into sensuous color, viewpoint, and spatial performance | `references/directors/dario_argento.md` |
| `john_woo` | John Woo | Emotional relationships expressed through clear, lyrical movement | `references/directors/john_woo.md` |
| `pedro_almodovar` | Pedro Almodóvar | Emotion externalized through color, décor, performance, and compassion | `references/directors/pedro_almodovar.md` |
| `spike_lee` | Spike Lee | Expressive viewpoint and color joining personal experience to public space | `references/directors/spike_lee.md` |
| `tim_burton` | Tim Burton | Outsider emotion embodied by handmade, theatrical visual worlds | `references/directors/tim_burton.md` |
| `jane_campion` | Jane Campion | Desire and power revealed through tactile bodies, objects, and place | `references/directors/jane_campion.md` |
| `bela_tarr` | Béla Tarr | Human endurance observed through patient space, weather, and material time | `references/directors/bela_tarr.md` |
| `quentin_tarantino` | Quentin Tarantino | Genre memory turned into confident staging, tension, and performance | `references/directors/quentin_tarantino.md` |
| `paul_thomas_anderson` | Paul Thomas Anderson | Restless characters moving through richly specific American worlds | `references/directors/paul_thomas_anderson.md` |
| `wes_anderson` | Wes Anderson | Crafted visual order containing unruly feeling and relationship | `references/directors/wes_anderson.md` |
| `bong_joon_ho` | Bong Joon-ho | Social power and tonal change made legible through physical space | `references/directors/bong_joon_ho.md` |
| `park_chan_wook` | Park Chan-wook | Desire and secrecy arranged through sensuous detail and visual rhyme | `references/directors/park_chan_wook.md` |
| `guillermo_del_toro` | Guillermo del Toro | Wounded beauty inhabiting tactile worlds of history and fantasy | `references/directors/guillermo_del_toro.md` |
| `christopher_nolan` | Christopher Nolan | Abstract ideas grounded in physical scale, structure, and consequence | `references/directors/christopher_nolan.md` |
| `alfonso_cuaron` | Alfonso Cuarón | Human vulnerability immersed in continuous, socially alive environments | `references/directors/alfonso_cuaron.md` |
