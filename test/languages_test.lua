-- Languages compiled to Lua: discovery, helpers, traces and servers.
--
-- The tests use the toy language from test/fixtures/languages/toy.lua:
-- Lua with a `#toy` first line and `fn` instead of `function`.

local fio = require('fio')
local popen = require('popen')

local t = require('luatest')
local Server = t.Server
local treegen = require('luatest.treegen')

local g = t.group()

local ROOT = fio.dirname(fio.dirname(package.search('luatest.runner')))
local FIXTURES = fio.pathjoin(ROOT, 'test', 'fixtures', 'languages')
local TOY = 'test.fixtures.languages.toy'
local DEFAULT_INSTANCE = fio.pathjoin(ROOT, 'luatest', 'server_instance.lua')

local function read_file(path)
    local fh = assert(io.open(path))
    local content = fh:read('*a')
    fh:close()
    return content
end

-- Create a project directory with the toy language module (`toy`), the toy
-- module `answer` and the given files.
local function make_project(files)
    local dir = fio.tempdir()
    treegen.write_file(dir, 'toy.lua', read_file(fio.pathjoin(FIXTURES, 'toy.lua')))
    treegen.write_file(dir, 'answer.toy', read_file(fio.pathjoin(FIXTURES, 'answer.toy')))
    for name, content in pairs(files) do
        treegen.write_file(dir, name, content)
    end
    return dir
end

-- Run bin/luatest in the project directory and return its exit code and the
-- combined stdout and stderr.
--
-- The project is the search root of the run, so its `test.helper` is the one
-- looked up. luatest and checks are found through LUA_PATH.
local function run_luatest(dir, args)
    local checks_dir = fio.dirname(package.search('checks'))
    local lua_path = table.concat({
        ROOT .. '/?.lua', ROOT .. '/?/init.lua',
        checks_dir .. '/?.lua', checks_dir .. '/?/init.lua',
    }, ';') .. ';;'
    local command = ("cd '%s' && LUA_PATH='%s' VARDIR='%s' '%s' '%s' %s 2>&1"):format(
        dir, lua_path, fio.pathjoin(dir, 'var'), arg[-1],
        fio.pathjoin(ROOT, 'bin', 'luatest'), table.concat(args or {}, ' '))
    local ph = popen.shell(command, 'r')
    local chunks = {}
    while true do
        local chunk = assert(ph:read())
        if chunk == '' then
            break
        end
        table.insert(chunks, chunk)
    end
    local exit_code = ph:wait().exit_code
    ph:close()
    return exit_code, table.concat(chunks)
end

local PLAIN_TEST = [[
local t = require('luatest')
local g = t.group('plain')

g.test_ok = function()
    t.assert(true)
end
]]

local TOY_TEST = [[
#toy
local t = require('luatest')
local util = require('test.util')
local g = t.group()

g.test_compiled = fn()
    t.assert_equals(util.double(21), 42)
end
]]

local TOY_UTIL = [[
#toy
return {double = fn(x) return x * 2 end}
]]

local TOY_NESTED_TEST = [[
#toy
local t = require('luatest')
local g = t.group()

g.test_deep = fn()
    t.assert(true)
end
]]

local function make_suite(extra)
    local files = {
        ['test/plain_test.lua'] = PLAIN_TEST,
        ['test/toy_suite_test.toy'] = TOY_TEST,
        ['test/util.toy'] = TOY_UTIL,
        ['test/nested/deep_test.toy'] = TOY_NESTED_TEST,
    }
    for k, v in pairs(extra or {}) do
        files[k] = v
    end
    return make_project(files)
end

