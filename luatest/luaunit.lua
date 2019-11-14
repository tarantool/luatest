--[[
        luaunit.lua

Description: A unit testing framework
Homepage: https://github.com/bluebird75/luaunit
Development by Philippe Fremy <phil@freehackers.org>
Based on initial work of Ryu, Gwang (http://www.gpgstudy.com/gpgiki/LuaUnit)
License: BSD License, see LICENSE.txt
]]--

local clock = require("clock")
require("math")
local M={}

-- private exported functions (for testing)
M.private = {}

M.VERSION='0.3.0'

--[[ Some people like assert_equals( actual, expected ) and some people prefer
assert_equals( expected, actual ).
]]--
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
            'Can not guess test name from the source file name'
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
local STRIP_LUAUNIT_FROM_STACKTRACE = true

M.VERBOSITY_DEFAULT = 10
M.VERBOSITY_LOW     = 1
M.VERBOSITY_QUIET   = 0
M.VERBOSITY_VERBOSE = 20
M.FORCE_DEEP_ANALYSIS   = true
M.DISABLE_DEEP_ANALYSIS = false

M.USAGE=[[Usage: luatest [options] [files or dirs...] [testname1 [testname2] ... ]
Options:
  -h, --help:             Print this help
  --version:              Print version information
  -v, --verbose:          Increase verbosity
  -q, --quiet:            Set verbosity to minimum
  -c                      Disable capture
  -e, --error:            Stop on first error
  -f, --failure:          Stop on first failure or error
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
  testname1, testname2, ... : tests to run in the form of testFunction,
                              TestClass or TestClass.testMethod
]]

local is_equal -- defined here to allow calling from mismatch_formatting_pure_list

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

local function prefix_string( prefix, s )
    -- Prefix all the lines of s with prefix
    return prefix .. string.gsub(s, '\n', '\n' .. prefix)
end
M.private.prefix_string = prefix_string

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

local function xml_escape( s )
    -- Return s escaped for XML attributes
    -- escapes table:
    -- "   &quot;
    -- '   &apos;
    -- <   &lt;
    -- >   &gt;
    -- &   &amp;

    return string.gsub( s, '.', {
        ['&'] = "&amp;",
        ['"'] = "&quot;",
        ["'"] = "&apos;",
        ['<'] = "&lt;",
        ['>'] = "&gt;",
    } )
end
M.private.xml_escape = xml_escape

local function xml_c_data_escape( s )
    -- Return s escaped for CData section, escapes: "]]>"
    return string.gsub( s, ']]>', ']]&gt;' )
end
M.private.xml_c_data_escape = xml_c_data_escape

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
        -- use clever delimiters according to content:
        -- enclose with single quotes if string contains ", but no '
        if v:find('"', 1, true) and not v:find("'", 1, true) then
            return "'" .. v .. "'"
        end
        -- use double quotes otherwise, escape embedded "
        return '"' .. v:gsub('"', '\\"') .. '"'

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
        if not is_equal(table_a[i], table_b[i]) then
            commonUntil = i - 1
            break
        end
    end

    local commonBackTo = shortest - 1
    for i = 0, shortest - 1 do
        if not is_equal(table_a[len_a-i], table_b[len_b-i]) then
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
        if is_equal( table_a[ai], table_b[bi]) then
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

local function _table_contains(t, element)
    if type(t) == "table" then
        local type_e = type(element)
        for _, value in pairs(t) do
            if type(value) == type_e then
                if value == element then
                    return true
                end
                if type_e == 'table' then
                    -- if we wanted recursive items content comparison, we could use
                    -- _is_table_items_equals(v, expected) but one level of just comparing
                    -- items is sufficient
                    if M.private._is_table_equals( value, element ) then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function _is_table_items_equals(actual, expected )
    local type_a, type_e = type(actual), type(expected)

    if (type_a == 'table') and (type_e == 'table') then
        for _, v in pairs(actual) do
            if not _table_contains(expected, v) then
                return false
            end
        end
        for _, v in pairs(expected) do
            if not _table_contains(actual, v) then
                return false
            end
        end
        return true

    elseif type_a ~= type_e then
        return false

    elseif actual ~= expected then
        return false
    end

    return true
end

--[[
This is a specialized metatable to help with the bookkeeping of recursions
in _is_table_equals(). It provides an __index table that implements utility
functions for easier management of the table. The "cached" method queries
the state of a specific (actual,expected) pair; and the "store" method sets
this state to the given value. The state of pairs not "seen" / visited is
assumed to be `nil`.
]]
local _recursion_cache_MT = {
    __index = {
        -- Return the cached value for an (actual,expected) pair (or `nil`)
        cached = function(t, actual, expected)
            local subtable = t[actual] or {}
            return subtable[expected]
        end,

        -- Store cached value for a specific (actual,expected) pair.
        -- Returns the value, so it's easy to use for a "tailcall" (return ...).
        store = function(t, actual, expected, value, asymmetric)
            local subtable = t[actual]
            if not subtable then
                subtable = {}
                t[actual] = subtable
            end
            subtable[expected] = value

            -- Unless explicitly marked "asymmetric": Consider the recursion
            -- on (expected,actual) to be equivalent to (actual,expected) by
            -- default, and thus cache the value for both.
            if not asymmetric then
                t:store(expected, actual, value, true)
            end

            return value
        end
    }
}

local function _is_table_equals(actual, expected, recursions)
    local type_a, type_e = type(actual), type(expected)
    recursions = recursions or setmetatable({}, _recursion_cache_MT)

    if type_a ~= type_e then
        return false -- different types won't match
    end

    if (type_a == 'table') then
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
                -- can have _is_table_equals(t[k1], t[k2]) despite k1 ~= k2. So
                -- we first collect table keys from "actual", and then later try
                -- to match each table key from "expected" to actualTableKeys.
                table.insert(actualTableKeys, k)
            else
                if not _is_table_equals(v, expected[k], recursions) then
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
                    if _is_table_equals(candidate, k, recursions) then
                        if _is_table_equals(actual[candidate], v, recursions) then
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

    elseif actual ~= expected then
        return false
    end

    return true
end
M.private._is_table_equals = _is_table_equals
is_equal = _is_table_equals

local function luaunit_error(status, message, level)
    local _
    _, message = pcall(error, message, (level or 1) + 2)
    error({class = 'LuaUnitError', status = status, message = message})
end

local function is_luaunit_error(err)
    return type(err) == 'table' and err.class == 'LuaUnitError'
end

local function failure(main_msg, extra_msg_or_nil, level)
    -- raise an error indicating a test failure
    -- for error() compatibility we adjust "level" here (by +1), to report the
    -- calling context
    local msg
    if type(extra_msg_or_nil) == 'string' and extra_msg_or_nil:len() > 0 then
        msg = extra_msg_or_nil .. '\n' .. main_msg
    else
        msg = main_msg
    end
    luaunit_error('fail', msg, (level or 1) + 1)
end

local function fail_fmt(level, extra_msg_or_nil, ...)
     -- failure with printf-style formatted message and given error level
    failure(string.format(...), extra_msg_or_nil, (level or 1) + 1)
end
M.private.fail_fmt = fail_fmt

local function error_fmt(level, ...)
     -- printf-style error()
    error(string.format(...), (level or 1) + 1)
end

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

local function cast_value_for_equals(value)
    if type(value) == 'cdata' and value.totable then
        return value:totable()
    end
    return value
end

function M.assert_equals(actual, expected, extra_msg_or_nil, doDeepAnalysis)
    actual = cast_value_for_equals(actual)
    expected = cast_value_for_equals(expected)
    if type(actual) == 'table' and type(expected) == 'table' then
        if not _is_table_equals(actual, expected) then
            failure( error_msg_equality(actual, expected, doDeepAnalysis), extra_msg_or_nil, 2 )
        end
    elseif type(actual) ~= type(expected) then
        failure( error_msg_equality(actual, expected), extra_msg_or_nil, 2 )
    elseif actual ~= expected then
        failure( error_msg_equality(actual, expected), extra_msg_or_nil, 2 )
    end
end

function M.almost_equals( actual, expected, margin )
    if type(actual) ~= 'number' or type(expected) ~= 'number' or type(margin) ~= 'number' then
        error_fmt(3, 'almost_equals: must supply only number arguments.\nArguments supplied: %s, %s, %s',
            prettystr(actual), prettystr(expected), prettystr(margin))
    end
    if margin < 0 then
        error('almost_equals: margin must not be negative, current value is ' .. margin, 3)
    end
    return math.abs(expected - actual) <= margin
end

function M.assert_almost_equals( actual, expected, margin, extra_msg_or_nil )
    -- check that two floats are close by margin
    margin = margin or M.EPS
    if not M.almost_equals(actual, expected, margin) then
        local delta = math.abs(actual - expected)
        fail_fmt(2, extra_msg_or_nil, 'Values are not almost equal\n' ..
                    'Actual: %s, expected: %s, delta %s above margin of %s',
                    actual, expected, delta, margin)
    end
end

function M.assert_not_equals(actual, expected, extra_msg_or_nil)
    if type(actual) ~= type(expected) then
        return
    end

    if type(actual) == 'table' and type(expected) == 'table' then
        if not _is_table_equals(actual, expected) then
            return
        end
    elseif actual ~= expected then
        return
    end
    fail_fmt(2, extra_msg_or_nil, 'Received the not expected value: %s', prettystr(actual))
end

function M.assert_not_almost_equals( actual, expected, margin, extra_msg_or_nil )
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
    -- checks that the items of table expected
    -- are contained in table actual. Warning, this function
    -- is at least O(n^2)
    if not _is_table_items_equals(actual, expected ) then
        expected, actual = prettystr_pairs(expected, actual)
        fail_fmt(2, extra_msg_or_nil, 'Content of the tables are not identical:\nExpected: %s\nActual: %s',
                 expected, actual)
    end
end

local function table_covers(actual, expected)
    if type(actual) ~= 'table' and type(expected) ~= 'table' then
        error('Argument 1 and 2 must be tables')
    end
    local sliced = {}
    for k, _ in pairs(expected) do
        sliced[k] = actual[k]
    end
    return _is_table_equals(sliced, expected)
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
    if not string.find(str, sub, 1, not isPattern) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Could not find %s %s in string %s',
                 isPattern and 'pattern' or 'substring', sub, str)
    end
