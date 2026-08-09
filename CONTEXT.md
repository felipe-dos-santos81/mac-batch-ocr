# Domain vocabulary — mac-batch-ocr

Terms pinned during the architecture review of 2026-08-09. Use these names in code,
tests, and conversation; add a term here when a concept earns its name.

## Core terms

- **Image** — a source image to OCR (input of the pipeline).
- **.txt output** — the OCR result file; one per image, UTF-8.
- **Output routing** — the rule mapping an image to its .txt output: beside the image
  by default, into `--output-dir` when given. Name collisions across nested dirs are
  last-write-wins (documented, not handled).
- **Skip** — an image whose non-empty .txt output already exists is not re-OCR'd
  unless `--overwrite`; a skipped image is a `.skipped` outcome, never a failure.
- **Discovery** — expanding CLI paths into a sorted, deduped image list (extension
  filter, recursion). Fails with `DiscoveryError` for missing paths.
- **Recognition** — running Apple Vision over one image to produce text. Governed by
  **RecognitionSettings** (languages, language correction, auto-detect).
- **RecognitionSettings** — the recognition-only configuration bag consumed by the
  engine interface. Distinct from **OCRConfig**, the batch orchestration bag (jobs,
  overwrite, outputDir, recursive, extensions).
- **OCR job** — the per-file pipeline: route output, apply the skip rule, recognize,
  write the .txt, classify. Its interface is `run() -> FileResult`; the outcome enum
  (`ok` / `skipped` / `empty` / `failed`) is the single result type.
- **Window** — the sliding-window concurrency runner (TaskGroup capped at `--jobs`)
  in BatchProcessor; it only dispatches OCR jobs and reports results in the parent loop.
- **Summary / progress / log lines** — the Reporter's machine-readable contract:
  `done= skipped= empty= failed= elapsed=` (en_US_POSIX), `[i/N] label path` progress,
  and timestamped `[LEVEL]` log lines.
- **Exit codes** — 0 all processed; 1 batch finished with per-file failures; 2 usage or
  config error.

## Modules

| Module | Interface | Purpose |
|---|---|---|
| `FileDiscovery` | `discover(paths:recursive:extensions:)` | Expand paths to images |
| `OCRJob` | `run() -> FileResult` | Per-file pipeline |
| `BatchProcessor` | `run(files:) -> BatchSummary` | Windowed dispatch + summary |
| `VisionOCREngine` | `recognize(imageURL:settings:)` | Vision adapter behind `OCREngine` |
| `Reporter` | `progress` / `summary` | Line formats + sinks |
| `OutputPath` | `forImage` / `hasExistingOutput` | Output naming + existence check |
