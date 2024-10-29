local Class = require('luatest.class')
local sorted_pairs = require('luatest.sorted_pairs')

-- Pretty printer.
local pp = {
    TABLE_REF_IN_ERROR_MSG = false,
    LINE_LENGTH = 80,
}

-- Returns same values as original tostring for any table.
function pp.table_ref(t)
    local mt = getmetatable(t)
    if mt then setmetatable(t, nil) end
    local ref = tostring(t)
    if mt then setmetatable(t, mt) end
    return ref
end

local TABLE_TOSTRING_SEP = ", "
local TABLE_TOSTRING_SEP_LEN = string.len(TABLE_TOSTRING_SEP)

-- Final function called in format_table() to format the resulting list of
-- string describing the table.
local function _table_tostring_format_result(tbl, result, indentLevel, printTableRefs)
    local dispOnMultLines = false

    -- set dispOnMultLines to true if the maximum LINE_LENGTH would be exceeded with the values
    local totalLength = 0
    for _, v in ipairs(result) do
        totalLength = totalLength + string.len(v)
        if totalLength >= pp.LINE_LENGTH then
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
        dispOnMultLines = (totalLength + 2 >= pp.LINE_LENGTH)
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
        table.insert(result, 1, "<"..pp.table_ref(tbl).."> ") -- prepend table ref
    end
    return table.concat(result)
end

local function _table_tostring_format_multiline_string(tbl_str, indentLevel)
    local indentString = '\n' .. string.rep("    ", indentLevel - 1)
    return table.concat(tbl_str, indentString)
end

local Formatter = Class.new()

function Formatter.mt:initialize(printTableRefs)
    self.printTableRefs = printTableRefs
    self.recursionTable = {}
end

function Formatter.mt:format_table(tbl, indentLevel)
    indentLevel = indentLevel or 1
    self.recursionTable[tbl] = true

    local result = {}

    -- like pp.tostring but do not enclose with "" if the string is just alphanumerical
    -- this is better for displaying table keys who are often simple strings
    local function keytostring(k)
        if "string" == type(k) and k:match("^[_%a][_%w]*$") then
            return k
        end
        return '[' .. self:format(k, indentLevel + 1) .. ']'
    end

    local mt = getmetatable(tbl)

    if mt and mt.__tostring then
        -- if table has a __tostring() function in its metatable, use it to display the table
        -- else, compute a regular table
        result = tostring(tbl)
        if type(result) ~= 'string' then
            return string.format('<invalid tostring() result: "%s" >', pp.tostring(result))
        end
        result = result:split('\n')
        return _table_tostring_format_multiline_string(result, indentLevel)
    else
        -- no metatable, compute the table representation
        local count, seq_index = 0, 1
        for k, v in sorted_pairs(tbl) do
            local entry

            -- key part
            if k == seq_index then
                -- for the sequential part of tables, we'll skip the "<key>=" output
                entry = ''
                seq_index = seq_index + 1
            elseif self.recursionTable[k] then
                -- recursion in the key detected
                self.recursionDetected = true
                entry = "<"..pp.table_ref(k)..">="
            else
                entry = keytostring(k) .. " = "
            end

            -- value part
            if self.recursionTable[v] then
                -- recursion in the value detected!
                self.recursionDetected = true
                entry = entry .. "<"..pp.table_ref(v)..">"
            else
                entry = entry .. self:format(v, indentLevel + 1)
            end
            count = count + 1
            result[count] = entry
        end
        return _table_tostring_format_result(tbl, result, indentLevel, self.printTableRefs)
    end
end

function Formatter.mt:format(v, indentLevel)
    local type_v = type(v)
    if "string" == type_v  then
        return string.format("%q", v)
    elseif "table" == type_v then
        return self:format_table(v, indentLevel)
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

-- Pretty string conversion, to display the full content of a variable of any type.
--
-- * string are enclosed with " by default, or with ' if string contains a "
-- * tables are expanded to show their full content, with indentation in case of nested tables
function pp.tostring(value)
    local formatter = Formatter:new(pp.TABLE_REF_IN_ERROR_MSG)
    local result = formatter:format(value)
    if formatter.recursionDetected and not pp.TABLE_REF_IN_ERROR_MSG then
        -- some table contain recursive references,
        -- so we must recompute the value by including all table references
        -- else the result looks like crap
        return Formatter:new(true):format(value)
    end
    return result
end

local function has_new_line(s)
    return (string.find(s, '\n', 1, true) ~= nil)
end

-- This function helps with the recurring task of constructing the "expected
-- vs. actual" error messages. It takes two arbitrary values and formats
-- corresponding strings with tostring().
--
-- To keep the (possibly complex) output more readable in case the resulting
-- strings contain line breaks, they get automatically prefixed with additional
-- newlines. Both suffixes are optional (default to empty strings), and get
-- appended to the "value1" string. "suffix_a" is used if line breaks were
-- encountered, "suffix_b" otherwise.
--
-- Returns the two formatted strings (including padding/newlines).
function pp.tostring_pair(value1, value2, suffix_a, suffix_b)
    local str1, str2 = pp.tostring(value1), pp.tostring(value2)
    if has_new_line(str1) or has_new_line(str2) then
        -- line break(s) detected, add padding
        return "\n" .. str1 .. (suffix_a or ""), "\n" .. str2
    end
    return str1 .. (suffix_b or ""), str2
end

return pp
