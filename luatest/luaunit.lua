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

--[[ EPS is meant to help with Lua's floating point math in simple corner
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

----------------------------------------------------------------
--
--                 general utility functions
--
----------------------------------------------------------------

local function str_match(s, pattern, start, final )
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

local function fail_fmt(level, extra_msg_or_nil, ...)
     -- failure with printf-style formatted message and given error level
    failure(string.format(...), extra_msg_or_nil, (level or 1) + 1)
end
M.private.fail_fmt = fail_fmt

----------------------------------------------------------------
--
--                     assertions
--
----------------------------------------------------------------

local function error_msg_equality(actual, expected, doDeepAnalysis)
    if type(expected) == 'string' or type(expected) == 'table' then
        local strExpected, strActual = prettystr_pairs(expected, actual)
        local result = string.format("expected: %s\nactual: %s", strExpected, strActual)

        -- extend with mismatch analysis if possible:
        local success, mismatchResult = mismatch_formatter.format(actual, expected, doDeepAnalysis)
        if success then
            result = table.concat( { result, mismatchResult }, '\n' )
        end
        return result
    end
    return string.format("expected: %s, actual: %s",
                         prettystr(expected), prettystr(actual))
end
M.private.error_msg_equality = error_msg_equality

function M.assert_error(f, ...)
    -- assert that calling f with the arguments will raise an error
    -- example: assert_error( f, 1, 2 ) => f(1,2) should generate an error
    local ok, err = pcall( f, ... )
    if ok then
        failure( "Expected an error when calling function but no error generated", nil, 2 )
    end
    return err
end

function M.fail( msg )
    -- stops a test due to a failure
    failure( msg, nil, 2 )
end

function M.fail_if( cond, msg )
    -- Fails a test with "msg" if condition is true
    if cond and cond ~= nil then
        failure( msg, nil, 2 )
    end
end

function M.skip(msg)
    -- skip a running test
    utils.luatest_error('skip', msg, 2)
end

function M.skip_if( cond, msg )
    -- skip a running test if condition is met
    if cond and cond ~= nil then
        utils.luatest_error('skip', msg, 2)
    end
end

function M.run_only_if( cond, msg )
    -- continue a running test if condition is met, else skip it
    if not (cond and cond ~= nil) then
        utils.luatest_error('skip', prettystr(msg), 2)
    end
end

function M.success()
    -- stops a test with a success
    utils.luatest_error('success', 2)
end

function M.success_if( cond )
    -- stops a test with a success if condition is met
    if cond and cond ~= nil then
        utils.luatest_error('success', 2)
    end
end


------------------------------------------------------------------
--                  Equality assertions
------------------------------------------------------------------

function M.assert_equals(actual, expected, extra_msg_or_nil, doDeepAnalysis)
    if not comparator.equals(actual, expected) then
        failure(M.private.error_msg_equality(actual, expected, doDeepAnalysis), extra_msg_or_nil, 2)
    end
end

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

function M.assert_almost_equals(actual, expected, margin, extra_msg_or_nil)
    -- check that two floats are close by margin
    margin = margin or M.EPS
    if not M.almost_equals(actual, expected, margin) then
        local delta = math.abs(tonumber(actual - expected))
        fail_fmt(2, extra_msg_or_nil, 'Values are not almost equal\n' ..
                    'Actual: %s, expected: %s, delta %s above margin of %s',
                    actual, expected, delta, margin)
    end
end

function M.assert_not_equals(actual, expected, extra_msg_or_nil)
    if comparator.equals(actual, expected) then
        fail_fmt(2, extra_msg_or_nil, 'Received unexpected value: %s', prettystr(actual))
    end
end

function M.assert_not_almost_equals(actual, expected, margin, extra_msg_or_nil)
    -- check that two floats are not close by margin
    margin = margin or M.EPS
    if M.almost_equals(actual, expected, margin) then
        local delta = math.abs(actual - expected)
        fail_fmt(2, extra_msg_or_nil, 'Values are almost equal\nActual: %s, expected: %s' ..
                    ', delta %s below margin of %s',
                    actual, expected, delta, margin)
    end
end

function M.assert_items_equals(actual, expected, extra_msg_or_nil)
    -- Checks equality of tables regardless of the order of elements.
    if comparator.is_subset(actual, expected) ~= 0 then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, extra_msg_or_nil, 'Content of the tables are not identical:\nExpected: %s\nActual: %s',
                 expected, actual)
    end
end

function M.assert_items_include(actual, expected, extra_msg_or_nil)
    if not comparator.is_subset(expected, actual) then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, extra_msg_or_nil, 'Expected all elements from: %s\nTo be present in: %s', expected, actual)
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

