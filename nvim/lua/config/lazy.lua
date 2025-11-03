--- NOTE: I keep all plugins in one file, because I often want to disable half of them when I debug what plugin broke my config.

local nvim_treesitter_dev = false
local nvim_treesitter_textobjects_dev = false
local nvim_treesitter_context_dev = false
-- local jupynium_dev = false
-- local python_import_dev = false
-- local korean_ime_dev = false
-- local tmux_send_dev = false

local icons = require("kiyoon.icons")

return {
  {
    "folke/tokyonight.nvim",
    lazy = false, -- make sure we load this during startup if it is your main colorscheme
    priority = 1000, -- make sure to load this before all the other start plugins
    config = function()
      require("kiyoon.tokyonight")
      vim.cmd.colorscheme("tokyonight")
    end,
  },
  --- NOTE: Python
  {
    -- There are four types of python highlighting.
    -- 1. Default vim python (syntax highlighting)
    -- 2. This plugin (syntax highlighting)
    -- 3. nvim-treesitter (syntax highlighting)
    -- 4. basedpyright (semantic highlighting)
    --
    -- I want to use 4, so I disabled 3 which is distracting. (It's good but too much color)
    -- However, then it was sometimes confusing if f-strings were actually f-strings. (the values were not highlighted)
    -- with this plugin (2), I can see the f-strings are actually f-strings, but it doesn't hurt the 4.
    -- "vim-python/python-syntax",
    "wmvanvliet/python-syntax",
    ft = "python",
    init = function()
      -- I only care about string highlighting here.
      -- vim.g.python_highlight_all = 1
      vim.g.python_highlight_string_formatting = 1
      vim.g.python_highlight_string_format = 1
      vim.g.python_highlight_string_templates = 1
      vim.g.python_highlight_builtin_funcs = 1
      vim.g.python_highlight_builtin_objs = 1
      vim.g.python_highlight_builtin_types = 1
    end,
  },
  {
    -- Similar to tpope/vim-surround
    -- Plus dsf to delete surrounding function call.
    "kylechui/nvim-surround",
    event = "VeryLazy",
    config = function()
      require("nvim-surround").setup()

      local right = function()
        local nowCol = vim.api.nvim_eval([[virtcol('.')]])
        local lastCol = vim.api.nvim_eval([[virtcol('$')]]) - 1
        if nowCol == lastCol then
          vim.cmd("startinsert!")
        else
          vim.cmd("norm! a")
        end
      end
      -- map backtick to surround backtick (or alt ` in i mode)
      -- backtick originally goes to the mark, but I don't use it. You can use ` to go to the mark.
      -- 디폴트 `ys`를 선행키로 잡으면 약간의 딜레이가 생긴다.
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

      -- map <F4> to surround with parenthesis for function call (keep cursor at front)
      -- change iskeyword temporarily because we don't want `-` to be included in the word
      vim.keymap.set("n", "<F4>", function()
        local original_iskeyword = vim.opt.iskeyword
        vim.opt.iskeyword = "@,48-57,_,192-255" -- alphabet, _, and European accented characters
        vim.cmd.normal({ "viw", bang = true })
        vim.opt.iskeyword = original_iskeyword
        vim.cmd.normal("S)")
        vim.cmd.startinsert()
      end, { desc = "Surround parens (function call)" })
      vim.keymap.set("i", "<F4>", function()
        local original_iskeyword = vim.opt.iskeyword
        vim.opt.iskeyword = "@,48-57,_,192-255" -- alphabet, _, and European accented characters
        vim.cmd.normal({ "hviw", bang = true })
        vim.opt.iskeyword = original_iskeyword
        vim.cmd.normal("S)")
      end, { silent = false, desc = "Surround parens (function call)" })
      vim.keymap.set("x", "<F4>", function()
        vim.cmd.normal("S)")
        vim.cmd.startinsert()
      end, { silent = false, desc = "Surround parens (function call)" })

      -- map <space>tl to make hyperlink for markdown
      -- vim.keymap.set("n", "<space>tl", function()
      --   vim.cmd.normal("viwS]f]a()")
      --   vim.cmd.startinsert()
      -- end, { desc = "Make markdown hyperlink" })
      -- vim.keymap.set("x", "<space>tl", function()
      --   vim.cmd.normal("S]f]a()")
      --   vim.cmd.startinsert()
      -- end, { desc = "Make markdown hyperlink" })
    end,
  },
  {
    "chaoren/vim-wordmotion",
    event = "VeryLazy",
    -- use init instead of config to set variables before loading the plugin
    init = function()
      vim.g.wordmotion_prefix = "<space>"
    end,
  },
  ---Yank
  {
    "aserowy/tmux.nvim",
    keys = {
      "<C-h>",
      "<C-j>",
      "<C-k>",
      "<C-l>",
      { "<C-A-i>", [[<cmd>lua require("tmux").resize_top()<cr>]] },
      { "<C-A-u>", [[<cmd>lua require("tmux").resize_bottom()<cr>]] },
      { "<C-A-y>", [[<cmd>lua require("tmux").resize_left()<cr>]] },
      { "<C-A-o>", [[<cmd>lua require("tmux").resize_right()<cr>]] },
      { "<F16>", [[<cmd>lua require("tmux").resize_top()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <S-F3>
      { "<F15>", [[<cmd>lua require("tmux").resize_top()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <S-F2>
      { "<F18>", [[<cmd>lua require("tmux").resize_bottom()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <S-F6>
      { "<F27>", [[<cmd>lua require("tmux").resize_left()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <C-F3>
      { "<F26>", [[<cmd>lua require("tmux").resize_left()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <C-F2>
      { "<F30>", [[<cmd>lua require("tmux").resize_right()<cr>]], mode = { "n", "i", "x", "s", "o" } }, -- <C-F6>
      "<C-n>",
      "<C-p>",
      -- { '"', mode = { "n", "x" } },
      -- { "<C-r>", mode = { "i" } },
      { "p", mode = { "n", "x", "o", "s" } },
      { "P", mode = { "n", "x", "o", "s" } },
      { "=p", mode = { "n", "x", "o", "s" } },
      { "=P", mode = { "n", "x", "o", "s" } },
      { "y", mode = { "x", "o", "s" } },
      { "d", mode = { "x", "o", "s" } },
      { "c", mode = { "x", "o", "s" } },
      { "Y", mode = { "n", "x", "o", "s" } },
      { "D", mode = { "n", "x", "o", "s" } },
      { "C", mode = { "n", "x", "o", "s" } },
    },
    dependencies = {
      "gbprod/yanky.nvim",
      "nvim-telescope/telescope.nvim",
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("kiyoon.tmux-yanky")
      -- After initialising yanky, this mapping gets lost so we do this here.
      vim.cmd([[nnoremap Y y$]])
    end,
  },
  {
    "y3owk1n/undo-glow.nvim",
    version = "*", -- remove this if you want to use the `main` branch
    opts = {
      animation = {
        enabled = true,
        duration = 500,
        animtion_type = "zoom",
      },
      highlights = {
        undo = {
          hl_color = { bg = "#693232" }, -- Dark muted red
        },
        redo = {
          hl_color = { bg = "#2F4640" }, -- Dark muted green
        },
        yank = {
          hl_color = { bg = "#7A683A" }, -- Dark muted yellow
        },
        paste = {
          hl_color = { bg = "#325B5B" }, -- Dark muted cyan
        },
        search = {
          hl_color = { bg = "#5C475C" }, -- Dark muted purple
        },
        comment = {
          hl_color = { bg = "#7A5A3D" }, -- Dark muted orange
        },
        cursor = {
          hl_color = { bg = "#793D54" }, -- Dark muted pink
        },
      },
      priority = 2048 * 3,
    },
    keys = {
      {
        "u",
        function()
          require("undo-glow").undo()
        end,
        mode = "n",
        desc = "Undo with highlight",
        noremap = true,
      },
      {
        "<C-r>",
        function()
          require("undo-glow").redo()
        end,
        mode = "n",
        desc = "Redo with highlight",
        noremap = true,
      },
    },
  },
  {
    "github/copilot.vim",
    -- event = "InsertEnter",
    -- cmd = { "Copilot" },
    init = function()
      vim.g.copilot_no_tab_map = true
      vim.cmd([[imap <silent><script><expr> <C-s> copilot#Accept("")]])
      vim.cmd([[imap <silent><script><expr> <F7> copilot#Accept("")]])

      -- delete word in INSERT mode
      -- you can use <C-w> but this is for consistency with github copilot
      -- using <A-Right> to accept a word.
      vim.cmd([[inoremap <A-Left> <C-\><C-o>db]])
      vim.cmd([[inoremap <A-BS> <C-\><C-o>db]]) -- consistency with zsh and bash
      vim.cmd([[inoremap <F2> <C-\><C-o>db]])
      vim.cmd([[inoremap <F3> <C-\><C-o>db]])
      vim.cmd([[inoremap <F5> <Plug>(copilot-accept-word)]])
      vim.cmd([[inoremap <F6> <Plug>(copilot-accept-word)]])
    end,
  },
  --- NOTE: Treesitter: Better syntax highlighting, text objects, refactoring, context
  {
    "nvim-treesitter/nvim-treesitter",
    event = { "BufReadPost", "BufNewFile" },
    build = ":TSUpdate",
    init = function(plugin)
      -- PERF: add nvim-treesitter queries to the rtp and it's custom query predicates early
      -- This is needed because a bunch of plugins no longer `require("nvim-treesitter")`, which
      -- no longer trigger the **nvim-treesitter** module to be loaded in time.
      -- Luckily, the only things that those plugins need are the custom queries, which we make available
      -- during startup.
      require("lazy.core.loader").add_to_rtp(plugin)
      -- require("nvim-treesitter.query_predicates")
    end,
    config = function()
      require("kiyoon.treesitter")
    end,
    dependencies = {
      {
        "nvim-treesitter/nvim-treesitter-textobjects",
        -- "kiyoon/nvim-treesitter-textobjects",
        -- branch = "fix/builtin_find",
        dev = nvim_treesitter_textobjects_dev,
      },
      "RRethy/nvim-treesitter-endwise",
      {
        "andymass/vim-matchup",
        init = function()
          --- Without this, lualine will flicker when matching offscreen
          --- Maybe it happens when cmdheight is set to 0
          vim.g.matchup_matchparen_offscreen = { method = "popup" }
        end,
      },
      {
        "HiPhish/rainbow-delimiters.nvim",
        config = function()
          -- https://github.com/ayamir/nvimdots/pull/868/files
          ---@param threshold number @Use global strategy if nr of lines exceeds this value
          local function init_strategy(threshold)
            return function()
              local errors = 200
              vim.treesitter.get_parser():for_each_tree(function(lt)
                if lt:root():has_error() and errors >= 0 then
                  errors = errors - 1
                end
              end)
              if errors < 0 then
                return nil
              end
              return vim.fn.line("$") > threshold and require("rainbow-delimiters").strategy["global"]
                or require("rainbow-delimiters").strategy["local"]
            end
          end

          vim.g.rainbow_delimiters = {
            strategy = {
              [""] = init_strategy(500),
              c = init_strategy(200),
              cpp = init_strategy(200),
              lua = init_strategy(500),
              vimdoc = init_strategy(300),
              vim = init_strategy(300),
              markdown = require("rainbow-delimiters").strategy["global"], -- markdown parser is slow
            },
            query = {
              [""] = "rainbow-delimiters",
              latex = "rainbow-blocks",
              javascript = "rainbow-delimiters-react",
            },
            highlight = {
              "RainbowDelimiterRed",
              "RainbowDelimiterOrange",
              "RainbowDelimiterYellow",
              "RainbowDelimiterGreen",
              "RainbowDelimiterBlue",
              "RainbowDelimiterCyan",
              "RainbowDelimiterViolet",
            },
          }
        end,
      },
    },
    dev = nvim_treesitter_dev,
  },
  {
    "lukas-reineke/indent-blankline.nvim",
    tag = "v2.20.8",
    -- main = "ibl",
    -- opts = {},
    event = "BufReadPost",
    config = function()
      vim.opt.list = true
      --vim.opt.listchars:append "space:⋅"
      --vim.opt.listchars:append "eol:↴"

      -- local highlight = {
      --   "RainbowDelimiterRed",
      --   "RainbowDelimiterOrange",
      --   "RainbowDelimiterYellow",
      --   "RainbowDelimiterGreen",
      --   "RainbowDelimiterBlue",
      --   "RainbowDelimiterCyan",
      --   "RainbowDelimiterViolet",
      -- }
      -- local hooks = require "ibl.hooks"
      -- -- create the highlight groups in the highlight setup hook, so they are reset
      -- -- every time the colorscheme changes
      -- hooks.register(hooks.type.HIGHLIGHT_SETUP, function()
      --     vim.api.nvim_set_hl(0, "RainbowRed", { fg = "#E06C75" })
      --     vim.api.nvim_set_hl(0, "RainbowYellow", { fg = "#E5C07B" })
      --     vim.api.nvim_set_hl(0, "RainbowBlue", { fg = "#61AFEF" })
      --     vim.api.nvim_set_hl(0, "RainbowOrange", { fg = "#D19A66" })
      --     vim.api.nvim_set_hl(0, "RainbowGreen", { fg = "#98C379" })
      --     vim.api.nvim_set_hl(0, "RainbowViolet", { fg = "#C678DD" })
      --     vim.api.nvim_set_hl(0, "RainbowCyan", { fg = "#56B6C2" })
      -- end)
      --
      -- require("ibl").setup { scope = { highlight = highlight } }
      -- hooks.register(hooks.type.SCOPE_HIGHLIGHT, hooks.builtin.scope_highlight_from_extmark)
      require("indent_blankline").setup({
        space_char_blankline = " ",
        show_current_context = true,
        show_current_context_start = true,
      })
    end,
  },
  {
    "folke/flash.nvim",
    event = "VeryLazy",
    ---@type Flash.Config
    opts = {
      modes = {
        -- sometimes search results may not exist in a file.
        -- but flash search will accidentally match something else.
        -- e.g. I want to search for "enabled" but it matches "english"
        -- because "en" is in "english" and when you type a it matches the first one.
        -- so I disable search mode.
        search = {
          enabled = false,
        },
        -- Use nvim-treesitter-textobjects' repetable_move instead.
        char = {
          enabled = false,
        },
      },
    },
    -- stylua: ignore
    keys = {
      { "s", mode = { "n", "x", "o" }, function() require("flash").jump() end, desc = "Flash" },
      { "m", mode = { "n", "x", "o" }, function() require("flash").treesitter() end, desc = "Flash Treesitter" },
      { "M", "m", noremap = true, desc = "[M]ark" },
      { "r", mode = "o", function() require("flash").remote() end, desc = "Remote Flash" },
      { "R", mode = { "o", "x" }, function() require("flash").treesitter_search() end, desc = "Treesitter Search" },
      { "<c-s>", mode = { "c" }, function() require("flash").toggle() end, desc = "Toggle Flash Search" },
    },
  },
  -- Telescope
  {
    "nvim-telescope/telescope.nvim",
    cmd = { "Telescope" },
    -- branch = "0.1.x",
    keys = {
      {
        "<leader>fF",
        "<cmd>lua require('telescope.builtin').git_files()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]uzzy [F]ind Git [F]iles",
      },
      {
        "<leader>ff",
        "<cmd>lua require('telescope.builtin').find_files()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]uzzy [F]ind [F]iles",
      },
      {
        "<leader>fW",
        "<cmd>lua require('telescope.builtin').live_grep()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind [W]ord",
      },
      {
        "<leader>fw",
        "<cmd>lua require('kiyoon.telescope').live_grep_gitdir()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind [W]ord in git dir",
      },
      {
        "<leader>fiw",
        "<cmd>lua require('kiyoon.telescope').grep_string_gitdir()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind [i]nner [w]ord in git dir",
      },
      {
        "<leader>fg",
        "<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<cr>",
        desc = "Live grep with args",
      },
      {
        "<leader>fr",
        "<cmd>lua require('telescope.builtin').oldfiles()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind [R]ecent files",
      },
      {
        "<leader>fb",
        "<cmd>lua require('telescope.builtin').buffers()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind [B]uffers",
      },
      {
        "<leader>fh",
        "<cmd>lua require('telescope.builtin').help_tags()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]ind in vim [H]elp",
      },
      {
        "<leader>fs",
        "<cmd>lua require('telescope.builtin').current_buffer_fuzzy_find()<cr>",
        noremap = true,
        silent = true,
        desc = "[F]uzzy [S]earch Current Buffer",
      },
    },
    init = function()
      local status, wk = pcall(require, "which-key")
      if status then
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
      {
        "nvim-telescope/telescope-live-grep-args.nvim",
      },
    },
    config = function()
      require("kiyoon.telescope")
    end,
  },

  --- NOTE: LSP
  --
  -- CoC supports out-of-the-box features like inlay hints
  -- which isn't possible with native LSP yet.
  -- {
  --   "neoclide/coc.nvim",
  --   -- branch = "release",
  --   commit = "bbaa1d5d1ff3cbd9d26bb37cfda1a990494c4043",
  --   ft = "python",
  --   init = function()
  --     vim.cmd [[ hi link CocInlayHint LspInlayHint ]]
  --     vim.g.coc_data_home = vim.fn.stdpath "data" .. "/coc"
  --   end,
  --   config = function()
  --     vim.cmd [[
  --       call coc#add_extension('coc-pyright')
  --     ]]
  --   end,
  -- },

  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    cmd = {
      "Mason",
      "MasonUpdate",
    },
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
            -- Library items can be absolute paths
            "~/project/nvim-treesitter-textobjects",
            "~/project/jupynium.nvim",
            "~/project/python-import.nvim",
            -- Or relative, which means they will be resolved as a plugin
            -- "LazyVim",
            -- When relative, you can also provide a path to the library in the plugin dir
            -- "luvit-meta/library", -- see below
            { path = "luvit-meta/library", words = { "vim%.uv" } },
          },
        },
      },
    },
    config = function()
      require("kiyoon.lsp")
    end,
  },
  {
    "L3MON4D3/LuaSnip",
    version = "v2.x",
    event = "InsertEnter",
    dependencies = {
      "rafamadriz/friendly-snippets",
    },
    config = function()
      require("kiyoon.luasnip")
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    -- event = "InsertEnter",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-calc",
      "hrsh7th/cmp-emoji",
      "chrisgrieser/cmp-nerdfont",
      "saadparwaiz1/cmp_luasnip",
      "onsails/lspkind.nvim", -- display icons
    },
    config = function()
      require("kiyoon.cmp")
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
    -- event = "LSPAttach",
    event = "BufReadPre",
    config = function()
      local cfg = {
        on_attach = function(client, bufnr)
          require("lsp_signature").on_attach({
            bind = true, -- This is mandatory, otherwise border config won't get registered.
            handler_opts = {
              border = "rounded",
            },
          }, bufnr)
        end,
        -- debug = true, -- set to true to enable debug logging
        -- log_path = vim.fn.stdpath "cache" .. "/lsp_signature.log", -- log dir when debug is on
        -- default is  ~/.cache/nvim/lsp_signature.log
        -- verbose = true, -- show debug line number
      }
      require("lsp_signature").setup(cfg)
    end,
  },
  -- Show current context in lualine (statusline)
  {
    "SmiteshP/nvim-navic",
    lazy = true,
    init = function()
      vim.g.navic_silence = true
      vim.api.nvim_create_augroup("LspAttach_navic", {})
      vim.api.nvim_create_autocmd("LspAttach", {
        group = "LspAttach_navic",
        callback = function(args)
          if not (args.data and args.data.client_id) then
            return
          end

          local bufnr = args.buf
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client.server_capabilities.documentSymbolProvider then
            require("nvim-navic").attach(client, bufnr)
          end
        end,
      })
    end,
    opts = function()
      return {
        separator = " ",
        highlight = true,
        depth_limit = 5,
        icons = icons.kinds,
      }
    end,
  },

  -- Formatting and linting
  {
    -- "jose-elias-alvarez/null-ls.nvim",
    "nvimtools/none-ls.nvim",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("kiyoon.lsp.null-ls")
    end,
  },
  {
    "stevearc/conform.nvim",
    event = { "BufWritePre" },
    cmd = { "ConformInfo" },
    keys = {
      {
        -- Customize or remove this keymap to your liking
        "<space>pf",
        function()
          require("conform").format({ async = true, lsp_fallback = true })
        end,
        mode = "",
        desc = "Format buffer",
      },
    },
    -- Everything in opts will be passed to setup()
    opts = {
      -- Define your formatters
      formatters_by_ft = {
        lua = { "stylua" },
        -- python = { "isort", "black" },
        python = { "ruff_fix", "ruff_format" },
        -- javascript = { { "prettierd", "prettier" } },
        -- typescript = { { "prettierd", "prettier" } },
        javascript = { "biome-organize-imports", "biome" },
        typescript = { "biome-organize-imports", "biome" },
        javascriptreact = { "biome-organize-imports", "biome" },
        typescriptreact = { "biome-organize-imports", "biome" },
        html = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettier" },
        -- json = { "prettier" },
        json = { "biome" },
        jsonc = { "biome" },
        css = { "biome" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        cs = { "csharpier" },
        toml = { "taplo" },
      },
      -- Set up format-on-save
      format_on_save = { timeout_ms = 2000, lsp_fallback = true },
      -- Customize formatters
      formatters = {
        shfmt = {
          prepend_args = { "-i", "2" },
        },
        -- isort = {
        --   prepend_args = { "--profile", "black" },
        -- },
        ruff_fix = {
          -- I: isort
          -- D20, D21: docstring
          -- UP00: upgrade to python 3.10
          -- UP032: f-string over str.format
          -- UP034: extraneous parentheses
          -- ruff:[RUF100]: unused noqa

          -- IGNORED:
          -- ruff:[D212]: multi-line docstring summary should start at the first line (in favor of D213, second line)
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

        -- biome_assist = {
        --   command = "biome",
        --   args = {
        --     "check",
        --     "--write",
        --     "--linter-enabled=false",
        --     "--formatter-enabled=false",
        --     "--assist-enabled=true",
        --     "--stdin-file-path",
        --     "$FILENAME",
        --   },
        --   stdin = true,
        -- },
      },
    },
    init = function()
      -- If you want the formatexpr, here is the place to set it
      vim.o.formatexpr = "v:lua.require'conform'.formatexpr()"
    end,
  },
  --- NOTE: UI
  --
  -- Beautiful command menu
  {
    "gelguy/wilder.nvim",
    build = ":UpdateRemotePlugins",
    dependencies = {
      {
        "romgrk/fzy-lua-native",
        -- build = "make",
      },
    },
    event = "CmdlineEnter",
    config = function()
      require("kiyoon.wilder")
    end,
  },
  -- better vim.notify()
  {
    "rcarriga/nvim-notify",
    event = "VeryLazy",
    keys = {
      {
        "<leader>un",
        function()
          require("notify").dismiss({ silent = true, pending = true })
        end,
        desc = "Delete all Notifications",
      },
    },
    opts = {
      stages = "fade_in_slide_out",
      -- stages = "slide",
      timeout = 3000,
      max_height = function()
        return math.floor(vim.o.lines * 0.75)
      end,
      max_width = function()
        return math.floor(vim.o.columns * 0.75)
      end,
    },
    config = function(_, opts)
      require("notify").setup(opts)
      vim.notify = require("notify")
    end,
  },

  -- better vim.ui
  {
    "stevearc/dressing.nvim",
    lazy = true,
    init = function()
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.select = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.select(...)
      end
      ---@diagnostic disable-next-line: duplicate-set-field
      vim.ui.input = function(...)
        require("lazy").load({ plugins = { "dressing.nvim" } })
        return vim.ui.input(...)
      end
    end,
  },
  -- Settings from LazyVim
  {
    "folke/todo-comments.nvim",
    cmd = { "TodoTrouble", "TodoTelescope" },
    event = { "BufReadPost", "BufNewFile" },
    dependencies = "nvim-lua/plenary.nvim",
    config = function()
      local todo_comments = require("todo-comments")
      todo_comments.setup({
        -- match TODO(scope):
        -- See https://github.com/folke/todo-comments.nvim/pull/255
        highlight = {
          -- vimgrep regex, supporting the pattern TODO(name):
          pattern = [[.*<((KEYWORDS)%(\(.{-1,}\))?):]],
        },
        search = {
          -- ripgrep regex, supporting the pattern TODO(name):
          pattern = [[\b(KEYWORDS)(\(\w*\))*:]],
        },
      })
      local tstext = require("nvim-treesitter.textobjects.repeatable_move")
      local next_todo, prev_todo = tstext.make_repeatable_move_pair(todo_comments.jump_next, todo_comments.jump_prev)
      vim.keymap.set("n", "]t", next_todo, { desc = "Next todo comment" })

      vim.keymap.set("n", "[t", prev_todo, { desc = "Previous todo comment" })

      -- You can also specify a list of valid jump keywords

      -- vim.keymap.set("n", "]t", function()
      --   require("todo-comments").jump_next({keywords = { "ERROR", "WARNING" }})
      -- end, { desc = "Next error/warning todo comment" })
    end,
  },
  -- Dashboard
  {
    "goolord/alpha-nvim",
    event = "VimEnter",
    config = function()
      require("kiyoon.alpha")
    end,
  },
  {
    "luukvbaal/statuscol.nvim",
    config = function()
      require("kiyoon.statuscol")
    end,
  },

  --- NOTE: Utils
  {
    "dstein64/vim-startuptime",
    cmd = "StartupTime",
    config = function()
      vim.g.startuptime_tries = 10
    end,
  },
  {
    "mbbill/undotree",
    cmd = "UndotreeToggle",
    keys = {
      { "<space>u", "<cmd>UndotreeToggle<CR>", mode = { "n", "x" }, desc = "Undotree Toggle" },
    },
  },
  -- search/replace in multiple files
  {
    "windwp/nvim-spectre",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    -- stylua: ignore
    keys = {
      { "<leader>sr", function() require("spectre").open() end, desc = "Replace in files (Spectre)" },
    },
  },
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    config = function()
      -- vim.o.timeout = true
      -- vim.o.timeoutlen = 600
      require("which-key").setup({
        delay = 600,
      })

      -- Sync with tmux registers
      -- https://github.com/folke/which-key.nvim/issues/743#issuecomment-2234460129
      local reg = require("which-key.plugins.registers")
      local expand = reg.expand

      function reg.expand()
        if vim.env.TMUX then
          require("tmux.copy").sync_registers()
        end
        return expand()
      end
    end,
  },
  -- {
  --   "mechatroner/rainbow_csv",
  --   ft = "csv",
  -- },
  -- {
  --   "cameron-wags/rainbow_csv.nvim",
  --   opts = {},
  --   ft = {
  --     "csv",
  --     "tsv",
  --     "csv_semicolon",
  --     "csv_whitespace",
  --     "csv_pipe",
  --     "rfc_csv",
  --     "rfc_semicolon",
  --   },
  -- },
  {
    "fei6409/log-highlight.nvim",
    config = function()
      require("log-highlight").setup({
        -- The file extensions.
        extension = "log",

        -- The file path glob patterns, e.g. `.*%.lg`, `/var/log/.*`.
        -- Note: `%.` is to match a literal dot (`.`) in a pattern in Lua, but most
        -- of the time `.` and `%.` here make no observable difference.
        pattern = {
          "/var/log/.*",
          "messages%..*",
        },
      })
    end,
  },
  {
    "andythigpen/nvim-coverage",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    config = function()
      require("coverage").setup()
    end,
  },
  {
    "kiyoon/Korean-IME.nvim",
    dev = korean_ime_dev,
    keys = {
      -- lazy load on 한영전환
      {
        "<f12>",
        function()
          require("korean_ime").change_mode()
        end,
        mode = { "i", "n", "x", "s" },
        desc = "한/영",
      },
    },
    config = function()
      require("korean_ime").setup()
      vim.keymap.set("i", "<f9>", function()
        require("korean_ime").convert_hanja()
      end, { noremap = true, silent = true, desc = "한자" })
    end,
  },
  {
    -- required for wookayin/dotfiles, the python keymaps
    -- which is in kiyoon/python_utils.lua
    "tpope/vim-repeat",
  },
  {
    "linrongbin16/gitlinker.nvim",
    config = function()
      require("gitlinker").setup()
    end,
  },
  {
    -- There are four types of python highlighting.
    -- 1. Default vim python (syntax highlighting)
    -- 2. This plugin (syntax highlighting)
    -- 3. nvim-treesitter (syntax highlighting)
    -- 4. basedpyright (semantic highlighting)
    --
    -- I want to use 4, so I disabled 3 which is distracting. (It's good but too much color)
    -- However, then it was sometimes confusing if f-strings were actually f-strings. (the values were not highlighted)
    -- with this plugin (2), I can see the f-strings are actually f-strings, but it doesn't hurt the 4.
    -- "vim-python/python-syntax",
    "wmvanvliet/python-syntax",
    ft = "python",
    init = function()
      -- I only care about string highlighting here.
      -- vim.g.python_highlight_all = 1
      vim.g.python_highlight_string_formatting = 1
      vim.g.python_highlight_string_format = 1
      vim.g.python_highlight_string_templates = 1
      vim.g.python_highlight_builtin_funcs = 1
      vim.g.python_highlight_builtin_objs = 1
      vim.g.python_highlight_builtin_types = 1
    end,
  },
}
