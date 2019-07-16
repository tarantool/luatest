local fun = require('fun')

-- This is lightweight module to run luatest suite.
-- It has only basic dependencies (and no top-level luatest dependencies)
-- to clear as much as modules as possible after running tests.
local export = {}

-- Tarantool does not invoke Lua's GC-callbacks on exit.
-- So this method clears every loaded package and invokes GC explicitly.
-- It does not clear previously loaded packages to not break any GC-callback
-- which relies on built-in package.
function export.gc_sandboxed(fn)
    local original = fun.iter(package.loaded):map(function(x) return x, true end):tomap()
    local result = fn()
    -- Collect list of new packages to not modify map while iterating over it.
    local new_packages = fun.iter(package.loaded):
        map(function(x) return x end):
        filter(function(x) return not original[x] end):
        totable()
    for _, name in pairs(new_packages) do
        package.loaded[name] = nil -- luacheck: no global
    end
    collectgarbage()
    return result
end

function export.run(...)
    local args = {...}
    return export.gc_sandboxed(function() return require('luatest').runner:run(unpack(args)) end)
end

return export
