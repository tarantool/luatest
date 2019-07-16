local t = require('luatest')
local g = t.group('capturing')

local helper = require('test.helper')
local Capture = require('luatest.capture')
local capture = Capture:new()

g.setup = function() capture:enable() end
g.teardown = function()
    capture:flush()
    capture:disable()
end

local function assert_capture_restored()
    io.stdout:write('capture-restored')
    t.assert_equals(capture:flush(), {stdout = 'capture-restored', stderr = ''})
end

local function assert_captured(fn)
    helper.run_suite(fn)
    local captured = capture:flush()
    t.assert_not_str_contains(captured.stdout, '-test-')
    t.assert_not_str_contains(captured.stderr, '-test-')
    assert_capture_restored()
end

local function assert_shown(fn)
    helper.run_suite(fn)
    local captured = capture:flush()
    t.assert_str_contains(captured.stdout, 'Captured stdout:\ntest-out')
    t.assert_str_contains(captured.stdout, 'Captured stderr:\ntest-err')
    t.assert_equals(captured.stderr, '')
    assert_capture_restored()
end

local function assert_error(fn)
    t.assert_equals(helper.run_suite(fn), 1)
    local captured = capture:flush()
    t.assert_str_contains(captured.stderr, 'custom-error')
    t.assert_str_contains(captured.stderr, 'Captured stdout:\ntest-out')
    t.assert_str_contains(captured.stderr, 'Captured stderr:\ntest-err')
    assert_capture_restored()
end

g.test_example = function()
    assert_captured(function(lu2)
        lu2.group('test').test = function()
            io.stdout:write('-test-')
            io.stderr:write('-test-')
        end
    end)
end

g.test_example_failed = function()
    assert_shown(function(lu2)
        lu2.group('test').test = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('test')
        end
    end)
end

g.test_example_hook = function()
    assert_captured(function(lu2)
        local group = lu2.group('test')
        group.setup = function()
            io.stdout:write('-test-')
            io.stderr:write('-test-')
        end
        group.teardown = group.setup
        group.test = function() end
    end)
end

g.test_example_hook_failed = function()
    assert_shown(function(lu2)
        local group = lu2.group('test')
        group.setup = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('test')
        end
        group.test = function() end
    end)

    assert_shown(function(lu2)
        local group = lu2.group('test')
        group.teardown = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('test')
        end
        group.test = function() end
    end)

    assert_shown(function(lu2)
        local group = lu2.group('test')
        group.setup = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
        end
        group.test = function() error('test') end
    end)
end

g.test_load_tests = function()
    assert_captured(function()
        io.stdout:write('-test-')
        io.stderr:write('-test-')
    end)
end

g.test_load_tests_failed = function()
    assert_error(function()
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        error('custom-error')
    end)
end

g.test_class_hook = function()
    assert_captured(function(lu2)
        local group = lu2.group('test')
        group.before_all = function()
            io.stdout:write('-test-')
            io.stderr:write('-test-')
        end
        group.after_all = group.before_all
        group.test = function() end

        local group2 = lu2.group('test2')
        group2.before_all = function()
            io.stdout:write('-test-')
            io.stderr:write('-test-')
        end
        group2.after_all = group2.before_all
        group2.test = function() end
    end)
end

g.test_class_hook_failed = function()
    assert_error(function(lu2)
        local group = lu2.group('test')
        group.before_all = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('custom-error')
        end
        group.test = function() end
    end)

    assert_error(function(lu2)
        local group = lu2.group('test')
        group.after_all = function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('custom-error')
        end
        group.test = function() end
    end)
end

g.test_suite_hook = function()
    assert_captured(function(lu2)
        local group = lu2.group('test')
        local hook = function()
            io.stdout:write('-test-')
            io.stderr:write('-test-')
        end
        lu2.before_suite(hook)
        lu2.after_all(hook)
        group.test = function() end
    end)
end

g.test_suite_hook_failed = function()
    assert_error(function(lu2)
        lu2.group('test').test = function() end
        lu2.before_suite(function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('custom-error')
        end)
    end)

    assert_error(function(lu2)
        lu2.group('test').test = function() end
        lu2.after_suite(function()
            io.stdout:write('test-out')
            io.stderr:write('test-err')
            error('custom-error')
        end)
    end)
end
