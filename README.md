# nbimg

`nbimg` is a small Zig CLI for experimenting with Gemini native image
generation and the Gemini Files API.

The current implementation is intentionally narrow:

- generate image output from a text prompt
- edit an uploaded Gemini File API image with a text prompt
- upload supported image files to Gemini Files API
- list, get, and delete uploaded Gemini files
- optionally print sanitized request/response traffic for debugging

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
zig-out/bin/nbimg gen --prompt "Create a photo of my fair lady"
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
  --base files/tjtj5me9i96c,image/jpeg \
  --base-role character
```

If `gen` or `edit` omits `--prompt`, `nbimg` reads the prompt from stdin.
Stdin prompts are limited to `16 KiB`.

The `edit` command takes uploaded image references in `files/ID,MIME` form.
Supported MIME values are `image/jpeg`, `image/png`, and `image/webp`. The
command derives the Gemini File API URI from the `files/...` name and does not
call `files get` before generation.

Useful edit flags:

```sh
--base-role scene|character|object
--character [LABEL=]files/ID,MIME
--object [LABEL=]files/ID,MIME
--style [LABEL=]files/ID,MIME
--ref ROLE[:LABEL]=files/ID,MIME
--preserve TEXT
--do-not TEXT
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
  --print-response \
  --prompt "Create a photo of my fair lady"
```

`gen` and `edit` also support `--write-response` to save the raw Gemini
response JSON next to generated outputs.

Traffic logs go to stderr. Command results, such as generated filenames, Files
API metadata JSON, or delete `OK`, go to stdout.

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
generating content. The edit request-shape live test uploads
`sample_images/good_night.jpeg` through the Files API, validates the edit
request with the uploaded `files/...` name, and deletes the uploaded file after
validation.
