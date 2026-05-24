# Implementation Plan

This file tracks prioritized TODO items for `nbimg`. Keep it synchronized with
the current codebase: remove items when implemented, revise items when the API
shape changes, and add newly discovered gaps in priority order.

## 1. Google Search and Image Search Grounding

- Current gap: `nbimg` does not expose Gemini grounding tools for Nano Banana 2
  image generation or edit workflows.
- Likely CLI/API surface: add grounding flags such as `--grounding web`,
  `--grounding image`, and optional grounding metadata output controls.
- Implementation notes: add request `tools` support in shared API structures,
  keep grounding metadata handling explicit, and document current limitations
  such as web-searched real-world people.
- Testing: add offline request-shape tests and validate changed grounding
  request shapes through a non-generation endpoint when possible.

## 2. Thinking controls

- Current gap: `generationConfig.thinkingConfig` is not supported.
- Likely CLI/API surface: add `--thinking-level minimal|high`,
  `--include-thoughts`, and a thought-output policy.
- Implementation notes: response decoding must distinguish final outputs from
  thought parts so thought images are not saved as ordinary results by mistake.
- Testing: cover request JSON, invalid option values, and response fixtures
  containing `thought` parts and thought signatures.

## 3. Response Modality Selection

- Current gap: `gen` and `edit` always request image-only output.
- Likely CLI/API surface: add a response modality flag for `image` and
  `text,image`, with image-only remaining the default unless product behavior
  intentionally changes.
- Implementation notes: keep generated text output naming and decoding stable,
  because response decoding already supports text parts.
- Testing: add request-shape tests for each accepted modality combination and
  response fixture tests for interleaved text and image parts.

## 4. `responseFormat.image` Output Options

- Current status: `--aspect-ratio` and `--image-size` serialize through
  `generationConfig.responseFormat.image` using Gemini enum values such as
  `ASPECT_RATIO_SIXTEEN_BY_NINE` and `IMAGE_SIZE_TWO_K`.
- Remaining gap: image `mimeType` and `delivery` are not user-configurable.
  Live `countTokens` accepted `IMAGE_JPEG` with `INLINE` and `URI`, but adding
  flags needs response-shape and output-writing behavior validation.
- Testing: keep golden request JSON tests and live countTokens validation
  covering the selected REST wire shape.

## 5. Configurable Safety Settings

- Current gap: requests always send fixed `BLOCK_NONE` safety settings.
- Likely CLI/API surface: add explicit safety threshold controls per supported
  harm category, while preserving the current defaults unless changed
  deliberately.
- Implementation notes: keep safety parsing in the CLI and shared wire structs
  in `src/api.zig`; document any categories the API accepts but the CLI omits.
- Testing: cover parsing, duplicate category handling, request serialization,
  and at least one live validation for changed safety settings.

## 6. Generic Generation Controls

- Current gap: generic `GenerationConfig` fields such as `candidateCount`,
  `maxOutputTokens`, `temperature`, `topP`, `topK`, `seed`, penalties,
  logprobs, and stop sequences are not exposed.
- Likely CLI/API surface: add conservative flags only for fields confirmed to
  be image-compatible, with validation for numeric ranges and duplicates.
- Implementation notes: avoid a broad raw passthrough until there is a clear
  compatibility and validation strategy.
- Testing: add parser tests, request JSON tests, and live validation for each
  image-compatible field group.

## 7. Request-Level Controls

- Current gap: request-level fields such as `systemInstruction`,
  `cachedContent`, `serviceTier`, and `store` are not exposed.
- Likely CLI/API surface: add narrowly scoped flags when a concrete workflow
  needs them, such as `--system`, `--cached-content`, `--service-tier`, and
  `--store`.
- Implementation notes: separate request-level fields from generation config
  fields in internal structs so ownership and validation stay visible.
- Testing: add request-shape tests and live validation for any field whose
  accepted values or image-model compatibility are uncertain.
