local t = require('luatest')
local g = t.group()

local utils = require('luatest.utils')

g.test_is_tarantool_binary = function()
    local cases = {
        {'/usr/bin/tarantool', true},
        {'/usr/local/bin/tarantool', true},
        {'/usr/local/bin/tt', false},
        {'/usr/bin/ls', false},
        {'/home/myname/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/go-server', false},
        {'/usr/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
        {'/home/tarantool/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
    }

    for _, case in ipairs(cases) do
        local path, result = unpack(case)
        t.assert_equals(utils.is_tarantool_binary(path), result,
                        ("Unexpected result for %q"):format(path))
    end
end

g.test_table_pack = function()
    t.assert_equals(utils.table_pack(), {n = 0})
    t.assert_equals(utils.table_pack(1), {n = 1, 1})
    t.assert_equals(utils.table_pack(1, 2), {n = 2, 1, 2})
    t.assert_equals(utils.table_pack(1, 2, nil), {n = 3, 1, 2})
    t.assert_equals(utils.table_pack(1, 2, nil, 3), {n = 4, 1, 2, nil, 3})
end

g.test_box_error = function()
    local err = 'FOOBAR'
    t.assert_not(utils.is_box_error(err))
    t.assert_equals(utils.error_unpack(err), err)
    err = box.error.new({type = 'MyError', reason = 'FOOBAR'})
    err:set_prev(box.error.new({type = 'MyError2', reason = 'FUZZ'}))
    t.assert(utils.is_box_error(err))
    t.assert_covers(utils.error_unpack(err), {
        type = 'MyError', message = 'FOOBAR',
        prev = {type = 'MyError2', message = 'FUZZ'}
    })
end

-- Helper to extract line number from luatest error message ("path:line: msg").
local function error_line(err)
    if type(err) == 'table' and err.message then
        return tonumber(err.message:match(':(%d+):'))
    end
end

-- Helper to get current line number (for expected line in assertions).
local function current_line()
    return debug.getinfo(2, 'l').currentline
end

-- A helper function that calls t.assert internally.
local function assert_true_helper(value)
    t.helper()

    t.assert(value, 'assertion failed in helper')
end

-- A helper that calls another helper.
local function nested_helper(value)
    t.helper()

    assert_true_helper(value)
end

-- A function without t.helper().
local function not_a_helper(value)
    t.assert(value, 'assertion failed')
end

g.test_helper_points_to_caller = function()
    local expected_line = current_line() + 2
    local err = t.assert_error(function()
        assert_true_helper(false) -- error should point HERE
    end)
    t.assert(utils.is_luatest_error(err), err)
    t.assert_equals(error_line(err), expected_line)
end

g.test_helper_nested = function()
    local expected_line = current_line() + 2
    local err = t.assert_error(function()
        nested_helper(false) -- error should point HERE, skipping both helpers
    end)
    t.assert(utils.is_luatest_error(err), err)
    t.assert_equals(error_line(err), expected_line)
end

g.test_no_helper_points_to_function = function()
    -- Without t.helper(), error points to t.assert inside not_a_helper.
    local helper_line = debug.getinfo(not_a_helper, 'Sl').linedefined + 1
    local err = t.assert_error(function()
        not_a_helper(false)
    end)
    t.assert(utils.is_luatest_error(err), err)
    t.assert_equals(error_line(err), helper_line)
end
