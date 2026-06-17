# Best practices for using image references with `nbimg edit`

`nbimg edit` is currently wired to the fixed `gemini-3.1-flash-image` model,
called `nano2` internally. Treat image references as explicit edit inputs
managed by `nbimg`: upload local image files with `nbimg files upload`, copy
each uploaded file's canonical `name` and `mimeType` from the returned
metadata, then pass those values to `nbimg edit` with typed `--ref` flags.

The first `--ref` is always the image to edit and is labeled `BASE_IMAGE` by
`nbimg`. Later references can be labeled explicitly, such as
`CHARACTER_HERO`, `OBJECT_BAG`, or `STYLE_POSTER`, and the final prompt should
refer to those symbolic labels instead of local filenames.

The current implementation enforces 14 total edit images including the base
image, up to 4 character references including a character base, and up to 10
object references including an object base.

---

## 1. Upload references first

Upload each local image once, then use the uploaded metadata for edit commands.
Do not pass local paths directly to `nbimg edit`.

```sh
nbimg files upload --path refs/base-scene.jpg
nbimg files upload --path refs/hero-face.jpg
nbimg files upload --path refs/leather-bag.png
nbimg files upload --path refs/poster-style.webp
```

These examples intentionally omit `--display-name`; when it is omitted, the
uploaded file metadata keeps the original local filename as the display name.

If you did not keep the upload output, list uploaded files or fetch a known
file:

```sh
nbimg files list
nbimg files get --name files/base123
```

For every `--ref`, copy the canonical `name` and `mimeType` from upload, list,
or get output:

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --ref object:OBJECT_BAG=files/bag789,image/png \
  --ref style:STYLE_POSTER=files/style234,image/webp \
  --prompt "Edit BASE_IMAGE so CHARACTER_HERO appears in the scene holding OBJECT_BAG. Use STYLE_POSTER only for color grading and rendering style."
```

`files/ID` is a Gemini Files API resource name. It is not a local path, and a
bare ID without `files/` is invalid. `nbimg edit` does not call `files get`
before generation; it derives the request `file_uri` from the canonical
`files/...` name and uses the MIME value you supplied as `file_data.mime_type`.

---

## 2. Think in reference roles

Use one primary role per image. The CLI turns each role into model-facing
manifest text and interleaves that text with the uploaded image `file_data`
part.

| Role | Use it for |
| --- | --- |
| `scene` | environment, composition, camera angle, framing, placement, lighting direction, scene geometry |
| `character` | identity, apparent age, face, hair, skin tone, body proportions, recognizable presence |
| `object` | product or prop geometry, proportions, material, color, texture, markings, logo/text placement |
| `style` | palette, contrast, lighting mood, line weight, surface texture, grain, rendering technique |
| `pose` | body position, gesture, posture |
| `composition` | layout, negative space, camera angle, framing, subject placement |
| `background` | setting and background details |
| `texture` | material feel, surface texture, pattern, finish |
| `image` | general visual details explicitly requested by the task |

Use the base role to tell `nbimg` what the edit target primarily represents:

```sh
nbimg edit \
  --ref character=files/portrait_base,image/jpeg \
  --preserve "BASE_IMAGE facial identity, apparent age, hairstyle, and body proportions" \
  --prompt "Change BASE_IMAGE clothing and background while keeping the same recognizable person."
```

The first reference is still `BASE_IMAGE`; the `character` role only changes
the base-image guidance sent by `nbimg`.

---

## 3. Use symbolic labels, not filenames

Do not rely on uploaded file names like `IMG_4021.jpg`,
`claire_face_asset`, or `scooter_prop_asset` in the prompt. File names are
metadata; symbolic labels are the model-facing handles.

```sh
nbimg edit \
  --ref scene=files/city_base,image/jpeg \
  --ref character:CHARACTER_CLAIRE=files/claire_face,image/jpeg \
  --ref object:OBJECT_HOVER_SCOOTER=files/scooter_prop,image/png \
  --prompt "Edit BASE_IMAGE so CHARACTER_CLAIRE rides OBJECT_HOVER_SCOOTER through the existing street scene."
