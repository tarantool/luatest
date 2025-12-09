local fio = require('fio')
local t = require('luatest')
local utils = require('luatest.utils')
local ReplicaSet = require('luatest.replica_set')
local helper = require('test.helpers.general')

local g = t.group()
local Server = t.Server

local function build_specific_replica_set(alias_suffix)
    local rs = ReplicaSet:new()
    local box_cfg = {
        replication_timeout = 0.1,
        replication_connect_timeout = 1,
        replication_sync_lag = 0.01,
        replication_connect_quorum = 2,
    }

    local aliases = {
        ('replica1-%s'):format(alias_suffix),
        ('replica2-%s'):format(alias_suffix),
    }

    box_cfg = utils.merge(table.deepcopy(box_cfg), {
        replication = {
            Server.build_listen_uri(aliases[1], rs.id),
            Server.build_listen_uri(aliases[2], rs.id),
        },
    })

    for _, alias in ipairs(aliases) do
        rs:build_and_add_server({alias = alias, box_cfg = box_cfg})
    end
    return rs
end

local function get_replica_set_artifacts_path(rs)
    return ('%s/artifacts/%s'):format(rs._server.vardir, rs.id)
end

local function build_artifacts_paths(rs)
    local paths = {
        rs = get_replica_set_artifacts_path(rs),
        servers = {},
    }

    for _, server in ipairs(rs.servers) do
        table.insert(paths.servers, ('%s/%s'):format(paths.rs, server.id))
    end

    return paths
end

local function assert_artifacts_paths(paths)
    t.assert_equals(fio.path.exists(paths.rs), true)
    t.assert_equals(fio.path.is_dir(paths.rs), true)

    for _, server_path in ipairs(paths.servers) do
        t.assert_equals(fio.path.exists(server_path), true)
        t.assert_equals(fio.path.is_dir(server_path), true)
    end
end

g.test_foo = function()
    local paths

    local status = helper.run_suite(function(lu2)
        local cg = lu2.group()

        cg.before_all(function()
            cg.rs_all = build_specific_replica_set('all')
            cg.rs_all:start()
        end)

        cg.before_each(function()
            cg.rs_each = build_specific_replica_set('each')
            cg.rs_each:start()
        end)

        cg.before_test('test_failure', function()
            cg.rs_test = build_specific_replica_set('test')
            cg.rs_test:start()
        end)

        cg.test_failure = function()
            for _, rs in pairs({cg.rs_test, cg.rs_each, cg.rs_all}) do
                for _, server in pairs(rs.servers) do
                    server:exec(function() return true end)
                end
            end

            paths = {
                test = build_artifacts_paths(cg.rs_test),
                each = build_artifacts_paths(cg.rs_each),
                all = build_artifacts_paths(cg.rs_all),
            }

            lu2.fail('trigger artifact saving')
        end

        cg.after_test('test_failure', function()
            cg.rs_test:drop()
        end)

        cg.after_each(function()
            cg.rs_each:drop()
        end)

        cg.after_all(function()
            cg.rs_all:drop()
        end)
    end, {'--no-clean'})

    t.assert_equals(status, 1)

    assert_artifacts_paths(paths.test)
    assert_artifacts_paths(paths.each)
    assert_artifacts_paths(paths.all)
end
