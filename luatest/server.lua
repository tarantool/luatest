--- Class to manage Tarantool instances.
--
-- @classmod luatest.server

local checks = require('checks')
local clock = require('clock')
local digest = require('digest')
local errno = require('errno')
local fiber = require('fiber')
local fio = require('fio')
local fun = require('fun')
local http_client = require('http.client')
local json = require('json')
local log = require('log')
local net_box = require('net.box')
local uri = require('uri')
local _, luacov_runner = pcall(require, 'luacov.runner') -- luacov may not be installed

local assertions = require('luatest.assertions')
local HTTPResponse = require('luatest.http_response')
local Process = require('luatest.process')
local utils = require('luatest.utils')

local DEFAULT_VARDIR = '/tmp/t'
local DEFAULT_ALIAS = 'server'
local DEFAULT_INSTANCE = fio.pathjoin(
    fio.dirname(fio.abspath(package.search('luatest.server'))), 'server_instance.lua'
)
local WAIT_TIMEOUT = 60
local WAIT_DELAY = 0.1

local Server = {
    constructor_checks = {
        command = '?string',
        workdir = '?string',
        datadir = '?string',
        chdir = '?string',
        env = '?table',
        args = '?table',
        box_cfg = '?table',

        http_port = '?number',
        net_box_port = '?number',
        net_box_uri = '?string',
        net_box_credentials = '?table',

        alias = '?string',

        coverage_report = '?boolean',
    },
}

Server.vardir = fio.abspath(os.getenv('VARDIR') or DEFAULT_VARDIR)

function Server:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

--- Build a server object.
--
-- @tab[opt] object Table with the entries listed below. (optional)
-- @string[opt] object.command Executable path to run a server process with.
--   Defaults to the internal `server_instance.lua` script. If a custom path
--   is provided, it should correctly process all env variables listed below
--   to make constructor parameters work.
-- @tab[opt] object.args Arbitrary args to run `object.command` with.
-- @tab[opt] object.env Pass the given env variables into the server process.
-- @string[opt] object.chdir Change to the given directory before running
--   the server process.
-- @string[opt] object.alias Alias for the new server and the value of the
--   `TARANTOOL_ALIAS` env variable which is passed into the server process.
--   Defaults to 'server'.
-- @string[opt] object.workdir Working directory for the new server and the
--   value of the `TARANTOOL_WORKDIR` env variable which is passed into the
--   server process.
--   Defaults to `<vardir>/<alias>-<random id>`.
-- @string[opt] object.datadir Directory path whose contents will be recursively
--   copied into `object.workdir` during initialization.
-- @number[opt] object.http_port Port for HTTP connection to the new server and
--   the value of the `TARANTOOL_HTTP_PORT` env variable which is passed into
--   the server process.
--   Not supported in the default `server_instance.lua` script.
-- @number[opt] object.net_box_port Port for the `net.box` connection to the new
--   server and the value of the `TARANTOOL_LISTEN` env variable which is passed
--   into the server process.
-- @string[opt] object.net_box_uri URI for the `net.box` connection to the new
--   server and the value of the `TARANTOOL_LISTEN` env variable which is passed
--   into the server process.
-- @tab[opt] object.net_box_credentials Override the default credentials for the
--   `net.box` connection to the new server.
-- @tab[opt] object.box_cfg Extra options for `box.cfg()` and the value of the
--   `TARANTOOL_BOX_CFG` env variable which is passed into the server process.
-- @return table
function Server:new(object)
    checks('table', self.constructor_checks)
    if not object then object = {} end
    self:inherit(object)
    object:initialize()
    return object
end

