local t = require('luatest')
local g = t.group('hooks')

local helper = require('test.helper')

g.test_hooks = function()
    local hooks = {}
    local expected = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite_1') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_1') end)

        lu2.before_suite(function() table.insert(hooks, 'before_suite_2') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_2') end)

        table.insert(expected, 'before_suite_1')
        table.insert(expected, 'before_suite_2')

        for _, v in ipairs({'_t1', '_t2'}) do
            local t2 = lu2.group(v)

            t2.before_all(function() table.insert(hooks, 'before_all' .. v) end)
            t2.after_all(function() table.insert(hooks, 'after_all' .. v) end)
            t2.before_each(function() table.insert(hooks, 'before_each' .. v) end)
            t2.after_each(function() table.insert(hooks, 'after_each' .. v) end)
            t2.before_all(function() table.insert(hooks, 'before_all2_' .. v) end)
            t2.after_all(function() table.insert(hooks, 'after_all2_' .. v) end)
            t2.before_each(function() table.insert(hooks, 'before_each2_' .. v) end)
            t2.after_each(function() table.insert(hooks, 'after_each2_' .. v) end)
            t2.test_1 = function() table.insert(hooks, 'test_1' .. v) end
            t2.test_2 = function() table.insert(hooks, 'test_2' .. v) end
            table.insert(expected, 'before_all' .. v)
            table.insert(expected, 'before_all2_' .. v)
            table.insert(expected, 'before_each' .. v)
            table.insert(expected, 'before_each2_' .. v)
            table.insert(expected, 'test_1' .. v)
            table.insert(expected, 'after_each' .. v)
            table.insert(expected, 'after_each2_' .. v)
            table.insert(expected, 'before_each' .. v)
            table.insert(expected, 'before_each2_' .. v)
            table.insert(expected, 'test_2' .. v)
            table.insert(expected, 'after_each' .. v)
            table.insert(expected, 'after_each2_' .. v)
            table.insert(expected, 'after_all' .. v)
            table.insert(expected, 'after_all2_' .. v)
        end

        table.insert(expected, 'after_suite_1')
        table.insert(expected, 'after_suite_2')
    end, {'--shuffle', 'none'})

    t.assert_equals(result, 0)
    t.assert_equals(hooks, expected)
end

g.test_hooks_legacy = function()
    local hooks = {}
    local expected = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite_1') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_1') end)

        lu2.before_suite(function() table.insert(hooks, 'before_suite_2') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_2') end)

        table.insert(expected, 'before_suite_1')
        table.insert(expected, 'before_suite_2')

        for _, v in ipairs({'_t1', '_t2'}) do
            local t2 = lu2.group(v)

            t2.before_all = function() table.insert(hooks, 'before_all' .. v) end
            t2.after_all = function() table.insert(hooks, 'after_all' .. v) end
            t2.setup = function() table.insert(hooks, 'setup' .. v) end
            t2.teardown = function() table.insert(hooks, 'teardown' .. v) end
            t2.test_1 = function() table.insert(hooks, 'test_1' .. v) end
            t2.test_2 = function() table.insert(hooks, 'test_2' .. v) end
            table.insert(expected, 'before_all' .. v)
            table.insert(expected, 'setup' .. v)
            table.insert(expected, 'test_1' .. v)
            table.insert(expected, 'teardown' .. v)
            table.insert(expected, 'setup' .. v)
            table.insert(expected, 'test_2' .. v)
            table.insert(expected, 'teardown' .. v)
            table.insert(expected, 'after_all' .. v)
        end

        table.insert(expected, 'after_suite_1')
        table.insert(expected, 'after_suite_2')
    end, {'--shuffle', 'none'})

    t.assert_equals(result, 0)
    t.assert_equals(hooks, expected)
end

g.test_before_suite_failed = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite_1') end)
        lu2.before_suite(function() error('custom-error') end)
        lu2.before_suite(function() table.insert(hooks, 'before_suite_2') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite') end)

        local t2 = lu2.group('test')
        t2.before_all = function() table.insert(hooks, 'before_all') end
        t2.after_all = function() table.insert(hooks, 'after_all') end
        t2.test = function() table.insert(hooks, 'test') end
    end)

    t.assert_equals(result, -1)
    t.assert_equals(hooks, {'before_suite_1', 'after_suite'})
