--- Tool for testing tarantool applications.
--
-- @module luatest
local luautest = require('luatest.luaunit')

luautest.runner = require('luatest.runner')
luautest.Process = require('luatest.process')

--- Helpers.
-- @see luatest.helpers
luautest.helpers = require('luatest.helpers')

--- Class to manage tarantool instances.
-- @see luatest.server
luautest.Server = require('luatest.server')

return luautest

-- LDocs for luaunit functions.
-- We encourage using snake_case naming and simple assertions (no assertNumber, etc.)
-- so we document only these functions.

---
-- @function almost_equals
-- @number actual
-- @number expected
-- @number margin

--- Check that two floats are close by margin.
--
-- @function assert_almost_equals
-- @number actual
-- @number expected
-- @number margin
-- @string[opt] message

--- Check that two values are equal.
-- Tables are compared by value.
--
-- @function assert_equals
-- @param actual
-- @param expected
-- @string[opt] message
-- @bool[opt] deep_analysis print diff.

--- Check that calling fn raises an error.
--
-- @function assert_error
-- @func fn
-- @param ... arguments for function

---
-- @function assert_error_msg_contains
-- @string expected_partial
-- @func fn
-- @param ... arguments for function

---
-- Strips location info from message text.
--
-- @function assert_error_msg_content_equals
-- @string expected
-- @func fn
-- @param ... arguments for function

---
-- Checks full error: location and text.
--
-- @function assert_error_msg_equals
-- @string expected
-- @func fn
-- @param ... arguments for function

---
-- @function assert_error_msg_matches
-- @string pattern
-- @func fn
-- @param ... arguments for function

--- Check that value is falsy.
--
-- @function assert_eval_to_false
-- @param value
-- @string[opt] message

--- Check that value is truthy.
--
-- @function assert_eval_to_true
-- @param value
-- @string[opt] message

--- Check that values are the same.
--
-- @function assert_is
-- @param actual
-- @param expected
-- @string[opt] message

--- Check that the items of table expected are contained in table actual.
-- Warning, this function is at least O(n^2)
--
-- @function assert_items_equals
-- @param actual
-- @param expected
-- @string[opt] message

---
-- @function assert_nan
-- @param value
-- @string[opt] message

--- Check that two floats are not close by margin.
--
-- @function assert_not_almost_equals
-- @number actual
-- @number expected
-- @number margin
-- @string[opt] message

--- Check that two values are not equal.
-- Tables are compared by value.
--
-- @function assert_not_equals
-- @param actual
-- @param expected
-- @string[opt] message

--- Check that values are not the same.
--
-- @function assert_not_is
-- @param actual
-- @param expected
-- @string[opt] message

---
-- @function assert_not_nan
-- @param value
-- @string[opt] message

--- Case-sensitive strings comparison.
--
-- @function assert_not_str_contains
-- @string actual
-- @string expected
-- @bool[opt] is_pattern
-- @string[opt] message

--- Case-insensitive strings comparison.
--
-- @function assert_not_str_icontains
-- @string value
-- @string expected
-- @string[opt] message

--- Case-sensitive strings comparison.
--
-- @function assert_str_contains
-- @string value
-- @string expected
-- @bool[opt] is_pattern
-- @string[opt] message

--- Case-insensitive strings comparison.
--
-- @function assert_str_icontains
-- @string value
-- @string expected
-- @string[opt] message

--- Verify a full match for the string.
--
-- @function assert_str_matches
-- @string value
-- @string pattern
-- @int[opt=1] start
-- @int[opt=value:len()] final
-- @string[opt] message

--- Stops a test due to a failure.
--
-- @function fail
-- @string message

--- Stops a test due to a failure if condition is met.
--
-- @function fail_if
-- @param condition
-- @string message

--- Create group of tests.
--
-- @function group
-- @string name

--- Skip a running test.
--
-- @function skip
-- @string message

--- Skip a running test if condition is met.
--
-- @function skip_if
-- @param condition
-- @string message

--- Stops a test with a success.
--
-- @function success

--- Stops a test with a success if condition is met.
--
-- @function success_if
-- @param condition
