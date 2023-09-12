--- Class to manage groups of Tarantool instances with the same data set.
--
-- @classmod luatest.replica_set

local checks = require('checks')
local fio = require('fio')
local log = require('log')

local helpers = require('luatest.helpers')
local Server = require('luatest.server')
local utils = require('luatest.utils')

local ReplicaSet = {}

function ReplicaSet:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

--- Build a replica set object.
--
-- @tab[opt] object Table with the entries listed below. (optional)
-- @tab[opt] object.servers List of server configurations to build server
--   objects from and add them to the new replica set. See an example below.
-- @return table
-- @see luatest.server:new
-- @usage
--   local ReplicaSet = require('luatest.replica_set')
--   local Server = require('luatest.server')
--   local box_cfg = {
--       replication_timeout = 0.1,
--       replication_connect_timeout = 10,
--       replication_sync_lag = 0.01,
--       replication_connect_quorum = 3,
--       replication = {
--           Server.build_listen_uri('replica1'),
--           Server.build_listen_uri('replica2'),
--           Server.build_listen_uri('replica3'),
--       },
--   }
--   local replica_set = ReplicaSet:new({
--       servers = {
--           {alias = 'replica1', box_cfg = box_cfg},
--           {alias = 'replica2', box_cfg = box_cfg},
--           {alias = 'replica3', box_cfg = box_cfg},
--       }
--   })
--   replica_set:start()
--   replica_set:wait_for_fullmesh()
function ReplicaSet:new(object)
    if not object then object = {} end
    self:inherit(object)
    object:initialize()
    return object
end

-- Initialize the replica set object.
function ReplicaSet:initialize()
    self._server = Server

    self.alias = 'rs'
    self.id = ('%s-%s'):format(self.alias, utils.generate_id())
    self.workdir = fio.pathjoin(self._server.vardir, self.id)

    if self.servers then
        local configs = table.deepcopy(self.servers)
        self.servers = {}
        for _, config in ipairs(configs) do
            self:build_and_add_server(config)
        end
    else
        self.servers = {}
    end
end

--- Build a server object for the replica set.
--
-- @tab[opt] config Configuration for the new server.
-- @return table
-- @see luatest.server:new
function ReplicaSet:build_server(config)
    checks('table', self._server.constructor_checks)
    if config then config = table.deepcopy(config) end
    return self._server:new(config, {rs_id = self.id, vardir = self.workdir})
end

--- Add the server object to the replica set.
-- The added server object should be built via the `ReplicaSet:build_server`
-- function.
--
-- @tab server Server object to be added to the replica set.
function ReplicaSet:add_server(server)
    checks('table', 'table')
    if not server.rs_id then
        error('Server should be built via `ReplicaSet:build_server` function')
    end
    if self:get_server(server.alias) then
        error(('Server with alias "%s" already exists in replica set')
            :format(server.alias))
    end
    table.insert(self.servers, server)
end

--- Build a server object and add it to the replica set.
--
-- @tab[opt] config Configuration for the new server.
-- @return table
-- @see luatest.server:new
function ReplicaSet:build_and_add_server(config)
    checks('table', self._server.constructor_checks)
    local server = self:build_server(config)
    self:add_server(server)
    return server
end

--- Get the server object from the replica set by the given server alias.
--
-- @string alias Server alias.
-- @return table|nil
function ReplicaSet:get_server(alias)
    checks('table', 'string')
    for _, server in ipairs(self.servers) do
        if server.alias == alias then
            return server
        end
    end
    return nil
end

-- Get the index of the server object by the given server alias.
local function get_server_index_by_alias(servers, alias)
    for index, server in ipairs(servers) do
        if server.alias == alias then
            return index
        end
    end
    return nil
end

--- Delete the server object from the replica set by the given server alias.
--
-- @string alias Server alias.
function ReplicaSet:delete_server(alias)
    checks('table', 'string')
    local server_index = get_server_index_by_alias(self.servers, alias)
    if server_index then
        table.remove(self.servers, server_index)
    else
        log.warn(('Server with alias "%s" does not exist in replica set')
            :format(alias))
    end
end

--- Start all servers in the replica set.
-- Optionally waits until all servers are ready.
--
-- @tab[opt] opts Table with the entries listed below. (optional)
-- @bool[opt] opts.wait_until_ready Wait until all servers are ready.
--   Defaults to `true`.
function ReplicaSet:start(opts)
    checks('table', {wait_until_ready = '?boolean'})

    fio.mktree(self.workdir)

    for _, server in ipairs(self.servers) do
        if not server.process then
            server:start({wait_until_ready = false})
        end
    end

    if not opts or opts.wait_until_ready ~= false then
        for _, server in ipairs(self.servers) do
            server:wait_until_ready()
        end
    end
end

--- Stop all servers in the replica set.
function ReplicaSet:stop()
    for _, server in ipairs(self.servers) do
        server:stop()
    end
end

--- Stop all servers in the replica set and save their artifacts if the test fails.
-- This function should be used only at the end of the test (`after_test`,
-- `after_each`, `after_all` hooks) to terminate all server processes in
-- the replica set. Besides process termination, it saves the contents of
-- each server working directory to the `<vardir>/artifacts` directory
-- for further analysis if the test fails.
function ReplicaSet:drop()
    for _, server in ipairs(self.servers) do
        server:drop()
    end
end

--- Get a server which is a writable node in the replica set.
--
-- @return table
function ReplicaSet:get_leader()
    for _, server in ipairs(self.servers) do
        if server:exec(function() return box.info.ro end) == false then
            return server
        end
    end
end

--- Wait until every node is connected to every other node in the replica set.
--
-- @tab[opt] opts Table with the entries listed below. (optional)
-- @number[opt] opts.timeout Timeout in seconds to wait for full mesh.
--   Defaults to 60.
-- @number[opt] opts.delay Delay in seconds between attempts to check full mesh.
--   Defaults to 0.1.
function ReplicaSet:wait_for_fullmesh(opts)
    checks('table', {timeout = '?number', delay = '?number'})
    if not opts then opts = {} end
    local config = {timeout = opts.timeout or 60, delay = opts.delay or 0.1}
    helpers.retrying(config, function(replica_set)
        for _, server1 in ipairs(replica_set.servers) do
            for _, server2 in ipairs(replica_set.servers) do
                if server1 ~= server2 then
                    local server1_id = server1:get_instance_id()
                    local server2_id = server2:get_instance_id()
                    if server1_id ~= server2_id then
                        server1:assert_follows_upstream(server2_id)
                    else
                        -- If IDs are equal, nodes are anonymous replicas and
                        -- not registered yet. Raise an error to retry checking
                        -- full mesh again.
                        error()
                    end
                end
            end
        end
    end, self)
end

return ReplicaSet