-- Initialize the server object.
function Server:initialize()
    if self.id == nil then
        self.id = digest.base64_encode(digest.urandom(9), {urlsafe = true})
    end

    if self.alias == nil then
        self.alias = DEFAULT_ALIAS
    end

    if self.command == nil then
        self.command = DEFAULT_INSTANCE
    end

    if self.workdir == nil then
        self.workdir = fio.pathjoin(self.vardir, ('%s-%s'):format(self.alias, self.id))
        fio.rmtree(self.workdir)
        fio.mktree(self.workdir)
    end

    if self.datadir ~= nil then
        local ok, err = fio.copytree(self.datadir, self.workdir)
        if not ok then
            error(('Failed to copy directory: %s'):format(err))
        end
        self.datadir = nil
    end

    if self.http_port then
        self.http_client = http_client.new()
    end

    if self.net_box_uri == nil and self.net_box_port == nil then
        self.net_box_uri = self.build_listen_uri(self.alias)
        fio.mktree(self.vardir)
    end
    if self.net_box_uri == nil and self.net_box_port then
        self.net_box_uri = 'localhost:' .. self.net_box_port
    end
    if uri.parse(self.net_box_uri).host == 'unix/' then
        -- Linux uses max 108 bytes for Unix domain socket paths, which means a 107 characters
        -- string ended by a null terminator. Other systems use 104 bytes and 103 characters strings.
        local max_unix_socket_path = {linux = 107, other = 103}
        local system = os.execute('[ $(uname) = Linux ]') == 0 and 'linux' or 'other'
        if self.net_box_uri:len() > max_unix_socket_path[system] then
            error(('Net box URI must be <= max Unix domain socket path length (%d chars)')
                :format(max_unix_socket_path[system]))
        end
    end

    self.env = utils.merge(self.env or {}, self:build_env())
    self.args = self.args or {}

    -- Enable coverage_report if it's enabled when server is instantiated
    -- and it's not disabled explicitly.
    if self.coverage_report == nil and luacov_runner and luacov_runner.initialized then
        self.coverage_report = true
    end
    if self.coverage_report then
        -- If command is executable lua script, run it with `tarantool -l luatest.coverage script.lua`
        if self.command:endswith('.lua') then
            table.insert(self.args, 1, '-l')
            table.insert(self.args, 2, 'luatest.coverage')
            table.insert(self.args, 3, self.command)
            self.command = arg[-1]
        -- If command is tarantool, add `-l luatest.coverage`
        elseif self.command:endswith('/tarantool') then
            if not fun.index('luatest.coverage', self.args) then
                table.insert(self.args, 1, '-l')
                table.insert(self.args, 2, 'luatest.coverage')
            end
        else
            log.warn('Luatest can not enable coverage report ' ..
                'for started process `' .. self.command .. '` ' ..
                'because it may appear not a Lua script. ' ..
                "Add `require('luatest.coverage')` to the program or " ..
                'pass `coverage_report = false` option to disable this warning.')
        end
        -- values set with os.setenv are not available with os.environ
        -- so set it explicitly:
        self.env.LUATEST_LUACOV_ROOT = os.getenv('LUATEST_LUACOV_ROOT')
    end
end

-- Create a table with env variables based on the constructor params.
-- The result will be passed into the server process.
-- Table consists of the following entries:
--
--   * `TARANTOOL_WORKDIR`
--   * `TARANTOOL_LISTEN`
--   * `TARANTOOL_ALIAS`
--   * `TARANTOOL_HTTP_PORT`
--   * `TARANTOOL_BOX_CFG`
--
-- @return table
function Server:build_env()
    local res = {
        TARANTOOL_WORKDIR = self.workdir,
        TARANTOOL_HTTP_PORT = self.http_port,
        TARANTOOL_LISTEN = self.net_box_port or self.net_box_uri,
        TARANTOOL_ALIAS = self.alias,
    }
    if self.box_cfg ~= nil then
        res.TARANTOOL_BOX_CFG = json.encode(self.box_cfg)
    end
    return res
end

--- Build a listen URI based on the given server alias.
-- For now, only UNIX sockets are supported.
--
-- @string server_alias Server alias.
-- @return string
function Server.build_listen_uri(server_alias)
    return fio.pathjoin(Server.vardir, server_alias .. '.sock')
end

