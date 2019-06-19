-- Module to capture output. It works by replacing stdout and stderr file
-- descriptors with pipes inputs.

local ffi = require('ffi')
local yaml = require('yaml')

local utils = require('luatest.utils')

ffi.cdef([[
    int pipe(int fildes[2]);

    int dup(int oldfd);
    int dup2(int oldfd, int newfd);

    int fileno(struct FILE *stream);

    ssize_t read(int fd, void *buf, size_t count);
    ssize_t write(int fildes, const void *buf, size_t nbyte);
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

local READ_BUFFER_SIZE = 65536

local function read_fd(fd)
    local buffer = ffi.new('char[?]', READ_BUFFER_SIZE)
    local count = ffi.C.read(fd, buffer, READ_BUFFER_SIZE)
    if count < 0 then
        error('read pipe failed')
    end
    return ffi.string(buffer, count)
end

-- It's not possible to implement platform-independent select/poll using ffi
-- because of macros and constant usage. To avoid blocking read call we put
-- character to pipe and remove it from result.
local function read_pipe(pipe)
    if ffi.C.write(pipe[1], ' ', 1) ~= 1 then
        error('write to pipe failed')
    end
    local result = read_fd(pipe[0])
    if result:len() < READ_BUFFER_SIZE then
        return result:sub(1, -2)
    end
    local suffix = read_pipe(pipe)
    if suffix:len() > 0 then
        return result .. suffix
    else
        return result:sub(1, -2)
    end
end

local Capture = {}

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
    io.flush()
    return {
        stdout = read_pipe(self.pipes.stdout),
        stderr = read_pipe(self.pipes.stderr),
    }
end

-- Run function with enabled/disabled capture and restore previous state.
-- In the case of error it prints error to original stdout.
function Capture:wrap(enabled, fn)
    local old = self.enabled
    local result = {xpcall(function()
        self:set_enabled(enabled)
        local result = fn()
        return result
    end, function(err)
        local captured = self:flush()
        self:disable()
        if type(err) ~= 'string' then
            err = yaml.encode(err)
        else
            err = err .. '\n'
        end
        io.stderr:write(err)
        io.stderr:write(tostring(debug.traceback()) .. '\n')
        utils.print_captured('stdout', captured.stdout, io.stderr)
        utils.print_captured('stderr', captured.stderr, io.stderr)
    end)}
    self:set_enabled(old)
    return unpack(result)
end

return Capture
