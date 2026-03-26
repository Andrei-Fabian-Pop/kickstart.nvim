-- Neotest - Test runner integration for Neovim
-- Run tests, see failures inline, view diffs

return {
  'nvim-neotest/neotest',
  dependencies = {
    'nvim-neotest/nvim-nio',
    'nvim-lua/plenary.nvim',
    'antoinemadec/FixCursorHold.nvim',
    'nvim-treesitter/nvim-treesitter',
    -- Adapters
    'marilari88/neotest-vitest',
  },
  ft = { 'typescript', 'javascript', 'typescriptreact', 'javascriptreact' },
  keys = {
    { '<leader>tt', function() require('neotest').run.run() end, desc = '[T]est nearest' },
    { '<leader>tf', function() require('neotest').run.run(vim.fn.expand('%')) end, desc = '[T]est [F]ile' },
    { '<leader>ts', function() require('neotest').summary.toggle() end, desc = '[T]est [S]ummary' },
    { '<leader>to', function() require('neotest').output.open({ enter = true, auto_close = true }) end, desc = '[T]est [O]utput' },
    { '<leader>tp', function() require('neotest').output_panel.toggle() end, desc = '[T]est [P]anel' },
    { '<leader>tl', function() require('neotest').run.run_last() end, desc = '[T]est [L]ast' },
    { '<leader>td', function() require('neotest').run.run({ strategy = 'dap' }) end, desc = '[T]est [D]ebug nearest' },
    { '<leader>tS', function() require('neotest').run.stop() end, desc = '[T]est [S]top' },
    { '[t', function() require('neotest').jump.prev({ status = 'failed' }) end, desc = 'Previous failed test' },
    { ']t', function() require('neotest').jump.next({ status = 'failed' }) end, desc = 'Next failed test' },
  },
  config = function()
    require('neotest').setup({
      adapters = {
        require('neotest-vitest')({
          cwd = function(file)
            -- Walk up to find nearest package.json
            local path = vim.fn.fnamemodify(file, ':h')
            while path ~= '/' do
              if vim.fn.filereadable(path .. '/package.json') == 1 then
                return path
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return vim.fn.getcwd()
          end,
          -- Only claim files if vitest.config exists in the project
          is_test_file = function(file)
            if not (file:match('%.test%.[tj]sx?$') or file:match('%.spec%.[tj]sx?$')) then
              return false
            end
            -- Check if vitest.config exists in the project
            local path = vim.fn.fnamemodify(file, ':h')
            while path ~= '/' do
              if vim.fn.filereadable(path .. '/vitest.config.ts') == 1 or
                 vim.fn.filereadable(path .. '/vitest.config.js') == 1 or
                 vim.fn.filereadable(path .. '/vitest.config.mts') == 1 then
                return true
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return false
          end,
        }),
        require('neotest-vscode-test').setup({
          -- Optional: override defaults
          -- vscode_test_cmd = { "npx", "vscode-test" },
          -- compile_cmd = { "yarn", "run", "compile-tests" },
        }),
      },
    })
  end,
}
