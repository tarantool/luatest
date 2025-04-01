local fio = require('fio')
local json = require('json')
local urilib = require('uri')

local t = require('luatest')
local g = t.group()
local utils = require('luatest.utils')

local helper = require('test.helpers.general')

local Process = t.Process
local Server = t.Server

local root = fio.dirname(fio.abspath('test.helpers'))
local datadir = fio.pathjoin(root, 'tmp', 'db_test')
local command = fio.pathjoin(root, 'test', 'server_instance.lua')

local server = Server:new({
    command = command,
    workdir = fio.pathjoin(datadir, 'common'),
    env = {
        LUA_PATH = root .. '/?.lua;' ..
            root .. '/?/init.lua;' ..
            root .. '/.rocks/share/tarantool/?.lua',
        custom_env = 'test_value',
    },
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
    server:stop()
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

g.test_restart = function()
    local workdir = fio.pathjoin(datadir, 'restart')
    fio.mktree(workdir)
    local s = Server:new({command = command, workdir = workdir, alias = 'Bob'})
    local orig_args = table.copy(s.args)

    s:start()

    -- Restart server with the same args
    local pid = s.process.pid
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert(Process.is_pid_alive(pid))
    end)
    s:restart()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(Process.is_pid_alive(pid))
    end)
    pid = s.process.pid
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert(Process.is_pid_alive(pid))
    end)
    t.assert_equals(s.args, orig_args)

    -- Restart server with another args
    local new_args = {'test', 'args'}
    s:restart({args = new_args, alias = 'Tom'})
    pid = s.process.pid
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert(Process.is_pid_alive(pid))
    end)
    t.assert_equals(s.args, new_args)
    t.assert_equals(s.env.TARANTOOL_ALIAS, 'Tom')

    s:stop()
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

g.test_http_request_post_body = function()
    local value = "{field = 'data'}"
    local response = server:http_request('post', '/echo', {body = value})
    t.assert_equals(response.json.body, value)
    t.assert_equals(response.json.request_headers['content-type'], 'application/x-www-form-urlencoded')
end

g.test_http_request_post_json = function()
    local value = {field = 'data'}
    local response = server:http_request('post', '/echo', {json = value})
    t.assert_equals(response.json.body, json.encode(value))
    t.assert_equals(response.json.request_headers['content-type'], 'application/json')
end

g.test_http_request_post_json_with_custom_headers = function()
    local value = {field = 'data'}
    local response = server:http_request('post', '/echo', {json = value, http = {headers = {head_key = 'head_val'}}})
    t.assert_equals(response.json.body, json.encode(value))
    t.assert_equals(response.json.request_headers['content-type'], 'application/json')
    t.assert_equals(response.json.request_headers.head_key, 'head_val')

    response = server:http_request('post', '/echo', {json = value, http = {headers = {['Content-Type'] = 'head_val'}}})
    t.assert_equals(response.json.body, json.encode(value))
    t.assert_equals(response.json.request_headers['content-type'], 'head_val')
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
    t.assert_equals(server:eval('return os.getenv("custom_env")'), 'test_value')

    server.net_box:close()
    t.assert_equals(server.net_box.state, 'closed')
    server:connect_net_box()
    t.assert_equals(server.net_box.state, 'active')

    server:eval('function f(x,y) return {x, y} end;')
    t.assert_equals(server:call('f', {1, 'test'}), {1, 'test'})

    server.net_box:close()
    t.assert_error_msg_equals('Connection closed', server.eval, server, '')
    t.assert_error_msg_equals('Connection closed', server.call, server, '')

    server.net_box = nil
    t.assert_error_msg_equals('net_box is not connected', server.eval, server, '')
    t.assert_error_msg_equals('net_box is not connected', server.call, server, '')
end

