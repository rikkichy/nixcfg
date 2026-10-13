{ config, lib, pkgs, ... }:

{
  services.atticd = {
    # Enable only after DNS, public TCP 80/443 and /etc/attic/server.env provisioning.
    enable = false;
    environmentFile = "/etc/attic/server.env";
    settings = {
      listen = "127.0.0.1:8080";
      allowed-hosts = [ "cache.kror.net" ];
      api-endpoint = "https://cache.kror.net/";
      database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      storage = {
        type = "local";
        path = "/var/lib/atticd/storage";
      };
      compression.type = "zstd";
      garbage-collection = {
        interval = "12 hours";
        default-retention-period = "90 days";
      };
    };
  };

  environment.systemPackages = lib.optionals config.services.atticd.enable [
    pkgs.attic-client
    pkgs.openssl
    pkgs.jq
  ];

  services.nginx = lib.mkIf config.services.atticd.enable {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    virtualHosts."cache.kror.net" = {
      enableACME = true;
      forceSSL = true;
      # NAR uploads can exceed nginx's default 1 MiB body limit.
      extraConfig = "client_max_body_size 0;";
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
        extraConfig = ''
          proxy_request_buffering off;
          proxy_buffering off;
          proxy_read_timeout 600s;
          proxy_send_timeout 600s;
        '';
      };
    };
  };

  security.acme.acceptTerms = lib.mkIf config.services.atticd.enable true;
  networking.firewall.allowedTCPPorts =
    lib.optionals config.services.atticd.enable [ 80 443 ];
}
