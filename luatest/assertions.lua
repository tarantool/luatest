--- Module with assertion methods.
-- These methods are available in the root luatest module.
--
-- @submodule luatest

local math = require('math')

local comparator = require('luatest.comparator')
local mismatch_formatter = require('luatest.mismatch_formatter')
local pp = require('luatest.pp')
local utils = require('luatest.utils')

local prettystr = pp.tostring
local prettystr_pairs = pp.tostring_pair

local M = {}

-- private exported functions (for testing)
M.private = {}

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

--- Check that calling fn raises an error.
--
-- @func fn
-- @param ... arguments for function
function M.assert_error(fn, ...)
    local ok, err = pcall(fn, ...)
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
    utils.luatest_error('skip', message, 2)
end

--- Skip a running test if condition is met.
--
-- @param condition
-- @string message
function M.skip_if(condition, message)
    if condition and condition ~= nil then
        utils.luatest_error('skip', message, 2)
    end
end

function M.run_only_if(condition, message)
    -- continue a running test if condition is met, else skip it
    if not (condition and condition ~= nil) then
        utils.luatest_error('skip', prettystr(message), 2)
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

--- Check that two values are equal.
-- Tables are compared by value.
--
-- @param actual
-- @param expected
-- @string[opt] message
-- @bool[opt] deep_analysis print diff.
function M.assert_equals(actual, expected, message, deep_analysis)
    if not comparator.equals(actual, expected) then
        failure(M.private.error_msg_equality(actual, expected, deep_analysis), message, 2)
    end
end

---
-- @number actual
-- @number expected
-- @number margin
function M.almost_equals(actual, expected, margin)
    if not tonumber(actual) or not tonumber(expected) or not tonumber(margin) then
        fail_fmt(2, 'almost_equals: must supply only number arguments.\nArguments supplied: %s, %s, %s',
            prettystr(actual), prettystr(expected), prettystr(margin))
    end
    if margin < 0 then
        failure('almost_equals: margin must not be negative, current value is ' .. margin, 2)
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

--- Check that two values are not equal.
-- Tables are compared by value.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_not_equals(actual, expected, message)
    if comparator.equals(actual, expected) then
        fail_fmt(2, message, 'Received unexpected value: %s', prettystr(actual))
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

--- Checks equality of tables regardless of the order of elements.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_items_equals(actual, expected, message)
    if comparator.is_subset(actual, expected) ~= 0 then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, message, 'Content of the tables are not identical:\nExpected: %s\nActual: %s',
                 expected, actual)
    end
end

--- Checks that actual includes all items of expected.
--
-- @param actual
-- @param expected
-- @string[opt] message
function M.assert_items_include(actual, expected, message)
    if not comparator.is_subset(expected, actual) then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, message, 'Expected all elements from: %s\nTo be present in: %s', expected, actual)
    end
end

local function table_covers(actual, expected)
    if type(actual) ~= 'table' or type(expected) ~= 'table' then
        failure('Argument 1 and 2 must be tables', 3)
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

local function _assert_error_msg_equals(stripFileAndLine, expectedMsg, func, ...)
    local no_error, error_msg = pcall(func, ...)
    if no_error then
        failure('No error generated when calling function but expected error: ' .. prettystr(expectedMsg), nil, 3)
    end
    if type(expectedMsg) == "string" and type(error_msg) ~= "string" then
        -- table are converted to string automatically
        error_msg = tostring(error_msg)
    end
    local differ = false
    if stripFileAndLine then
        if error_msg:gsub("^.+:%d+: ", "") ~= expectedMsg then
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
    local no_error, error_msg = pcall(fn, ...)
    if no_error then
        failure('No error generated when calling function but expected error containing: ' ..
            prettystr(expected_partial), nil, 2)
    end
    if type(error_msg) ~= "string" then
        error_msg = tostring(error_msg)
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
    local no_error, error_msg = pcall(fn, ...)
    if no_error then
        failure('No error generated when calling function but expected error matching: "' .. pattern .. '"', nil, 2)
    end
    if type(error_msg) ~= "string" then
        error_msg = tostring(error_msg)
    end
    if not str_match(error_msg, pattern) then
        pattern, error_msg = prettystr_pairs(pattern, error_msg)
        fail_fmt(2, nil, 'Error message does not match pattern: %s\nError message received: %s\n', pattern, error_msg)
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
