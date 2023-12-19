local fio = require('fio')
local fun = require('fun')
local json = require('json')
local log = require('log')

local TIMEOUT_INFINITY = 500 * 365 * 86400

local function log_cfg()
    -- `log.cfg{}` is available since 2.5.1 version only. See more
    -- details at https://github.com/tarantool/tarantool/issues/689.
    if log.cfg ~= nil then
        -- Logging may be initialized before `box.cfg{}` call:
        --
        --     server:new({
        --         env = {['TARANTOOL_RUN_BEFORE_BOX_CFG'] = [[
        --             require('log').cfg{ log = <custom_log_file> }
        --         ]]})
        --
        -- This causes the `Can't set option 'log' dynamically` error,
        -- so we need to return the old log file path.
        if log.cfg.log ~= nil then
            return log.cfg.log
        end
    end
    local log_file = fio.pathjoin(
        os.getenv('TARANTOOL_WORKDIR'),
        os.getenv('TARANTOOL_ALIAS') .. '.log'
    )
    -- When `box.cfg.log` is called, we may get a string like
    --
    --     | tee ${TARANTOOL_WORKDIR}/${TARANTOOL_ALIAS}.log
    --
    -- Some tests or functions (e.g. Server:grep_log) may request the
    -- log file path, so we save it to a global variable. Thus it can
    -- be obtained by `rawget(_G, 'box_cfg_log_file')`.
    rawset(_G, 'box_cfg_log_file', log_file)

    local unified_log_enabled = os.getenv('TARANTOOL_UNIFIED_LOG_ENABLED')
    if unified_log_enabled then
        -- Redirect the data stream to two sources at once:
        -- to the standard stream (stdout) and to the file
        -- ${TARANTOOL_WORKDIR}/${TARANTOOL_ALIAS}.log.
        return string.format('| tee %s', log_file)
    end
    return log_file
end

local function default_cfg()
    return {
        work_dir = os.getenv('TARANTOOL_WORKDIR'),
        listen = os.getenv('TARANTOOL_LISTEN'),
        log = log_cfg()
    }
end

local function env_cfg()
    local cfg = os.getenv('TARANTOOL_BOX_CFG')
    if cfg == nil then
        return {}
    end
    local res = json.decode(cfg)
    assert(type(res) == 'table')
    return res
end

local function box_cfg(cfg)
    return fun.chain(default_cfg(), env_cfg(), cfg or {}):tomap()
end

-- Set the shutdown timeout to infinity to catch tests that leave asynchronous
-- requests. With the default timeout of 3 seconds, such tests would still pass,
-- but slow down the overall test run, because the server would take longer to
-- stop. Setting the timeout to infinity makes such bad tests hang and fail.
if type(box.ctl.set_on_shutdown_timeout) == 'function' then
    box.ctl.set_on_shutdown_timeout(TIMEOUT_INFINITY)
end

local run_before_box_cfg = os.getenv('TARANTOOL_RUN_BEFORE_BOX_CFG')
if run_before_box_cfg then
    loadstring(run_before_box_cfg)()
end

box.cfg(box_cfg())

box.schema.user.grant('guest', 'super', nil, nil, {if_not_exists = true})

-- server:wait_until_ready() unblocks only when this variable becomes `true`.
-- In this case, it is considered that the instance is fully operable.
-- Use server:start({wait_until_ready = false}) to not wait for setting this
-- variable.
_G.ready = true
