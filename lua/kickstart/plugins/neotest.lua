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
    {
      '<leader>tt',
      function()
        require('neotest').run.run()
      end,
      desc = '[T]est nearest',
    },
    {
      '<leader>tf',
      function()
        require('neotest').run.run(vim.fn.expand '%')
      end,
      desc = '[T]est [F]ile',
    },
    {
      '<leader>ts',
      function()
        require('neotest').summary.toggle()
      end,
      desc = '[T]est [S]ummary',
    },
    {
      '<leader>to',
      function()
        require('neotest').output.open { enter = true, auto_close = true }
      end,
      desc = '[T]est [O]utput',
    },
    {
      '<leader>tp',
      function()
        require('neotest').output_panel.toggle()
      end,
      desc = '[T]est [P]anel',
    },
    {
      '<leader>tl',
      function()
        require('neotest').run.run_last()
      end,
      desc = '[T]est [L]ast',
    },
    {
      '<leader>td',
      function()
        require('neotest').run.run { strategy = 'dap' }
      end,
      desc = '[T]est [D]ebug nearest',
    },
    {
      '<leader>tS',
      function()
        require('neotest').run.stop()
      end,
      desc = '[T]est [S]top',
    },
    {
      '[t',
      function()
        require('neotest').jump.prev { status = 'failed' }
      end,
      desc = 'Previous failed test',
    },
    {
      ']t',
      function()
        require('neotest').jump.next { status = 'failed' }
      end,
      desc = 'Next failed test',
    },
  },
  config = function()
    require('neotest').setup {
      adapters = {
        require 'neotest-vitest' {
          cwd = function(file)
            -- Walk up to find nearest package.json
            local path = vim.fn.fnamemodify(file, ':h')
            while path ~= '/' do
              local f = io.open(path .. '/package.json', 'r')
              if f then
                f:close()
                return path
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return vim.fn.getcwd()
          end,
          -- Only claim files if vitest.config exists in the project
          is_test_file = function(file)
            if not (file:match '%.test%.[tj]sx?$' or file:match '%.spec%.[tj]sx?$') then
              return false
            end
            -- Walk up to find nearest package.json and check for vscode-test-cli
            -- If found, this is a VSCode extension test - let vscode-test adapter handle it
            local path = vim.fn.fnamemodify(file, ':h')
            while path ~= '/' do
              local pkg_json = path .. '/package.json'
              local f = io.open(pkg_json, 'r')
              if f then
                local content = f:read '*a'
                f:close()
                if content and content:match '@vscode/test%-cli' then
                  return false -- Let vscode-test adapter handle this
                end
              end
              -- Check if vitest.config exists at this level (use io.open for async safety)
              local has_vitest = io.open(path .. '/vitest.config.ts', 'r')
                or io.open(path .. '/vitest.config.js', 'r')
                or io.open(path .. '/vitest.config.mts', 'r')
              if has_vitest then
                has_vitest:close()
                return true
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return false
          end,
        },
        require('custom.plugins.neotest-vscode-test').setup {
          -- Find workspace root (where .vscode-test.mjs lives) for cwd
          cwd = function(root)
            local path = root
            while path ~= '/' do
              local f = io.open(path .. '/.vscode-test.mjs', 'r')
              if f then
                f:close()
                return path
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return root
          end,
          -- Find compile-tests script in workspace root
          compile_cmd = function(root)
            local path = root
            while path ~= '/' do
              local f = io.open(path .. '/package.json', 'r')
              if f then
                local content = f:read '*a'
                f:close()
                if content and content:match '"compile%-tests"' then
                  return { 'yarn', 'run', 'compile-tests' }
                end
              end
              path = vim.fn.fnamemodify(path, ':h')
            end
            return nil
          end,
        },
      },
    }
  end,
}
