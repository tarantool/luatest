local t = require('luatest')
local g = t.group()

g.test_pretystr = function()
    local subject = t.prettystr
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
