{
  programs.fish.shellInit = ''
    /opt/homebrew/bin/brew shellenv fish | source
    fish_add_path --global --path /opt/homebrew/opt/rustup/bin
    set -gx BUN_INSTALL "$HOME/.bun"
    fish_add_path --global --path "$BUN_INSTALL/bin"
  '';
}
