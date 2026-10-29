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
mkdir -p "$tmp/images" "$tmp/other" "$tmp/videos" "$tmp/other-videos" "$tmp/empty" "$XDG_RUNTIME_DIR"
reject() {
  if "$@" >"$tmp/out" 2>"$tmp/error"; then
    printf 'Unexpected success: %s\n' "$*" >&2
    exit 1
  fi
  test -s "$tmp/error"
  test ! -s "$tmp/out"
}
files=('quote" #%.png' $'line\nbreak.png' '-leading.png')
for file in "${files[@]}"; do cp -- "$image" "$tmp/images/$file"; done
ln -s -- "$image" "$tmp/images/link.png"
"$wpp" --list "$tmp/images" >"$tmp/list.json"
jq -e --arg dir "$tmp/images" '
  ([.[].path] == ([$dir + "/quote\" #%.png", $dir + "/line\nbreak.png", $dir + "/-leading.png"] | sort)) and
  all(.[]; .preview == .path and .name == (.path | split("/")[-1]) and (.revision | type == "string" and length > 0))
' "$tmp/list.json" >/dev/null
"$wpp" --list "$tmp/images" >"$tmp/repeated.json"
cmp "$tmp/list.json" "$tmp/repeated.json"
# A backdated edit and then a size-only change must each invalidate the UI cache.
touch -d '2000-01-01 UTC' -- "$tmp/images/${files[0]}"
"$wpp" --list "$tmp/images" >"$tmp/changed.json"
jq -e --slurpfile before "$tmp/list.json" '.[-1].revision != $before[0][-1].revision' "$tmp/changed.json" >/dev/null
touch -r "$tmp/images/${files[0]}" "$tmp/timestamp"
printf x >>"$tmp/images/${files[0]}"
touch -r "$tmp/timestamp" "$tmp/images/${files[0]}"
"$wpp" --list "$tmp/images" >"$tmp/resized.json"
jq -e --slurpfile before "$tmp/changed.json" '.[-1].revision != $before[0][-1].revision' "$tmp/resized.json" >/dev/null
cp -- "$image" "$tmp/other/${files[0]}"
"$wpp" --list "$tmp/other" >"$tmp/other.json"
jq -e --slurpfile first "$tmp/list.json" '.[0].preview as $preview | all($first[0][]; .preview != $preview)' "$tmp/other.json" >/dev/null
"$wpp" --list "$tmp/empty" >"$tmp/default.json"
jq -e 'length == 1 and (.[0] | (.path | startswith("/nix/store/")) and .name == "Built-in default" and .preview == .path and (.revision | length > 0))' "$tmp/default.json" >/dev/null
"$wpp" --list "$tmp/missing" >"$tmp/missing.json"
cmp "$tmp/default.json" "$tmp/missing.json"
reject "$awpp" --list "$tmp/empty"
for helper in "$wpp" "$awpp"; do
  for invalid in "$tmp/other/${files[0]}" "$tmp/images/missing.png" "$tmp/images/link.png"; do
    reject "$helper" --apply "$invalid" "$tmp/images"
  done
done

# Short clips exercise the frame helper's fallback from its three-second seek.
ffmpeg -nostdin -v error -f lavfi -i color=c=red:s=32x18:r=2 -t 1 -c:v ffv1 -threads 1 "$tmp/clip.mkv"
videos=('quote" #%.mkv' $'line\nbreak.mkv' '-leading.mkv')
for file in "${videos[@]}"; do cp -- "$tmp/clip.mkv" "$tmp/videos/$file"; done
cp -- "$tmp/clip.mkv" "$tmp/other-videos/${videos[0]}"
printf 'not a video' >"$tmp/videos/broken.mp4"
ln -s -- "$tmp/clip.mkv" "$tmp/videos/link.mkv"
"$awpp" --list "$tmp/videos" >"$tmp/videos.json"
jq -e --arg dir "$tmp/videos" '
  ([.[].path] == ([$dir + "/quote\" #%.mkv", $dir + "/line\nbreak.mkv", $dir + "/-leading.mkv", $dir + "/broken.mp4"] | sort)) and
  all(.[]; .preview == "" and .name == (.path | split("/")[-1] | sub("\\.[^.]*$"; "")) and (.revision | type == "string" and length > 0))
