--- Module with assertion methods.
-- These methods are available in the root luatest module.
--
-- @submodule luatest

local math = require('math')

local comparator = require('luatest.comparator')
local mismatch_formatter = require('luatest.mismatch_formatter')
local pp = require('luatest.pp')
local log = require('luatest.log')
local utils = require('luatest.utils')
local tarantool = require('tarantool')
local ffi = require('ffi')

local prettystr = pp.tostring
local prettystr_pairs = pp.tostring_pair

local M = {}

local xfail = false

local box_error_type = ffi.typeof(box.error.new(box.error.UNKNOWN))

-- private exported functions (for testing)
M.private = {}

function M.private.is_xfail()
    local xfail_status = xfail
    xfail = false
    return xfail_status
end

--[[--

EPS is meant to help with Lua's floating point math in simple corner
cases like almost_equals(1.1-0.1, 1), which may not work as-is (e.g. on numbers
with rational binary representation) if the user doesn't provide some explicit
error margin.

The default margin used by almost_equals() in such cases is EPS; and since
Lua may be compiled with different numeric precisions (single vs. double), we
try to select a useful default for it dynamically. Note: If the initial value
is not acceptable, it can be changed by the user to better suit specific needs.

See also: https://en.wikipedia.org/wiki/Machine_epsilon
]]
M.EPS = 2^-52 -- = machine epsilon for "double", ~2.22E-16
if math.abs(1.1 - 1 - 0.1) > M.EPS then
    -- rounding error is above EPS, assume single precision
    M.EPS = 2^-23 -- = machine epsilon for "float", ~1.19E-07
end

local function failure(msg, extra_msg, level)
    -- raise an error indicating a test failure
    -- for error() compatibility we adjust "level" here (by +1), to report the
    -- calling context
    if extra_msg ~= nil then
        if type(extra_msg) ~= 'string' then
            extra_msg = prettystr(extra_msg)
        end
        if #extra_msg > 0 then
            msg = extra_msg .. '\n' .. msg
        end
    end
    utils.luatest_error('fail', msg, (level or 1) + 1)
end

local function fail_fmt(level, message, ...)
     -- failure with printf-style formatted message and given error level
    failure(string.format(...), message, (level or 1) + 1)
end
M.private.fail_fmt = fail_fmt

local function error_msg_equality(actual, expected, deep_analysis)
    if type(expected) == 'string' or type(expected) == 'table' then
        local strExpected, strActual = prettystr_pairs(expected, actual)
        local result = string.format("expected: %s\nactual: %s", strExpected, strActual)

        -- extend with mismatch analysis if possible:
        local success, mismatchResult = mismatch_formatter.format(actual, expected, deep_analysis)
        if success then
            result = table.concat({result, mismatchResult}, '\n')
        end
        return result
    end
    return string.format("expected: %s, actual: %s",
                         prettystr(expected), prettystr(actual))
end
M.private.error_msg_equality = error_msg_equality

--
-- The wrapper is used when trace check is required. See pcall_check_trace.
--
-- Without wrapper the trace will point to the pcall implementation. So trace
-- check is not strict enough (the trace can point to any pcall in below in
-- call trace).
--
local trace_line = debug.getinfo(1, 'l').currentline + 2
local function wrapped_call(fn, ...)
    local res = utils.table_pack(fn(...))
    -- With `return fn(...)` wrapper does not work due to tail call
    -- optimization.
    return unpack(res, 1, res.n)
end

-- Expected trace for trace check. See pcall_check_trace.
local wrapped_trace = {
    file = debug.getinfo(1, 'S').short_src,
    line = trace_line,
}

-- Used in tests to force check for given module.
M.private.check_trace_module = nil

--
-- Return true if error trace check is required for function. Basically it is
-- just a wrapper around Tarantool's utils.proper_trace_required. Additionally
-- old Tarantool versions where this function is not present are handled.
--
local function trace_check_is_required(fn)
    local src = debug.getinfo(fn, 'S').short_src
    if M.private.check_trace_module == src then
        return true
    end
    if tarantool._internal ~= nil and
       tarantool._internal.trace_check_is_required ~= nil then
        local path = debug.getinfo(fn, 'S').short_src
        return tarantool._internal.trace_check_is_required(path)
    end
    return false
end

