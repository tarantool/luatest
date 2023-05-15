local t = require('luatest')
local g = t.group()

local helper = require('test.helpers.general')

g.test_validation = function()
    t.assert_error_msg_contains(
        'parameters_combinations should be a contiguous array',
        function() t.group('parametrized', {[2] = {1, 2}}) end
    )

    t.assert_error_msg_contains(
        'parameter name should be string, got function',
        function() t.group('parametrized', {{[function() end] = 1}}) end
    )

    t.assert_error_msg_contains(
        'parameters_combinations\' entry should be table, got string',
        function() t.group('parametrized', {'params'}) end
    )

    t.assert_error_msg_contains(
        'parameters_combinations should be a contiguous array',
        function() t.group('parametrized', {['name'] = 1}) end
    )

    t.assert(pcall(function() t.group('parametrized', {{name = 'value'}}) end))

    local pg = t.group('pg', {{name = 'value'}})
    t.assert_error_msg_contains(
        'hook should be function, got number',
        function() pg.after_each(1) end
    )
    t.assert_error_msg_contains(
        'params should be table, got function',
        function() pg.after_each(function() end, {name = 'value'}) end
    )
    t.assert_error_msg_contains(
        'hook should be function, got number',
        function() pg.after_each({name = 'value'}, 1) end
    )
    t.assert(pcall(function() pg.after_each({name = 'value'}, function() end) end))

    t.assert_error_msg_contains(
        'test name should be string, got number',
        function() pg.after_test(1) end
    )
    t.assert_error_msg_contains(
        'test name should be string, got number',
        function() pg.after_test(1, {name = 'value'}, function() end) end
    )
    t.assert_error_msg_contains(
        'params should be table, got function',
        function() pg.after_test('test_name', function() end, {name = 'value'}) end
    )
    t.assert_error_msg_contains(
        'hook should be function, got number',
        function() pg.after_test('test_name', {name = 'value'}, 1) end
    )
    t.assert(pcall(function()
        pg.after_test('test_name', {name = 'value'}, function() end)
    end))
end

g.test_index_redirection = function()
    local counter = 0
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('parametrized', t.helpers.matrix({param1 = {1, 2, 3}, param2 = {4, 5}}))
        pg.test_counter_inc = function()
            counter = counter + 1
        end
    end)

    t.assert_equals(result , 0)
    t.assert_equals(counter, 6)
end

g.test_params = function()
    local expected = {
        ['a.b:1.c:{3}'] = 3,
        ['a.b:1.c:{4}'] = 4,
        ['a.b:2.c:{3}'] = 6,
        ['a.b:2.c:{4}'] = 8,
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('a', t.helpers.matrix({b = {1, 2}, c = {{3}, {4}}}))
        pg.test_1 = function(cg)
            actual[cg.name] = cg.params.b * cg.params.c[1]
        end
    end)

    t.assert_equals(result , 0)
    t.assert_equals(actual, expected)
end

g.test_hooks = function()
    local expected = {
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
        "after_each2_2",
        "after_each_2",
        "after_all2_2",
        "after_all_2",
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('super', t.helpers.matrix({b = {1, 2}}))

        pg.before_all(function(cg) print(g.name) table.insert(actual, 'before_all_' .. cg.params.b) end)
        pg.before_all({b = 1}, function(cg) table.insert(actual, 'before_all1_' .. cg.params.b) end)

        pg.before_each(function(cg) table.insert(actual, 'before_each_' .. cg.params.b) end)
        pg.before_each({b = 1}, function(cg) table.insert(actual, 'before_each1_' .. cg.params.b) end)

        pg.after_each({b = 2}, function(cg) table.insert(actual, 'after_each2_' .. cg.params.b) end)
        pg.after_each(function(cg) table.insert(actual, 'after_each_' .. cg.params.b) end)

        pg.after_all({b = 2}, function(cg) table.insert(actual, 'after_all2_' .. cg.params.b) end)
        pg.after_all(function(cg) table.insert(actual, 'after_all_' .. cg.params.b) end)

        pg.test_1 = function(cg)
            table.insert(actual, 'test1_' .. cg.params.b)
        end
    end)

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
        local pg = lu2.group('super', t.helpers.matrix({b = {1, 2}}))

        pg.before_test('test_1', function(cg) table.insert(actual, 'before_test_1_' .. cg.params.b) end)
        pg.before_test('test_1', {b = 1}, function(cg) table.insert(actual, 'before_test_1_b_1_' .. cg.params.b) end)
        pg.after_test('test_2', {b = 2}, function(cg) table.insert(actual, 'after_test_2_b_2_' .. cg.params.b) end)
        pg.after_test('test_2', function(cg) table.insert(actual, 'after_test_2__' .. cg.params.b) end)
        pg.test_1 = function(cg)
            table.insert(actual, 'test1_' .. cg.params.b)
        end
        pg.test_2 = function(cg)
            table.insert(actual, 'test2_' .. cg.params.b)
        end
    end)

    t.assert_equals(result, 0)
    t.assert_equals(actual, expected)
end

g.test_fixed_param_hooks = function()
    local expected = {
        "before_each_b!:1_c:4",
        "test_1_b:1_c:4",
        "before_each_b!:1_c:3",
        "test_1_b:1_c:3",
        "after_each_b:1_c!:3",
        "before_test_b!:2_c!:4",
        "test_1_b:2_c:4",
        "test_1_b:2_c:3",
        "after_each_b:2_c!:3",
    }

    local actual = {}
    local result = helper.run_suite(function(lu2)
        local pg = lu2.group('super', t.helpers.matrix({b = {1, 2}, c = {{v = 3}, {l = 4}}}))

        pg.before_each({b = 1}, function(cg)
            table.insert(actual, "before_each_b!:1_c:".. (cg.params.c.v or cg.params.c.l))
        end)

        pg.after_each({c = {v = 3}}, function(cg)
            table.insert(actual, "after_each_b:".. cg.params.b .."_c!:3")
        end)

        pg.before_test('test_1', {b = 2, c = {l = 4}}, function(cg)
            table.insert(actual, "before_test_b!:".. cg.params.b .."_c!:".. (cg.params.c.v or cg.params.c.l))
        end)

        pg.before_each({b = 3}, function() table.insert(actual, 'will never happen') end)
        pg.before_each({c = {v = 3, l = 4}}, function() table.insert(actual, 'will never happen') end)

        pg.test_1 = function(cg) table.insert(actual,
            string.format("test_1_b:%s_c:%s", cg.params.b, cg.params.c.v or cg.params.c.l))
        end
    end)

    t.assert_equals(result, 0)
    t.assert_equals(actual, expected)
end

g.test_cmd = function()
    local function run_param_test(params)
        local cmd = './bin/luatest'
        local fixture = './test/fixtures/parametrized.lua'
        cmd = cmd .. ' ' .. fixture .. ' '
        cmd = cmd .. 'parametrized_fixture.' .. params
        cmd = cmd .. '.test_something'
        return os.execute(cmd)
    end

    t.assert_equals(run_param_test('a:1.b:4'), 0)
    t.assert_equals(run_param_test('a:3.b:4'), 256)
end
