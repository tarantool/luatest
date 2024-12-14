local t = require('luatest')
local cbuilder = require('luatest.cbuilder')
local cluster = require('luatest.cluster')
local utils = require('luatest.utils')
local fio = require('fio')

local g = t.group()

local root = fio.dirname(fio.abspath('test.helpers'))

-- These are extra server opts passed to the cluster.
-- They are needed for the server to be able to access
-- luatest.coverage.
local server_opts = {
    env = {
        LUA_PATH = root .. '/?.lua;' ..
            root .. '/?/init.lua;' ..
            root .. '/.rocks/share/tarantool/?.lua',
    }
}

local function assert_instance_running(c, instance, replicaset)
    local server = c[instance]
    t.assert(type(server) == 'table')

    t.assert_equals(server:eval('return box.info.name'), instance)

    if replicaset ~= nil then
        t.assert_equals(server:eval('return box.info.replicaset.name'),
                        replicaset)
    end
end

local function assert_instance_stopped(c, instance)
    local server = c[instance]
    t.assert(type(server) == 'table')
    t.assert_is(server.process, nil)
end

g.test_start_stop = function()
    local function assert_instance_is_ro(c, instance, is_ro)
        local server = c[instance]
        t.assert(type(server) == 'table')

        t.assert_equals(server:eval('return box.info.ro'), is_ro)
    end

    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local config = cbuilder:new()
        :use_group('group-a')
        :use_replicaset('replicaset-x')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('leader', 'instance-x1')
        :add_instance('instance-x1', {})
        :add_instance('instance-x2', {})

        :use_group('group-b')
        :use_replicaset('replicaset-y')
        :set_replicaset_option('replication.failover', 'manual')
        :set_replicaset_option('leader', 'instance-y1')
        :add_instance('instance-y1', {})
        :add_instance('instance-y2', {})

        :config()

    local c = cluster:new(config, server_opts)
    c:start()

    assert_instance_running(c, 'instance-x1', 'replicaset-x')
    assert_instance_running(c, 'instance-x2', 'replicaset-x')
    assert_instance_running(c, 'instance-y1', 'replicaset-y')
    assert_instance_running(c, 'instance-y2', 'replicaset-y')

    assert_instance_is_ro(c, 'instance-x1', false)
    assert_instance_is_ro(c, 'instance-x2', true)
    assert_instance_is_ro(c, 'instance-y1', false)
    assert_instance_is_ro(c, 'instance-y2', true)

    c:stop()

    assert_instance_stopped(c, 'instance-x1')
    assert_instance_stopped(c, 'instance-x2')
    assert_instance_stopped(c, 'instance-y1')
    assert_instance_stopped(c, 'instance-y2')
end

g.test_start_instance = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    t.assert_equals(g.cluster, nil)

    local config = cbuilder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :use_replicaset('r-002')
        :add_instance('i-002', {})

        :use_group('g-002')
        :use_replicaset('r-003')
        :add_instance('i-003', {})

        :config()

    local c = cluster:new(config, server_opts)

    t.assert_equals(c:size(), 3)
    c:start_instance('i-002')

    assert_instance_running(c, 'i-002')

    assert_instance_stopped(c, 'i-001')
    assert_instance_stopped(c, 'i-003')

    c:stop()

    assert_instance_stopped(c, 'i-002')
end

g.test_sync = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    t.assert_equals(g._cluster, nil)

    local config = cbuilder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :config()

    local c = cluster:new(config, server_opts)

    t.assert_equals(c:size(), 1)

    c:start()
    assert_instance_running(c, 'i-001')

    c:stop()
    assert_instance_stopped(c, 'i-001')

    local config2 = cbuilder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-002', {})

        :use_group('g-002')
        :use_replicaset('r-002')
        :add_instance('i-003', {})

        :config()

    c:sync(config2)

    t.assert_equals(c:size(), 3)

    c:start_instance('i-002')
    c:start_instance('i-003')
    assert_instance_running(c, 'i-002')
    assert_instance_running(c, 'i-003')

    c:stop()
    assert_instance_stopped(c, 'i-002')
    assert_instance_stopped(c, 'i-003')
end

g.test_reload = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local function assert_instance_failover_mode(c, instance, mode)
        local server = c._server_map[instance]
        t.assert_equals(
            server:eval('return require("config"):get("replication.failover")'),
            mode)
    end

    t.assert_equals(g._cluster, nil)

    local config = cbuilder:new()
        :set_global_option('replication.failover', 'election')
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :add_instance('i-002', {})

        :use_replicaset('r-002')
        :add_instance('i-003', {})

        :config()

    local c = cluster:new(config, server_opts)
    c:start()

    assert_instance_failover_mode(c, 'i-001', 'election')
    assert_instance_failover_mode(c, 'i-002', 'election')
    assert_instance_failover_mode(c, 'i-003', 'election')

    local config2 = cbuilder:new(config)
        :set_global_option('replication.failover', 'off')
        :config()

    c:reload(config2)

    assert_instance_failover_mode(c, 'i-001', 'off')
    assert_instance_failover_mode(c, 'i-002', 'off')
    assert_instance_failover_mode(c, 'i-003', 'off')
end

g.test_each = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local config = cbuilder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :add_instance('i-002', {})

        :use_replicaset('r-002')
        :add_instance('i-003', {})

        :config()

    local c = cluster:new(config, server_opts)

    local res = {}
    c:each(function(server)
        table.insert(res, server.alias)
    end)

    t.assert_items_equals(res, {'i-001', 'i-002', 'i-003'})
end

g.test_startup_error = function()
    t.run_only_if(utils.version_current_ge_than(3, 0, 0),
                  [[Declarative configuration works on Tarantool 3.0.0+.
                    See tarantool/tarantool@13149d65bc9d for details]])

    local config = cbuilder:new()
        :use_group('g-001')
        :use_replicaset('r-001')
        :add_instance('i-001', {})
        :set_global_option('app.file', 'non-existent.lua')
        :config()

    cluster:startup_error(config, 'No such file')
end
