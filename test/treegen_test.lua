local t = require('luatest')
local fio = require('fio')

local treegen = require('luatest.treegen')

local g = t.group()


local function assert_file_content_equals(file, expected)
    local fh = fio.open(file)
    t.assert_equals(fh:read(), expected)
end

g.test_prepare_directory = function()
    treegen.add_template('^.*$', 'test_script')
    local dir = treegen.prepare_directory({'foo/bar.lua', 'baz.lua'})

    t.assert(fio.path.is_dir(dir))
    t.assert(fio.path.exists(dir))

    t.assert(fio.path.exists(fio.pathjoin(dir, 'foo', 'bar.lua')))
    t.assert(fio.path.exists(fio.pathjoin(dir, 'baz.lua')))

    assert_file_content_equals(fio.pathjoin(dir, 'foo', 'bar.lua'), 'test_script')
    assert_file_content_equals(fio.pathjoin(dir, 'baz.lua'), 'test_script')
end

g.before_test('test_clean_keep_data', function()
    treegen.add_template('^.*$', 'test_script')

    os.setenv('KEEP_DATA', 'true')

    g.dir = treegen.prepare_directory(g, {'foo.lua'})

    t.assert(fio.path.is_dir(g.dir))
    t.assert(fio.path.exists(g.dir))
end)

g.test_clean_keep_data = function()
    t.assert(fio.path.is_dir(g.dir))
    t.assert(fio.path.exists(g.dir))
end

g.after_test('test_clean_keep_data', function()
    os.setenv('KEEP_DATA', '')
    t.assert(fio.path.is_dir(g.dir))
    t.assert(fio.path.exists(g.dir))
end)