' "$tmp/videos.json" >/dev/null
"$awpp" --list "$tmp/videos" >"$tmp/repeated.json"
cmp "$tmp/videos.json" "$tmp/repeated.json"
for mode in --preview --apply; do
  for invalid in "$tmp/other-videos/${videos[0]}" "$tmp/videos/missing.mkv" "$tmp/videos/link.mkv" "$tmp/images/${files[0]}"; do
    reject "$awpp" "$mode" "$invalid" "$tmp/videos"
  done
done
# Neither listing nor rejected selection may create preview caches.
test ! -e "$XDG_CACHE_HOME"
for file in "${videos[@]}"; do
  "$awpp" --preview "$tmp/videos/$file" "$tmp/videos" >"$tmp/preview.json"
  preview=$(jq -er '.preview | select(startswith("/"))' "$tmp/preview.json")
  test -s "$preview"
  test "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$preview")" = '640,360'
done
video="$tmp/videos/${videos[0]}"
"$awpp" --preview "$video" "$tmp/videos" >"$tmp/selected.json"
preview=$(jq -er .preview "$tmp/selected.json")
cp -- "$preview" "$tmp/retained.png"
stamp=$(stat -c '%y' "$preview")
"$awpp" --preview "$video" "$tmp/videos" >"$tmp/reused.json"
cmp "$tmp/selected.json" "$tmp/reused.json"
test "$stamp" = "$(stat -c '%y' "$preview")"
"$awpp" --preview "$tmp/other-videos/${videos[0]}" "$tmp/other-videos" >"$tmp/isolated.json"
jq -e --slurpfile first "$tmp/selected.json" '.preview != $first[0].preview' "$tmp/isolated.json" >/dev/null
# Even an older source revision must not reuse the previous revision's frame.
touch -d '2000-01-01 UTC' -- "$video"
"$awpp" --list "$tmp/videos" >"$tmp/revised-videos.json"
jq -e --slurpfile before "$tmp/videos.json" '.[-1].revision != $before[0][-1].revision' "$tmp/revised-videos.json" >/dev/null
"$awpp" --preview "$video" "$tmp/videos" >"$tmp/revised-preview.json"
jq -e --slurpfile first "$tmp/selected.json" '.preview != $first[0].preview' "$tmp/revised-preview.json" >/dev/null
touch -r "$video" "$tmp/timestamp"
printf '\0' >>"$video"
touch -r "$tmp/timestamp" "$video"
"$awpp" --preview "$video" "$tmp/videos" >"$tmp/resized-preview.json"
jq -e --slurpfile first "$tmp/revised-preview.json" '.preview != $first[0].preview' "$tmp/resized-preview.json" >/dev/null
# Failed regeneration must preserve the previous frame and remove staging files.
preview=$(jq -er .preview "$tmp/resized-preview.json")
cp -- "$preview" "$tmp/retained.png"
size=$(stat -c %s "$video")
truncate -s 0 "$video"
truncate -s "$size" "$video"
touch -r "$tmp/timestamp" "$video"
touch -d '1970-01-01 UTC' "$preview"
reject "$awpp" --preview "$video" "$tmp/videos"
cmp "$tmp/retained.png" "$preview"
reject "$awpp" --preview "$tmp/videos/broken.mp4" "$tmp/videos"
test -z "$(find "$XDG_CACHE_HOME" -name '.frame.*' -print)"
# Warm listing must not regenerate a stale preview or touch any cache entry.
find "$XDG_CACHE_HOME" -printf '%p\0%T@:%s\0' >"$tmp/cache-before"
"$awpp" --list "$tmp/videos" >"$tmp/out"
find "$XDG_CACHE_HOME" -printf '%p\0%T@:%s\0' >"$tmp/cache-after"
cmp "$tmp/cache-before" "$tmp/cache-after"
printf 'PASS: metadata-only lists, revisions, lazy previews, filename round-trip, cache isolation and rejected selections\n'
