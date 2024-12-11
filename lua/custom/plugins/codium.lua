return {
  'Exafunction/codeium.vim',
  dependencies = { 'dundalek/parpar.nvim' },
  init = function()
    vim.g.codeium_disable_bindings = 1
  end,
  config = function()
    local parpar = require 'parpar'
    local accept = function()
      vim.schedule(parpar.pause())
      return vim.fn['codeium#Accept']()
    end

    vim.keymap.set('i', '<S-Tab>', accept, { expr = true })
  end,
}
