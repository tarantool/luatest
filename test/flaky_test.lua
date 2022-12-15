local t = require('luatest')
local g = t.group()

local helper = require('test.helper')

g.test_failed = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('flaky')
        pg.test_fail = function()
            lu2.flaky()
            lu2.assert_equals(2 + 2, 5)
        end
    end)

    t.assert_equals(result, 0)
end

g.test_succeeded = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('flaky')
        pg.test_success = function()
            lu2.flaky()
            lu2.assert_equals(2 + 3, 5)
        end
    end)

    t.assert_equals(result, 0)
end

g.test_error = function()
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('flaky')
        pg.test_error = function()
            lu2.flaky()
            error('Boom!')
        end
    end)

    t.assert_equals(result, 1)
end
