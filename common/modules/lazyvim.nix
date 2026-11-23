{
  lib,
  pkgs,
  servers,
}:
let
  plugins = with pkgs.vimPlugins; [
    LazyVim
    blink-cmp
    bufferline-nvim
    conform-nvim
    flash-nvim
    friendly-snippets
    gitsigns-nvim
    grug-far-nvim
    lazy-nvim
    lazydev-nvim
    lualine-nvim
    mini-ai
    mini-icons
    mini-pairs
    noice-nvim
    nui-nvim
    nvim-lint
    nvim-lspconfig
    nvim-treesitter
    nvim-treesitter-textobjects
    nvim-ts-autotag
    persistence-nvim
    plenary-nvim
    snacks-nvim
    todo-comments-nvim
    tokyonight-nvim
    trouble-nvim
    ts-comments-nvim
    which-key-nvim
  ];
  # lazy.nvim identifies a module's plugin by its directory basename.
  pluginRoot = pkgs.linkFarm "lazyvim-plugins" (
    map (p: {
      name = p.pname;
      path = p;
    }) plugins
    ++ [
      {
        name = "catppuccin";
        path = pkgs.vimPlugins.catppuccin-nvim;
      }
    ]
  );
  parsers = pkgs.symlinkJoin {
    name = "lazyvim-parsers";
    paths =
      (pkgs.vimPlugins.nvim-treesitter.withPlugins (
        p: with p; [
          bash
          c
          diff
          fish
          html
          javascript
          jsdoc
          json
          lua
          luadoc
          luap
          markdown
          markdown_inline
          nix
          printf
          python
          qmljs
          query
          regex
          rust
          toml
          tsx
          typescript
          vim
          vimdoc
          xml
          yaml
        ]
      )).dependencies;
  };
  lspNames = {
    lua-language-server = "lua_ls";
    rust-analyzer = "rust_analyzer";
    typescript-language-server = "vtsls";
    vscode-json-language-server = "jsonls";
  };
  lazyServers = lib.mapAttrs' (
    name: config: lib.nameValuePair (lspNames.${name} or name) config
  ) servers;
in
''
  vim.opt.rtp:prepend("${pluginRoot}/lazy.nvim")

  require("lazy").setup({
    spec = {
      { "LazyVim/LazyVim", import = "lazyvim.plugins" },
      { "mason-org/mason.nvim", enabled = false },
      { "mason-org/mason-lspconfig.nvim", enabled = false },
      { "neovim/nvim-lspconfig", opts = { servers = ${lib.generators.toLua { } lazyServers} } },
      { "nvim-treesitter/nvim-treesitter", opts = { install_dir = "${parsers}" } },
      {
        "stevearc/conform.nvim",
        opts = {
          formatters_by_ft = { nix = { "nixfmt" }, fish = { "fish_indent" } },
          formatters = { shfmt = { prepend_args = { "-i", "2" } } },
        },
      },
    },
    -- Only explicitly packaged plugins may load. Do not evaluate project-local specs.
    dev = {
      patterns = { "github.com/" },
      path = "${pluginRoot}",
    },
    local_spec = false,
    install = { missing = false },
    rocks = { enabled = false },
  })
''