```

Later references may omit a custom label. In that case `nbimg` assigns labels
by role, such as `CHARACTER_A`, `OBJECT_A`, or `STYLE_REFERENCE_A`.
Explicit labels are easier to read when multiple references are involved.

If you omit labels on repeated references with the same role, `nbimg` advances
the deterministic label by letter:

```sh
nbimg edit \
  --ref scene=files/gallery_base,image/jpeg \
  --ref style=files/watercolor_style,image/webp \
  --ref style=files/ink_style,image/png \
  --prompt "Blend STYLE_REFERENCE_A watercolor texture with STYLE_REFERENCE_B ink linework while preserving BASE_IMAGE layout."
```

The first omitted `style` label becomes `STYLE_REFERENCE_A`; the second becomes
`STYLE_REFERENCE_B`. Other roles follow the same pattern: `SCENE_REFERENCE_A`,
`CHARACTER_A`, `OBJECT_A`, `POSE_REFERENCE_A`, `COMPOSITION_REFERENCE_A`,
`BACKGROUND_REFERENCE_A`, `TEXTURE_REFERENCE_A`, and `IMAGE_REFERENCE_A`.
Custom labels must be unique ASCII `SCREAMING_SNAKE_CASE`, start with an ASCII
uppercase letter, and be at most 64 bytes. `BASE_IMAGE` is reserved.

Use `background` when the reference should contribute only setting details, and
use `image` when the reference is general visual context:

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

---

## 4. Separate preserve, change, and do-not-copy instructions

The safest edit pattern is to say what stays from `BASE_IMAGE`, what is borrowed
from each later reference, and what must not be copied.

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

This prevents common failure modes: copying the whole reference photo, importing
the wrong background, merging product details into the character, or treating a
style reference as literal scene content.

`--preserve TEXT` and `--do-not TEXT` are repeatable. Empty string values are
accepted as no-ops and are not sent in the edit task. Each list is capped at 16
non-empty entries, and each non-empty value is capped at 16 KiB.

---

## 5. Character references need identity boundaries

For character consistency, use a `character` reference and constrain the prompt
to identity traits. Let clothing, pose, lighting, and background come from the
edit task or base image unless you explicitly want them copied.

```sh
nbimg files upload --path refs/base-portrait.jpg
nbimg files upload --path refs/nadine-identity.jpg
```

```sh
nbimg edit \
  --ref scene=files/base_portrait,image/jpeg \
  --ref character:CHARACTER_NADINE=files/nadine_identity,image/jpeg \
  --preserve "BASE_IMAGE pose, crop, camera angle, lighting, and clothing silhouette" \
  --do-not "copy CHARACTER_NADINE background, lighting, clothing, pose, or camera angle" \
  --prompt "Replace the person in BASE_IMAGE with CHARACTER_NADINE while preserving the original scene and pose."
```

For multiple characters, label each identity and explicitly keep them distinct:

```sh
nbimg edit \
  --ref scene=files/group_base,image/jpeg \
  --ref character:CHARACTER_A=files/person_a,image/jpeg \
  --ref character:CHARACTER_B=files/person_b,image/jpeg \
  --preserve "BASE_IMAGE group composition, camera angle, lighting, and body placement" \
  --do-not "blend CHARACTER_A and CHARACTER_B facial features, hairstyles, clothing, or body proportions" \
  --prompt "Edit BASE_IMAGE so the left person has CHARACTER_A identity and the right person has CHARACTER_B identity."
```

---

## 6. Object references need fidelity boundaries

For products or props, preserve exact object details and prevent unwanted
context from leaking into the scene.

```sh
nbimg files upload --path refs/desk-scene.jpg
nbimg files upload --path refs/ceramic-speaker.png
```

```sh
nbimg edit \
  --ref scene=files/desk_scene,image/jpeg \
  --ref object:OBJECT_SPEAKER=files/ceramic_speaker,image/png \
  --preserve "BASE_IMAGE desk, room, camera angle, light direction, and realistic perspective" \
  --do-not "copy OBJECT_SPEAKER background, tabletop, shadows, or surrounding props" \
  --prompt "Place OBJECT_SPEAKER on the desk in BASE_IMAGE. Preserve its geometry, material, color, texture, logo placement, proportions, and visible markings. Match scale, contact shadows, and lighting."
