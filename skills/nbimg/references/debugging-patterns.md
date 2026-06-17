# Debugging Patterns

Use this reference before validating command shape with `--print-request` or troubleshooting failed edit references.

## Request Shape

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

Check stdout for command results and stderr for request/response diagnostics.

## Failed Edit References

If an edit reference fails, first verify:

- The reference uses canonical `files/ID` form, not a local path or bare ID.
- The MIME is exactly `image/jpeg`, `image/png`, or `image/webp`.
- The file still exists in Gemini Files API storage; HTTP 403 `PERMISSION_DENIED` usually means the `files/ID` is inaccessible, often expired or deleted.
- The first `--ref` has no custom label.
- Custom labels start with an ASCII uppercase letter and contain only ASCII uppercase letters, digits, and underscores.
- Role and label are not swapped; use `pose:POSE_MAIN=files/a,image/jpeg`, not `POSE_MAIN=files/a,image/jpeg`.

## Common Mistakes

- Passing local paths to `edit`; upload first, then use `--ref scene=files/ID,image/jpeg`.
- Using `--display-name` as a prompt label; label references with `--ref role:LABEL=...`.
- Referring to first/second/third image; use `BASE_IMAGE`, auto-labels such as `CHARACTER_A`, or explicit labels.
- Labeling the first reference; it is always `BASE_IMAGE`.
- Not saying what to ignore; add repeatable `--do-not` boundaries.
- Mixing style and content; use `style` references only for style qualities and exclude subject/layout.
- Using too many unrelated references; keep only references that contribute to the output.
- Vague object constraints; preserve geometry, material, logo/text placement, markings, and scale.
