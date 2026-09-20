#!/usr/bin/env bash
set -euo pipefail
frame=${1:?usage: wallpaper-frame.sh /absolute/path/bin/wallpaper-frame}
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
for duration in 1 5; do
  video="$tmp/clip ' \$ $duration.mp4"
  full="$tmp/full $duration.png"
  thumb="$tmp/thumb $duration.png"
  ffmpeg -loglevel error -f lavfi -i "color=c=red:s=640x360:d=$duration" -y "$video"
  "$frame" "$video" "$full"
  test -s "$full"
  "$frame" "$video" "$thumb" -vf scale=256:-2
  test "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$thumb")" = 256,144
  before=$(stat -c %y "$full")
  "$frame" "$video" "$full"
  test "$(stat -c %y "$full")" = "$before"
  checksum=$(sha256sum "$full")
  printf 'invalid video\n' > "$video"
  touch -d 'next minute' "$video"
  if "$frame" "$video" "$full"; then
    echo 'Invalid video unexpectedly succeeded' >&2
    exit 1
  fi
  test "$(sha256sum "$full")" = "$checksum"
done
printf 'wallpaper-frame: short/long clips, thumbnail size, quoting, freshness and failed regeneration passed\n'