end

function M.assert_str_icontains( str, sub, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    if not string.find(str:lower(), sub:lower(), 1, true) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Could not find (case insensitively) substring %s in string %s',
                 sub, str)
    end
end

function M.assert_not_str_contains( str, sub, isPattern, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    if string.find(str, sub, 1, not isPattern) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Found the not expected %s %s in string %s',
                 isPattern and 'pattern' or 'substring', sub, str)
    end
end

function M.assert_not_str_icontains( str, sub, extra_msg_or_nil )
    -- this relies on lua string.find function
    -- a string always contains the empty string
    if string.find(str:lower(), sub:lower(), 1, true) then
        sub, str = prettystr_pairs(sub, str, '\n')
        fail_fmt(2, extra_msg_or_nil, 'Found (case insensitively) the not expected substring %s in string %s',
                 sub, str)
    end
end

function M.assert_str_matches( str, pattern, start, final, extra_msg_or_nil )
    -- Verify a full match for the string
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

function M.assert_type(value, type_expected, extra_msg_or_nil)
    if type(value) ~= type_expected then
        fail_fmt(2, extra_msg_or_nil, 'expected: a %s value, actual: type %s, value %s',
                 type_expected, type(value), prettystr_pairs(value))
    end
end

function M.assert_is(actual, expected, extra_msg_or_nil)
    if actual ~= expected then
        expected, actual = prettystr_pairs(expected, actual, '\n', '')
        fail_fmt(2, extra_msg_or_nil, 'expected and actual object should not be different\nExpected: %s\nReceived: %s',
                 expected, actual)
    end
