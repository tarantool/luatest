local clock = require("clock")
require("math")

local Class = require('luatest.class')
local comparator = require('luatest.comparator')
local mismatch_formatter = require('luatest.mismatch_formatter')
local pp = require('luatest.pp')
local sorted_pairs = require('luatest.sorted_pairs')

local prettystr = pp.tostring
local prettystr_pairs = pp.tostring_pair

local M={}

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

-- set this to false to debug luaunit
M.STRIP_LUAUNIT_FROM_STACKTRACE = os.getenv('LUATEST_BACKTRACE') == nil

M.VERBOSITY = require('luatest.output.generic').VERBOSITY

M.USAGE=[[Usage: luatest [options] [files or dirs...] [testname1 [testname2] ... ]
Options:
  -h, --help:             Print this help
  --version:              Print version information
  -v, --verbose:          Increase verbosity
  -q, --quiet:            Set verbosity to minimum
  -c                      Disable capture
  -f, --fail-fast:        Stop on first failure or error
  --shuffle VALUE:        Set execution order:
                            - group[:seed] - shuffle tests within group
                            - all[:seed] - shuffle all tests
                            - none - sort tests within group by line number (default)
  --seed NUMBER:          Set seed value for shuffler
  -o, --output OUTPUT:    Set output type to OUTPUT
                          Possible values: text, tap, junit, nil
  -n, --name NAME:        For junit only, mandatory name of xml file
  -r, --repeat NUM:       Execute all tests NUM times, e.g. to trig the JIT
  -p, --pattern PATTERN:  Execute all test names matching the Lua PATTERN
                          May be repeated to include several patterns
                          Make sure you escape magic chars like +? with %
  -x, --exclude PATTERN:  Exclude all test names matching the Lua PATTERN
                          May be repeated to exclude several patterns
                          Make sure you escape magic chars like +? with %
  --coverage:             Use luacov to collect code coverage.
  test_name, ...:         Tests to run in the form of group_name or group_name.test_name
]]

----------------------------------------------------------------
--
--                 general utility functions
--
----------------------------------------------------------------

local function randomize_table( t )
    -- randomize the item orders of the table t
    for i = #t, 2, -1 do
        local j = math.random(i)
        if i ~= j then
            t[i], t[j] = t[j], t[i]
        end
    end
end
M.private.randomize_table = randomize_table

local function strsplit(delimiter, text)
-- Split text into a list consisting of the strings in text, separated
-- by strings matching delimiter (which may _NOT_ be a pattern).
-- Example: strsplit(", ", "Anna, Bob, Charlie, Dolores")
    if delimiter == "" or delimiter == nil then -- this would result in endless loops
        error("delimiter is nil or empty string!")
    end
    if text == nil then
        return nil
    end

    local list, pos, first, last = {}, 1
    while true do
        first, last = text:find(delimiter, pos, true)
        if first then -- found?
            table.insert(list, text:sub(pos, first - 1))
            pos = last + 1
        else
            table.insert(list, text:sub(pos))
            break
        end
    end
    return list
end
M.private.strsplit = strsplit

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

local function pattern_filter(patterns, expr)
    -- Run `expr` through the inclusion and exclusion rules defined in patterns
    -- and return true if expr shall be included, false for excluded.
    -- Inclusion pattern are defined as normal patterns, exclusions
    -- patterns start with `!` and are followed by a normal pattern

    -- result: nil = UNKNOWN (not matched yet), true = ACCEPT, false = REJECT
    -- default: true if no explicit "include" is found, set to false otherwise
    local default, result = true, nil

    if patterns ~= nil then
        for _, pattern in ipairs(patterns) do
            local exclude = pattern:sub(1,1) == '!'
            if exclude then
                pattern = pattern:sub(2)
            else
                -- at least one include pattern specified, a match is required
                default = false
            end
            -- print('pattern: ',pattern)
            -- print('exclude: ',exclude)
            -- print('default: ',default)

            if string.find(expr, pattern) then
                -- set result to false when excluding, true otherwise
                result = not exclude
            end
        end
    end

    if result ~= nil then
        return result
    end
    return default
end
M.private.pattern_filter = pattern_filter

local function is_luaunit_internal_line(s)
    -- return true if line of stack trace comes from inside luaunit
    return s:find('[/\\]luatest[/\\]') or s:find('bin[/\\]luatest')
end

