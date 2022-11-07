--- Class to manage Tarantool instances, version 2.
--
-- @classmod luatest.server2

local checks = require('checks')
local clock = require('clock')
local digest = require('digest')
local errno = require('errno')
local ffi = require('ffi')
local fiber = require('fiber')
local fio = require('fio')
local fun = require('fun')
local json = require('json')

local assertions = require('luatest.assertions')

local DEFAULT_VARDIR = '/tmp/t'
local DEFAULT_ALIAS = 'server'
local DEFAULT_INSTANCE = '../luatest/server_v2_instance.lua'
local WAIT_TIMEOUT = 60
local WAIT_DELAY = 0.1

ffi.cdef([[
    int kill(pid_t pid, int sig);
]])

--- Build a server object.
-- Changes from the 1st version of the server class:
--   * The `alias` parameter defaults to 'server'.
--   * The `command` parameter is optional.
--   * The `workdir` parameter is optional.
--   * New parameter `datadir` (optional).
--   * New parameter `box_cfg` (optional).
--
-- @function new
-- @param object
-- @string[opt] object.command Executable path to run a server process with.
--   Defaults to the internal `server_v2_instance.lua` script. If a custom path
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
--   Defaults to <vardir>/<alias>-<random id>.
-- @string[opt] object.datadir Directory path whose contents will be recursively
--   copied into `object.workdir` during initialization.
-- @int[opt] object.http_port Port for HTTP connection to the new server and the
--   value of the `TARANTOOL_HTTP_PORT` env variable which is passed into the
--   server process.
--   Not supported in the default `server_v2_instance.lua` script.
-- @int[opt] object.net_box_port Port for the `net.box` connection to the new
--   server and the value of the `TARANTOOL_LISTEN` env variable which is passed
--   into the server process.
-- @string[opt] object.net_box_uri URI for the `net.box` connection to the new
--   server and the value of the `TARANTOOL_LISTEN` env variable which is passed
--   into the server process.
--   Overrides `object.net_box_port`.
-- @tab[opt] object.net_box_credentials Override the default credentials for the
--   `net.box` connection to the new server.
-- @tab[opt] object.box_cfg Extra options for `box.cfg()` and the value of the
--   `TARANTOOL_BOX_CFG` env variable which is passed into the server process.
-- @return table
local Server = require('luatest.server'):inherit({})

Server.constructor_checks = fun.chain(
    Server.constructor_checks,
    {
        command = '?string',
        workdir = '?string',
        datadir = '?string',
        engine = '?string',
        box_cfg = '?table',
    }
):tomap()
Server.vardir = fio.abspath(os.getenv('VARDIR') or DEFAULT_VARDIR)

-- Initialize the server object.
function Server:initialize()
    self.id = digest.base64_encode(digest.urandom(9), {urlsafe = true})
    if self.alias == nil then
        self.alias = DEFAULT_ALIAS
    end
    if self.command == nil then
        self.command = fio.pathjoin(fio.dirname(fio.abspath(arg[0])), DEFAULT_INSTANCE)
    end
    if self.workdir == nil then
        self.workdir = fio.pathjoin(self.vardir, ('%s-%s'):format(self.alias, self.id))
        fio.rmtree(self.workdir)
        fio.mktree(self.workdir)
    end
    if self.datadir ~= nil then
        local ok, err = fio.copytree(self.datadir, self.workdir)
        if not ok then
            error(string.format('Failed to copy directory: %s', err))
        end
        self.datadir = nil
    end
    if self.net_box_port == nil and self.net_box_uri == nil then
        self.net_box_uri = self.build_listen_uri(self.alias)
        fio.mktree(self.vardir)
    end
    getmetatable(getmetatable(self)).initialize(self)
end

--- Create a table with env variables based on the constructor params.
-- The result will be passed into the server process.
-- Table consists of the following entries:
--   * TARANTOOL_ALIAS
--   * TARANTOOL_WORKDIR
--   * TARANTOOL_HTTP_PORT
--   * TARANTOOL_LISTEN
--   * TARANTOOL_BOX_CFG
--
-- @return table
function Server:build_env()
    local res = getmetatable(getmetatable(self)).build_env(self)
    if self.box_cfg ~= nil then
        res.TARANTOOL_BOX_CFG = json.encode(self.box_cfg)
    end
    return res
end

--- Build a listen URI based on the given server alias.
-- For now, only UNIX sockets are supported.
--
-- @string alias Server alias.
-- @return string
function Server.build_listen_uri(server_alias)
    return fio.pathjoin(Server.vardir, server_alias .. '.sock')
end