--
-- Substitute for pcall but additionally checks error trace if required.
--
-- The error should be box.error and trace should point to the place
-- where fn is called.
--
-- level is used to set proper level in error assertions that use this function.
--
local function pcall_check_trace(level, fn, ...)
    local fn_explicit = fn
    if type(fn) ~= 'function' then
        fn_explicit = debug.getmetatable(fn).__call
    end
    if not trace_check_is_required(fn_explicit) then
        return pcall(fn, ...)
    end
    local ok, err = pcall(wrapped_call, fn, ...)
    if ok then
        return ok, err
    end
    if type(err) ~= 'cdata' or ffi.typeof(err) ~= box_error_type then
        fail_fmt(level + 1, nil, 'Error raised is not a box.error: %s',
                 prettystr(err))
    end
    local unpacked = err:unpack()
    if not comparator.equals(unpacked.trace[1], wrapped_trace) then
        fail_fmt(level + 1, nil,
                 'Unexpected error trace, expected: %s, actual: %s',
                 prettystr(wrapped_trace), prettystr(unpacked.trace[1]))
    end
    return ok, err
end

--- Check that calling fn raises an error.
--
-- @func fn
-- @param ... arguments for function
function M.assert_error(fn, ...)
    local ok, err = pcall_check_trace(2, fn, ...)
    if ok then
        failure("Expected an error when calling function but no error generated", nil, 2)
    end
    return err
end

--- Stops a test due to a failure.
--
-- @function fail
-- @string message
function M.fail(message)
    failure(message, nil, 2)
end

--- Stops a test due to a failure if condition is met.
--
-- @param condition
-- @string message
function M.fail_if(condition, message)
    if condition and condition ~= nil then
        failure(message, nil, 2)
    end
end

--- Skip a running test.
--
-- @string message
function M.skip(message)
    utils.luatest_error('skip', message or '(no reason specified)', 2)
end

--- Skip a running test if condition is met.
--
-- @param condition
-- @string message
function M.skip_if(condition, message)
    if condition and condition ~= nil then
        utils.luatest_error('skip', message or '(no reason specified)', 2)
    end
end

function M.run_only_if(condition, message)
    -- continue a running test if condition is met, else skip it
    if not (condition and condition ~= nil) then
        utils.luatest_error('skip', message or '(no reason specified)', 2)
    end
end

--- Stops a test with a success.
function M.success()
    utils.luatest_error('success', 2)
end

--- Stops a test with a success if condition is met.
--
-- @param condition
function M.success_if(condition)
    if condition and condition ~= nil then
        utils.luatest_error('success', 2)
    end
end

--- Mark a test as xfail.
--
-- @string message
function M.xfail(message)
    xfail = message or true
end

--- Mark a test as xfail if condition is met
--
-- @param condition
-- @string message
function M.xfail_if(condition, message)
    if condition and condition ~= nil then
        xfail = message or true
    end
end

--- Check that two values are equal.
-- Tables are compared by value.
--
-- @param actual
-- @param expected
-- @string[opt] message
-- @bool[opt] deep_analysis print diff.
function M.assert_equals(actual, expected, message, deep_analysis)
    log.info('Assert %s equals to %s', actual, expected)
    if not comparator.equals(actual, expected) then
        failure(M.private.error_msg_equality(actual, expected, deep_analysis), message, 2)
    end
end

---
-- @number actual
-- @number expected
-- @number margin
-- @string[opt] message
function M.almost_equals(actual, expected, margin, message)
    if not tonumber(actual) or not tonumber(expected) or not tonumber(margin) then
        fail_fmt(2, message, 'almost_equals: must supply only number arguments.\n' ..
            'Arguments supplied: %s, %s, %s',
            actual, expected, margin)
    end
    if margin < 0 then
        failure('almost_equals: margin must not be negative, current value is ' .. margin, nil, 2)
    end
    return math.abs(tonumber(expected - actual)) <= margin
end

--- Check that two floats are close by margin.
--
-- @number actual
-- @number expected
-- @number margin
-- @string[opt] message
function M.assert_almost_equals(actual, expected, margin, message)
    margin = margin or M.EPS
    if not M.almost_equals(actual, expected, margin) then
        local delta = math.abs(tonumber(actual - expected))
        fail_fmt(2, message, 'Values are not almost equal\n' ..
                    'Actual: %s, expected: %s, delta %s above margin of %s',
                    actual, expected, delta, margin)
    end
end

