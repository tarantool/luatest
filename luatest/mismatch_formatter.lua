local comparator = require('luatest.comparator')
local pp = require('luatest.pp')

local export = {
    LIST_DIFF_ANALYSIS_THRESHOLD = 10, -- display deep analysis for more than 10 items
}

local function extend_with_str_fmt(res, ...)
    table.insert(res, string.format(...))
end

-- Prepares a nice error message when comparing tables which are lists, performing a deeper
-- analysis.
--
-- Returns: {success, result}
-- * success: false if deep analysis could not be performed
--            in this case, just use standard assertion message
-- * result: if success is true, a multi-line string with deep analysis of the two lists
local function mismatch_formatting_pure_list(table_a, table_b)
    local result = {}

    local len_a, len_b, refa, refb = #table_a, #table_b, '', ''
    if pp.TABLE_REF_IN_ERROR_MSG then
        refa, refb = string.format('<%s> ', pp.table_ref(table_a)), string.format('<%s> ', pp.table_ref(table_b))
    end
    local longest, shortest = math.max(len_a, len_b), math.min(len_a, len_b)
    local deltalv  = longest - shortest

    local commonUntil = shortest
    for i = 1, shortest do
        if not comparator.equals(table_a[i], table_b[i]) then
            commonUntil = i - 1
            break
        end
    end

    local commonBackTo = shortest - 1
    for i = 0, shortest - 1 do
        if not comparator.equals(table_a[len_a-i], table_b[len_b-i]) then
            commonBackTo = i - 1
            break
        end
    end


    table.insert(result, 'List difference analysis:')
    if len_a == len_b then
        -- TODO: handle expected/actual naming
        extend_with_str_fmt(result, '* lists %sA (actual) and %sB (expected) have the same size', refa, refb)
    else
        extend_with_str_fmt(result,
            '* list sizes differ: list %sA (actual) has %d items, list %sB (expected) has %d items',
            refa, len_a, refb, len_b
        )
    end

    extend_with_str_fmt(result, '* lists A and B start differing at index %d', commonUntil+1)
    if commonBackTo >= 0 then
        if deltalv > 0 then
            extend_with_str_fmt(result, '* lists A and B are equal again from index %d for A, %d for B',
                len_a-commonBackTo, len_b-commonBackTo)
        else
            extend_with_str_fmt(result, '* lists A and B are equal again from index %d', len_a-commonBackTo)
        end
    end

    local function insert_ab_value(ai, bi)
        bi = bi or ai
        if comparator.equals(table_a[ai], table_b[bi]) then
            return extend_with_str_fmt(result, '  = A[%d], B[%d]: %s', ai, bi, pp.tostring(table_a[ai]))
        else
            extend_with_str_fmt(result, '  - A[%d]: %s', ai, pp.tostring(table_a[ai]))
            extend_with_str_fmt(result, '  + B[%d]: %s', bi, pp.tostring(table_b[bi]))
        end
    end

    -- common parts to list A & B, at the beginning
    if commonUntil > 0 then
        table.insert(result, '* Common parts:')
        for i = 1, commonUntil do
            insert_ab_value(i)
        end
    end

    -- diffing parts to list A & B
    if commonUntil < shortest - commonBackTo - 1 then
        table.insert(result, '* Differing parts:')
        for i = commonUntil + 1, shortest - commonBackTo - 1 do
            insert_ab_value(i)
        end
    end

    -- display indexes of one list, with no match on other list
    if shortest - commonBackTo <= longest - commonBackTo - 1 then
        table.insert(result, '* Present only in one list:')
        for i = shortest - commonBackTo, longest - commonBackTo - 1 do
            if len_a > len_b then
                extend_with_str_fmt(result, '  - A[%d]: %s', i, pp.tostring(table_a[i]))
                -- table.insert(result, '+ (no matching B index)')
            else
                -- table.insert(result, '- no matching A index')
                extend_with_str_fmt(result, '  + B[%d]: %s', i, pp.tostring(table_b[i]))
            end
        end
    end

    -- common parts to list A & B, at the end
    if commonBackTo >= 0 then
        table.insert(result, '* Common parts at the end of the lists')
        for i = longest - commonBackTo, longest do
            if len_a > len_b then
                insert_ab_value(i, i-deltalv)
            else
                insert_ab_value(i-deltalv, i)
            end
        end
    end

    return true, table.concat(result, '\n')
end

-- Prepares a nice error message when comparing tables, performing a deeper
-- analysis.
--
-- Arguments:
-- * table_a, table_b: tables to be compared
-- * doDeepAnalysis:
--     nil: (the default if not specified) perform deep analysis
--         only for big lists and big dictionnaries
--     true: always perform deep analysis
--     false: never perform deep analysis
--
-- Returns: {success, result}
-- * success: false if deep analysis could not be performed
--            in this case, just use standard assertion message
-- * result: if success is true, a multi-line string with deep analysis of the two lists
function export.format(table_a, table_b, doDeepAnalysis)
    -- check if table_a & table_b are suitable for deep analysis
    if type(table_a) ~= 'table' or type(table_b) ~= 'table' then
        return false
    end

    if doDeepAnalysis == false then
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

    if isPureList and math.min(len_a, len_b) < export.LIST_DIFF_ANALYSIS_THRESHOLD then
        if not (doDeepAnalysis == true) then
            return false
        end
    end

    if isPureList then
        return mismatch_formatting_pure_list(table_a, table_b)
    else
        return false
    end
end

return export
