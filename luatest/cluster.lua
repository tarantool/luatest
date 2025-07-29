--- Tarantool 3.0+ cluster management utils.
--
-- The helper is used to automatically collect a set of
-- instances from the provided configuration and automatically
-- set up servers per each configured instance.
--
-- @usage
--
-- local cluster = Cluster:new(config)
-- cluster:start()
-- cluster['instance-001']:exec(<...>)
-- cluster:each(function(server)
--     server:exec(<...>)
-- end)
--
-- -- After setting up a cluster object the following methods
-- -- could be used to interact with it:
-- -- * :start() Startup the cluster.
-- -- * :start_instance() Startup a specific instance.
-- -- * :stop() Stop the cluster.
-- -- * :each() Execute a function on each instance.
-- -- * :size() get an amount of instances
-- -- * :drop() Drop the cluster.
-- -- * :sync() Sync the configuration and collect a new set of
-- -- instances
-- -- * :reload() Reload the configuration.
--
-- -- The module can also be used for testing failure startup
-- -- cases:
--
-- Cluster.startup_error(config, "something went wrong")
--
-- @classmod luatest.cluster

local fun = require('fun')
local yaml = require('yaml')
local assertions = require('luatest.assertions')
local helpers = require('luatest.helpers')
local hooks = require('luatest.hooks')
local treegen = require('luatest.treegen')
local justrun = require('luatest.justrun')
local server = require('luatest.server')

local Cluster = require('luatest.class').new()

-- Cluster uses custom __index implementation to support
-- getting instances from it using `cluster['i-001']`.
--
-- Thus, we need to change the metatable of the class
-- with a custom __index method.
local mt = getmetatable(Cluster)
mt.__index = function(self, k)
    local method = rawget(mt, k)
    if method ~= nil then
        return method
    end

    local server_map = rawget(self, '_server_map')
    if server_map ~= nil and server_map[k] ~= nil then
        return server_map[k]
    end

    return rawget(self, k)
end

local cluster = {
    _group = {}
}

function Cluster:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

local function init(g)
    cluster._group = g
end

-- Stop all the managed instances using <server>:drop().
local function drop(g)
    if g._cluster ~= nil then
        g._cluster:drop()
    end
    g._cluster = nil
end

local function clean(g)
    assert(g._cluster == nil)
end

-- {{{ Helpers

-- Start all instances in the list.
--
-- @tab[opt] opts Options.
-- @bool[opt] opts.wait_until_ready Wait until servers are ready
--   (default: true).
-- @bool[opt] opts.wait_until_running Wait until servers are running
--   (default: wait_until_ready).
local function start_instances(servers, opts)
    for _, iserver in ipairs(servers) do
        iserver:start({wait_until_ready = false})
    end

    -- wait_until_ready is true by default.
    local wait_until_ready = true
    if opts ~= nil and opts.wait_until_ready ~= nil then
        wait_until_ready = opts.wait_until_ready
    end

    if wait_until_ready then
        for _, iserver in ipairs(servers) do
            iserver:wait_until_ready()
        end
    end

    -- wait_until_running is equal to wait_until_ready by default.
    local wait_until_running = wait_until_ready
    if opts ~= nil and opts.wait_until_running ~= nil then
        wait_until_running = opts.wait_until_running
    end

    if wait_until_running then
        for _, iserver in ipairs(servers) do
            helpers.retrying({timeout = 60}, function()
                assertions.assert_equals(iserver:eval('return box.info.status'),
                                         'running')
            end)
        end
    end
end

-- Collect names of all the instances defined in the config
-- in the alphabetical order.
local function instance_names_from_config(config)
    local instance_names = {}
    for _, group in pairs(config.groups or {}) do
        for _, replicaset in pairs(group.replicasets or {}) do
            for name, _ in pairs(replicaset.instances or {}) do
                table.insert(instance_names, name)
            end
        end
    end
    table.sort(instance_names)
    return instance_names
end

-- }}} Helpers