g.test_net_box_exec = function()
    server:connect_net_box()

    t.assert_equals(
        {server:exec(function() return 3, 5, 8 end)},
        {3, 5, 8}
    )

    t.assert_equals(
        server:exec(function(a, b) return a + b end, {21, 34}),
        55
    )

    local function efmt(line, e)
        -- Little helper to check where the error actually points to
        local _src = debug.getinfo(1, 'S').short_src
        return string.format('%s:%s: %s', _src, line, e)
    end

    local function l()
        return debug.getinfo(2, 'Sl').currentline
    end

    local _l_exec, exec = l(), function(fn) server:exec(fn) end

    do
        local foo, bar = 200, 300
        local fn = function() return foo, bar end
        t.assert_error_msg_equals(
            efmt(_l_exec, 'bad argument #2 to exec' ..
                ' (excess upvalues: foo, bar)'),
            exec, fn
        )
    end

    do
        local _l_fn, fn = l(), function() error('X_x') end
        t.assert_error_msg_equals(
            efmt(_l_fn, 'X_x'),
            exec, fn
        )
    end

    do
        local _l_fn, fn = l(), function() require('luatest').assert(false) end
        local err = t.assert_error(
            exec, fn
        )
        t.assert(utils.is_luatest_error(err), err)
        t.assert_equals(
            err.message,
            efmt(_l_fn, 'expected: a value evaluating to true, actual: false')
        )
    end

    server.net_box:close()
    t.assert_error_msg_equals(
        'Connection closed',
        exec, function() end
    )

    server.net_box = nil
    t.assert_error_msg_equals(
        efmt(_l_exec, 'net_box is not connected'),
        exec, function() end
    )
end

g.test_inherit = function()
    local child = Server:inherit({})
    local instance = child:new({command = 'test-cmd', workdir = 'test-dir'})
    t.assert_equals(instance.start, Server.start)
end

g.test_update_params = function()
    local workdir = fio.pathjoin(datadir, 'update')
    fio.mktree(workdir)
    local s = Server:new({command = command, workdir = workdir, alias = 'Bob'})
    -- env is initialized when server is built
    t.assert_equals(s.env.TARANTOOL_ALIAS, 'Bob')
    s.alias = 'Tom'
    -- env is not updated on the fly. It must be done manually
    -- or server should be restarted.
    t.assert_not_equals(s.env.TARANTOOL_ALIAS, 'Tom')
    s:start()
    -- After server restart its params are updated just as
    -- during initial building
    t.assert_equals(s.env.TARANTOOL_ALIAS, 'Tom')
    s:stop()
end

g.test_unix_socket = function()
    local workdir = fio.pathjoin(datadir, 'unix_socket')
    fio.mktree(workdir)
    local s = Server:new({
        command = command,
        workdir = workdir,
        net_box_uri = fio.pathjoin(workdir, '/test_socket.sock'),
        http_port = 0, -- unused
    })
    s:start()
    t.helpers.retrying({}, function() s:connect_net_box() end)
    t.assert_str_matches(
        s:eval('return box.info.status'),
        'running'
    )
    s:stop()
end

g.test_max_unix_socket_path_exceeded = function()
    local max_unix_socket_path = {linux = 107, other = 103}
    local system = os.execute('[ $(uname) = Linux ]') == 0 and 'linux' or 'other'
    local workdir = fio.pathjoin(datadir, 'unix_socket')
    local workdir_len = string.len(workdir)
    local socket_name_len = max_unix_socket_path[system] + 1 - workdir_len
    local socket_name = string.format('test_socket%s.sock', string.rep('t', socket_name_len - 17))
    local net_box_uri = fio.pathjoin(workdir, socket_name)

    t.assert_equals(string.len(net_box_uri), max_unix_socket_path[system] + 1)
    t.assert_error_msg_contains(
        string.format('Unix domain socket path cannot be longer than %d ' ..
                      'chars. Current path is:', max_unix_socket_path[system]),
        Server.new, Server, {
            command = command,
            workdir = workdir,
            net_box_uri = net_box_uri,
            http_port = 0, -- unused
        }
    )
end

g.test_unix_socket_not_include_uri_fields = function()
    local max_unix_socket_path = {linux = 107, other = 103}
    local system = os.execute('[ $(uname) = Linux ]') == 0 and 'linux' or
                   'other'
    local workdir = fio.pathjoin(datadir, 'unix_socket')
    fio.mktree(workdir)
    local workdir_len = string.len(workdir)
    local socket_name_len = max_unix_socket_path[system] + 1 - workdir_len
    local socket_name = string.format('test_socket%s.sock',
                                      string.rep('t', socket_name_len - 18))
    local socket_path = fio.pathjoin(workdir, socket_name)
    t.assert_equals(string.len(socket_path), max_unix_socket_path[system])
    local net_box_uri = 'unix/:' .. socket_path .. '?three=1&four=2'
    local s = Server:new({
        command = command,
        workdir = workdir,
        net_box_uri = net_box_uri,
        http_port = 0, -- unused
    })
    s:start()
    t.helpers.retrying({}, function() s:connect_net_box() end)
    t.assert_equals(s:exec(function() return box.cfg.listen end), net_box_uri)
    s:stop()
