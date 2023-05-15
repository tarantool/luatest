local t = require('luatest')
local g = t.group()

local helper = require('test.helpers.general')
local assert_failure = helper.assert_failure
local assert_failure_equals = helper.assert_failure_equals

local function f()
end

local function f_with_error()
    error('This is an error', 2)
end

local function f_with_table_error()
    local ts = {__tostring = function() return 'This table has error!' end}
    error(setmetatable({this_table="has error"}, ts))
end

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
end
