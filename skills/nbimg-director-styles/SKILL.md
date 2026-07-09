---
name: nbimg-director-styles
description: Use when agent needs to transform one input prompt and image references into nbimg batch edit image sets across film-director visual aesthetics. Creates one same-language rewritten prompt per selected director, embeds preservation and reference boundaries in the prompt, appends all requested outputs to one nbimg Batch JSONL file, submits it, polls status, and downloads results.
---

# Nbimg Director Styles

Create one `nbimg` Batch edit image set across the requested directors. Keep the user's subject and constraints intact while translating the scene through concrete visual principles from each selected director profile.

## Required Inputs

Confirm:

- Base text prompt, or general instructions/ideas for the intended future scene.
- One or more local `.jpg`, `.jpeg`, `.png`, or `.webp` references, or canonical `files/ID,MIME` refs.
- Images per director.
- `--image-size`: `512`, `1K`, `2K`, or `4K`.
- Requested aspect ratio or framing, such as `16:9 landscape`, `1:1 square`, or `9:16 portrait`; embed this in every prompt instead of passing an `nbimg` aspect-ratio flag.
- Output directory for downloaded Batch results. Default to `images/`.

Default to all directors below unless the user selects a subset. Treat the first reference as `BASE_IMAGE`.

## Language Consistency

Write every rewritten prompt in the same language as the original base prompt. This applies to the scene rewrite, visual direction, preservation rules, reference boundaries, aesthetic context, and exclusions.

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

Reformulate rather than append generic style words. Preserve the requested subject, action, setting, identity, relationships, and explicit constraints.

First classify the user's text:

- **Source prompt provided:** If the user supplied text that is already intended to work as an image-generation prompt, reformulate that prompt through the selected director profile. Preserve as many original details, relationships, constraints, intentional nuances, and concrete visual facts as possible. Include as much relevant, mutually compatible director-profile context as makes sense for creative interpretation and stylization across composition, perspective, lighting, palette, texture, production design, atmosphere, and visible motion treatment. Do not summarize away source-prompt detail, dump irrelevant profile content, or combine conflicting profile modes. Source-prompt fidelity takes precedence when a director cue conflicts with an explicit user detail.
- **General instructions only:** If the user supplied only high-level instructions, goals, or ideas about the future scene, compose the full scene prompt from those instructions and use the **Required In-Prompt Guidance** template below.

When classification is ambiguous, treat detailed scene prose as a source prompt so its specifics are preserved.

Build each prompt in this semantic order, translated into the base prompt's language:

1. **Rewritten scene:** Describe the intended final image clearly.
2. **Aspect ratio:** State the requested aspect ratio or framing in natural language, preserving the exact ratio the user requested.
3. **Visual direction:** For general instructions, select 4-6 compatible profile cues across composition, perspective, lighting, palette, texture, production design, atmosphere, and visible motion treatment. For a source prompt, include broader relevant compatible profile context when it meaningfully supports creative interpretation and stylization.
4. **Reference requirements:** State what must remain from `BASE_IMAGE` and what may be borrowed from every additional labeled reference.
5. **Aesthetic context:** Name the director, summarize the concrete visual principles, and list representative films only as analytical context.

Do not include section headings if they make the prompt unnatural in its language. Keep the requirements explicit even when rendered as continuous prose.
Always put the requested aspect ratio in the prompt text. Never pass `--aspect-ratio` to `nbimg`; the Batch request should rely on prompt guidance for framing.

### Cue Selection

- Describe visible outcomes, not production trivia. Use exact equipment only when it materially clarifies an image characteristic.
- Translate temporal cinema techniques into still-image evidence: directional blur, layered movement, suspended gesture, static tension, compressed depth, or a dynamic instant.
- Use one compatible mode when a profile offers alternatives. Do not combine conflicting lens, lighting, palette, period, or motion modes.
- When reformulating a source prompt, include every relevant compatible profile cue that strengthens the creative interpretation without diluting the source prompt.
- Keep prompts below the `nbimg` 16 KiB limit.

### Required In-Prompt Guidance

Use this template only when the user did not provide a source prompt and instead provided general instructions or ideas about the future scene. When reformulating a supplied source prompt, do not use this stock template; add only task-specific reference boundaries and necessary exclusions.

Express the following meaning in the source language and adapt it to the task:

```text
Preserve BASE_IMAGE's recognizable subject or identity, composition, camera angle, proportions, and core user-requested details unless the rewritten scene explicitly changes them.

Use CHARACTER_HERO only for the requested identity traits. Do not inherit its background, pose, clothing, lighting, framing, or unrelated details unless explicitly requested.

Use the visual principles associated with [Director]: [concise profile-derived summary]. Representative works for analytical context: [films].
```

Generate one boundary for every additional reference using its exact label and actual role. Cover identity, pose, clothing, object markings, background, lighting, composition, and styling when relevant.

Never pass `--preserve` or `--do-not`; all such guidance belongs in the prompt file.

## Reference Handling

Follow the `nbimg` skill contract.

1. Resolve references with `nbimg files list`, `get`, or `upload`.
2. Use canonical `files/ID,MIME` metadata.
3. Put the edit target first with no custom label.
4. Give later references clear ASCII `SCREAMING_SNAKE_CASE` labels when useful.
5. Track purpose, path, role, label, file ID, MIME type, and expiration.

