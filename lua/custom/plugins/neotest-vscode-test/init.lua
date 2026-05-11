---@class neotest-vscode-test
---Neotest adapter for running VSCode extension tests via @vscode/test-cli
---
---This adapter allows running Mocha tests that require the VSCode runtime
---environment, which cannot be run with standard test runners.

local lib = require 'neotest.lib'

---@type neotest.Adapter
local M = { name = 'neotest-vscode-test' }

---@class VscodeTestConfig
---@field vscode_test_cmd? string[] Command to run vscode-test (default: {"npx", "vscode-test"})
---@field compile_cmd? string[]|fun(root: string): string[]|nil Command or function returning command to compile tests
---@field cwd? fun(root: string): string Function to determine working directory for test execution
---@field root_patterns? string[] Patterns to identify project root
---@field test_file_patterns? string[] Patterns to identify test files

---@type VscodeTestConfig
local config = {
  vscode_test_cmd = { 'npx', 'vscode-test' },
  compile_cmd = nil,
  cwd = function(root)
    return root
  end,
  root_patterns = { '.vscode-test.mjs', '.vscode-test.js', 'package.json' },
  test_file_patterns = { '%.test%.[tj]s$', '%.spec%.[tj]s$' },
}

---Configure the adapter
---@param opts VscodeTestConfig
---@return neotest.Adapter
function M.setup(opts)
  config = vim.tbl_deep_extend('force', config, opts or {})
  return M
end

---Find the project root directory
---@param path string
---@return string|nil
function M.root(path)
  local root = lib.files.match_root_pattern(unpack(config.root_patterns))(path)
  if not root then
    return nil
  end

  -- Verify this is a vscode-test project
  local f = io.open(root .. '/.vscode-test.mjs', 'r')
  if f then
    f:close()
    return root
  end

  -- Check package.json for @vscode/test-cli
  f = io.open(root .. '/package.json', 'r')
  if f then
    local content = f:read '*a'
    f:close()
    if content and content:match '@vscode/test%-cli' then
      return root
    end
  end

  return nil
end

---Filter test directories
---@param name string
---@return boolean
function M.filter_dir(name, _, _)
  local ignored_dirs = {
    'node_modules',
    '.git',
    'dist',
    'out',
    '.vscode-test',
    'coverage',
  }
  for _, dir in ipairs(ignored_dirs) do
    if name == dir then
      return false
    end
  end
  return true
end

---Check if a file is a test file
---@param file_path string
---@return boolean
function M.is_test_file(file_path)
  if not file_path then
    return false
  end

  for _, pattern in ipairs(config.test_file_patterns) do
    if file_path:match(pattern) then
      local root = M.root(file_path)
      return root ~= nil
    end
  end

  return false
end

---Parse test positions from file using treesitter
---@async
---@param path string
---@return neotest.Tree
function M.discover_positions(path)
  local query = [[
    ; Match suite("name", function)
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "suite")
      arguments: (arguments
        (string) @suite.name
        (arrow_function) @suite.definition
      )
    ) @suite.block

    ; Match suite("name", function() {})
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "suite")
      arguments: (arguments
        (string) @suite.name
        (function_expression) @suite.definition
      )
    ) @suite.block

    ; Match test("name", async () => {})
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "test")
      arguments: (arguments
        (string) @test.name
        (arrow_function) @test.definition
      )
    ) @test.block

    ; Match test("name", async function() {})
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "test")
      arguments: (arguments
        (string) @test.name
        (function_expression) @test.definition
      )
    ) @test.block

    ; Match it("name", ...) - alternative Mocha syntax
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "it")
      arguments: (arguments
        (string) @test.name
        [(arrow_function) (function_expression)] @test.definition
      )
    ) @test.block

    ; Match describe("name", ...) - alternative Mocha syntax
    (call_expression
      function: (identifier) @func_name (#eq? @func_name "describe")
      arguments: (arguments
        (string) @namespace.name
        [(arrow_function) (function_expression)] @namespace.definition
      )
    ) @namespace.block
  ]]

  return lib.treesitter.parse_positions(path, query, {
    nested_tests = true,
    require_namespaces = false,
    position_id = function(position, namespaces)
      return table.concat(
        vim.tbl_flatten {
          position.path,
          vim.tbl_map(function(pos)
            return pos.name
          end, namespaces),
          position.name,
        },
        '::'
      )
    end,
  })
end

