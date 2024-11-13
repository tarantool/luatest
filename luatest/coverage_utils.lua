local fio = require('fio')
local runner = require('luacov.runner')

-- Fix luacov issue. Without patch it's failed when `assert` is redefined.
function runner.update_stats(old_stats, extra_stats)
   old_stats.max = math.max(old_stats.max, extra_stats.max)
   for line_nr, run_nr in pairs(extra_stats) do
      if type(line_nr) == 'number' then -- This line added instead of `= nil`
        old_stats[line_nr] = (old_stats[line_nr] or 0) + run_nr
        old_stats.max_hits = math.max(old_stats.max_hits, old_stats[line_nr])
      end
   end
end

-- Module with utilities for collecting code coverage from external processes.
local export = {
    DEFAULT_EXCLUDE = {
        '^builtin/',
        '/luarocks/',
        '/build.luarocks/',
        '/.rocks/',
    },
}

local function with_cwd(dir, fn)
    local old = fio.cwd()
    assert(fio.chdir(dir), 'Failed to chdir to ' .. dir)
    fn()
    assert(fio.chdir(old), 'Failed to chdir to ' .. old)
end

local function find_luas(list_of_lua_modules, path)
    for _, filename in pairs(fio.listdir(path)) do
        local full_filename = fio.pathjoin(path, filename)
        if fio.path.is_dir(full_filename) then
            find_luas(list_of_lua_modules, full_filename)
        elseif full_filename:endswith(".lua") then
            list_of_lua_modules[full_filename] = {max = 0, max_hits = 0}
        end
    end
end

function export.enable()
    local root = os.getenv('LUATEST_LUACOV_ROOT')
    if not root then
        root = fio.cwd()
        os.setenv('LUATEST_LUACOV_ROOT', root)
    end
    -- Chdir to original root so luacov can find default config and resolve relative filenames.
    with_cwd(root, function()
        local config = runner.load_config()
        config.exclude = config.exclude or {}
        for _, item in pairs(export.DEFAULT_EXCLUDE) do
            table.insert(config.exclude, item)
        end

        runner.data = {}
        find_luas(runner.data, root)

        runner.init(config)
    end)
end

function export.shutdown()
    if runner.initialized then
        runner.shutdown()
    end
end

return export
