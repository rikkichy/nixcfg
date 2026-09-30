{ config, ... }:

let
  hostKey = "/etc/secrets/initrd/ssh_host_ed25519_key";
  passwordAgent = "${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent";
in
{
  boot.initrd = {
    # ponytail: common wired NICs only; add the actual driver for other hardware.
    availableKernelModules = [
      "e1000e"
      "igb"
      "igc"
      "r8169"
      "r8152"
      "ax88179_178a"
      "cdc_ether"
      "cdc_ncm"
      "virtio_net"
    ];

    systemd = {
      enable = true;
      storePaths = [ passwordAgent ];
      network = {
        enable = true;
        # Network access is optional: console/FIDO unlock must work without a cable.
        wait-online.enable = false;
        networks."10-unlock-wired" = {
          matchConfig.Type = "ether";
          networkConfig = {
            DHCP = "ipv4";
            IPv6AcceptRA = false;
            LinkLocalAddressing = false;
          };
        };
      };
    };

    network.ssh = {
      enable = true;
      port = 2222;
      # A string path lets Limine append this secret outside the Nix store.
      hostKeys = [ hostKey ];
      authorizedKeys = config.users.users.ri.openssh.authorizedKeys.keys;
      authorizedKeyFiles = [ ];
      # Restrict SSH, not root's shell: local console recovery remains available.
      extraConfig = ''
        AllowUsers root
        PermitRootLogin prohibit-password
        AddressFamily inet
        AuthenticationMethods publickey
        PubkeyAuthentication yes
        ForceCommand ${passwordAgent} --query
        DisableForwarding yes
        PermitTunnel no
        X11Forwarding no
        PermitUserRC no
      '';
    };
  };

  system.preSwitchChecks.initrdSshHostKey = ''
    if [ ! -s ${hostKey} ]; then
      echo "Provision the dedicated initrd SSH host key at ${hostKey} before switching." >&2
      exit 1
    fi
  '';
}