local function strip_luaunit_trace(trace)
    local lines = strsplit('\n', trace)
    local result = {lines[1]} -- always keep 1st line
    local keep = true
    for i = 2, table.maxn(lines) do
        local line = lines[i]
        -- `[C]:` lines and `...` don't change context
        if not line:find('^%s+%[C%]:') and not line:find('^%s+%.%.%.') then
            keep = not is_luaunit_internal_line(line)
        end
        if keep then
            table.insert(result, line)
        end
    end
    return table.concat(result, '\n')
end
M.private.strip_luaunit_trace = strip_luaunit_trace

local function luaunit_error(status, message, level)
    local _
    _, message = pcall(error, message, (level or 1) + 2)
    error({class = 'LuaUnitError', status = status, message = message})
end

local function is_luaunit_error(err)
    return type(err) == 'table' and err.class == 'LuaUnitError'
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
    luaunit_error('fail', msg, (level or 1) + 1)
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
    luaunit_error('skip', msg, 2)
end

function M.skip_if( cond, msg )
    -- skip a running test if condition is met
    if cond and cond ~= nil then
        luaunit_error('skip', msg, 2)
    end
end

function M.run_only_if( cond, msg )
    -- continue a running test if condition is met, else skip it
    if not (cond and cond ~= nil) then
        luaunit_error('skip', prettystr(msg), 2)
    end
end

function M.success()
    -- stops a test with a success
    luaunit_error('success', 2)
end

function M.success_if( cond )
    -- stops a test with a success if condition is met
    if cond and cond ~= nil then
        luaunit_error('success', 2)
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

----------------------------------------------------------------
--
--                     class LuaUnit
--
----------------------------------------------------------------

M.LuaUnit = Class.new()

