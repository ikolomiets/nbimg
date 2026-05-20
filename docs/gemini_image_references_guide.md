# Best practices for describing attached image references in Nano Banana 2 edit-mode `generateContent`

For Nano Banana 2, treat image references as **model-readable context**, not as opaque API attachments. The API receives images as `parts`; the model understands their role from the **nearby text annotations** you put around those image parts. The attached guide’s strongest pattern is exactly this: interleave every reference asset with a textual “anchor block,” then finish with a separate generation/edit instruction that maps the assets into the target scene. 

Google’s current docs confirm the relevant mechanics: `gemini-3.1-flash-image-preview` is Nano Banana 2 / Gemini 3.1 Flash Image, supports image generation and editing, and can mix up to 14 reference images, including up to 10 object images and up to 4 character references for Gemini 3.1 Flash Image Preview. ([Google AI for Developers][1])

---

## 1. Think in three image categories

In edit mode, do not just say “use these images.” Assign each image a precise role.

### A. Base image / edit target

This is the image you want modified.

Use labels like:

```text
BASE_IMAGE
EDIT_TARGET
SOURCE_SCENE
ORIGINAL_IMAGE
```

Describe what should be preserved:

```text
BASE_IMAGE:
This is the image to edit. Preserve the overall composition, camera angle, framing, subject placement, and body pose unless the edit instruction explicitly says otherwise.
```

### B. Character reference

This is for identity consistency.

Use labels like:

```text
CHARACTER_A
CHARACTER_MAIN
CHARACTER_NADINE
FACE_REFERENCE_A
```

Describe identity attributes separately from scene attributes:

```text
CHARACTER_A:
This is the identity reference for the main woman. Preserve facial identity, apparent age, face shape, hairstyle, hair color, skin tone, and recognizable proportions. Do not copy the background, lighting, clothing, pose, or camera angle unless explicitly requested.
```

### C. Object / product reference

This is for object fidelity.

Use labels like:

```text
OBJECT_A
PRODUCT_A
PROP_SCOOTER
LOGO_REFERENCE
PACKAGE_DESIGN_REFERENCE
```

Describe the object’s non-negotiable features:

```text
OBJECT_A:
This is the product reference. Preserve the product geometry, color, material, visible markings, logo placement, proportions, and distinctive details. It should appear as the same object in the edited image.
```

---

## 2. Use an explicit reference manifest

The best prompt shape is:

```text
REFERENCE MANIFEST

BASE_IMAGE:
[meaning of the next image]

[image part]

CHARACTER_A:
[meaning of the next image]

[image part]

OBJECT_A:
[meaning of the next image]

[image part]

EDIT TASK:
[what to create or change]

PRESERVE:
[what must remain unchanged]

CHANGE:
[what should be modified]

DO NOT:
[what must not be copied, changed, merged, or hallucinated]
```

This is better than a free-form paragraph because it gives the model a stable symbolic map. The official Files API examples show that uploaded File API assets are passed into `generateContent` as file parts, using the uploaded file’s `file_uri` and MIME type; in current REST examples this appears as `file_data: { mime_type, file_uri }`. ([Google AI for Developers][2])

---

## 3. Put the role text immediately before the image part

Use this ordering for multiple references:

```json
{
  "text": "CHARACTER_A: The next image is the identity reference for the main woman. Preserve identity, face, hair, apparent age, and body proportions. Do not copy pose, lighting, background, or clothing."
},
{
  "file_data": {
    "mime_type": "image/jpeg",
    "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/..."
  }
}
```

This adjacency matters. The attached guide recommends aligning each image with an interleaved explanation/anchor block so the model can map “this image” to “this semantic role.” 

Avoid this weaker pattern:

```text
Here are five images. Use the first as the woman, the second as the dress, the third as the style, and the fourth as the room...
```

It can work, but it is fragile. Once you have several references, labels like `CHARACTER_A`, `OBJECT_DRESS`, and `STYLE_REFERENCE` are safer.

---

## 4. Separate “preserve” from “borrow”

This is the most important edit-mode discipline.

Bad:

```text
Use this woman and this dress and make a new image.
```

Better:

