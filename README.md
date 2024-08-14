# Bach OCR on macOS

Apple Script used as a helper to process an image file and writing the recognized text to a text file.
The recognized text is written to a text file with the same name as the image file but with a .txt extension.

The script uses the Vision framework to recognize text in the image.

> IMPORTANT: This script runs only on macOS 10.13+ <br>
> Tested on macOS Sonoma 14.6+

##	Legal Disclaimer

This script is provided “as-is” without any warranty, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose, or non-infringement.

The author(s) of this script are not liable for any damages or issues arising from the use of this script. Use it at your own risk.

## Trademark Disclaimer:

macOS and Vision are trademarks of Apple Inc., registered in the U.S. and other countries. This project is in no way affiliated with or endorsed by Apple Inc.

All other trademarks and service marks are the property of their respective owners.


## Usage:

### Help

```shell
osascript /my/script/process_image.scpt --help
```

### Single image

```shell
osascript /my/script/process_image.scpt "/my/images/image.png"
```

### Multiple images

```shell
find /my/images \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) -type f -exec \
    bash -c 'p="$(realpath "{}")"; [[ ! "$p" =~ ^\./ ]] && osascript /my/script/process_image.scpt "{}" \;
```

#### Where:
- `/my/images` is the folder to scan for image(s)
- `/my/script` The path this script was added

Execution log is generated as `/my/script/process_image_log.txt`
