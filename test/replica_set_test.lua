local fio = require('fio')
local t = require('luatest')
local ReplicaSet = require('luatest.replica_set')

local g = t.group()
local Server = t.Server

g.before_each(function()
    local box_cfg = {
        replication_timeout = 0.1,
        replication_connect_timeout = 10,
        replication_sync_lag = 0.01,
        replication_connect_quorum = 3,
        replication = {
            Server.build_listen_uri('replica1'),
            Server.build_listen_uri('replica2'),
            Server.build_listen_uri('replica3'),
        },
    }
    g.s1 = Server:new({alias = 'replica1', box_cfg = box_cfg})
    g.s2 = Server:new({alias = 'replica2', box_cfg = box_cfg})
    g.s3 = Server:new({alias = 'replica3', box_cfg = box_cfg})

    g.replica_set = ReplicaSet:new({})
    g.replica_set:add_server(g.s1)
    g.replica_set:add_server(g.s2)
    g.replica_set:add_server(g.s3)


    g.replica_set:start()
    g.replica_set:wait_for_fullmesh()

    g.rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, g.replica_set.alias)
    g.s1_artifacts = ('%s/%s-%s'):format(g.rs_artifacts, g.s1.alias, g.s1.id)
    g.s2_artifacts = ('%s/%s-%s'):format(g.rs_artifacts, g.s2.alias, g.s2.id)
    g.s3_artifacts = ('%s/%s-%s'):format(g.rs_artifacts, g.s3.alias, g.s3.id)
end)

g.test_save_rs_artifacts_when_test_failed = function()
    local test = rawget(_G, 'current_test')
    -- the test must be failed to save artifacts
    test.status = 'fail'
    g.replica_set:drop()
    test.status = 'success'

    t.assert_equals(fio.path.exists(g.rs_artifacts), true)
    t.assert_equals(fio.path.is_dir(g.rs_artifacts), true)

    t.assert_equals(fio.path.exists(g.s1_artifacts), true)
    t.assert_equals(fio.path.is_dir(g.s1_artifacts), true)

    t.assert_equals(fio.path.exists(g.s2_artifacts), true)
    t.assert_equals(fio.path.is_dir(g.s2_artifacts), true)

    t.assert_equals(fio.path.exists(g.s3_artifacts), true)
    t.assert_equals(fio.path.is_dir(g.s3_artifacts), true)
end

g.test_remove_rs_artifacts_when_test_success = function()
    g.replica_set:drop()

    t.assert_equals(fio.path.exists(g.replica_set.workdir), false)
end