--- Start a server.
-- Optionally waits until the server is ready.
--
-- @tab[opt] opts
-- @bool[opt] opts.wait_until_ready Wait until the server is ready.
--   Defaults to `true` unless a custom executable was provided while building
--   the server object.
function Server:start(opts)
    checks('table', {wait_until_ready = '?boolean'})

    self:initialize()

    local command = self.command
    local args = table.copy(self.args)
    local env = table.copy(os.environ())

    if not command:endswith('/tarantool') then
        -- When luatest is installed as a rock, the internal server_instance.lua
        -- script won't have execution permissions even though it has them in the
        -- source tree, and won't be able to be run while a server start. To bypass
        -- this issue, we start a server process as `tarantool /path/to/script.lua`
        -- instead of just `/path/to/script.lua`.
        table.insert(args, 1, command)
        command = arg[-1]
    end

    local log_cmd = {}
    for k, v in pairs(self.env) do
        table.insert(log_cmd, string.format('%s=%q', k, v))
        env[k] = v
    end
    table.insert(log_cmd, command)
    for _, v in ipairs(args) do
        table.insert(log_cmd, string.format('%q', v))
    end
    log.debug(table.concat(log_cmd, ' '))

    self.process = Process:start(command, args, env, {
        chdir = self.chdir,
        output_prefix = self.alias,
    })

    local wait_until_ready = self.command == DEFAULT_INSTANCE
    if opts ~= nil and opts.wait_until_ready ~= nil then
        wait_until_ready = opts.wait_until_ready
    end
    if wait_until_ready then
        self:wait_until_ready()
    end

    log.debug('Started server PID: ' .. self.process.pid)
end

--- Restart the server with the given parameters.
-- Optionally waits until the server is ready.
--
-- @tab[opt] params Parameters to restart the server with.
--   Like `command`, `args`, `env`, etc.
-- @tab[opt] opts
-- @bool[opt] opts.wait_until_ready Wait until the server is ready.
--   Defaults to `true` unless a custom executable path was provided while
--   building the server object.
-- @see luatest.server:new
function Server:restart(params, opts)
    checks('table', {
        command = '?string',
        workdir = '?string',
        datadir = '?string',
        chdir = '?string',
        env = '?table',
        args = '?table',
        box_cfg = '?table',

        http_port = '?number',
        net_box_port = '?number',
        net_box_uri = '?string',
        net_box_credentials = '?table',

        alias = '?string',

        coverage_report = '?boolean',
    }, {wait_until_ready = '?boolean'})

    if not self.process then
        log.warn("Process wasn't started")
    end
    self:stop()

    for param, value in pairs(params or {}) do
        self[param] = value
    end

    self:start(opts)
    log.debug('Restarted server PID: ' .. self.process.pid)
end

-- Wait until the given condition is `true` (anything except `false` and `nil`).
-- Throws an error when timeout exceeds.
local function wait_for_condition(cond_desc, server, func, ...)
    local deadline = clock.time() + WAIT_TIMEOUT
    while true do
        if func(...) then
            return
        end
        if clock.time() > deadline then
            error(('Timed out to wait for "%s" condition for server (alias: %s, workdir: %s, pid: %d) within %ds')
                :format(cond_desc, server.alias, fio.basename(server.workdir), server.process.pid, WAIT_TIMEOUT))
        end
        fiber.sleep(WAIT_DELAY)
    end
end

--- Stop the server.
-- Waits until the server process is terminated.
function Server:stop()
    if self.net_box then
        if self.coverage_report then
            self:coverage('shutdown')
        end
        self.net_box:close()
        self.net_box = nil
    end

    if self.process then
        self.process:kill()
        wait_for_condition('process is terminated', self, function()
            return not self.process:is_alive()
        end)
        log.debug('Killed server process PID ' .. self.process.pid)
        self.process = nil
    end
end

--- Clean the server's working directory.
-- Should be invoked only for a stopped server.
function Server:clean()
    fio.rmtree(self.workdir)
    self.instance_id = nil
    self.instance_uuid = nil
end

--- Stop the server and clean its working directory.
function Server:drop()
    self:stop()
    self:clean()
end

--- Wait until the server is ready after the start.
-- A server is considered ready when its `_G.ready` variable becomes `true`.
function Server:wait_until_ready()
    wait_for_condition('server is ready', self, function()
        local ok, is_ready = pcall(function()
            self:connect_net_box()
            return self.net_box:eval('return _G.ready') == true
        end)
        return ok and is_ready
    end)
end

--- Get ID of the server instance.
--
-- @return number
function Server:get_instance_id()
    -- Cache the value when found it first time.
    if self.instance_id then
        return self.instance_id
    end
    local id = self:exec(function() return box.info.id end)
    -- But do not cache 0 - it is an anon instance, its ID might change.
    if id ~= 0 then
        self.instance_id = id
    end
    return id
