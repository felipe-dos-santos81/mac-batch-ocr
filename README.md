# Batch OCR for macOS

`batch-ocr` is a Swift command-line tool that recognizes text in images using the Apple
Vision framework and writes one `.txt` per image, named after it. It processes single
files or whole directories (optionally recursive), runs OCR in parallel, and skips images
that already have output.

Requires macOS 13+ and Swift 6. Inspired by [this thread](https://www.macscripter.net/t/image-png-to-text-through-applescript/74490/27).

## Build

```shell
git clone https://github.com/felipe-dos-santos81/mac-batch-ocr.git
cd mac-batch-ocr
swift build -c release   # binary: .build/release/batch-ocr
```

Makefile shortcuts: `make build`, `make test`, `make release`, `make install`,
`make run ARGS="--help"`, `make clean`, `make help`.

> `swift test` needs the Testing framework: full Xcode works out of the box;
> Command-Line-Tools-only setups may need it symlinked into the CLT SDK.

## Usage

```shell
batch-ocr image.png                               # single image
batch-ocr /my/images                              # every image in a directory
batch-ocr -r -j 8 -l pt-BR -c -o out /my/images   # recursive, 8 jobs, Portuguese, output dir
```

Each `foo.png` produces `foo.txt` (beside the image, or in `--output-dir`). Re-running
skips images whose `.txt` already exists; use `--overwrite` to force.

### Flags

```
-d, --detect-language          Automatically detect the language. Default is disabled.
-l, --language <code>          Recognition language, repeatable (BCP-47, e.g. en-US). Default: en.
-c, --language-correction      Enable language correction. Default is disabled.
-o, --output-dir <dir>         Write all .txt outputs into this directory.
-r, --recursive                Recurse into subdirectories.
-j, --jobs <n>                 Max concurrent OCR tasks. Default: 4.
    --extensions <csv>         Image extensions to include. Default: png,jpg,jpeg,tif,tiff,heic,webp.
    --overwrite                Re-OCR images even if a non-empty .txt output already exists.
    --log-file <path>          Append leveled log lines to this file.
-q, --quiet                    Suppress per-file progress lines.
-v, --version                  Print version.
```

With `-r` and `-o`, images sharing a base name across subdirectories write to the same
`.txt` (last write wins).

Exit codes: `0` all processed, `1` finished with per-file failures, `2` usage/config error.

## Legal Disclaimer

This script is provided “as-is” without any warranty, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, or non-infringement.

The author(s) of this script are not liable for any damages or issues arising from the use of this script. Use it at your own risk.

## Trademark Disclaimer:

macOS and Vision are trademarks of Apple Inc., registered in the U.S. and other countries. This project is in no way affiliated with or endorsed by Apple Inc.

All other trademarks and service marks are the property of their respective owners.
