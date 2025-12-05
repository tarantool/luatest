local t = require('luatest')
local utils = require('luatest.utils')
local fio = require('fio')

local g = t.group()
local Server = t.Server
local deferred_artifact_checks = {}

local function is_server_in_test(server, test)
    for _, s in pairs(test.servers) do
        if server.id == s.id then
            return true
        end
    end
    return false
end

g.public = Server:new({alias = 'public'})
g.public:start()

g.before_all(function()
    g.all = Server:new({alias = 'all9'})
    g.all:start()
end)

g.before_each(function()
    g.each = Server:new({alias = 'each'})
    g.each:start()
end)

g.before_test('test_association_between_test_and_servers', function()
    g.test = Server:new({alias = 'test'})
    g.test:start()
end)

g.test_association_between_test_and_servers = function()
    g.internal = Server:new({alias = 'internal'})
    g.internal:start()

    local test = rawget(_G, 'current_test').value

    -- test static association
    t.assert(is_server_in_test(g.internal, test))
    t.assert(is_server_in_test(g.each, test))
    t.assert(is_server_in_test(g.test, test))
    t.assert_not(is_server_in_test(g.public, test))

    g.public:exec(function() return 1 + 1 end)
    g.all:exec(function() return 1 + 1 end)

    -- test dynamic association
    t.assert(is_server_in_test(g.public, test))
    t.assert(is_server_in_test(g.all, test))

    t.assert(utils.table_len(test.servers) == 5)
end

g.after_test('test_association_between_test_and_servers', function()
    local ctx = rawget(_G, 'current_test')
    local test = ctx.value
    ctx.runner:update_status(test, {status = 'fail'})
    g.internal:drop()
    g.test:drop()
    test:update_status('success')
    table.insert(deferred_artifact_checks, function()
        t.assert(fio.path.exists(g.test.artifacts))
    end)
end)

g.after_each(function()
    g.each:drop()
    table.insert(deferred_artifact_checks, function()
        t.assert(fio.path.exists(g.each.artifacts))
    end)
end)

g.after_all(function()
    g.all:drop()
    table.insert(deferred_artifact_checks, function()
        t.assert(fio.path.exists(g.all.artifacts))
    end)
    g.public:drop()
    for _, check in ipairs(deferred_artifact_checks) do
        check()
    end
end)
