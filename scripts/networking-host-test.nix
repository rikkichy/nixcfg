# Run: nix eval --impure --file scripts/networking-host-test.nix
let
  flake = builtins.getFlake ("path:" + toString ../.);
  inherit (flake.inputs.nixpkgs) lib;
  desktop = flake.nixosConfigurations.nix.config;
  server = flake.nixosConfigurations.nixos-server.config;
  hasVpn = config: builtins.any (p: lib.getName p == "vpn") config.environment.systemPackages;
in
assert desktop.services.mihomo.enable;
assert desktop.systemd.services ? mihomo-config;
assert desktop.systemd.services ? mihomo;
assert hasVpn desktop;
assert builtins.elem "mihomo" desktop.networking.firewall.trustedInterfaces;
assert builtins.elem "interface-name:mihomo" desktop.networking.networkmanager.unmanaged;
assert !server.services.mihomo.enable;
assert !(server.systemd.services ? mihomo-config);
assert !(server.systemd.services ? mihomo);
assert !(server.systemd.services ? sops-install-secrets);
assert !(hasVpn server);
assert !(builtins.elem "mihomo" server.networking.firewall.trustedInterfaces);
assert !(builtins.elem "interface-name:mihomo" server.networking.networkmanager.unmanaged);
assert server.networking.networkmanager.enable;
assert server.services.avahi.enable;
"PASS: VPN is desktop-only; server retains NetworkManager and Avahi"
