-- Module to capture output. It works by replacing stdout and stderr file
-- descriptors with pipes inputs.

local ffi = require('ffi')
local fiber = require('fiber')

local Class = require('luatest.class')
local ffi_io = require('luatest.ffi_io')
local utils = require('luatest.utils')

ffi.cdef([[
    int dup(int oldfd);
    int fileno(struct FILE *stream);
]])

-- Duplicate lua's io object to new fd.
local function dup_io(file)
    local newfd = ffi.C.dup(ffi.C.fileno(file))
    if newfd < 0 then
        error('dup call failed')
    end
    return newfd
end

local Capture = Class.new({
    CAPTURED_ERROR_TYPE = 'ERROR_WITH_CAPTURE',
})

Capture.Stub = Capture:new_class()
Capture.Stub.mt.enable = function() end
Capture.Stub.mt.disable = function() end

function Capture:stub()
    return self.Stub:new()
end

function Capture.mt:initialize()
    self.enabled = false
    self.buffer = {stdout = {}, stderr = {}}
end

-- Overwrite stdout and stderr fds with pipe inputs.
-- Original fds are copied into original_fds, to be able to restore them later.
function Capture.mt:enable(raise)
    if self.enabled then
        if raise then
            error('Already capturing')
        end
        return
    end
    if not self.pipes then
        self.pipes = {stdout = ffi_io.create_pipe(), stderr = ffi_io.create_pipe()}
        self.original_fds = {stdout = dup_io(io.stdout), stderr = dup_io(io.stderr)}
    end
    io.flush()
    ffi_io.dup2_io(self.pipes.stdout[1], io.stdout)
    ffi_io.dup2_io(self.pipes.stderr[1], io.stderr)
    self:start_reader_fibers()
    self.enabled = true
end

-- Start the fiber that reads from pipes to the buffer.
function Capture.mt:start_reader_fibers()
    assert(not self.reader_fibers, 'reader_fibers are already running')
    self.reader_fibers = {}
    for name, pipe in pairs(self.pipes) do
        self.reader_fibers[name] = fiber.new(function()
            while fiber.testcancel() or true do
                ffi_io.read_fd(pipe[0], self.buffer[name])
            end
        end)
        self.reader_fibers[name]:set_joinable(true)
    end
end

-- Stop reader fiber and read available data from pipe after fiber was stopped.
function Capture.mt:stop_reader_fibers()
    io.flush()
    if not self.reader_fibers then
        return false
    end
    for name, item in pairs(self.reader_fibers) do
        item:cancel()
        item:join()
        ffi_io.read_fd(self.pipes[name][0], self.buffer[name], {timeout = 0})
    end
    self.reader_fibers = nil
    return true
end

-- Restore original fds for stdout and stderr.
function Capture.mt:disable(raise)
    if not self.enabled then
        if raise then
            error('Not capturing')
        end
        return
    end
    self:stop_reader_fibers()
    ffi_io.dup2_io(self.original_fds.stdout, io.stdout)
    ffi_io.dup2_io(self.original_fds.stderr, io.stderr)
    self.enabled = false
end

-- Enable/disable depending on passed value.
function Capture.mt:set_enabled(value)
    if value then
        self:enable()
    else
        self:disable()
    end
end

-- Read from capture pipes and return results.
function Capture.mt:flush()
    if not self.pipes then
        return {stdout = '', stderr = ''}
    end
    local restart_reader_fibers = self:stop_reader_fibers()
    local result = {
        stdout = table.concat(self.buffer.stdout),
        stderr = table.concat(self.buffer.stderr),
    }
    self.buffer = {stdout = {}, stderr = {}}
    if restart_reader_fibers then
        self:start_reader_fibers()
    end
    return result
end

-- Run function with enabled/disabled capture and restore previous state.
-- In the case of failure it wraps error into map-table with captured output added.
function Capture.mt:wrap(enabled, fn)
    local old = self.enabled
    return utils.reraise_and_ensure(function()
        self:set_enabled(enabled)
        return fn()
    end, function(err)
        -- Don't re-wrap error.
        if type(err) ~= 'table' or rawget(err, 'type') ~= self.class.CAPTURED_ERROR_TYPE then
            err = {
                type = self.class.CAPTURED_ERROR_TYPE,
                original = err,
                traceback = utils.traceback(err),
                captured = self:flush(),
            }
        end
        return err
    end, function()
        self:set_enabled(old)
    end)
end

return Capture
