local pp = require("luatest.pp")

local M = {}

-- Diff algorithm: Longest Common Subsequence (LCS).
-- See https://en.wikipedia.org/wiki/Longest_common_subsequence
local function diff_by_lines(text1, text2)
    local lines1 = string.split(text1, '\n')
    local lines2 = string.split(text2, '\n')

    local m = #lines1
    local n = #lines2
    local lcs = {}

    for i = 0, m do
        lcs[i] = {}
        lcs[i][0] = 0
    end

    for j = 0, n do
        lcs[0][j] = 0
    end

    for i = 1, m do
        for j = 1, n do
            if lines1[i] == lines2[j] then
                lcs[i][j] = lcs[i - 1][j - 1] + 1
            else
                local left = lcs[i - 1][j]
                local top = lcs[i][j - 1]
                lcs[i][j] = left >= top and left or top
            end
        end
    end

    local out = {}
    local i = m
    local j = n

    while i > 0 or j > 0 do
        if i > 0 and j > 0 and lines1[i] == lines2[j] then
            table.insert(out, 1, ' ' .. lines1[i])
            i = i - 1
            j = j - 1
        elseif j > 0 and (i == 0 or lcs[i][j - 1] >= lcs[i - 1][j]) then
            table.insert(out, 1, '+' .. lines2[j])
            j = j - 1
        else
            table.insert(out, 1, '-' .. lines1[i])
            i = i - 1
        end
    end

    return table.concat(out, '\n')
end

--- Build a simple line-by-line diff for expected and actual values
-- serialized to text. Returns nil when values can't be serialized
-- or there is no diff.
function M.build_line_diff(expected, actual)
    local old = pp.LINE_LENGTH
    pp.LINE_LENGTH = 0
    local expected_text = pp.tostring(expected)
    local actual_text = pp.tostring(actual)
    pp.LINE_LENGTH = old

    return diff_by_lines(expected_text, actual_text)
end

return M
