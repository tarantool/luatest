local fio = require('fio')
local json = require('json')

local t = require('luatest')
local g = t.group('server')

local Process = t.Process
local Server = t.Server

local root = fio.dirname(fio.dirname(fio.abspath(package.search('test.helper'))))
local datadir = fio.pathjoin(root, 'tmp', 'db_test')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

local server = Server:new({
    command = command,
    workdir = fio.pathjoin(datadir, 'common'),
    env = {custom_env = 'test_value'},
    http_port = 8182,
    net_box_port = 3133,
})

g.before_all = function()
    fio.rmtree(datadir)
    fio.mktree(server.workdir)
    server:start()
    -- wait until booted
    t.helpers.retrying({timeout = 2}, function() server:http_request('get', '/ping') end)
end

g.after_all = function()
    if server.process then
        server:stop()
    end
    fio.rmtree(datadir)
end

g.test_start_stop = function()
    local workdir = fio.pathjoin(datadir, 'start_stop')
    fio.mktree(workdir)
    local s = Server:new({command = command, workdir = workdir})
    local orig_args = table.copy(s.args)
    s:start()
    local pid = s.process.pid
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert(Process.is_pid_alive(pid))
    end)
    s:stop()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(Process.is_pid_alive(pid))
    end)
    t.assert_equals(s.args, orig_args)
end

g.test_http_request = function()
    local response = server:http_request('get', '/test')
    local expected = {
        workdir = fio.pathjoin(datadir, 'common'),
        listen = '3133',
        http_port = '8182',
        value = 'test_value',
    }
    t.assert_equals(response.body, json.encode(expected))
    t.assert_equals(response.json, expected)
end

g.test_http_request_post_json = function()
    local value = {field = 'data'}
    local response = server:http_request('post', '/echo', {json = value})
    t.assert_equals(response.json, value)
end

g.test_http_request_post_created = function()
    local response = server:http_request('post', '/test')
    t.assert_equals(response.status, 201)
end

g.test_http_request_failed = function()
    local ok, err = pcall(function() server:http_request('get', '/invalid') end)
    t.assert_equals(ok, false)
    t.assert_equals(err.type, 'HTTPRequest')
    t.assert_equals(err.response.status, 404)
end

g.test_http_request_supress_exception = function()
    local response = server:http_request('post', '/invalid', {raise = false})
    t.assert_equals(response.status, 404)
end

g.test_net_box = function()
    server:connect_net_box()
    t.assert_equals(server.net_box:eval('return os.getenv("custom_env")'), 'test_value')

    server.net_box:close()
    t.assert_equals(server.net_box.state, 'closed')
    server:connect_net_box()
    t.assert_equals(server.net_box.state, 'active')
end

g.test_inherit = function()
    local child = Server:inherit({})
    local instance = child:new({command = 'test-cmd', workdir = 'test-dir'})
    t.assert_equals(instance.start, Server.start)
end
