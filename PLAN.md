# Implementation Plan

This file tracks prioritized TODO items for `nbimg`. Keep it synchronized with
the current codebase: remove items when implemented, revise items when the API
shape changes, and add newly discovered gaps in priority order.

## 1. Thinking controls

- Current gap: `generationConfig.thinkingConfig` is not supported.
- Likely CLI/API surface: add `--thinking-level minimal|high`,
  `--include-thoughts`, and a thought-output policy.
- Implementation notes: response decoding must distinguish final outputs from
  thought parts so thought images are not saved as ordinary results by mistake.
- Testing: cover request JSON, invalid option values, and response fixtures
  containing `thought` parts and thought signatures.

## 2. Response Modality Selection

- Current gap: `gen` and `edit` always request image-only output.
- Likely CLI/API surface: add a response modality flag for `image` and
  `text,image`, with image-only remaining the default unless product behavior
  intentionally changes.
- Implementation notes: keep generated text output naming and decoding stable,
  because response decoding already supports text parts.
- Testing: add request-shape tests for each accepted modality combination and
  response fixture tests for interleaved text and image parts.

## 3. `responseFormat.image` Output Options

- Current status: `--aspect-ratio` and `--image-size` serialize through
  `generationConfig.responseFormat.image` using Gemini enum values such as
  `ASPECT_RATIO_SIXTEEN_BY_NINE` and `IMAGE_SIZE_TWO_K`.
- Current status: do not add a public `--delivery` option for the nano2 image
  model. Billable `generateContent` validation showed Gemini rejects explicit
  `responseFormat.image.delivery` values, including both `INLINE` and `URI`,
  even though `countTokens` accepts them.
- Remaining gap: image `mimeType` is not user-configurable because only
  `IMAGE_JPEG` is currently useful. URI delivery is also not implemented
  because Gemini currently rejects explicit delivery on `generateContent`.
- Testing: keep golden request JSON tests and live countTokens validation
  covering the selected aspect/size REST wire shape. Before serializing future
  `delivery` or `mimeType` fields, validate against billable `generateContent`
  or a non-billable endpoint proven to match it, because `countTokens` accepted
  explicit `delivery` values that `generateContent` rejected.

## 4. Configurable Safety Settings

- Current gap: requests always send fixed `BLOCK_NONE` safety settings.
- Likely CLI/API surface: add explicit safety threshold controls per supported
  harm category, while preserving the current defaults unless changed
  deliberately.
- Implementation notes: keep safety parsing in the CLI and shared wire structs
  in `src/api.zig`; document any categories the API accepts but the CLI omits.
- Testing: cover parsing, duplicate category handling, request serialization,
  and at least one live validation for changed safety settings.

## 5. Generic Generation Controls

- Current gap: generic `GenerationConfig` fields such as `candidateCount`,
  `maxOutputTokens`, `temperature`, `topP`, `topK`, `seed`, penalties,
  logprobs, and stop sequences are not exposed.
- Likely CLI/API surface: add conservative flags only for fields confirmed to
  be image-compatible, with validation for numeric ranges and duplicates.
- Implementation notes: avoid a broad raw passthrough until there is a clear
  compatibility and validation strategy.
- Testing: add parser tests, request JSON tests, and live validation for each
  image-compatible field group.

## 6. Request-Level Controls

- Current gap: request-level fields such as `systemInstruction`,
  `cachedContent`, `serviceTier`, and `store` are not exposed.
- Likely CLI/API surface: add narrowly scoped flags when a concrete workflow
  needs them, such as `--system`, `--cached-content`, `--service-tier`, and
  `--store`.
- Implementation notes: separate request-level fields from generation config
  fields in internal structs so ownership and validation stay visible.
- Testing: add request-shape tests and live validation for any field whose
  accepted values or image-model compatibility are uncertain.
