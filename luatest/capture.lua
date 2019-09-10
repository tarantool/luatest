-- Module to capture output. It works by replacing stdout and stderr file
-- descriptors with pipes inputs.

local ffi = require('ffi')

local utils = require('luatest.utils')

ffi.cdef([[
    int pipe(int fildes[2]);

    int dup(int oldfd);
    int dup2(int oldfd, int newfd);

    int fileno(struct FILE *stream);

    ssize_t read(int fd, void *buf, size_t count);

    int coio_wait(int fd, int event, double timeout);
]])

local function create_pipe()
    local fildes = ffi.new('int[?]', 2)
    if ffi.C.pipe(fildes) ~= 0 then
        error('pipe call failed')
    end
    return fildes
end

-- Duplicate lua's io object to new fd.
local function dup_io(file)
    local newfd = ffi.C.dup(ffi.C.fileno(file))
    if newfd < 0 then
        error('dup call failed')
    end
    return newfd
end

local COIO_READ = 0x1
local READ_BUFFER_SIZE = 4096

local function read_fd(fd)
    local chunks = {}
    local buffer = nil
    while ffi.C.coio_wait(fd, COIO_READ, 0) ~= 0 do
        buffer = buffer or ffi.new('char[?]', READ_BUFFER_SIZE)
        local count = ffi.C.read(fd, buffer, READ_BUFFER_SIZE)
        if count < 0 then
            error('read pipe failed')
        end
        table.insert(chunks, ffi.string(buffer, count))
    end
    return table.concat(chunks)
end

local Capture = {
    CAPTURED_ERROR_TYPE = 'ERROR_WITH_CAPTURE',
}

function Capture:new()
    local object = {}
    setmetatable(object, self)
    self.__index = self
    object.enabled = false
    return object
end

-- Overwrite stdout and stderr fds with pipe inputs.
-- Original fds are copied into original_fds, to be able to restore them later.
function Capture:enable(raise)
    if self.enabled then
        if raise then
            error('Already capturing')
        end
        return
    end
    if not self.pipes then
        self.pipes = {stdout = create_pipe(), stderr = create_pipe()}
        self.original_fds = {stdout = dup_io(io.stdout), stderr = dup_io(io.stderr)}
    end
    io.flush()
    ffi.C.dup2(self.pipes.stdout[1], ffi.C.fileno(io.stdout))
    ffi.C.dup2(self.pipes.stderr[1], ffi.C.fileno(io.stderr))
    self.enabled = true
end

-- Restore original fds for stdout and stderr.
function Capture:disable(raise)
    if not self.enabled then
        if raise then
            error('Not capturing')
        end
        return
    end
    io.flush()
    ffi.C.dup2(self.original_fds.stdout, ffi.C.fileno(io.stdout))
    ffi.C.dup2(self.original_fds.stderr, ffi.C.fileno(io.stderr))
    self.enabled = false
end

-- Enable/disable depending on passed value.
function Capture:set_enabled(value)
    if value then
        self:enable()
    else
        self:disable()
    end
end

-- Read from capture pipes and return results.
function Capture:flush()
    if not self.pipes then
        return {stdout = '', stderr = ''}
    end
    io.flush()
    return {
        stdout = read_fd(self.pipes.stdout[0]),
        stderr = read_fd(self.pipes.stderr[0]),
    }
end

-- Run function with enabled/disabled capture and restore previous state.
-- In the case of failure it wraps error into map-table with captured output added.
function Capture:wrap(enabled, fn)
    local old = self.enabled
    return utils.reraise_and_ensure(function()
        self:set_enabled(enabled)
        return fn()
    end, function(err)
        -- Don't re-wrap error.
        if err.type ~= self.CAPTURED_ERROR_TYPE then
            err = {
                type = self.CAPTURED_ERROR_TYPE,
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
