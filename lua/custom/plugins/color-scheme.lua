return {
    "catppuccin/nvim",
    name = "catppuccin",
    priority = 1000, -- Ensures the theme is loaded early
    config = function()
        require("catppuccin").setup({
            flavour = "macchiato", -- Choose between latte, frappe, macchiato, mocha
            background = { -- Background settings
                light = "latte",
                dark = "mocha",
            },
            transparent_background = true, -- Disable background color transparency
            show_end_of_buffer = false, -- Disable '~' characters after end of buffer
            term_colors = false, -- Disable terminal colors
            dim_inactive = { -- Dimming inactive windows
                enabled = false,
                shade = "dark",
                percentage = 0.15,
            },
            no_italic = false, -- Allow italics
            no_bold = false, -- Allow bold
            no_underline = false, -- Allow underline
            styles = { -- Syntax group styling
                comments = { "italic" }, -- Italic comments
                conditionals = { "italic" },
                loops = {},
                functions = {},
                keywords = {},
                strings = {},
                variables = {},
                numbers = {},
                booleans = {},
                properties = {},
                types = {},
                operators = {},
            },
            color_overrides = {}, -- No custom color overrides
            custom_highlights = {}, -- No custom highlight overrides
            integrations = { -- Plugin integrations
                cmp = true, -- nvim-cmp integration
                gitsigns = true, -- gitsigns integration
                nvimtree = true, -- nvim-tree integration
                treesitter = true, -- treesitter integration
                notify = false, -- Disable nvim-notify integration
                mini = {
                    enabled = true,
                    indentscope_color = "", -- Leave empty to use default color
                },
            },
        })

        -- Set the colorscheme after the setup
        vim.cmd("colorscheme catppuccin")
    end
}