end

function M.assert_is_not(actual, expected, extra_msg_or_nil)
    if actual == expected then
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
--                     Outputters
--
----------------------------------------------------------------

-- A common "base" class for outputters
-- For concepts involved (class inheritance) see http://www.lua.org/pil/16.2.html

M.OutputTypes = {}

local genericOutput = {__class__ = 'genericOutput'} -- class
genericOutput.MT = {__index = genericOutput} -- metatable
M.genericOutput = genericOutput -- publish, so that custom classes may derive from it

function genericOutput.new_class(name)
    local output = setmetatable({__class__ = name}, genericOutput.MT)
    output.MT = {__index = output}
    M.OutputTypes[name:lower():gsub('output$', '')] = output
    return output
end

function genericOutput:new(runner)
    local object = {
        runner = runner,
        result = runner.result,
        verbosity = runner.verbosity,
    }
    return setmetatable(object, self.MT)
end

-- luacheck: push no unused
-- abstract ("empty") methods
function genericOutput:start_suite()
    -- Called once, when the suite is started
end

function genericOutput:start_group(group_name)
    -- Called each time a new test class is started
end

function genericOutput:start_test(test_name)
    -- called each time a new test is started, right before the setUp()
    -- the current test status node is already created and available in: self.result.current_node
end

function genericOutput:update_status(node)
    -- called with status failed or error as soon as the error/failure is encountered
    -- this method is NOT called for a successful test because a test is marked as successful by default
    -- and does not need to be updated