Choose `scene`, `character`, `object`, `style`, `pose`, `composition`, `background`, `texture`, or `image` according to the reference's permitted contribution.

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
| `wes_anderson` | Wes Anderson | Frontal symmetry, storybook sets, coded pastels, deadpan tableaux | `references/directors/wes_anderson.md` |
| `stanley_kubrick` | Stanley Kubrick | One-point geometry, controlled light, oppressive spatial order | `references/directors/stanley_kubrick.md` |
| `david_lynch` | David Lynch | Uncanny Americana, liminal rooms, saturated symbols, noir dread | `references/directors/david_lynch.md` |
| `tim_burton` | Tim Burton | Crooked gothic silhouettes, macabre whimsy, theatrical fantasy | `references/directors/tim_burton.md` |
| `wong_kar_wai` | Wong Kar-wai | Neon intimacy, obstructed frames, smeared time, romantic longing | `references/directors/wong_kar_wai.md` |
| `quentin_tarantino` | Quentin Tarantino | Retro genre collage, graphic staging, pulp color and tension | `references/directors/quentin_tarantino.md` |
| `akira_kurosawa` | Akira Kurosawa | Elemental weather, motion in depth, dynamic group geometry | `references/directors/akira_kurosawa.md` |
| `federico_fellini` | Federico Fellini | Carnivalesque crowds, dream pageantry, theatrical excess | `references/directors/federico_fellini.md` |
| `ridley_scott` | Ridley Scott | Atmospheric world-building, tactile surfaces, monumental environments | `references/directors/ridley_scott.md` |
| `andrei_tarkovsky` | Andrei Tarkovsky | Organic elements, decayed spaces, contemplative spiritual time | `references/directors/andrei_tarkovsky.md` |
| `denis_villeneuve` | Denis Villeneuve | Austere scale, brutalist geometry, silhouettes and muted space | `references/directors/denis_villeneuve.md` |
| `christopher_nolan` | Christopher Nolan | Large-format clarity, practical scale, engineered visual momentum | `references/directors/christopher_nolan.md` |
| `guillermo_del_toro` | Guillermo del Toro | Tactile gothic fantasy, cyan-amber light, wounded beauty | `references/directors/guillermo_del_toro.md` |
| `park_chan_wook` | Park Chan-wook | Immaculate elegance, sensual surfaces, concealed violence | `references/directors/park_chan_wook.md` |
| `gaspar_noe` | Gaspar Noe | Neon disorientation, overhead geometry, bodily subjectivity | `references/directors/gaspar_noe.md` |
| `yorgos_lanthimos` | Yorgos Lanthimos | Wide-angle clinical absurdity, stiff ritualized blocking | `references/directors/yorgos_lanthimos.md` |
| `nicolas_winding_refn` | Nicolas Winding Refn | Neon-noir minimalism, glossy symmetry, ritualized menace | `references/directors/nicolas_winding_refn.md` |
| `sofia_coppola` | Sofia Coppola | Soft isolation, elegant interiors, pastel melancholy | `references/directors/sofia_coppola.md` |
| `terrence_malick` | Terrence Malick | Golden naturalism, drifting intimacy, spiritual landscapes | `references/directors/terrence_malick.md` |
| `pedro_almodovar` | Pedro Almodovar | Saturated melodrama, expressive decor, fashion-conscious color | `references/directors/pedro_almodovar.md` |
| `baz_luhrmann` | Baz Luhrmann | Maximalist spectacle, decorative excess, pop-operatic energy | `references/directors/baz_luhrmann.md` |
| `robert_eggers` | Robert Eggers | Period texture, ritual composition, archaic natural-light dread | `references/directors/robert_eggers.md` |
| `ari_aster` | Ari Aster | Controlled wide-frame anxiety, ritual space, daylight horror | `references/directors/ari_aster.md` |
| `bong_joon_ho` | Bong Joon-ho | Class-coded architecture, precise blocking, tonal collision | `references/directors/bong_joon_ho.md` |
| `michelangelo_antonioni` | Michelangelo Antonioni | Alienated architecture, negative space, industrial color | `references/directors/michelangelo_antonioni.md` |
| `ingmar_bergman` | Ingmar Bergman | Severe faces, spiritual chiaroscuro, ritual intimacy | `references/directors/ingmar_bergman.md` |
| `sergio_leone` | Sergio Leone | Extreme close-ups, vast landscapes, operatic standoff tension | `references/directors/sergio_leone.md` |
| `zhang_yimou` | Zhang Yimou | Ceremonial color blocks, painterly landscapes, choreographed spectacle | `references/directors/zhang_yimou.md` |
| `hayao_miyazaki` | Hayao Miyazaki | Lyrical skies, ecological wonder, layered hand-drawn worlds | `references/directors/hayao_miyazaki.md` |
| `john_woo` | John Woo | Balletic action, suspended debris, lyrical heroic melodrama | `references/directors/john_woo.md` |
| `bela_tarr` | Bela Tarr | Monochrome desolation, slow drift, mud, wind, duration | `references/directors/bela_tarr.md` |
| `jane_campion` | Jane Campion | Tactile landscapes, restrained desire, feminine subjectivity | `references/directors/jane_campion.md` |
| `dario_argento` | Dario Argento | Giallo primaries, baroque space, theatrical POV dread | `references/directors/dario_argento.md` |
