local t = require('luatest')
local utils = require('luatest.utils')

local g = t.group()
local Server = t.Server

g.public = Server:new({ alias = 'public'})
g.public:start()

g.test_servers_not_added_if_they_are_not_used = function()
end

g.after_test('test_servers_not_added_if_they_are_not_used', function()
    t.fail_if(
        utils.table_len(rawget(_G, 'current_test').value.servers) ~= 0,
        'Test instance should not contain a servers')
end)

g.test_only_public_server_has_been_added = function()
    g.public:get_vclock()
end

g.after_test('test_only_public_server_has_been_added', function()
    t.fail_if(
        rawget(_G, 'current_test').value.servers[g.public.id] == nil,
        'Test should contain only public server')
end)


g.test_only_private_server_has_been_added = function()
    g.private = Server:new({alias = 'private'})
    g.private:start()
end

g.after_test('test_only_private_server_has_been_added', function()
    t.fail_if(
        rawget(_G, 'current_test').value.servers[g.private.id] == nil,
        'Test should contain only private server')

end)

g.before_test('test_add_server_from_test_hooks', function()
    g.before = Server:new({ alias = 'before' })
    g.before:start()
end)

g.test_add_server_from_test_hooks = function()
end

g.after_test('test_add_server_from_test_hooks', function()
    g.after = Server:new({ alias = 'after' })
    g.after:start()

    local test_servers = rawget(_G, 'current_test').value.servers

    t.fail_if(
        utils.table_len(test_servers) ~= 2,
        'Test should contain two servers (from before/after hooks)')
    t.fail_if(
        test_servers[g.before.id] == nil or
        test_servers[g.after.id] == nil,
        'Test should contain only `before` and `after` servers')
end)
