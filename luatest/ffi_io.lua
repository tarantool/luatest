local errno = require('errno')
local ffi = require('ffi')
local socket = require('socket')

ffi.cdef([[
    int close(int fildes);
    int dup2(int oldfd, int newfd);
    int fileno(struct FILE *stream);
    int pipe(int fildes[2]);

    ssize_t read(int fd, void *buf, size_t count);
]])

local export = {}

function export.create_pipe()
    local fildes = ffi.new('int[?]', 2)
    if ffi.C.pipe(fildes) ~= 0 then
        error('pipe call failed: ' .. errno.strerror())
    end
    ffi.gc(fildes, function(x)
        ffi.C.close(x[0])
        ffi.C.close(x[1])
    end)
    return fildes
end

export.READ_BUFFER_SIZE = 4096
export.READ_PIPE_TIMEOUT = 1

-- Read fd into chunks array while it's readable.
function export.read_fd(fd, chunks, options)
    local buffer_size = options and options.buffer_size or export.READ_BUFFER_SIZE
    local timeout = options and options.timeout or export.READ_TIMEOUT
    chunks = chunks or {}
    local buffer
    while socket.iowait(fd, 'R', timeout) ~= '' do
        timeout = 0 -- next iowait must return immediately
        buffer = buffer or ffi.new('char[?]', buffer_size)
        local count = ffi.C.read(fd, buffer, buffer_size)
        if count < 0 then
            error('read pipe failed: ' .. errno.strerror())
        end
        table.insert(chunks, ffi.string(buffer, count))
    end
    return chunks
end

-- Call `dup2` for io object to change it's descriptor.
function export.dup2_io(oldfd, newio)
    ffi.C.dup2(oldfd, ffi.C.fileno(newio))
end

return export
