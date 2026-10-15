{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    extraConfig.pipewire."90-blessing3-eq" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "Blessing 3 EQ";
            "media.name" = "Blessing 3 EQ";

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
              "node.description" = "Blessing 3 EQ";
              "media.class" = "Audio/Sink";
              "filter.smart" = true;
              "filter.smart.name" = "blessing3-eq";
              "filter.smart.target" = {
                "alsa.card_name" = "Elgato Wave XLR";
              };
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
