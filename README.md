# Batch Processing of Images to do OCR on macOS

`batch-ocr` is a native Swift command-line tool that recognizes text in images using the
Apple Vision framework and writes the recognized text to a `.txt` file with the same name
as each image. It processes single files or whole directories (optionally recursive),
runs OCR tasks in parallel, and skips images that already have output.

The original AppleScript helper, `process_image.scpt`, is kept in this repository as legacy.

> IMPORTANT: Runs on macOS 13+ (Ventura or newer). Built with Swift 6. <br>
> _Script inspired by [this](https://www.macscripter.net/t/image-png-to-text-through-applescript/74490/27) thread_ <br>

## Build

```shell
git clone https://github.com/felipe-dos-santos81/mac-batch-ocr.git
cd mac-batch-ocr
swift build -c release
# binary: .build/release/batch-ocr
```

> Note: `swift test` requires the Testing framework — full Xcode works out of the box; Command-Line-Tools-only setups may need the framework symlinked into the CLT SDK.

## Makefile

Common targets: `make build`, `make test`, `make release`, `make install`, `make run ARGS="--help"`, `make clean`, `make help`.

## Usage

### Help

```shell
batch-ocr --help
```

### Single image

```shell
batch-ocr "/my/images/image.png"
```

### Directory (batch)

```shell
batch-ocr "/my/images"
```

### Recursive, parallel, custom languages and output folder

```shell
batch-ocr -r -j 8 -l pt-BR -c -o "/my/output" "/my/images"
```

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

Note: with `-r` and `-o`, images that share a base name across different subdirectories write to the same `.txt` file (last write wins).

Exit codes: `0` all processed, `1` finished with per-file failures, `2` usage/config error.

## Legal Disclaimer

This script is provided “as-is” without any warranty, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, or non-infringement.

The author(s) of this script are not liable for any damages or issues arising from the use of this script. Use it at your own risk.

## Trademark Disclaimer:

macOS and Vision are trademarks of Apple Inc., registered in the U.S. and other countries. This project is in no way affiliated with or endorsed by Apple Inc.

All other trademarks and service marks are the property of their respective owners.

## Legacy AppleScript (process_image.scpt)

Single image:

```shell
osascript /my/script/process_image.scpt "/my/images/image.png"
```

Multiple images:

```shell
find /my/images \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -type f -exec \
    bash -c 'p="$(realpath "{}")"; [[ ! "$p" =~ ^\./ ]] && osascript /my/script/process_image.scpt "$p" \;
```

Execution log is generated as `/my/script/process_image_log.txt`
