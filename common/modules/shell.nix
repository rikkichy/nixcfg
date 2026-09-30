{ config, osConfig, lib, pkgs, ... }:

{
  home.packages = with pkgs; [
    sops age
    btop git gh wget
    starship zoxide eza fzf bat ripgrep lazygit jq fastfetch micro
    file unzip
    matugen
    nerd-fonts.departure-mono
  ];

  fonts.fontconfig.enable = pkgs.stdenv.hostPlatform.isLinux;

  home.file.".omp/agent/rules/nixcfg-host.md".text = ''
    ---
    alwaysApply: true
    ---
    # Local configured identity

    - Local configured host: ${osConfig.networking.hostName} (${pkgs.stdenv.hostPlatform.system})
    - Configured primary user: ${config.home.username}
    - Configuration model: ${if pkgs.stdenv.hostPlatform.isDarwin then "nix-darwin" else "NixOS"} + Home Manager
    - Configured desktop: ${if pkgs.stdenv.hostPlatform.isDarwin then "macOS desktop" else if osConfig.programs.hyprland.enable then "Hyprland (Wayland)" else "none"}

    These values identify the local installed Nix configuration, not the current
    process user, session working directory or a remote SSH target. Verify live
    identity when an operation depends on it.
  '';

  home.file.".omp/agent/extensions/nixcfg-execution.js".source =
    ../dotfiles/omp/nixcfg-execution.js;

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fish = {
    enable = true;
    shellAbbrs = {
      lg = "lazygit";
      pic = "omp --continue";
      pir = "omp --resume";
      gd = "git diff";
      ga = "git add .";
      gc = "git commit -am";
      gl = "git log";
      gs = "git status";
      gst = "git stash";
      gsp = "git stash pop";
      gp = "git push";
      gpl = "git pull";
      gsw = "git switch";
      gsm = "git switch main";
      gb = "git branch";
      gbd = "git branch -d";
      gco = "git checkout";
      gsh = "git show";
      l = "ls";
      ll = "ls -l";
      la = "ls -a";
      lla = "ls -la";
    };
    shellAliases.ls = "eza --icons --group-directories-first -1";

    interactiveShellInit = lib.mkMerge [
      (lib.mkOrder 1490 ''
        starship init fish | source
        zoxide init fish --cmd cd | source
      '')
      (lib.mkOrder 1492 ''
        function mark_prompt_start --on-event fish_prompt
            echo -en "\e]133;A\e\\"
        end

        source $HOME/.config/fish/user-config.fish 2> /dev/null
      '')
    ];

    functions.fish_greeting = ''
      fastfetch --key-padding-left 5
    '';
  };

  xdg.configFile = {
    "starship.toml".source = ../dotfiles/starship.toml;
    "btop/btop.conf".source = ../dotfiles/btop.conf;
    "fastfetch/config.jsonc".source = ../dotfiles/fastfetch.jsonc;
    "micro/settings.json".text = ''
      {
          "colorscheme": "simple"
      }
    '';
  };
}
