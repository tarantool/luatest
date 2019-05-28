local lt = require('luatest')
local t = lt.group('capture')

local Capture = require('luatest.capture')
local capture = Capture:new()

t.setup = function() capture:enable() end
t.teardown = function()
    capture:flush()
    capture:disable()
end

t.test_flush = function()
    lt.assertEquals(capture:flush(), {stdout = '', stderr = ''})
    io.stdout:write('test-out')
    io.stderr:write('test-err')
    lt.assertEquals(capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    lt.assertEquals(capture:flush(), {stdout = '', stderr = ''})
end

t.test_flush_large_strings = function()
    lt.skip('no support for large strings yet')
    local buffer_size = 65536
    local out = ('a'):rep(buffer_size)
    local err = ('a'):rep(buffer_size + 1)
    io.stdout:write(out)
    io.stderr:write(err)
    lt.assertEquals(capture:flush(), {stdout = out, stderr = err})
end

t.test_wrap = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        return 'result'
    end)}
    lt.assertEquals(result, {true, 'result'})
    assert(not test_capture.enabled)
    lt.assertEquals(capture:flush(), {stdout = '', stderr = ''})
    lt.assertEquals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    lt.assertEquals(capture:flush(), {stdout = '', stderr = ''})
end

t.test_wrap_with_error = function()
    local test_capture = Capture:new()
    assert(not test_capture.enabled)
    local result = {test_capture:wrap(true, function()
        assert(test_capture.enabled)
        io.stdout:write('test-out')
        io.stderr:write('test-err')
        invalid() -- luacheck: ignore
        return 'result'
    end)}
    lt.assertEquals(result, {false})
    assert(not test_capture.enabled)
    local captured = capture:flush()
    lt.assertEquals(captured.stdout, '')
    lt.assertNotStrContains(captured.stderr, 'test-err')
    lt.assertStrContains(captured.stderr, "attempt to call global 'invalid'")
    lt.assertStrContains(captured.stderr, 'stack traceback:')
    lt.assertEquals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    lt.assertEquals(capture:flush(), {stdout = '', stderr = ''})
end

t.test_wrap_nested = function()
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
    lt.assertEquals(capture:flush(), {stdout = 'test-out-2', stderr = 'test-err-2'})
    lt.assertEquals(test_capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
end
