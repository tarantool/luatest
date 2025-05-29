local t = require('luatest')
local g = t.group()

local helper = require('test.helpers.general')
local assert_failure = helper.assert_failure
local assert_failure_equals = helper.assert_failure_equals
local assert_failure_contains = helper.assert_failure_contains
local assert_failure_matches = helper.assert_failure_matches

local function f()
end

local function f_with_error()
    error('This is an error', 2)
end

local function f_with_table_error()
    local ts = {__tostring = function() return 'This table has error!' end}
    error(setmetatable({this_table="has error"}, ts))
end

local f_check_trace = function(level)
    box.error(box.error.UNKNOWN, level)
end

local wrapper_line = debug.getinfo(1, 'l').currentline + 2
local f_check_trace_wrapper = function()
    f_check_trace(2)
end

local _, wrapper_err = pcall(f_check_trace_wrapper)
local box_error_has_level = wrapper_err:unpack().trace[1].line == wrapper_line

local f_check_success = function()
    return {1, 'foo'}
end

local THIS_MODULE = debug.getinfo(1, 'S').short_src

g.after_each(function()
    t.private.check_trace_module = nil
end)

function g.test_assert_error()
    local x = 1

    -- f_with_error generates an error
    local has_error = not pcall(f_with_error, x)
    t.assert_equals(has_error, true)

    -- f does not generate an error
    has_error = not pcall(f, x)
    t.assert_equals(has_error, false)

    -- t.assert_error is happy with f_with_error
    t.assert_error(f_with_error, x)

    -- t.assert_error is unhappy with f
    assert_failure_equals("Expected an error when calling function but no error generated",
                         t.assert_error, f, x)

    -- multiple arguments
    local function f_with_multi_arguments(a,b,c)
        if a == b and b == c then return end
        error("three arguments not equal")
    end

    t.assert_error(f_with_multi_arguments, 1, 1, 3)
    t.assert_error(f_with_multi_arguments, 1, 3, 1)
    t.assert_error(f_with_multi_arguments, 3, 1, 1)

    assert_failure_equals("Expected an error when calling function but no error generated",
                         t.assert_error, f_with_multi_arguments, 1, 1, 1)

    -- error generated as table
    t.assert_error(f_with_table_error, 1)

    -- test assert failure due to unexpected error trace
    t.private.check_trace_module = THIS_MODULE
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error, f_check_trace, 1)
end

function g.test_assert_errorMsgContains()
    local x = 1
    assert_failure(t.assert_error_msg_contains, 'toto', f, x)
    t.assert_error_msg_contains('is an err', f_with_error, x)
    t.assert_error_msg_contains('This is an error', f_with_error, x)
    assert_failure(t.assert_error_msg_contains, ' This is an error', f_with_error, x)
    assert_failure(t.assert_error_msg_contains, 'This .. an error', f_with_error, x)
    t.assert_error_msg_contains("50", function() error(500) end)

    -- error message is a table which converts to a string
    t.assert_error_msg_contains('This table has error', f_with_table_error, 1)

    -- test assert failure due to unexpected error trace
    t.private.check_trace_module = THIS_MODULE
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error_msg_contains, 'bar', f_check_trace,
                            1)
end

function g.test_assert_error_msg_equals()
    local x = 1
    assert_failure(t.assert_error_msg_equals, 'toto', f, x)
    assert_failure(t.assert_error_msg_equals, 'is an err', f_with_error, x)

    -- expected string, receive string
    t.assert_error_msg_equals('This is an error', f_with_error, x)

    -- expected table, receive table
    t.assert_error_msg_equals({1,2,3,4}, function() error({1,2,3,4}) end)

    -- expected complex table, receive complex table
    t.assert_error_msg_equals({
        details = {1,2,3,4},
        id = 10,
    }, function() error({
        details = {1,2,3,4},
        id = 10,
    }) end)

    -- expected string, receive number converted to string
    t.assert_error_msg_equals("500", function() error(500, 2) end)

    -- one space added at the beginning
    assert_failure(t.assert_error_msg_equals, ' This is an error', f_with_error, x)

    -- pattern does not work
    assert_failure(t.assert_error_msg_equals, 'This .. an error', f_with_error, x)

    -- expected string, receive table which converts to string
    t.assert_error_msg_equals("This table has error!", f_with_table_error, x)

    -- expected table, no error generated
    assert_failure(t.assert_error_msg_equals, {1}, function() return "{1}" end, 33)

    -- expected table, error generated as string, no match
    assert_failure(t.assert_error_msg_equals, {1}, function() error("{1}") end, 33)

    -- test assert failure due to unexpected error trace
    t.private.check_trace_module = THIS_MODULE
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error_msg_equals, 'bar', f_check_trace, 1)
end

function g.test_assert_errorMsgMatches()
    local x = 1
    assert_failure(t.assert_error_msg_matches, 'toto', f, x)
    assert_failure(t.assert_error_msg_matches, 'is an err', f_with_error, x)
    t.assert_error_msg_matches('This is an error', f_with_error, x)
    t.assert_error_msg_matches('This is .. error', f_with_error, x)
    t.assert_error_msg_matches(".*500$", function() error(500, 2) end)
    t.assert_error_msg_matches("This .* has error!", f_with_table_error, 33)

    -- one space added to cause failure
    assert_failure(t.assert_error_msg_matches, ' This is an error', f_with_error, x)
    assert_failure(t.assert_error_msg_matches,  "This", f_with_table_error, 33)

    -- test assert failure due to unexpected error trace
    t.private.check_trace_module = THIS_MODULE
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error_msg_matches, 'bar', f_check_trace, 1)
end

