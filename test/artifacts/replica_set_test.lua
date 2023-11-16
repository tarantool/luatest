local t = require('luatest')
local utils = require('luatest.utils')
local ReplicaSet = require('luatest.replica_set')

local g = t.group()

g.box_cfg = {
    replication_timeout = 0.1,
    replication_connect_timeout = 3,
    replication_sync_lag = 0.01,
    replication_connect_quorum = 3
}

g.rs = ReplicaSet:new()
g.rs:build_and_add_server({alias = 'replica1', box_cfg = g.box_cfg})
g.rs:build_and_add_server({alias = 'replica2', box_cfg = g.box_cfg})

g.test_foo = function()
    g.rs:start()
    g.foo_test = rawget(_G, 'current_test').value
end

g.test_bar = function()
    g.bar_test = rawget(_G, 'current_test').value
end

g.after_test('test_foo', function()
    t.fail_if(
        utils.table_len(g.foo_test.servers) ~= 2,
        'Test instance should contain all servers from replica set'
    )
    g.rs:drop()
end)

g.after_test('test_bar', function()
    t.fail_if(
        utils.table_len(g.bar_test.servers) ~= 0,
        'Test instance should not contain any servers'
    )
end)
