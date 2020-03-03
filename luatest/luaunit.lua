local clock = require("clock")
require("math")

local Class = require('luatest.class')

local M={}

-- private exported functions (for testing)
M.private = {}

M.VERSION = require('luatest.VERSION')

M.PRINT_TABLE_REF_IN_ERROR_MSG = false
M.TABLE_EQUALS_KEYBYCONTENT = true
M.LINE_LENGTH = 80
M.LIST_DIFF_ANALYSIS_THRESHOLD  = 10    -- display deep analysis for more than 10 items

M.groups = {}

local function find_closest_matching_frame(pattern)
    local level = 2
    while true do
        local info = debug.getinfo(level, 'S')
        if not info then
            return
        end
        local source = info.source
        if source:match(pattern) then
            return info
        end
        level = level + 1
    end
end

--- Define named test group.
M.group = function(name)
    if not name then
        local pattern = '.*/test/(.+)_test%.lua'
        local info = assert(
            find_closest_matching_frame(pattern),
            "Can't derive test name from file name " ..
            "(it should match pattern '.*/test/.*_test.lua')"
        )
        local test_filename = info.source:match(pattern)
        name = test_filename:gsub('/', '.')
    end
    if M.groups[name] then
        error('Test group already exists: ' .. name ..
            '. To modify existing group use `luatest.groups[name]`.')
    end
    if name:find('/') then
        error('Group name must not contain `/`: ' .. name)
    end
    M.groups[name] = {name = name}
    return M.groups[name]
end

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
M.FORCE_DEEP_ANALYSIS   = true
M.DISABLE_DEEP_ANALYSIS = false

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

-- Replace LuaUnit's calls to os exit to exit gracefully from luatest runner.
local function os_exit(code)
    error({type = 'LUAUNIT_EXIT', code = code})
end

local crossTypeOrdering = {
    number = 1, boolean = 2, string = 3, table = 4, other = 5
}
local crossTypeComparison = {
    number = function(a, b) return a < b end,
    string = function(a, b) return a < b end,
    other = function(a, b) return tostring(a) < tostring(b) end,
}

local function cross_type_sort(a, b)
    local type_a, type_b = type(a), type(b)
    if type_a == type_b then
        local func = crossTypeComparison[type_a] or crossTypeComparison.other
        return func(a, b)
    end
    type_a = crossTypeOrdering[type_a] or crossTypeOrdering.other
    type_b = crossTypeOrdering[type_b] or crossTypeOrdering.other
    return type_a < type_b
end

local function __gen_sorted_index( t )
    -- Returns a sequence consisting of t's keys, sorted.
    local sortedIndex = {}

    for key,_ in pairs(t) do
        table.insert(sortedIndex, key)
    end

    table.sort(sortedIndex, cross_type_sort)
    return sortedIndex
end
M.private.__gen_sorted_index = __gen_sorted_index

local function sorted_next(state, control)
    -- Equivalent of the next() function of table iteration, but returns the
    -- keys in sorted order (see __gen_sorted_index and cross_type_sort).
    -- The state is a temporary variable during iteration and contains the
    -- sorted key table (state.sortedIdx). It also stores the last index (into
    -- the keys) used by the iteration, to find the next one quickly.
    local key

    --print("sorted_next: control = "..tostring(control) )
    if control == nil then
        -- start of iteration
        state.count = #state.sortedIdx
        state.lastIdx = 1
        key = state.sortedIdx[1]
        return key, state.t[key]
    end

    -- normally, we expect the control variable to match the last key used
    if control ~= state.sortedIdx[state.lastIdx] then
        -- strange, we have to find the next value by ourselves
        -- the key table is sorted in cross_type_sort() order! -> use bisection
        local lower, upper = 1, state.count
        repeat
            state.lastIdx = math.modf((lower + upper) / 2)
            key = state.sortedIdx[state.lastIdx]
            if key == control then
                break -- key found (and thus prev index)
            end
            if cross_type_sort(key, control) then
                -- key < control, continue search "right" (towards upper bound)
                lower = state.lastIdx + 1
            else
                -- key > control, continue search "left" (towards lower bound)
                upper = state.lastIdx - 1
            end
        until lower > upper
        if lower > upper then -- only true if the key wasn't found, ...
            state.lastIdx = state.count -- ... so ensure no match in code below
        end
    end

    -- proceed by retrieving the next value (or nil) from the sorted keys
    state.lastIdx = state.lastIdx + 1
    key = state.sortedIdx[state.lastIdx]
    if key then
        return key, state.t[key]
    end

    -- getting here means returning `nil`, which will end the iteration