--- Check that left is less than right.
--
-- @number left
-- @number right
-- @string[opt] message
function M.assert_lt(left, right, message)
    if not tonumber(left) or not tonumber(right) then
        print(prettystr(right))
        fail_fmt(2, message, 'assert_lt: must supply only number arguments.\nArguments supplied: %s, %s',
            prettystr(left), prettystr(right))
    end
    if not comparator.lt(tonumber(left), tonumber(right)) then
        fail_fmt(2, message, 'Assertion failed: %s < %s', left, right)
    end
end

--- Check that left is greater than right.
--
-- @number left
-- @number right
-- @string[opt] message
function M.assert_gt(left, right, message)
    if not tonumber(left) or not tonumber(right) then
        fail_fmt(2, message, 'assert_gt: must supply only number arguments.\nArguments supplied: %s, %s',
            prettystr(left), prettystr(right))
    end
    if not comparator.lt(tonumber(right), tonumber(left)) then
        fail_fmt(2, message, 'Assertion failed: %s > %s', left, right)
    end
end

--- Check that left is less than or equal to right.
--
-- @number left
-- @number right
-- @string[opt] message
function M.assert_le(left, right, message)
    if not tonumber(left) or not tonumber(right) then
        fail_fmt(2, message, 'assert_le: must supply only number arguments.\nArguments supplied: %s, %s',
            prettystr(left), prettystr(right))
    end
    if not (comparator.le(tonumber(left), tonumber(right))) then
        fail_fmt(2, message, 'Assertion failed: %s <= %s', left, right)
    end
end

--- Check that left is greater than or equal to right.
--
-- @number left
-- @number right
-- @string[opt] message
function M.assert_ge(left, right, message)
    if not tonumber(left) or not tonumber(right) then
        fail_fmt(2, message, 'assert_ge: must supply only number arguments.\nArguments supplied: %s, %s',
            prettystr(left), prettystr(right))
    end
    if not (comparator.le(tonumber(right), tonumber(left))) then
        fail_fmt(2, message, 'Assertion failed: %s >= %s', left, right)
    end
end

--- Check that two values are not equal.
-- Tables are compared by value.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_not_equals(actual, expected, message)
    log.info('Assert %s not equals to %s', actual, expected)
    if comparator.equals(actual, expected) then
        fail_fmt(2, message, 'Actual and expected values are equal: %s', prettystr(actual))
    end
end

--- Check that two floats are not close by margin.
--
-- @number actual
-- @number expected
-- @number margin
-- @string[opt] message
function M.assert_not_almost_equals(actual, expected, margin, message)
    margin = margin or M.EPS
    if M.almost_equals(actual, expected, margin) then
        local delta = math.abs(actual - expected)
        fail_fmt(2, message, 'Values are almost equal\nActual: %s, expected: %s' ..
                    ', delta %s below margin of %s',
                    actual, expected, delta, margin)
    end
end

--- Checks that two tables contain the same items, irrespective of their keys.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_items_equals(actual, expected, message)
    if comparator.is_subset(actual, expected) ~= 0 then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, message, 'Item values of the tables are not identical\nExpected table: %s\nActual table: %s',
                 expected, actual)
    end
end

--- Checks that one table includes all items of another, irrespective of their keys.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_items_include(actual, expected, message)
    if not comparator.is_subset(expected, actual) then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, message, 'Expected all item values from: %s\nTo be present in: %s', expected, actual)
    end
end

local function table_covers(actual, expected)
    if type(actual) ~= 'table' or type(expected) ~= 'table' then
        failure('Argument 1 and 2 must be tables', nil, 3)
    end
    local sliced = {}
    for k, _ in pairs(expected) do
        sliced[k] = actual[k]
    end
    return comparator.equals(sliced, expected)
end

--- Checks that actual map includes expected one.
--
-- @tab actual
-- @tab expected
-- @string[opt] message
function M.assert_covers(actual, expected, message)
    if not table_covers(actual, expected) then
        local str_actual, str_expected = prettystr_pairs(actual, expected)
        failure(string.format('expected %s to cover %s', str_actual, str_expected), message, 2)
    end
end

--- Checks that map does not contain the other one.
--
-- @tab actual
-- @tab expected
-- @string[opt] message
function M.assert_not_covers(actual, expected, message)
    if table_covers(actual, expected) then
        local str_actual, str_expected = prettystr_pairs(actual, expected)
        failure(string.format('expected %s to not cover %s', str_actual, str_expected), message, 2)
    end
end

