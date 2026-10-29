#!/usr/bin/env bash
# Requires jq, ffmpeg and ffprobe. Pass built wpp and awpp executable paths.
set -euo pipefail
wpp=${1:?pass the built wpp executable}
awpp=${2:?pass the built awpp executable}
image="$(dirname "${BASH_SOURCE[0]}")/../hosts/nix/dotfiles/ricing/default-wallpaper.png"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache" XDG_RUNTIME_DIR="$tmp/run"
export WAYLAND_DISPLAY=unavailable DBUS_SESSION_BUS_ADDRESS="unix:path=$tmp/no-bus"
mkdir -p "$tmp/images" "$tmp/other-images" "$tmp/videos" "$tmp/other-videos" "$tmp/empty" "$XDG_RUNTIME_DIR"
reject() {
  if "$@" >"$tmp/out" 2>"$tmp/error"; then
    printf 'Unexpected success: %s\n' "$*" >&2
    exit 1
  fi
  test -s "$tmp/error"
  test ! -s "$tmp/out"
}
check_preview() {
  local preview
  preview=$(jq -er '.preview | select(startswith("/") and endswith(".jpg"))' "$1")
  test -s "$preview"
  ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height -of json "$preview" |
    jq -e '.streams | length == 1 and all(.[]; .codec_name == "mjpeg" and .width > 0 and .width <= 640 and .height > 0 and .height <= 360)' >/dev/null
}
cache_snapshot() {
  find "$XDG_CACHE_HOME" -printf '%p\0%T@:%s\0'
}
images=('quote" #%.png' $'line\nbreak.png' '-leading.png')
for file in "${images[@]}"; do cp -- "$image" "$tmp/images/$file"; done
ln -s -- "$image" "$tmp/images/link.png"
"$wpp" --list "$tmp/images" >"$tmp/images.json"
jq -e --arg dir "$tmp/images" '
  ([.[].path] == ([$dir + "/quote\" #%.png", $dir + "/line\nbreak.png", $dir + "/-leading.png"] | sort)) and
  all(.[]; .preview == "" and .name == (.path | split("/")[-1]) and (.revision | type == "string" and length > 0))
' "$tmp/images.json" >/dev/null
"$wpp" --list "$tmp/empty" >"$tmp/default.json"
jq -e 'length == 1 and (.[0] | (.path | startswith("/nix/store/")) and .name == "Built-in default" and .preview == "" and (.revision | length > 0))' "$tmp/default.json" >/dev/null
"$wpp" --list "$tmp/missing" >"$tmp/missing.json"
cmp "$tmp/default.json" "$tmp/missing.json"
reject "$awpp" --list "$tmp/empty"
reject "$awpp" --list "$tmp/missing"

# Short clips exercise fallback from the three-second keyframe seek.
ffmpeg -nostdin -v error -f lavfi -i color=c=red:s=1280x720:r=2 -t 1 -c:v ffv1 -threads 1 "$tmp/clip.mkv"
videos=('quote" #%.mkv' $'line\nbreak.mkv' '-leading.mkv')
for file in "${videos[@]}"; do cp -- "$tmp/clip.mkv" "$tmp/videos/$file"; done
printf 'not a video' >"$tmp/videos/broken.mp4"
ln -s -- "$tmp/clip.mkv" "$tmp/videos/link.mkv"
"$awpp" --list "$tmp/videos" >"$tmp/videos.json"
jq -e --arg dir "$tmp/videos" '
  ([.[].path] == ([$dir + "/quote\" #%.mkv", $dir + "/line\nbreak.mkv", $dir + "/-leading.mkv", $dir + "/broken.mp4"] | sort)) and
  all(.[]; .preview == "" and .name == (.path | split("/")[-1] | sub("\\.[^.]*$"; "")) and (.revision | type == "string" and length > 0))
' "$tmp/videos.json" >/dev/null
for kind in images videos; do
  if [ "$kind" = images ]; then helper="$wpp"; files=("${images[@]}"); source="$image"; extension=png
  else helper="$awpp"; files=("${videos[@]}"); source="$tmp/clip.mkv"; extension=mkv; fi
  cp -- "$source" "$tmp/other-$kind/${files[0]}"
  "$helper" --list "$tmp/$kind" >"$tmp/repeated.json"
  cmp "$tmp/$kind.json" "$tmp/repeated.json"
  for mode in --preview --apply; do
    for invalid in "$tmp/other-$kind/${files[0]}" "$tmp/$kind/missing.$extension" "$tmp/$kind/link.$extension"; do
      reject "$helper" "$mode" "$invalid" "$tmp/$kind"
    done
  done
done
# Neither listing nor rejected selection may create preview caches.
test ! -e "$XDG_CACHE_HOME"

