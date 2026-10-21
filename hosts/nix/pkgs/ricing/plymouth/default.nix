{
  lib,
  stdenv,
  callPackage,
  fetchurl,
  google-sans-rounded,
  plymouth,
  harfbuzz,
  pkg-config,
  qt6,
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
  # The pinned Rounded source has no Semibold file. HarfBuzz performs the
  # instancing; its name-override API requires this package-local build option.
  fontHarfbuzz = (harfbuzz.override { withIntrospection = false; }).overrideAttrs (old: {
    mesonFlags = old.mesonFlags ++ [ "-Dexperimental_api=true" ];
  });
in
stdenv.mkDerivation (finalAttrs: {
  pname = "plymouth-theme-expressive";
  version = "1.0";
  dontUnpack = true;
  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ qt6.qtbase qt6.qtsvg fontHarfbuzz ];
  dontWrapQtApps = true;

  buildPhase = ''
    runHook preBuild
    $CXX -std=c++17 -O2 -fPIC ${./render-assets.cpp} -o render-assets \
      $(pkg-config --cflags --libs Qt6Svg Qt6Xml)
    $CXX -std=c++17 -O2 -DHB_EXPERIMENTAL_API ${./instance-font.cpp} -o instance-font \
      $(PKG_CONFIG_PATH=${lib.getDev fontHarfbuzz}/lib/pkgconfig:$PKG_CONFIG_PATH pkg-config --cflags --libs harfbuzz-subset)
    ./instance-font \
      ${google-sans-rounded}/share/fonts/truetype/GoogleSansRounded-Regular.ttf \
      GoogleSansRounded-Semibold.ttf
    ./render-assets ${lock}
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    theme=$out/share/plymouth/themes/expressive
    mkdir -p "$theme" "$out/share/licenses/expressive"
    install -Dm444 GoogleSansRounded-Semibold.ttf \
      "$out/share/fonts/truetype/GoogleSansRounded-Semibold.ttf"
    cp lock.png entry.png bullet.png unlock-success.png ${animation}/throbber-*.png "$theme/"
    cp material-lock.png "$theme/watermark.png"
    cp ${plymouth}/share/plymouth/themes/spinner/{keyboard,keymap-render,capslock}.png "$theme/"
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
    license = with lib.licenses; [ gpl2Plus mit asl20 ofl ];
    platforms = lib.platforms.linux;
  };
})