end

g.test_after_suite_failed = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_1') end)
        lu2.after_suite(function() error('custom-error') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_2') end)

        local t2 = lu2.group('test')
        t2.before_all = function() table.insert(hooks, 'before_all') end
        t2.after_all = function() table.insert(hooks, 'after_all') end
        t2.test = function() table.insert(hooks, 'test') end
    end)

    t.assert_equals(result, -1)
    t.assert_equals(hooks, {'before_suite', 'before_all', 'test', 'after_all', 'after_suite_1'})
end

g.test_before_group_failed = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite') end)

        local t_0 = lu2.group('test_0')
        t_0.before_all = function() table.insert(hooks, 'before_all_0') end
        t_0.after_all = function() table.insert(hooks, 'after_all_0') end
        t_0.test = function() table.insert(hooks, 'test_0') end

        local t_1 = lu2.group('test_1')
        t_1.before_all = function()
            table.insert(hooks, 'before_all_1')
            error('custom-error')
        end
        t_1.after_all = function() table.insert(hooks, 'after_all_1') end
        t_1.test_1 = function() table.insert(hooks, 'test_1_1') end
        t_1.test_2 = function() table.insert(hooks, 'test_1_2') end

        local t_2 = lu2.group('test_2')
        t_2.before_all = function() table.insert(hooks, 'before_all_2') end
        t_2.after_all = function() table.insert(hooks, 'after_all_2') end
        t_2.test = function() table.insert(hooks, 'test_2') end
    end)

    t.assert_equals(result, 2)
    t.assert_equals(hooks, {
        'before_suite',
        'before_all_0',
        'test_0',
        'after_all_0',
        'before_all_1',
        'after_all_1',
        'before_all_2',
        'test_2',
        'after_all_2',
        'after_suite',
    })
end

g.test_after_group_failed = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite') end)

        local t_1 = lu2.group('test_1')
        t_1.before_all = function() table.insert(hooks, 'before_all_1') end
        t_1.after_all = function() error('custom-error') end
        t_1.test_1 = function() table.insert(hooks, 'test_1_1') end
        t_1.test_2 = function() table.insert(hooks, 'test_1_2') end

        local t_2 = lu2.group('test_2')
        t_2.before_all = function() table.insert(hooks, 'before_all_2') end
        t_2.after_all = function() table.insert(hooks, 'after_all_2') end
        t_2.test = function() table.insert(hooks, 'test_2') end
    end, {'--shuffle', 'none'})

    t.assert_equals(result, 1)
    t.assert_equals(hooks, {
        'before_suite',
        'before_all_1',
        'test_1_1',
        'test_1_2',
        'before_all_2',
        'test_2',
        'after_all_2',
        'after_suite',
    })
end

g.test_suite_and_group_hooks_dont_run_when_no_tests_running = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite') end)
        local t2 = lu2.group('test')
        t2.before_all = function() table.insert(hooks, 'before_all') end
        t2.after_all = function() table.insert(hooks, 'after_all') end
    end)
    t.assert_equals(result, 0)
    t.assert_equals(hooks, {})
end

g.test_suite_and_group_hooks_dont_run_when_luaunit_stops_before_suite = function()
    local hooks = {}

    local suite = function(lu2)
        lu2.before_suite(function() table.insert(hooks, 'before_suite') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite') end)
        local t2 = lu2.group('test')
        t2.before_all = function() table.insert(hooks, 'before_all') end
        t2.after_all = function() table.insert(hooks, 'after_all') end
        t2.test = function() table.insert(hooks, 'test') end
    end

    t.assert_equals(helper.run_suite(suite, {'-h'}), 0)
    t.assert_equals(hooks, {})
    t.assert_equals(helper.run_suite(suite, {'--invalid'}), -1)
    t.assert_equals(hooks, {})
end