local function str_match(s, pattern, start, final)
    -- return true if s matches completely the pattern from index start to index end
    -- return false in every other cases
    -- if start is nil, matches from the beginning of the string
    -- if final is nil, matches to the end of the string
    start = start or 1
    final = final or string.len(s)

    local foundStart, foundEnd = string.find(s, pattern, start, false)
    return foundStart == start and foundEnd == final
end
M.private.str_match = str_match

--- Case-sensitive strings comparison.
--
-- @string value
-- @string expected
-- @bool[opt] is_pattern
-- @string[opt] message
function M.assert_str_contains(value, expected, is_pattern, message)
    log.info('Assert string %s contains %s', value, expected)

    M.assert_type(value, 'string', nil, 2)
    M.assert_type(expected, 'string', nil, 2)

    if not string.find(value, expected, 1, not is_pattern) then
        expected, value = prettystr_pairs(expected, value, '\n')
        fail_fmt(2, message, 'Could not find %s %s in string %s',
            is_pattern and 'pattern' or 'substring', expected, value)
    end
end

--- Case-insensitive strings comparison.
--
-- @string value
-- @string expected
-- @string[opt] message
function M.assert_str_icontains(value, expected, message)
    M.assert_type(value, 'string', nil, 2)
    M.assert_type(expected, 'string', nil, 2)

    if not string.find(value:lower(), expected:lower(), 1, true) then
        expected, value = prettystr_pairs(expected, value, '\n')
        fail_fmt(2, message, 'Could not find (case insensitively) substring %s in string %s', expected, value)
    end
end

--- Case-sensitive strings comparison.
--
-- @string actual
-- @string expected
-- @bool[opt] is_pattern
-- @string[opt] message
function M.assert_not_str_contains(actual, expected, is_pattern, message)
    M.assert_type(actual, 'string', nil, 2)
    M.assert_type(expected, 'string', nil, 2)

    if string.find(actual, expected, 1, not is_pattern) then
        expected, actual = prettystr_pairs(expected, actual, '\n')
        fail_fmt(2, message, 'Found unexpected %s %s in string %s',
            is_pattern and 'pattern' or 'substring', expected, actual)
    end
end

--- Case-insensitive strings comparison.
--
-- @string value
-- @string expected
-- @string[opt] message
function M.assert_not_str_icontains(value, expected, message)
    M.assert_type(value, 'string', nil, 2)
    M.assert_type(expected, 'string', nil, 2)

    if string.find(value:lower(), expected:lower(), 1, true) then
        expected, value = prettystr_pairs(expected, value, '\n')
        fail_fmt(2, message, 'Found (case insensitively) unexpected substring %s in string %s', expected, value)
    end
end

--- Verify a full match for the string.
--
-- @string value
-- @string pattern
-- @int[opt=1] start
-- @int[opt=value:len()] final
-- @string[opt] message
function M.assert_str_matches(value, pattern, start, final, message)
    M.assert_type(value, 'string', nil, 2)
    M.assert_type(pattern, 'string', nil, 2)

    if not str_match(value, pattern, start, final) then
        pattern, value = prettystr_pairs(pattern, value, '\n')
        fail_fmt(2, message, 'Could not match pattern %s with string %s', pattern, value)
    end
end

-- Convert an error object to an error message
-- @param err error object
-- @return error message
local function error_to_msg(err)
    if type(err) == 'cdata' then
        -- We assume that this is a `box.error` instance.
        return err.message
    else
        return tostring(err)
    end
end

local function _assert_error_msg_equals(stripFileAndLine, expectedMsg, func, ...)
    local no_error, error_msg = pcall_check_trace(3, func, ...)
    if no_error then
        local failure_message = string.format(
            'Function successfully returned: %s\nExpected error: %s',
            prettystr(error_msg), prettystr(expectedMsg))
        failure(failure_message, nil, 3)
    end
    if type(expectedMsg) == "string" and type(error_msg) ~= "string" then
        error_msg = error_to_msg(error_msg)
    end
    local differ = false
    if stripFileAndLine then
        error_msg = error_msg:gsub("^.+:%d+: ", "")
        if error_msg ~= expectedMsg then
            differ = true
        end
    else
        if error_msg ~= expectedMsg then
            local tr = type(error_msg)
            local te = type(expectedMsg)
            if te == 'table' then
                if tr ~= 'table' then
                    differ = true
                else
                     local ok = pcall(M.assert_items_equals, error_msg, expectedMsg)
                     if not ok then
                         differ = true
                     end
                end
            else
               differ = true
            end
        end
    end

    if differ then
        error_msg, expectedMsg = prettystr_pairs(error_msg, expectedMsg)
        fail_fmt(3, nil, 'Error message expected: %s\nError message received: %s\n',
                 expectedMsg, error_msg)
    end
