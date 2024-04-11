local t = require('luatest')
local fio = require('fio')

local justrun = require('luatest.justrun')
local utils = require('luatest.utils')

local g = t.group()

g.before_each(function()
    g.tempdir = fio.tempdir()
    g.tempfile = fio.pathjoin(g.tempdir, 'main.lua')

    local default_flags = {'O_CREAT', 'O_WRONLY', 'O_TRUNC'}
    local default_mode = tonumber('644', 8)

    g.tempfile_fh = fio.open(g.tempfile, default_flags, default_mode)
end)

g.after_each(function()
    fio.rmdir(g.tempdir)
end)

g.before_test('test_stdout_stderr_output', function()
    g.tempfile_fh:write([[
        local log = require('log')

        print('hello stdout!')
        log.info('hello stderr!')
    ]])
end)

g.test_stdout_stderr_output = function()
    t.skip_if(not utils.version_current_ge_than(2, 4, 1),
              "popen module is available since Tarantool 2.4.1.")
    local res = justrun.tarantool(g.tempdir, {}, {g.tempfile}, {nojson = true, stderr = true})

    t.assert_equals(res.exit_code, 0)
    t.assert_str_contains(res.stdout, 'hello stdout!')
    t.assert_str_contains(res.stderr, 'hello stderr!')
end

g.before_test('test_decode_stdout_as_json', function()
    g.tempfile_fh:write([[
        print('{"a": 1, "b": 2}')
    ]])
end)

g.test_decode_stdout_as_json = function()
    t.skip_if(not utils.version_current_ge_than(2, 4, 1),
              "popen module is available since Tarantool 2.4.1.")
    local res = justrun.tarantool(g.tempdir, {}, {g.tempfile}, {nojson = false, stdout = true})

    t.assert_equals(res.exit_code, 0)
    t.assert_equals(res.stdout, {{ a = 1, b = 2}})
end

g.before_test('test_bad_exit_code', function()
    g.tempfile_fh:write([[
        local magic = require('magic_lib')
    ]])
end)

g.test_bad_exit_code = function()
    t.skip_if(not utils.version_current_ge_than(2, 4, 1),
              "popen module is available since Tarantool 2.4.1.")
    local res = justrun.tarantool(g.tempdir, {}, {g.tempfile}, {nojson = true, stderr = true})

    t.assert_equals(res.exit_code, 1)

    t.assert_str_contains(res.stderr, "module 'magic_lib' not found")
    t.assert_equals(res.stdout, nil)
end

g.test_error_when_popen_is_not_available = function()
    -- Substitute `require` function to test the behavior of `justrun.tarantool`
    -- if the `popen` module is not available (on versions below 2.4.1).

    -- luacheck: push ignore 121
    local old = require
    require = function(name) -- ignore:
        if name == 'popen' then
            return error("module " .. name .. " not found:")
        else
            return old(name)
        end
    end

    local _, err = pcall(justrun.tarantool, g.tempdir, {}, {g.tempfile}, {nojson = true})

    t.assert_str_contains(err, 'module popen not found:')

    require = old
    -- luacheck: pop
end
