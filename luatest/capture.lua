-- Module to capture output. It works by replacing stdout and stderr file
-- descriptors with pipes inputs.

local ffi = require('ffi')
local fio = require('fio')

local utils = require('luatest.utils')

ffi.cdef([[
    int pipe(int fildes[2]);

    int dup(int oldfd);
    int dup2(int oldfd, int newfd);

    int fileno(struct FILE *stream);

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
local fio_file_mt

-- The simplest way of non-blocking read is `fio.file:read()`.
-- However we have only file descriptor number and there is no way to create
-- fio file from it, so we need to fetch metatable and then create object manually.
local function fd_to_fio(fd)
    if not fio_file_mt then
        local dev_null, err = fio.open('/dev/null')
        assert(dev_null, tostring(err))
        fio_file_mt = getmetatable(dev_null)
        dev_null:close()
    end
    return setmetatable({fh = fd}, fio_file_mt)
end

local function read_fd(fd)
    if ffi.C.coio_wait(fd, COIO_READ, 0) == 0 then
        return ''
    else
        return fd_to_fio(fd):read()
    end
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
