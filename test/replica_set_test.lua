local fio = require('fio')
local t = require('luatest')
local ReplicaSet = require('luatest.replica_set')

local g = t.group()
local Server = t.Server

g.before_all(function()
    g.box_cfg = {
        replication_timeout = 0.1,
        replication_connect_timeout = 10,
        replication_sync_lag = 0.01,
        replication_connect_quorum = 3,
        replication = {
            Server.build_listen_uri('replica1'),
            Server.build_listen_uri('replica2'),
            Server.build_listen_uri('replica3'),
        }
    }
end)

g.before_test('test_save_rs_artifacts_when_test_failed', function()
    g.rs = ReplicaSet:new()

    g.rs:build_and_add_server({alias = 'replica1', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({alias = 'replica2', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({alias = 'replica3', box_cfg = g.box_cfg})

    g.rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, g.rs.id)
    g.s1_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica1').id)
    g.s2_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica2').id)
    g.s3_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica3').id)
end)

g.test_save_rs_artifacts_when_test_failed = function()
    local test = rawget(_G, 'current_test')
    -- the test must be failed to save artifacts
    test.status = 'fail'
    g.rs:drop()
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

g.before_test('test_save_rs_artifacts_when_server_workdir_passed', function()
    g.rs = ReplicaSet:new()

    local s1_workdir = ('%s/%s'):format(Server.vardir, os.tmpname())
    local s2_workdir = ('%s/%s'):format(Server.vardir, os.tmpname())
    local s3_workdir = ('%s/%s'):format(Server.vardir, os.tmpname())

    g.rs:build_and_add_server({workdir = s1_workdir, alias = 'replica1', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({workdir = s2_workdir, alias = 'replica2', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({workdir = s3_workdir, alias = 'replica3', box_cfg = g.box_cfg})

    g.rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, g.rs.id)
    g.s1_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica1').id)
    g.s2_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica2').id)
    g.s3_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica3').id)
end)

g.test_save_rs_artifacts_when_server_workdir_passed = function()
    local test = rawget(_G, 'current_test')
    -- the test must be failed to save artifacts
    test.status = 'fail'
    g.rs:drop()
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

g.before_test('test_remove_rs_artifacts_when_test_success', function()
    g.rs = ReplicaSet:new()

    g.rs:build_and_add_server({alias = 'replica1', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({alias = 'replica2', box_cfg = g.box_cfg})
    g.rs:build_and_add_server({alias = 'replica3', box_cfg = g.box_cfg})

    g.rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, g.rs.id)
    g.s1_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica1').id)
    g.s2_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica2').id)
    g.s3_artifacts = ('%s/%s'):format(g.rs_artifacts, g.rs:get_server('replica3').id)
end)

g.test_remove_rs_artifacts_when_test_success = function()
    g.rs:drop()

    t.assert_equals(fio.path.exists(g.rs.workdir), false)
end
