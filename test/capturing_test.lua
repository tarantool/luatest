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

local function assert_captured(fn)
    helper.run_suite(fn)
    local captured = capture:flush()
    t.assertNotStrContains(captured.stdout, '-test-')
    t.assertNotStrContains(captured.stderr, '-test-')
end

local function assert_shown(fn)
    helper.run_suite(fn)
    local captured = capture:flush()
    t.assertStrContains(captured.stdout, 'Captured stdout:\ntest-out')
    t.assertStrContains(captured.stdout, 'Captured stderr:\ntest-err')
    t.assertEquals(captured.stderr, '')
end

local function assert_error(fn)
    t.assertEquals(helper.run_suite(fn), 1)
    local captured = capture:flush()
    t.assertStrContains(captured.stderr, 'custom-error')
    t.assertStrContains(captured.stderr, 'Captured stdout:\ntest-out')
    t.assertStrContains(captured.stderr, 'Captured stderr:\ntest-err')
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
