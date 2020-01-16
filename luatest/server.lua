--- Class to run tarantool instance.
--
-- @classmod luatest.server

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

        alias = '?string',
    },
}

function Server:inherit(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

--- Build server object.
-- @param object
-- @string object.command Command to start server process.
-- @string object.workdir Value to be passed in `TARANTOOL_WORKDIR`.
-- @string[opt] object.chdir Path to cwd before running a process.
-- @tab[opt] object.env Table to pass as env variables to process.
-- @tab[opt] object.args Args to run command with.
-- @int[opt] object.http_port Value to be passed in `TARANTOOL_HTTP_PORT` and used to perform HTTP requests.
-- @int[opt] object.net_box_port Value to be passed in `TARANTOOL_LISTEN` and used for net_box connection.
-- @tab[opt] object.net_box_credentials Override default net_box credentials.
-- @string[opt] object.alias Instance alias. Used to prefix output.
-- @return input object.
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
    self.env = utils.merge(self:build_env(), self.env or {})
    self.args = self.args or {}
end

--- Generates environment to run process with.
-- The result is merged into os.environ().
-- @return map
function Server:build_env()
    return {
        TARANTOOL_WORKDIR = self.workdir,
        TARANTOOL_HTTP_PORT = self.http_port,
        TARANTOOL_LISTEN = self.net_box_port,
    }
end

--- Start server process.
function Server:start()
    local env = table.copy(os.environ())
    local log_cmd = {}
    for k, v in pairs(self.env) do
        table.insert(log_cmd, string.format('%s=%q', k, v))
        env[k] = v
    end
    table.insert(log_cmd, self.command)
    for _, v in ipairs(self.args) do
        table.insert(log_cmd, string.format('%q', v))
    end

    log.debug(table.concat(log_cmd, ' '))

    self.process = Process:start(self.command, self.args, env, {
        chdir = self.chdir,
        output_prefix = self.alias,
    })
    log.debug('Started server PID: ' .. self.process.pid)
end

--- Stop server process.
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

--- Perform HTTP request.
-- @string method
-- @string path
-- @tab[opt] options
-- @string[opt] options.body request body
-- @param[opt] options.json data to encode as JSON into request body
-- @tab[opt] options.http other options for HTTP-client
-- @bool[opt] options.raise raise error when status is not in 200..299. Default to true.
-- @return response object from HTTP client.
--   If response body is valid JSON it's parsed into `json` field.
-- @raise HTTPRequest error when response status is not 200.
function Server:http_request(method, path, options)
    if not self.http_client then
        error('http_port not configured')
    end
    options = options or {}
    if options.raw ~= nil then
        error('`raw` option for http_request is removed, please replace `raw = true` => `raise = false`')
    end
    local body = options.body or (options.json and json.encode(options.json))
    local http_options = options.http or {}
    local url = 'http://localhost:' .. self.http_port .. path
    local response = self.http_client:request(method, url, body, http_options)
    local ok, json_body = pcall(json.decode, response.body)
    if ok then
        response.json = json_body
    end
    if response.status < 200 or response.status > 299 then
        if options.raise == nil or options.raise then
            error({type = 'HTTPRequest', response = response})
        end
    end
    return response
end

return Server