end

--- Get UUID of the server instance.
--
-- @return string
function Server:get_instance_uuid()
    -- Cache the value when found it first time.
    if self.instance_uuid then
        return self.instance_uuid
    end
    self.instance_uuid = self:exec(function() return box.info.uuid end)
    return self.instance_uuid
end

--- Establish `net.box` connection.
-- It's available in `net_box` field.
function Server:connect_net_box()
    if self.net_box and self.net_box:is_connected() then
        return self.net_box
    end
    if not self.net_box_uri then
        error('net_box_port not configured')
    end
    local connection = net_box.connect(self.net_box_uri, self.net_box_credentials)
    if connection.error then
        error(connection.error)
    end
    self.net_box = connection
end

local function is_header_set(headers, name)
    name = name:lower()
    for key in pairs(headers) do
        if name == tostring(key):lower() then
            return true
        end
    end
    return false
end

--- Perform HTTP request.
-- @string method
-- @string path
-- @tab[opt] options
-- @string[opt] options.body request body
-- @param[opt] options.json data to encode as JSON into request body
-- @tab[opt] options.http other options for HTTP-client
-- @bool[opt] options.raise raise error when status is not in 200..299. Default to true.
-- @return response object from HTTP client with helper methods.
-- @see luatest.http_response
-- @raise HTTPRequest error when response status is not 200.
function Server:http_request(method, path, options)
    if not self.http_client then
        error('http_port not configured')
    end
    options = options or {}
    if options.raw ~= nil then
        error('`raw` option for http_request is removed, please replace `raw = true` => `raise = false`')
    end
    local http_options = options.http or {}
    local body = options.body
    if not body and options.json then
        body = json.encode(options.json)
        http_options.headers = http_options.headers or {}
        if not is_header_set(http_options.headers, 'Content-Type') then
            http_options.headers['Content-Type'] = 'application/json'
        end
    end
    local url = 'http://localhost:' .. self.http_port .. path
    local raw_response = self.http_client:request(method, url, body, http_options)
    local response = HTTPResponse:from(raw_response)
    if not response:is_successful() then
        if options.raise == nil or options.raise then
            error({type = 'HTTPRequest', response = response})
        end
    end
    return response
end

--- Evaluate Lua code on the server.
--
-- This is a wrapper for `server.net_box:eval()`.
-- @string code
-- @tab[opt] args
-- @tab[opt] options
function Server:eval(code, ...)
    if self.net_box == nil then
        error('net_box is not connected', 2)
    end
    return self.net_box:eval(code, ...)
end

--- Call remote function on the server by name.
--
-- This is a shortcut for `server.net_box:call()`.
-- @string fn_name
-- @tab[opt] args
-- @tab[opt] options
function Server:call(...)
    if self.net_box == nil then
        error('net_box is not connected', 2)
    end
    return self.net_box:call(...)
end

local function exec_tail(ok, ...)
    if not ok then
        error(..., 0)
    else
        return ...
    end
end

--- Run given function on the server.
--
-- Much like `Server:eval`, but takes a function instead of a string.
-- The executed function must have no upvalues (closures). Though it
-- may use global functions and modules (like `box`, `os`, etc.)
--
-- @tparam function fn
-- @tab[opt] args
-- @tab[opt] options
--
-- @usage
--
--    local vclock = server:exec(function()
--        return box.info.vclock
--    end)
--
--    local sum = server:exec(function(a, b)
--        return a + b
--    end, {1, 2})
--    -- sum == 3
--
--    server:exec(function()
--        -- luatest is always available as `t`
--        t.assert_equals(math.pi, 3)
--    end)
--    -- mytest.lua:12: expected: 3, actual: 3.1415926535898
--
function Server:exec(fn, args, options)
    checks('?', 'function', '?table', '?table')
    if self.net_box == nil then
        error('net_box is not connected', 2)
    end

    local luatest_ups = {}
    local other_ups = {}
    for i = 1, debug.getinfo(fn, 'u').nups do
        local name, value = debug.getupvalue(fn, i)
        if value == package.loaded.luatest then
            luatest_ups[name] = true
        else
            table.insert(other_ups, name)
        end
    end

    if next(other_ups) ~= nil then
        local err = string.format(
            'bad argument #2 to exec (excess upvalues: %s)',
            table.concat(other_ups, ', ')
        )
        error(err, 2)
    end

    return exec_tail(self:eval([[
        local dump, args, luatest_ups = ...
        local fn = loadstring(dump)

        for i = 1, debug.getinfo(fn, 'u').nups do
            local name, value = debug.getupvalue(fn, i)
            if luatest_ups[name] then
                debug.setupvalue(fn, i, require('luatest'))
            end
        end
        if args == nil then
            return pcall(fn)
        else
            return pcall(fn, unpack(args))
        end
    ]], {string.dump(fn), args, luatest_ups}, options))