end

--- Checks full error: location and text.
--
-- @string expected
-- @func fn
-- @param ... arguments for function
function M.assert_error_msg_equals(expected, fn, ...)
    _assert_error_msg_equals(false, expected, fn, ...)
end

--- Strips location info from message text.
--
-- @string expected
-- @func fn
-- @param ... arguments for function
function M.assert_error_msg_content_equals(expected, fn, ...)
     _assert_error_msg_equals(true, expected, fn, ...)
end

---
-- @string expected_partial
-- @func fn
-- @param ... arguments for function
function M.assert_error_msg_contains(expected_partial, fn, ...)
    local no_error, error_msg = pcall_check_trace(2, fn, ...)
    log.info('Assert error message %s contains %s', error_msg, expected_partial)
    if no_error then
        local failure_message = string.format(
            'Function successfully returned: %s\nExpected error containing: %s',
            prettystr(error_msg), prettystr(expected_partial))
        failure(failure_message, nil, 2)
    end
    if type(error_msg) ~= "string" then
        error_msg = error_to_msg(error_msg)
    end
    if not string.find(error_msg, expected_partial, nil, true) then
        error_msg, expected_partial = prettystr_pairs(error_msg, expected_partial)
        fail_fmt(2, nil, 'Error message does not contain: %s\nError message received: %s\n',
            expected_partial, error_msg)
    end
end

---
-- @string pattern
-- @func fn
-- @param ... arguments for function
function M.assert_error_msg_matches(pattern, fn, ...)
    local no_error, error_msg = pcall_check_trace(2, fn, ...)
    if no_error then
        local failure_message = string.format(
            'Function successfully returned: %s\nExpected error matching: %s',
            prettystr(error_msg), prettystr(pattern))
        failure(failure_message, nil, 2)
    end
    if type(error_msg) ~= "string" then
        error_msg = error_to_msg(error_msg)
    end
    if not str_match(error_msg, pattern) then
        pattern, error_msg = prettystr_pairs(pattern, error_msg)
        fail_fmt(2, nil, 'Error message does not match pattern: %s\nError message received: %s\n', pattern, error_msg)
    end
end

-- If it is box.error that unpack it recursively. If it is not then
-- return argument unchanged.
local function error_unpack(err)
    if type(err) ~= 'cdata' or ffi.typeof(err) ~= box_error_type then
        return err
    end
    local unpacked = err:unpack()
    local tmp = unpacked
    while tmp.prev ~= nil do
        tmp.prev = tmp.prev:unpack()
        tmp = tmp.prev
    end
    return unpacked
end

-- Return table with keys from expected but values from actual. Apply
-- same changes recursively for key 'prev'.
local function error_slice(actual, expected)
    if type(expected) ~= 'table' or type(actual) ~= 'table' then
        return actual
    end
    local sliced = {}
    for k, _ in pairs(expected) do
        sliced[k] = actual[k]
    end
    sliced.prev = error_slice(sliced.prev, expected.prev)
    return sliced
end

--- Checks that error raised by function is table that includes expected one.
--- box.error is unpacked to convert to table. Stacked errors are supported.
--- That is if there is prev field in expected then it should cover prev field
--- in actual and so on recursively.
--
-- @tab expected
-- @func fn
-- @param ... arguments for function
function M.assert_error_covers(expected, fn, ...)
    local ok, actual = pcall_check_trace(2, fn, ...)
    if ok then
        fail_fmt(2, nil,
                 'Function successfully returned: %s\nExpected error: %s',
                  prettystr(actual), prettystr(expected))
    end
    local unpacked = error_unpack(actual)
    if not comparator.equals(error_slice(unpacked, expected), expected) then
        actual, expected = prettystr_pairs(unpacked, expected)
        fail_fmt(2, nil, 'Error expected: %s\nError received: %s',
                 expected, actual)
    end
end

--- Alias for @{assert}.
--
-- @param value
-- @string[opt] message
function M.assert_eval_to_true(value, message, ...)
    if not value or value == nil then
        failure("expected: a value evaluating to true, actual: " ..prettystr(value), message, 2)
    end
    return value, message, ...
end

