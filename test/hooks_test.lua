local t = require('luatest')
local g = t.group()

local Capture = require('luatest.capture')
local helper = require('test.helpers.general')

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

            t2.before_test('test_1', function() table.insert(hooks, 'before_test1' .. v) end)
            t2.after_test('test_2', function() table.insert(hooks, 'after_test2' .. v) end)

            t2.test_1 = function() table.insert(hooks, 'test_1' .. v) end
            t2.test_2 = function() table.insert(hooks, 'test_2' .. v) end

            table.insert(expected, 'before_all' .. v)
            table.insert(expected, 'before_all2_' .. v)
            table.insert(expected, 'before_each' .. v)
            table.insert(expected, 'before_each2_' .. v)
            table.insert(expected, 'before_test1' .. v)
            table.insert(expected, 'test_1' .. v)
            table.insert(expected, 'after_each' .. v)
            table.insert(expected, 'after_each2_' .. v)
            table.insert(expected, 'before_each' .. v)
            table.insert(expected, 'before_each2_' .. v)
            table.insert(expected, 'test_2' .. v)
            table.insert(expected, 'after_test2' .. v)
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

g.test_predefined_hooks = function()
    local _hooks = require('luatest.hooks')
    local hooks = {}

    _hooks.before_suite_preloaded(function() table.insert(hooks, 'before_suite') end)
    _hooks.after_suite_preloaded(function() table.insert(hooks, 'after_suite') end)
    _hooks.before_suite_preloaded(function() table.insert(hooks, 'before_suite2') end)
    _hooks.after_suite_preloaded(function() table.insert(hooks, 'after_suite2') end)

    _hooks.before_all_preloaded(function() table.insert(hooks, 'before_all') end)
    _hooks.after_all_preloaded(function() table.insert(hooks, 'after_all') end)
    _hooks.before_all_preloaded(function() table.insert(hooks, 'before_all2') end)
    _hooks.after_all_preloaded(function() table.insert(hooks, 'after_all2') end)

    _hooks.before_each_preloaded(function() table.insert(hooks, 'before_each') end)
    _hooks.after_each_preloaded(function() table.insert(hooks, 'after_each') end)
    _hooks.before_each_preloaded(function() table.insert(hooks, 'before_each2') end)
    _hooks.after_each_preloaded(function() table.insert(hooks, 'after_each2') end)

    _hooks.before_suite_preloaded(function() table.insert(hooks, 'before_suite3') end)
    _hooks.before_all_preloaded(function() table.insert(hooks, 'before_all3') end)
    _hooks.before_all_preloaded(function() table.insert(hooks, 'before_all4') end)
    _hooks.after_suite_preloaded(function() table.insert(hooks, 'after_suite3') end)
    _hooks.after_all_preloaded(function() table.insert(hooks, 'after_all3') end)
    _hooks.after_all_preloaded(function() table.insert(hooks, 'after_all4') end)

    local result = helper.run_suite(function(lu2)
        local t2 = lu2.group('test')
        t2.before_all(function() table.insert(hooks, 'before_all_inner') end)
        lu2.before_suite(function() table.insert(hooks, 'before_suite_inner') end)
        lu2.after_suite(function() table.insert(hooks, 'after_suite_inner') end)
        t2.after_all(function() table.insert(hooks, 'after_all_inner') end)
        t2.before_each(function() table.insert(hooks, 'before_each_inner') end)
        t2.after_each(function() table.insert(hooks, 'after_each_inner') end)
        t2.test = function() table.insert(hooks, 'test') end
    end)

    t.assert_equals(result, 0)
    t.assert_equals(hooks, {
        "before_suite",
        "before_suite2",
        "before_suite3",
        "before_suite_inner",
        "before_all",
        "before_all2",
        "before_all3",
        "before_all4",
        "before_all_inner",
        "before_each",
        "before_each2",
        "before_each_inner",
        "test",
        "after_each_inner",
        "after_each2",
        "after_each",
        "after_all_inner",
        "after_all4",
        "after_all3",
        "after_all2",
        "after_all",
        "after_suite_inner",
        "after_suite3",
        "after_suite2",
        "after_suite",
    })
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

g.test_suite_and_group_hooks_dont_run_when_suite_is_not_launched = function()
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

