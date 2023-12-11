local t = require('luatest')
local proxy = require('luatest.replica_proxy')
local utils = require('luatest.utils')
local replica_set = require('luatest.replica_set')
local server = require('luatest.server')

local fiber = require('fiber')

local g = t.group('proxy-version-check')

g.test_proxy_errors = function()
    t.skip_if(utils.version_current_ge_than(2, 10, 1),
              "Proxy works on Tarantool 2.10.1+, nothing to test")
    t.assert_error_msg_contains('Proxy requires Tarantool 2.10.1 and newer',
                                proxy.new, proxy, {
                                    client_socket_path = 'somepath',
                                    server_socket_path = 'somepath'
                                })
end

local g1 = t.group('proxy', {
    {is_paused = true},
    {is_paused = false}
})

g1.before_all(function(cg)
    -- Proxy only works on tarantool 2.10+
    t.run_only_if(utils.version_current_ge_than(2, 10, 1),
                  [[Proxy works on Tarantool 2.10.1+.
                    See tarantool/tarantool@57ecb6cd90b4 for details]])
    cg.rs = replica_set:new{}
    cg.box_cfg = {
        replication_timeout = 0.1,
        replication = {
            server.build_listen_uri('server2_proxy', cg.rs.id),
        },
    }
    cg.server1 = cg.rs:build_and_add_server{
        alias = 'server1',
        box_cfg = cg.box_cfg,
    }
    cg.box_cfg.replication = nil
    cg.server2 = cg.rs:build_and_add_server{
        alias = 'server2',
        box_cfg = cg.box_cfg,
    }
    cg.proxy = proxy:new{
        client_socket_path = server.build_listen_uri('server2_proxy', cg.rs.id),
        server_socket_path = server.build_listen_uri('server2', cg.rs.id),
    }
    t.assert(cg.proxy:start{force = true}, 'Proxy is started')
    cg.rs:start{}
end)

g1.test_server_disconnect_is_noticed = function(cg)
    local id = cg.server2:get_instance_id()
    t.helpers.retrying({}, cg.server1.assert_follows_upstream, cg.server1, id)
    if cg.params.is_paused then
        cg.proxy:pause()
    end
    cg.server2:stop()
    fiber.sleep(cg.box_cfg.replication_timeout)
    local upstream = cg.server1:exec(function(upstream_id)
        return box.info.replication[upstream_id].upstream
    end, {id})
    if cg.params.is_paused then
        t.assert_equals(upstream.status, 'follow',
                        'Server disconnect is not noticed')
    else
        t.assert_equals(upstream.system_message, 'Broken pipe',
                        'Server disconnect is noticed')
    end
    if cg.params.is_paused then
        cg.proxy:resume()
    end
    cg.server2:start()
end

g1.after_all(function(cg)
    cg.rs:drop()
end)
