# Implementation Plan

This file tracks prioritized TODO items for `nbimg`. Keep it synchronized with
the current codebase: remove items when implemented, revise items when the API
shape changes, and add newly discovered gaps in priority order.

## Module Design Guardrail

Adhere to the chosen module ownership before adding new behavior. Shared Gemini
wire mechanics, parsing rules, MIME/name enums, transport helpers, response
decoding, and cross-command request primitives belong in `src/api.zig`.
Command modules should keep only command-specific parsing, validation, request
assembly, and response handling. If a helper would be duplicated between
`src/gen.zig`, `src/edit.zig`, or `src/files.zig`, treat that as a design
signal to pick one shared owner, usually `src/api.zig`, before implementation.
Avoid compatibility aliases for internal duplicated types unless there is a
specific migration need.

## 1. `responseFormat.image` Output Options

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

## 2. Request-Level Controls

- Current gap: request-level fields such as `systemInstruction`,
  `cachedContent`, `serviceTier`, and `store` are not exposed.
- Likely CLI/API surface: add narrowly scoped flags when a concrete workflow
  needs them, such as `--system`, `--cached-content`, `--service-tier`, and
  `--store`.
- Implementation notes: separate request-level fields from generation config
  fields in internal structs so ownership and validation stay visible.
- Testing: add request-shape tests and live validation for any field whose
  accepted values or image-model compatibility are uncertain.
