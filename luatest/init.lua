--- Tool for testing tarantool applications.
--
-- @module luatest
local luatest = setmetatable({}, {__index = require('luatest.assertions')})

luatest.Process = require('luatest.process')
luatest.VERSION = require('luatest.VERSION')

--- Helpers.
-- @see luatest.helpers
luatest.helpers = require('luatest.helpers')

--- Class to manage tarantool instances.
-- @see luatest.server
luatest.Server = require('luatest.server')

local Group = require('luatest.group')
local hooks = require('luatest.hooks')

--- Add before suite hook.
--
-- @function before_suite
-- @func fn

--- Add after suite hook.
--
-- @function after_suite
-- @func fn
hooks.define_suite_hooks(luatest)

luatest.groups = {}

--- Create group of tests.
--
-- @string[opt] name
-- @return Group object
-- @see luatest.group
function luatest.group(name)
    local group = Group:new(name)
    name = group.name
    if luatest.groups[name] then
        error('Test group already exists: ' .. name ..'.')
    end
    luatest.groups[name] = group
    return group
end

local runner_config = {}

--- Update default options.
-- See @{luatest.runner:run} for the list of available options.
--
-- @tab[opt={}] options list of options to update
-- @return options after update
function luatest.configure(options)
    for k, v in pairs(options or {}) do
        runner_config[k] = v
    end
    return runner_config
end

function luatest.defaults(...)
    require('log').warn('luatest.defaults is deprecated in favour of luatest.configure')
    return luatest.configure(...)
end

return luatest
