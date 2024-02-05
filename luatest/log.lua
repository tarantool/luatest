local tarantool_log = require('log')

local utils = require('luatest.utils')
local pp = require('luatest.pp')

-- Utils for logging
local log = {}
local default_level = 'info'

local function _log(level, msg, ...)
    if not utils.version_current_ge_than(2, 5, 1) then
        return
    end
    local args = {...}
    for k, v in pairs(args) do
        args[k] = pp.tostringlog(v)
    end
    return tarantool_log[level](msg, unpack(args))
end

--- Extra wrapper for `__call` function
-- An additional function that takes `table` as
-- the first argument to call table function.
local function _log_default(t, msg, ...)
    return t[default_level](msg, ...)
end

function log.info(msg, ...)
    return _log('info', msg, ...)
end

function log.verbose(msg, ...)
    return _log('verbose', msg, ...)
end

function log.debug(msg, ...)
    return _log('debug', msg, ...)
end

function log.warn(msg, ...)
    return _log('warn', msg, ...)
end

function log.error(msg, ...)
    return _log('error', msg, ...)
end

setmetatable(log, {__call = _log_default})

return log