for kind in images videos; do
  if [ "$kind" = images ]; then helper="$wpp"; files=("${images[@]}"); source="$image"
  else helper="$awpp"; files=("${videos[@]}"); source="$tmp/clip.mkv"; fi
  dir="$tmp/$kind"
  for file in "${files[@]}"; do
    "$helper" --preview "$dir/$file" "$dir" >"$tmp/preview.json"
    check_preview "$tmp/preview.json"
    preview=$(jq -er .preview "$tmp/preview.json")
    "$helper" --list "$dir" >"$tmp/warm.json"
    jq -e --arg path "$dir/$file" --arg preview "$preview" 'map(select(.path == $path)) | length == 1 and .[0].preview == $preview' "$tmp/warm.json" >/dev/null
  done
  selected="$dir/${files[0]}"
  "$helper" --preview "$selected" "$dir" >"$tmp/selected.json"
  preview=$(jq -er .preview "$tmp/selected.json")
  stamp=$(stat -c '%y' "$preview")
  "$helper" --preview "$selected" "$dir/." >"$tmp/reused.json"
  cmp "$tmp/selected.json" "$tmp/reused.json"
  test "$stamp" = "$(stat -c '%y' "$preview")"
  "$helper" --preview "$tmp/other-$kind/${files[0]}" "$tmp/other-$kind" >"$tmp/isolated.json"
  jq -e --slurpfile first "$tmp/selected.json" '.preview != $first[0].preview' "$tmp/isolated.json" >/dev/null
  cache_snapshot >"$tmp/cache-before"
  "$helper" --list "$dir" >"$tmp/warm.json"
  cache_snapshot >"$tmp/cache-after"
  cmp "$tmp/cache-before" "$tmp/cache-after"

  # Backdated edits and size-only changes each get a new revision and cache key.
  touch -d '2000-01-01 UTC' -- "$selected"
  "$helper" --list "$dir" >"$tmp/revised.json"
  jq -e --arg path "$selected" --slurpfile before "$tmp/$kind.json" '
    map(select(.path == $path))[0] as $entry |
    $entry.preview == "" and $entry.revision != ($before[0] | map(select(.path == $path))[0].revision)
  ' "$tmp/revised.json" >/dev/null
  "$helper" --preview "$selected" "$dir" >"$tmp/revised-preview.json"
  check_preview "$tmp/revised-preview.json"
  jq -e --slurpfile first "$tmp/selected.json" '.preview != $first[0].preview' "$tmp/revised-preview.json" >/dev/null
  touch -r "$selected" "$tmp/timestamp"
  printf '\0' >>"$selected"
  touch -r "$tmp/timestamp" "$selected"
  "$helper" --list "$dir" >"$tmp/resized.json"
  jq -e --arg path "$selected" --slurpfile before "$tmp/revised.json" '
    map(select(.path == $path))[0] as $entry |
    $entry.preview == "" and $entry.revision != ($before[0] | map(select(.path == $path))[0].revision)
  ' "$tmp/resized.json" >/dev/null
  "$helper" --preview "$selected" "$dir" >"$tmp/resized-preview.json"
  check_preview "$tmp/resized-preview.json"
  jq -e --slurpfile first "$tmp/revised-preview.json" '.preview != $first[0].preview' "$tmp/resized-preview.json" >/dev/null

  # Failed same-revision regeneration retains the old frame but lists never advertise it as fresh.
  preview=$(jq -er .preview "$tmp/resized-preview.json")
  cp -- "$preview" "$tmp/retained.jpg"
  size=$(stat -c %s "$selected")
  truncate -s 0 "$selected"
  truncate -s "$size" "$selected"
  touch -r "$tmp/timestamp" "$selected"
  touch -d '1970-01-01 UTC' "$preview"
  reject "$helper" --preview "$selected" "$dir"
  cmp "$tmp/retained.jpg" "$preview"
  test -z "$(find "$XDG_CACHE_HOME" -name '.frame.*' -print)"
  cache_snapshot >"$tmp/cache-before"
  "$helper" --list "$dir" >"$tmp/stale.json"
  jq -e --arg path "$selected" 'map(select(.path == $path)) | length == 1 and .[0].preview == ""' "$tmp/stale.json" >/dev/null
  cache_snapshot >"$tmp/cache-after"
  cmp "$tmp/cache-before" "$tmp/cache-after"
  cp -- "$source" "$selected"
  printf '\0' >>"$selected"
  touch -r "$tmp/timestamp" "$selected"
  "$helper" --preview "$selected" "$dir" >"$tmp/retry.json"
  cmp "$tmp/resized-preview.json" "$tmp/retry.json"
  check_preview "$tmp/retry.json"
  test "$selected" -ot "$preview"
done
reject "$awpp" --preview "$tmp/videos/broken.mp4" "$tmp/videos"

# Portrait bounds and collection names containing newlines must survive every cache/list round trip.
odd_dir="$tmp/"$'portrait "#%\n'
mkdir -p "$odd_dir"
ffmpeg -nostdin -v error -f lavfi -i color=c=blue:s=720x1280 -frames:v 1 -threads 1 "$odd_dir/tall.png"
"$wpp" --preview "$odd_dir/tall.png" "$odd_dir" >"$tmp/portrait.json"
check_preview "$tmp/portrait.json"
"$wpp" --list "$odd_dir" >"$tmp/portrait-list.json"
jq -e --arg path "$odd_dir/tall.png" --slurpfile preview "$tmp/portrait.json" 'length == 1 and .[0].path == $path and .[0].preview == $preview[0].preview' "$tmp/portrait-list.json" >/dev/null
builtin=$(jq -er '.[0].path' "$tmp/default.json")
for dir in "$tmp/empty" "$tmp/missing"; do
  "$wpp" --preview "$builtin" "$dir" >"$tmp/builtin-preview.json"
  check_preview "$tmp/builtin-preview.json"
  "$wpp" --list "$dir" >"$tmp/builtin-list.json"
  jq -e --slurpfile preview "$tmp/builtin-preview.json" 'length == 1 and .[0].preview == $preview[0].preview' "$tmp/builtin-list.json" >/dev/null
done
test ! -e "$tmp/missing"
test -z "$(find "$XDG_CACHE_HOME" -name '.frame.*' -print)"
printf 'PASS: metadata-only cold/warm lists, bounded JPEG previews, revisions, retries, filename round-trip, isolation and rejected selections\n'
