local t = require('luatest')
local g = t.group()

local helper = require('test.helper')

g.test_failed = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('xfail')
        pg.xfail['test_fail'] = true
        pg.test_fail = function()
            t.assert_equals(2 + 2, 5)
        end
    end)

    t.assert_equals(result, 0)
end

g.test_succeeded = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('xfail')
        pg.xfail['test_success'] = true
        pg.test_success = function()
            t.assert_equals(2 + 3, 5)
        end
    end)

    t.assert_equals(result, 1)
end

g.test_error = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('xfail')
        pg.xfail['test_error'] = true
        pg.test_error = function()
            error('Boom!')
        end
    end)

    t.assert_equals(result, 1)
end