M.LuaUnit.mt.output = 'text'
M.LuaUnit.mt.verbosity = M.VERBOSITY.DEFAULT
M.LuaUnit.mt.shuffle = 'none'

    -----------------[[ Utility methods ]]---------------------

    -- Split `some.group.name.method` into `some.group.name` and `method`.
    -- Returns `nil, input` if input value does not have a dot.
    function M.LuaUnit.split_test_method_name(someName)
        local separator
        for i = #someName, 1, -1 do
            if someName:sub(i, i) == '.' then
                separator = i
                break
            end
        end
        if separator then
            return someName:sub(1, separator - 1), someName:sub(separator + 1)
        end
        return nil, someName
    end

    function M.LuaUnit.is_method_test_name( s )
        -- return true is the name matches the name of a test method
        -- default rule is that is starts with 'Test' or with 'test'
        return string.sub(s, 1, 4):lower() == 'test'
    end

    function M.LuaUnit.parse_cmd_line(args)
        local result = {}

        local arg_n = 0
        local function next_arg(optional)
            arg_n = arg_n + 1
            local arg = args and args[arg_n]
            if arg == nil and not optional then
                error('Missing argument after ' .. args[#args])
            end
            return arg
        end

        while true do
            local arg = next_arg(true)
            if arg == nil then
                break
            elseif arg == '--help' or arg == '-h' then
                result.help = true
            elseif arg == '--version' then
                result.version = true
            elseif arg == '--verbose' or arg == '-v' then
                result.verbosity = M.VERBOSITY.VERBOSE
            elseif arg == '--quiet' or arg == '-q' then
                result.verbosity = M.VERBOSITY.QUIET
            elseif arg == '--fail-fast' or arg == '-f' then
                result.fail_fast = true
            elseif arg == '--shuffle' or arg == '-s' then
                local seed
                result.shuffle, seed = unpack(next_arg():split(':'))
                if seed then
                    result.seed = tonumber(seed) or error('Invalid seed value')
                end
            elseif arg == '--seed' then
                result.seed = tonumber(next_arg()) or error('Invalid seed value')
            elseif arg == '--output' or arg == '-o' then
                result.output = next_arg()
            elseif arg == '--name' or arg == '-n' then
                result.output_file_name = next_arg()
            elseif arg == '--repeat' or arg == '-r' then
                result.exe_repeat = tonumber(next_arg()) or error('Invalid value for -r option. Integer required.')
            elseif arg == '--pattern' or arg == '-p' then
                result.tests_pattern = result.tests_pattern or {}
                table.insert(result.tests_pattern, next_arg())
            elseif arg == '--exclude' or arg == '-x' then
                result.tests_pattern = result.tests_pattern or {}
                table.insert(result.tests_pattern, '!' .. next_arg())
            elseif arg == '-b' then
                result.full_backtrace = true
            elseif arg == '-c' then
                result.enable_capture = false
            elseif arg == '--coverage' then
                result.coverage_report = true
            elseif arg:sub(1,1) == '-' then
                error('Unknown option: ' .. arg)
            elseif arg:find('/') then
                -- If argument contains / then it's treated as file path.
                -- This assumption to support luaunit's test names along with file paths.
                result.paths = result.paths or {}
                table.insert(result.paths, arg)
            else
                result.test_names = result.test_names or {}
                table.insert(result.test_names, arg)
            end
        end

        return result
    end

----------------------------------------------------------------
--                     class NodeStatus
----------------------------------------------------------------

    local NodeStatus = Class.new()

    -- default constructor, test are PASS by default
    function NodeStatus.mt:initialize()
        self.status = 'success'
    end

    function NodeStatus.mt:update_status(status, message, trace)
        self.status = status
        self.message = message
        self.trace = trace
    end

    function NodeStatus.mt:is(status)
        return self.status == status
    end

    --------------[[ Output methods ]]-------------------------

    function M.LuaUnit.mt:start_suite(selected_count, not_selected_count)
        self.result = {
            selected_count = selected_count,
            not_selected_count = not_selected_count,
            start_time = clock.time(),
            tests = {
                all = {},
                success = {},
                fail = {},
                error = {},
                skip = {},
            },
        }
        self.output.result = self.result
        self.output:start_suite()
    end

    function M.LuaUnit.mt:start_group(group)
        self.output:start_group(group)
    end

    function M.LuaUnit.mt:start_test(test)
        test.serial_number = #self.result.tests.all + 1
        test.start_time = clock.time()
        table.insert(self.result.tests.all, test)
        self.output:start_test(test)
    end

    function M.LuaUnit.mt:update_status(node, err)
        -- "err" is expected to be a table / result from protected_call()
        if err.status == 'success' then
            return
        -- if the node is already in failure/error, just don't report the new error (see above)
        elseif not node:is('success') then
            return
        elseif err.status == 'fail' or err.status == 'error' or err.status == 'skip' then
            node:update_status(err.status, err.message, err.trace)
        else
            error('No such status: ' .. prettystr(err.status))
        end
        self.output:update_status(node)
    end

    function M.LuaUnit.mt:end_test(node)
        node.duration = clock.time() - node.start_time
        node.start_time = nil
        self.output:end_test(node)

        if node:is('error') or node:is('fail') then
            self.result.aborted = self.fail_fast
        elseif not node:is('success') and not node:is('skip') then
            error('No such node status: ' .. prettystr(node.status))
        end
    end

    function M.LuaUnit.mt:end_group(group)
        self.output:end_group(group)
    end

    function M.LuaUnit.mt:end_suite()
        if self.result.duration then
            error('Suite was already ended' )
        end
        self.result.duration = clock.time() - self.result.start_time
        for _, test in pairs(self.result.tests.all) do
            table.insert(self.result.tests[test.status], test)
        end
        self.result.failures_count = #self.result.tests.fail + #self.result.tests.error
        self.output:end_suite()
    end

    --------------[[ Runner ]]-----------------

    function M.LuaUnit.mt:protected_call(instance, method, pretty_name) -- luacheck: no unused
        local _, err = xpcall(function()
            method(instance)
            return {status = 'success'}
        end, function(e)
            -- transform error into a table, adding the traceback information
            local trace = debug.traceback('', 3):sub(2)
            if is_luaunit_error(e) then
                return {status = e.status, message = e.message, trace = trace}
            else
                return {status = 'error', message = e, trace = trace}
            end
        end)

        if type(err.message) ~= 'string' then
            err.message = prettystr(err.message)
        end

        if err.status == 'success' or err.status == 'skip' then
            err.trace = nil
            return err
        end

        -- reformat / improve the stack trace
        if pretty_name then -- we do have the real method name
            err.trace = err.trace:gsub("in (%a+) 'method'", "in %1 '" .. pretty_name .. "'")
        end
        if M.STRIP_LUAUNIT_FROM_STACKTRACE then
            err.trace = strip_luaunit_trace(err.trace)
        end

        return err -- return the error "object" (table)
    end

    function M.LuaUnit.mt:invoke_test_function(test, iteration)
        local err = self:protected_call(test.group, test.method, test.name)
        if iteration > 1 and err.status ~= 'success' then
            err.message = tostring(err.message) .. '\nIteration ' .. self.test_iteration
        end
        self:update_status(test, err)
    end

    function M.LuaUnit.mt:run_test(test)
        self:start_test(test)
        for iteration = 1, self.exe_repeat or 1 do
            if not test:is('success') then
                break
            end
            self:invoke_test_function(test, iteration)
        end
        self:end_test(test)
    end

    function M.LuaUnit.mt:run_tests(tests_list)
        -- Make seed for ordering not affect other random numbers.
        math.randomseed(os.time())
        local last_group
        for _, test in ipairs(tests_list) do
            if last_group ~= test.group then
                if last_group then
                    self:end_group(last_group)
                end
                self:start_group(test.group)
                last_group = test.group
            end
            self:run_test(test)
            if self.result.aborted then
                break
            end
        end
        if last_group then
            self:end_group(last_group)
        end
    end

    function M.LuaUnit.build_test(group, method_name)
        local name = group.name .. '.' .. method_name
        local method = assert(group[method_name], 'Could not find method ' .. name)
        assert(type(method) == 'function', name .. ' is not a function')
        return NodeStatus:from({
            name = name,
            group = group,
            method_name = method_name,
            method = method,
            line = debug.getinfo(method).linedefined or 0,
        })
    end

    -- Exrtact all test methods from group.
    function M.LuaUnit.mt:expand_group(group)
        local result = {}
        for method_name in sorted_pairs(group) do
            if M.LuaUnit.is_method_test_name(method_name) then
                table.insert(result, self.class.build_test(group, method_name))
            end
        end
        return result
    end

    function M.LuaUnit.mt:find_test(name)
        local group_name, method_name = M.LuaUnit.split_test_method_name(name)
        assert(group_name and method_name, 'Invalid test name: ' .. name)
        local group = assert(self.groups[group_name], 'Group not found: ' .. group_name)
        return self.class.build_test(group, method_name)
    end

    function M.LuaUnit.filter_tests(tests_list, patterns)
        local included, excluded = {}, {}
        for _, test in ipairs(tests_list) do
            if  pattern_filter(patterns, test.name) then
                table.insert(included, test)
            else
                table.insert(excluded, test)
            end
        end
        return included, excluded
    end

    function M.LuaUnit.mt:find_tests()
        -- Set seed to ordering.
        if self.seed then
            math.randomseed(self.seed)
        end

        if not self.test_names then
            self.test_names = {}
            for name in sorted_pairs(self.groups) do
                table.insert(self.test_names, name)
            end
        end

        local result = {}
        for _, name in ipairs(self.test_names) do
            local group = self.groups[name]
            if group then
                local fns = self:expand_group(group)
                if self.shuffle == 'group' then
                    randomize_table(fns)
                elseif self.shuffle == 'none' then
                    table.sort(fns, function(a, b) return a.line < b.line end)
                end
                for _, x in pairs(fns) do
                    table.insert(result, x)
                end
            else
                table.insert(result, self:find_test(name))
            end
        end

        if self.shuffle == 'all' then
            randomize_table(result)
        end

        return result
    end

    -- Available options are:
    --
    --   - verbosity
    --   - fail_fast
    --   - output_file_name
    --   - exe_repeat
    --   - tests_pattern
    --   - shuffle
    --   - seed
    function M.LuaUnit.run(options)
        return M.LuaUnit:from(options):run_suite()
    end

    function M.LuaUnit.mt:initialize()
        if self.shuffle == 'group' or self.shuffle == 'all' then
            if not self.seed then
                math.randomseed(os.time())
                self.seed = math.random(1000, 10000)
            end
        elseif self.shuffle ~= 'none' then
            error('Invalid shuffle value')
        end

        if self.output then
            self.output = self.output:lower()
            if self.output == 'junit' and self.output_file_name == nil then
                error('With junit output, a filename must be supplied with -n or --name')
            end
            local ok, output_type = pcall(require, 'luatest.output.' .. self.output)
            assert(ok, 'Can not load output module: ' .. self.output)
            self.output = output_type:new(self)
        end
    end

    function M.LuaUnit.mt:run_suite()
        local tests = self:find_tests()
        local filtered_list, filtered_out_list = self.class.filter_tests(tests, self.tests_pattern)
        self:start_suite(#filtered_list, #filtered_out_list)
        self:run_tests(filtered_list)
        self:end_suite()
        if self.result.aborted then
            print("Test suite ABORTED because of --fail-fast option")
            return -2
        end
        return self.result.failures_count
    end
-- class LuaUnit

function M.defaults(options)
    for k, v in pairs(options) do
        M.LuaUnit[k] = v
    end
end

return M
