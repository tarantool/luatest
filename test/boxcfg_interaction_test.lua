local fio = require('fio')
local t = require('luatest')

local g = t.group()
local Server = t.Server

local root = fio.dirname(fio.dirname(fio.abspath(package.search('test.helper'))))
local datadir = fio.pathjoin(root, 'tmp', 'boxcfg_interaction')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

g.before_all(function()
    fio.rmtree(datadir)

    local workdir = fio.tempdir()
    local log = fio.pathjoin(workdir, 'boxcfg_interaction.log')

    g.server = Server:new({
        command = command,
        workdir = fio.pathjoin(datadir, 'boxcfg_interaction'),
        env = {
            TARANTOOL_LOG = log
        },
        box_cfg = {read_only = false},
        http_port = 8187,
        net_box_port = 3138,
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

g.test_update_box_cfg = function()
    g.server:update_box_cfg{read_only = true}

    local c = g.server:exec(function() return box.cfg end)

    t.assert_type(c, 'table')
    t.assert_equals(c.read_only, true)
    t.assert(
        g.server:grep_log(
            "I> set 'read_only' configuration option to true"
        )
    )
end

g.test_update_box_cfg_multiple_parameters = function()
    g.server:update_box_cfg{checkpoint_count = 5, replication_timeout = 2}

    local c = g.server:exec(function() return box.cfg end)

    t.assert_type(c, 'table')

    t.assert_equals(c.checkpoint_count, 5)
    t.assert(
        g.server:grep_log(
            "I> set 'checkpoint_count' configuration option to 5"
        )
    )

    t.assert_equals(c.replication_timeout, 2)
    t.assert(
        g.server:grep_log(
            "I> set 'replication_timeout' configuration option to 2"
        )
    )
end

g.test_update_box_cfg_bad_type = function()
    local function foo()
        g.server:update_box_cfg(1)
    end
    t.assert_error_msg_contains(
        'bad argument #2 to update_box_cfg (table expected, got number)', foo)

end

g.test_get_box_cfg = function()
    local cfg1 = g.server:get_box_cfg()
    local cfg2 = g.server:exec(function() return box.cfg end)

    t.assert_equals(cfg1, cfg2)
end