---Build the test command specification
---@async
---@param args neotest.RunArgs
---@return neotest.RunSpec|nil
function M.build_spec(args)
  local position = args.tree:data()
  local root = M.root(position.path)

  if not root then
    return nil
  end

  local cwd = config.cwd(root)

  -- Build grep pattern for the test
  local grep_pattern
  if position.type == 'test' then
    local test_name = position.name:gsub('^["\']', ''):gsub('["\']$', '')
    grep_pattern = test_name:gsub('([%(%)%[%]%.%*%+%?%^%$])', '\\%1')
  elseif position.type == 'namespace' then
    local ns_name = position.name:gsub('^["\']', ''):gsub('["\']$', '')
    grep_pattern = '^' .. ns_name:gsub('([%(%)%[%]%.%*%+%?%^%$])', '\\%1')
  end

  -- Build command
  local cmd = vim.list_extend({}, config.vscode_test_cmd)

  if grep_pattern then
    table.insert(cmd, '--grep')
    table.insert(cmd, grep_pattern)
  end

  -- Get compile command (can be static or dynamic via function)
  local compile_cmd = config.compile_cmd
  if type(compile_cmd) == 'function' then
    compile_cmd = compile_cmd(root)
  end

  -- Create combined command with compilation
  local full_cmd
  if compile_cmd then
    local function shell_escape(arg)
      return "'" .. arg:gsub("'", "'\\''") .. "'"
    end
    local compile_str = table.concat(compile_cmd, ' ')
    local test_parts = {}
    for _, arg in ipairs(cmd) do
      table.insert(test_parts, shell_escape(arg))
    end
    local test_str = table.concat(test_parts, ' ')
    full_cmd = { 'sh', '-c', compile_str .. ' && ' .. test_str }
  else
    full_cmd = cmd
  end

  return {
    command = full_cmd,
    cwd = cwd,
    context = {
      position = position,
      root = root,
    },
    env = {
      FORCE_COLOR = '0',
      NO_COLOR = '1',
    },
  }
end

---Parse Mocha test output
---@param output string
---@return table<string, {status: string, message?: string}>, number, number
local function parse_mocha_output(output)
  local results = {}

  for test_name in output:gmatch '[✓√]%s+(.-)%s*\n' do
    test_name = test_name:gsub('%s*%(.-%)%s*$', '')
    results[test_name] = { status = 'passed' }
  end

  for test_name in output:gmatch '%s+%d+%)%s+([^\n]+)' do
    test_name = test_name:gsub('%s+$', '')
    local error_msg = output:match 'AssertionError[^\n]*:%s*([^\n]+)' or output:match 'Error:%s*([^\n]+)'
    results[test_name] = {
      status = 'failed',
      message = error_msg,
    }
  end

  for test_name in output:gmatch '%s%-%s+(.-)%s*\n' do
    results[test_name] = { status = 'skipped' }
  end

  local passing_count = tonumber(output:match '(%d+) passing') or 0
  local failing_count = tonumber(output:match '(%d+) failing') or 0

  return results, passing_count, failing_count
end

---Recursively process tree nodes
---@param node neotest.Tree
---@param parsed table
---@param passing_count number
---@param failing_count number
---@param output_path string
---@param results table
local function process_node(node, parsed, passing_count, failing_count, output_path, results)
  local pos = node:data()
  if not pos then
    return
  end

  if pos.type == 'test' then
    local test_result = parsed[pos.name]

    if test_result then
      results[pos.id] = {
        status = test_result.status,
        short = test_result.message,
        output = output_path,
      }
    elseif failing_count > 0 and passing_count == 0 then
      results[pos.id] = {
        status = 'failed',
        output = output_path,
      }
    elseif passing_count > 0 and failing_count == 0 then
      results[pos.id] = {
        status = 'passed',
        output = output_path,
      }
    elseif failing_count > 0 then
      results[pos.id] = {
        status = 'failed',
        output = output_path,
      }
    else
      results[pos.id] = {
        status = 'skipped',
        output = output_path,
      }
    end
  end

  local children = node:children()
  for _, child in ipairs(children) do
    process_node(child, parsed, passing_count, failing_count, output_path, results)
  end

  if pos.type == 'file' or pos.type == 'namespace' then
    local aggregated_status = 'passed'
    for _, child in ipairs(children) do
      local child_pos = child:data()
      if child_pos and results[child_pos.id] then
        local child_status = results[child_pos.id].status
        if child_status == 'failed' then
          aggregated_status = 'failed'
          break
        elseif child_status == 'skipped' and aggregated_status ~= 'failed' then
          aggregated_status = 'skipped'
        end
      end
    end
    results[pos.id] = {
      status = aggregated_status,
      output = output_path,
    }
  end
end

---Process test results
---@async
---@param result neotest.StrategyResult
---@param tree neotest.Tree
---@return table<string, neotest.Result>
function M.results(_, result, tree)
  local results = {}
  local output_path = result.output

  if not output_path then
    return results
  end

  local output = lib.files.read(output_path) or ''
  local parsed, passing_count, failing_count = parse_mocha_output(output)

  process_node(tree, parsed, passing_count, failing_count, output_path, results)

  return results
end

return M
