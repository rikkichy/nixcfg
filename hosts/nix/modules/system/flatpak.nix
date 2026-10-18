{ pkgs, ... }:

{
  services.flatpak.enable = true;

  systemd.user.services.flatpak-bootstrap = {
    description = "Install the Flatpak apps this config expects";
    unitConfig.OnSuccess = [ "opendeck-autostart.service" ];
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "10min";
    };
    script = ''
      set -eu
      flatpak=${pkgs.flatpak}/bin/flatpak
      $flatpak remote-add --user --if-not-exists flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo
      for app in org.vinegarhq.Sober me.amankhanna.opendeck; do
        $flatpak install --user -y --noninteractive flathub "$app"
      done

      $flatpak override --user --filesystem=xdg-run/discord-ipc-0 \
        me.amankhanna.opendeck
    '';
  };

  systemd.user.timers.flatpak-bootstrap = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnStartupSec = "2min";
      AccuracySec = "1min";
    };
  };

  # Keep the launch request active for the session, even if OpenDeck exits or
  # fails before bootstrap completes. A second start then does nothing.
  systemd.user.services.opendeck-autostart = {
    description = "Start installed OpenDeck once per graphical session";
    wantedBy = [ "graphical-session.target" ];
    partOf = [ "graphical-session.target" ];
    requisite = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    unitConfig.ConditionPathExists = "%h/.local/share/flatpak/app/me.amankhanna.opendeck/current/active";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/systemctl --user --no-block start opendeck.service";
    };
  };

  systemd.user.services.opendeck = {
    description = "OpenDeck controls";
    partOf = [ "graphical-session.target" ];
    requisite = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "exec";
      ExecStartPre = "${pkgs.flatpak}/bin/flatpak override --user --filesystem=xdg-run/discord-ipc-0 me.amankhanna.opendeck";
      ExecStart = "${pkgs.flatpak}/bin/flatpak run --user me.amankhanna.opendeck --hide";
      Slice = "session.slice";
    };
  };

  systemd.user.services.flatpak-update = {
    description = "Update Flatpak apps";
    serviceConfig.Type = "oneshot";
    script = "${pkgs.flatpak}/bin/flatpak update --user -y --noninteractive";
  };
  systemd.user.timers.flatpak-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "15min";
      Persistent = true;
    };
  };
}
