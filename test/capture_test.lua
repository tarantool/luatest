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
    t.assert_equals(result, {'result'})
    assert(not test_capture.enabled)
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_disabled = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(false, function()
        assert(not test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        return 'result'
    end)}
    t.assert_equals(result, {'result'})
    assert(not test_capture.enabled)
    t.assert_equals(capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    t.assert_equals(test_capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_with_error = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local ok, err = pcall(function() test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        invalid() -- luacheck: ignore
        return 'result'
    end) end)
    t.assert_equals(ok, false)
    assert(not test_capture.enabled)
    t.assert_str_contains(err.original, "attempt to call global 'invalid'")
    t.assert_str_contains(err.traceback, "attempt to call global 'invalid'")
    t.assert_str_contains(err.traceback, 'stack traceback:')
    t.assert_equals(err.captured.stdout, 'test-out')
    t.assert_equals(err.captured.stderr, 'test-err')
    t.assert_equals(test_capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_wrap_disabled_with_error = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local ok, err = pcall(function() test_capture:wrap(false, function()
        assert(not test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        invalid() -- luacheck: ignore
        return 'result'
    end) end)
    t.assert_equals(ok, false)
    assert(not test_capture.enabled)
    t.assert_str_contains(err.original, "attempt to call global 'invalid'")
    t.assert_str_contains(err.traceback, "attempt to call global 'invalid'")
    t.assert_str_contains(err.traceback, 'stack traceback:')
    t.assert_equals(err.captured.stdout, '')
    t.assert_equals(err.captured.stderr, '')
    t.assert_equals(test_capture:flush(), {stdout = '', stderr = ''})
    t.assert_equals(capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
end

g.test_wrap_with_error_table = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local err_table = {type = 'err-class', message = 'hey'}
    local ok, err = pcall(function() test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        error(err_table)
        return 'result'
    end) end)
    t.assert_equals(ok, false)
    assert(not test_capture.enabled)
    t.assert_equals(err.original, err_table)
    t.assert_str_contains(err.traceback, "type: err-class\nmessage: hey")
    t.assert_str_contains(err.traceback, 'stack traceback:')
    t.assert_equals(err.captured.stdout, 'test-out')
    t.assert_equals(err.captured.stderr, 'test-err')
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
