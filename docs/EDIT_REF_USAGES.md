# Edit Reference Usage

`--ref ROLE[:LABEL]=files/ID,MIME` adds one uploaded image as a typed
reference for `nbimg edit`. The first `--ref` is the base image to edit, is
always labeled `BASE_IMAGE`, and must omit `LABEL`.

## Syntax

```text
--ref ROLE[:LABEL]=files/ID,MIME
      |    |       |        |
      |    |       |        MIME type
      |    |       Gemini Files API resource name
      |    optional custom label
      reference role
```

`ROLE` is required and must be one of:

```text
scene
character
object
style
pose
composition
background
texture
image
```

`LABEL` is optional only after the first `--ref`. If it is omitted on a later
reference, `nbimg` assigns a deterministic label such as `SCENE_REFERENCE_A`,
`TEXTURE_REFERENCE_A`, `STYLE_REFERENCE_A`, or `OBJECT_A`.

Custom labels must:

- be unique within the edit request
- use ASCII `SCREAMING_SNAKE_CASE`
- start with a letter
- be at most 64 bytes
- not be `BASE_IMAGE`

`files/ID` is the uploaded Gemini File API resource name, such as
`files/abc123`. It is not a local file path.

`MIME` is required and must be one of:

```text
image/jpeg
image/png
image/webp
```

## Examples

Use a character reference with a custom label:

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --prompt "Put CHARACTER_HERO into the BASE_IMAGE scene"
```

Use a style reference with an automatically assigned label:

```sh
nbimg edit \
  --ref scene=files/base123,image/png \
  --ref style=files/watercolor789,image/webp \
  --prompt "Apply the style reference to BASE_IMAGE"
```

More later-reference examples:

```sh
--ref object:OBJECT_SHOE=files/shoe123,image/png
--ref pose:POSE_MAIN=files/pose123,image/jpeg
--ref background:BACKGROUND_CITY=files/city123,image/webp
--ref texture=files/fabric123,image/png
--ref image=files/general123,image/jpeg
```

Use `--ref` repeatedly when an edit needs multiple reference images:

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --ref object:OBJECT_SHOE=files/shoe123,image/png \
  --ref style:STYLE_POSTER=files/poster789,image/webp \
  --prompt "Edit BASE_IMAGE so CHARACTER_HERO wears OBJECT_SHOE, using STYLE_POSTER only for the rendering style"
```

## Invalid Examples

```sh
--ref scene:BASE_SCENE=files/base,image/jpeg
```

Invalid for the first `--ref` because the base image is always labeled
`BASE_IMAGE`; use `--ref scene=files/base,image/jpeg` instead.

```sh
--ref style:style_ref=files/a,image/png
```

Invalid because `style_ref` is not ASCII `SCREAMING_SNAKE_CASE`.

```sh
--ref pose:POSE_MAIN=files/a,image/jpg
```

Invalid because the MIME type must be `image/jpeg`, not `image/jpg`.

```sh
--ref pose:POSE_MAIN=files/a
```

Invalid because the required `,MIME` suffix is missing.

```sh
--ref POSE_MAIN=files/a,image/jpeg
```

Invalid because `POSE_MAIN` is parsed as the role, and it is not one of the
supported role names. Use `pose:POSE_MAIN=files/a,image/jpeg` instead.
