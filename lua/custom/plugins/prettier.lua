return {
  'MunifTanjim/prettier.nvim',
  dependencies = { 'jose-elias-alvarez/null-ls.nvim', 'nvim-lspconfig' },
  config = function()
    local prettier = require 'prettier'
    prettier.setup {
      bin = 'prettier', -- or `'prettierd'` (v0.23.3+)
      filetypes = {
        'css',
        'graphql',
        'html',
        'javascript',
        'javascriptreact',
        'json',
        'less',
        'markdown',
        'scss',
        'typescript',
        'typescriptreact',
        'yaml',
      },
    }
  end,
}
