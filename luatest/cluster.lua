--- Tarantool 3.0+ cluster management utils.
--
-- The helper is used to automatically collect a set of
-- instances from the provided configuration and automatically
-- set up servers per each configured instance.
--
-- @usage
--
-- local cluster = new(g, config)
-- cluster:start()
-- cluster['instance-001']:exec(<...>)
-- cluster:each(function(server)
--     server:exec(<...>)
-- end)
--
-- After setting up a cluster object the following methods could
-- be used to interact with it:
--
-- * :start() Startup the cluster.
-- * :start_instance() Startup a specific instance.
-- * :stop() Stop the cluster.
-- * :each() Execute a function on each instance.
-- * :size() get an amount of instances
-- * :drop() Drop the cluster.
-- * :sync() Sync the configuration and collect a new set of
--   instances
-- * :reload() Reload the configuration.
--
-- The module can also be used for testing failure startup
-- cases:
--
-- cluster.startup_error(g, config, error_message)
--
-- @module luatest.cluster

local fun = require('fun')
local yaml = require('yaml')
local assertions = require('luatest.assertions')
local helpers = require('luatest.helpers')
local hooks = require('luatest.hooks')
local treegen = require('luatest.treegen')
local justrun = require('luatest.justrun')
local server = require('luatest.server')

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
-- @tab self Cluster itself.
-- @func f Function to execute with a server as the first param.
local function cluster_each(self, f)
    fun.iter(self._servers):each(function(iserver)
        f(iserver)
    end)
end

--- Get cluster size.
-- @return number.
local function cluster_size(self)
    return #self._servers
end

--- Start all the instances.
--
-- @tab self Cluster itself.
-- @tab[opt] opts Cluster startup options.
-- @bool[opt] opts.wait_until_ready Wait until servers are ready
--   (default: false).
local function cluster_start(self, opts)
    self:each(function(iserver)
        iserver:start({wait_until_ready = false})
    end)

    -- wait_until_ready is true by default.
    local wait_until_ready = true
    if opts ~= nil and opts.wait_until_ready ~= nil then
        wait_until_ready = opts.wait_until_ready
    end

    if wait_until_ready then
        self:each(function(iserver)
            iserver:wait_until_ready()
        end)
    end

    -- wait_until_running is equal to wait_until_ready by default.
    local wait_until_running = wait_until_ready
    if opts ~= nil and opts.wait_until_running ~= nil then
        wait_until_running = opts.wait_until_running
    end

    if wait_until_running then
        self:each(function(iserver)
            helpers.retrying({timeout = 60}, function()
                assertions.assert_equals(iserver:eval('return box.info.status'),
                                         'running')
            end)

        end)
    end
end

--- Start the given instance.
--
-- @tab self Cluster itself.
-- @string instance_name Instance name.
local function cluster_start_instance(self, instance_name)
    local iserver = self._server_map[instance_name]
    assert(iserver ~= nil)
    iserver:start()
end

--- Stop the whole cluster.
--
-- @tab self Cluster itself.
local function cluster_stop(self)
    for _, iserver in ipairs(self._servers or {}) do
        iserver:stop()
    end
end

--- Drop the cluster's servers.
--
-- @tab self Cluster itself.
local function cluster_drop(self)
    for _, iserver in ipairs(self._servers or {}) do
        iserver:drop()
    end
    self._servers = nil
    self._server_map = nil
end

--- Sync the cluster object with the new config.
--
-- It performs the following actions.
--
-- * Write the new config into the config file.
-- * Update the internal list of instances.
--
-- @tab self Cluster itself.
-- @tab config New config.
local function cluster_sync(self, config)
    assert(type(config) == 'table')

    local instance_names = instance_names_from_config(config)

    treegen.write_file(self._dir, self._config_file_rel, yaml.encode(config))

    for i, name in ipairs(instance_names) do
        if self._server_map[name] == nil then
            local iserver = server:new(fun.chain(self._server_opts, {
                alias = name,
            }):tomap())
            table.insert(self._servers, i, iserver)
            self._server_map[name] = iserver
        end
    end

end

--- Reload configuration on all the instances.
--
-- @tab self Cluster itself.
-- @tab[opt] config New config.
local function cluster_reload(self, config)
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

local methods = {
    each = cluster_each,
    size = cluster_size,
    start = cluster_start,
    start_instance = cluster_start_instance,
    stop = cluster_stop,
    drop = cluster_drop,
    sync = cluster_sync,
    reload = cluster_reload,
}

local cluster_mt = {
    __index = function(self, k)
        if methods[k] ~= nil then
            return methods[k]
        end
        if self._server_map[k] ~= nil then
            return self._server_map[k]
        end
        return rawget(self, k)
    end
}

--- Create a new Tarantool cluster.
--
-- @tab g Group of tests.
-- @tab config Cluster configuration.
-- @tab[opt] server_opts Extra options passed to server:new().
-- @tab[opt] opts Cluster options.
-- @string[opt] opts.dir Specific directory for the cluster.
-- @return table
local function new(g, config, server_opts, opts)
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

    -- Create a cluster object and store it in 'g'.
    g._cluster = setmetatable({
        _servers = servers,
        _server_map = server_map,
        _dir = dir,
        _config_file_rel = config_file_rel,
        _server_opts = server_opts,
    }, cluster_mt)
    return g._cluster
end

-- }}} Replicaset management

-- {{{ Replicaset that can't start

--- Ensure cluster startup error
--
-- Starts a all instance of a cluster from the given config and
-- ensure that all the instances fails to start and reports the
-- given error message.
--
-- @tab g Group of tests.
-- @tab config Cluster configuration.
-- @string exp_err Expected error message.
local function startup_error(g, config, exp_err)
    assert(g)  -- temporary stub to not fail luacheck due to unused var
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

hooks.after_each_preloaded(drop)
hooks.after_all_preloaded(clean)

return {
    new = new,
    startup_error = startup_error,
}
