local runner = require('luacov.runner')

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
