{ pkgs, ... }:

{
  imports = [
    ../../common/modules/nh.nix
    ./hardware.nix
    ../../common/modules/nixos-yubikey.nix
    ../../common/modules/nixos-limine.nix
    ../../common/modules/nixos-networking.nix
    ./modules/system/services.nix
    ./modules/system/hysteria.nix
    ./modules/system/minecraft.nix
  ];

  networking.hostName = "nixos-server";
  networking.useDHCP = false; # NetworkManager owns DHCP.
  networking.firewall.enable = true;

  services.avahi.publish = {
    enable = true;
    addresses = true;
  };

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      AllowAgentForwarding = true;
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  security.pam = {
    rssh = {
      enable = true;
      settings = {
        # Trust the root-controlled SSH key inventory, never a user-writable file.
        auth_key_file = "/etc/ssh/authorized_keys.d/$user";
        cue = true;
      };
    };
    services.sudo.rssh = true;
    services.sudo-i.rssh = true;
  };

  boot.loader.timeout = 5;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  programs.fish.enable = true;
  environment.systemPackages = with pkgs; [ git vim pam_u2f ghostty.terminfo ];
  users.users.ri = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAILf+Jn/kb+/9xR8dND9SjvG6k1hS+jcQImmzyp3LAFDwAAAABHNzaDo= ri@nixos-server"
    ];
  };

  system.stateVersion = "26.05";
}
