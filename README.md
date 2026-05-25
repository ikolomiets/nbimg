# nbimg

`nbimg` is a small Zig CLI for experimenting with Gemini native image
generation and the Gemini Files API.

The current implementation is intentionally narrow:

- generate image and text output from a text prompt
- edit an uploaded Gemini File API image with a text prompt
- enable Google Search or Image Search grounding for generation and edit
- configure Gemini Thinking level and request returned thought parts
- upload supported image files to Gemini Files API
- list, get, and delete uploaded Gemini files
- print sanitized response traffic by default, with optional request traffic

See [docs/IMPLEMENTATION_DESIGN.md](docs/IMPLEMENTATION_DESIGN.md) for the
current implementation details.

## Requirements

- Zig 0.16.0
- `GEMINI_API_KEY` set in the environment for live API calls

The project currently uses only the Zig standard library.

## Build

```sh
zig build
```

The installed executable is always built with `ReleaseSafe`, which keeps Zig
safety checks and `std.debug.assert` active.

The executable is written to:

```sh
zig-out/bin/nbimg
```

Development executions through `zig build run -- <args>` compile and run a
separate Debug artifact from the build cache.

## Usage

Generate an image from a prompt:

```sh
printf '%s\n' "Create a photo of my fair lady" | zig-out/bin/nbimg gen
```

You can also pass the prompt explicitly:

```sh
zig-out/bin/nbimg gen \
  --aspect-ratio 16:9 \
  --image-size 2K \
  --prompt "Create a photo of my fair lady"
```

Upload an image:

```sh
zig-out/bin/nbimg files upload --path sample_images/good_night.jpeg
```

By default, uploads use the local file name as the Gemini display name. Override
it with `--display-name`:

```sh
zig-out/bin/nbimg files upload \
  --path sample_images/good_night.jpeg \
  --display-name "nbimg sample image"
```

Edit an uploaded image:

```sh
printf '%s\n' "change visual style to Broadway musical" | zig-out/bin/nbimg edit \
  --ref character=files/tjtj5me9i96c,image/jpeg
```

If `gen` or `edit` omits `--prompt`, `nbimg` reads the prompt from stdin.
Stdin prompts are limited to `16 KiB`.

Use `--out-dir DIR` with `gen` or `edit` to write generated outputs to an
existing relative or absolute directory instead of the current directory.
Gemini text response parts are written as `.txt` files beside generated image
files.

Use `--aspect-ratio RATIO` and `--image-size SIZE` with `gen` or `edit` to
request a specific generated canvas shape or resolution tier. Valid aspect
ratios are `1:1`, `1:4`, `1:8`, `2:3`, `3:2`, `3:4`, `4:1`, `4:3`, `4:5`,
`5:4`, `8:1`, `9:16`, `16:9`, and `21:9`. Valid image sizes are `512`, `1K`,
`2K`, and `4K`. If both flags are omitted, `nbimg` leaves Gemini's output
shape defaults unchanged.

Use `--thinking-level minimal|high` with `gen` or `edit` to control Gemini's
thinking effort. Omit it to use Gemini's default. Use `--include-thoughts` to
ask Gemini to return thought parts in the response. Response traffic is already
logged to stderr by default, so thought text is visible there when returned.
Thought image parts are written beside final outputs, using filenames such as
`RESPONSE-0-thought-0.jpg`.

Use `--grounding MODE` with `gen` or `edit` when the prompt should be grounded
with Google Search. Valid modes are `none`, `web`, `image`, and `web,image`.
The default is `none`.

Grounding adds the Gemini `google_search` tool to the request. The model may
then search before answering, use the retrieved context while generating, and
return `groundingMetadata` in the raw API response. `nbimg` does not save that
metadata separately; response traffic is logged to stderr by default, so the
metadata remains visible there when Gemini returns it.

Web grounding is for current factual or real-world context, such as recent
events, venue details, weather-aware scenes, or up-to-date product information:

```sh
zig-out/bin/nbimg gen \
  --grounding web \
  --prompt "Create a 16:9 editorial image of the current Toronto skyline at sunrise, using accurate recent landmark details"
```

