local t = require('luatest')
local g = t.group('capture')

local Capture = require('luatest.capture')
local capture = Capture:new()

g.setup = function() capture:enable() end
g.teardown = function()
    capture:flush()
    capture:disable()
end

g.test_flush = function()
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
    io.stdout:write('test-out')
    io.stderr:write('test-err')
    t.assert_equals(capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_flush_large_strings = function()
    t.skip('no support for large strings yet')
    local buffer_size = 65536
    local out = ('a'):rep(buffer_size)
    local err = ('a'):rep(buffer_size + 1)
    io.stdout:write(out)
    io.stderr:write(err)
    t.assert_equals(capture:flush(), {stdout = out, stderr = err})
end

g.test_wrap = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        return 'result'
    end)}
    t.assert_equals(result, {true, 'result'})
    assert(not test_capture.enabled)
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_with_error = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        invalid() -- luacheck: ignore
        return 'result'
    end)}
    t.assert_equals(result, {false})
    assert(not test_capture.enabled)
    local captured = capture:flush()
    t.assert_equals(captured.stdout, '')
    t.assert_str_contains(captured.stderr, "attempt to call global 'invalid'")
    t.assert_str_contains(captured.stderr, 'stack traceback:')
    t.assert_str_contains(captured.stderr, 'Captured stdout:\ntest-out')
    t.assert_str_contains(captured.stderr, 'Captured stderr:\ntest-err')
    t.assert_equals(test_capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_with_error_table = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        error({type = 'err-class', message = 'hey'})
        return 'result'
    end)}
    t.assert_equals(result, {false})
    assert(not test_capture.enabled)
    local captured = capture:flush()
    t.assert_equals(captured.stdout, '')
    t.assert_str_contains(captured.stderr, "type: err-class\nmessage: hey")
    t.assert_str_contains(captured.stderr, 'stack traceback:')
    t.assert_str_contains(captured.stderr, 'Captured stdout:\ntest-out')
    t.assert_str_contains(captured.stderr, 'Captured stderr:\ntest-err')
    t.assert_equals(test_capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_nested = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        test_capture:wrap(false, function()
            assert(not test_capture.enabled)
            io.stdout:write('test-out-2')
            io.stderr:write('test-err-2')
        end)
        assert(test_capture.enabled)
    end)
    assert(not test_capture.enabled)
    t.assert_equals(capture:flush(), {stdout = 'test-out-2', stderr = 'test-err-2'})
    t.assert_equals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
end
