local wezterm = require("wezterm")

local config = {
    color_scheme = "Dracula (Official)",

    -- Native Wayland can leave IBus/Hangul inactive in WezTerm after login on
    -- GNOME. XWayland uses the more reliable IBus/XIM path.
    enable_wayland = false,
    use_ime = true,
    font = wezterm.font_with_fallback({
        -- "Cascadia Code NF",
        "JetBrainsMono Nerd Font",
        "Pretendard",
        "Noto Sans CJK KR",
        "NanumGothic",
        "Fira Code Nerd Font",
    }),
    font_size = 12.5,
    window_frame = {
        font_size = 10,
    },

    max_fps = 60,

    window_decorations = "NONE",

    -- undercurl becomes ugly if underline_position < -4
    underline_position = -4,
    keys = {
        {
            -- Used in neovim (python-import.nvim)
            key = "Enter",
            mods = "ALT",
            action = wezterm.action.DisableDefaultAssignment,
        },
        {
            key = "r",
            mods = "CMD|SHIFT",
            action = wezterm.action.ReloadConfiguration,
        },
        {
            key = "F3",
            mods = "CMD|SHIFT",
            action = wezterm.action.ActivateTabRelative(-1),
        },
        {
            key = "F2",
            mods = "CMD|SHIFT",
            action = wezterm.action.ActivateTabRelative(-1),
        },
        {
            key = "F6",
            mods = "CMD|SHIFT",
            action = wezterm.action.ActivateTabRelative(1),
        },
        { key = "t", mods = "CTRL", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
        { key = "w", mods = "CTRL", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
        { key = "1", mods = "CTRL", action = wezterm.action.ActivateTab(0) },
        { key = "2", mods = "CTRL", action = wezterm.action.ActivateTab(1) },
        { key = "3", mods = "CTRL", action = wezterm.action.ActivateTab(2) },
        { key = "4", mods = "CTRL", action = wezterm.action.ActivateTab(3) },
        { key = "5", mods = "CTRL", action = wezterm.action.ActivateTab(4) },
        { key = "6", mods = "CTRL", action = wezterm.action.ActivateTab(5) },
        { key = "7", mods = "CTRL", action = wezterm.action.ActivateTab(6) },
        { key = "8", mods = "CTRL", action = wezterm.action.ActivateTab(7) },
        { key = "9", mods = "CTRL", action = wezterm.action.ActivateTab(8) },
        {
            key = "D",
            mods = "CMD|SHIFT",
            action = wezterm.action_callback(function(win, pane)
                local tab, window = pane:move_to_new_window()
            end),
        },
        {
            key = "C",
            mods = "CMD|SHIFT",
            action = wezterm.action_callback(function(win, pane)
                local tab, window = pane:move_to_new_tab()
            end),
        },
        {
            key = "|",
            mods = "CTRL|SHIFT|ALT",
            action = wezterm.action.SplitPane({
                direction = "Right",
                -- command = { args = { "top" } },
                size = { Percent = 50 },
            }),
        },
        {
            key = "_",
            mods = "CTRL|SHIFT|ALT",
            action = wezterm.action.SplitPane({
                direction = "Down",
                -- command = { args = { "top" } },
                size = { Percent = 50 },
            }),
        },
        -- OSC 133
        -- need to enable shell integration
        -- https://wezterm.org/shell-integration.html
        { key = "UpArrow", mods = "SHIFT", action = wezterm.action.ScrollToPrompt(-1) },
        { key = "DownArrow", mods = "SHIFT", action = wezterm.action.ScrollToPrompt(1) },
    },

    enable_scroll_bar = true,
    scrollback_lines = 30000,

    enable_kitty_graphics = true,
}

-- disable ctrl+shift +/- zooming
-- in favour of using cmd + = and cmd + -
if wezterm.target_triple == "aarch64-apple-darwin" then
    table.insert(config.keys, {
        key = "+",
        mods = "CTRL|SHIFT",
        action = wezterm.action.DisableDefaultAssignment,
    })
    table.insert(config.keys, {
        key = "_",
        mods = "CTRL|SHIFT",
        action = wezterm.action.DisableDefaultAssignment,
    })
end

-- config.hyperlink_rules = wezterm.default_hyperlink_rules()
-- NOTE: the default rule doesn't work well with parens, brackets, or braces.
-- Updated rules following https://github.com/wez/wezterm/issues/3803
config.hyperlink_rules = {
    -- Rewrite bare: ssh://github.com/...  -->  https://github.com/...
    -- Put this BEFORE any generic \w+:// rules in your real config.
    {
        regex = [[\bssh://(github\.com)/?([^\s)\]\}>]*)?]],
        format = "https://$1/$2",
    },
    -- Matches: a URL in parens: (URL)
    {
        regex = "\\((\\w+://\\S+)\\)",
        format = "$1",
        highlight = 1,
    },
    -- Matches: a URL in brackets: [URL]
    {
        regex = "\\[(\\w+://\\S+)\\]",
        format = "$1",
        highlight = 1,
    },
    -- Matches: a URL in curly braces: {URL}
    {
        regex = "\\{(\\w+://\\S+)\\}",
        format = "$1",
        highlight = 1,
    },
    -- Matches: a URL in angle brackets: <URL>
    {
        regex = "<(\\w+://\\S+)>",
        format = "$1",
        highlight = 1,
    },
    -- Then handle URLs not wrapped in brackets
    -- {
    --     regex = "[^(]\\b(\\w+://\\S+[)/a-zA-Z0-9-]+)",
    --     format = "$1",
    --     highlight = 1,
    -- },
    {
        regex = "(?<![\\(\\{\\[<])\\b\\w+://\\S+",
        format = "$0",
    },
    -- NOTE(kiyoon): hyperlink at the beginning of the line doesn't work
    -- handle it.
    -- {
    --     regex = "^\\b(\\w+://\\S+[)/a-zA-Z0-9-]+)",
    --     format = "$1",
    --     highlight = 1,
    -- },
    -- implicit mailto link
    {
        regex = "\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b",
        format = "mailto:$0",
    },
}

-- make username/project paths clickable. this implies paths like the following are for github.
-- ( "nvim-treesitter/nvim-treesitter" | wbthomason/packer.nvim | wez/wezterm | "wez/wezterm.git" )
-- as long as a full url hyperlink regex exists above this it should not match a full url to
-- github or gitlab / bitbucket (i.e. https://gitlab.com/user/project.git is still a whole clickable url)
table.insert(config.hyperlink_rules, {
    regex = [[["'\s]([\w\d]{1}[-\w\d]+)(/){1}([-\w\d\.]+)["'\s]] .. "]",
    format = "https://www.github.com/$1/$3",
})

-- Example:
--     ruff: Mixed spaces and tabs [E101]
table.insert(config.hyperlink_rules, {
    regex = [[🔗🐍 \[(\w+)\]] .. "]",
    format = "https://docs.astral.sh/ruff/rules/$1",
})
table.insert(config.hyperlink_rules, {
    regex = [[🔗🐍b \[(\w+)\]] .. "]",
    format = "https://docs.basedpyright.com/latest/configuration/config-files/#$1",
})

table.insert(config.hyperlink_rules, {
    regex = [[🔗🐚 \[(\w+)\]] .. "]",
    format = "https://shellcheck.net/wiki/$1",
})

-- rustc error
table.insert(config.hyperlink_rules, {
    regex = [[🔗🦀 \[E([0-9]+)\]] .. "]",
    format = "https://doc.rust-lang.org/error_codes/E$1.html",
})
-- rustc lint warning
table.insert(config.hyperlink_rules, {
    regex = [[🔗🦀 \[([a-z0-9_]+)\]] .. "]",
    format = "https://doc.rust-lang.org/rustc/?search=$1",
})
-- clippy
table.insert(config.hyperlink_rules, {
    regex = [[🔗🦀cl \[([a-z0-9_]+)\]] .. "]",
    format = "https://rust-lang.github.io/rust-clippy/master/index.html#$1",
})

table.insert(config.hyperlink_rules, {
    regex = [[🔗🌜d \[(.*)\]] .. "]",
    format = "https://luals.github.io/wiki/diagnostics/#$1",
})

table.insert(config.hyperlink_rules, {
    regex = [[🔗🌜s \[(.*)\]] .. "]",
    format = "https://luals.github.io/wiki/syntax-errors/#$1",
})

-- biome
table.insert(config.hyperlink_rules, {
    regex = [[🔗 \[([a-z0-9-]+)]] .. "]",
    format = "https://biomejs.dev/linter/rules/$1",
})
table.insert(config.hyperlink_rules, {
    regex = [[\[lint/.*/(.*)\]] .. "]",
    format = "https://next.biomejs.dev/linter/rules/$1",
})

-- selene
table.insert(config.hyperlink_rules, {
    regex = [[🔗selene \[([a-z0-9_]+)\]] .. "]",
    format = "https://kampfkarren.github.io/selene/lints/$1.html",
})

config.colors = {
    scrollbar_thumb = "#392a48",
}

-- From wezterm doc
config.colors.tab_bar = {
    -- The color of the strip that goes along the top of the window
    -- (does not apply when fancy tab bar is in use)
    background = "#0b0022",

    -- The active tab is the one that has focus in the window
    active_tab = {
        -- The color of the background area for the tab
        bg_color = "#2b2042",
        -- The color of the text for the tab
        fg_color = "#c0c0c0",

        -- Specify whether you want "Half", "Normal" or "Bold" intensity for the
        -- label shown for this tab.
        -- The default is "Normal"
        intensity = "Normal",

        -- Specify whether you want "None", "Single" or "Double" underline for
        -- label shown for this tab.
        -- The default is "None"
        underline = "None",

        -- Specify whether you want the text to be italic (true) or not (false)
        -- for this tab.  The default is false.
        italic = false,

        -- Specify whether you want the text to be rendered with strikethrough (true)
        -- or not for this tab.  The default is false.
        strikethrough = false,
    },

    -- Inactive tabs are the tabs that do not have focus
    inactive_tab = {
        bg_color = "#1b1032",
        fg_color = "#808080",

        -- The same options that were listed under the `active_tab` section above
        -- can also be used for `inactive_tab`.
    },

    -- You can configure some alternate styling when the mouse pointer
    -- moves over inactive tabs
    inactive_tab_hover = {
        bg_color = "#3b3052",
        fg_color = "#909090",
        italic = true,

        -- The same options that were listed under the `active_tab` section above
        -- can also be used for `inactive_tab_hover`.
    },

    -- The new tab button that let you create new tabs
    new_tab = {
        bg_color = "#1b1032",
        fg_color = "#808080",

        -- The same options that were listed under the `active_tab` section above
        -- can also be used for `new_tab`.
    },

    -- You can configure some alternate styling when the mouse pointer
    -- moves over the new tab button
    new_tab_hover = {
        bg_color = "#3b3052",
        fg_color = "#909090",
        italic = true,

        -- The same options that were listed under the `active_tab` section above
        -- can also be used for `new_tab_hover`.
    },
}

config.window_background_opacity = 1
config.macos_window_background_blur = 20

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
    config.default_prog = { "pwsh.exe", "-NoLogo" }
else
    config.term = "wezterm"
end

wezterm.on("gui-startup", function(cmd)
    local _, _, window = wezterm.mux.spawn_window(cmd or {})
    window:gui_window():maximize()
end)

return config
