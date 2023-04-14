local t = require('luatest')
local proxy = require('luatest.replica_proxy')
local utils = require('luatest.utils')

local g = t.group('proxy-version-check')

g.test_proxy_errors = function()
    t.skip_if(utils.version_ge(utils.get_tarantool_version(),
                               utils.version(2, 10, 1)),
              "Proxy works on Tarantool 2.10.1+, nothing to test")
    t.assert_error_msg_contains('Proxy requires Tarantool 2.10.1 and newer',
                                proxy.new, proxy, {
                                    client_socket_path = 'somepath',
                                    server_socket_path = 'somepath'
                                })
end