```

For packaging or branded assets, put text fidelity in the edit prompt:

```sh
nbimg edit \
  --ref scene=files/shelf_base,image/jpeg \
  --ref object:OBJECT_PACKAGE=files/package_front,image/png \
  --preserve "BASE_IMAGE shelf layout, camera angle, and lighting direction" \
  --do-not "invent additional brand names, slogans, symbols, or package text" \
  --prompt "Place OBJECT_PACKAGE on the shelf in BASE_IMAGE. Preserve all legible text from OBJECT_PACKAGE exactly where it appears on the package."
```

The current CLI does not expose a separate text-fidelity control, so keep
branded packaging and lettering requirements in the edit prompt and in
`--do-not` constraints.

---

## 7. Style references need narrow boundaries

Style references are easy to over-copy. Use `style` only for palette, contrast,
lighting mood, line weight, surface texture, grain, and rendering technique.

```sh
nbimg files upload --path refs/cafe-base.jpg
nbimg files upload --path refs/watercolor-style.webp
```

```sh
nbimg edit \
  --ref scene=files/cafe_base,image/jpeg \
  --ref style:STYLE_WATERCOLOR=files/watercolor_style,image/webp \
  --preserve "BASE_IMAGE composition, subject identity, object placement, and camera angle" \
  --do-not "copy STYLE_WATERCOLOR subject, layout, objects, background, or composition" \
  --prompt "Re-render BASE_IMAGE using STYLE_WATERCOLOR color palette, contrast, lighting mood, paper texture, and brush rendering."
```

For photographic style, constrain the style reference to photographic qualities:

```sh
nbimg edit \
  --ref scene=files/night_street_base,image/jpeg \
  --ref style:STYLE_CINEMA=files/cinema_reference,image/jpeg \
  --preserve "BASE_IMAGE street layout, subject placement, and camera angle" \
  --do-not "copy STYLE_CINEMA people, vehicles, location, or composition" \
  --prompt "Apply STYLE_CINEMA cinematic lighting, lens feel, film grain, contrast curve, and color grading to BASE_IMAGE."
```

---

## 8. Composition, pose, background, and texture references

Use these roles when the reference is not an identity, product, or style
source.

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

---

## 9. Multi-reference workflow

A complex edit should still use one base image and a small set of clearly
labeled references.

```sh
nbimg files upload --path refs/apartment-base.jpg
nbimg files upload --path refs/model-identity.jpg
nbimg files upload --path refs/canvas-tote.png
nbimg files upload --path refs/editorial-style.webp
```

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

Use `--out-dir` only with an existing directory. `nbimg` prints generated output
filenames to stdout and logs response details to stderr. Do not combine
`--out-dir` with `--batch-file`; batch mode validates and appends a request
instead of generating images immediately.

---

## 10. Request debugging

Use `--print-request` when you want to inspect the sanitized request sent to
Gemini. By itself, `--print-request` still executes the edit through
`generateContent`.

```sh
nbimg edit \
  --print-request \
  --ref scene=files/base123,image/jpeg \
  --ref object:OBJECT_BAG=files/bag789,image/png \
  --preserve "BASE_IMAGE composition and camera angle" \
  --do-not "copy OBJECT_BAG background or product-photo lighting" \
  --prompt "Place OBJECT_BAG on the chair in BASE_IMAGE."
```

For request-shape validation without immediate image generation, use batch
mode. `nbimg` builds the same `GenerateContentRequest`, sends it to
`countTokens`, and appends a Batch API JSONL entry only after the validation
request succeeds.

```sh
nbimg edit \
  --batch-file requests.jsonl \
  --batch-key bag-on-chair \
  --ref scene=files/base123,image/jpeg \
  --ref object:OBJECT_BAG=files/bag789,image/png \
  --preserve "BASE_IMAGE composition and camera angle" \
  --do-not "copy OBJECT_BAG background or product-photo lighting" \
  --prompt "Place OBJECT_BAG on the chair in BASE_IMAGE."
