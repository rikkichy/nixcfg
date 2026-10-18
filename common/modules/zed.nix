{
  lib,
  pkgs,
  osConfig,
  nixcfgPath,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  tooling = import ./language-servers.nix { inherit lib pkgs osConfig nixcfgPath; };
  zedNames = {
    typescript-language-server = "vtsls";
    bashls = "bash-language-server";
    yamlls = "yaml-language-server";
    vscode-json-language-server = "json-language-server";
  };
in
{
  home.packages =
    with pkgs;
    [
      nixfmt
      ruff
      stylua
      shellcheck
      shfmt
      tooling.rustAnalyzer
    ]
    ++ lib.optionals isLinux [
      cargo
      rustc
      rustfmt
    ];

  programs.zed-editor = {
    enable = true;
    package = pkgs.zed-editor;
    extraPackages = lib.optionals isLinux [ pkgs.qt6.qtdeclarative ];
    mutableUserSettings = false;
    themes.matugen = ../dotfiles/zed/themes/matugen.json;
    extensions = [
      "nix"
      "kotlin"
      "lua"
      "qml"
      "fish"
      "toml"
      "tombi"
    ];

    userSettings = {
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
      disable_ai = true;
      ui_font_size = 16;
      buffer_font_size = 15;
      buffer_font_family = "DepartureMono Nerd Font";
      theme = {
        mode = "system";
        light = "Matugen Light";
        dark = "Matugen Dark";
      };
      auto_update = false;
      autosave = "off";
      format_on_save = "on";
      auto_signature_help = true;
      inlay_hints.enabled = false;
      load_direnv = "direct";
      terminal = {
        font_family = "DepartureMono Nerd Font";
        shell.program = lib.getExe pkgs.fish;
      };
      # Zed's own Node runtime, not a global project toolchain.
      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = "${pkgs.nodejs}/bin/npm";
      };
      languages = {
        Nix = {
          language_servers = [ "nixd" ];
          formatter.external.command = lib.getExe pkgs.nixfmt;
        };
        Go = {
          language_servers = [ "gopls" ];
          formatter = "language_server";
          code_actions_on_format."source.organizeImports" = true;
        };
        Python = {
          language_servers = [
            "basedpyright"
            "ruff"
          ];
          formatter.language_server.name = "ruff";
          code_actions_on_format."source.organizeImports.ruff" = true;
        };
        Kotlin.language_servers = [ "kotlin-lsp" ];
        Kotlin.enable_language_server = !isLinux;
        Lua.formatter.external = {
          command = lib.getExe pkgs.stylua;
          arguments = [
            "--stdin-filepath"
            "{buffer_path}"
            "-"
          ];
        };
        QML.enable_language_server = isLinux;
        Fish.formatter.external.command = "${pkgs.fish}/bin/fish_indent";
      };
      lsp = lib.mapAttrs' (name: server:
        lib.nameValuePair (zedNames.${name} or name) {
          binary = {
            path = server.command;
            arguments = server.args;
          };
          # Zed's nixd adapter supplies the configuration section itself.
          settings = if name == "nixd" then server.settings.nixd else server.settings or { };
        }
      ) tooling.servers;
    };
  };
}
