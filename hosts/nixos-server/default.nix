{ pkgs, ... }:

{
  imports = [
    ../../common/modules/nh.nix
    ./hardware.nix
    ../../common/modules/nixos-yubikey.nix
  ];

  networking.hostName = "nixos-server";
  networking.useDHCP = true;
  networking.firewall.enable = true;

  services.openssh = {
    enable = true;
    openFirewall = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
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
