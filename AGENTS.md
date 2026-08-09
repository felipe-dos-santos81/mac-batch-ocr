# AGENTS.md

Swift 6 CLI (`batch-ocr`) that batch-OCRs images via Apple Vision. SwiftPM, macOS 13+ floor, tools 6.0 (strict concurrency).

## Commands

```shell
swift build -c release        # binary: .build/release/batch-ocr
swift test                    # full suite (Swift Testing)
swift test --filter <name>    # single test, e.g. --filter concurrencyIsCappedByJobs
swift test --sanitize=thread  # required after touching BatchProcessor/concurrency
make build|test|test-tsan|release|install|run|clean|help   # Makefile wrappers
```

No CI and no lint/format toolchain configured.

## Toolchain gotcha

`swift test` fails on Command-Line-Tools-only machines (`no such module '_Testing_Foundation'`): the Testing framework ships with full Xcode. Either use full Xcode or symlink `Testing.framework` (and its `_Testing_*` companions) from the Xcode SDK into the CLT SDK dirs — this machine needed that workaround.

## Architecture

Executable target `BatchOCR` (product `batch-ocr`); tests `@testable import BatchOCR`. Flow: `BatchOCRCommand` (ArgumentParser, maps flags → `OCRConfig` + `RecognitionSettings`) → `FileDiscovery` → `BatchProcessor` (sliding-window TaskGroup capped at `--jobs`, dispatches `OCRJob` per file) → `Reporter`. OCR lives only in `VisionOCREngine` behind the `OCREngine: Sendable` protocol — tests inject `MockEngine`. Exit codes are a contract: 0 ok, 1 per-file failures, 2 usage/config errors. Domain vocabulary: see `CONTEXT.md`.

## Hard rules

- Exactly one external dependency: `swift-argument-parser`. Do not add more.
- No code comments unless documenting a non-obvious Vision/API quirk.
- Everything crossing task boundaries stays `Sendable`; all stdout/stderr/log writes happen in the parent `group.next()` loop, never in child tasks.
- Test fixtures are rendered at runtime via `FixtureFactory` (CoreGraphics). Never commit binary images.
- `Reporter` output is machine-readable: keep `en_US_POSIX` locale for `elapsed=` and log timestamps. Format is pinned by `ReporterTests` (line renderers are static funcs on `Reporter`; I/O goes through injected `TextOutputStream` sinks).
- `.agent/`, `.superpowers/`, and `docs/` are gitignored scratch/artifact dirs — never commit anything from them.
- Short imperative commit messages (repo style).

## Traps

- `-c` flag: `languageCorrection` must keep `[.customShort("c"), .long]`. `.shortAndLong` derives `-l` from "languageCorrection" and collides with `--language`, crashing all parsing.
- `-v` is a custom flag handled in `validate()` via `CleanExit.message(...)`. Don't move it into `run()` — later `run()` rewrites would silently regress it.
- `--language` defaults to `[]` with fallback to `["en"]` (default of `RecognitionSettings.languages`) in `makeConfig()`; don't give the option a non-empty default (ArgumentParser array-default semantics).
- Empty recognition result is outcome `.empty` (no file written, exit 0) — legacy-compatible; don't turn it into a failure.
- `print(_:to:)` with an `any TextOutputStream & Sendable` existential crashes the installed swift-frontend (IRGen signal 11, Swift 6.3.3 CLT). Write directly via `var s = sink; s.write(...)` in `Reporter.write(_:to:)`; don't reintroduce `print(to:)`.
- `docs/superpowers/` (spec/plan) is gitignored and local-only — reference it if present, never commit or rewrite it.
