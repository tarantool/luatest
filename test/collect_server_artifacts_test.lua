local fio = require('fio')

local t = require('luatest')
local helper = require('test.helpers.general')
local g = t.group()

local function assert_artifacts_path(s)
    t.assert(fio.path.exists(s))
    t.assert(fio.path.is_dir(s))
end

g.test_foo = function()
    local artifacts_paths

    local status = helper.run_suite(function(lu2)
        local cg = lu2.group()
        local Server = lu2.Server

        cg.before_all(function()
            cg.s_all = Server:new({alias = 'all'})
            cg.s_all2 = Server:new({alias = 'all2'})

            cg.s_all:start()
            cg.s_all2:start()
        end)

        cg.before_each(function()
            cg.s_each  = Server:new({alias = 'each'})
            cg.s_each2 = Server:new({alias = 'each2'})

            cg.s_each:start()
            cg.s_each2:start()
        end)

        cg.before_test('test_failure', function()
            cg.s_test  = Server:new({alias = 'test'})
            cg.s_test2 = Server:new({alias = 'test2'})

            cg.s_test:start()
            cg.s_test2:start()
        end)

        cg.test_failure = function()
            for _, server in ipairs({cg.s_test, cg.s_test2, cg.s_each,
                                       cg.s_each2, cg.s_all, cg.s_all2}) do
                server:exec(function() return true end)
            end

            artifacts_paths = {
                cg.s_test.artifacts,
                cg.s_test2.artifacts,
                cg.s_each.artifacts,
                cg.s_each2.artifacts,
                cg.s_all.artifacts,
                cg.s_all2.artifacts,
            }

            lu2.fail('trigger artifact saving')
        end

        cg.after_test('test_failure', function()
            cg.s_test:drop()
            cg.s_test2:drop()
        end)

        cg.after_each(function()
            cg.s_each:drop()
            cg.s_each2:drop()
        end)

        cg.after_all(function()
            cg.s_all:drop()
            cg.s_all2:drop()
        end)
    end, {'--no-clean'})

    t.assert_equals(status, 1)

    for _, path in ipairs(artifacts_paths) do
        assert_artifacts_path(path)
    end
end
