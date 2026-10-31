{
  config,
  osConfig,
  lib,
  pkgs,
  nixcfgPath,
  ...
}:
let
  tooling = import ./language-servers.nix {
    inherit
      lib
      pkgs
      osConfig
      nixcfgPath
      ;
  };
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
  starshipSettings = builtins.fromTOML (builtins.readFile ../dotfiles/starship.toml);
  sovietPrompt = (pkgs.formats.toml { }).generate "starship-soviet.toml" (
    lib.recursiveUpdate starshipSettings {
      palette = "soyuz";
      palettes.soyuz = {
        red = "#ee6a5e";
        bright-red = "#ff9185";
        yellow = "#ddc390";
        bright-yellow = "#ead6ae";
        white = "#e5d5b5";
        bright-white = "#f2e8d5";
        green = "#b8ba8a";
        bright-green = "#c8cba0";
        blue = "#c5bb9d";
        bright-blue = "#e5d5b5";
        cyan = "#c5bb9d";
        bright-cyan = "#e5d5b5";
        purple = "#e49b88";
        bright-purple = "#ffb4a2";
      };
      format = "$nix_shell$container$cmd_duration$env_var$hostname$localip$username[soyuz-workstation](bold red) $jobs$sudo$character";
      continuation_prompt = "[.. ](red)";
      username = {
        show_always = true;
        format = "[$user@]($style)";
        style_user = "bold yellow";
        style_root = "bold bright-red";
      };
      character = {
        success_symbol = "[>](bold red)";
        error_symbol = "[!](bold bright-red)";
        vimcmd_symbol = "[<](bold yellow)";
      };
      directory = {
        style = "white";
        repo_root_style = "bold white";
      };
      git_branch.style = "red";
      git_status.style = "red";
      time.style = "yellow";
    }
  );
  sovietColors = {
    fish_color_normal = "e5d5b5";
    fish_color_command = "ee6a5e --bold";
    fish_color_param = "e5d5b5";
    fish_color_quote = "ddc390";
    fish_color_redirection = "ee6a5e --bold";
    fish_color_end = "ee6a5e";
    fish_color_error = "ff9185 --bold --underline";
    fish_color_comment = "a8aa8c";
    fish_color_operator = "ddc390";
    fish_color_escape = "ddc390";
    fish_color_autosuggestion = "a8aa8c";
    fish_color_search_match = "f2e8d5 --background=68332f";
    fish_color_selection = "f2e8d5 --background=68332f";
    fish_color_valid_path = "--underline";
    fish_pager_color_prefix = "ee6a5e --bold";
    fish_pager_color_completion = "e5d5b5";
    fish_pager_color_description = "ddc390";
    fish_pager_color_progress = "f2e8d5 --background=68332f";
    fish_pager_color_selected_background = "--background=68332f";
  };
  deepSpacePrompt = (pkgs.formats.toml { }).generate "starship-deep-space.toml" (
    lib.recursiveUpdate starshipSettings {
      palette = "deep-space";
      palettes.deep-space = {
        red = "#e87878";
        muted = "#a3a6ad";
        white = "#d5d7dd";
        yellow = "#c9b589";
      };
      format = "[● discovery](red)  $username$hostname$fill$directory$git_branch$git_commit$git_state$git_status$time$line_break$env_var$nix_shell$container$jobs$sudo$character";
      right_format = "";
      continuation_prompt = "[· ](muted)";
      username = {
        show_always = true;
        format = "[$user@]($style)";
        style_user = "muted";
        style_root = "bold red";
      };
      hostname = {
        ssh_only = false;
        format = "[$hostname]($style)";
        style = "muted";
      };
      character = {
        success_symbol = "[›](red)";
        error_symbol = "[!](bold red)";
        vimcmd_symbol = "[‹](red)";
      };
      directory = {
        home_symbol = "~";
        truncation_length = 3;
        truncation_symbol = "…/";
        truncate_to_repo = false;
        style = "muted";
        repo_root_style = "muted";
        repo_root_format = "[$before_root_path]($before_repo_root_style)[$repo_root]($repo_root_style)[$path]($style)[$read_only]($read_only_style)";
        read_only = " ro";
        read_only_style = "red";
      };
      git_branch = {
        format = "[ · $branch]($style)";
        style = "muted";
        ignore_branches = [ ];
      };
      git_commit = {
        format = "[ · $hash]($style)";
        style = "muted";
      };
      git_state.style = "red";
      git_status = {
        style = "muted";
        format = "([$all_status$ahead_behind]($style))";
        conflicted = " !$count";
        ahead = " ↑$count";
        behind = " ↓$count";
        diverged = " ↑$ahead_count↓$behind_count";
        untracked = " ?$count";
        stashed = " *$count";
        modified = " ~$count";
        staged = " +$count";
        renamed = " r$count";
        deleted = " -$count";
      };
      time = {
        format = "[ · $time]($style)";
        style = "muted";
      };
    }
  );
  deepSpaceColors = {
    fish_color_normal = "d5d7dd";
    fish_color_command = "d5d7dd";
    fish_color_param = "b9bdc6";
    fish_color_quote = "c2b8ad";
    fish_color_redirection = "e87878";
    fish_color_end = "e87878";
    fish_color_error = "ff9696 --bold --underline";
    fish_color_comment = "9498a1";
    fish_color_operator = "a3a6ad";
    fish_color_escape = "e87878";
    fish_color_autosuggestion = "9498a1";
    fish_color_search_match = "e5e6eb --background=3f262d";
    fish_color_selection = "e5e6eb --background=3f262d";
    fish_color_valid_path = "--underline";
    fish_pager_color_prefix = "e87878";
    fish_pager_color_completion = "d5d7dd";
    fish_pager_color_description = "a3a6ad";
    fish_pager_color_progress = "e5e6eb --background=3f262d";
    fish_pager_color_selected_background = "--background=3f262d";
  };
