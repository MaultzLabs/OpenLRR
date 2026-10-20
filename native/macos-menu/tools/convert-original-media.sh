#!/usr/bin/env bash
# Optional offline conversion of user-owned retail audio/video for native macOS.
# Never modifies the source, installs Windows codecs, downloads files, or
# commits/redistributes game assets.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: bash tools/convert-original-media.sh <original AVI/OGG file or folder> [output folder]

Converts legacy game .avi videos -> H.264/AAC .mp4 and .ogg soundtrack
-> AAC .m4a via a locally installed FFmpeg (https://ffmpeg.org).
WAV files already work natively and are deliberately left unchanged.
The original files are never overwritten.
Default output: ~/Library/Application Support/RockRaidersNativeMenu/ConvertedMedia
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then usage; exit 0; fi
if (( $# < 1 || $# > 2 )); then usage >&2; exit 2; fi
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo 'FFmpeg not found. Install an official FFmpeg build or use: brew install ffmpeg' >&2
  exit 2
fi

src="$1"
dest="${2:-$HOME/Library/Application Support/RockRaidersNativeMenu/ConvertedMedia}"
if [[ ! -e "$src" ]]; then echo "Missing input: $src" >&2; exit 2; fi
if [[ ! -f "$src" && ! -d "$src" ]]; then echo 'Input must be a file or folder.' >&2; exit 2; fi
mkdir -p "$dest"

convert_one() {
  local file="$1" relative="$2"
  local ext
  ext="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  local destination
  case "$ext" in
    avi) destination="$dest/${relative%.*}.mp4" ;;
    ogg) destination="$dest/${relative%.*}.m4a" ;;
    *) return 0 ;;
  esac
  mkdir -p "$(dirname "$destination")"
  if [[ -e "$destination" ]]; then
    printf 'Skipping existing conversion: %s\n' "$destination"
    return 0
  fi
  printf 'Converting %s -> %s\n' "$file" "$destination"
  if [[ "$ext" == avi ]]; then
    ffmpeg -nostdin -n -hide_banner -loglevel warning -i "$file" \
      -map '0:v:0' -map '0:a:0?' -c:v libx264 -crf 19 -preset medium \
      -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$destination"
  else
    ffmpeg -nostdin -n -hide_banner -loglevel warning -i "$file" \
      -map '0:a:0' -vn -c:a aac -b:a 192k "$destination"
  fi
}

if [[ -f "$src" ]]; then
  convert_one "$src" "$(basename "$src")"
else
  src="${src%/}"
  while IFS= read -r -d '' file; do
    convert_one "$file" "${file#"$src"/}"
  done < <(find "$src" -type f \( -iname '*.avi' -o -iname '*.ogg' \) -print0)
fi

printf 'Converted media is available privately under: %s\n' "$dest"
