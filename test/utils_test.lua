local t = require('luatest')
local g = t.group()

local utils = require('luatest.utils')

g.test_is_tarantool_binary = function()
    local cases = {
        {'/usr/bin/tarantool', true},
        {'/usr/local/bin/tarantool', true},
        {'/usr/local/bin/tt', false},
        {'/usr/bin/ls', false},
        {'/home/myname/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/go-server', false},
        {'/usr/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
        {'/home/tarantool/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
    }

    for _, case in ipairs(cases) do
        local path, result = unpack(case)
        t.assert_equals(utils.is_tarantool_binary(path), result,
                        ("Unexpected result for %q"):format(path))
    end
end

g.test_table_pack = function()
    t.assert_equals(utils.table_pack(), {n = 0})
    t.assert_equals(utils.table_pack(1), {n = 1, 1})
    t.assert_equals(utils.table_pack(1, 2), {n = 2, 1, 2})
    t.assert_equals(utils.table_pack(1, 2, nil), {n = 3, 1, 2})
    t.assert_equals(utils.table_pack(1, 2, nil, 3), {n = 4, 1, 2, nil, 3})
end