end

function Server:coverage(action)
    self:eval('require("luatest.coverage_utils").' .. action .. '()')
end

--
-- Log
--

--- Search a string pattern in the server's log file.
-- If the server has crashed, `opts.filename` is required.
--
-- @string pattern String pattern to search in the server's log file.
-- @number[opt] bytes_num Number of bytes to read from the server's log file.
-- @tab[opt] opts
-- @bool[opt] opts.reset Reset the result when `Tarantool %d+.%d+.%d+-.*%d+-g.*`
--   pattern is found, which means that the server was restarted.
--   Defaults to `true`.
-- @string[opt] opts.filename Path to the server's log file.
--   Defaults to `box.cfg.log`.
-- @return string|nil
function Server:grep_log(pattern, bytes_num, opts)
    local options = opts or {}
    local reset = options.reset or true
    local filename = options.filename or self:exec(function() return box.cfg.log end)
    local file = fio.open(filename, {'O_RDONLY', 'O_NONBLOCK'})

    local function fail(msg)
        local err = errno.strerror()
        if file ~= nil then
            file:close()
        end
        error(string.format('%s: %s: %s', msg, filename, err))
    end

    if file == nil then
        fail('Failed to open log file')
    end

    io.flush() -- attempt to flush stdout == log fd

    local filesize = file:seek(0, 'SEEK_END')
    if filesize == nil then
        fail('Failed to get log file size')
    end

    local bytes = bytes_num or 65536 -- don't read the whole log -- it can be huge
    bytes = bytes > filesize and filesize or bytes
    if file:seek(-bytes, 'SEEK_END') == nil then
        fail('Failed to seek log file')
    end

    local found, buf
    repeat -- read file in chunks
        local s = file:read(2048)
        if s == nil then
            fail('Failed to read log file')
        end
        local pos = 1
        repeat -- split read string in lines
            local endpos = string.find(s, '\n', pos)
            endpos = endpos and endpos - 1 -- strip terminating \n
            local line = string.sub(s, pos, endpos)
            if endpos == nil and s ~= '' then
                -- Line doesn't end with \n or EOF, append it to buffer
                -- to be checked on next iteration.
                buf = buf or {}
                table.insert(buf, line)
            else
                if buf ~= nil then
                    -- Prepend line with buffered data.
                    table.insert(buf, line)
                    line = table.concat(buf)
                    buf = nil
                end
                if string.match(line, '> Tarantool %d+.%d+.%d+-.*%d+-g.*$') and reset then
                    found = nil -- server was restarted, reset the result
                else
                    found = string.match(line, pattern) or found
                end
            end
            pos = endpos and endpos + 2 -- jump to char after \n
        until pos == nil
    until s == ''

    file:close()

    return found
end

--
-- Replication
--

--- Assert that the server follows the source node with the given ID.
-- Meaning that it replicates from the remote node normally, and has already
-- joined and subscribed.
--
-- @number server_id Server ID.
function Server:assert_follows_upstream(server_id)
    local status = self:exec(function(id)
        return box.info.replication[id].upstream.status
    end, {server_id})
    local msg = ('%s: server does not follow upstream'):format(self.alias)
    assertions.assert_equals(status, 'follow', msg)
end

-- Election

--- Get the election term as seen by the server.
--
-- @return number
function Server:get_election_term()
    return self:exec(function() return box.info.election.term end)
end

--- Wait for the server to reach at least the given election term.
--
-- @string term Election term to wait for.
function Server:wait_for_election_term(term)
    wait_for_condition('election term', self, self.exec, self, function(t)
        return box.info.election.term >= t
    end, {term})
