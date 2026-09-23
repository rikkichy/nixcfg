{
  lib,
  pkgs,
  nixcfgPath,
  ...
}:

let
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  flake = "(builtins.getFlake ${builtins.toJSON nixcfgPath})";
  host = if isLinux then "nixosConfigurations.nix" else "darwinConfigurations.ne";
  rustAnalyzer = if isLinux then pkgs.rust-analyzer else pkgs.rust-analyzer-unwrapped;
  # Keep project Go toolchains first; the editor still works outside a dev shell.
  gopls = pkgs.symlinkJoin {
    name = "zed-gopls";
    paths = [ pkgs.gopls ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/gopls --suffix PATH : ${lib.makeBinPath [ pkgs.go ]}
    '';
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
      rustAnalyzer
    ]
    ++ lib.optionals isLinux [
      cargo
      rustc
      rustfmt
    ];

  programs.zed-editor = {
    enable = true;
    package = if isLinux then pkgs.zed-editor else null;
    extraPackages = lib.optionals isLinux [ pkgs.qt6.qtdeclarative ];
    mutableUserSettings = false;
    themes.matugen = ../../dotfiles/common/zed/themes/matugen.json;
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
      auto_update = !isLinux;
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
      lsp = {
        nixd = {
          binary = {
            path = lib.getExe pkgs.nixd;
            arguments = [ ];
          };
          settings = {
            nixpkgs.expr = "import ${flake}.inputs.nixpkgs { system = ${builtins.toJSON pkgs.stdenv.hostPlatform.system}; }";
            options = {
              nixos.expr = "${flake}.nixosConfigurations.nix.options";
              darwin.expr = "${flake}.darwinConfigurations.ne.options";
              home-manager.expr = "${flake}.${host}.options.home-manager.users.type.getSubOptions []";
            };
          };
        };
        gopls.binary = {
          path = "${gopls}/bin/gopls";
          arguments = [ ];
        };
        basedpyright.binary = {
          path = "${pkgs.basedpyright}/bin/basedpyright-langserver";
          arguments = [ "--stdio" ];
        };
        ruff.binary = {
          path = lib.getExe pkgs.ruff;
          arguments = [ "server" ];
        };
        rust-analyzer.binary = {
          path = lib.getExe rustAnalyzer;
          arguments = [ ];
        };
        kotlin-lsp.binary = {
          path = if isLinux then lib.getExe pkgs.kotlin-lsp else "/opt/homebrew/bin/kotlin-lsp";
          arguments = [ "--stdio" ];
        };
        vtsls.binary = {
          path = lib.getExe pkgs.vtsls;
          arguments = [ "--stdio" ];
        };
        lua-language-server.binary = {
          path = lib.getExe pkgs.lua-language-server;
          arguments = [ ];
        };
        bash-language-server = {
          binary = {
            path = lib.getExe pkgs.bash-language-server;
            arguments = [ "start" ];
          };
          settings.bashIde = {
            shellcheckPath = lib.getExe pkgs.shellcheck;
            shfmt.path = lib.getExe pkgs.shfmt;
          };
        };
        yaml-language-server.binary = {
          path = lib.getExe pkgs.yaml-language-server;
          arguments = [ "--stdio" ];
        };
        tombi.binary = {
          path = lib.getExe pkgs.tombi;
          arguments = [ "lsp" ];
        };
        json-language-server.binary = {
          path = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
          arguments = [ "--stdio" ];
        };
      }
      // lib.optionalAttrs isLinux {
        # zed-qml discovers qmlls on PATH and only forwards binary.arguments.
        qml.binary.arguments = [
          "-I"
          "${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}"
          "-I"
          "${pkgs.quickshell}/${pkgs.qt6.qtbase.qtQmlPrefix}"
          "--no-cmake-calls"
        ];
      };
    };
  };
}
