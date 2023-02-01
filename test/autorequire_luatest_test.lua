local ll = require('luatest')
local t = ll
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

g.test_exec = function()
    g.server:exec(function()
        return ll.assert_equals(1, 1)
    end)
    t.assert_equals(2, 2)
end