end

local function sorted_pairs(tbl)
    -- Equivalent of the pairs() function on tables. Allows to iterate in
    -- sorted order. As required by "generic for" loops, this will return the
    -- iterator (function), an "invariant state", and the initial control value.
    -- (see http://www.lua.org/pil/7.2.html)
    return sorted_next, {t = tbl, sortedIdx = __gen_sorted_index(tbl)}, nil
end
M.private.sorted_pairs = sorted_pairs

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

local function has_new_line( s )
    -- return true if s has a newline
    return (string.find(s, '\n', 1, true) ~= nil)
end
M.private.has_new_line = has_new_line

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


local function prettystr_sub(v, indentLevel, printTableRefs, recursionTable )
    local type_v = type(v)
    if "string" == type_v  then
        return string.format("%q", v)
    elseif "table" == type_v then
        return M.private._table_tostring(v, indentLevel, printTableRefs, recursionTable)
    elseif "number" == type_v then
        -- eliminate differences in formatting between various Lua versions
        if v ~= v then
            return "#NaN" -- "not a number"
        end
        if v == math.huge then
            return "#Inf" -- "infinite"
        end
        if v == -math.huge then
            return "-#Inf"
        end
        if rawget(math, 'tointeger') then -- Lua 5.3
            local i = rawget(math, 'tointeger')(v)
            if i then
                return tostring(i)
            end
        end
    end

    return tostring(v)
end

local function prettystr( v )
    --[[ Pretty string conversion, to display the full content of a variable of any type.

    * string are enclosed with " by default, or with ' if string contains a "
    * tables are expanded to show their full content, with indentation in case of nested tables
    ]]--
    local recursionTable = {}
    local s = prettystr_sub(v, 1, M.PRINT_TABLE_REF_IN_ERROR_MSG, recursionTable)
    if recursionTable.recursionDetected and not M.PRINT_TABLE_REF_IN_ERROR_MSG then
        -- some table contain recursive references,
        -- so we must recompute the value by including all table references
        -- else the result looks like crap
        recursionTable = {}
        s = prettystr_sub(v, 1, true, recursionTable)
    end
    return s
end
M.prettystr = prettystr

local function try_mismatch_formatting( table_a, table_b, doDeepAnalysis )
    --[[
    Prepares a nice error message when comparing tables, performing a deeper
    analysis.

    Arguments:
    * table_a, table_b: tables to be compared
    * doDeepAnalysis:
        M.DEFAULT_DEEP_ANALYSIS: (the default if not specified) perform deep analysis
                                    only for big lists and big dictionnaries
        M.FORCE_DEEP_ANALYSIS  : always perform deep analysis
        M.DISABLE_DEEP_ANALYSIS: never perform deep analysis

    Returns: {success, result}
    * success: false if deep analysis could not be performed
               in this case, just use standard assertion message
    * result: if success is true, a multi-line string with deep analysis of the two lists
    ]]

    -- check if table_a & table_b are suitable for deep analysis
    if type(table_a) ~= 'table' or type(table_b) ~= 'table' then
        return false
    end

    if doDeepAnalysis == M.DISABLE_DEEP_ANALYSIS then
        return false
    end

    local len_a, len_b, isPureList = #table_a, #table_b, true

    for k1 in pairs(table_a) do
        if type(k1) ~= 'number' or k1 > len_a then
            -- this table a mapping
            isPureList = false
            break
        end
    end

    if isPureList then
        for k2 in pairs(table_b) do
            if type(k2) ~= 'number' or k2 > len_b then
                -- this table a mapping
                isPureList = false
                break
            end
        end
    end

    if isPureList and math.min(len_a, len_b) < M.LIST_DIFF_ANALYSIS_THRESHOLD then
        if not (doDeepAnalysis == M.FORCE_DEEP_ANALYSIS) then
            return false
        end
    end

    if isPureList then
        return M.private.mismatch_formatting_pure_list( table_a, table_b )
    else
        return false
    end
end
M.private.try_mismatch_formatting = try_mismatch_formatting


local function extend_with_str_fmt( res, ... )
    table.insert( res, string.format( ... ) )
end

local function mismatch_formatting_pure_list( table_a, table_b )
    --[[
    Prepares a nice error message when comparing tables which are lists, performing a deeper
    analysis.

    Returns: {success, result}
    * success: false if deep analysis could not be performed
               in this case, just use standard assertion message
    * result: if success is true, a multi-line string with deep analysis of the two lists
    ]]
    local result = {}

    local len_a, len_b, refa, refb = #table_a, #table_b, '', ''
    if M.PRINT_TABLE_REF_IN_ERROR_MSG then
        refa, refb = string.format( '<%s> ', tostring(table_a)), string.format('<%s> ', tostring(table_b) )
    end
    local longest, shortest = math.max(len_a, len_b), math.min(len_a, len_b)
    local deltalv  = longest - shortest

    local commonUntil = shortest
    for i = 1, shortest do
        if not M.private.equals(table_a[i], table_b[i]) then
            commonUntil = i - 1
            break
        end
    end

    local commonBackTo = shortest - 1
    for i = 0, shortest - 1 do
        if not M.private.equals(table_a[len_a-i], table_b[len_b-i]) then
            commonBackTo = i - 1
            break
        end
    end


    table.insert( result, 'List difference analysis:' )
    if len_a == len_b then
        -- TODO: handle expected/actual naming
        extend_with_str_fmt(result, '* lists %sA (actual) and %sB (expected) have the same size', refa, refb)
    else
        extend_with_str_fmt(result,
            '* list sizes differ: list %sA (actual) has %d items, list %sB (expected) has %d items',
            refa, len_a, refb, len_b
        )
    end

    extend_with_str_fmt( result, '* lists A and B start differing at index %d', commonUntil+1 )
    if commonBackTo >= 0 then
        if deltalv > 0 then
            extend_with_str_fmt(result, '* lists A and B are equal again from index %d for A, %d for B',
                len_a-commonBackTo, len_b-commonBackTo)
        else
            extend_with_str_fmt( result, '* lists A and B are equal again from index %d', len_a-commonBackTo )
        end
    end

    local function insert_ab_value(ai, bi)
        bi = bi or ai
        if M.private.equals(table_a[ai], table_b[bi]) then
            return extend_with_str_fmt( result, '  = A[%d], B[%d]: %s', ai, bi, prettystr(table_a[ai]) )
        else
            extend_with_str_fmt( result, '  - A[%d]: %s', ai, prettystr(table_a[ai]))
            extend_with_str_fmt( result, '  + B[%d]: %s', bi, prettystr(table_b[bi]))
        end
    end

    -- common parts to list A & B, at the beginning
    if commonUntil > 0 then
        table.insert( result, '* Common parts:' )
        for i = 1, commonUntil do
            insert_ab_value( i )
        end
    end

    -- diffing parts to list A & B
    if commonUntil < shortest - commonBackTo - 1 then
        table.insert( result, '* Differing parts:' )
        for i = commonUntil + 1, shortest - commonBackTo - 1 do
            insert_ab_value( i )
        end
    end

    -- display indexes of one list, with no match on other list
    if shortest - commonBackTo <= longest - commonBackTo - 1 then
        table.insert( result, '* Present only in one list:' )
        for i = shortest - commonBackTo, longest - commonBackTo - 1 do
            if len_a > len_b then
                extend_with_str_fmt( result, '  - A[%d]: %s', i, prettystr(table_a[i]) )
                -- table.insert( result, '+ (no matching B index)')
            else
                -- table.insert( result, '- no matching A index')
                extend_with_str_fmt( result, '  + B[%d]: %s', i, prettystr(table_b[i]) )
            end
        end
    end

    -- common parts to list A & B, at the end
    if commonBackTo >= 0 then
        table.insert( result, '* Common parts at the end of the lists' )
        for i = longest - commonBackTo, longest do
            if len_a > len_b then
                insert_ab_value( i, i-deltalv )
            else
                insert_ab_value( i-deltalv, i )
            end
        end
    end

    return true, table.concat( result, '\n')
end
M.private.mismatch_formatting_pure_list = mismatch_formatting_pure_list

local function prettystr_pairs(value1, value2, suffix_a, suffix_b)
    --[[
    This function helps with the recurring task of constructing the "expected
    vs. actual" error messages. It takes two arbitrary values and formats
    corresponding strings with prettystr().

    To keep the (possibly complex) output more readable in case the resulting
    strings contain line breaks, they get automatically prefixed with additional
    newlines. Both suffixes are optional (default to empty strings), and get
    appended to the "value1" string. "suffix_a" is used if line breaks were
    encountered, "suffix_b" otherwise.

    Returns the two formatted strings (including padding/newlines).
    ]]
    local str1, str2 = prettystr(value1), prettystr(value2)
    if has_new_line(str1) or has_new_line(str2) then
        -- line break(s) detected, add padding
        return "\n" .. str1 .. (suffix_a or ""), "\n" .. str2
    end
    return str1 .. (suffix_b or ""), str2
end
M.private.prettystr_pairs = prettystr_pairs

local function _table_raw_tostring( t )
    -- return the default tostring() for tables, with the table ID, even if the table has a metatable
    -- with the __tostring converter
    local mt = getmetatable( t )
    if mt then setmetatable( t, nil ) end
    local ref = tostring(t)
    if mt then setmetatable( t, mt ) end
    return ref
end
M.private._table_raw_tostring = _table_raw_tostring

local TABLE_TOSTRING_SEP = ", "
local TABLE_TOSTRING_SEP_LEN = string.len(TABLE_TOSTRING_SEP)

local function _table_tostring( tbl, indentLevel, printTableRefs, recursionTable )
    printTableRefs = printTableRefs or M.PRINT_TABLE_REF_IN_ERROR_MSG
    recursionTable = recursionTable or {}
    recursionTable[tbl] = true

    local result = {}

    -- like prettystr but do not enclose with "" if the string is just alphanumerical
    -- this is better for displaying table keys who are often simple strings
    local function keytostring(k)
        if "string" == type(k) and k:match("^[_%a][_%w]*$") then
            return k
        end
        return '[' .. prettystr_sub(k, indentLevel+1, printTableRefs, recursionTable) .. ']'
    end

    local mt = getmetatable( tbl )

    if mt and mt.__tostring then
        -- if table has a __tostring() function in its metatable, use it to display the table
        -- else, compute a regular table
        result = tostring(tbl)
        if type(result) ~= 'string' then
            return string.format( '<invalid tostring() result: "%s" >', prettystr(result) )
        end
        result = strsplit( '\n', result )
        return M.private._table_tostring_format_multiline_string( result, indentLevel )

    else
        -- no metatable, compute the table representation

        local count, seq_index = 0, 1
        for k, v in sorted_pairs( tbl ) do
            local entry

            -- key part
            if k == seq_index then
                -- for the sequential part of tables, we'll skip the "<key>=" output
                entry = ''
                seq_index = seq_index + 1
            elseif recursionTable[k] then
                -- recursion in the key detected
                recursionTable.recursionDetected = true
                entry = "<".._table_raw_tostring(k)..">="
            else
                entry = keytostring(k) .. " = "
            end

            -- value part
            if recursionTable[v] then
                -- recursion in the value detected!
                recursionTable.recursionDetected = true
                entry = entry .. "<".._table_raw_tostring(v)..">"
            else
                entry = entry ..
                    prettystr_sub( v, indentLevel+1, printTableRefs, recursionTable )
            end
            count = count + 1
            result[count] = entry
        end
        return M.private._table_tostring_format_result( tbl, result, indentLevel, printTableRefs )
    end

end
M.private._table_tostring = _table_tostring -- prettystr_sub() needs it

local function _table_tostring_format_multiline_string( tbl_str, indentLevel )
    local indentString = '\n'..string.rep("    ", indentLevel - 1)
    return table.concat( tbl_str, indentString )

end
M.private._table_tostring_format_multiline_string = _table_tostring_format_multiline_string


local function _table_tostring_format_result( tbl, result, indentLevel, printTableRefs )
    -- final function called in _table_to_string() to format the resulting list of
    -- string describing the table.

    local dispOnMultLines = false

    -- set dispOnMultLines to true if the maximum LINE_LENGTH would be exceeded with the values
    local totalLength = 0
    for _, v in ipairs( result ) do
        totalLength = totalLength + string.len( v )
        if totalLength >= M.LINE_LENGTH then
            dispOnMultLines = true
            break
        end
    end

    -- set dispOnMultLines to true if the max LINE_LENGTH would be exceeded
    -- with the values and the separators.
    if not dispOnMultLines then
        -- adjust with length of separator(s):
        -- two items need 1 sep, three items two seps, ... plus len of '{}'
        if #result > 0 then
            totalLength = totalLength + TABLE_TOSTRING_SEP_LEN * (#result - 1)
        end
        dispOnMultLines = (totalLength + 2 >= M.LINE_LENGTH)
    end

    -- now reformat the result table (currently holding element strings)
    if dispOnMultLines then
        local indentString = string.rep("    ", indentLevel - 1)
        result = {
                    "{\n    ",
                    indentString,
                    table.concat(result, ",\n    " .. indentString),
                    ",\n",
                    indentString,
                    "}"
                }
    else
        result = {"{", table.concat(result, TABLE_TOSTRING_SEP), "}"}
    end
    if printTableRefs then
        table.insert(result, 1, "<".._table_raw_tostring(tbl).."> ") -- prepend table ref
    end
    return table.concat(result)
end
M.private._table_tostring_format_result = _table_tostring_format_result -- prettystr_sub() needs it

--[[
This is a specialized metatable to help with the bookkeeping of recursions
in M.private.table_equals(). It provides an __index table that implements utility
functions for easier management of the table. The "cached" method queries
the state of a specific (actual,expected) pair; and the "store" method sets
this state to the given value. The state of pairs not "seen" / visited is
assumed to be `nil`.
]]
local RecursionCache = Class.new()
-- Return the cached value for an (actual,expected) pair (or `nil`)
function RecursionCache.mt:cached(actual, expected)
    local subtable = self[actual] or {}
    return subtable[expected]
end

-- Store cached value for a specific (actual,expected) pair.
-- Returns the value, so it's easy to use for a "tailcall" (return ...).
function RecursionCache.mt:store(actual, expected, value, asymmetric)
    local subtable = self[actual]
    if not subtable then
        subtable = {}
        self[actual] = subtable
    end
    subtable[expected] = value

    -- Unless explicitly marked "asymmetric": Consider the recursion
    -- on (expected,actual) to be equivalent to (actual,expected) by
    -- default, and thus cache the value for both.
    if not asymmetric then
        self:store(expected, actual, value, true)
    end

    return value
end

function M.private.table_equals(actual, expected, recursions)
        recursions = recursions or RecursionCache:new()

        if actual == expected then
            -- Both reference the same table, so they are actually identical
            return recursions:store(actual, expected, true)
        end

        -- If we've tested this (actual,expected) pair before: return cached value
        local previous = recursions:cached(actual, expected)
        if previous ~= nil then
            return previous
        end

        -- Mark this (actual,expected) pair, so we won't recurse it again. For
        -- now, assume a "false" result, which we might adjust later if needed.
        recursions:store(actual, expected, false)

        -- We used to verify that table count is identical here by comparing their length
        -- but this is unreliable when table is not a sequence. There is a test in test_luaunit.lua
        -- to catch this case.
        local actualKeysMatched, actualTableKeys = {}, {}

        for k, v in pairs(actual) do
            if M.TABLE_EQUALS_KEYBYCONTENT and type(k) == "table" then
                -- If the keys are tables, things get a bit tricky here as we
                -- can have M.private.table_equals(t[k1], t[k2]) despite k1 ~= k2. So
                -- we first collect table keys from "actual", and then later try
                -- to match each table key from "expected" to actualTableKeys.
                table.insert(actualTableKeys, k)
            else
                if not M.private.equals(v, expected[k], recursions) then
                    return false -- Mismatch on value, tables can't be equal
                end
                actualKeysMatched[k] = true -- Keep track of matched keys
            end
        end

        for k, v in pairs(expected) do
            if M.TABLE_EQUALS_KEYBYCONTENT and type(k) == "table" then
                local found = false
                -- Note: DON'T use ipairs() here, table may be non-sequential!
                for i, candidate in pairs(actualTableKeys) do
                    if M.private.equals(candidate, k, recursions) then
                        if M.private.equals(actual[candidate], v, recursions) then
                            found = true
                            -- Remove the candidate we matched against from the list
                            -- of table keys, so each key in actual can only match
                            -- one key in expected.
                            actualTableKeys[i] = nil
                            break
                        end
                        -- keys match but values don't, keep searching
                    end
                end
                if not found then
                    return false -- no matching (key,value) pair
                end
            else
                if not actualKeysMatched[k] then
                    -- Found a key that we did not see in "actual" -> mismatch
                    return false
                end
                -- Otherwise actual[k] was already matched against v = expected[k].
            end
        end

        if next(actualTableKeys) then
            -- If there is any key left in actualTableKeys, then that is
            -- a table-type key in actual with no matching counterpart
            -- (in expected), and so the tables aren't equal.
            return false
        end

        -- The tables are actually considered equal, update cache and return result
        return recursions:store(actual, expected, true)
end

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
        local success, mismatchResult
        success, mismatchResult = try_mismatch_formatting( actual, expected, doDeepAnalysis )
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

function M.private.cast_value_for_equals(value)
    if type(value) == 'cdata' then
        local ok, table_value = pcall(function() return value:totable() end)
        if ok then
            return table_value
        end
    end
    return value
end

function M.private.equals(a, b, recursions)
    a = M.private.cast_value_for_equals(a)
    b = M.private.cast_value_for_equals(b)
    if type(a) == 'table' and type(b) == 'table' then
        return M.private.table_equals(a, b, recursions)
    else
        return a == b
    end
end

function M.assert_equals(actual, expected, extra_msg_or_nil, doDeepAnalysis)
    if not M.private.equals(actual, expected) then
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
    if M.private.equals(actual, expected) then
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

-- Checks that actual is subset of expected.
-- Returns number of elements that are present in expected but not in actual.
function M.private.is_subset(actual, expected)
    if (type(actual) ~= 'table') or (type(expected) ~= 'table') then
        return false
    end

    local expected_array = {}
    local expected_casted = {}
    local found_ids = {}
    local found_count = 0
    for _, v in pairs(expected) do
        table.insert(expected_array, v)
    end

    local function search(a)
        for i = 1, #expected_array do
            if not found_ids[i] then
                if not expected_casted[i] then
                    expected_casted[i] = M.private.cast_value_for_equals(expected_array[i])
                end
                if M.private.equals(a, expected_casted[i]) then
                    found_ids[i] = true
                    found_count = found_count + 1
                    return true
                end
            end
        end
    end

    for _, a in pairs(actual) do
        if not search(a) then
            return false
        end
    end
    return #expected_array - found_count
end

function M.assert_items_equals(actual, expected, extra_msg_or_nil)
    -- Checks equality of tables regardless of the order of elements.
    if M.private.is_subset(actual, expected) ~= 0 then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, extra_msg_or_nil, 'Content of the tables are not identical:\nExpected: %s\nActual: %s',
                 expected, actual)
    end
end

function M.assert_items_include(actual, expected, extra_msg_or_nil)
    if not M.private.is_subset(expected, actual) then
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
    return M.private.table_equals(sliced, expected)
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
        failure( 'No error generated when calling function but expected error: '..M.prettystr(expectedMsg), nil, 3 )
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
                M.LuaUnit.help()
            elseif arg == '--version' then
                M.LuaUnit.version()
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

    function M.LuaUnit.help()
        print(M.USAGE)
        os_exit(0)
    end

    function M.LuaUnit.version()
        print('luatest v'..M.VERSION)
        os_exit(0)
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
        self.output = self.output_type:new(self)
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

    function M.LuaUnit.mt:find_test(groups, name)
        local group_name, method_name = M.LuaUnit.split_test_method_name(name)
        assert(group_name and method_name, 'Invalid test name: ' .. name)
        local group = assert(groups[group_name], 'Group not found: ' .. group_name)
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

        local groups = M.groups
        local result = {}
        for _, name in ipairs(self.test_names) do
            local group = groups[name]
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
                table.insert(result, self:find_test(groups, name))
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

        if not self.test_names then
            self.test_names = {}
            for name in sorted_pairs(M.groups) do
                table.insert(self.test_names, name)
            end
        end

        if self.output then
            self.output = self.output:lower()
            if self.output == 'junit' and self.output_file_name == nil then
                print('With junit output, a filename must be supplied with -n or --name')
                os_exit(-1)
            end
            local ok, output_type = pcall(require, 'luatest.output.' .. self.output)
            assert(ok, 'Can not load output module: ' .. self.output)
            self.output_type = output_type
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
            os_exit(-2)
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
