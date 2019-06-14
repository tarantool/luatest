local t = require('luatest')
local g = t.group('runner')

local helper = require('test.helper')

g.test_run_pass = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assertEquals(1, 1) end
    end)

    t.assertEquals(result, 0)
end

g.test_run_fail = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assertEquals(1, 0) end
    end)

    t.assertEquals(result, 1)
end

g.test_run_error = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() error('custom_error') end
    end)

    t.assertEquals(result, 1)
end
