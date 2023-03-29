local fio = require('fio')
local t = require('luatest')
local utils = require('luatest.utils')
local ReplicaSet = require('luatest.replica_set')

local g = t.group()
local Server = t.Server

local function build_specific_replica_set(alias_suffix)
    local box_cfg = {
        replication_timeout = 0.1,
        replication_connect_timeout = 1,
        replication_sync_lag = 0.01,
        replication_connect_quorum = 3,
    }

    local s1_alias = ('replica1-%s'):format(alias_suffix)
    local s2_alias = ('replica2-%s'):format(alias_suffix)
    local s3_alias = ('replica3-%s'):format(alias_suffix)

    box_cfg = utils.merge(
        table.deepcopy(box_cfg),
        {
            replication ={
            Server.build_listen_uri(s1_alias),
            Server.build_listen_uri(s2_alias),
            Server.build_listen_uri(s3_alias)
    }})
    local rs = ReplicaSet:new()

    rs:build_and_add_server({alias = s1_alias, box_cfg = box_cfg})
    rs:build_and_add_server({alias = s2_alias, box_cfg = box_cfg})
    rs:build_and_add_server({alias = s3_alias, box_cfg = box_cfg})
    return rs
end

local function get_replica_set_artifacts_path(rs)
    return ('%s/artifacts/%s'):format(rs._server.vardir, rs.id)
end

local function get_server_artifacts_path_by_alias(rs, position, alias_node)
    local rs_artifacts = get_replica_set_artifacts_path(rs)
    return ('%s/%s'):format(
        rs_artifacts,
        rs:get_server(('replica%s-%s'):format(position, alias_node)).id)
end

local function assert_artifacts_paths(rs, alias_suffix)
    t.assert_equals(fio.path.exists(get_replica_set_artifacts_path(rs)), true)
    t.assert_equals(fio.path.is_dir(get_replica_set_artifacts_path(rs)), true)

    t.assert_equals(
        fio.path.exists(get_server_artifacts_path_by_alias(rs, 1, alias_suffix)), true)
    t.assert_equals(
        fio.path.is_dir(get_server_artifacts_path_by_alias(rs, 1, alias_suffix)), true)

    t.assert_equals(
        fio.path.exists(get_server_artifacts_path_by_alias(rs, 2, alias_suffix)), true)
    t.assert_equals(
        fio.path.is_dir(get_server_artifacts_path_by_alias(rs, 2, alias_suffix)), true)

    t.assert_equals(
        fio.path.exists(get_server_artifacts_path_by_alias(rs, 3, alias_suffix)), true)
    t.assert_equals(
        fio.path.is_dir(get_server_artifacts_path_by_alias(rs, 3, alias_suffix)), true)
end

g.before_all(function()
    g.rs_all = build_specific_replica_set('all')

    g.rs_all:start()
    g.rs_all:wait_for_fullmesh()
end)

g.before_each(function()
    g.rs_each = build_specific_replica_set('each')

    g.rs_each:start()
    g.rs_each:wait_for_fullmesh()
end)

g.before_test('test_foo', function()
    g.rs_test = build_specific_replica_set('test')

    g.rs_test:start()
    g.rs_test:wait_for_fullmesh()
end)

g.test_foo = function()
    local test = rawget(_G, 'current_test')

    test.status = 'fail'
    g.rs_test:drop()
    g.rs_each:drop()
    g.rs_all:drop()
    test.status = 'success'

    assert_artifacts_paths(g.rs_test, 'test')
    assert_artifacts_paths(g.rs_each, 'each')
    assert_artifacts_paths(g.rs_all, 'all')
end
