local t = require('luatest')
local g = t.group('luatest')

local helper = require('test.helper')

g.test_assert_returns_velue = function()
    t.assert_equals(t.assert(1), 1)
    local obj = {a = 'a', b = 'b'}
    t.assert_is(t.assert(obj, 'extra msg'), obj)
    t.assert_equals({t.assert(obj, 'extra msg', 1, 2, 3)}, {obj, 'extra msg', 1, 2, 3})
end

g.test_assert_tnt_specific = function()
    t.assert(true)
    t.assert({})
    t.assert_error(function() t.assert(box.NULL) end)
    t.assert_not(box.NULL)
    t.assert_error(function() t.assert_not(true) end)
    t.assert_error(function() t.assert_not({}) end)
end

g.test_assert_equals_tnt_tuples = function()
    t.assert_equals(box.tuple.new(1), box.tuple.new(1))
    t.assert_equals(box.tuple.new(1, 'a', box.NULL), box.tuple.new(1, 'a', box.NULL))
    t.assert_equals(box.tuple.new(1, {'a'}), box.tuple.new(1, {'a'}))

    t.assert_not_equals(box.tuple.new(1), box.tuple.new(2))
    t.assert_not_equals(box.tuple.new(1, 'a', box.NULL), box.tuple.new(1, 'a'))
    t.assert_not_equals(box.tuple.new(1, {'a'}), box.tuple.new(1, {'b'}))
end

g.test_fail_if_tnt_specific = function()
    t.fail_if(box.NULL, 'unexpected')
    t.assert_error(function() t.fail_if(true, 'expected') end)
    t.assert_error(function() t.fail_if({}, 'expected') end)
end

local function assert_any_error(fn, ...)
    local ok, err = pcall(fn, ...)
    t.assert(ok, 'Got error: ' .. tostring(err))
end

g.test_skip_if_tnt_specific = function()
    assert_any_error(t.skip_if, box.NULL, 'unexpected')
    t.assert_equals(t.assert_error(t.skip_if, true, 'expected').status, 'skip')
    t.assert_equals(t.assert_error(t.skip_if, {}, 'expected').status, 'skip')
end

g.test_success_if_tnt_specific = function()
    assert_any_error(t.success_if, box.NULL)
    t.assert_equals(t.assert_error(t.success_if, true).status, 'success')
    t.assert_equals(t.assert_error(t.success_if, {}).status, 'success')
end

g.test_assert_aliases = function ()
    t.assert_is(t.assert, t.assert_eval_to_true)
    t.assert_is(t.assert_not, t.assert_eval_to_false)
end

g.test_assert_covers = function()
    local subject = t.assert_covers
    subject({a = 1, b = 2, c = 3}, {})
    subject({a = 1, b = 2, c = 3}, {a = 1})
    subject({a = 1, b = 2, c = 3}, {a = 1, c = 3})
    subject({a = 1, b = 2, c = 3}, {a = 1, b = 2, c = 3})
    subject({a = box.NULL}, {a = box.NULL})

    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 2})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 1, b = 1})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 1, b = 2, c = 3, d = 4})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {d = 1})
    t.assert_error(subject, {a = nil}, {a = box.NULL})
end

g.test_assert_not_covers = function()
    local subject = t.assert_not_covers
    subject({a = 1, b = 2, c = 3}, {a = 2})
    subject({a = 1, b = 2, c = 3}, {a = 1, b = 1})
    subject({a = 1, b = 2, c = 3}, {a = 1, b = 2, c = 3, d = 4})
    subject({a = 1, b = 2, c = 3}, {d = 1})
    subject({a = nil}, {a = box.NULL})

    t.assert_error(subject, {a = 1, b = 2, c = 3}, {})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 1})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 1, c = 3})
    t.assert_error(subject, {a = 1, b = 2, c = 3}, {a = 1, b = 2, c = 3})
    t.assert_error(subject, {a = box.NULL}, {a = box.NULL})
end

g.test_assert_type = function()
    local subject = t.assert_type
    subject(1, 'number')
    subject('1', 'string')

    t.assert_error(subject, 1, 'string')
    t.assert_error(subject, '1', 'number')
end

g.test_group_with_existing_name_fails = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('asd')
        t.assert_error_msg_contains('Test group already exists: asd', lu2.group, 'asd')
        lu2.group('qwe')
    end)
    t.assert_equals(result, 0)
end

g.test_group_with_dot = function()
    local run
    local result = helper.run_suite(function(lu2)
        lu2.group('asd.qwe').test_1 = function() run = true end
    end)
    t.assert_equals(result, 0)
    t.assert(run)
end

g.test_group_with_slash_in_name_fails = function()
    local result = helper.run_suite(function(lu2)
        t.assert_error_msg_contains('Group name must not contain `/`: asd/qwe', lu2.group, 'asd/qwe')
    end)
    t.assert_equals(result, 0)
end

g.test_group_sets_default_group_name_from_filename = function()
    local result = helper.run_suite(function(lu2)
        local g2 = lu2.group()
        t.assert_is(lu2.groups.luatest, g2)
    end)
    t.assert_equals(result, 0)
end
