{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # MK1 shares its capture/playback clock. Avoid idle transitions and renegotiation.
    wireplumber.extraConfig."51-wave-xlr-mk1"."monitor.alsa.rules" = [
      {
        matches = [
          { "node.name" = "~alsa_(input|output)[.]usb-Elgato_Systems_Elgato_Wave_XLR_.*"; }
        ];
        actions.update-props = {
          "session.suspend-timeout-seconds" = 0;
          "node.pause-on-idle" = false;
          "audio.rate" = 48000;
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
              "filter.smart.target" = {
                "alsa.card_name" = "Elgato Wave XLR";
                "media.class" = "Audio/Sink";
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

    # Wave DX on Elgato Wave XLR: warm voice EQ, no EasyEffects.
    # Smart filtering targets the capture source of the Elgato card.
    extraConfig.pipewire."91-wave-dx-velvet-voice" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "Shure Nexadyne";
            "media.name" = "Shure Nexadyne";

            "filter.graph" = {
              nodes = [
                {
                  type = "builtin";
                  name = "preamp";
                  label = "linear";
                  control = {
                    Mult = 0.794328; # -2 dB headroom
                    Add = 0.0;
                  };
                }
                {
                  type = "builtin";
                  name = "eq";
                  label = "param_eq";
                  config.filters = [
                    { type = "bq_highpass"; freq = 75.0; gain = 0.0; q = 0.71; }
                    { type = "bq_lowshelf"; freq = 135.0; gain = 1.5; q = 0.71; }
                    { type = "bq_peaking"; freq = 280.0; gain = -2.5; q = 1.0; }
                    { type = "bq_peaking"; freq = 900.0; gain = -1.0; q = 1.1; }
                    { type = "bq_peaking"; freq = 3500.0; gain = -1.8; q = 1.0; }
                    { type = "bq_highshelf"; freq = 8000.0; gain = -1.0; q = 0.71; }
                  ];
                }
              ];
              links = [
                {
                  output = "preamp:Out";
                  input = "eq:In 1";
                }
              ];
              inputs = [ "preamp:In" ];
              outputs = [ "eq:Out 1" ];
            };

            "audio.channels" = 1;
            "audio.position" = [ "MONO" ];

            "capture.props" = {
              "node.name" = "capture.wave_dx_velvet_voice";
              "node.passive" = true;
            };

            "playback.props" = {
              "node.name" = "wave_dx_velvet_voice";
              "node.description" = "Shure Nexadyne";
              "media.class" = "Audio/Source";
              "filter.smart" = true;
              "filter.smart.name" = "wave-dx-velvet-voice";
              "filter.smart.target" = {
                "alsa.card_name" = "Elgato Wave XLR";
                "media.class" = "Audio/Source";
              };
            };
          };
        }
      ];
    };
  };
}