end

function genericOutput:end_test(node)
    -- called when the test is finished, after the tearDown() method
end

function genericOutput:end_group()
    -- called when executing the class is finished, before moving on to the next class
    -- of at the end of the test execution
end

function genericOutput:end_suite()
    -- called at the end of the test suite execution
end
-- luacheck: pop


----------------------------------------------------------------
--                     class TapOutput
----------------------------------------------------------------

local TapOutput = genericOutput.new_class('TapOutput')
    -- For a good reference for TAP format, check: http://testanything.org/tap-specification.html

    function TapOutput:start_suite()
        print("1.."..self.result.selected_count)
        print('# Started on ' .. os.date(nil, self.result.start_time))
    end
    function TapOutput:start_group(group_name) -- luacheck: no unused
        if group_name ~= '[TestFunctions]' then
            print('# Starting class: '..group_name)
        end
    end

    function TapOutput:update_status(node)
        if node:is('skip') then
            io.stdout:write("ok ", node.serial_number, "\t# SKIP ", node.message or '', "\n")
            return
        end

        io.stdout:write("not ok ", node.serial_number, "\t", node.name, "\n")
        if self.verbosity > M.VERBOSITY_LOW then
           print(prefix_string( '#   ', node.message))
        end
        if (node:is('fail') or node:is('error')) and self.verbosity > M.VERBOSITY_DEFAULT then
           print(prefix_string('#   ', node.trace))
        end
    end

    function TapOutput:end_test(node) -- luacheck: no unused
        if node:is('success') then
            io.stdout:write("ok     ", node.serial_number, "\t", node.name, "\n")
        end
    end

    function TapOutput:end_suite()
        print( '# '..M.LuaUnit.status_line( self.result ) )
    end


-- class TapOutput end

----------------------------------------------------------------
--                     class JUnitOutput
----------------------------------------------------------------