```text
Use CHARACTER_A only for the woman’s identity: face, apparent age, hair, skin tone, and recognizable proportions.

Use OBJECT_DRESS only for the dress design: silhouette, fabric texture, color, neckline, sleeve shape, and decorative details.

Do not copy CHARACTER_A’s original clothing. Do not copy OBJECT_DRESS’s original mannequin/body/background. Combine the identity from CHARACTER_A with the garment design from OBJECT_DRESS in the edited BASE_IMAGE.
```

This prevents common failure modes: the model copies the whole reference photo, imports the wrong background, merges character and object details, or treats a style reference as a literal scene reference.

---

## 5. Use typed labels, not file names

Do not rely on uploaded file names like:

```text
IMG_4021.jpg
claire_face_asset
scooter_prop_asset
```

Use semantic labels:

```text
CHARACTER_CLAIRE
OBJECT_HOVER_SCOOTER
STYLE_ISOMETRIC_COMIC
BASE_SCENE
```

The File API `displayName` / file name is metadata. The model-facing interpretation should be stated explicitly in the prompt. The API gives you a reusable file URI, but the *role* of that file is still established by text context. ([Google AI for Developers][2])

---

## 6. Distinguish edit target from references

For edit mode, the base image should usually be introduced first:

```text
BASE_IMAGE:
The next image is the image to edit. Preserve its composition, camera angle, subject placement, and original framing.

[base image]

CHARACTER_A:
The next image is the identity reference for the replacement character.

[character image]

OBJECT_A:
The next image is the object/product to add to the scene.

[object image]

EDIT TASK:
Edit BASE_IMAGE so that the person in BASE_IMAGE has the identity of CHARACTER_A and is holding OBJECT_A.
```

This tells the model: **one image is the canvas; the others are constraints**.

If you put all images in without this distinction, the model may invent a new scene instead of editing the intended base image.

---

## 7. Make “do not copy” explicit

Every reference image contains unwanted visual context: background, lighting, camera angle, pose, clothing, props, artifacts, shadows, watermark, compression noise, etc.

Use negative role boundaries:

```text
Do not copy the background from CHARACTER_A.
Do not copy the pose from CHARACTER_A.
Do not copy the lighting from OBJECT_A.
Do not copy the table, room, or surrounding objects from OBJECT_A.
Do not merge the logo from OBJECT_A into the character’s clothing.
Do not change BASE_IMAGE composition unless required by the edit.
```

Google’s prompt guidance also recommends specificity, step-by-step instructions for complex scenes, and positively framed constraints rather than vague keyword lists. ([Google AI for Developers][3])

---

## 8. Use “identity lock” language for characters

For character references, use:

```text
Maintain:
- facial identity
- face shape
- apparent age
- hairstyle and hair color
- skin tone
- body proportions
- recognizable presence

May change:
- clothing
- expression
- pose
- lighting
- background
- camera angle
```

Example:

```text
CHARACTER_A:
Use this image only as an identity reference. Preserve the woman’s facial identity, apparent age, hair, face shape, skin tone, and body proportions. In the edited image, she may have a different expression and clothing, but she must remain recognizably the same person.
```

For multiple characters:

```text
CHARACTER_A and CHARACTER_B must remain visually distinct. Do not blend their facial features, hairstyles, clothing, or body proportions.
```

---

## 9. Use “fidelity lock” language for objects

For product/object references, be concrete:

```text
OBJECT_A:
Preserve the exact object category, silhouette, proportions, material, color palette, texture, logo placement, text placement, hardware details, seams, edges, and visible markings.
```

For product placement:

```text
Place OBJECT_A on the table in BASE_IMAGE. It should look physically integrated into the scene, with correct perspective, scale, contact shadows, and lighting consistent with BASE_IMAGE.
```

For packaging or branded assets:

```text
Preserve all legible text from OBJECT_A exactly where it appears on the package. Do not invent additional brand names, slogans, or symbols.
```

Text rendering is improved in Gemini 3 image models, but for best results Google recommends generating text first and then asking for an image with that text. ([Google AI for Developers][3])

---

## 10. Use style references carefully

Style references are especially easy to over-copy. Say whether the style reference controls palette, medium, lighting, composition, linework, or all of them.

Weak:

```text
Use this style.
```

Better:

```text
STYLE_REFERENCE:
Use this image only for visual style: color palette, contrast, lighting mood, line weight, surface texture, and overall rendering technique. Do not copy its subject, characters, objects, background, layout, or composition.
```

For photographic style:

