local tarantool_log = require('log')

local utils = require('luatest.utils')

-- Utils for logging
local log = {}
local default_level = 'info'

local function _log(level, msg, ...)
    if utils.version_current_ge_than(2, 5, 1) then
        return tarantool_log[level](msg, ...)
    end
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

function log.warn(msg, ...)
    return _log('warn', msg, ...)
end

function log.error(msg, ...)
    return _log('error', msg, ...)
end

setmetatable(log, {__call = _log_default})

return log
