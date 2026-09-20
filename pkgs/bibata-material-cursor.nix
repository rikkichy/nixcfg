{
  lib,
  src,
  stdenvNoCC,
  writeShellApplication,
  coreutils,
  librsvg,
  python3,
  xcursorgen,
}:


let
  tree = stdenvNoCC.mkDerivation {
    pname = "bibata-cursor-tree";
    version = "0-unstable-${builtins.substring 0 8 (src.rev or "00000000")}";
    inherit src;

    patches = [ ./bibata-parallel-render.patch ];

    postPatch = ''
      substituteInPlace config/build.toml \
        --replace-fail \
          'x11_sizes = [16, 20, 22, 24, 28, 32, 48, 64, 72, 84, 96]' \
          'x11_sizes = [12, 16, 18, 20, 22, 24, 28, 30, 32, 36, 42, 48, 54, 60, 64, 66, 72, 84, 96]'
    '';

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r src svg config $out/
      runHook postInstall
    '';

    meta = {
      description = "Bibata cursor renderer, artwork and render config";
      homepage = "https://github.com/rtgiskard/bibata_cursor";
      license = lib.licenses.gpl3Plus;
      platforms = lib.platforms.linux;
    };
  };

  tonal = ./bibata-tonal.py;
in

writeShellApplication {
  name = "bibata-material-render";

  runtimeInputs = [
    coreutils
    librsvg
    python3
    xcursorgen
  ];

  text = ''
    accent="''${1:?usage: bibata-material-render <accent-hex> <theme-dir> [hypr|x11]...}"
    dest="''${2:?usage: bibata-material-render <accent-hex> <theme-dir> [hypr|x11]...}"
    name="''${dest##*/}"
    shift 2

    formats=("$@")
    if [ "''${#formats[@]}" -eq 0 ]; then
      formats=(hypr x11)
    fi

    flags=()
    for format in "''${formats[@]}"; do
      case "$format" in
        hypr | x11) flags+=("--$format") ;;
        *)
          echo "bibata-material-render: unknown format '$format'" >&2
          exit 1
          ;;
      esac
    done

    colours=$(python3 ${tonal} "$accent")
    get() { printf '%s\n' "$colours" | sed -n "s/^$1=//p"; }

    body=$(get body)
    outline=$(get outline)
    watch=$(get watch)

    mkdir -p "$dest"
    work=$(mktemp -d "$(dirname "$dest")/.bibata-render.XXXXXX")
    trap 'rm -rf "$work"' EXIT

    cp -r ${tree}/. "$work/"
    chmod -R u+w "$work"
    cd "$work"

    cat > config/render.json <<EOF
    {
      "$name": {
        "desc": "Bibata, coloured from the current wallpaper",
        "dir": "svg/modern",
        "colors": [
          { "match": "#00FF00", "replace": "$body" },
          { "match": "#0000FF", "replace": "$outline" },
          { "match": "#FF0000", "replace": "$watch" }
        ]
      }
    }
    EOF

    python3 ./src/cursor_utils.py \
      "''${flags[@]}" --theme "$name" --out-dir out --log-level error

    for part in manifest.hl hyprcursors index.theme cursors; do
      [ -e "out/$name/$part" ] || continue

      rm -rf "$dest/.$part.new" "$dest/.$part.old"
      mv "out/$name/$part" "$dest/.$part.new"
      if [ -e "$dest/$part" ]; then
        mv "$dest/$part" "$dest/.$part.old"
      fi
      mv "$dest/.$part.new" "$dest/$part"
      rm -rf "$dest/.$part.old"
    done
  '';

  meta = {
    description = "Render a Bibata cursor theme from one accent colour";
    homepage = "https://github.com/SakibShahariar/material-bibata-cursor";
    license = with lib.licenses; [
      mit
      gpl3Plus
    ];
    mainProgram = "bibata-material-render";
    platforms = lib.platforms.linux;
  };
}