function g.test_assert_errorCovers()
    local actual
    local expected
    -- function executes successfully
    assert_failure_equals('Function successfully returned: {1, "foo"}\n' ..
                          'Expected error: {}', t.assert_error_covers, {},
                          function() return {1, 'foo'} end)
    ----------------
    -- good coverage
    ----------------
    t.assert_error_covers({}, error, {})
    t.assert_error_covers({b = 2}, error, {b = 2})
    t.assert_error_covers({b = 2}, error, {a = 1, b = 2})
    actual = {a = 1, b = 2, prev = {x = 3, y = 4}}
    expected = {b = 2, prev = {x = 3}}
    t.assert_error_covers(expected, error, actual)
    actual.prev.prev = {i = 5, j = 6}
    expected.prev.prev = {j = 6}
    t.assert_error_covers(expected, error, actual)
    ---------------
    -- bad coverage
    ---------------
    local msg = 'Error expected: .*\nError received: .*'
    assert_failure_matches(msg, t.assert_error_covers,
                           {b = 2}, error, {a = 1, b = 3})
    assert_failure_matches(msg, t.assert_error_covers, {b = 2}, error, {a = 1})
    assert_failure_matches(msg, t.assert_error_covers, {b = 2}, error, {})
    actual = {a = 1, b = 2, prev = {x = 3, y = 4}}
    expected = {b = 2, prev = {x = 4}}
    assert_failure_matches(msg, t.assert_error_covers, expected, error, actual)
    actual = {a = 1, b = 2, prev = {x = 3, y = 4, prev = {i = 5, j = 6}}}
    expected = {b = 2, prev = {x = 3, prev = {i = 6}}}
    assert_failure_matches(msg, t.assert_error_covers, expected, error, actual)
    --------
    --- misc
    --------
    -- several arguments for tested function
    local error_args = function(a, b) error({a = a, b = b}) end
    t.assert_error_covers({b = 2}, error_args, 1, 2)
    -- full error message
    assert_failure_equals('Error expected: {b = 2}\n' ..
                          'Error received: {a = 1, b = 3}',
                          t.assert_error_covers, {b = 2}, error, {a = 1, b = 3})
    ---------------
    -- corner cases
    ---------------
    -- strange, but still
    t.assert_error_covers('foo', error, 'foo')
    -- same but for stacked diagnostics
    t.assert_error_covers({b = 2, prev = 'foo'},
                          error, {a = 1, b = 2, prev = 'foo'})
    -- actual error is not table
    assert_failure_matches(msg, t.assert_error_covers, {}, error, 'foo')
    -- expected in not a table
    assert_failure_matches(msg, t.assert_error_covers, 2, error, {})
    -- actual error is not indexable
    assert_failure_matches(msg, t.assert_error_covers, {}, error, 1LL)
    -- actual error prev is not table
    assert_failure_matches(msg, t.assert_error_covers, {prev = {}},
                           error, {prev = 'foo'})
    -- expected error prev is not table
    assert_failure_matches(msg, t.assert_error_covers, {prev = 'foo'},
                           error, {prev = {}})
    -- actual error prev is not indexable
    assert_failure_matches(msg, t.assert_error_covers, {prev = {}},
                           error, {prev = 1LL})
    ------------
    -- box.error
    ------------
    t.assert_error_covers({type = 'ClientError', code = 0}, box.error, 0)
    local err = box.error.new(box.error.UNKNOWN)
    if err.set_prev ~= nil then
        err:set_prev(box.error.new(box.error.UNSUPPORTED, 'foo', 'bar'))
        expected = {
            type = 'ClientError',
            code = box.error.UNKNOWN,
            prev = {type = 'ClientError', code = box.error.UNSUPPORTED}
        }
        t.assert_error_covers(expected, box.error, err)
    end

    -- test assert failure due to unexpected error trace
    t.private.check_trace_module = THIS_MODULE
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error_covers, 'bar', f_check_trace, 1)
end

function g.test_error_trace_check()
    local foo = function(a) error(a) end
    -- test when trace check is NOT required
    t.assert_error_msg_content_equals('foo', foo, 'foo')

    local ftor = setmetatable({}, {
        __call = function(_, ...) return f_check_trace(...) end
    })
    t.private.check_trace_module = THIS_MODULE

    -- test when trace check IS required
    if box_error_has_level then
        t.assert_error_covers({code = box.error.UNKNOWN}, f_check_trace, 2)
        t.assert_error_covers({code = box.error.UNKNOWN}, ftor, 2)
    end

    -- check if there is no error then the returned value is reported correctly
    assert_failure_contains('Function successfully returned: {1, "foo"}',
                            t.assert_error_msg_equals, 'bar', f_check_success)
    -- test assert failure due to unexpected error type
    assert_failure_contains('Error raised is not a box.error:',
                            t.assert_error, foo, 'foo')
    -- test assert failure due to unexpected error trace
    assert_failure_contains('Unexpected error trace, expected:',
                            t.assert_error, f_check_trace, 1)
end
