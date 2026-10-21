{
  lib,
  stdenvNoCC,
  plymouth,
  keymap ? "us",
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "plymouth-theme-expressive";
  version = "1.0";
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    theme=$out/share/plymouth/themes/expressive
    mkdir -p "$theme" "$out/share/licenses/expressive"
    tar -xJf ${./assets.tar.xz}
    cp *.png "$theme/"
    install -Dm444 GoogleSansFlex.ttf "$out/share/fonts/truetype/GoogleSansFlex.ttf"
    cp ${plymouth}/share/plymouth/themes/spinner/{keyboard,capslock}.png "$theme/"
    cp ${./licenses}/* "$out/share/licenses/expressive/"
    cp ${plymouth.src}/COPYING "$out/share/licenses/expressive/plymouth-GPL-2.0"
    substitute ${./expressive.script} "$theme/expressive.script" \
      --replace-fail '@KEYMAP@' ${lib.escapeShellArg (builtins.toJSON keymap)}
    ln -s /run/plymouth/cryptroot-unlocked.png "$theme/cryptroot-unlocked.png"

    cat > "$theme/expressive.plymouth" <<EOF
    [Plymouth Theme]
    Name=Expressive
    Description=Material Expressive loading with native Plymouth authentication
    ModuleName=script

    [script]
    ImageDir=$theme
    ScriptFile=$theme/expressive.script
    EOF
    runHook postInstall
  '';

  passthru.font = "${finalAttrs.finalPackage}/share/fonts/truetype/GoogleSansFlex.ttf";

  meta = {
    description = "Native Plymouth script theme with static Material Expressive assets";
    license = with lib.licenses; [ gpl2Plus mit asl20 ofl ];
    platforms = lib.platforms.linux;
  };
})
