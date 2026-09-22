{ lib, ... }:

{
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
      # Keep prompt/user configuration after colors, before direnv's mkAfter hook.
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
    "starship.toml".source = ../../../dotfiles/starship.toml;
    "btop/btop.conf".source = ../../../dotfiles/btop.conf;
    "fastfetch/config.jsonc".source = ../../../dotfiles/fastfetch.jsonc;
    "micro/settings.json".text = ''
      {
          "colorscheme": "simple"
      }
    '';
  };
}
