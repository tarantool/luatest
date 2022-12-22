local fio = require('fio')
local fun = require('fun')
local json = require('json')

local TIMEOUT_INFINITY = 500 * 365 * 86400

local function default_cfg()
    return {
        work_dir = os.getenv('TARANTOOL_WORKDIR'),
        listen = os.getenv('TARANTOOL_LISTEN'),
        log = fio.pathjoin(
            os.getenv('TARANTOOL_WORKDIR'),
            os.getenv('TARANTOOL_ALIAS') .. '.log'
        ),
        replication_sync_timeout = 300,
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
