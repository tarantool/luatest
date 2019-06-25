local checks = require('checks')
local http_client = require('http.client')
local json = require('json')
local log = require('log')
local net_box = require('net.box')

local Process = require('luatest.process')
local utils = require('luatest.utils')

local Server = {
    constructor_checks = {
        command = 'string',
        workdir = 'string',
        chdir = '?string',
        env = '?table',
        args = '?table',

        http_port = '?number',
        net_box_port = '?number',
        net_box_credentials = '?table',
    },
}

function Server:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

function Server:new(object)
    checks('table', self.constructor_checks)
    self:inherit(object)
    object:initialize()
    return object
end

function Server:initialize()
    if self.http_port then
        self.http_client = http_client.new()
    end
    if self.net_box_port then
        self.net_box_uri = 'localhost:' .. self.net_box_port
    end
    self.env = utils.reverse_merge({}, self.env or {}, self:build_env())
    self.args = self.args or {}
end

function Server:build_env()
    return {
        TARANTOOL_WORKDIR = self.workdir,
        TARANTOOL_HTTP_PORT = self.http_port,
        TARANTOOL_LISTEN = self.net_box_port,
    }
end

function Server:start()
    local env = table.copy(os.environ())
    local log_cmd = ''
    for k, v in pairs(self.env) do
        log_cmd = log_cmd .. 'export ' .. k .. '=' .. v .. ' '
        env[k] = v
    end
    log_cmd = log_cmd .. self.command
    log.debug(log_cmd)

    self.process = Process:start(self.command, self.args, env, {chdir = self.chdir})
    log.debug('Started server PID: ' .. self.process.pid)
end

function Server:stop()
    if self.net_box then
        self.net_box:close()
        self.net_box = nil
    end
    if self.process then
        self.process:kill()
        log.debug('Killed server process PID '.. self.process.pid)
        self.process = nil
    end
end

function Server:connect_net_box()
    if self.net_box then
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

function Server:http_request(method, path, options)
    if not self.http_client then
        error('http_port not configured')
    end
    options = options or {}
    local body = options.body or (options.json and json.encode(options.json))
    local http_options = options.http or {}
    local url = 'http://localhost:' .. self.http_port .. path
    local response = self.http_client:request(method, url, body, http_options)
    local ok, json_body = pcall(json.decode, response.body)
    if ok then
        response.json = json_body
    end
    if not options.raw and response.status ~= 200 then
        error({type = 'HTTPReqest', response = response})
    end
    return response
end

return Server
