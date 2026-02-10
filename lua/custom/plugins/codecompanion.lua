---@param params table Table containing message and allowed_words
---@return table The filtered message
local function filter_out_messages(params)
  local message = params.message

  local allowed = params.allowed_words

  for key, _ in pairs(message) do
    if not vim.tbl_contains(allowed, key) then
      message[key] = nil
    end
  end
  return message
end

return {
  'olimorris/codecompanion.nvim',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-treesitter/nvim-treesitter',
    'ravitemer/mcphub.nvim',
  },
  opts = {
    adapters = {
      acp = {
        opencode = function()
          return require('codecompanion.adapters').extend('opencode', {
            commands = {
              default = {
                'opencode',
                'acp',
              },
              anthropic_sonnet_4_5 = {
                'opencode',
                'acp',
                '-m',
                'anthropic/claude-sonnet-4.5',
              },
              anthropic_opus_4_5 = {
                'opencode',
                'acp',
                '-m',
                'anthropic/claude-opus-4.5',
              },
            },
          })
        end,
      },
    },
    opts = {
      log_level = 'DEBUG',
    },
    strategies = {
      inline = {
        adapter = 'opencode',
      },
      cmd = {
        adapter = 'opencode',
      },

      chat = {
        --- adapter = 'codex',
        adapter = 'opencode',
        --- adapter = 'qwen3',
        variables = {
          ['buffer'] = {
            callback = 'strategies.chat.variables.buffer',
            description = 'Share the current buffer with the LLM',
            opts = {
              contains_code = true,
              default_params = 'watch', -- watch|pin
              has_params = true,
              excluded = {
                buftypes = {
                  'nofile',
                  'quickfix',
                  'prompt',
                  'popup',
                },
                fts = {
                  'codecompanion',
                  'help',
                  'terminal',
                },
              },
            },
          },
          ['lsp'] = {
            callback = 'strategies.chat.variables.lsp',
            description = 'Share LSP information and code for the current buffer',
            opts = {
              contains_code = true,
            },
          },
          ['viewport'] = {
            callback = 'strategies.chat.variables.viewport',
            description = 'Share the code that you see in Neovim with the LLM',
            opts = {
              contains_code = true,
            },
          },
        },
      },
    },
  },
}
