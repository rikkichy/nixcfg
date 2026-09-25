{ lib, pkgs, ... }:

{
  home.packages = [ pkgs.hysteria ];
  xdg.configFile."hysteria/client.example.yaml".source =
    ../dotfiles/hysteria/client.example.yaml;

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "nixos-server" = {
        HostName = "nixos-server.local";
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
    if [ -f "$HOME/.ssh/nixos-server" ]; then
      run chmod 600 "$HOME/.ssh/nixos-server"
    fi
  '';
}
