local t = require('luatest')
local utils = require('luatest.utils')

local Server = t.Server

local g = t.group()

g.test_foo = function()
    g.foo_test = rawget(_G, 'current_test').value
end

g.test_bar = function()
    g.bar_test = rawget(_G, 'current_test').value
end

g.after_all(function()
    g.s = Server:new()
    g.s:start()

    t.fail_if(
        utils.table_len(g.foo_test.servers) ~= 0,
        'Test instance `foo` should not contain a servers')

    t.fail_if(
        utils.table_len(g.bar_test.servers) ~= 0,
        'Test instance `bar` should not contain a servers')
end)
