local fio = require('fio')
local t = require('luatest')

local g = t.group()
local Server = t.Server

local root = fio.dirname(fio.abspath('test.helpers'))
local datadir = fio.pathjoin(root, 'tmp', 'malformed_args')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

g.before_all(function()
    fio.rmtree(datadir)

    local log = fio.pathjoin(datadir, 'malformed_args_server.log')
    g.server = Server:new({
        command = command,
        workdir = datadir,
        env = {
            TARANTOOL_LOG = log
        },
        http_port = 8186,
        net_box_port = 3139,
    })
    fio.mktree(g.server.workdir)

    g.server:start()
    t.helpers.retrying({timeout = 2}, function()
        g.server:http_request('get', '/ping')
    end)

    g.server:connect_net_box()
end)

g.after_all(function()
    g.server:drop()
    fio.rmtree(datadir)
end)

g.test_exec_correct_args = function()
    local a = g.server:exec(function(a, b) return a + b end, {1, 1})
    t.assert_equals(a, 2)
end

g.test_exec_no_args = function()
    local a = g.server:exec(function() return 1 + 1 end)
    t.assert_equals(a, 2)
end

g.test_exec_specific_args = function()
    -- nil
    local a = g.server:exec(function(a) return a end)
    t.assert_equals(a, nil)

    -- too few args
    local b, c = g.server:exec(function(b, c) return b, c end, {1})
    t.assert_equals(b, 1)
    t.assert_equals(c, nil)

    -- too many args
    local d = g.server:exec(function(d) return d end, {1, 2})
    t.assert_equals(d, 1)
end

g.test_exec_non_array_args = function()
    local function f1()
        g.server:exec(function(a, b, c) return a, b, c end, {a="a", 2, 3})
    end

    local function f2()
        g.server:exec(function(a, b, c) return a, b, c end, {1, a="a", 2})
    end

    local function f3()
        g.server:exec(function(a, b, c) return a, b, c end, {1, 2, a="a"})
    end

    t.assert_error_msg_contains("bad argument #3 for exec at malformed_args_test.lua:66:", f1)
    t.assert_error_msg_contains("bad argument #3 for exec at malformed_args_test.lua:70:", f2)
    t.assert_error_msg_contains("bad argument #3 for exec at malformed_args_test.lua:74:", f3)
end
