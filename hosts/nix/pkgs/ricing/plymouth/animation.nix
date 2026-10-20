{
  lib,
  fetchurl,
  runCommand,
  imagemagick,
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
    nativeBuildInputs = [ imagemagick ];
    meta = {
      description = "Official Material 3 Expressive loading indicator frames for Plymouth";
      homepage = "https://github.com/material-components/material-components-android/blob/${revision}/docs/components/LoadingIndicator.md";
      license = lib.licenses.asl20;
      platforms = lib.platforms.all;
    };
  }
  ''
    mkdir -p "$out"
    # The reference capture repeats its first pose at frame 136; omit that pose
    # and the three trailing frames of the next cycle, rather than adding a pause.
    # Native Plymouth must use THROBBER_DURATION=4.55 (seven 650ms transitions).
    # Recover coverage from the brown-on-cream GIF's green channel, clipping its
    # compression noise but retaining antialiased edges before downsampling.
    magick ${animation} -coalesce -delete 136-139 \
      -channel G -separate +channel -level 32%,94% -negate \
      -filter Lanczos -resize 96x96 \
      -background '#a8c7fa' -alpha Shape -strip \
      -set comment 'Adapted from Material Components for Android ${revision}, Apache-2.0: cropped to one cycle, recolored, resized, and converted to transparent PNG.' \
      -define png:exclude-chunk=date,time -scene 0 \
      PNG32:"$out/throbber-%04d.png"
    install -Dm644 ${license} "$out/share/licenses/expressive-animation/LICENSE"
  ''
