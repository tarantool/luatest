local t = require('luatest')
local g = t.group('reporting')

local Capture = require('luatest.capture')
local capture = Capture:new()

local helper = require('test.helper')

g.setup = function() capture:enable() end
g.teardown = function()
    capture:flush()
    capture:disable()
end

g.test_no_fails_summary_on_success = function()
    local result = helper.run_suite(function(lu2)
        local g2 = lu2.group('group-name')
        g2.test = function() end
    end)
        t.assert_equals(result, 0)
    local captured = capture:flush()
    t.assert_not_str_contains(captured.stdout, 'Failed tests:')
end

g.test_fails_summary_on_failure = function()
    local result = helper.run_suite(function(lu2)
        local g2 = lu2.group('group-name')
        g2.test_1 = function() error('custom') end
        g2.test_2 = function() end
        g2.test_3 = function() lu2.assert_equals(1, 2) end
        g2.test_4 = function() end
    end)
    t.assert_equals(result, 2)
    local captured = capture:flush()
    t.assert_str_contains(captured.stdout, 'Failed tests:')
    t.assert_str_contains(captured.stdout, [[
group-name.test_1
group-name.test_3
]])
    t.assert_not_str_contains(captured.stdout, 'group-name.test_2')
    t.assert_not_str_contains(captured.stdout, 'group-name.test_4')
end

local output_presets = {
    verbose = {'-v'},
    text = {'-o', 'text'},
    junit = {'-o', 'junit', '-n', 'tmp/test_junit'},
    tap = {'-o', 'tap'},
    tap_verbose = {'-o', 'tap', '-v'},
    ['nil'] = {'-o', 'nil'},
}

for output_type, options in pairs(output_presets) do
    g['test_' .. output_type .. '_output'] = function()
        capture:disable()
        t.assert_equals(helper.run_suite(function(lu2)
            local g2 = lu2.group('group-name')
            g2.test_1 = function() error('custom') end
            g2.test_2 = function() end
            g2.test_3 = function() lu2.assert_equals(1, 2) end
            g2.test_4 = function() lu2.skip() end
            g2.test_5 = function() lu2.skip('skip-msg') end
            g2.test_6 = function() lu2.success() end
            g2.test_7 = function() lu2.success('success-msg') end
            g2.test_8 = function() end
        end, options), 2)

        t.assert_equals(helper.run_suite(function(lu2)
            local g2 = lu2.group('group-name')
            g2.test_2 = function() end
            g2.test_4 = function() lu2.skip() end
            g2.test_5 = function() lu2.skip('skip-msg') end
            g2.test_6 = function() lu2.success() end
            g2.test_7 = function() lu2.success('success-msg') end
            g2.test_8 = function() end
        end, options), 0)

        t.assert_equals(helper.run_suite(function(lu2)
            local g2 = lu2.group('group-name')
            g2.test_2 = function() end
        end, options), 0)
    end
end