function M.assert_covers(actual, expected, message)
    if not table_covers(actual, expected) then
        local str_actual, str_expected = prettystr_pairs(actual, expected)
        failure(string.format('expected %s to cover %s', str_actual, str_expected), message, 2)
    end
end

function M.assert_not_covers(actual, expected, message)
    if table_covers(actual, expected) then
        local str_actual, str_expected = prettystr_pairs(actual, expected)
        failure(string.format('expected %s to not cover %s', str_actual, str_expected), message, 2)
    end
end

------------------------------------------------------------------
--                  String assertion
------------------------------------------------------------------

function M.assert_str_contains( str, sub, isPattern, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    -- assert( type(str) == 'string', 'Argument 1 of assert_str_contains() should be a string.' ) )
    -- assert( type(sub) == 'string', 'Argument 2 of assert_str_contains() should be a string.' ) )
    M.assert_type(str, 'string', nil, 2)
    M.assert_type(sub, 'string', nil, 2)

    if not string.find(str, sub, 1, not isPattern) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Could not find %s %s in string %s',
                 isPattern and 'pattern' or 'substring', sub, str)
    end
end

function M.assert_str_icontains( str, sub, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    M.assert_type(str, 'string', nil, 2)
    M.assert_type(sub, 'string', nil, 2)

    if not string.find(str:lower(), sub:lower(), 1, true) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Could not find (case insensitively) substring %s in string %s',
                 sub, str)
    end
end

function M.assert_not_str_contains( str, sub, isPattern, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    M.assert_type(str, 'string', nil, 2)
    M.assert_type(sub, 'string', nil, 2)

    if string.find(str, sub, 1, not isPattern) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Found unexpected %s %s in string %s',
                 isPattern and 'pattern' or 'substring', sub, str)
    end
end

