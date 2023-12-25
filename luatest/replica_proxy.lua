--- Manage connection to Tarantool replication instances via proxy.
--
-- @module luatest.replica_proxy

local checks = require('checks')
local fiber = require('fiber')
local fio = require('fio')
local socket = require('socket')
local uri = require('uri')

local log = require('luatest.log')
local utils = require('luatest.utils')
local Connection = require('luatest.replica_conn')

local TIMEOUT = 0.001
local BACKLOG = 512

local Proxy = {
    constructor_checks = {
        client_socket_path = 'string',
        server_socket_path = 'string',
        process_client = '?table',
        process_server = '?table',
    },
}

function Proxy:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

local function check_tarantool_version()
    if utils.version_current_ge_than(2, 10, 1) then
        return
    else
        error('Proxy requires Tarantool 2.10.1 and newer')
    end
end

--- Build a proxy object.
--
-- @param object
-- @string object.client_socket_path Path to a UNIX socket where proxy will await new connections.
-- @string object.server_socket_path Path to a UNIX socket where Tarantool server is listening to.
-- @tab[opt] object.process_client Table describing how to process the client socket.
-- @tab[opt] object.process_server Table describing how to process the server socket.
-- @return Input object.
function Proxy:new(object)
    checks('table', self.constructor_checks)
    check_tarantool_version()
    self:inherit(object)
    object:initialize()
    return object
end

function Proxy:initialize()
    self.connections = {}
    self.accept_new_connections = true
    self.running = false

    self.client_socket = socket('PF_UNIX', 'SOCK_STREAM', 0)
end

--- Stop accepting new connections on the client socket.
-- Join the fiber created by proxy:start() and close the client socket.
-- Also, stop all active connections.
function Proxy:stop()
    self.running = false
    self.worker:join()
    for _, c in pairs(self.connections) do
        c:stop()
    end
end

--- Pause accepting new connections and pause all active connections.
function Proxy:pause()
    self.accept_new_connections = false
    for _, c in pairs(self.connections) do
        c:pause()
    end
end

--- Resume accepting new connections and resume all paused connections.
function Proxy:resume()
    for _, c in pairs(self.connections) do
        c:resume()
    end
    self.accept_new_connections = true
end

--- Start accepting new connections on the client socket in a new fiber.
--
-- @tab[opt] opts
-- @bool[opt] opts.force Remove the client socket before start.
function Proxy:start(opts)
    checks('table', {force = '?boolean'})
    if opts ~= nil and opts.force then
        os.remove(self.client_socket_path)
    end

    fio.mktree(fio.dirname(uri.parse(self.client_socket_path).service))

    if not self.client_socket:bind('unix/', self.client_socket_path) then
        log.error("Failed to bind client socket: %s", self.client_socket:error())
        return false
    end

    self.client_socket:nonblock(true)
    if not self.client_socket:listen(BACKLOG) then
        log.error("Failed to listen on client socket: %s",
            self.client_socket:error())
        return false
    end

    self.running = true
    self.worker = fiber.new(function()
        while self.running do
            if not self.accept_new_connections then
                fiber.sleep(TIMEOUT)
                goto continue
            end

            if not self.client_socket:readable(TIMEOUT) then
                goto continue
            end

            local client = self.client_socket:accept()
            if client == nil then goto continue end
            client:nonblock(true)

            local conn = Connection:new({
                client_socket = client,
                server_socket_path = self.server_socket_path,
                process_client = self.process_client,
                process_server = self.process_server,
            })
            table.insert(self.connections, conn)
            conn:start()
            :: continue ::
        end

        self.client_socket:shutdown(socket.SHUT_RW)
        self.client_socket:close()
        os.remove(self.client_socket_path)
    end)
    self.worker:set_joinable(true)
    self.worker:name('ProxyWorker')

    return true
end

return Proxy