-- See directory junitxml for more information about the junit format
local JUnitOutput = genericOutput.new_class('JUnitOutput')

    function JUnitOutput:start_suite()
        self.output_file_name = assert(self.runner.output_file_name)
        -- open xml file early to deal with errors
        if string.sub(self.output_file_name,-4) ~= '.xml' then
            self.output_file_name = self.output_file_name..'.xml'
        end
        self.fd = io.open(self.output_file_name, "w")
        if self.fd == nil then
            error("Could not open file for writing: "..self.output_file_name)
        end

        print('# XML output to '..self.output_file_name)
        print('# Started on ' .. os.date(nil, self.result.start_time))
    end
    function JUnitOutput:start_group(group_name) -- luacheck: no unused
        if group_name ~= '[TestFunctions]' then
            print('# Starting class: '..group_name)
        end
    end
    function JUnitOutput:start_test(test_name) -- luacheck: no unused
        print('# Starting test: '..test_name)
    end

    function JUnitOutput:update_status( node ) -- luacheck: no unused
        if node:is('fail') then
            print('#   Failure: ' .. prefix_string('#   ', node.message):sub(4, nil))
            -- print('# ' .. node.trace)
        elseif node:is('error') then
            print('#   Error: ' .. prefix_string('#   ', node.message):sub(4, nil))
            -- print('# ' .. node.trace)
        end
    end

    function JUnitOutput:end_suite()
        print( '# '..M.LuaUnit.status_line(self.result))

        -- XML file writing
        self.fd:write('<?xml version="1.0" encoding="UTF-8" ?>\n')
        self.fd:write('<testsuites>\n')
        self.fd:write(string.format(
            '    <testsuite name="luatest" id="00001" package="" hostname="localhost" tests="%d" timestamp="%s" ' ..
            'time="%0.3f" errors="%d" failures="%d" skipped="%d">\n',
            #self.result.tests.all - #self.result.tests.skip, os.date('%Y-%m-%dT%H:%M:%S', self.result.start_time),
            self.result.duration, #self.result.tests.error, #self.result.tests.fail, #self.result.tests.skip
        ))
        self.fd:write("        <properties>\n")
        self.fd:write(string.format('            <property name="Lua Version" value="%s"/>\n', _VERSION ) )
        self.fd:write(string.format('            <property name="luatest Version" value="%s"/>\n', M.VERSION) )
        -- XXX please include system name and version if possible
        self.fd:write("        </properties>\n")

        for _, node in ipairs(self.result.tests.all) do
            self.fd:write(string.format('        <testcase classname="%s" name="%s" time="%0.3f">\n',
                node.group.name or '', node.name, node.duration))
            if not node:is('success') then
                self.fd:write(JUnitOutput.node_status_xml(node))
            end
            self.fd:write('        </testcase>\n')
        end

        -- Next two lines are needed to validate junit ANT xsd, but really not useful in general:
        self.fd:write('    <system-out/>\n')
        self.fd:write('    <system-err/>\n')

        self.fd:write('    </testsuite>\n')
        self.fd:write('</testsuites>\n')
        self.fd:close()
    end

    function JUnitOutput.node_status_xml(node)
        if node:is('error') then
            return table.concat(
                {'            <error type="', xml_escape(node.message), '">\n',
                 '                <![CDATA[', xml_c_data_escape(node.trace),
                 ']]></error>\n'})
        elseif node:is('fail') then
            return table.concat(
                {'            <failure type="', xml_escape(node.message), '">\n',
                 '                <![CDATA[', xml_c_data_escape(node.trace),
                 ']]></failure>\n'})
        elseif node:is('skip') then
            return table.concat({'            <skipped>', xml_escape(node.message or ''),'</skipped>\n' } )
        end
        return '            <passed/>\n' -- (not XSD-compliant! normally shouldn't get here)
    end


-- class JUnitOutput end


local TextOutput = genericOutput.new_class('TextOutput')

TextOutput.BOLD_CODE = '\x1B[1m'
TextOutput.ERROR_COLOR_CODE = TextOutput.BOLD_CODE .. '\x1B[31m' -- red
TextOutput.SUCCESS_COLOR_CODE = TextOutput.BOLD_CODE .. '\x1B[32m' -- green
TextOutput.RESET_TERM = '\x1B[0m'

    function TextOutput:start_suite()
        if self.runner.seed then
            print('Running with --shuffle ' .. self.runner.shuffle .. ':' .. self.runner.seed)
        end
        if self.verbosity > M.VERBOSITY_DEFAULT then
            print('Started on '.. os.date(nil, self.result.start_time))
        end
    end

    function TextOutput:start_test(test_name) -- luacheck: no unused
        if self.verbosity > M.VERBOSITY_DEFAULT then
            io.stdout:write( "    ", test_name, " ... " )
        end
    end

    function TextOutput:end_test( node )
        if node:is('success') then
            if self.verbosity > M.VERBOSITY_DEFAULT then
                io.stdout:write("Ok\n")
            else
                io.stdout:write(".")
                io.stdout:flush()
            end
        else
            if self.verbosity > M.VERBOSITY_DEFAULT then
                print(node.status)
                print(node.message)
            else
                -- write only the first character of status E, F or S
                io.stdout:write(string.sub(node.status, 1, 1):upper())
                io.stdout:flush()
            end
        end
    end

    function TextOutput:display_one_failed_test(index, fail) -- luacheck: no unused
        print(index..") " .. fail.name .. TextOutput.ERROR_COLOR_CODE)
        print(fail.message .. TextOutput.RESET_TERM)
        print(fail.trace)
        print()
    end

    function TextOutput:display_errored_tests()
        if #self.result.tests.error > 0 then
            print(TextOutput.BOLD_CODE)
            print("Tests with errors:")
            print("------------------")
            print(TextOutput.RESET_TERM)
            for i, v in ipairs(self.result.tests.error) do
                self:display_one_failed_test(i, v)
            end
        end
    end

    function TextOutput:display_failed_tests()
        if #self.result.tests.fail > 0 then
            print(TextOutput.BOLD_CODE)
            print("Failed tests:")
            print("-------------")
            print(TextOutput.RESET_TERM)
            for i, v in ipairs(self.result.tests.fail) do
                self:display_one_failed_test(i, v)
            end
        end
    end

    function TextOutput:end_suite()
        if self.verbosity > M.VERBOSITY_DEFAULT then
            print("=========================================================")
        else
            print()
        end
        self:display_errored_tests()
        self:display_failed_tests()
        print( M.LuaUnit.status_line( self.result, {
            success = TextOutput.SUCCESS_COLOR_CODE,
            failure = TextOutput.ERROR_COLOR_CODE,
            reset = TextOutput.RESET_TERM,
        } ) )
        if self.result.notSuccessCount == 0 then
            print('OK')
        end

        local list = table.copy(self.result.tests.fail)
        for _, x in pairs(self.result.tests.error) do
            table.insert(list, x)
        end
        if #list > 0 then
            table.sort(list, function(a, b) return a.name < b.name end)
            if self.verbosity > M.VERBOSITY_DEFAULT then
                print("\n=========================================================")
            else
                print()
            end
            print(TextOutput.BOLD_CODE .. 'Failed tests:\n' .. TextOutput.ERROR_COLOR_CODE)
            for _, x in pairs(list) do
                print(x.name)
            end
            io.stdout:write(TextOutput.RESET_TERM)
        end
    end

-- class TextOutput end


----------------------------------------------------------------
--                     class NilOutput
----------------------------------------------------------------

local NilOutput = genericOutput.new_class('NilOutput')
NilOutput.MT = {__index = function(self, key)
    self[key] = function() end
    return self.key
end}

----------------------------------------------------------------
--
--                     class LuaUnit
--
----------------------------------------------------------------

M.LuaUnit = {
    output_type = TextOutput,
    verbosity = M.VERBOSITY_DEFAULT,
    shuffle = 'none',
    __class__ = 'LuaUnit'
}
local LuaUnit_MT = { __index = M.LuaUnit }


    function M.LuaUnit.new(object)
        object = setmetatable(object or {}, LuaUnit_MT)
        object:initialize()
        return object
    end

    -----------------[[ Utility methods ]]---------------------

    -- Split `some.class.name.method` into `some.class.name` and `method`.
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

    function M.LuaUnit.parse_cmd_line( cmdLine )
        -- parse the command line
        -- See M.USAGE for supported options.

        local result, state = {paths = {}}, nil

        if cmdLine == nil then
            return result
        end

        local function parse_option( option )
            if option == '--help' or option == '-h' then
                M.LuaUnit.help()
            elseif option == '--version' then
                M.LuaUnit.version()
            elseif option == '--verbose' or option == '-v' then
                result.verbosity = M.VERBOSITY_VERBOSE
            elseif option == '--quiet' or option == '-q' then
                result.verbosity = M.VERBOSITY_QUIET
            elseif option == '--error' or option == '-e' then
                result.quit_on_error = true
            elseif option == '--failure' or option == '-f' then
                result.quit_on_failure = true
            elseif option == '--shuffle' or option == '-s' then
                return 'SET_SHUFFLE'
            elseif option == '--seed' then
                return 'SET_SEED'
            elseif option == '--output' or option == '-o' then
                return 'SET_OUTPUT'
            elseif option == '--name' or option == '-n' then
                return 'SET_OUTPUT_FILENAME'
            elseif option == '--repeat' or option == '-r' then
                return 'SET_REPEAT'
            elseif option == '--pattern' or option == '-p' then
                return 'SET_PATTERN'
            elseif option == '--exclude' or option == '-x' then
                return 'SET_EXCLUDE'
            elseif option == '-c' then
                result.enable_capture = false
            else
                error('Unknown option: '..option,3)
            end
        end

        local function set_arg(cmdArg)
            if state == 'SET_OUTPUT' then
                result.output = cmdArg
            elseif state == 'SET_OUTPUT_FILENAME' then
                result.output_file_name = cmdArg
            elseif state == 'SET_REPEAT' then
                result.exe_repeat = tonumber(cmdArg)
                                     or error('Malformed -r argument: '..cmdArg)
            elseif state == 'SET_PATTERN' then
                if result.tests_pattern then
                    table.insert( result.tests_pattern, cmdArg )
                else
                    result.tests_pattern = { cmdArg }
                end
            elseif state == 'SET_EXCLUDE' then
                local notArg = '!'..cmdArg
                if result.tests_pattern then
                    table.insert( result.tests_pattern,  notArg )
                else
                    result.tests_pattern = { notArg }
                end
            elseif state == 'SET_SHUFFLE' then
                local seed
                result.shuffle, seed = unpack(cmdArg:split(':'))
                if seed then
                    result.seed = tonumber(seed) or error('Invalid seed value')
                end
            elseif state == 'SET_SEED' then
                result.seed = tonumber(cmdArg) or error('Invalid seed value')
            else
                error('Unknown parse state: '.. state)
            end
        end


        for _, cmdArg in ipairs(cmdLine) do
            if state ~= nil then
                set_arg(cmdArg)
                state = nil
            else
                if cmdArg:sub(1,1) == '-' then
                    state = parse_option( cmdArg )
                -- If argument contains / then it's treated as file path.
                -- This assumption to support luaunit's test names along with file paths.
                elseif cmdArg:find('/') then
                    table.insert(result.paths, cmdArg)
                else
                    if result.test_names then
                        table.insert( result.test_names, cmdArg )
                    else
                        result.test_names = { cmdArg }
                    end
                end
            end
        end

        if state ~= nil then
            error('Missing argument after '..cmdLine[ #cmdLine ],2 )
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

    local NodeStatus = {
        __class__ = 'NodeStatus',
        MT = {},
        STATUSES = {'success', 'skip', 'fail', 'error'},
    }
    NodeStatus.MT = {__index = NodeStatus} -- metatable

    -- default constructor, test are PASS by default
    function NodeStatus:new(object)
        object.status = 'success'
        return setmetatable(object, self.MT)
    end

    function NodeStatus:update_status(status, message, trace)
        self.status = status
        self.message = message
        self.trace = trace
    end

    function NodeStatus:is(status)
        return self.status == status
    end

    --------------[[ Output methods ]]-------------------------

    local function conditional_plural(number, singular)
        -- returns a grammatically well-formed string "%d <singular/plural>"
        local suffix = ''
        if number ~= 1 then -- use plural
            suffix = (singular:sub(-2) == 'ss') and 'es' or 's'
        end
        return string.format('%d %s%s', number, singular, suffix)
    end

    function M.LuaUnit.status_line(result, colors)
        colors = colors or {success = '', failure = '', reset = ''}
        -- return status line string according to results
        local tests = result.tests
        local s = {
            string.format('Ran %d tests in %0.3f seconds', #tests.all - #tests.skip, result.duration),
            colors.success .. conditional_plural(#tests.success, 'success') .. colors.reset,
        }
        if #tests.fail > 0 then
            table.insert(s, colors.failure .. conditional_plural(#tests.fail, 'fail') .. colors.reset)
        end
        if #tests.error > 0 then
            table.insert(s, colors.failure .. conditional_plural(#tests.error, 'error') .. colors.reset)
        end
        if #tests.fail == 0 and #tests.error == 0 then
            table.insert(s, '0 failures')
        end
        if #tests.skip > 0 then
            table.insert(s, string.format("%d skipped", #tests.skip))
        end
        if result.not_selected_count > 0 then
            table.insert(s, string.format("%d not-selected", result.not_selected_count))
        end
        return table.concat(s, ', ')
    end

    function M.LuaUnit:start_suite(selected_count, not_selected_count)
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

    function M.LuaUnit:start_group(group)
        self.result.current_group = group
        self.output:start_group(group.name)
    end

    function M.LuaUnit:start_test(test)
        test = table.copy(test)
        test.serial_number = #self.result.tests.all + 1
        test.start_time = clock.time()
        self.result.current_node = NodeStatus:new(test)
        table.insert(self.result.tests.all, self.result.current_node)
        self.output:start_test(test.name)
    end

    function M.LuaUnit:update_status(err)
        local node = self.result.current_node
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

    function M.LuaUnit:end_test()
        local node = self.result.current_node
        node.duration = clock.time() - node.start_time
        node.start_time = nil
        self.output:end_test(node)
        self.result.current_node = nil

        if node:is('error') then
            self.result.aborted = self.quit_on_error or self.quit_on_failure
        elseif node:is('fail') then
            self.result.aborted = self.quit_on_failure
        elseif not node:is('success') and not node:is('skip') then
            error('No such node status: ' .. prettystr(node.status))
        end
        table.insert(self.result.tests[node.status], node)
    end

    function M.LuaUnit:end_group()
        self.output:end_group()
    end

    function M.LuaUnit:end_suite()
        if self.result.duration then
            error('Suite was already ended' )
        end
        self.result.duration = clock.time() - self.result.start_time
        self.result.failures_count = #self.result.tests.fail + #self.result.tests.error
        self.output:end_suite()
    end

    --------------[[ Runner ]]-----------------

    function M.LuaUnit:protected_call(instance, method, pretty_name)
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

        if self.test_iteration > 1 then
            err.message = tostring(err.message) .. '\nIteration ' .. self.test_iteration
        end

        if err.status == 'success' or err.status == 'skip' then
            err.trace = nil
            return err
        end

        -- reformat / improve the stack trace
        if pretty_name then -- we do have the real method name
            err.trace = err.trace:gsub("in (%a+) 'method'", "in %1 '" .. pretty_name .. "'")
        end
        if STRIP_LUAUNIT_FROM_STACKTRACE then
            err.trace = strip_luaunit_trace(err.trace)
        end

        return err -- return the error "object" (table)
    end

    function M.LuaUnit:invoke_test_function(test)
        self:update_status(self:protected_call(test.group, test.method, test.name))
    end

    function M.LuaUnit:run_test(test)
        self:start_test(test)
        for iter_n = 1, self.exe_repeat or 1 do
            if not self.result.current_node:is('success') then
                break
            end
            self.test_iteration = iter_n
            self:invoke_test_function(test)
        end
        self:end_test()
    end

    function M.LuaUnit:run_tests(tests_list)
        -- Make seed for ordering not affect other random numbers.
        math.randomseed(os.time())
        for _, test in ipairs(tests_list) do
            if self.result.current_group ~= test.group then
                if self.result.current_group then
                    self:end_group()
                end
                self:start_group(test.group)
            end
            self:run_test(test)
            if self.result.aborted then
                break -- "--error" or "--failure" option triggered
            end
        end
        if self.result.current_group then
            self:end_group()
        end
    end

    function M.LuaUnit.build_test(group, method_name)
        local name = group.name .. '.' .. method_name
        local method = assert(group[method_name], 'Could not find method ' .. name)
        assert(type(method) == 'function', name .. ' is not a function')
        return {
            name = name,
            group = group,
            method_name = method_name,
            method = method,
            line = debug.getinfo(method).linedefined or 0,
        }
    end

    -- Exrtact all test methods from group.
    function M.LuaUnit:expand_group(group)
        local result = {}
        for method_name in sorted_pairs(group) do
            if M.LuaUnit.is_method_test_name(method_name) then
                table.insert(result, self.build_test(group, method_name))
            end
        end
        return result
    end

    function M.LuaUnit:find_test(groups, name)
        local group_name, method_name = M.LuaUnit.split_test_method_name(name)
        assert(group_name and method_name, 'Invalid test name: ' .. name)
        local group = assert(groups[group_name], 'Group not found: ' .. group_name)
        return self.build_test(group, method_name)
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

    function M.LuaUnit:find_tests()
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
    --   - quit_on_error
    --   - quit_on_failure
    --   - output_file_name
    --   - exe_repeat
    --   - tests_pattern
    --   - shuffle
    --   - seed
    function M.LuaUnit.run(options)
        return M.LuaUnit.new(options):run_suite()
    end

    function M.LuaUnit:initialize()
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
            self.output_type = assert(M.OutputTypes[self.output], 'No such format: ' .. self.output)
        end
    end

    function M.LuaUnit:run_suite()
        local tests = self:find_tests()
        local filtered_list, filtered_out_list = self.filter_tests(tests, self.tests_pattern)
        self:start_suite(#filtered_list, #filtered_out_list)
        self:run_tests(filtered_list)
        self:end_suite()
        if self.result.aborted then
            print("Test suite ABORTED (as requested by --error or --failure option)")
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
