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

function export.enable()
    local config = runner.load_config()
    config.exclude = config.exclude or {}
    for _, item in pairs(export.DEFAULT_EXCLUDE) do
        table.insert(config.exclude, item)
    end
    runner.init(config)
end

function export.shutdown()
    if runner.initialized then
        runner.shutdown()
    end
end

return export
