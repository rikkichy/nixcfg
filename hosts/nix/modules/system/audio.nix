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
      {
        matches = [
          { "node.name" = "alsa_input.usb-Solid_State_Logic_SSL_2__Mk_II-00.pro-input-0"; }
          { "node.name" = "alsa_output.usb-Solid_State_Logic_SSL_2__Mk_II-00.pro-output-0"; }
        ];
        # IRQ scheduling ties the graph to the hardware period, which can overrun osu!'s 10 ms audio request.
        actions.update-props."api.alsa.disable-tsched" = false;
      }
    ];
  };
}
