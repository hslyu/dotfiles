local python_import_dev = false

return {
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("kiyoon.tokyonight")
      vim.cmd.colorscheme("tokyonight")
    end,
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        "<space>pf",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        desc = "Format buffer",
      },
    },
    opts = {
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_fix", "ruff_format" },
        javascript = { "biome-organize-imports", "biome" },
        typescript = { "biome-organize-imports", "biome" },
        javascriptreact = { "biome-organize-imports", "biome" },
        typescriptreact = { "biome-organize-imports", "biome" },
        html = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettier" },
        json = { "biome" },
        jsonc = { "biome" },
        css = { "biome" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        cs = { "csharpier" },
        toml = { "taplo" },
      },
      format_on_save = { timeout_ms = 2000, lsp_fallback = true },
      formatters = {
        shfmt = {
          prepend_args = { "-i", "2" },
        },
        ruff_fix = {
          prepend_args = {
            "check",
            "--select",
            "I,D20,D21,UP00,UP032,UP034",
            "--ignore",
            "D212",
          },
        },
        prettier = {
          prepend_args = {
            "--no-semi",
            "--single-quote",
            "--jsx-single-quote",
          },
        },
      },
    },
    init = function()
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
    end,
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    cmd = { "Mason", "MasonUpdate" },
    build = ":MasonUpdate",
    dependencies = {
      {
        "williamboman/mason.nvim",
        dependencies = {
          "williamboman/mason-lspconfig.nvim",
        },
      },
      {
        "folke/lazydev.nvim",
        ft = "lua",
        opts = {
          library = {
            { path = "luvit-meta/library", words = { "vim%.uv" } },
          },
        },
      },
      { "Bilal2453/luvit-meta", lazy = true },
    },
    config = function()
      require("kiyoon.lsp")
    end,
  },
  {
    "chrisgrieser/nvim-lsp-endhints",
    event = "LspAttach",
    config = function()
      require("lsp-endhints").setup({
        label = {
          truncateAtChars = 40,
        },
      })
      require("kiyoon.lsp.inlayhints")
    end,
  },
  {
    "ray-x/lsp_signature.nvim",
    event = "BufReadPre",
    config = function()
      require("lsp_signature").setup({
        on_attach = function(_, bufnr)
          require("lsp_signature").on_attach({
            bind = true,
            handler_opts = {
              border = "rounded",
            },
          }, bufnr)
        end,
      })
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-calc",
      "hrsh7th/cmp-emoji",
      "chrisgrieser/cmp-nerdfont",
      "saadparwaiz1/cmp_luasnip",
      "onsails/lspkind.nvim",
    },
    config = function()
      require("kiyoon.cmp")
    end,
  },
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    event = "InsertEnter",
    dependencies = { "rafamadriz/friendly-snippets" },
    config = function()
      require("kiyoon.luasnip")
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    build = ":TSUpdate",
    init = function(plugin)
      require("lazy.core.loader").add_to_rtp(plugin)
      require("nvim-treesitter.query_predicates")
    end,
    dependencies = {
      { "nvim-treesitter/nvim-treesitter-textobjects" },
    },
    config = function()
      require("kiyoon.treesitter")
    end,
  },
  {
    "nvim-telescope/telescope.nvim",
    cmd = { "Telescope" },
    keys = {
      { "<leader>fF", function() require("telescope.builtin").git_files() end, desc = "[F]uzzy [F]ind Git [F]iles" },
      { "<leader>ff", function() require("telescope.builtin").find_files() end, desc = "[F]uzzy [F]ind [F]iles" },
      { "<leader>fW", function() require("telescope.builtin").live_grep() end, desc = "[F]ind [W]ord" },
      { "<leader>fw", function() require("kiyoon.telescope").live_grep_gitdir() end, desc = "[F]ind [W]ord in git dir" },
      { "<leader>fiw", function() require("kiyoon.telescope").grep_string_gitdir() end, desc = "[F]ind inner word (git)" },
      { "<leader>fg", function() require("telescope").extensions.live_grep_args.live_grep_args() end, desc = "Live grep args" },
      { "<leader>fr", function() require("telescope.builtin").oldfiles() end, desc = "[F]ind [R]ecent files" },
      { "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "[F]ind [B]uffers" },
      { "<leader>fh", function() require("telescope.builtin").help_tags() end, desc = "[F]ind [H]elp" },
      { "<leader>fs", function() require("telescope.builtin").current_buffer_fuzzy_find() end, desc = "[F]uzzy [S]earch buffer" },
    },
    init = function()
      local ok, wk = pcall(require, "which-key")
      if ok then
        wk.add({
          { "<leader>f", group = "Telescope [F]uzzy [F]inder" },
          { "<leader>fi", group = "[I]nner" },
        })
      end
    end,
    dependencies = {
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
        config = function()
          require("telescope").load_extension("fzf")
        end,
      },
      { "kiyoon/telescope-insert-path.nvim" },
      { "nvim-telescope/telescope-live-grep-args.nvim" },
    },
    config = function()
      require("kiyoon.telescope")
    end,
  },
  {
    "stevearc/oil.nvim",
    opts = {
      keymaps = {
        ["\\"] = { "actions.select", opts = { vertical = true }, desc = "Open vertical split" },
        ["|"] = { "actions.select", opts = { horizontal = true }, desc = "Open horizontal split" },
        ["<C-r>"] = "actions.refresh",
        ["g?"] = "actions.show_help",
        ["<CR>"] = "actions.select",
        ["<C-t>"] = { "actions.select", opts = { tab = true }, desc = "Open in new tab" },
        ["<C-p>"] = "actions.preview",
        ["<C-c>"] = "actions.close",
        ["U"] = "actions.parent",
        ["<BS>"] = "actions.parent",
        ["`"] = "actions.cd",
        ["~"] = { "actions.cd", opts = { scope = "tab" }, desc = ":tcd to oil dir" },
        ["gs"] = "actions.change_sort",
        ["gx"] = "actions.open_external",
        ["g."] = "actions.toggle_hidden",
        ["g\\"] = "actions.toggle_trash",
      },
      use_default_keymaps = false,
    },
  },
  {
    "kylechui/nvim-surround",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup()

      local right = function()
        local now_col = vim.api.nvim_eval([[virtcol('.')]])
        local last_col = vim.api.nvim_eval([[virtcol('$')]]) - 1
        if now_col == last_col then
          vim.cmd("startinsert!")
        else
          vim.cmd("norm! a")
        end
      end

      vim.keymap.set("n", "`", function()
        vim.cmd.normal("viwS`f`l")
      end, { desc = "Surround backtick" })

      vim.keymap.set("i", "<A-`>", function()
        vim.cmd.normal("hviwS`f`l")
        right()
      end, { silent = false, desc = "Surround backtick" })

      vim.keymap.set("x", "`", function()
        vim.cmd.normal("S`f`")
        right()
      end, { silent = false, desc = "Surround backtick" })

      vim.keymap.set("n", "<F4>", function()
        local original_iskeyword = vim.opt.iskeyword
        vim.opt.iskeyword = "@,48-57,_,192-255"
        vim.cmd.normal({ "viw", bang = true })
        vim.opt.iskeyword = original_iskeyword
        vim.cmd.normal("S)")
        vim.cmd.startinsert()
      end, { desc = "Surround parens (function call)" })
      vim.keymap.set("i", "<F4>", function()
        local original_iskeyword = vim.opt.iskeyword
        vim.opt.iskeyword = "@,48-57,_,192-255"
        vim.cmd.normal({ "hviw", bang = true })
        vim.opt.iskeyword = original_iskeyword
        vim.cmd.normal("S)")
      end, { silent = false, desc = "Surround parens (function call)" })
      vim.keymap.set("x", "<F4>", function()
        vim.cmd.normal("S)")
        vim.cmd.startinsert()
      end, { silent = false, desc = "Surround parens (function call)" })
    end,
  },
  {
    "kiyoon/python-import.nvim",
    build = "uv tool install . --force --reinstall",
    ft = "python",
    keys = {
      {
        "<M-CR>",
        function()
          require("python_import.api").add_import_current_word_and_notify()
        end,
        mode = { "i", "n" },
        desc = "Add python import",
      },
      {
        "<M-CR>",
        function()
          require("python_import.api").add_import_current_selection_and_notify()
        end,
        mode = "x",
        desc = "Add python import",
      },
      {
        "<space>i",
        function()
          require("python_import.api").add_import_current_word_and_move_cursor()
        end,
        desc = "Add python import and move cursor",
      },
      {
        "<space>i",
        function()
          require("python_import.api").add_import_current_selection_and_move_cursor()
        end,
        mode = "x",
        desc = "Add python import and move cursor",
      },
      {
        "<space>tr",
        function()
          require("python_import.api").add_rich_traceback()
        end,
        desc = "Add rich traceback",
      },
    },
    opts = {
      extend_lookup_table = {
        import = {},
        import_as = {},
        import_from = {},
        statement_after_imports = {},
      },
      custom_function = function(winnr, word, ts_node)
        local bufnr = vim.api.nvim_win_get_buf(winnr)
        local utils = require("python_import.utils")
        local cached = utils.get_cached_first_party_modules(bufnr)
        if cached and cached[1] then
          local first_module = cached[1]
          if word:match("_DIR$") then
            return { "from " .. first_module .. " import " .. word }
          elseif word == "setup_logging" then
            return { "from " .. first_module .. " import setup_logging" }
          end
        end
      end,
    },
    dev = python_import_dev,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    main = "indent_blankline",
    config = function()
      require("indent_blankline").setup({
        space_char_blankline = " ",
        show_current_context = true,
        show_current_context_start = true,
      })
    end,
  },
  {
    "luukvbaal/statuscol.nvim",
    config = function()
      require("kiyoon.statuscol")
    end,
  },
  {
    "chaoren/vim-wordmotion",
    event = "VeryLazy",
    init = function()
      vim.g.wordmotion_prefix = "<space>"
    end,
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      modes = {
        search = { enabled = false },
        char = { enabled = false },
      },
    },
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "m", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "M", "m", noremap = true, desc = "[M]ark" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<C-s>", mode = "c", function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },
}
