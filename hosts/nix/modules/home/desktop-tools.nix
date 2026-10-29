{ pkgs, nixcfgPath, ... }:

{
  xdg.desktopEntries = let
    terminalEntry = name: command: icon: {
      inherit name icon;
      exec = "${pkgs.foot}/bin/foot --app-id=nix-menu --title=Nix --hold ${command}";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
  in {
    bemoji = {
      name = "Emoji";
      exec = "quickshell -c expressive ipc call desktop toggle emoji";
      icon = "accessories-character-map";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    sunp = {
      name = "Blue-light filter";
      exec = "quickshell -c expressive ipc call desktop toggle night-light";
      icon = "indicator-weather";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    vpnp = {
      name = "VPN";
      exec = "quickshell -c expressive ipc call desktop toggle vpn";
      icon = "network-vpn";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    reboot = {
      name = "Reboot";
      exec = "quickshell -c expressive ipc call desktop toggle power";
      icon = "system-reboot";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
    shutdown = {
      name = "Shutdown";
      exec = "quickshell -c expressive ipc call desktop toggle power";
      icon = "system-shutdown";
      terminal = false;
      categories = [ "System" ];
      settings.OnlyShowIn = "X-DesktopTools;";
    };
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
