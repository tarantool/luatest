local t = require('luatest')
local proxy = require('luatest.replica_proxy')
local utils = require('luatest.utils')

local fio = require('fio')
local socket = require('socket')

local g = t.group('proxy-readable-pause')

g.before_each(function(cg)
    -- Proxy only works on tarantool 2.10+
    t.run_only_if(utils.version_current_ge_than(2, 10, 1),
                  [[Proxy works on Tarantool 2.10.1+.
                    See tarantool/tarantool@57ecb6cd90b4 for details]])
    cg.dir = fio.tempdir()
    cg.client_sock_path = fio.pathjoin(cg.dir, 'client.sock')
    cg.server_sock_path = fio.pathjoin(cg.dir, 'server.sock')
    cg.server_listen = socket('PF_UNIX', 'SOCK_STREAM', 0)
    t.assert(cg.server_listen:bind('unix/', cg.server_sock_path))
    t.assert(cg.server_listen:listen(1))
    cg.proxy = proxy:new{
        client_socket_path = cg.client_sock_path,
        server_socket_path = cg.server_sock_path,
    }
    t.assert(cg.proxy:start{force = true}, 'Proxy is started')
    cg.client = socket.tcp_connect('unix/', cg.client_sock_path)
    t.assert(cg.client, 'Client is connected')
    t.assert(cg.server_listen:readable(10), 'Proxy connects to the server')
    cg.server = cg.server_listen:accept()
    t.assert(cg.server, 'Server accepted the connection')
    -- Make sure the link is fully alive in both directions.
    t.assert(cg.client:write('ping'))
    t.assert(cg.server:readable(10))
    t.assert_equals(cg.server:recv(4), 'ping')
    t.assert(cg.server:write('pong'))
    t.assert(cg.client:readable(10))
    t.assert_equals(cg.client:recv(4), 'pong')
end)

g.after_each(function(cg)
    cg.proxy:resume()
    cg.proxy:stop()
    cg.client:close()
    cg.server:close()
    cg.server_listen:close()
    fio.rmtree(cg.dir)
end)

--
-- Data sent right after proxy:pause() returned could still be forwarded. The
-- connection fibers were checking the pause flag only at the top of their
-- loop. A fiber which was already inside its wait for the socket to become
-- readable was forwarding the first arriving data despite the pause.
--
g.test_pause_blocks_data_sent_after_pause = function(cg)
    cg.proxy:pause()
    --
    -- The proxy connection fibers right now are already inside their socket
    -- waits, entered before the pause. The data must not go through anyway.
    --
    t.assert(cg.server:write('to client'))
    t.assert(cg.client:write('to server'))
    t.assert_not(cg.client:readable(0.5), 'Nothing is leaked to the client')
    t.assert_not(cg.server:readable(0), 'Nothing is leaked to the server')
    --
    -- The data is not lost - it finishes its trip after the resume.
    --
    cg.proxy:resume()
    t.assert(cg.client:readable(10), 'The data is delivered to the client')
    t.assert_equals(cg.client:recv(9), 'to client')
    t.assert(cg.server:readable(10), 'The data is delivered to the server')
    t.assert_equals(cg.server:recv(9), 'to server')
end