end

--- Wait for the server to enter the given election state.
-- Note that if it becomes a leader, it does not mean it is already writable.
--
-- @string state Election state to wait for.
function Server:wait_for_election_state(state)
    wait_for_condition('election state', self, self.exec, self, function(s)
        return box.info.election.state == s
    end, {state})
end

--- Wait for the server to become a **writable** election leader.
function Server:wait_for_election_leader()
    -- Include read-only property too because if an instance is a leader, it
    -- does not mean that it has finished the synchro queue ownership transition.
    -- It is read-only until that happens. But in tests, the leader is usually
    -- needed as a writable node.
    wait_for_condition('election leader', self, self.exec, self, function()
        return box.info.election.state == 'leader' and not box.info.ro
    end)
end

--- Wait for the server to discover an election leader.
function Server:wait_until_election_leader_found()
    wait_for_condition('election leader is found', self, self.exec, self, function()
        return box.info.election.leader ~= 0
    end)
end

-- Synchro

--- Get the synchro term as seen by the server.
--
-- @return number
function Server:get_synchro_queue_term()
    return self:exec(function() return box.info.synchro.queue.term end)
end

--- Wait for the server to reach at least the given synchro term.
--
-- @number term Synchro queue term to wait for.
function Server:wait_for_synchro_queue_term(term)
    wait_for_condition('synchro queue term', self, self.exec, self, function(t)
        return box.info.synchro.queue.term >= t
    end, {term})
end

--- Play WAL until the synchro queue becomes busy.
-- WAL records go one by one. The function is needed, because during
-- `box.ctl.promote()` it is not known for sure which WAL record is PROMOTE -
-- first, second, third? Even if known, it might change in the future. WAL delay
-- should already be started before the function is called.
function Server:play_wal_until_synchro_queue_is_busy()
    wait_for_condition('synchro queue is busy', self, self.exec, self, function()
        if not box.error.injection.get('ERRINJ_WAL_DELAY') then
            return false
        end
        if box.info.synchro.queue.busy then
            return true
        end
        -- Allow 1 more WAL write.
        box.error.injection.set('ERRINJ_WAL_DELAY_COUNTDOWN', 0)
        box.error.injection.set('ERRINJ_WAL_DELAY', false)
        return false
    end)
end

-- Vclock

--- Get the server's own vclock, including the local component.
--
-- @return table
function Server:get_vclock()
    return self:exec(function() return box.info.vclock end)
end

--- Get vclock acknowledged by another node to the current server.
--
-- @number server_id Server ID.
-- @return table
function Server:get_downstream_vclock(server_id)
    return self:exec(function(id)
        local info = box.info.replication[id]
        return info and info.downstream and info.downstream.vclock or nil
    end, {server_id})
end

-- Compare vclocks and return `true` if a >= b or `false` otherwise.
local function vclock_ge(a, b)
    if a == nil then
        return b == nil
    end
    for server_id, b_lsn in pairs(b) do
        local a_lsn = a[server_id]
        if a_lsn == nil or a_lsn < b_lsn then
            return false
        end
    end
    return true
end

--- Wait until the server's own vclock reaches at least the given value.
-- Including the local component.
--
-- @tab vclock Server's own vclock to reach.
function Server:wait_for_vclock(vclock)
    while true do
        if vclock_ge(self:get_vclock(), vclock) then
            return
        end
        fiber.sleep(0.005)
    end
end

--- Wait until all own data is replicated and confirmed by the given server.
--
-- @tab server Server's object.
function Server:wait_for_downstream_to(server)
    local id = server:get_instance_id()
    local vclock = server:get_vclock()
    vclock[0] = nil  -- first component is for local changes
    while true do
        if vclock_ge(self:get_downstream_vclock(id), vclock) then
            return
        end
        fiber.sleep(0.005)
    end
end

--- Wait for the server to reach at least the same vclock as the other server.
-- Not including the local component, of course.
--
-- @tab other_server Other server's object.
function Server:wait_for_vclock_of(other_server)
    local vclock = other_server:get_vclock()
    vclock[0] = nil  -- first component is for local changes
    self:wait_for_vclock(vclock)
end

return Server
