local t = require('luatest')
local g = t.group()

local helper = require('test.helpers.general')
local clock = require('clock')

local pp = require('luatest.pp')

g.test_tostring = function()
    local subject = pp.tostring
    t.assert_equals(subject({['a-b'] = 1, ab = 2, [10] = 10}), '{[10] = 10, ["a-b"] = 1, ab = 2}')

    local large_table = {}
    local expected_large_format = {'{'}
    for i = 0, 9 do
        large_table['a' .. i] = i
        table.insert(expected_large_format, string.format('    a%d = %d,', i, i))
    end
    table.insert(expected_large_format, '}')
    t.assert_equals(subject(large_table), table.concat(expected_large_format, '\n'))
end

g.test_tostring_huge_table = function()
    local str_table = {}
    for _ = 1, 15000 do table.insert(str_table, 'a') end
    local str = table.concat(str_table, '\n')
    local start = clock.time()
    local result = helper.run_suite(function(lu2)
        lu2.group().test = function() t.skip(str) end
    end)
    t.assert_equals(result, 0)
    t.assert_almost_equals(clock.time() - start, 0, 0.5)
end
