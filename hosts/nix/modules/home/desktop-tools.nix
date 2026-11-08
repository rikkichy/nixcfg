{ pkgs, nixcfgPath, ... }:

{
  xdg.desktopEntries = let
    toolEntry = name: exec: icon: {
      inherit name exec icon;
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    terminalEntry = name: command: toolEntry name
      "${pkgs.foot}/bin/foot --app-id=nix-menu --title=Nix --hold ${command}";
  in {
    hyprpicker = toolEntry "Color picker" "${pkgs.hyprpicker}/bin/hyprpicker -a" "applications-graphics"
      // { categories = [ "Utility" ]; };
    bemoji = toolEntry "Emoji" "quickshell -c expressive ipc call desktop toggle emoji" "accessories-character-map";
    sunp = toolEntry "Blue-light filter" "quickshell -c expressive ipc call desktop toggle night-light" "indicator-weather";
    vpnp = toolEntry "VPN" "quickshell -c expressive ipc call desktop toggle vpn" "network-vpn";
    reboot = toolEntry "Reboot" "quickshell -c expressive ipc call desktop toggle power" "system-reboot";
    shutdown = toolEntry "Shutdown" "quickshell -c expressive ipc call desktop toggle power" "system-shutdown";
    wpp = toolEntry "Wallpaper" "wpp" "accessories-image-viewer";
    awpp = toolEntry "Animated wallpaper" "awpp" "totem";
    nix-switch = terminalEntry "Switch"
      ''nh os switch "${nixcfgPath}" --hostname nix --no-update-lock-file''
      "system-software-update";
    nix-update = terminalEntry "Update"
      ''nh os switch "${nixcfgPath}" --hostname nix --update''
      "system-software-install";
    nix-clean = terminalEntry "Clean"
      "nh clean all"
      "user-trash";
  };
}
