{ lib, pkgs, ... }:

{
  home.packages = [ pkgs.hysteria ];
  xdg.configFile."hysteria/client.example.yaml".source =
    ../dotfiles/hysteria/client.example.yaml;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "r1" = {
        HostName = "r1.local";
        User = "root";
        IdentityFile = "~/.ssh/r1";
        IdentitiesOnly = true;
      };
      "r2" = {
        HostName = "r2.local";
        User = "root";
        IdentityFile = "~/.ssh/r2";
        IdentitiesOnly = true;
      };
      "nixos-server" = {
        HostName = "nixos-server.local";
        HostKeyAlias = "nixos-server.local";
        User = "ri";
        IdentityFile = "~/.ssh/nixos-server";
        IdentitiesOnly = true;
      };
      "nixos-server-remote" = {
        HostName = "127.0.0.1";
        Port = 2222;
        HostKeyAlias = "nixos-server.local";
        User = "ri";
        IdentityFile = "~/.ssh/nixos-server";
        IdentitiesOnly = true;
      };
    };
  };

  home.activation.sshPermissions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if [ -d "$HOME/.ssh" ]; then
      run chmod 700 "$HOME/.ssh"
    fi
    for key in "$HOME/.ssh/nixos-server" "$HOME/.ssh/r1" "$HOME/.ssh/r2"; do
      if [ -f "$key" ]; then
        run chmod 600 "$key"
      fi
    done
  '';
}
