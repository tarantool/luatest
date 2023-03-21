local fio = require('fio')

local t = require('luatest')
local g = t.group()

local Server = t.Server

local function get_server_artifacts_path(s)
    return ('%s/%s'):format(s.vardir, s.id)
end

local function assert_artifacts_path(s)
    t.assert_equals(fio.path.exists(get_server_artifacts_path(s)), true)
    t.assert_equals(fio.path.is_dir(get_server_artifacts_path(s)), true)
end

g.before_all(function()
    g.s_all  = Server:new({alias = 'all'})
    g.s_all2 = Server:new({alias = 'all2'})

    g.s_all:start()
    g.s_all2:start()
end)

g.before_each(function()
    g.s_each  = Server:new({alias = 'each'})
    g.s_each2 = Server:new({alias = 'each2'})

    g.s_each:start()
    g.s_each2:start()
end)

g.before_test('test_foo', function()
    g.s_test  = Server:new({alias = 'test'})
    g.s_test2 = Server:new({alias = 'test2'})

    g.s_test:start()
    g.s_test2:start()
end)

g.test_foo = function()
    t.xfail()
    t.assert_equals(1, 2)
end

g.after_test('test_foo', function()
    g.s_test:drop()
    g.s_test2:drop()

    assert_artifacts_path(g.s_test)
    assert_artifacts_path(g.s_test2)
end)

g.after_each(function()
    g.s_each:drop()
    g.s_each2:drop()

    assert_artifacts_path(g.s_each)
    assert_artifacts_path(g.s_each2)
end)

g.after_all(function()
    g.s_all:drop()
    g.s_all2:drop()

    assert_artifacts_path(g.s_all)
    assert_artifacts_path(g.s_all2)
end)