--- Check that value is truthy.
--
-- @function assert
-- @param value
-- @string[opt] message
-- @param[opt] ...
-- @return input values
M.assert = M.assert_eval_to_true

--- Alias for @{assert_not}.
--
-- @param value
-- @string[opt] message
function M.assert_eval_to_false(value, message)
    if value and value ~= nil then
        failure("expected: false or nil, actual: " ..prettystr(value), message, 2)
    end
end

--- Check that value is falsy.
--
-- @function assert_not
-- @param value
-- @string[opt] message
M.assert_not = M.assert_eval_to_false

--- Check value's type.
--
-- @string value
-- @string expected_type
-- @string[opt] message
-- @int[opt] level
function M.assert_type(value, expected_type, message, level)
    if type(value) ~= expected_type then
        fail_fmt((level or 1) + 1, message, 'expected: a %s value, actual: type %s, value %s',
            expected_type, type(value), prettystr_pairs(value))
    end
end

--- Check that values are the same.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_is(actual, expected, message)
    if actual ~= expected or type(actual) ~= type(expected) then
        expected, actual = prettystr_pairs(expected, actual, '\n', '')
        fail_fmt(2, message, 'expected and actual object should not be different\nExpected: %s\nReceived: %s',
                 expected, actual)
    end
end

--- Check that values are not the same.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_is_not(actual, expected, message)
    if actual == expected and type(actual) == type(expected) then
        fail_fmt(2, message, 'expected and actual object should be different: %s',
                 prettystr_pairs(expected))
    end
end

---
-- @param value
-- @string[opt] message
function M.assert_nan(value, message)
    if type(value) ~= "number" or value == value then
        failure("expected: NaN, actual: " ..prettystr(value), message, 2)
    end
end

---
-- @param value
-- @string[opt] message
function M.assert_not_nan(value, message)
    if type(value) == "number" and value ~= value then
        failure("expected: not NaN, actual: NaN", message, 2)
    end
end

function M.assert_inf(value, message)
    if type(value) ~= "number" or math.abs(value) ~= math.huge then
        failure("expected: #Inf, actual: " ..prettystr(value), message, 2)
    end
end

function M.assert_plus_inf(value, message)
    if type(value) ~= "number" or value ~= math.huge then
        failure("expected: #Inf, actual: " ..prettystr(value), message, 2)
    end
end

function M.assert_minus_inf(value, message)
    if type(value) ~= "number" or value ~= -math.huge then
        failure("expected: -#Inf, actual: " ..prettystr(value), message, 2)
    end
end

function M.assert_not_plus_inf(value, message)
    if type(value) == "number" and value == math.huge then
        failure("expected: not #Inf, actual: #Inf", message, 2)
    end
end

function M.assert_not_minus_inf(value, message)
    if type(value) == "number" and value == -math.huge then
        failure("expected: not -#Inf, actual: -#Inf", message, 2)
    end
end

function M.assert_not_inf(value, message)
    if type(value) == "number" and math.abs(value) == math.huge then
        failure("expected: not infinity, actual: " .. prettystr(value), message, 2)
    end
end

function M.assert_plus_zero(value, message)
    if type(value) ~= 'number' or value ~= 0 then
        failure("expected: +0.0, actual: " ..prettystr(value), message, 2)
    else if (1/value == -math.huge) then
            -- more precise error diagnosis
            failure("expected: +0.0, actual: -0.0", message, 2)
        else if (1/value ~= math.huge) then
                -- strange, case should have already been covered
                failure("expected: +0.0, actual: " ..prettystr(value), message, 2)
            end
        end
    end
end

function M.assert_minus_zero(value, message)
    if type(value) ~= 'number' or value ~= 0 then
        failure("expected: -0.0, actual: " ..prettystr(value), message, 2)
    else if (1/value == math.huge) then
            -- more precise error diagnosis
            failure("expected: -0.0, actual: +0.0", message, 2)
        else if (1/value ~= -math.huge) then
                -- strange, case should have already been covered
                failure("expected: -0.0, actual: " ..prettystr(value), message, 2)
            end
        end
    end
end

function M.assert_not_plus_zero(value, message)
    if type(value) == 'number' and (1/value == math.huge) then
        failure("expected: not +0.0, actual: +0.0", message, 2)
    end
end

function M.assert_not_minus_zero(value, message)
    if type(value) == 'number' and (1/value == -math.huge) then
        failure("expected: not -0.0, actual: -0.0", message, 2)
    end
end

return M
