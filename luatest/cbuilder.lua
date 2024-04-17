--- Configuration builder.
--
-- It allows to construct a declarative configuration for a test case using
-- less boilerplace code/options, especially when a replicaset is to be
-- tested, not a single instance. All the methods support chaining (return
-- the builder object back).
--
-- @usage
--
-- local config = Builder:new()
--     :add_instance('instance-001', {
--         database = {
--             mode = 'rw',
--         },
--     })
--     :add_instance('instance-002', {})
--     :add_instance('instance-003', {})
--     :config()
--
-- By default, all instances are added to replicaset-001 in group-001,
-- but it's possible to select a different replicaset and/or group:
--
-- local config = Builder:new()
--     :use_group('group-001')
--     :use_replicaset('replicaset-001')
--     :add_instance(<...>)
--     :add_instance(<...>)
--     :add_instance(<...>)
--
--     :use_group('group-002')
--     :use_replicaset('replicaset-002')
--     :add_instance(<...>)
--     :add_instance(<...>)
--     :add_instance(<...>)
--
--     :config()
--
-- The default credentials and iproto options are added to
-- setup replication and to allow a test to connect to the
-- instances.
--
-- There is a few other methods:
--
-- * :set_replicaset_option('foo.bar', value)
-- * :set_instance_option('instance-001', 'foo.bar', value)
--
-- @classmod luatest.cbuilder

local checks = require('checks')
local fun = require('fun')

local Builder = require('luatest.class').new()

-- Do a post-reqiure of the `internal.config.cluster_config`,
-- since it is available from version 3.0.0+. Otherwise we
-- will get an error when initializing the module in `luatest.init`.
local cluster_config = {}

local base_config = {
    credentials = {
        users = {
            replicator = {
                password = 'secret',
                roles = {'replication'},
            },
            client = {
                password = 'secret',
                roles = {'super'},
            },
        },
    },
    iproto = {
        listen = {{
            uri = 'unix/:./{{ instance_name }}.iproto'
        }},
        advertise = {
            peer = {
                login = 'replicator',
            }
        },
    },
    replication = {
        -- The default value is 1 second. It is good for a real
        -- usage, but often suboptimal for testing purposes.
        --
        -- If an instance can't connect to another instance (say,
        -- because it is not started yet), it retries the attempt
        -- after so called 'replication interval', which is equal
        -- to replication timeout.
        --
        -- One second waiting means one more second for a test
        -- case and, if there are many test cases with a
        -- replicaset construction, it affects the test timing a
        -- lot.
        --
        -- replication.timeout = 0.1 second reduces the timing
        -- by half for my test.
        timeout = 0.1,
    },
}

function Builder:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

--- Build a config builder object.
--
-- @tab[opt] config Table with declarative configuration.
function Builder:new(config)
    checks('table', '?table')
    cluster_config = require('internal.config.cluster_config')

    config = table.deepcopy(config or base_config)
    self._config = config
    self._group = 'group-001'
    self._replicaset = 'replicaset-001'
    return self
end

--- Select a group for following calls.
--
-- @string group_name Group of replicas.
function Builder:use_group(group_name)
    checks('table', 'string')
    self._group = group_name
    return self
end

--- Select a replicaset for following calls.
--
-- @string replicaset_name Replica set name.
function Builder:use_replicaset(replicaset_name)
    checks('table', 'string')
    self._replicaset = replicaset_name
    return self
end

--- Set option to the cluster config.
--
-- @string path Option path.
-- @param value Option value (int, string, table).
function Builder:set_global_option(path, value)
    checks('table', 'string', '?')
    cluster_config:set(self._config, path, value)
    return self
end

--- Set an option for the selected group.
--
-- @string path Option path.
-- @param value Option value (int, string, table).
function Builder:set_group_option(path, value)
    checks('table', 'string', '?')
    path = fun.chain({
        'groups', self._group,
    }, path:split('.')):totable()

    cluster_config:set(self._config, path, value)
    return self
end

--- Set an option for the selected replicaset.
--
-- @string path Option path.
-- @param value Option value (int, string, table).
function Builder:set_replicaset_option(path, value)
    checks('table', 'string', '?')
    path = fun.chain({
        'groups', self._group,
        'replicasets', self._replicaset,
    }, path:split('.')):totable()

    -- <schema object>:set() validation is too tight. Workaround
    -- it. Maybe we should reconsider this :set() behavior in a
    -- future.
    if value == nil then
        local cur = self._config
        for i = 1, #path - 1 do
            -- Create missed fields.
            local component = path[i]
            if cur[component] == nil then
                cur[component] = {}
            end

            cur = cur[component]
        end
        cur[path[#path]] = value
        return self
    end

    cluster_config:set(self._config, path, value)
    return self
end

-- Set an option of a particular instance in the selected replicaset.
--
-- @string instance_name Instance where the option will be saved.
-- @string path Option path.
-- @param value Option value (int, string, table).
function Builder:set_instance_option(instance_name, path, value)
    checks('table', 'string', 'string', '?')
    path = fun.chain({
        'groups', self._group,
        'replicasets', self._replicaset,
        'instances', instance_name,
    }, path:split('.')):totable()

    cluster_config:set(self._config, path, value)
    return self
end

--- Add an instance with the given options to the selected replicaset.
--
-- @string instance_name Instance where the config will be saved.
-- @tab iconfig Declarative config for the instance.
function Builder:add_instance(instance_name, iconfig)
    checks('table', 'string', '?')
    local path = {
        'groups', self._group,
        'replicasets', self._replicaset,
        'instances', instance_name,
    }
    cluster_config:set(self._config, path, iconfig)
    return self
end

--- Return the resulting configuration.
--
function Builder:config()
    return self._config
end

return Builder
