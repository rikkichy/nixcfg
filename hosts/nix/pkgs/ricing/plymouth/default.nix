{
  lib,
  stdenvNoCC,
  callPackage,
  fetchurl,
  google-sans-rounded,
  plymouth,
  python3,
}:

let
  animation = callPackage ./animation.nix { };
  materialRevision = "49d4db35df873165d6bd6ba09b063c7dafbac2f4";
  lock = fetchurl {
    url = "https://raw.githubusercontent.com/google/material-design-icons/${materialRevision}/symbols/web/lock/materialsymbolsrounded/lock_wght600_48px.svg";
    hash = "sha256-mc5OAVIzTtC/k9H0PlFg0AnSb9iVGURFP9p/THfWUN8=";
  };
  materialLicense = fetchurl {
    url = "https://raw.githubusercontent.com/google/material-design-icons/${materialRevision}/LICENSE";
    hash = "sha256-WNHhf/5RCaeuKWyq/K39vmp9F28LxKsB4SpomwSZ2L0=";
  };
  python = python3.withPackages (ps: [
    ps.fonttools
    ps.cairosvg
  ]);
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "plymouth-theme-expressive";
  version = "1.0";
  dontUnpack = true;
  nativeBuildInputs = [ python ];

  buildPhase = ''
    runHook preBuild
    python - <<'PY'
    from xml.etree import ElementTree
    import cairosvg
    from fontTools.ttLib import TTFont
    from fontTools.varLib.instancer import instantiateVariableFont

    font = TTFont("${google-sans-rounded}/share/fonts/truetype/GoogleSansRounded-Regular.ttf")
    # The rounded outlines are already baked in; retain every other axis default.
    axes = {axis.axisTag: axis.defaultValue for axis in font["fvar"].axes}
    axes["wght"] = 600
    instantiateVariableFont(font, axes, inplace=True)
    # Do not let the source variable font's Rounded/Regular names override weight 600.
    names = {
        1: "Google Sans Flex Rounded", 2: "Semibold",
        3: "GoogleSansFlexRounded-Semibold-600",
        4: "Google Sans Flex Rounded Semibold",
        6: "GoogleSansFlexRounded-Semibold",
        16: "Google Sans Flex Rounded", 17: "Semibold",
        21: "Google Sans Flex Rounded", 22: "Semibold",
    }
    for name_id, value in names.items():
        font["name"].removeNames(nameID=name_id)
        font["name"].setName(value, name_id, 3, 1, 0x409)
        font["name"].setName(value, name_id, 1, 0, 0)
    font["name"].removeNames(nameID=25)
    if "STAT" in font:
        del font["STAT"]
    font["OS/2"].usWeightClass = 600
    font["OS/2"].fsSelection &= ~((1 << 5) | (1 << 6))
    font["head"].macStyle &= ~1
    font.save("GoogleSansRounded-Semibold.ttf")

    icon = ElementTree.parse("${lock}")
    icon.getroot().set("fill", "#a8c7fa")
    svg = ElementTree.tostring(icon.getroot())
    cairosvg.svg2png(bytestring=svg, write_to="material-lock.png", output_width=96, output_height=96)
    cairosvg.svg2png(bytestring=svg, write_to="lock.png", output_width=48, output_height=48)
    PY
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    theme=$out/share/plymouth/themes/expressive
    mkdir -p "$theme" "$out/share/licenses/expressive"
    install -Dm444 GoogleSansRounded-Semibold.ttf \
      "$out/share/fonts/truetype/GoogleSansRounded-Semibold.ttf"
    cp lock.png ${animation}/throbber-*.png "$theme/"
    cp material-lock.png "$theme/watermark.png"
    cp ${plymouth}/share/plymouth/themes/spinner/{entry,bullet,keyboard,keymap-render,capslock}.png "$theme/"
    cp ${google-sans-rounded.src}/LICENSE "$out/share/licenses/expressive/font-OFL"
    cp ${materialLicense} "$out/share/licenses/expressive/material-symbols-Apache-2.0"
    cp ${plymouth.src}/COPYING "$out/share/licenses/expressive/plymouth-GPL-2.0"
    cp -r ${animation}/share/licenses/. "$out/share/licenses/"

    cat > "$theme/expressive.plymouth" <<EOF
    [Plymouth Theme]
    Name=Expressive
    Description=Material Expressive loading with native Plymouth authentication
    ModuleName=two-step

    [two-step]
    ImageDir=$theme
    Font=Google Sans Flex Rounded Semibold 16
    TitleFont=Google Sans Flex Rounded Semibold 20
    DialogHorizontalAlignment=.5
    DialogVerticalAlignment=.5
    TitleHorizontalAlignment=.5
    TitleVerticalAlignment=.5
    HorizontalAlignment=.5
    VerticalAlignment=.72
    WatermarkHorizontalAlignment=.5
    WatermarkVerticalAlignment=.25
    BackgroundStartColor=0x111318
    BackgroundEndColor=0x111318
    ProgressBarBackgroundColor=0x111318
    ProgressBarForegroundColor=0xa8c7fa
    Transition=none
    MessageBelowAnimation=true

    [boot-up]
    UseAnimation=true
    UseEndAnimation=false
    SuppressMessages=false
    Title=System is encrypted.
    SubTitle=Verify your identity.

    [shutdown]
    UseAnimation=true
    UseEndAnimation=false
    SuppressMessages=false

    [reboot]
    UseAnimation=true
    UseEndAnimation=false
    SuppressMessages=false
    EOF
    runHook postInstall
  '';

  passthru.font = "${finalAttrs.finalPackage}/share/fonts/truetype/GoogleSansRounded-Semibold.ttf";

  meta = {
    description = "Native Plymouth theme with Material Rounded lock and Expressive loading";
    license = with lib.licenses; [ gpl2Plus asl20 ofl ];
    platforms = lib.platforms.linux;
  };
})