-- {{{ Cluster management

--- Execute for server in the cluster.
--
-- @func f Function to execute with a server as the first param.
function Cluster:each(f)
    fun.iter(self._servers):each(function(iserver)
        f(iserver)
    end)
end

--- Get cluster size.
--
-- @return number.
function Cluster:size()
    return #self._servers
end

--- Start all the instances.
--
-- @tab[opt] opts Cluster startup options.
-- @bool[opt] opts.wait_until_ready Wait until servers are ready
--   (default: true).
-- @bool[opt] opts.wait_until_running Wait until servers are running
--   (default: wait_until_ready).
function Cluster:start(opts)
    start_instances(self._servers, opts)
end

--- Start the given instance.
--
-- @string instance_name Instance name.
function Cluster:start_instance(instance_name)
    local iserver = self._server_map[instance_name]
    assert(iserver ~= nil)
    iserver:start()
end

--- Stop the whole cluster.
function Cluster:stop()
    for _, iserver in ipairs(self._servers or {}) do
        iserver:stop()
    end
end

--- Drop the cluster's servers.
function Cluster:drop()
    for _, iserver in ipairs(self._servers or {}) do
        iserver:drop()
    end
    for _, iserver in ipairs(self._expelled_servers or {}) do
        iserver:drop()
    end
    self._servers = nil
    self._server_map = nil
    self._expelled_servers = nil
end

--- Sync the cluster object with the new config.
--
-- It performs the following actions.
--
-- * Write the new config into the config file.
-- * Update the internal list of instances.
-- * Optionally starts instances added to the config and stops instances
--   removed from the config.
--
-- @tab config New config.
-- @tab[opt] opts Options.
-- @bool[opt] opts.start_stop Start/stop added/removed servers
--   (default: false).
-- @bool[opt] opts.wait_until_ready Wait until servers are ready
--   (default: true; used only if start_stop is set).
-- @bool[opt] opts.wait_until_running Wait until servers are running
--   (default: wait_until_ready; used only if start_stop is set).
function Cluster:sync(config, opts)
    assert(type(config) == 'table')

    local instance_names = instance_names_from_config(config)

    treegen.write_file(self._dir, self._config_file_rel, yaml.encode(config))

    local server_map = self._server_map
    self._server_map = {}
    self._servers = {}
    local new_servers = {}

    for _, name in ipairs(instance_names) do
        local iserver = server_map[name]
        if iserver == nil then
            iserver = server:new(fun.chain(self._server_opts, {
                alias = name,
            }):tomap())
            table.insert(new_servers, iserver)
        else
            server_map[name] = nil
        end
        self._server_map[name] = iserver
        table.insert(self._servers, iserver)
    end

    local expelled_servers = {}
    for _, iserver in pairs(server_map) do
        table.insert(expelled_servers, iserver)
    end

    -- Sort expelled servers by name for reproducibility.
    table.sort(expelled_servers, function(a, b) return a.alias < b.alias end)

    -- Add expelled servers to the list to be dropped with the cluster.
    for _, iserver in pairs(expelled_servers) do
        table.insert(self._expelled_servers, iserver)
    end

    local start_stop = false
    if opts ~= nil and opts.start_stop ~= nil then
        start_stop = opts.start_stop
    end

    if start_stop then
        start_instances(new_servers, opts)
        for _, iserver in ipairs(expelled_servers) do
            iserver:stop()
        end
    end
end

--- Reload configuration on all the instances.
--
-- @tab[opt] config New config.
function Cluster:reload(config)
    assert(config == nil or type(config) == 'table')

    -- Rewrite the configuration file if a new config is provided.
    if config ~= nil then
        treegen.write_file(self._dir, self._config_file_rel,
                           yaml.encode(config))
    end

    -- Reload config on all the instances.
    self:each(function(iserver)
        -- Assume that all the instances are started.
        --
        -- This requirement may be relaxed if needed, it is just
        -- for simplicity.
        assert(iserver.process ~= nil)

        iserver:exec(function()
            local cfg = require('config')

            cfg:reload()
        end)
    end)
end

--- Create a new Tarantool cluster.
--
-- @tab config Cluster configuration.
-- @tab[opt] server_opts Extra options passed to server:new().
-- @tab[opt] opts Cluster options.
-- @string[opt] opts.dir Specific directory for the cluster.
-- @return table
function Cluster:new(config, server_opts, opts)
    local g = cluster._group

    assert(type(config) == 'table')
    assert(config._config == nil, "Please provide cbuilder:new():config()")
    assert(g._cluster == nil)

    -- Prepare a temporary directory and write a configuration
    -- file.
    local dir = opts and opts.dir or treegen.prepare_directory({}, {})
    local config_file_rel = 'config.yaml'
    local config_file = treegen.write_file(dir, config_file_rel,
                                           yaml.encode(config))

    -- Collect names of all the instances defined in the config
    -- in the alphabetical order.
    local instance_names = instance_names_from_config(config)

    assert(next(instance_names) ~= nil, 'No instances in the supplied config')

    -- Generate luatest server options.
    server_opts = fun.chain({
        config_file = config_file,
        chdir = dir,
        net_box_credentials = {
            user = 'client',
            password = 'secret',
        },
    }, server_opts or {}):tomap()

    -- Create luatest server objects.
    local servers = {}
    local server_map = {}
    for _, name in ipairs(instance_names) do
        local iserver = server:new(fun.chain(server_opts, {
            alias = name,
        }):tomap())
        table.insert(servers, iserver)
        server_map[name] = iserver
    end

    -- Store a cluster object in 'g'.
    self._servers = servers
    self._server_map = server_map
    self._expelled_servers = {}
    self._dir = dir
    self._config_file_rel = config_file_rel
    self._server_opts = server_opts

    g._cluster = self

    return self
end

-- }}} Replicaset management

-- {{{ Replicaset that can't start

--- Ensure cluster startup error
--
-- Starts a all instance of a cluster from the given config and
-- ensure that all the instances fails to start and reports the
-- given error message.
--
-- @tab config Cluster configuration.
-- @string exp_err Expected error message.
function Cluster:startup_error(config, exp_err)
    -- Stub for the linter, since self is unused though
    -- we need to be consistent with Cluster:new()
    assert(self)
    assert(type(config) == 'table')
    assert(config._config == nil, "Please provide cbuilder:new():config()")
    -- Prepare a temporary directory and write a configuration
    -- file.
    local dir = treegen.prepare_directory({}, {})
    local config_file_rel = 'config.yaml'
    local config_file = treegen.write_file(dir, config_file_rel,
                                           yaml.encode(config))

    -- Collect names of all the instances defined in the config
    -- in the alphabetical order.
    local instance_names = instance_names_from_config(config)

    for _, name in ipairs(instance_names) do
        local env = {}
        local args = {'--name', name, '--config', config_file}
        local opts = {nojson = true, stderr = true}
        local res = justrun.tarantool(dir, env, args, opts)

        assertions.assert_equals(res.exit_code, 1)
        assertions.assert_str_contains(res.stderr, exp_err)
    end
end

-- }}} Replicaset that can't start

hooks.before_all_preloaded(init)
hooks.after_each_preloaded(drop)
hooks.after_all_preloaded(clean)

return Cluster
