local fio = require('fio')
local t = require('luatest')

local g = t.group()
local Server = t.Server

local root = fio.dirname(fio.dirname(fio.abspath(package.search('test.helper'))))
local datadir = fio.pathjoin(root, 'tmp', 'luatest_module')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

g.before_all(function()
    fio.rmtree(datadir)

    g.server = Server:new({
        command = command,
        workdir = fio.pathjoin(datadir, 'common'),
        env = {
            LUA_PATH = root .. '/?.lua;' ..
                root .. '/?/init.lua;' ..
                root .. '/.rocks/share/tarantool/?.lua'
        },
        http_port = 8182,
        net_box_port = 3133,
    })
    fio.mktree(g.server.workdir)

    g.server:start()
    t.helpers.retrying({timeout = 2}, function()
        g.server:http_request('get', '/ping')
    end)

    g.server:connect_net_box()
end)

g.after_all(function()
    g.server:stop()
    fio.rmtree(datadir)
end)

g.test_exec_without_upvalue = function()
    local actual = g.server:exec(function()
        return 1 + 1
    end)
    t.assert_equals(actual, 2)
end

g.test_exec_with_upvalue = function()
    g.server:exec(function()
        t.assert_equals(1, 1)
    end)
    t.assert_equals(1, 1)

    local lt = require('luatest')
    g.server:exec(function()
        lt.assert_equals(1, 1)
    end)
    lt.assert_equals(1, 1)
end

g.test_exec_with_local_variable = function()
    g.server:exec(function()
        local t = require('luatest')  -- luacheck: ignore 431
        t.assert_equals(1, 1)
    end)
    t.assert_equals(1, 1)
end

g.test_exec_with_upvalue_and_local_variable = function()
    g.server:exec(function()
        local tt = require('luatest')
        t.assert_equals(1, 1)
        tt.assert_equals(1, 1)
        t.assert_equals(tt, t)
    end)
end

g.before_test('test_exec_when_luatest_not_found', function()
    -- Setup custom server without LUA_PATH variable
    g.bad_env_server = Server:new({
        command = command,
        workdir = fio.tempdir(),
        http_port = 8183,
        net_box_port = 3134,
    })

    fio.mktree(g.bad_env_server.workdir)

    g.bad_env_server:start()

    t.helpers.retrying({timeout = 2}, function()
        g.bad_env_server:http_request('get', '/ping')
    end)

    g.bad_env_server:connect_net_box()
end)

g.test_exec_when_luatest_not_found = function()
    t.assert_error_msg_contains(
        "module 'luatest' not found:", g.bad_env_server.exec, g.bad_env_server,
        function() t.assert_equals(1, 1) end
    )
end

g.after_test('test_exec_when_luatest_not_found', function()
    g.bad_env_server:drop()
end)
