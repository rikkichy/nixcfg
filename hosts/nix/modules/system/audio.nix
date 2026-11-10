{ pkgs, ... }:

{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    extraLv2Packages = [ pkgs.lsp-plugins ];
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

    # Shure Nexadyne voice chain on SSL input 1: EQ, noise gate, compressor. No EasyEffects.
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
                # Levels below are dBFS inside the filter and depend on the SSL gain knob.
                # Measured room noise reached -50 dBFS RMS; close speech is about -28 dBFS
                # RMS. LSP zone/hysteresis values are relative to the threshold.
                {
                  type = "lv2";
                  name = "gate";
                  plugin = "http://lsp-plug.in/plugins/lv2/gate_mono";
                  control = {
                    scm = 1; # RMS detection
                    sla = 5.0; # ms lookahead keeps word onsets
                    gt = 0.006310; # opens at -44 dB
                    gz = 0.501187; # 6 dB opening zone
                    gh = 1;
                    ht = 0.501187; # closes at -50 dB
                    hz = 0.501187;
                    gr = 0.063096; # -24 dB when closed, not hard mute
                    at = 2.0;
                    hold = 150.0;
                    rt = 200.0;
                  };
                }
                {
                  type = "lv2";
                  name = "comp";
                  plugin = "http://lsp-plug.in/plugins/lv2/compressor_mono";
                  control = {
                    scm = 1; # RMS detection
                    sla = 5.0;
                    al = 0.050119; # -26 dB threshold
                    cr = 3.0;
                    kn = 0.501187; # 6 dB soft knee
                    at = 5.0;
                    rt = 120.0;
                    mk = 1.584893; # +4 dB makeup
                  };
                }
              ];
              links = [
                {
                  output = "preamp:Out";
                  input = "eq:In 1";
                }
                {
                  output = "eq:Out 1";
                  input = "gate:in";
                }
                {
                  output = "gate:out";
                  input = "comp:in";
                }
              ];
              inputs = [ "preamp:In" ];
              outputs = [ "comp:out" ];
            };

            "audio.channels" = 1;
            "audio.position" = [ "MONO" ];

            # Pro Audio exposes AUX channels; without an explicit AUX0 position
            # WirePlumber links a stereo stream to inputs 1 and 2.
            "capture.props" = {
              "node.name" = "capture.wave_dx_velvet_voice";
              "node.passive" = true;
              "audio.position" = [ "AUX0" ];
              "stream.dont-remix" = true;
            };

            "playback.props" = {
              "node.name" = "wave_dx_velvet_voice";
              "node.description" = "Shure Nexadyne";
              "media.class" = "Audio/Source";
              "filter.smart" = true;
              "filter.smart.name" = "wave-dx-velvet-voice";
              "filter.smart.target"."node.name" = "alsa_input.usb-Solid_State_Logic_SSL_2__Mk_II-00.pro-input-0";
            };
          };
        }
      ];
    };
  };
}
