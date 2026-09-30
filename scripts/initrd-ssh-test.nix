# Run with the repository's pinned nixpkgs, not a channel:
# nixpkgs=$(nix eval --raw 'path:.#nixosConfigurations.nixos-server.pkgs.path')
# nix-build scripts/initrd-ssh-test.nix --no-out-link --arg pkgs "import $nixpkgs {}"
{ pkgs }:
let
  # Disposable transport credentials only; generated in the build sandbox, never
  # checked in. This does not emulate or claim physical FIDO authentication.
  clientKey = pkgs.runCommand "initrd-ssh-test-client-key" { nativeBuildInputs = [ pkgs.openssh ]; } ''
    mkdir -p "$out"
    ssh-keygen -q -t ed25519 -N "" -f "$out/id_ed25519"
  '';
  unlock = pkgs.writeText "initrd-ssh-test-unlock.exp" ''
    set timeout 60
    spawn -noecho ssh -tt -p 2222 -i /etc/test-client-key \
      -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
      -o UserKnownHostsFile=/tmp/initrd-known-hosts \
      root@192.168.1.100 {printf UNRESTRICTED_COMMAND}
    expect {
      "UNRESTRICTED_COMMAND" { exit 1 }
      "Please enter passphrase for disk cryptroot" {}
      timeout { exit 2 }
      eof { exit 3 }
    }
    send -- "[lindex $argv 0]\r"
    expect {
      "UNRESTRICTED_COMMAND" { exit 4 }
      timeout { exit 5 }
      eof {}
    }
  '';
in
pkgs.testers.runNixOSTest {
  name = "server-initrd-ssh-luks";

  nodes = {
    server =
      { lib, pkgs, ... }:
      {
        virtualisation = {
          emptyDiskImages = [ 512 ];
          useBootLoader = true;
          useEFIBoot = true;
          # Match upstream systemd-initrd-luks-password: the encrypted root is
          # real, while the test system closure stays on the shared store.
          mountHostNixStore = true;
        };
        boot.loader = {
          limine.enable = true;
          limine.efiSupport = true;
          efi.canTouchEfiVariables = true;
          timeout = 0;
        };
        boot.initrd.systemd.enable = true;
        networking.useDHCP = false;
        environment.systemPackages = [ pkgs.cryptsetup pkgs.openssh ];

        specialisation.remote-unlock.configuration = {
          imports = [ ../hosts/nixos-server/modules/system/initrd-ssh.nix ];
          users.users.ri = {
            isNormalUser = true;
            openssh.authorizedKeys.keys = [ (builtins.readFile "${clientKey}/id_ed25519.pub") ];
          };
          boot.initrd.luks.devices = lib.mkVMOverride {
            cryptroot.device = "/dev/vdb";
          };
          virtualisation.rootDevice = "/dev/mapper/cryptroot";
        };
      };

    client =
      { pkgs, ... }:
      {
        environment.systemPackages = [ pkgs.openssh pkgs.netcat-openbsd pkgs.expect ];
        environment.etc."test-client-key" = {
          source = "${clientKey}/id_ed25519";
          mode = "0600";
        };
        # Real DHCP on the isolated test VLAN exercises production initrd
        # networkd rather than bypassing it with a static initrd address.
        services.dnsmasq = {
          enable = true;
          settings = {
            interface = "eth1";
            bind-interfaces = true;
            port = 0;
            dhcp-range = [ "192.168.1.100,192.168.1.100,255.255.255.0,1h" ];
          };
        };
        networking.firewall.allowedUDPPorts = [ 67 ];
      };
  };

  testScript =
    { nodes, ... }:
    let
      encryptedSystem = nodes.server.specialisation.remote-unlock.configuration.system.build.toplevel;
    in
    ''
      import shlex
      from datetime import timedelta

      start_all()
      client.wait_for_unit("dnsmasq.service")
      server.wait_for_unit("multi-user.target")

      # Only VM-local disposable state is formatted or provisioned.
      server.succeed("printf test-unlock | cryptsetup luksFormat -q --iter-time=1 /dev/vdb -")
      server.succeed("printf test-unlock | cryptsetup luksOpen -q /dev/vdb cryptroot")
      server.succeed("mkfs.ext4 /dev/mapper/cryptroot")
      server.succeed("install -d -m 0700 /etc/secrets/initrd")
      server.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /etc/secrets/initrd/ssh_host_ed25519_key")
      host_public = server.succeed("cat /etc/secrets/initrd/ssh_host_ed25519_key.pub").strip()
      client.succeed("printf '%s\\n' " + shlex.quote("[192.168.1.100]:2222 " + host_public) + " > /tmp/initrd-known-hosts")
      client.succeed("ssh-keygen -q -t ed25519 -N \"\" -f /tmp/unauthorized")

      # Limine must append the runtime-only host key to the encrypted boot's
      # initrd. No host key is supplied directly through the test module.
      server.succeed("nix-env --profile /nix/var/nix/profiles/system --set ${encryptedSystem}")
      server.succeed("${encryptedSystem}/bin/switch-to-configuration boot")
      server.succeed("sync")
      server.crash()
      server.start()
      server.wait_for_console_text("Please enter passphrase for disk cryptroot", timeout=timedelta(seconds=90))
      client.wait_until_succeeds("nc -z 192.168.1.100 2222", timeout=timedelta(seconds=90))

      with subtest("unauthorized transport credential is rejected"):
          status, _ = client.execute(
              "ssh -p 2222 -i /tmp/unauthorized -o BatchMode=yes -o IdentitiesOnly=yes "
              "-o ConnectTimeout=5 -o StrictHostKeyChecking=yes "
              "-o UserKnownHostsFile=/tmp/initrd-known-hosts root@192.168.1.100 true"
          )
          assert status == 255, status

      authorized_ssh = (
          "ssh -p 2222 -i /etc/test-client-key -o BatchMode=yes -o IdentitiesOnly=yes "
          "-o ConnectTimeout=5 -o StrictHostKeyChecking=yes "
          "-o UserKnownHostsFile=/tmp/initrd-known-hosts "
      )
      with subtest("forwarding requests are rejected"):
          status, _ = client.execute("timeout 10 " + authorized_ssh + "-W 127.0.0.1:2222 root@192.168.1.100")
          assert status == 255, status
          status, _ = client.execute(
              "timeout 10 " + authorized_ssh
              + "-o ExitOnForwardFailure=yes -N -R 12345:127.0.0.1:2222 root@192.168.1.100"
          )
          assert status == 255, status

      with subtest("wrong passphrase does not release encrypted root"):
          client.succeed("expect ${unlock} deliberately-wrong")
          server.wait_for_console_text("Failed to activate with specified passphrase", timeout=timedelta(seconds=30))

      with subtest("forced password agent ignores arbitrary command and unlocks root"):
          # A fresh real cryptroot prompt after the wrong answer proves that
          # authentication alone and the previous passphrase did not unlock it.
          client.succeed("expect ${unlock} test-unlock")
          server.wait_for_unit("multi-user.target")
          assert server.succeed("findmnt -n -o SOURCE /").strip() == "/dev/mapper/cryptroot"
    '';
}
