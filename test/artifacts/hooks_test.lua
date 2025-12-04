local t = require('luatest')
local utils = require('luatest.utils')
local fio = require('fio')
local helper = require('test.helpers.general')

local g = t.group()

local function is_server_in_test(server, test)
    for _, s in pairs(test.servers) do
        if server.id == s.id then
            return true
        end
    end
    return false
end

g.test_association_between_test_and_servers = function()
    local artifacts_paths

    local status = helper.run_suite(function(lu2)
        local cg = lu2.group()
        local Server = lu2.Server

        cg.public = Server:new({alias = 'public'})
        cg.public:start()

        cg.before_all(function()
            cg.all = Server:new({alias = 'all9'})
            cg.all:start()
        end)

        cg.before_each(function()
            cg.each = Server:new({alias = 'each'})
            cg.each:start()
        end)

        cg.before_test('test_inner', function()
            cg.test = Server:new({alias = 'test'})
            cg.test:start()
        end)

        cg.test_inner = function()
            cg.internal = Server:new({alias = 'internal'})
            cg.internal:start()

            local test = rawget(_G, 'current_test').value

            -- test static association
            lu2.assert(is_server_in_test(cg.internal, test))
            lu2.assert(is_server_in_test(cg.each, test))
            lu2.assert(is_server_in_test(cg.test, test))
            lu2.assert_not(is_server_in_test(cg.public, test))

            cg.public:exec(function() return 1 + 1 end)
            cg.all:exec(function() return 1 + 1 end)

            -- test dynamic association
            lu2.assert(is_server_in_test(cg.public, test))
            lu2.assert(is_server_in_test(cg.all, test))

            lu2.assert(utils.table_len(test.servers) == 5)

            artifacts_paths = {
                test = cg.test.artifacts,
                each = cg.each.artifacts,
                all = cg.all.artifacts,
                public = cg.public.artifacts,
                internal = cg.internal.artifacts,
            }

            lu2.fail('trigger artifact saving')
        end

        cg.after_test('test_inner', function()
            cg.internal:drop()
            cg.test:drop()
        end)

        cg.after_each(function()
            cg.each:drop()
        end)

        cg.after_all(function()
            cg.all:drop()
            cg.public:drop()
        end)
    end, {'--no-clean'})

    t.assert_equals(status, 1)

    for _, path in pairs(artifacts_paths) do
        t.assert(fio.path.exists(path))
    end
end
