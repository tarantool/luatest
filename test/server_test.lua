local fiber = require('fiber')
local fio = require('fio')
local json = require('json')

local lt = require('luatest')
local t = lt.group('server')

local Server = lt.Server

local root = fio.dirname(fio.dirname(fio.abspath(package.search('test.helper'))))
local datadir = fio.pathjoin(root, 'tmp', 'db_test')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

local server = Server:new({
    command = command,
    workdir = fio.pathjoin(datadir, 'common'),
    env = {custom_env = 'test_value'},
    http_port = 8182,
    console_port = 3133,
})

t.before_all = function()
    fio.rmtree(datadir)
    fio.mktree(server.workdir)
    server:start()
    -- wait until booted
    lt.helpers.retrying({timeout = 2}, function() server:http_request('get', '/ping') end)
end

t.after_all = function()
    if server.process then
        server:stop()
    end
    fio.rmtree(datadir)
end

t.test_start_stop = function()
    local workdir = fio.pathjoin(datadir, 'start_stop')
    fio.mktree(workdir)
    local s = Server:new({command = command, workdir = workdir})
    s:start()
    fiber.sleep(0.1)
    lt.assertEquals(os.execute('ps -p ' .. s.process.pid .. ' > /dev/null'), 0)
    s:stop()
    fiber.sleep(0.1)
end

t.test_http_request = function()
    local response = server:http_request('get', '/test')
    local expected = {
        workdir = fio.pathjoin(datadir, 'common'),
        listen = '3133',
        http_port = '8182',
        value = 'test_value',
    }
    lt.assertEquals(response.body, json.encode(expected))
    lt.assertEquals(response.json, expected)
end

t.test_http_request_post_json = function()
    local value = {field = 'data'}
    local response = server:http_request('post', '/echo', {json = value})
    lt.assertEquals(response.json, value)
end

t.test_http_request_failed = function()
    local ok, err = pcall(function() server:http_request('get', '/invalid') end)
    lt.assertEquals(ok, false)
    lt.assertEquals(err.type, 'HTTPReqest')
    lt.assertEquals(err.response.status, 404)
end

t.test_console = function()
    server:connect_console()
    lt.assertEquals(server.console:eval('return os.getenv("custom_env")'), 'test_value')
end

t.test_inherit = function()
    local child = Server:inherit({})
    local instance = child:new({command = 'test-cmd', workdir = 'test-dir'})
    lt.assertEquals(instance.start, Server.start)
end