```

If a reference fails, first verify:

1. The reference uses canonical `files/ID` form.
2. The MIME is exactly `image/jpeg`, `image/png`, or `image/webp`.
3. The file still exists in Gemini Files API storage.
4. The first `--ref` has no custom label.

If Gemini returns HTTP 403 with `PERMISSION_DENIED`, such as
`{"error":{"code":403,...,"status":"PERMISSION_DENIED"}}`, treat the referenced
`files/ID` as inaccessible. For previously valid references, this usually means
the upload expired or was deleted, though it can also mean the file belongs to a
different API key/project. Check `expirationTime` in upload/list/get metadata,
run `nbimg files list` or `nbimg files get --name files/ID`, and re-upload the
local image before retrying `edit`.

These are invalid reference forms:

```sh
--ref scene:BASE_SCENE=files/base,image/jpeg
```

Invalid because the first `--ref` is always `BASE_IMAGE`; omit the label on the
base reference.

```sh
--ref style:style_ref=files/a,image/png
--ref style:STYLE-REF=files/a,image/png
```

Invalid because custom labels must start with an ASCII uppercase letter and
contain only ASCII uppercase letters, digits, and underscores.

```sh
--ref pose:POSE_MAIN=files/a,image/jpg
--ref pose:POSE_MAIN=files/a
```

Invalid because MIME is required and must be exactly `image/jpeg`,
`image/png`, or `image/webp`.

```sh
--ref POSE_MAIN=files/a,image/jpeg
```

Invalid because `POSE_MAIN` is parsed as the role. Use
`pose:POSE_MAIN=files/a,image/jpeg` instead.

---

## 11. Common mistakes to avoid

| Mistake | Why it fails | Better `nbimg` pattern |
| --- | --- | --- |
| Passing local paths to `edit` | `edit` accepts uploaded file names, not paths | Upload first, then use `--ref scene=files/ID,image/jpeg` |
| Using `--display-name` just to label references | Display names are metadata, not prompt labels | Omit `--display-name`; label references with `--ref role:LABEL=...` |
| Referring to first/second/third image | Brittle with many references | Use `BASE_IMAGE`, `CHARACTER_A`, `OBJECT_A`, or explicit labels |
| Labeling the first reference | The first reference is always `BASE_IMAGE` | Use `--ref scene=files/base,image/jpeg` |
| Reusing an expired upload | Gemini may return HTTP 403 `PERMISSION_DENIED` for inaccessible `files/ID` values | Check `expirationTime`; re-upload and replace the `files/ID` |
| Not saying what to ignore | Background, pose, or lighting may leak | Add repeatable `--do-not` boundaries |
| Mixing style and content | Style image subject may appear in output | Use `--ref style:STYLE_NAME=...` and exclude subject/layout |
| Too many unrelated references | Reference binding weakens | Use only references that contribute to the output |
| Vague object constraints | Product details may mutate | Preserve geometry, material, logo/text placement, markings, and scale |

---

## 12. Practical checklist

Before running `nbimg edit`, verify:

1. Every local image has been uploaded with `nbimg files upload --path PATH`.
2. Upload examples omit `--display-name` when you want the metadata display
   name to remain the local filename.
3. Every edit reference uses `files/ID,MIME` copied from upload/list/get
   metadata.
4. Every reused upload is still before its `expirationTime`; if not, upload the
   local image again and update the `files/ID`.
5. The first `--ref` is the intended edit target and has no custom label.
6. Later references use the most specific role: `character`, `object`,
   `style`, `pose`, `composition`, `background`, `texture`, or `image`.
7. The prompt references symbolic labels, not local filenames.
8. `--preserve` captures what must remain from `BASE_IMAGE`.
9. `--do-not` captures unwanted context from later references.
10. The request stays within current limits: 14 total images, 4 character
   references including a character base, and 10 object references including an
   object base.
11. Each `--preserve` and `--do-not` list has at most 16 non-empty entries.
12. Output controls such as `--aspect-ratio`, `--image-size`, and `--out-dir`
    are set when the result needs a specific shape, resolution tier, or
    destination.
13. Use `--batch-file` instead of `--out-dir` when you want `countTokens`
    validation and Batch JSONL preparation rather than immediate generation.

---

## Bottom line

Use `nbimg` as the reference-binding layer:

```sh
nbimg edit \
  --ref scene=files/base,image/jpeg \
  --ref character:CHARACTER_NAME=files/character,image/jpeg \
  --ref object:OBJECT_NAME=files/object,image/png \
  --preserve "what must stay from BASE_IMAGE" \
  --do-not "what must not leak from the references" \
  --prompt "the concrete edit using BASE_IMAGE, CHARACTER_NAME, and OBJECT_NAME"
```

The model does not need hidden reference metadata. It needs a clear base image,
typed references, symbolic labels, and explicit boundaries.
