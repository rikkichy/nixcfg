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

# Renders one Bibata cursor theme from one accent colour, at the moment the
# wallpaper changes.
#
# Two upstreams meet here. rtgiskard/bibata_cursor is the renderer and the
# artwork: its SVGs carry three placeholder colours, and config/render.json
# names the substitution that turns them into a variant.
# SakibShahariar/material-bibata-cursor is the design on top -- it establishes
# that the three want to be an M3 Container/Primary pair plus a near-black
# disc, ships 28 triples chosen that way, and drives the renderer from a
# matugen post-hook that matches a wallpaper to the nearest of them.
#
# The matching is what is left out. Every other themed file on this machine is
# rendered from the palette rather than selected from a set, and the accent
# matugen derives is already an M3 role, so bibata-tonal.py computes the triple
# from it instead. That is what makes the colour range unbounded rather than
# 28 wide -- see the header of that file for how the targets were calibrated
# against the 28.

let
  # The renderer, its artwork, and the config that binds them, patched for the
  # two things this machine needs differently and installed as data: nothing
  # here is a build, since the colours are not known until a wallpaper is
  # chosen.
  tree = stdenvNoCC.mkDerivation {
    pname = "bibata-cursor-tree";
    version = "0-unstable-${builtins.substring 0 8 (src.rev or "00000000")}";
    inherit src;

    patches = [ ./bibata-parallel-render.patch ];

    # material-bibata-cursor's size list, and its reasoning: these are every
    # exact pixel size a 24px cursor lands on across 0.5x-3x display scaling,
    # so a scaled monitor gets a rendered bitmap rather than one resampled
    # from the nearest size. It costs ~0.6s and 10 MB over upstream's eleven,
    # which is worth not having to remember when a second monitor arrives.
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

  # The renderer resolves config/, svg/ and --out-dir relative to the working
  # directory and writes into all three, so a store path cannot be rendered
  # from in place. The tree is small; what the run produces is not.
  #
  # That working copy is made beside the destination rather than in /tmp so
  # the install is a rename within one filesystem instead of a 30 MB copy
  # across two.
  #
  # Both formats land in one directory under one name -- manifest.hl and
  # hyprcursors/ for Hyprland, index.theme and cursors/ for everything reading
  # XCURSOR_PATH -- rather than two themes that would have to be kept in step.
  # The two halves are disjoint, which is what lets either be asked for alone
  # and installed without disturbing the other: each of the four entries is
  # moved aside and replaced in turn, so the theme is complete and valid at
  # every point rather than absent for the length of a copy.
  #
  # Naming no format renders both, which is what a run by hand wants.
  # cursor-apply asks for them one at a time, for reasons that belong with it.
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

    # render.json is replaced rather than edited. Upstream's copy describes
    # twelve variants this machine will never build, and the key a theme is
    # filed under is the name that reaches the generated manifest.hl and
    # index.theme -- so writing the one entry is also what names the output,
    # where patching a borrowed entry would leave both to be renamed after.
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

    # Whichever of the four the run produced. The staging names are dotted so
    # that a theme directory scanned mid-install offers nothing but the theme
    # itself, and cleared first so a killed run leaves nothing to trip over.
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
    # The scripts adapted here are MIT, but what they produce is a recolour of
    # Bibata's artwork and carries its licence.
    license = with lib.licenses; [
      mit
      gpl3Plus
    ];
    mainProgram = "bibata-material-render";
    platforms = lib.platforms.linux;
  };
}
