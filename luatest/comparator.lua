local Class = require('luatest.class')

-- Utils for smart comparison.
local comparator = {}

function comparator.cast(value)
    if type(value) == 'cdata' then
        local ok, table_value = pcall(function() return value:totable() end)
        if ok then
            return table_value
        end
    end
    return value
end

-- Compare items by value: casts cdata values to tables, and compare tables by their content.
function comparator.equals(a, b, recursions)
    a = comparator.cast(a)
    b = comparator.cast(b)
    if type(a) == 'table' and type(b) == 'table' then
        return comparator.table_equals(a, b, recursions)
    else
        return a == b
    end
end

-- Checks that actual is subset of expected.
-- Returns number of elements that are present in expected but not in actual.
function comparator.is_subset(actual, expected)
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
                    expected_casted[i] = comparator.cast(expected_array[i])
                end
                if comparator.equals(a, expected_casted[i]) then
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

-- This is a specialized metatable to help with the bookkeeping of recursions
-- in table_equals(). It provides an __index table that implements utility
-- functions for easier management of the table. The "cached" method queries
-- the state of a specific (actual,expected) pair; and the "store" method sets
-- this state to the given value. The state of pairs not "seen" / visited is
-- assumed to be `nil`.
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

function comparator.table_equals(actual, expected, recursions)
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
    -- but this is unreliable when table is not a sequence.
    local actualKeysMatched, actualTableKeys = {}, {}

    for k, v in pairs(actual) do
        if type(k) == "table" then
            -- If the keys are tables, things get a bit tricky here as we
            -- can have table_equals(t[k1], t[k2]) despite k1 ~= k2. So
            -- we first collect table keys from "actual", and then later try
            -- to match each table key from "expected" to actualTableKeys.
            table.insert(actualTableKeys, k)
        else
            if not comparator.equals(v, expected[k], recursions) then
                return false -- Mismatch on value, tables can't be equal
            end
            actualKeysMatched[k] = true -- Keep track of matched keys
        end
    end

    for k, v in pairs(expected) do
        if type(k) == "table" then
            local found = false
            -- Note: DON'T use ipairs() here, table may be non-sequential!
            for i, candidate in pairs(actualTableKeys) do
                if comparator.equals(candidate, k, recursions) then
                    if comparator.equals(actual[candidate], v, recursions) then
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

return comparator