end

g.test_table_uri_success = function()
    t.skip_if(not utils.version_current_ge_than(2, 10, 0),
              "URI as a table is supported since Tarantool 2.10.0.")
    local workdir = fio.pathjoin(datadir, 'unix_socket')
    fio.mktree(workdir)
    local net_box_uri = {
        uri = 'unix/:' .. fio.pathjoin(workdir, '/test_socket.sock'),
        params = {
            transport = 'plain'
        },
    }
    local res = urilib.format(urilib.parse(net_box_uri))
    local s = Server:new({
        command = command,
        workdir = workdir,
        net_box_uri = net_box_uri,
        http_port = 0, -- unused
    })
    s:start()
    t.helpers.retrying({}, function() s:connect_net_box() end)
    t.assert_equals(s:exec(function() return box.cfg.listen end), res)
    s:stop()
end

g.test_table_uri_error = function()
    t.skip_if(utils.version_current_ge_than(2, 10, 0),
              "URI as a table is supported since Tarantool 2.10.0.")
    local workdir = fio.pathjoin(datadir, 'unix_socket')
    fio.mktree(workdir)
    local net_box_uri = {
        login = 'guest',
        uri = 'unix/:' .. fio.pathjoin(workdir, '/test_socket.sock'),
        params = {
            transport = 'plain'
        },
    }
    local err = [[bad argument #2 to 'uri_parse' (cannot convert 'table' ]] ..
                [[to 'const char *')]]
    t.assert_error_msg_contains(
        err, Server.new, Server, {
            command = command,
            workdir = workdir,
            net_box_uri = net_box_uri,
            http_port = 0, -- unused
        }
    )
end

g.test_server_start_with_coverage_enabled = function()
    t.skip_if(server.coverage_report, 'Coverage is already enabled. Nothing to test')
    server:restart({coverage_report = true})
    t.helpers.retrying({}, function() server:connect_net_box() end)
    t.assert_str_matches(
        server:exec(function() return box.info.status end), 'running'
    )
end

g.test_wait_when_server_is_not_running_by_bad_option = function()
    local s1 = Server:new({
        box_cfg = {
            bad_option = 'bad'
        }
    })
    local s2 = Server:new({
        box_cfg = {
            replication = {
                'bad_uri'
            }
        }
    })

    local expected_msg = 'Process is terminated when waiting for "server is ready"'

    local status, msg = pcall(Server.start, s1)
    t.assert_equals(status, false)
    t.assert_str_contains(msg, expected_msg)
    t.assert_equals(s1.process:is_alive(), false)
    s1:drop()

    status, msg = pcall(Server.start, s2)
    t.assert_equals(status, false)
    t.assert_str_contains(msg, expected_msg)
    t.assert_equals(s2.process:is_alive(), false)
    s2:drop()
end

g.test_drop_server_if_process_is_dead = function()
    local s = Server:new({
        box_cfg = {
            bad_option = 'bad'
        }
    })
    local status, _ = pcall(Server.start, s)
    t.assert_equals(status, false)
    t.assert_equals(s.process:is_alive(), false)

    s:drop()
end

g.test_save_server_artifacts_when_test_failed = function()
    local s1 = Server:new() -- empty config
    local s2 = Server:new(
        {workdir = ('%s/%s'):format(Server.vardir, os.tmpname())}
    ) -- workdir passed

    s1:start()
    s2:start()

    local s1_artifacts = ('%s/artifacts/%s'):format(s1.vardir, s1.id)
    local s2_artifacts = ('%s/artifacts/%s'):format(s2.vardir, s2.id)
    local test = rawget(_G, 'current_test')

    -- the test must be failed to save artifacts
    test.status = 'fail'
    s1:drop()
    s2:drop()
    test.status = 'success'

    t.assert_equals(fio.path.exists(s1_artifacts), true)
    t.assert_equals(fio.path.is_dir(s1_artifacts), true)

    t.assert_equals(fio.path.exists(s2_artifacts), true)
    t.assert_equals(fio.path.is_dir(s2_artifacts), true)
end

g.test_server_build_listen_uri = function()
    local uri = Server.build_listen_uri('foo')
    t.assert_equals(uri, ('%s/foo.sock'):format(Server.vardir))

    local uri_extra = Server.build_listen_uri('foo', 'bar')
    t.assert_equals(uri_extra, ('%s/bar/foo.sock'):format(Server.vardir))
end

g.before_test('test_no_socket_collision_with_default_alias', function()
    g.s1 = Server:new()
    g.s2 = Server:new()

    g.s1:start()
    g.s2:start()
end)

g.test_no_socket_collision_with_default_alias = function()
    g.s1:exec(function() rawset(_G, 'foo', 'foo-value') end)
    local foo = g.s2:exec(function() rawget(_G, 'foo') end)

    t.assert_equals(foo, nil)
    t.assert_not_equals(g.s1.net_box_uri, g.s2.net_box_uri)
end

g.after_test('test_no_socket_collision_with_default_alias', function()
    g.s1:drop()
    g.s2:drop()
end)

g.test_no_socket_collision_with_duplicate_alias = function()
    g.s1 = Server:new({alias = 'foo'})
    g.s2 = Server:new({alias = 'foo'})

    t.assert_not_equals(g.s1.net_box_uri, g.s2.net_box_uri)
end

g.after_test('test_no_socket_collision_with_duplicate_alias', function()
    g.s1:drop()
    g.s2:drop()
end)

g.test_netbox_uri_is_not_overridden = function()
    local socket = ('%s/my-custom.sock'):format(Server.vardir)
    g.s1 = Server:new({net_box_uri = socket})

    t.assert_equals(g.s1.net_box_uri, socket)
end

g.after_test('test_netbox_uri_is_not_overridden', function()
    g.s1:drop()
end)

g.before_test('test_error_level_is_correct', function()
    g.s = Server:new()
    g.s:start()
end)

g.test_error_level_is_correct = function()
    local c = require('net.box').connect(g.s.net_box_uri)

    t.assert_error_msg_contains( -- error in exec
        "My error", g.s.exec, g.s,
        function() error("My error") end)

    t.assert_error_msg_contains( -- error in eval
        "eval", g.s.eval, g.s,
        [[error("My error")]])

    t.assert_error_msg_contains( -- error in closures
        "My error", g.s.exec, g.s,
        function()
            local function internal() error("My error") end
            internal()
        end)

    t.assert_error_msg_contains( -- error in tx netbox connection
        "My error", c.eval, c,
        [[box.begin() error("My error")]])

    t.assert_error_msg_contains( -- error in tx eval
        "My error", g.s.eval, g.s,
        [[box.begin() error("My error")]])

    t.assert_error_msg_contains( -- error in tx exec
        "My error", g.s.exec, g.s,
        function() box.begin() error("My error") end)

    t.assert_error_msg_contains( -- error in tx closures
        "My error", g.s.exec, g.s,
        function()
            local function internal() box.begin() error("My error") end
            internal()
        end)
end

g.after_test('test_error_level_is_correct', function()
    g.s:drop()
end)

g.test_grep_log = function()
    server:connect_net_box()

    -- Test that grep_log just works.
    server:exec(function() require('log').info('test grep_log') end)
    t.assert(server:grep_log('test grep_log'))

    -- By default opts.reset in server:grep_log() is true, so we
    -- should not find the message after instance restart.
    server:restart()
    t.helpers.retrying({}, function() server:http_request('get', '/ping') end)
    server:connect_net_box()
    t.assert_not(server:grep_log('test grep_log'))

    server.net_box:close()
    server.net_box = nil
end

g.before_test('test_assertion_failure', function()
    -- The compat module option may be unavailable.
    pcall(function()
        local compat = require('compat')
        compat.box_error_serialize_verbose = 'new'
    end)
end)

g.after_test('test_assertion_failure', function()
    pcall(function()
        require('compat').box_error_serialize_verbose = 'default'
    end)
end)

g.test_assertion_failure = function()
    server:connect_net_box()
    helper.assert_failure(server.exec, server, function() t.assert(false) end)
end