in

{
  home.packages = with pkgs; [
    omp
    age
    btop
    git
    gh
    wget
    eza
    bat
    ripgrep
    lazygit
    jq
    fastfetch
    file
    unzip
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
    - Configuration model: ${
      if pkgs.stdenv.hostPlatform.isDarwin then "nix-darwin" else "NixOS"
    } + Home Manager
    - Configured desktop: ${
      if pkgs.stdenv.hostPlatform.isDarwin then
        "macOS desktop"
      else if osConfig.programs.hyprland.enable then
        "Hyprland (Wayland)"
      else
        "none"
    }

    These values identify the local installed Nix configuration, not the current
    process user, session working directory or a remote SSH target. Verify live
    identity when an operation depends on it.
  '';

  home.file.".omp/agent/extensions/nixcfg-execution.js".source = ../dotfiles/omp/nixcfg-execution.js;

  home.file.".omp/agent/lsp.json".text = builtins.toJSON {
    servers =
      lib.mapAttrs (
        _: server:
        server
        // {
          settings = server.settings or { };
        }
      ) tooling.servers
      // {
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

  programs.fzf = {
    enable = true;
    enableFishIntegration = true;
    enableBashIntegration = false;
    enableZshIntegration = false;
    enableNushellIntegration = false;
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
      if test -e "$HOME/.config/fish/user-config.fish"
        source "$HOME/.config/fish/user-config.fish"
      end
    '';

    functions.larp = {
      description = "Switch shell appearance, or restore with larp";
      body = ''
        if test (count $argv) -gt 1
          printf 'Usage: larp [soviet|deep-space]\n' >&2
          return 2
        end

        set -l variables STARSHIP_CONFIG ${lib.concatStringsSep " " (
          builtins.attrNames (sovietColors // deepSpaceColors)
        )}
        switch "$argv[1]"
          case soviet deep-space
            if not set -q __larp_active
              set -g __larp_exported (set --names --global --export)
              for name in $variables
                if set -q --global $name
                  set -g -- __larp_saved_$name $$name
                end
              end
              set -g __larp_active 1
            end
            switch "$argv[1]"
              case soviet
                set -gx STARSHIP_CONFIG ${sovietPrompt}
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: value: "set -g -- ${name} ${value}") sovietColors
                )}
              case deep-space
                set -gx STARSHIP_CONFIG ${deepSpacePrompt}
                ${lib.concatStringsSep "\n" (
                  lib.mapAttrsToList (name: value: "set -g -- ${name} ${value}") deepSpaceColors
                )}
            end
          case '''
            if set -q __larp_active
              for name in $variables
                set -l saved __larp_saved_$name
                set -e --global $name
                if set -q --global $saved
                  if contains -- $name $__larp_exported
                    set -gx -- $name $$saved
                  else
                    set -gu -- $name $$saved
                  end
                  set -e --global $saved
                end
              end
              set -e __larp_active
              set -e __larp_exported
            end
          case -h --help
            printf 'Usage: larp [soviet|deep-space]\n\nsoviet      Soyuz workstation prompt and colors\ndeep-space  Quiet Discovery prompt with red accents\n(no argument)  Restore this shell’s original appearance\n'
          case '*'
            printf 'larp: unknown theme "%s"; use larp soviet, larp deep-space, or larp.\n' "$argv[1]" >&2
            return 2
        end
        return 0
      '';
    };

    functions.fish_greeting = ''
      fastfetch --key-padding-left 5
    '';
  };

  programs.micro = {
    enable = true;
    settings.colorscheme = "simple";
  };

  xdg.configFile = {
    "starship.toml".source = ../dotfiles/starship.toml;
    "fish/completions/larp.fish".text = ''
      complete -c larp -f
      complete -c larp -n 'not __fish_seen_subcommand_from soviet deep-space' -a soviet -d 'Soyuz workstation appearance'
      complete -c larp -n 'not __fish_seen_subcommand_from soviet deep-space' -a deep-space -d 'Quiet Discovery appearance'
      complete -c larp -s h -l help -d 'Show usage'
    '';
    "btop/btop.conf".source = ../dotfiles/btop.conf;
    "fastfetch/config.jsonc".source = ../dotfiles/fastfetch.jsonc;
  };
}
