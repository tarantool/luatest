local fio = require('fio')
local t = require('luatest')
local helper = require('test.helpers.general')
local ReplicaSet = require('luatest.replica_set')

local g = t.group()
local Server = t.Server
local deferred_artifact_checks = {}

local function build_box_cfg(rs)
    return {
        replication_timeout = 0.1,
        replication_connect_timeout = 10,
        replication_sync_lag = 0.01,
        replication_connect_quorum = 3,
        replication = {
            Server.build_listen_uri('replica1', rs.id),
            Server.build_listen_uri('replica2', rs.id),
            Server.build_listen_uri('replica3', rs.id),
        }
    }
end

g.before_each(function()
    g.rs = ReplicaSet:new()
    g.box_cfg = build_box_cfg(g.rs)
end)

g.test_save_rs_artifacts_when_test_failed = function()
    local artifact_paths

    local status = helper.run_suite(function(luatest)
        local cg = luatest.group()

        cg.before_test('test_failure', function()
            cg.rs = ReplicaSet:new()
            local box_cfg = build_box_cfg(cg.rs)

            cg.rs:build_and_add_server({alias = 'replica1', box_cfg = box_cfg})
            cg.rs:build_and_add_server({alias = 'replica2', box_cfg = box_cfg})
            cg.rs:build_and_add_server({alias = 'replica3', box_cfg = box_cfg})
            cg.rs:start()

            local rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, cg.rs.id)
            artifact_paths = {
                rs = rs_artifacts,
                servers = {
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica1').id),
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica2').id),
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica3').id),
                },
            }
        end)

        cg.test_failure = function()
            for _, server in pairs(cg.rs.servers) do
                server:exec(function() return true end)
            end

            luatest.fail('trigger artifact saving')
        end

        cg.after_test('test_failure', function()
            cg.rs:drop()
        end)
    end, {'--no-clean'})

    t.assert_equals(status, 1)

    table.insert(deferred_artifact_checks, function()
        t.assert_equals(fio.path.exists(artifact_paths.rs), true)
        t.assert_equals(fio.path.is_dir(artifact_paths.rs), true)

        for _, path in ipairs(artifact_paths.servers) do
            t.assert_equals(fio.path.exists(path), true)
            t.assert_equals(fio.path.is_dir(path), true)
        end
    end)
end

g.test_save_rs_artifacts_when_server_workdir_passed = function()
    local artifact_paths

    local status = helper.run_suite(function(luatest)
        local cg = luatest.group()

        cg.before_test('test_failure', function()
            cg.rs = ReplicaSet:new()
            local box_cfg = build_box_cfg(cg.rs)

            cg.rs:build_and_add_server({
                workdir = ('%s/%s'):format(Server.vardir, os.tmpname()),
                alias = 'replica1',
                box_cfg = box_cfg,
            })
            cg.rs:build_and_add_server({
                workdir = ('%s/%s'):format(Server.vardir, os.tmpname()),
                alias = 'replica2',
                box_cfg = box_cfg,
            })
            cg.rs:build_and_add_server({
                workdir = ('%s/%s'):format(Server.vardir, os.tmpname()),
                alias = 'replica3',
                box_cfg = box_cfg,
            })
            cg.rs:start()

            local rs_artifacts = ('%s/artifacts/%s'):format(Server.vardir, cg.rs.id)
            artifact_paths = {
                rs = rs_artifacts,
                servers = {
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica1').id),
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica2').id),
                    ('%s/%s'):format(rs_artifacts, cg.rs:get_server('replica3').id),
                },
            }
        end)

        cg.test_failure = function()
            for _, server in pairs(cg.rs.servers) do
                server:exec(function() return true end)
            end

            luatest.fail('trigger artifact saving')
        end

        cg.after_test('test_failure', function()
            cg.rs:drop()
        end)
    end, {'--no-clean'})

    t.assert_equals(status, 1)

    table.insert(deferred_artifact_checks, function()
        t.assert_equals(fio.path.exists(artifact_paths.rs), true)
        t.assert_equals(fio.path.is_dir(artifact_paths.rs), true)

        for _, path in ipairs(artifact_paths.servers) do
            t.assert_equals(fio.path.exists(path), true)
            t.assert_equals(fio.path.is_dir(path), true)
        end
    end)
end

g.after_each(function()
    g.rs:drop()
end)

g.after_all(function()
    for _, check in ipairs(deferred_artifact_checks) do
        check()
    end
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

g.test_rs_custom_properties_are_not_overridden = function()
    local socket = ('%s/custom.sock'):format(Server.vardir)
    local workdir = ('%s/custom'):format(Server.vardir)

    local s = g.rs:build_server({net_box_uri = socket, workdir = workdir})

    t.assert_equals(s.net_box_uri, socket)
    t.assert_equals(s.workdir, workdir)
end

g.after_test('test_rs_custom_properties_are_not_overridden', function()
    g.rs:drop()
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
