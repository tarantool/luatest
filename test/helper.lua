-- Disable jit until this issue is fixed:
-- https://github.com/tarantool/tarantool/issues/4476
jit.off() -- luacheck: no global

local t = require('luatest')
t.defaults({shuffle = 'group'})
local runner = t.runner

local helper = {}

function helper.run_suite(load_tests, args)
    local lu = dofile(package.search('luatest.luaunit'))
    -- Need to supply any option to prevent luaunit from taking args from _G
    return runner.run(args or {}, {luaunit = lu, load_tests = function() load_tests(lu) end})
end

return helper
