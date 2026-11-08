{ lib, pkgs, osConfig, nixcfgPath, ... }:

let
  tooling = import ./language-servers.nix { inherit lib pkgs osConfig nixcfgPath; };
  # Neovim attaches a server without filetypes to every buffer; the shared table's
  # fileTypes are OMP extensions, so map Neovim filetypes here.
  fileTypes = {
    nixd = [ "nix" ];
    gopls = [ "go" "gomod" "gowork" "gotmpl" ];
    basedpyright = [ "python" ];
    ruff = [ "python" ];
    rust-analyzer = [ "rust" ];
    typescript-language-server = [ "javascript" "javascriptreact" "typescript" "typescriptreact" ];
    lua-language-server = [ "lua" ];
    bashls = [ "sh" "bash" ];
    yamlls = [ "yaml" ];
    tombi = [ "toml" ];
    vscode-json-language-server = [ "json" "jsonc" ];
    qml = [ "qml" ];
  };
  serverConfig = name: server: lib.filterAttrs (_: value: value != [ ] && value != { }) {
    cmd = [ server.command ] ++ server.args;
    filetypes = fileTypes.${name};
    root_markers = server.rootMarkers or [ ];
    init_options = server.settings or { };
  };
  initLua = ''
    vim.g.mapleader = " "
    vim.g.maplocalleader = ","
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.signcolumn = "yes"
    vim.opt.termguicolors = true
    vim.opt.expandtab = true
    vim.opt.shiftwidth = 2
    vim.opt.tabstop = 2
    vim.opt.ignorecase = true
    vim.opt.smartcase = true
    vim.opt.undofile = true
    vim.opt.completeopt = { "menu", "menuone", "noselect" }
    vim.api.nvim_create_autocmd("InsertCharPre", {
      callback = function()
        if vim.fn.pumvisible() == 0 then
          vim.schedule(function() vim.lsp.completion.get() end)
        end
      end,
    })
    vim.lsp.config("*", { root_markers = { ".git" } })

    local capabilities = vim.lsp.protocol.make_client_capabilities()
    capabilities.textDocument.completion.completionItem.snippetSupport = true
    local servers = ${lib.generators.toLua { } (lib.mapAttrs serverConfig tooling.servers)}
    for name, config in pairs(servers) do
      config.capabilities = capabilities
      vim.lsp.config(name, config)
      vim.lsp.enable(name)
    end

    vim.api.nvim_create_autocmd("LspAttach", {
      callback = function(event)
        local opts = { buffer = event.buf }
        vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
        vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
        vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
        vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, opts)
        vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, opts)
      end,
    })

    local formatters = {
      nix = { "${lib.getExe pkgs.nixfmt}" },
      python = function() vim.lsp.buf.format({ name = "ruff" }) end,
      go = function() vim.lsp.buf.format({ name = "gopls" }) end,
      rust = function() vim.lsp.buf.format({ name = "rust-analyzer" }) end,
      lua = { "${lib.getExe pkgs.stylua}", "--stdin-filepath", "%", "-" },
      sh = { "${lib.getExe pkgs.shfmt}", "-i", "2", "-" },
      bash = { "${lib.getExe pkgs.shfmt}", "-i", "2", "-" },
      fish = function(bufnr)
        return vim.system({ "${lib.getExe pkgs.fish}", "-c", "fish_indent" }, { stdin = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, true), "\n") .. "\n" }):wait().stdout
      end,
    }
    vim.api.nvim_create_autocmd("BufWritePre", {
      callback = function(event)
        local formatter = formatters[vim.bo[event.buf].filetype]
        if formatter == nil then return end
        if type(formatter) == "function" then formatter(event.buf); return end
        local lines = vim.api.nvim_buf_get_lines(event.buf, 0, -1, true)
        local command = vim.tbl_map(function(arg)
          return arg == "%" and vim.api.nvim_buf_get_name(event.buf) or arg
        end, formatter)
        local result = vim.system(command, { stdin = table.concat(lines, "\n") .. "\n" }):wait()
        if result.code ~= 0 then
          vim.notify(result.stderr, vim.log.levels.ERROR)
          return
        end
        vim.api.nvim_buf_set_lines(event.buf, 0, -1, true, vim.split(result.stdout, "\n", { trimempty = true }))
      end,
    })
  '';
in
{
  home.packages = with pkgs; [
    nixfmt
    ruff
    stylua
    shellcheck
    shfmt
    tooling.rustAnalyzer
  ] ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
    cargo
    rustc
    rustfmt
  ];
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    extraPackages = lib.optionals pkgs.stdenv.hostPlatform.isLinux [ pkgs.qt6.qtdeclarative ];
    initLua = initLua;
  };
}
