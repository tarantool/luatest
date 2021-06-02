local t = require('luatest')
local g = t.group()

local Capture = require('luatest.capture')
local helper = require('test.helper')

g.test_run_pass = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assert_equals(1, 1) end
    end)

    t.assert_equals(result, 0)
end

g.test_run_fail = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assert_equals(1, 0) end
    end)

    t.assert_equals(result, 1)
end

g.test_run_error = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() error('custom_error') end
    end)

    t.assert_equals(result, 1)
end

local function run_file(file)
    return os.execute('bin/luatest test/fixtures/' .. file)
end

g.test_executable_pass = function()
    t.assert_equals(run_file('pass.lua'), 0)
end

g.test_executable_fail = function()
    t.assert_equals(run_file('fail.lua'), 256) -- luajit multiplies result by 256
end

g.test_executable_error = function()
    t.assert_equals(run_file('error.lua'), 256) -- luajit multiplies result by 256
end

g.test_run_without_capture = function()
    local result = helper.run_suite(function(lu2)
        lu2.group('test').test = function() t.assert_equals(1, 1) end
    end, {'-c'})

    t.assert_equals(result, 0)
end

local function get_run_order(options, extra_loader)
    local result = {}
    local status = helper.run_suite(function(lu2)
        for i = 1, 3 do
            local g2 = lu2.group('g' .. i)
            g2.test_a = function() table.insert(result, '' .. i .. '-a') end
            g2.test_b = function() table.insert(result, '' .. i .. '-b') end
        end
        if extra_loader then
            extra_loader(lu2)
        end
    end, options)
    return result, status
end

g.test_run_shuffle = function()
    t.assert_equals(get_run_order({'--shuffle', 'none'}), {
        '1-a',
        '1-b',
        '2-a',
        '2-b',
        '3-a',
        '3-b',
    })

    t.assert_equals(get_run_order({'--shuffle', 'group:1'}), {
        '1-b',
        '1-a',
        '2-b',
        '2-a',
        '3-a',
        '3-b',
    })
    t.assert_equals(get_run_order({'--shuffle', 'group:2'}), {
        '1-b',
        '1-a',
        '2-a',
        '2-b',
        '3-a',
        '3-b',
    })

    t.assert_equals(get_run_order({'--shuffle', 'all:1'}), {
        '3-b',
        '2-a',
        '3-a',
        '2-b',
        '1-a',
        '1-b',
    })
    t.assert_equals(get_run_order({'--shuffle', 'all', '--seed', '1'}), {
        '3-b',
        '2-a',
        '3-a',
        '2-b',
        '1-a',
        '1-b',
    })
end

g.test_pattern_and_exclude = function()
    t.assert_equals(get_run_order({'--shuffle', 'none', '-x', 'a'}), {
        '1-b',
        '2-b',
        '3-b',
    })

    t.assert_equals(get_run_order({'--shuffle', 'none', '-x', 'g'}), {})

    t.assert_equals(get_run_order({'--shuffle', 'none', '-p', 'a'}), {
        '1-a',
        '2-a',
        '3-a',
    })
end

g.test_running_selected_tests = function()
    t.assert_equals(get_run_order({'g1'}), {'1-a', '1-b'})
    t.assert_equals(get_run_order({'g2.test_b'}), {'2-b'})
    t.assert_equals(get_run_order({'g3', 'g1'}), {'3-a', '3-b', '1-a', '1-b'})
    t.assert_equals(get_run_order({'g3', 'g1.test_b'}), {'3-a', '3-b', '1-b'})
    t.assert_equals(get_run_order({'g2.test_a', 'g1.test_b'}), {'2-a', '1-b'})
end

g.test_running_invalid_selected_tests = function()
    t.assert_equals({get_run_order({'g-invalid'})}, {{}, -1})
    t.assert_equals({get_run_order({'g1.test_invlid'})}, {{}, -1})
end

g.test_running_selected_files = function()
    local run_paths = {}
    local path_args = {'a/b/c', 'd/e.lua'}
    helper.run_suite(function(_, path)
        table.insert(run_paths, path)
    end, path_args)
    t.assert_equals(run_paths, path_args)
end

g.test_fail_fast = function()
    t.assert_equals({get_run_order({'--fail-fast'})}, {{
        '1-a',
        '1-b',
        '2-a',
        '2-b',
        '3-a',
        '3-b',
    }, 0})
    t.assert_equals({get_run_order({'--fail-fast'}, function(lu2)
        lu2.groups.g2.test_b = function() error('fail') end
    end)}, {{
        '1-a',
        '1-b',
        '2-a',
    }, -2})
end

g.test_show_version = function()
    local capture = Capture:new()
    capture:wrap(true, function()
        helper.run_suite(function()
            error('must not be called')
        end, {'--version'})
    end)
    local captured = capture:flush()
    t.assert_equals(captured.stdout, 'luatest v' .. t.VERSION .. '\n')
end

g.test_show_help = function()
    local capture = Capture:new()
    capture:wrap(true, function()
        helper.run_suite(function()
            error('must not be called')
        end, {'--help'})
    end)
    local captured = capture:flush()
    t.assert_str_contains(captured.stdout, 'Usage: luatest')
end

g.test_sandbox = function()
    local status = os.execute('bin/luatest test/fixtures/mock.lua --sandbox')
    t.assert_equals(status, 0)
end
