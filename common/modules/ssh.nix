{ lib, ... }:

{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."nixos-server" = {
      HostName = "nixos-server.local";
      User = "ri";
      IdentityFile = "~/.ssh/nixos-server";
      IdentitiesOnly = true;
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