function M.assert_not_str_icontains( str, sub, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    M.assert_type(str, 'string', nil, 2)
    M.assert_type(sub, 'string', nil, 2)

    if string.find(str:lower(), sub:lower(), 1, true) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Found (case insensitively) unexpected substring %s in string %s', sub, str)
    end
end

function M.assert_str_matches( str, pattern, start, final, extra_msg_or_nil )
    -- Verify a full match for the string
    M.assert_type(str, 'string', nil, 2)
    M.assert_type(pattern, 'string', nil, 2)

    if not str_match( str, pattern, start, final ) then
        pattern, str = prettystr_pairs(pattern, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Could not match pattern %s with string %s',
                 pattern, str)
    end
end

local function _assert_error_msg_equals( stripFileAndLine, expectedMsg, func, ... )
    local no_error, error_msg = pcall( func, ... )
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

function M.assert_error_msg_equals( expectedMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assert_error( f, 1, 2 ) => f(1,2) should generate an error
    _assert_error_msg_equals(false, expectedMsg, func, ...)
end

function M.assert_error_msg_content_equals(expectedMsg, func, ...)
     _assert_error_msg_equals(true, expectedMsg, func, ...)
end

function M.assert_error_msg_contains( partialMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assert_error( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( func, ... )
    if no_error then
        failure( 'No error generated when calling function but expected error containing: '..prettystr(partialMsg),
            nil, 2 )
    end
    if type(error_msg) ~= "string" then
        error_msg = tostring(error_msg)
    end
    if not string.find( error_msg, partialMsg, nil, true ) then
        error_msg, partialMsg = prettystr_pairs(error_msg, partialMsg)
        fail_fmt(2, nil, 'Error message does not contain: %s\nError message received: %s\n',
                 partialMsg, error_msg)
    end
end

function M.assert_error_msg_matches( expectedMsg, func, ... )
    -- assert that calling f with the arguments will raise an error
    -- example: assert_error( f, 1, 2 ) => f(1,2) should generate an error
    local no_error, error_msg = pcall( func, ... )
    if no_error then
        failure( 'No error generated when calling function but expected error matching: "'..expectedMsg..'"', nil, 2 )
    end
    if type(error_msg) ~= "string" then
        error_msg = tostring(error_msg)
    end
    if not str_match( error_msg, expectedMsg ) then
        expectedMsg, error_msg = prettystr_pairs(expectedMsg, error_msg)
        fail_fmt(2, nil, 'Error message does not match pattern: %s\nError message received: %s\n',
                 expectedMsg, error_msg)
    end
end

------------------------------------------------------------------
--              Type assertions
------------------------------------------------------------------

function M.assert_eval_to_true(value, extra_msg_or_nil, ...)
    if not value or value == nil then
        failure("expected: a value evaluating to true, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
    return value, extra_msg_or_nil, ...
end

function M.assert_eval_to_false(value, extra_msg_or_nil)
    if value and value ~= nil then
        failure("expected: false or nil, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_type(value, type_expected, extra_msg_or_nil, level)
    if type(value) ~= type_expected then
        fail_fmt((level or 1) + 1, extra_msg_or_nil, 'expected: a %s value, actual: type %s, value %s',
                 type_expected, type(value), prettystr_pairs(value))
    end
end

function M.assert_is(actual, expected, extra_msg_or_nil)
    if actual ~= expected or type(actual) ~= type(expected) then
        expected, actual = prettystr_pairs(expected, actual, '\n', '')
        fail_fmt(2, extra_msg_or_nil, 'expected and actual object should not be different\nExpected: %s\nReceived: %s',
                 expected, actual)
    end
end

function M.assert_is_not(actual, expected, extra_msg_or_nil)
    if actual == expected and type(actual) == type(expected) then
        fail_fmt(2, extra_msg_or_nil, 'expected and actual object should be different: %s',
                 prettystr_pairs(expected))
    end
end


------------------------------------------------------------------
--              Scientific assertions
------------------------------------------------------------------


function M.assert_nan(value, extra_msg_or_nil)
    if type(value) ~= "number" or value == value then
        failure("expected: NaN, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_not_nan(value, extra_msg_or_nil)
    if type(value) == "number" and value ~= value then
        failure("expected: not NaN, actual: NaN", extra_msg_or_nil, 2)
    end
end

function M.assert_inf(value, extra_msg_or_nil)
    if type(value) ~= "number" or math.abs(value) ~= math.huge then
        failure("expected: #Inf, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_plus_inf(value, extra_msg_or_nil)
    if type(value) ~= "number" or value ~= math.huge then
        failure("expected: #Inf, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_minus_inf(value, extra_msg_or_nil)
    if type(value) ~= "number" or value ~= -math.huge then
        failure("expected: -#Inf, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_not_plus_inf(value, extra_msg_or_nil)
    if type(value) == "number" and value == math.huge then
        failure("expected: not #Inf, actual: #Inf", extra_msg_or_nil, 2)
    end
end

function M.assert_not_minus_inf(value, extra_msg_or_nil)
    if type(value) == "number" and value == -math.huge then
        failure("expected: not -#Inf, actual: -#Inf", extra_msg_or_nil, 2)
    end
end

function M.assert_not_inf(value, extra_msg_or_nil)
    if type(value) == "number" and math.abs(value) == math.huge then
        failure("expected: not infinity, actual: " .. prettystr(value), extra_msg_or_nil, 2)
    end
end

function M.assert_plus_zero(value, extra_msg_or_nil)
    if type(value) ~= 'number' or value ~= 0 then
        failure("expected: +0.0, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    else if (1/value == -math.huge) then
            -- more precise error diagnosis
            failure("expected: +0.0, actual: -0.0", extra_msg_or_nil, 2)
        else if (1/value ~= math.huge) then
                -- strange, case should have already been covered
                failure("expected: +0.0, actual: " ..prettystr(value), extra_msg_or_nil, 2)
            end
        end
    end
end

function M.assert_minus_zero(value, extra_msg_or_nil)
    if type(value) ~= 'number' or value ~= 0 then
        failure("expected: -0.0, actual: " ..prettystr(value), extra_msg_or_nil, 2)
    else if (1/value == math.huge) then
            -- more precise error diagnosis
            failure("expected: -0.0, actual: +0.0", extra_msg_or_nil, 2)
        else if (1/value ~= -math.huge) then
                -- strange, case should have already been covered
                failure("expected: -0.0, actual: " ..prettystr(value), extra_msg_or_nil, 2)
            end
        end
    end
end

function M.assert_not_plus_zero(value, extra_msg_or_nil)
    if type(value) == 'number' and (1/value == math.huge) then
        failure("expected: not +0.0, actual: +0.0", extra_msg_or_nil, 2)
    end
end

function M.assert_not_minus_zero(value, extra_msg_or_nil)
    if type(value) == 'number' and (1/value == -math.huge) then
        failure("expected: not -0.0, actual: -0.0", extra_msg_or_nil, 2)
    end
end

return M