```text
Use STYLE_REFERENCE for cinematic lighting, lens feel, film grain, contrast curve, and color grading only.
```

For layout/composition reference:

```text
COMPOSITION_REFERENCE:
Use this image only for layout: subject placement, negative space, camera angle, and overall framing. Do not copy its people, objects, colors, or background details.
```

---

## 11. Recommended REST template

For REST, current Google examples show uploaded file references as `file_data` with `mime_type` and `file_uri`. SDKs may expose helper objects such as `Part.from_uri(...)` or `createPartFromUri(...)`; the conceptual structure is the same. ([Google AI for Developers][2])

```json
{
  "contents": [
    {
      "role": "user",
      "parts": [
        {
          "text": "REFERENCE MANIFEST\n\nBASE_IMAGE:\nThe next image is the image to edit. Preserve its composition, camera angle, framing, lighting direction, subject placement, and overall scene geometry unless explicitly changed."
        },
        {
          "file_data": {
            "mime_type": "image/jpeg",
            "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/base_image_file"
          }
        },
        {
          "text": "CHARACTER_A:\nThe next image is the identity reference for the main woman. Preserve facial identity, apparent age, face shape, hairstyle, hair color, skin tone, and body proportions. Do not copy clothing, pose, background, lighting, or camera angle from this reference."
        },
        {
          "file_data": {
            "mime_type": "image/jpeg",
            "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/character_a_file"
          }
        },
        {
          "text": "OBJECT_A:\nThe next image is the product reference. Preserve its silhouette, proportions, material, color, texture, logo placement, and distinctive details. Do not copy its background or lighting."
        },
        {
          "file_data": {
            "mime_type": "image/png",
            "file_uri": "https://generativelanguage.googleapis.com/v1beta/files/object_a_file"
          }
        },
        {
          "text": "EDIT TASK:\nEdit BASE_IMAGE so the person in the scene has the identity of CHARACTER_A and is holding OBJECT_A.\n\nPRESERVE FROM BASE_IMAGE:\nComposition, camera angle, framing, room layout, light direction, and realistic perspective.\n\nCHANGE:\nReplace the visible person’s identity with CHARACTER_A. Add OBJECT_A naturally in her hand.\n\nDO NOT:\nDo not copy the backgrounds from CHARACTER_A or OBJECT_A. Do not change the overall scene layout. Do not merge object details into the character. Do not invent extra logos or text."
        }
      ]
    }
  ],
  "generationConfig": {
    "responseModalities": ["IMAGE"],
    "responseFormat": {
      "image": {
        "aspectRatio": "16:9",
        "imageSize": "2K"
      }
    }
  }
}
```

---

## 12. Recommended SDK-side abstraction

For your own CLI/API wrapper, I would model references explicitly in your application, then render them into Gemini `parts`.

```json
{
  "references": [
    {
      "id": "BASE_IMAGE",
      "kind": "edit_target",
      "file_uri": "...",
      "mime_type": "image/jpeg",
      "preserve": [
        "composition",
        "camera angle",
        "framing",
        "subject placement",
        "lighting direction"
      ],
      "change_scope": "Only the explicitly requested elements may change."
    },
    {
      "id": "CHARACTER_A",
      "kind": "character",
      "file_uri": "...",
      "mime_type": "image/jpeg",
      "preserve": [
        "facial identity",
        "apparent age",
        "hair",
        "skin tone",
        "body proportions"
      ],
      "exclude": [
        "background",
        "pose",
        "clothing",
        "lighting",
        "camera angle"
      ]
    },
    {
      "id": "OBJECT_A",
      "kind": "object",
      "file_uri": "...",
      "mime_type": "image/png",
      "preserve": [
        "geometry",
        "material",
        "color",
        "texture",
        "logo placement",
        "proportions"
      ],
      "exclude": [
        "background",
        "lighting",
        "surrounding props"
      ]
    }
  ]
}
```

Then render to prompt text like:

```text
REFERENCE MANIFEST

{id} ({kind}):
Preserve: ...
Do not copy: ...
The next image is this reference.
```

This gives you a deterministic layer between your CLI flags and the prompt.

---

## 13. Good reference-description patterns

### Character replacement

