{ pkgs, ... }:

{
  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;
    extraLv2Packages = [ pkgs.lsp-plugins ];
    extraLadspaPackages = [ pkgs.deepfilternet ];
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
                    Mult = 0.446684; # -7 dB, matches the bass shelf gain to avoid clipping
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
                    Gain = 7.0;
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

    # SSL input 1 as a clean mono mic: DeepFilterNet removes keyboard/mouse noise
    # (Krisp's job), then a gate mutes what remains between words (Discord's
    # input-sensitivity job). Select "SSL Mic" in applications.
    extraConfig.pipewire."91-ssl-mic" = {
      "context.modules" = [
        {
          name = "libpipewire-module-filter-chain";
          args = {
            "node.description" = "SSL Mic";
            "media.name" = "SSL Mic";

            "filter.graph" = {
              nodes = [
                {
                  type = "ladspa";
                  name = "denoise";
                  plugin = "libdeep_filter_ladspa";
                  label = "deep_filter_mono";
                }
                # Thresholds are dBFS on input 1 and move with the SSL gain knob. Measured
                # after DeepFilterNet: speech -27..-18 dB RMS, leaked clicks up to -42 dB.
                # LSP zone/hysteresis values are relative to the threshold.
                {
                  type = "lv2";
                  name = "gate";
                  plugin = "http://lsp-plug.in/plugins/lv2/gate_mono";
                  control = {
                    scm = 1; # RMS detection
                    sla = 5.0; # ms lookahead keeps word onsets
                    gt = 0.015849; # fully open above -36 dB, closed below -42 dB
                    gz = 0.501187; # 6 dB opening zone
                    gh = 1;
                    ht = 0.501187; # closes 6 dB lower
                    hz = 0.501187;
                    gr = 0.001; # -60 dB when closed
                    at = 2.0;
                    hold = 200.0;
                    rt = 150.0;
                  };
                }
              ];
              links = [
                {
                  output = "denoise:Audio Out";
                  input = "gate:in";
                }
              ];
              inputs = [ "denoise:Audio In" ];
              outputs = [ "gate:out" ];
            };

            "audio.channels" = 1;
            "audio.position" = [ "MONO" ];

            # Pro Audio exposes AUX channels; AUX0 without remixing reads input 1 only.
            "capture.props" = {
              "node.name" = "capture.ssl_mic";
              "node.passive" = true;
              "audio.position" = [ "AUX0" ];
              "stream.dont-remix" = true;
              "target.object" = "alsa_input.usb-Solid_State_Logic_SSL_2__Mk_II-00.pro-input-0";
              "node.dont-fallback" = true;
            };

            "playback.props" = {
              "node.name" = "ssl_mic";
              "node.description" = "SSL Mic";
              "media.class" = "Audio/Source";
            };
          };
        }
      ];
    };
  };
}