Image Search grounding is for visual search context. It lets Gemini use Google
Image Search results for visual grounding before generating, which is useful
for current visual trends, real object appearance, species or location
references, mood boards, and visual research. Google's current image docs state
that Image Search grounding cannot be used to search for people.

```sh
zig-out/bin/nbimg gen \
  --grounding image \
  --prompt "Use image search to find accurate images of a resplendent quetzal bird, then create a clean 3:2 wallpaper inspired by its real colors and shape"
```

Use combined `web,image` grounding when the prompt benefits from both factual
web context and visual image-search context:

```sh
zig-out/bin/nbimg gen \
  --grounding web,image \
  --prompt "Create a magazine-style page about the latest Gemini image model news, with a current hero image style informed by recent visual coverage"
```

The `edit` command takes uploaded image references in `files/ID,MIME` form.
The first `--ref` is the base image to edit and is always labeled
`BASE_IMAGE`; omit a custom label on that first reference. Supported MIME values
are `image/jpeg`, `image/png`, and `image/webp`. The command derives the Gemini
File API URI from the `files/...` name and does not call `files get` before
generation.

Generic edit references use this syntax:

```text
--ref ROLE[:LABEL]=files/ID,MIME
      |    |       |        |
      |    |       |        MIME type
      |    |       Gemini Files API resource name
      |    optional custom label
      reference role
```

Valid roles are `scene`, `character`, `object`, `style`, `pose`,
`composition`, `background`, `texture`, and `image`.

For example:

```sh
nbimg edit \
  --ref scene=files/base123,image/jpeg \
  --ref character:CHARACTER_HERO=files/person456,image/jpeg \
  --ref object:OBJECT_SHOE=files/shoe123,image/png \
  --ref style:STYLE_POSTER=files/poster789,image/webp \
  --prompt "Edit BASE_IMAGE so CHARACTER_HERO wears OBJECT_SHOE, using STYLE_POSTER only for the rendering style"
```

More later-reference examples:

```sh
--ref style=files/watercolor789,image/webp
--ref pose:POSE_MAIN=files/pose123,image/jpeg
--ref background:BACKGROUND_CITY=files/city123,image/webp
--ref texture=files/fabric123,image/png
--ref image=files/general123,image/jpeg
```

Useful edit flags:

```sh
--ref ROLE[:LABEL]=files/ID,MIME
--preserve TEXT
--do-not TEXT
--aspect-ratio RATIO
--image-size SIZE
--grounding none|web|image|web,image
--thinking-level minimal|high
--include-thoughts
--out-dir DIR
```

Empty `--preserve ""` and `--do-not ""` values are accepted as no-ops.
Omitting these flags renders no extra preserve or do-not section.

List uploaded file metadata:

```sh
zig-out/bin/nbimg files list
```

Get one uploaded file's metadata:

```sh
zig-out/bin/nbimg files get --name files/abc123
```

Delete one uploaded file:

```sh
zig-out/bin/nbimg files delete --name files/abc123
```

The upload, list, and get commands print JSON metadata to stdout.
The delete command prints `OK` on success.

Debug traffic:

```sh
zig-out/bin/nbimg gen \
  --print-request \
  --prompt "Create a photo of my fair lady"
```

Response traffic logs go to stderr by default. Use `--print-request` to also
log request traffic. Command results, such as generated filenames, Files API
metadata JSON, or delete `OK`, go to stdout.

## Testing

Run offline tests:

```sh
zig build test
```

Live API tests are opt-in and intended for validating request JSON shapes
against the real Gemini API:

```sh
zig build test-live-api-generate-content-request-validity
zig build test-live-api-edit-request-validity
zig build test-live-api-files-upload-list
zig build test-live-api-files-get
zig build test-live-api-files-delete
```

`generateContent` is billable, so the request-shape live tests for `gen` and
`edit` use `countTokens` as a lower-cost validation endpoint instead of
generating content. The `gen` and `edit` request-shape live tests include
`web,image` grounding and `thinkingConfig` to validate the tool-bearing and
Thinking request shape. The edit request-shape live test uploads
`sample_images/good_night.jpeg` through the Files API, validates the edit
request with the uploaded `files/...` name, and deletes the uploaded file after
validation.