```text
BASE_IMAGE:
The next image is the image to edit. Preserve the original composition, pose, body placement, camera angle, and lighting.

CHARACTER_A:
The next image is the identity reference. Use it only for facial identity, age, hairstyle, skin tone, and body proportions.

EDIT TASK:
Replace the person in BASE_IMAGE with CHARACTER_A while keeping the original pose, clothing silhouette, lighting, and scene composition from BASE_IMAGE.
```

### Product insertion

```text
BASE_IMAGE:
The next image is the scene to edit.

OBJECT_A:
The next image is the product to insert. Preserve its exact geometry, color, material, text, logo, and proportions.

EDIT TASK:
Place OBJECT_A on the desk in BASE_IMAGE. Match perspective, scale, shadows, reflections, and light direction. Do not alter the desk, room, or camera angle.
```

### Style transfer without copying content

```text
BASE_IMAGE:
The next image is the scene to transform.

STYLE_REFERENCE:
The next image is only a style reference. Use its color grading, contrast, lighting mood, grain, and rendering technique. Do not copy its subject, background, objects, or layout.

EDIT TASK:
Re-render BASE_IMAGE in the visual style of STYLE_REFERENCE while preserving the original composition and subject identity.
```

### Character + object + style

```text
CHARACTER_A:
Identity reference only.

OBJECT_A:
Product/object reference only.

STYLE_REFERENCE:
Rendering style only.

EDIT TASK:
Generate a new image of CHARACTER_A holding OBJECT_A, rendered in the style of STYLE_REFERENCE.

BOUNDARIES:
Do not copy CHARACTER_A’s original clothing or background.
Do not copy OBJECT_A’s background.
Do not copy STYLE_REFERENCE’s subject or composition.
```

---

## 14. Common mistakes to avoid

| Mistake                                           | Why it fails                                      | Better pattern                                                        |
| ------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------- |
| “Use this image as reference”                     | Role is underspecified                            | “Use this image only as CHARACTER_A identity reference.”              |
| Referring to “first/second/third image”           | Brittle with many images                          | Use symbolic IDs like `BASE_IMAGE`, `CHARACTER_A`, `OBJECT_A`.        |
| Not distinguishing base image from references     | Model may generate a new scene instead of editing | Mark one image as `BASE_IMAGE` / `EDIT_TARGET`.                       |
| Over-describing obvious image content incorrectly | Can fight the actual pixels                       | Describe the intended role, not every visible detail.                 |
| Not saying what to ignore                         | Model may copy background, pose, lighting         | Add `Do not copy...` constraints.                                     |
| Mixing style and content                          | Style image’s subject leaks into output           | Say “style only; do not copy subject/layout.”                         |
| Too many unrelated references                     | Reference binding weakens                         | Use only references that contribute to the output.                    |
| Vague object constraints                          | Object mutates                                    | Name exact preserved features: geometry, material, logo, text, scale. |

---

## 15. Practical checklist

Before sending the request, verify:

1. Every image has a unique symbolic ID.
2. Every image has exactly one primary role: base, character, object, style, pose, composition, background, or texture.
3. The base image is clearly marked as the edit target.
4. Each reference says what to preserve.
5. Each reference says what not to copy.
6. The final edit instruction references the symbolic IDs, not file names.
7. The final instruction separates `PRESERVE`, `CHANGE`, and `DO NOT`.
8. The request stays within the reference-image budget: for Nano Banana 2, up to 14 total references, with high-fidelity support documented for up to 10 objects and up to 4 characters. ([Google AI for Developers][3])
9. MIME types match the actual file contents.
10. Output config explicitly sets `responseModalities`, `aspectRatio`, and `imageSize` when you need deterministic output shape. Google documents `responseModalities`, aspect ratio, and image size controls for image generation responses. ([Google AI for Developers][3])

---

## Bottom line

The best practice is to treat the request as a **reference-binding protocol**:

```text
[Image ID] + [Role] + [Preserve rules] + [Ignore rules] + [Final edit operation]
```

Nano Banana 2 does not need hidden ControlNet-like metadata for character/object/style roles. It needs clean multimodal ordering and unambiguous text anchors around each image part.

[1]: https://ai.google.dev/gemini-api/docs/gemini-3 "Gemini generateContent API  |  Google AI for Developers"
[2]: https://ai.google.dev/gemini-api/docs/files "Gemini generateContent API  |  Google AI for Developers"
[3]: https://ai.google.dev/gemini-api/docs/image-generation "Gemini API  |  Google AI for Developers"

