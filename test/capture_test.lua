local fio = require('fio')
local t = require('luatest')
local g = t.group()

local Capture = require('luatest.capture')
local capture = Capture:new()

g.setup = function() capture:enable() end
g.teardown = function()
    capture:flush()
    capture:disable()
end

g.before_all(function()
    local err
    g.fd, err = fio.open('/dev/null')
    assert(err == nil, tostring(err))

    -- It is not really needed
    g.fd:close()
end)

-- Hack until https://github.com/tarantool/tarantool/issues/1338
-- is not implemented.
local function stdout_write(s)
    g.fd.fh = 1
    local res, err = g.fd:write(s)
    g.fd.fh = -1
    return res, err
end

local function stderr_write(s)
    g.fd.fh = 2
    local res, err = g.fd:write(s)
    g.fd.fh = -1
    return res, err
end

g.test_flush = function()
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
    io.stdout:write('test-out')
    io.stderr:write('test-err')
    t.assert_equals(capture:flush(), {stdout = 'test-out', stderr = 'test-err'})
    t.assert_equals(capture:flush(), {stdout = '', stderr = ''})
end

g.test_flush_large_strings = function()
    local buffer_size = 65536
    local out = ('out'):rep(buffer_size / 3)
    local err = ('error'):rep(buffer_size / 5 + 1)
    stdout_write(out)
    stderr_write(err)
    -- manually compare strings to avoid large diffs
    local captured = capture:flush()
    t.assert_equals(#captured.stdout, #out)
    t.assert(captured.stdout == out, 'invalid captured stdout')
    t.assert_equals(#captured.stderr, #err)
    t.assert(captured.stderr == err, 'invalid captured stdout')
    capture:disable()
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
        error('custom_error')
        return 'result'
    end) end)
    t.assert_equals(ok, false)
    assert(not test_capture.enabled)
    t.assert_str_contains(err.original, 'custom_error')
    t.assert_str_contains(err.traceback, 'custom_error')
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
        error('custom_error')
        return 'result'
    end) end)
    t.assert_equals(ok, false)
    assert(not test_capture.enabled)
    t.assert_str_contains(err.original, 'custom_error')
    t.assert_str_contains(err.traceback, 'custom_error')
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

g.test_re_enable_disable = function()
    capture:enable()
    t.assert_error_msg_contains('Already capturing', function() capture:enable(true) end)
    capture:disable()
    capture:disable()
    t.assert_error_msg_contains('Not capturing', function() capture:disable(true) end)
end