g.test_discover_directory_with_cli_language = function()
    local dir = make_suite()

    local code, output = run_luatest(dir, {'--language', 'toy', '--list-test-cases'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'nested.deep.test_deep\nplain.test_ok\ntoy_suite.test_compiled\n')

    code, output = run_luatest(dir, {'--language', 'toy'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'Ran 3 tests')
end

g.test_discover_single_file = function()
    local dir = make_suite()

    local code, output = run_luatest(dir, {
        '--language', 'toy', '--list-test-cases', 'test/toy_suite_test.toy',
    })
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'toy_suite.test_compiled\n')
    t.assert_not_str_contains(output, 'plain.test_ok')
    t.assert_not_str_contains(output, 'nested.deep.test_deep')
end

g.test_without_language_toy_files_are_ignored = function()
    local dir = make_suite()

    local code, output = run_luatest(dir, {'--list-test-cases'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'plain.test_ok\n')
    t.assert_not_str_contains(output, 'toy_suite.test_compiled')
end

g.test_configure_languages = function()
    local dir = make_suite({
        ['test/helper.lua'] = "require('luatest').configure({languages = {'toy'}})\n",
    })

    local code, output = run_luatest(dir, {'--list-test-cases'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'nested.deep.test_deep\nplain.test_ok\ntoy_suite.test_compiled\n')
end

g.test_helper_in_language = function()
    local dir = make_project({
        ['test/helper.toy'] = table.concat({
            '#toy',
            "local set = fn(value) rawset(_G, 'toy_helper', value) end",
            "set('loaded')",
        }, '\n'),
        ['test/helped_test.lua'] = table.concat({
            "local t = require('luatest')",
            "local g = t.group('helped')",
            'g.test_helper_loaded = function()',
            "    t.assert_equals(rawget(_G, 'toy_helper'), 'loaded')",
            'end',
        }, '\n'),
    })

    local code, output = run_luatest(dir, {'--language', 'toy'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'Ran 1 tests')
    t.assert_str_contains(output, '1 succeeded')
end

g.test_error_trace_names_source_file = function()
    local dir = make_project({
        ['test/toy_fail_test.toy'] = table.concat({
            '#toy',                         -- 1
            "local t = require('luatest')", -- 2
            'local g = t.group()',          -- 3
            '',                             -- 4
            'local fn raise()',             -- 5
            "    error('toy boom')",        -- 6
            'end',                          -- 7
            '',                             -- 8
            'g.test_error = fn()',          -- 9
            '    raise()',                  -- 10
            'end',                          -- 11
        }, '\n'),
    })

    local code, output = run_luatest(dir, {'--language', 'toy'})
    t.assert_equals(code, 1, output)
    t.assert_str_contains(output, 'test/toy_fail_test.toy:6: toy boom')
    t.assert_str_matches(output, ".*test/toy_fail_test%.toy:6: in function 'raise'\n.*")
    t.assert_str_matches(output, ".*test/toy_fail_test%.toy:10: in function 'toy_fail%.test_error'\n.*")
end

g.test_bad_language_module = function()
    local dir = make_suite()

    local code, output = run_luatest(dir, {'--language', 'no_such_language'})
    t.assert_not_equals(code, 0, output)
    t.assert_str_contains(output, "Failed to load language module 'no_such_language'")
    t.assert_str_contains(output, "module 'no_such_language' not found")

    code, output = run_luatest(dir, {'--language', 'test.fixtures.languages.bad_extensions'})
    t.assert_not_equals(code, 0, output)
    t.assert_str_contains(output,
        "Language module 'test.fixtures.languages.bad_extensions' must return a table " ..
        "with a non-empty 'extensions' list")
end

g.test_servers_of_the_run_get_the_language = function()
    local dir = make_project({
        ['test/server_lang_test.lua'] = [[
local t = require('luatest')
local Server = t.Server
local g = t.group('server_lang')

local function require_answer(s)
    return {s:exec(function()
        local ok, res = pcall(require, 'answer')
        if not ok then
            return false, tostring(res)
        end
        return true, res.value
    end)}
end

g.test_default = function()
    local s = Server:new({alias = 'default'})
    s:start()
    local res = require_answer(s)
    s:drop()
    t.assert_equals(res, {true, 42})
end

g.test_none = function()
    local s = Server:new({alias = 'none', languages = {}})
    s:start()
    local res = require_answer(s)
    s:drop()
    t.assert_equals(res[1], false)
    t.assert_str_contains(res[2], "module 'answer' not found")
end
]],
    })

    local code, output = run_luatest(dir, {'--language', 'toy'})
    t.assert_equals(code, 0, output)
    t.assert_str_contains(output, 'Ran 2 tests')
    t.assert_str_contains(output, '2 succeeded')
end

-- Servers started from this process: the languages are given explicitly.

local function require_answer(s)
    return {s:exec(function()
        local ok, res = pcall(require, 'test.fixtures.languages.answer')
        if not ok then
            return false, tostring(res)
        end
        return true, res.value
    end)}
end

g.after_each(function(cg)
    if cg.server ~= nil then
        cg.server:drop()
        cg.server = nil
    end
end)

g.test_server_script_command_languages = function(cg)
    cg.server = Server:new({alias = 'script', languages = {TOY}})
    cg.server:start()
    t.assert_equals(require_answer(cg.server), {true, 42})
end

g.test_server_tarantool_command_languages = function(cg)
    cg.server = Server:new({
        alias = 'binary',
        command = arg[-1],
        args = {DEFAULT_INSTANCE},
        languages = {TOY},
    })
    cg.server:start({wait_until_ready = true})
    t.assert_equals(require_answer(cg.server), {true, 42})
end

g.test_server_no_languages = function(cg)
    cg.server = Server:new({alias = 'nolang', languages = {}})
    cg.server:start()
    local res = require_answer(cg.server)
    t.assert_equals(res[1], false)
    t.assert_str_contains(res[2], "module 'test.fixtures.languages.answer' not found")
end

g.test_server_languages_option_is_checked = function()
    t.assert_error_msg_contains('bad argument', Server.new, Server, {languages = TOY})
    t.assert_error_msg_contains('languages must be a list of module names',
        Server.new, Server, {languages = {42}})
end

-- The registry itself, on fresh instances so the run's state is untouched.

local PRELOADED = {
    fake_lang = function() return {extensions = {'fake'}} end,
    fake_toy = function() return {extensions = {'toy'}} end,
    fake_two = function() return {extensions = {'one', 'two'}} end,
    fake_raises = function() error('fake language is broken', 0) end,
    fake_number = function() return 42 end,
    fake_no_list = function() return {extensions = 'fake'} end,
    fake_dot = function() return {extensions = {'.fake'}} end,
}

g.before_test('test_registry', function()
    for name, loader in pairs(PRELOADED) do
        package.preload[name] = loader
    end
end)

g.after_test('test_registry', function()
    for name in pairs(PRELOADED) do
        package.preload[name] = nil
        package.loaded[name] = nil
    end
end)

g.test_registry = function()
    local languages = require('luatest.languages')
    local registry = languages.new()

    t.assert_equals(registry:extensions(), {'lua'})
    t.assert_equals(registry:modules(), {})
    t.assert_equals({registry:strip_extension('a/b_test.lua')}, {'a/b_test', 'lua'})
    t.assert_equals(registry:strip_extension('a/b_test.fake'), nil)

    t.assert_equals(registry:use('fake_lang'), {extensions = {'fake'}})
    registry:use({'fake_two', 'fake_lang'})
    t.assert_equals(registry:modules(), {'fake_lang', 'fake_two'})
    t.assert_equals(registry:extensions(), {'lua', 'fake', 'one', 'two'})
    t.assert_equals({registry:strip_extension('a/b_test.fake')}, {'a/b_test', 'fake'})
    t.assert_equals({registry:strip_extension('a.two')}, {'a', 'two'})

    -- A fresh registry does not see the languages of another one.
    t.assert_equals(languages.new():extensions(), {'lua'})

    t.assert_error_msg_contains("Failed to load language module 'fake_raises': fake language is broken",
        registry.use, registry, 'fake_raises')
    t.assert_error_msg_contains("Failed to load language module 'fake_missing'",
        registry.use, registry, 'fake_missing')
    t.assert_error_msg_contains("Language module 'fake_number' must return a table " ..
        "with a non-empty 'extensions' list, got: 42", registry.use, registry, 'fake_number')
    t.assert_error_msg_contains("Language module 'fake_no_list' must return a table",
        registry.use, registry, 'fake_no_list')
    t.assert_error_msg_contains("Language module 'fake_dot' has an invalid extension \".fake\"",
        registry.use, registry, 'fake_dot')
    t.assert_error_msg_contains('Language module name must be a string',
        registry.use, registry, {42})
    -- Failed modules are not registered.
    t.assert_equals(registry:modules(), {'fake_lang', 'fake_two'})

    -- Lookup of a module: Lua first, then the language extensions along the
    -- search root and package.path.
    local toy = languages.new()
    t.assert_equals(toy:search('luatest.runner'), package.search('luatest.runner'))
    t.assert_equals(toy:search('test.fixtures.languages.answer'), nil)
    toy:use('fake_toy')
    t.assert_equals(toy:search('test.fixtures.languages.answer'), fio.pathjoin(FIXTURES, 'answer.toy'))
    t.assert_equals(toy:search('test.fixtures.languages.missing'), nil)
end
