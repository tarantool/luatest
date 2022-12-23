local fio = require('fio')

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
            LUA_PATH =
                root .. '/?.lua;' ..
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

g.test_exec_without_t = function()
    local actual = g.server:exec(function()
        return 1 + 1
    end)
    t.assert_equals(actual, 2)
end

g.test_exec_with_global_variable = function()
    g.server:exec(function()
        t.assert_equals(1, 1)
    end)
    t.assert_equals(1, 1)
end

g.test_exec_with_local_variable = function()
    g.server:exec(function()
        local t = require('luatest')
        t.assert_equals(1, 1)
    end)
    t.assert_equals(1, 1)
end

g.test_exec_with_local_duplicate = function()
    g.server:exec(function()
        local tt = require('luatest')
        t.assert_equals(1, 1)
        tt.assert_equals(1, 1)
        t.assert_equals(tt, t)
    end)
end

g.test_eval_with_t = function()
    local actual = g.server:eval([[
        t.assert_equals(1, 1)
        return 1
    ]])
    t.assert_equals(actual, 1)
end

g.before_test('test_exec_when_lua_path_is_unset', function()
    -- Setup custom server without LUA_PATH variable
    local workdir = fio.tempdir()
    local log = fio.pathjoin(workdir, 'bad_env_server.log')
    g.bad_env_server = Server:new({
        command = command,
        workdir = workdir,
        env = {
            TARANTOOL_LOG = log
        },
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

g.test_exec_when_lua_path_is_unset = function()
    g.bad_env_server:exec(function() return 1 + 1 end)

    t.assert(
        g.bad_env_server:grep_log(
            "W> LUA_PATH is unset or incorrect, module 'luatest' not found"
        )
    )
end

g.after_test('test_exec_when_lua_path_is_unset', function()
    g.bad_env_server:drop()
end)
