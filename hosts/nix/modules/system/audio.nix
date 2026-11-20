{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Pinned alsa-ucm-conf 1.2.16.1 mistakes the 2+ Mk II for the plain 2 Mk II
    # (fixed upstream in 4367278). Use the smallest ACP duplex profile instead.
    wireplumber.extraConfig."51-ssl2-profile"."monitor.alsa.rules" = [
      {
        matches = [ { "device.name" = "alsa_card.usb-Solid_State_Logic_SSL_2__Mk_II-00"; } ];
        actions.update-props = {
          "api.alsa.use-ucm" = false;
          "device.profile" = "output:analog-surround-21+input:analog-surround-71";
        };
      }
    ];

    extraConfig.pipewire."91-ssl-mic"."context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          # The SSL's other capture channels include hardware playback loopback.
          "capture.props" = {
            "node.name" = "capture.ssl_mic";
            "target.object" = "alsa_input.usb-Solid_State_Logic_SSL_2__Mk_II-00.analog-surround-71";
            "audio.position" = [ "FL" ];
            "stream.dont-remix" = true;
            "node.passive" = true;
            "node.dont-fallback" = true;
          };
          "playback.props" = {
            "node.name" = "ssl_mic";
            "node.description" = "SSL Mic (Input 1)";
            "media.class" = "Audio/Source";
            "audio.position" = [ "MONO" ];
          };
        };
      }
    ];
  };
}
