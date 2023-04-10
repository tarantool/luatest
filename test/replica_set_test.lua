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

g.before_test('test_rs_no_socket_collision_with_custom_alias', function()
    g.rs = ReplicaSet:new()
end)

g.test_rs_no_socket_collision_with_custom_alias = function()
    local s1 = g.rs:build_server({alias = 'foo'})
    local s2 = g.rs:build_server({alias = 'bar'})

    t.assert(s1.vardir:find(g.rs.id, 1, true))
    t.assert(s2.vardir:find(g.rs.id, 1, true))
    t.assert_equals(s1.net_box_uri, ('%s/foo.sock'):format(s1.vardir))
    t.assert_equals(s2.net_box_uri, ('%s/bar.sock'):format(s2.vardir))
end

g.after_test('test_rs_no_socket_collision_with_custom_alias', function()
    g.rs:drop()
end)

g.before_test('test_rs_custom_properties_are_not_overridden', function()
    g.rs = ReplicaSet:new()
end)

g.test_rs_custom_properties_are_not_overridden = function()
    local socket = ('%s/custom.sock'):format(Server.vardir)
    local workdir = ('%s/custom'):format(Server.vardir)

    local s = g.rs:build_server({net_box_uri = socket, workdir=workdir})

    t.assert_equals(s.net_box_uri, socket)
    t.assert_equals(s.workdir, workdir)
end

g.after_test('test_rs_custom_properties_are_not_overridden', function()
    g.rs:drop()
end)

g.before_test('test_rs_raise_error_when_add_custom_server', function()
    g.rs = ReplicaSet:new()
end)

g.test_rs_raise_error_when_add_custom_server = function()
    local s = Server:new()

    t.assert_error_msg_contains(
        'Server should be built via `ReplicaSet:build_server` function',
        function() g.rs:add_server(s) end)
end

g.after_test('test_rs_raise_error_when_add_custom_server', function()
    g.rs:drop()
end)
