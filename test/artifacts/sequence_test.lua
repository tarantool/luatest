local t = require('luatest')
local utils = require('luatest.utils')

local g = t.group()
local Server = t.Server

g.s = Server:new()
g.s:start()

g.before_each(function()
    g.each = Server:new()
    g.each:start()
end)

g.test_foo = function()
    g.foo_test = rawget(_G, 'current_test').value
    g.foo_test_server = g.each.id
end

g.test_bar = function()
    g.bar_test = rawget(_G, 'current_test').value
    g.bar_test_server = g.each.id
end

g.after_test('test_foo', function()
    t.fail_if(
        utils.table_len(g.foo_test.servers) ~= 1,
        'Test instance should contain server')
end)

g.after_test('test_bar', function()
    t.fail_if(
        utils.table_len(g.bar_test.servers) ~= 1,
        'Test instance should contain server')
end)

g.after_all(function()
    t.fail_if(
        g.foo_test_server == g.bar_test_server,
        'Servers must be unique within the group'
    )
end)
