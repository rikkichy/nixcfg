{ config, pkgs, nixcfgPath, ... }:

{
  programs.git.config.safe.directory = nixcfgPath;

  system.autoUpgrade = {
    enable = true;
    operation = "boot";
    flake = nixcfgPath;

    flags = [
      "--update-input" "nixpkgs"
      "--update-input" "home-manager"
      "--update-input" "vhelper"
      "--update-input" "openwave"
      "--update-input" "helium"
      "--update-input" "omp"
      "--update-input" "tg-ws-proxy"
    ];
    dates = "daily";
    randomizedDelaySec = "10min";
  };

  systemd.services.nixos-upgrade-notify = {
    description = "HalruneNix upgrade notification";
    serviceConfig.Type = "oneshot";
    script = ''
      user=ri
      uid=$(${pkgs.coreutils}/bin/id -u "$user")

      wl=$(cd /run/user/"$uid" && ls -d wayland-[0-9] 2>/dev/null | head -1)
      asuser() {
        ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
          HOME="/home/$user" \
          LANG=${config.i18n.defaultLocale} \
          PATH=${config.nix.package}/bin \
          XDG_RUNTIME_DIR=/run/user/"$uid" \
          WAYLAND_DISPLAY="$wl" \
          DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/"$uid"/bus \
          "$@"
      }

      booted="$(readlink -f /run/booted-system)"
      built="$(readlink -f /nix/var/nix/profiles/system)"
      if [ "$booted" = "$built" ]; then
        asuser ${pkgs.libnotify}/bin/notify-send "HalruneNix" "Update successful." || true
        exit 0
      fi

      round=0
      while [ "$round" -lt 10 ]; do
        round=$((round + 1))
        choice=$(asuser ${pkgs.coreutils}/bin/timeout 15m \
          ${pkgs.libnotify}/bin/notify-send -u critical \
            -A view="View changes" \
            -A reboot="Reboot now" \
            "HalruneNix" "Update requires reboot.") || true
        case "$choice" in
          reboot)
            ${pkgs.systemd}/bin/systemctl reboot
            exit 0
            ;;
          view)
            asuser ${pkgs.foot}/bin/foot --app-id=nix-menu \
              --title="nix: pending update" --hold \
              ${pkgs.nvd}/bin/nvd diff "$booted" "$built" || true
            ;;
          *) exit 0 ;;
        esac
      done
    '';
  };
  systemd.services.nixos-upgrade.onSuccess = [ "nixos-upgrade-notify.service" ];

  systemd.services.nixos-upgrade-failed = {
    description = "HalruneNix upgrade failure notification";
    serviceConfig.Type = "oneshot";
    script = ''
      user=ri
      uid=$(${pkgs.coreutils}/bin/id -u "$user")
      ${pkgs.util-linux}/bin/runuser -u "$user" -- ${pkgs.coreutils}/bin/env \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus \
        ${pkgs.libnotify}/bin/notify-send -u critical \
          "HalruneNix" "Update failed — journalctl -u nixos-upgrade" || true
    '';
  };
  systemd.services.nixos-upgrade.onFailure = [ "nixos-upgrade-failed.service" ];
}
