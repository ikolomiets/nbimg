# nbimg

`nbimg` is a small Zig CLI for experimenting with Gemini native image
generation and the Gemini Files API.

The current implementation is intentionally narrow:

- generate image output from a text prompt
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

The default build mode is `ReleaseSafe`, which keeps Zig safety checks and
`std.debug.assert` active.

The executable is written to:

```sh
zig-out/bin/nbimg
```

## Usage

Generate an image from a prompt:

```sh
zig-out/bin/nbimg gen --prompt "Create a photo of my fair lady"
```

Upload an image:

```sh
zig-out/bin/nbimg files upload --path sample_images/good_night.jpeg
```

Upload an image with a Gemini display name:

```sh
zig-out/bin/nbimg files upload \
  --path sample_images/good_night.jpeg \
  --display-name "nbimg sample image"
```

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
zig build test-live-api-files-upload-list
zig build test-live-api-files-get
zig build test-live-api-files-delete
```

`generateContent` is billable, so the generate-content request validity test
uses `countTokens` as a lower-cost validation endpoint instead of generating
content.
