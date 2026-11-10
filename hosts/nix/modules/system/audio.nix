{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Pinned alsa-ucm-conf 1.2.16.1 mistakes the 2+ Mk II for the plain 2 Mk II
    # (fixed upstream in 4367278); Pro Audio needs no UCM.
    wireplumber.extraConfig."51-ssl2-pro-audio"."monitor.alsa.rules" = [
      {
        matches = [ { "device.name" = "alsa_card.usb-Solid_State_Logic_SSL_2__Mk_II-00"; } ];
        actions.update-props = {
          "api.alsa.use-ucm" = false;
          "device.profile" = "pro-audio";
        };
      }
    ];

    extraConfig.pipewire."90-blessing3-eq" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "BriseAudio Fugaku";
            "media.name" = "BriseAudio Fugaku";

            "filter.graph" = {
              nodes = [
                {
                  type = "builtin";
                  name = "preamp";
                  label = "linear";
                  control = {
                    Mult = 0.630957;
                    Add = 0.0;
                  };
                }
                {
                  type = "builtin";
                  name = "bass";
                  label = "bq_lowshelf";
                  control = {
                    Freq = 105.0;
                    Q = 0.70;
                    Gain = 4.0;
                  };
                }
              ];
              links = [
                {
                  output = "preamp:Out";
                  input = "bass:In";
                }
              ];
            };

            "audio.channels" = 2;
            "audio.position" = [ "FL" "FR" ];

            "capture.props" = {
              "node.name" = "blessing3_eq";
              "node.description" = "BriseAudio Fugaku";
              "media.class" = "Audio/Sink";
              "filter.smart" = true;
              "filter.smart.name" = "blessing3-eq";
            };

            "playback.props" = {
              "node.name" = "blessing3_eq_output";
              "node.passive" = true;
              "stream.dont-remix" = true;
            };
          };
        }
      ];
    };
  };
}