--- Start a server.
-- Waits until the server is ready, unlike the 1st version of the server class.
--
-- @tab[opt] opts
-- @bool[opt] opts.wait_until_ready Wait until the server is ready.
--   Defaults to `true`.
function Server:start(opts)
    checks('table', {wait_until_ready = '?boolean'})
    getmetatable(getmetatable(self)).start(self)
    local wait_until_ready = true
    if opts ~= nil and opts.wait_until_ready ~= nil then
        wait_until_ready = opts.wait_until_ready
    end
    if wait_until_ready then
        self:wait_until_ready()
    end
end

-- TODO: Add Server:restart() function.

--- Stop the server.
-- Waits until the server process is killed, unlike the 1st version of the
-- server class.
function Server:stop()
    if self.process then
        local pid = self.process.pid
        getmetatable(getmetatable(self)).stop(self)
        local deadline = clock.time() + WAIT_TIMEOUT
        while true do
            if ffi.C.kill(pid, 0) ~= 0 then
                break
            end
            if clock.time() > deadline then
                error(('Stopping of server (alias: %s, workdir: %s, pid: %d) timed out')
                    :format(self.alias, fio.basename(self.workdir), pid))
            end
            fiber.sleep(WAIT_DELAY)
        end
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

-- Wait until the given condition is `true` (anything except `false` and `nil`).
-- Throw an error when timeout exceeds.
local function wait_for_condition(cond_name, server, func, ...)
    local pid = server.process.pid
    local deadline = clock.time() + WAIT_TIMEOUT
    while true do
        if func(...) then
            return
        end
        if clock.time() > deadline then
            error(('Waiting for "%s" condition on server (alias: %s, workdir: %s, pid: %d) timed out')
                :format(cond_name, server.alias, fio.basename(server.workdir), pid))
        end
        fiber.sleep(WAIT_DELAY)
    end
end

--- Wait until the server is ready after the start.
-- A server is considered ready when its `_G.ready` variable becomes `true`.
function Server:wait_until_ready()
    return wait_for_condition('server is ready', self, function()
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

--
-- Log
--

--- Search a string pattern in the server's log file.
-- If the server has crashed, `opts.filename` is required.
--
-- @string pattern String pattern to search in the server's log file.
-- @number[opt] bytes_num Number of bytes to read from the server's log file.
-- @tab[opt] options
-- @bool[opt] options.reset Reset the result when 'Tarantool %d.%d+.%d+' pattern
--   is found, which means that the server was restarted.
--   Defaults to `true`.
-- @string[opt] options.filename Path to the server's log file.
--   Defaults to `box.cfg.log`.
-- @return string|nil
function Server:grep_log(pattern, bytes_num, options)
    local opts = options or {}
    local reset = opts.reset or true
    local filename = opts.filename or self:exec(function() return box.cfg.log end)
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
                if string.match(line, 'Tarantool %d.%d+.%d+') and reset then
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
    return wait_for_condition('election term', self, self.exec, self, function(t)
        return box.info.election.term >= t
    end, {term})
end

--- Wait for the server to enter the given election state.
-- Note that if it becomes a leader, it does not mean it is already writable.
--
-- @string state Election state to wait for.
function Server:wait_for_election_state(state)
    return wait_for_condition('election state', self, self.exec, self, function(s)
        return box.info.election.state == s
    end, {state})
end

--- Wait for the server to become a *writable* election leader.
function Server:wait_for_election_leader()
    -- Include read-only property too because if an instance is a leader, it
    -- does not mean that it has finished the synchro queue ownership transition.
    -- It is read-only until that happens. But in tests, the leader is usually
    -- needed as a writable node.
    return wait_for_condition('election leader', self, self.exec, self, function()
        return box.info.election.state == 'leader' and not box.info.ro
    end)
end

--- Wait for the server to discover an election leader.
function Server:wait_until_election_leader_found()
    return wait_for_condition('election leader is found', self, self.exec, self,
        function() return box.info.election.leader ~= 0 end)
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
    return wait_for_condition('synchro queue term', self, self.exec, self, function(t)
        return box.info.synchro.queue.term >= t
    end, {term})
end

--- Play WAL until the synchro queue becomes busy.
-- WAL records go one by one. The function is needed, because during
-- `box.ctl.promote()` it is not known for sure which WAL record is PROMOTE -
-- first, second, third? Even if known, it might change in the future. WAL delay
-- should already be started before the function is called.
function Server:play_wal_until_synchro_queue_is_busy()
    return wait_for_condition('synchro queue is busy', self, self.exec, self, function()
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
-- @table vclock Server's own vclock to reach.
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
-- @table server Server's object.
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
-- @table other_server Other server's object.
function Server:wait_for_vclock_of(other_server)
    local vclock = other_server:get_vclock()
    vclock[0] = nil  -- first component is for local changes
    return self:wait_for_vclock(vclock)
end

return Server
