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

-- Returns a sequence consisting of t's keys, sorted.
local function gen_index(t)
    local sortedIndex = {}

    for key,_ in pairs(t) do
        table.insert(sortedIndex, key)
    end

    table.sort(sortedIndex, cross_type_sort)
    return sortedIndex
end

-- Equivalent of the next() function of table iteration, but returns the
-- keys in sorted order (see __gen_sorted_index and cross_type_sort).
-- The state is a temporary variable during iteration and contains the
-- sorted key table (state.sortedIdx). It also stores the last index (into
-- the keys) used by the iteration, to find the next one quickly.
local function next(state, control)
    local key

    -- print("next: control = "..tostring(control))
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

-- Equivalent of the pairs() function on tables. Allows to iterate in
-- sorted order. As required by "generic for" loops, this will return the
-- iterator (function), an "invariant state", and the initial control value.
-- (see http://www.lua.org/pil/7.2.html)
return function(tbl)
    return next, {t = tbl, sortedIdx = gen_index(tbl)}, nil
end
