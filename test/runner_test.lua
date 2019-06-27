local t = require('luatest')
local g = t.group('runner')

local helper = require('test.helper')

g.test_run_pass = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assert_equals(1, 1) end
    end)

    t.assert_equals(result, 0)
end

g.test_run_fail = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assert_equals(1, 0) end
    end)

    t.assert_equals(result, 1)
end

g.test_run_error = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() error('custom_error') end
    end)

    t.assert_equals(result, 1)
end

local function run_file(file)
    return os.execute('bin/luatest test/fixtures/' .. file)
end

g.test_executable_pass = function()
    t.assert_equals(run_file('pass.lua'), 0)
end

g.test_executable_fail = function()
    t.assert_equals(run_file('fail.lua'), 256) -- luajit multiplies result by 256
end

g.test_executable_error = function()
    t.assert_equals(run_file('error.lua'), 256) -- luajit multiplies result by 256
end
