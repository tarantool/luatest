local fun = require('fun')
local json = require('json')

local TIMEOUT_INFINITY = 500 * 365 * 86400

local function default_cfg()
    return {
        work_dir = os.getenv('TARANTOOL_WORKDIR'),
        listen = os.getenv('TARANTOOL_LISTEN'),
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

local credentials = os.getenv('TARANTOOL_CREDENTIALS')
if credentials ~= nil then
    credentials = json.decode(credentials)
    assert(type(credentials) == 'table')
    assert(type(credentials.user) == 'string')
    assert(credentials.password == nil or
           type(credentials.password) == 'string')
else
    credentials = {user = 'guest'}
end
-- Users 'admin' and 'guest' are predefined.
if credentials.user ~= 'admin' and credentials.user ~= 'guest' then
    box.schema.user.create(credentials.user, {if_not_exists = true})
end
-- User 'admin' has all privileges so it does not need role 'super'.
if credentials.user ~= 'admin' then
    box.schema.user.grant(credentials.user, 'super', nil, nil,
                          {if_not_exists = true})
end
-- User 'guest' doesn't require authentication.
if credentials.user ~= 'guest' then
    if next(box.space._user.index.name:get(credentials.user).auth) == nil then
        box.schema.user.passwd(credentials.user, credentials.password or '')
    end
end

-- server:wait_until_ready() unblocks only when this variable becomes `true`.
-- In this case, it is considered that the instance is fully operable.
-- Use server:start({wait_until_ready = false}) to not wait for setting this
-- variable.
_G.ready = true
