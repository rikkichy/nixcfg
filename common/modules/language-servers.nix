{ lib, pkgs, osConfig, nixcfgPath }:
let
  isDarwin = pkgs.stdenv.hostPlatform.isDarwin;
  isDesktop = osConfig.networking.hostName == "nix";
  # Nix's path fetcher rejects Darwin's /etc symlink.
  evaluationPath = if isDarwin then "/private${nixcfgPath}" else nixcfgPath;
  flake = "(builtins.getFlake ${builtins.toJSON evaluationPath})";
  host = "${if isDarwin then "darwinConfigurations" else "nixosConfigurations"}.${osConfig.networking.hostName}";
  rustAnalyzer = if isDarwin then pkgs.rust-analyzer-unwrapped else pkgs.rust-analyzer;
  # Preserve project Go toolchains; supply a fallback outside a dev shell.
  gopls = pkgs.symlinkJoin {
    name = "gopls-with-go";
    paths = [ pkgs.gopls ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/gopls --suffix PATH : ${lib.makeBinPath [ pkgs.go ]}
    '';
  };
in
{
  inherit rustAnalyzer;
  servers = {
    nixd = {
      command = lib.getExe pkgs.nixd;
      args = [ ];
      settings.nixd = {
        nixpkgs.expr = "${flake}.${host}.pkgs";
        options = {
          nixos.expr = "${flake}.nixosConfigurations.nix.options";
          nixos-server.expr = "${flake}.nixosConfigurations.nixos-server.options";
          darwin.expr = "${flake}.darwinConfigurations.ne.options";
          home-manager.expr = "${flake}.${host}.options.home-manager.users.type.getSubOptions []";
        };
        formatting.command = [ (lib.getExe pkgs.nixfmt) ];
      };
    };
    gopls = {
      command = "${gopls}/bin/gopls";
      args = [ ];
    };
    basedpyright = {
      command = "${pkgs.basedpyright}/bin/basedpyright-langserver";
      args = [ "--stdio" ];
    };
    ruff = {
      command = lib.getExe pkgs.ruff;
      args = [ "server" ];
    };
    rust-analyzer = {
      command = lib.getExe rustAnalyzer;
      args = [ ];
    };
    typescript-language-server = {
      command = lib.getExe pkgs.vtsls;
      args = [ "--stdio" ];
    };
    lua-language-server = {
      command = lib.getExe pkgs.lua-language-server;
      args = [ ];
    };
    bashls = {
      command = lib.getExe pkgs.bash-language-server;
      args = [ "start" ];
      settings.bashIde = {
        shellcheckPath = lib.getExe pkgs.shellcheck;
        shfmt.path = lib.getExe pkgs.shfmt;
      };
    };
    yamlls = {
      command = lib.getExe pkgs.yaml-language-server;
      args = [ "--stdio" ];
    };
    tombi = {
      command = lib.getExe pkgs.tombi;
      args = [ "lsp" ];
      fileTypes = [ ".toml" ];
      rootMarkers = [ "tombi.toml" "pyproject.toml" "Cargo.toml" ".git" ];
      languageId = "toml";
    };
    vscode-json-language-server = {
      command = "${pkgs.vscode-langservers-extracted}/bin/vscode-json-language-server";
      args = [ "--stdio" ];
    };
  } // lib.optionalAttrs (isDarwin || isDesktop) {
    kotlin-lsp = {
      command = if isDarwin then "/opt/homebrew/bin/kotlin-lsp" else lib.getExe pkgs.kotlin-lsp;
      args = [ "--stdio" ];
    };
  } // lib.optionalAttrs isDesktop {
    qml = {
      command = "${pkgs.qt6.qtdeclarative}/bin/qmlls";
      args = [
        "-I" "${pkgs.qt6.qtdeclarative}/${pkgs.qt6.qtbase.qtQmlPrefix}"
        "-I" "${pkgs.quickshell}/${pkgs.qt6.qtbase.qtQmlPrefix}"
        "--no-cmake-calls"
      ];
      fileTypes = [ ".qml" ];
      rootMarkers = [ "CMakeLists.txt" ".qmlls.ini" "qmldir" "shell.qml" ".git" ];
      languageId = "qml";
    };
  };
}
