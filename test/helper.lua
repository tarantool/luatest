local t = require('luatest')
t.defaults({shuffle = 'group'})
local runner = t.runner

local helper = {}

function helper.run_suite(load_tests, args)
    local luatest = dofile(package.search('luatest'))
    -- Need to supply any option to prevent luatest from taking args from _G
    return runner.run(args or {}, {luatest = luatest, load_tests = function(...) load_tests(luatest, ...) end})
end

function helper.assert_failure(...)
    local err = t.assert_error(...)
    t.assert_equals(err.class, 'LuaUnitError', err)
    return err
end

function helper.assert_failure_equals(msg, ...)
    t.assert_equals(helper.assert_failure(...).message, msg)
end

function helper.assert_failure_matches(msg, ...)
    t.assert_str_matches(helper.assert_failure(...).message, msg)
end

function helper.assert_failure_contains(msg, ...)
    t.assert_str_contains(helper.assert_failure(...).message, msg)
end

return helper
