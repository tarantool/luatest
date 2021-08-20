local t = require('luatest')
local g = t.group()

local helper = require('test.helper')

g.test_validation = function()
    t.assert_error_msg_contains(
        'Parameter name should be string, got number',
        function() t.group('parametrized', {[1] = {1, 2}}) end
    )

    t.assert_error_msg_contains(
        'Parameter name should be string, got table',
        function() t.group('parametrized', {[{'name'}] = {1, 2}}) end
    )

    t.assert_error_msg_contains(
        'Parameter values should be table, got string',
        function() t.group('parametrized', {['name'] = 'value'}) end
    )

    t.assert_error_msg_contains(
        'Parameter values should be table, got number',
        function() t.group('parametrized', {['name'] = 1}) end
    )

    t.assert(pcall(function() t.group('parametrized', {name = {'value'}}) end))
end

g.test_index_redirection = function()
    local counter = 0
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('parametrized', {param1 = {1, 2, 3}, param2 = {4, 5}})
        pg.test_counter_inc = function()
            counter = counter + 1
        end
    end, {'-v'})

    t.assert_equals(result , 0)
    t.assert_equals(counter, 6)
end

g.test_params = function()
    local expected = {
        ['a.b_1.c_3'] = 3,
        ['a.b_1.c_4'] = 4,
        ['a.b_2.c_3'] = 6,
        ['a.b_2.c_4'] = 8,
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('a', {b = {1, 2}, c = {3, 4}})
        pg.test_1 = function(g)
            actual[g.name] = g.params.b * g.params.c
        end
    end, {'-v'})

    t.assert_equals(result , 0)
    t.assert_equals(actual, expected)
end

g.test_hooks = function()
    local expected = {
        -- From general to specific
        "before_all_1",
        "before_all1_1",
        "before_each_1",
        "before_each1_1",
        "test1_1",
        "after_each_1",
        "after_all_1",
        "before_all_2",
        "before_each_2",
        "test1_2",
        -- From specific to general
        "after_each2_2",
        "after_each_2",
        "after_all2_2",
        "after_all_2",
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('super', {b = {1, 2}})

        pg.before_all(function(g) print(g.name) table.insert(actual, 'before_all_' .. g.params.b) end)
        pg.before_each(function(g) table.insert(actual, 'before_each_' .. g.params.b) end)
        pg.after_each(function(g) table.insert(actual, 'after_each_' .. g.params.b) end)
        pg.after_all(function(g) table.insert(actual, 'after_all_' .. g.params.b) end)

        pg.before_all(function(g) table.insert(actual, 'before_all1_' .. g.params.b) end, {b = 1})
        pg.before_each(function(g) table.insert(actual, 'before_each1_' .. g.params.b) end, {b = 1})
        pg.after_each(function(g) table.insert(actual, 'after_each2_' .. g.params.b) end, {b = 2})
        pg.after_all(function(g) table.insert(actual, 'after_all2_' .. g.params.b) end, {b = 2})
        pg.test_1 = function(g)
            table.insert(actual, 'test1_' .. g.params.b)
        end
    end, {'-v', '-c'})

    t.assert_equals(result, 0)
    t.assert_equals(actual, expected)

end

g.test_named_hooks = function()
    local expected = {
        "before_test_1_1",
        "before_test_1_b_1_1",
        "test1_1",
        "test2_1",
        "after_test_2__1",
        "before_test_1_2",
        "test1_2",
        "test2_2",
        "after_test_2_b_2_2",
        "after_test_2__2",
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('super', {b = {1, 2}})

        pg.before_test('test_1', function(g) table.insert(actual, 'before_test_1_' .. g.params.b) end)
        pg.before_test('test_1', function(g) table.insert(actual, 'before_test_1_b_1_' .. g.params.b) end, {b = 1})
        pg.after_test('test_2', function(g) table.insert(actual, 'after_test_2__' .. g.params.b) end)
        pg.after_test('test_2', function(g) table.insert(actual, 'after_test_2_b_2_' .. g.params.b) end, {b = 2})
        pg.test_1 = function(g)
            table.insert(actual, 'test1_' .. g.params.b)
        end
        pg.test_2 = function(g)
            table.insert(actual, 'test2_' .. g.params.b)
        end
    end, {'-v', '-c'})

    t.assert_equals(result, 0)
    t.assert_equals(actual, expected)
end

g.test_fixed_param_hooks = function()
    local expected = {
        "b fixed at 1: b = 1; c = 3",
        "c fixed at 3: b = 1; c = 3",
        "b fixed at 1, c at 3: b = 1; c = 3",
        "b fixed at 1: b = 1; c = 4",
        "c fixed at 3: b = 2; c = 3",
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('super', {b = {1, 2}, c = {3, 4}})

        pg.before_all(function(g)
            local message = string.format('b fixed at 1: b = %d; c = %d', g.params.b, g.params.c)
            table.insert(actual, message)
        end, {b = 1})

        pg.before_all(function(g)
            local message = string.format('c fixed at 3: b = %d; c = %d', g.params.b, g.params.c)
            table.insert(actual, message)
        end, {c = 3})

        pg.before_all(function(g)
            local message = string.format('b fixed at 3: shouldn\'t happen', g.params.b, g.params.c)
            table.insert(actual, message)
        end, {b = 3})

        pg.before_all(function(g)
            local message = string.format('b fixed at 1, c at 3: b = %d; c = %d', g.params.b, g.params.c)
            table.insert(actual, message)
        end, {b = 1, c = 3})

        pg.test_1 = function(g) end
    end, {'-v', '-c'})

    t.assert_equals(result, 0)
    t.assert_equals(actual, expected)
end
