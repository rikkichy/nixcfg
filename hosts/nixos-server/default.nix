{ pkgs, ... }:

{
  imports = [
    ./hardware.nix
    ../../common/modules/nixos-yubikey.nix
  ];

  networking.hostName = "nixos-server";
  networking.useDHCP = true;
  networking.firewall.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 5;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = with pkgs; [ git vim pam_u2f ];
  users.users.ri = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  system.stateVersion = "26.05";
}
