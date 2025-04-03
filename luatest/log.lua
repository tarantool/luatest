local checks = require('checks')
local fio = require('fio')
local tarantool_log = require('log')

local OutputBeautifier = require('luatest.output_beautifier')
local utils = require('luatest.utils')

-- Utils for logging
local log = {}
local default_level = 'info'
local is_initialized = false

function log.initialize(options)
    checks({
        vardir = 'string',
        log_file = '?string',
        log_prefix = '?string',
    })
    if is_initialized then
        return
    end

    local vardir = options.vardir
    local luatest_log_prefix = options.log_prefix or 'luatest'
    local luatest_log_file = fio.pathjoin(vardir, luatest_log_prefix .. '.log')
    local unified_log_file = options.log_file

    fio.mktree(vardir)

    if unified_log_file then
        -- Save the file descriptor as a global variable to use it in
        -- the `output_beautifier` module.
        local fh = fio.open(unified_log_file, {'O_CREAT', 'O_WRONLY', 'O_TRUNC'},
                            tonumber('640', 8))
        rawset(_G, 'log_file', {fh = fh})
    end

    local output_beautifier = OutputBeautifier:new({
        file = luatest_log_file,
        prefix = luatest_log_prefix,
    })
    output_beautifier:enable()

    -- Redirect all logs to the pipe created by OutputBeautifier.
    local log_cfg = string.format('/dev/fd/%d', output_beautifier.pipes.stdout[1])

    -- Logging cannot be initialized without configuring the `box` engine
    -- on a version less than 2.5.1 (see more details at [1]). Otherwise,
    -- this causes the `attempt to call field 'cfg' (a nil value)` error,
    -- so there are the following limitations:
    --     1. There is no `luatest.log` file (but logs are still available
    --        in stdout and in the `run.log` file);
    --     2. All logs from luatest are non-formatted and look like:
    --
    --        luatest | My log message
    --
    -- [1]: https://github.com/tarantool/tarantool/issues/689
    if utils.version_current_ge_than(2, 5, 1) then
        -- Initialize logging for luatest runner.
        -- The log format will be as follows:
        --     YYYY-MM-DD HH:MM:SS.ZZZ [ID] main/.../luatest I> ...
        require('log').cfg{log = log_cfg}
    end

    is_initialized = true
end

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
