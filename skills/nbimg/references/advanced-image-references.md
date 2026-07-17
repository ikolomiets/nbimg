# Image References

Use this reference before every `nbimg edit` operation. It covers reference
setup for simple edits and the stronger boundaries needed for multiple
references, character consistency, product fidelity, style transfer, and
pose/composition/background/texture binding.

For failed references or request logging, also read [Debugging Patterns](debugging-patterns.md). For `--batch-file` validation and Batch JSONL workflows, also read [Batch Operations](batch-operations.md).

## Contents

- [Reference Setup](#reference-setup)
- [Roles And Labels](#roles-and-labels)
- [Boundary Pattern](#boundary-pattern)
- [Advanced Recipes](#advanced-recipes)
- [Checklist](#checklist)

## Reference Setup

Upload local images first. `nbimg edit` accepts Gemini Files names and MIME types, not local paths or bare IDs.

```sh
nbimg files upload --path refs/base-scene.jpg
nbimg files upload --path refs/hero-face.jpg
nbimg files upload --path refs/leather-bag.png
```

Copy both fields from upload/list/get output:

- `name`: canonical `files/ID`.
- `mimeType`: exactly `image/jpeg`, `image/png`, or `image/webp`.

The first `--ref` is always the edit target and is labeled `BASE_IMAGE` by `nbimg`; omit a custom label on that reference.

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --ref object:OBJECT_BAG=files/bag789,image/png \
  --prompt "Edit BASE_IMAGE so CHARACTER_HERO appears in the scene holding OBJECT_BAG."
```

Current limits:

- Up to 14 total images including the base image.
- Up to 4 character references including a character base.
- Up to 10 object references including an object base.
- Up to 16 `--preserve` entries and 16 `--do-not` entries.
- Each `--preserve` or `--do-not` value must be non-empty and at most 16 KiB.

## Roles And Labels

Use one primary role per image. The base role tells `nbimg` what the edit target primarily represents; later roles tell Gemini what to borrow from each reference.

- `scene`: environment, composition, camera angle, framing, placement, lighting direction, scene geometry.
- `character`: identity, apparent age, face, hair, skin tone, body proportions, recognizable presence.
- `object`: product or prop geometry, proportions, material, color, texture, markings, logo/text placement.
- `style`: palette, contrast, lighting mood, line weight, surface texture, grain, rendering technique.
- `pose`: body position, gesture, posture.
- `composition`: layout, negative space, camera angle, framing, subject placement.
- `background`: setting and background details, without foreground subject transfer.
- `texture`: material feel, surface texture, pattern, finish.
- `image`: general visual details explicitly requested by the task.

Prompts should refer to symbolic labels, not local filenames, upload display names, or first/second/third image positions.

Custom labels are optional on later references. Use unique ASCII `SCREAMING_SNAKE_CASE`, start with an uppercase ASCII letter, keep labels at most 64 bytes, and never use `BASE_IMAGE`.

If a later reference omits a label, `nbimg` assigns deterministic labels by role. Repeated unlabeled references advance by letter:

```sh
nbimg edit \
  --ref scene=files/gallery_base,image/jpeg \
  --ref style=files/watercolor_style,image/webp \
  --ref style=files/ink_style,image/png \
  --prompt "Blend STYLE_REFERENCE_A watercolor texture with STYLE_REFERENCE_B ink linework while preserving BASE_IMAGE layout."
```

Auto-label families include `SCENE_REFERENCE_A`, `CHARACTER_A`, `OBJECT_A`, `STYLE_REFERENCE_A`, `POSE_REFERENCE_A`, `COMPOSITION_REFERENCE_A`, `BACKGROUND_REFERENCE_A`, `TEXTURE_REFERENCE_A`, and `IMAGE_REFERENCE_A`.

## Boundary Pattern

For every complex edit, separate:

- What stays from `BASE_IMAGE`.
- What is borrowed from each later reference.
- What must not be copied from each later reference.

```sh
nbimg edit \
  --ref scene=files/living_room_base,image/jpeg \
  --ref character:CHARACTER_HERO=files/hero_identity,image/jpeg \
  --ref object:OBJECT_DRESS=files/red_dress,image/png \
  --preserve "BASE_IMAGE composition, camera angle, room layout, and lighting direction" \
  --do-not "copy CHARACTER_HERO background, lighting, clothing, pose, or camera angle" \
  --do-not "copy OBJECT_DRESS mannequin, background, or product-photo lighting" \
  --prompt "Edit BASE_IMAGE so the person in the scene has CHARACTER_HERO identity and wears OBJECT_DRESS. Match BASE_IMAGE perspective and lighting."
```

This prevents common leakage: copying a reference's background, importing the wrong pose or lighting, merging product details into a character, or treating style references as literal scene content.

## Advanced Recipes

### Character Identity

Constrain character references to identity traits unless clothing, pose, lighting, or background should also transfer.

```sh
nbimg edit \
  --ref scene=files/base_portrait,image/jpeg \
  --ref character:CHARACTER_NADINE=files/nadine_identity,image/jpeg \
  --preserve "BASE_IMAGE pose, crop, camera angle, lighting, and clothing silhouette" \
  --do-not "copy CHARACTER_NADINE background, lighting, clothing, pose, or camera angle" \
  --prompt "Replace the person in BASE_IMAGE with CHARACTER_NADINE while preserving the original scene and pose."
```

For multiple people, label each identity and keep them distinct:

```sh
nbimg edit \
  --ref scene=files/group_base,image/jpeg \
  --ref character:CHARACTER_A=files/person_a,image/jpeg \
  --ref character:CHARACTER_B=files/person_b,image/jpeg \
  --preserve "BASE_IMAGE group composition, camera angle, lighting, and body placement" \
  --do-not "blend CHARACTER_A and CHARACTER_B facial features, hairstyles, clothing, or body proportions" \
  --prompt "Edit BASE_IMAGE so the left person has CHARACTER_A identity and the right person has CHARACTER_B identity."
```

### Product Or Prop Fidelity

Preserve exact object details and block unwanted context from product photos.

```sh
nbimg edit \
  --ref scene=files/desk_scene,image/jpeg \
  --ref object:OBJECT_SPEAKER=files/ceramic_speaker,image/png \
  --preserve "BASE_IMAGE desk, room, camera angle, light direction, and realistic perspective" \
  --do-not "copy OBJECT_SPEAKER background, tabletop, shadows, or surrounding props" \
  --prompt "Place OBJECT_SPEAKER on the desk in BASE_IMAGE. Preserve its geometry, material, color, texture, logo placement, proportions, and visible markings. Match scale, contact shadows, and lighting."
```

For packaging or branded assets, put text fidelity in the prompt and block invented text:

```sh
nbimg edit \
  --ref scene=files/shelf_base,image/jpeg \
  --ref object:OBJECT_PACKAGE=files/package_front,image/png \
  --preserve "BASE_IMAGE shelf layout, camera angle, and lighting direction" \
  --do-not "invent additional brand names, slogans, symbols, or package text" \
  --prompt "Place OBJECT_PACKAGE on the shelf in BASE_IMAGE. Preserve all legible text from OBJECT_PACKAGE exactly where it appears on the package."
```

### Style Transfer

Use `style` only for palette, contrast, lighting mood, line weight, surface texture, grain, rendering technique, lens feel, or color grading. Exclude subject, layout, location, and objects.

```sh
nbimg edit \
  --ref scene=files/night_street_base,image/jpeg \
  --ref style:STYLE_CINEMA=files/cinema_reference,image/jpeg \
  --preserve "BASE_IMAGE street layout, subject placement, and camera angle" \
  --do-not "copy STYLE_CINEMA people, vehicles, location, or composition" \
  --prompt "Apply STYLE_CINEMA cinematic lighting, lens feel, film grain, contrast curve, and color grading to BASE_IMAGE."
```

### Composition, Pose, Background, Texture, And General Image Details

Use these roles when the source is not primarily an identity, product, or style source.

```sh
nbimg edit \
  --ref scene=files/product_base,image/jpeg \
  --ref composition:COMPOSITION_HERO=files/layout_reference,image/png \
  --preserve "BASE_IMAGE product identity, material, logo placement, and color" \
  --do-not "copy COMPOSITION_HERO people, objects, colors, or background details" \
  --prompt "Recompose BASE_IMAGE using COMPOSITION_HERO subject placement, negative space, camera angle, and framing."
```

```sh
nbimg edit \
  --ref character=files/dancer_base,image/jpeg \
  --ref pose:POSE_LEAP=files/leap_pose,image/jpeg \
  --preserve "BASE_IMAGE character identity, hairstyle, outfit, and lighting" \
  --do-not "copy POSE_LEAP identity, clothing, background, lighting, camera angle, or style" \
  --prompt "Adjust BASE_IMAGE so the character uses POSE_LEAP body position, gesture, and posture."
```

```sh
nbimg edit \
  --ref scene=files/studio_base,image/jpeg \
  --ref texture:TEXTURE_FABRIC=files/fabric_macro,image/png \
  --preserve "BASE_IMAGE subject placement, camera angle, and lighting direction" \
  --do-not "copy TEXTURE_FABRIC object shape, layout, lighting, or background" \
  --prompt "Apply TEXTURE_FABRIC material feel, surface texture, pattern, and finish to the sofa in BASE_IMAGE."
```

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

### Multi-Reference Edits

Keep the set small and use explicit labels when more than one role is involved.

```sh
nbimg edit \
  --out-dir outputs \
  --aspect-ratio 16:9 \
  --image-size 2K \
  --ref scene=files/apartment_base,image/jpeg \
  --ref character:CHARACTER_MODEL=files/model_identity,image/jpeg \
  --ref object:OBJECT_TOTE=files/canvas_tote,image/png \
  --ref style:STYLE_EDITORIAL=files/editorial_style,image/webp \
  --preserve "BASE_IMAGE apartment layout, camera angle, window placement, and light direction" \
  --do-not "copy CHARACTER_MODEL background, clothing, pose, lighting, or camera angle" \
  --do-not "copy OBJECT_TOTE background, tabletop, shadows, or surrounding props" \
  --do-not "copy STYLE_EDITORIAL subject, room layout, objects, or composition" \
  --prompt "Edit BASE_IMAGE so CHARACTER_MODEL stands near the window holding OBJECT_TOTE. Use STYLE_EDITORIAL only for color grading, contrast, grain, and lighting mood."
```

## Checklist

Before running `nbimg edit`, verify:

1. Every local image is uploaded and each `--ref` uses `files/ID,MIME` copied from upload/list/get metadata.
2. The first `--ref` is the intended edit target and has no custom label.
3. Later references use the most specific role and prompts use symbolic labels.
4. Reused uploads are still before `expirationTime`; otherwise re-upload and replace the `files/ID`.
5. `--preserve` captures what must stay from `BASE_IMAGE`.
6. `--do-not` blocks unwanted context from later references.
7. The request stays within image, character, object, preserve, and do-not limits.
8. Use `--batch-file` instead of `--out-dir` when preparing Batch JSONL and validating request shape through `countTokens`.