g.test_wrong_before_and_after = function()
    local hooks = {}

    local suite = function(lu2)
        local t2 = lu2.group('test')
        t2.before_test('test',
            function() table.insert(hooks, 'before_test') end)
        t2.before_test('wrong_test',
            function() table.insert(hooks, 'before_wrong_test') end)
        t2.test = function() table.insert(hooks, 'test') end
    end
    local result = helper.run_suite(suite)

    t.assert_equals(result, -1)
    t.assert_equals(hooks, {})

    local capture = Capture:new()
    capture:wrap(true, function() helper.run_suite(suite) end)
    t.assert_str_contains(capture:flush().stderr,
        "There is no test with name 'wrong_test' but hook 'before_test' is \z
        defined for it")

    suite = function(lu2)
        local t2 = lu2.group('test')
        t2.after_test('test', function() table.insert(hooks, 'after_test') end)
        t2.after_test('wrong_test',
            function() table.insert(hooks, 'after_wrong_test') end)
        t2.test = function() table.insert(hooks, 'test') end
    end
    result = helper.run_suite(suite)

    t.assert_equals(result, -1)
    t.assert_equals(hooks, {})

    capture = Capture:new()
    capture:wrap(true, function() helper.run_suite(suite) end)
    t.assert_str_contains(capture:flush().stderr,
        "There is no test with name 'wrong_test' but hook 'after_test' is \z
        defined for it")
end

g.test_before_and_after_failed_test = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        local t2 = lu2.group('test')
        t2.before_test('test', function() table.insert(hooks, 'before_test') end)
        t2.after_test('test', function() table.insert(hooks, 'after_test') end)
        t2.test = function() t.assert_equals(1, 2) table.insert(hooks, 'test') end
    end)

    t.assert_equals(result, 1)
    t.assert_equals(hooks, {'before_test', 'after_test'})
end

g.test_before_and_after_error = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        local t2 = lu2.group('test')
        t2.before_test('test', function() table.insert(hooks, 'before_test1') end)
        t2.before_test('test', function() error('custom-error') end)
        t2.before_test('test', function() table.insert(hooks, 'before_test3') end)
        t2.after_test('test', function() table.insert(hooks, 'after_test1') end)
        t2.after_test('test', function() error('custom-error') end)
        t2.after_test('test', function() table.insert(hooks, 'after_test3') end)
        t2.test = function() table.insert(hooks, 'test') end
    end, {'--repeat', '2'})

    t.assert_equals(result, 1)
    t.assert_equals(hooks, {'before_test1', 'after_test1'})
end

g.test_each_error = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        local t2 = lu2.group('test')
        t2.before_each(function() table.insert(hooks, 'before_each1') end)
        t2.before_each(function() error('custom-error') end)
        t2.before_each(function() table.insert(hooks, 'before_each3') end)
        t2.after_each(function() table.insert(hooks, 'after_each1') end)
        t2.after_each(function() error('custom-error') end)
        t2.after_each(function() table.insert(hooks, 'after_each3') end)
        t2.test = function() table.insert(hooks, 'test') end
    end, {'--repeat', '2'})

    t.assert_equals(result, 1)
    t.assert_equals(hooks, {'before_each1', 'after_each1'})
end

g.test_each_repeat = function()
    local hooks = {}

    local result = helper.run_suite(function(lu2)
        local t2 = lu2.group('test')
        local counter = 0
        t2.before_all(function() table.insert(hooks, 'before_all') end)
        t2.before_each(function() table.insert(hooks, 'before_each') end)
        t2.before_test('test_a', function() table.insert(hooks, 'before_test') end)
        t2.after_each(function() table.insert(hooks, 'after_each') end)
        t2.after_test('test_b', function() table.insert(hooks, 'after_test') end)
        t2.after_all(function() table.insert(hooks, 'after_all') end)
        t2.test_a = function()
            if counter >= 1 then
                error('The time has come')
            end

            counter = counter + 1
            table.insert(hooks, 'test_a')
        end
        t2.test_b = function() table.insert(hooks, 'test_b') end
    end, {'--repeat', '2'})

    t.assert_equals(result, 1)
    t.assert_equals(hooks, {
        'before_all',
        'before_each', 'before_test', 'test_a', 'after_each',
        'before_each', 'before_test', 'after_each',
        'before_each', 'test_b', 'after_test', 'after_each',
        'before_each', 'test_b', 'after_test', 'after_each',
        'after_all'
    })
end
