{ pkgs, ... }:

let
  # Revoke the socket-file grant (its inode is pinned at sandbox start) in favour of the relay directory.
  discordIpcGrant = "--nofilesystem=xdg-run/discord-ipc-0 --filesystem=xdg-run/app/com.discordapp.Discord:create";
in
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
        $flatpak override --user ${discordIpcGrant} "$app"
      done
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

  # A Flatpak file grant pins the socket inode at sandbox start, so a later or restarted
  # Discord stays unreachable. Relay each connection to the live socket from a stable directory.
  systemd.user.sockets.opendeck-discord-ipc = {
    description = "Discord IPC relay for Flatpak apps";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = "%t/app/com.discordapp.Discord/discord-ipc-0";
      SocketMode = "0600";
    };
  };
  systemd.user.services.opendeck-discord-ipc = {
    description = "Discord IPC relay for Flatpak apps";
    serviceConfig.ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd %t/discord-ipc-0";
  };

  systemd.user.services.opendeck = {
    description = "OpenDeck controls";
    partOf = [ "graphical-session.target" ];
    requisite = [ "graphical-session.target" ];
    wants = [ "opendeck-discord-ipc.socket" ];
    after = [ "graphical-session.target" "opendeck-discord-ipc.socket" ];
    serviceConfig = {
      Type = "exec";
      ExecStartPre = "${pkgs.flatpak}/bin/flatpak override --user ${discordIpcGrant} me.amankhanna.opendeck";
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
