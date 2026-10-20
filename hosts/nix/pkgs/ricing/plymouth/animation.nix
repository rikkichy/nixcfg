{
  lib,
  fetchurl,
  runCommand,
  imagemagick,
  ffmpeg,
}:

let
  revision = "66b0eeb53afeb6025ffbbd37734b08e5bce197ed";
  upstream = "https://raw.githubusercontent.com/material-components/material-components-android/${revision}";
  animation = fetchurl {
    url = "${upstream}/docs/components/assets/loadingindicator/loading-indicator.gif";
    hash = "sha256-S4CdduizUMLkB8tPEERN/qmNXeeGIYDTw26AC3nefRQ=";
  };
  license = fetchurl {
    url = "${upstream}/LICENSE";
    hash = "sha256-z8d0m5b2O9McPEK1xHG/dWgUBT6EfBDz6wA0F7xSPTA=";
  };
in
runCommand "plymouth-expressive-animation"
  {
    nativeBuildInputs = [ imagemagick ffmpeg ];
    meta = {
      description = "Interpolated Material 3 Expressive loading indicator frames for Plymouth";
      homepage = "https://github.com/material-components/material-components-android/blob/${revision}/docs/components/LoadingIndicator.md";
      license = lib.licenses.asl20;
      platforms = lib.platforms.all;
    };
  }
  ''
    mkdir -p masks smooth "$out"
    # The reference capture repeats its first pose at frame 136; omit that pose
    # and the three trailing frames of the next cycle, rather than adding a pause.
    # Recover coverage from its green channel before interpolating the mask.
    magick ${animation} -coalesce -delete 136-139 \
      -channel G -separate +channel -level 32%,94% -negate \
      -filter Lanczos -resize 96x96 -depth 8 -scene 0 masks/frame-%04d.png
    # 136 source frames / 4.55 seconds = 2720/91 Hz. Keep the middle cycle so
    # interpolation also sees both sides of the loop boundary.
    # ponytail: interpolated motion is approximate; use vector assets if edge artifacts matter.
    ffmpeg -v error -framerate 2720/91 -stream_loop 2 -i masks/frame-%04d.png \
      -vf 'minterpolate=fps=240:scd=none:mc_mode=aobmc:me_mode=bidir:mb_size=4:vsbmc=1,trim=start_frame=1092:end_frame=2184,setpts=PTS-STARTPTS' \
      -fps_mode passthrough -start_number 0 smooth/frame-%04d.png
    magick smooth/frame-*.png \
      -background '#a8c7fa' -alpha Shape -strip \
      -set comment 'Adapted from Material Components for Android ${revision}, Apache-2.0: cropped to one cycle, motion-interpolated to 240 Hz, recolored, resized, and converted to transparent PNG.' \
      -define png:exclude-chunk=date,time -scene 0 \
      PNG32:"$out/throbber-%04d.png"
    install -Dm644 ${license} "$out/share/licenses/expressive-animation/LICENSE"
  ''
