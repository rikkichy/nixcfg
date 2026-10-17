{ config, osConfig, lib, pkgs, nixcfgPath, ... }:
let
  tooling = import ./language-servers.nix { inherit lib pkgs osConfig nixcfgPath; };
  ompTooling = pkgs.writeText "omp-tooling.yml" ''
    astGrep:
      enabled: true
    lsp:
      diagnosticsOnEdit: true
      diagnosticsOnWrite: true
  '';
  omp = pkgs.writeShellScriptBin "omp" ''
    exec ${lib.getExe pkgs.bun} x --bun --package @oh-my-pi/pi-coding-agent@latest omp --config ${ompTooling} "$@"
  '';
in

{
  home.packages = with pkgs; [
    omp
    sops age
    btop git gh wget
    eza fzf bat ripgrep lazygit jq fastfetch micro
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

  home.file.".omp/agent/lsp.json".text = builtins.toJSON {
    servers = lib.mapAttrs (_: server: server // {
      settings = server.settings or { };
    }) tooling.servers // {
      # Use the same selected servers as Zed, even when alternatives are on PATH.
      nil.disabled = true;
      pyright.disabled = true;
      pylsp.disabled = true;
      ty.disabled = true;
      typescript-native.disabled = true;
    };
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableIonIntegration = false;
    enableNushellIntegration = false;
  };

  programs.zoxide = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableNushellIntegration = false;
    options = [ "--cmd cd" ];
  };

  programs.fish = {
    enable = true;
    shellInit = lib.mkAfter ''
      fish_add_path --global --path --move ${omp}/bin
    '';
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

    interactiveShellInit = lib.mkOrder 1492 ''
      source $HOME/.config/fish/user-config.fish 2> /dev/null
    '';

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
