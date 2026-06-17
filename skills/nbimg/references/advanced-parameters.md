# Advanced Parameters

Use this reference before adding less-common `gen` or `edit` controls. Keep `--aspect-ratio`, `--image-size`, and `--thinking-level` in the main skill file.

All controls here are available on both `gen` and `edit` unless noted. All are omitted from the request unless explicitly set.

## Generation Config

Advanced generation controls are sent under Gemini `generationConfig`; they do not replace image-specific controls such as `--aspect-ratio` or `--image-size`. Except for repeatable `--stop`, each advanced generation option is accepted at most once.

- `--temperature FLOAT`: sampling variation, `0.0` through `2.0`. Lower values are more conservative; higher values allow more variation.
- `--top-p FLOAT`: nucleus sampling, `0.0` through `1.0`. Mostly useful for controlled prompt experiments.
- `--seed INT`: signed 32-bit decimal seed for best-effort reproducibility. Exact repeatability is not guaranteed; keep the same prompt, model, inputs, and generation settings when comparing runs.
- `--max-output-tokens INT`: response token budget, `1` through `32768`. It is not an image-resolution or visual-quality control; values that are too low can truncate generated text or stop generation early.
- `--presence-penalty FLOAT`: `-2.0` up to but not including `2.0`. Positive values discourage repetition; negative values can encourage reuse.
- `--frequency-penalty FLOAT`: `-2.0` up to but not including `2.0`. Positive values discourage repeated wording; negative values can encourage reuse.
- `--stop TEXT`: repeatable literal stop sequence. Up to five non-empty unique stop sequences are accepted. Stop sequences are case-sensitive text controls, not negative prompts.
- `--response-logprobs`: request token-level diagnostics on chosen response tokens.
- `--logprobs INT`: request top-token alternatives, `1` through `20`; requires `--response-logprobs`. These diagnostics are not image confidence scores.

## Request-Level Controls

These controls are top-level Gemini `GenerateContentRequest` fields. Each request-level option is accepted at most once.

- `--system TEXT`: send a text-only Gemini `systemInstruction`. The value must be non-empty and at most 16 KiB.
- `--cached-content cachedContents/ID`: attach an existing Gemini cached content resource. Use canonical `cachedContents/...` form; raw cache IDs are invalid.
- `--service-tier flex|standard|priority`: request a Gemini service tier. If omitted, Gemini uses the project and model default. If `priority` is requested and the response reports `usageMetadata.serviceTier` as `standard`, `nbimg` prints a warning but handles the response normally.
- `--store`: send `store:true`.
- `--no-store`: send `store:false`.

`--store` and `--no-store` are mutually exclusive. Omit both flags to use the project-level logging configuration.

## Grounding

Use `--grounding MODE` when the prompt should be grounded with Google Search. Valid modes are `none`, `web`, `image`, and `web,image`. The default is `none`.

- `--grounding web`: use Google Search grounding for current factual or real-world context, such as recent events, venue details, weather-aware scenes, or up-to-date product information.
- `--grounding image`: use Image Search grounding for visual context, such as current visual trends, real object appearance, species or location references, mood boards, and visual research. Do not use Image Search grounding to search for people.
- `--grounding web,image`: use both factual web context and visual image-search context.

Grounding adds the Gemini `google_search` tool to the request. The model may search before answering, use retrieved context while generating, and return `groundingMetadata` in the raw API response. `nbimg` does not save that metadata separately; response traffic is logged to stderr by default.

## Thinking Output

Use `--include-thoughts` to ask Gemini to return thought parts in the response. Returned thought parts remain in response logs and are not written as separate sidecar files.

Use the main skill file for `--thinking-level minimal|high`.

## Safety

Use `--safety none|off|permissive|balanced|strict` to choose one Gemini safety threshold for every safety category that `nbimg` sends. If omitted, `nbimg` does not send `safetySettings`.

Explicit levels serialize as `BLOCK_NONE`, `OFF`, `BLOCK_ONLY_HIGH`, `BLOCK_MEDIUM_AND_ABOVE`, or `BLOCK_LOW_AND_ABOVE`.

`--safety` controls only Gemini's adjustable request-level `safetySettings`. Gemini has additional built-in protections that may still block prompts, responses, or image generation. The exact image-generation behavior of `BLOCK_NONE` versus `OFF` is not defined by `nbimg`; both are exposed for API coverage.
