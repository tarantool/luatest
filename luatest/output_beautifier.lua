local checks = require('checks')
local fiber = require('fiber')
local fun = require('fun')

local Class = require('luatest.class')
local ffi_io = require('luatest.ffi_io')
local Monitor = require('luatest.monitor')
local Process -- later require to avoid circular dependency

local OutputBeautifier = Class.new({
    monitor = Monitor:new(),
    PID_TRACKER_INTERVAL = 0.2,

    RESET_TERM = '\x1B[0m',
    COLORS = {
        {'magenta', '\x1B[35m'},
        {'blue', '\x1B[34m'},
        {'cyan', '\x1B[36m'},
        {'green', '\x1B[32m'},
        {'bright_magenta', '\x1B[95m'},
        {'bright_cyan', '\x1B[96m'},
        {'bright_blue', '\x1B[94m'},
        {'bright_green', '\x1B[92m'},
    },
    ERROR_COLOR_CODE = '\x1B[31m', -- red
    WARN_COLOR_CODE = '\x1B[33m', -- yellow

    ERROR_LOG_LINE_PATTERN = ' (%u)> ',
})

OutputBeautifier.COLOR_BY_NAME = fun.iter(OutputBeautifier.COLORS):
    map(function(x) return unpack(x) end):
    tomap()

-- Map of `log_level_letter => color_code`.
OutputBeautifier.COLOR_CODE_BY_LOG_LEVEL = fun.iter({
    S_FATAL = 'ERROR_COLOR_CODE',
    S_SYSERROR = 'ERROR_COLOR_CODE',
    S_ERROR = 'ERROR_COLOR_CODE',
    S_CRIT = 'ERROR_COLOR_CODE',
    S_WARN = 'WARN_COLOR_CODE',
    S_INFO = 'RESET_TERM',
    S_VERBOSE = 'RESET_TERM',
    S_DEBUG = 'RESET_TERM',
}):map(function(k, v) return k:sub(3, 3), OutputBeautifier[v] end):tomap()

-- Generates color code from the list of `self.COLORS`.
function OutputBeautifier:next_color_code()
    self._NEXT_COLOR = (self._NEXT_COLOR and self._NEXT_COLOR + 1 or 0) % #self.COLORS
    return self.COLORS[self._NEXT_COLOR + 1][2]
end

function OutputBeautifier:synchronize(...)
    return self.monitor:synchronize(...)
end

--- Build OutputBeautifier object.
-- @param object
-- @string object.prefix String to prefix each output line with.
-- @string[opt] object.color Color name for prefix.
-- @string[opt] object.color_code Color code for prefix.
-- @return input object.
function OutputBeautifier:new(object)
    checks('table', {prefix = 'string', color = '?string', color_code = '?string'})
    return self:from(object)
end

function OutputBeautifier.mt:initialize()
    self.color_code = self.color_code or
        self.class.COLOR_BY_NAME[self.color] or
        OutputBeautifier:next_color_code()
    self.pipes = {stdout = ffi_io.create_pipe(), stderr = ffi_io.create_pipe()}
end

-- Replace standard output descriptors with pipes.
function OutputBeautifier.mt:hijack_output()
    ffi_io.dup2_io(self.pipes.stdout[1], io.stdout)
    ffi_io.dup2_io(self.pipes.stderr[1], io.stderr)
end

-- Start fibers that reads from pipes and prints formatted output.
-- Pass `track_pid` option to automatically stop forwarder once process is finished.
function OutputBeautifier.mt:enable(options)
    if self.fibers then
        return
    end
    self.fibers = {}
    for i, pipe in pairs(self.pipes) do
        self.fibers[i] = fiber.new(self.run, self, pipe[0])
    end
    self.fibers.pid_tracker = options and options.track_pid and fiber.new(function()
        Process = Process or require('luatest.process')
        while fiber.testcancel() or true do
            if not Process.is_pid_alive(options.track_pid) then
                fiber.sleep(self.class.PID_TRACKER_INTERVAL)
                return self:disable()
            end
            fiber.sleep(self.class.PID_TRACKER_INTERVAL)
        end
    end)
end

-- Stop fibers.
function OutputBeautifier.mt:disable()
    if self.fibers then
        for _, item in pairs(self.fibers) do
            if item:status() ~= 'dead' then
                item:cancel()
            end
        end
    end
    self.fibers = nil
end

-- Process all available data from fd using synchronization with monitor.
-- It prevents intensive output from breaking into chunks, interfering
-- with other output or getting out of active capture.
-- First it tries to read from fd with yielding call. If any data is available
-- the it enters critical section and
function OutputBeautifier.mt:process_fd_output(fd, fn)
    local chunks = ffi_io.read_fd(fd)
    if #chunks == 0 then
        return
    end
    self.class:synchronize(function()
        while true do
            fn(chunks)
            chunks = ffi_io.read_fd(fd, nil, {timeout = 0})
            if #chunks == 0 then
                return
            end
        end
    end)
end

-- Reads from file desccriptor and prints colored and prefixed lines.
-- Prefix is colored with `self.color_code` and error lines are printed in red.
--
-- Every line with log level mark (` X> `) changes the color for all the following
-- lines until the next one with the mark.
function OutputBeautifier.mt:run(fd)
    local prefix = self.color_code .. self.prefix .. ' | '
    local line_color_code = self.class.RESET_TERM
    while fiber.testcancel() or true do
        self:process_fd_output(fd, function(chunks)
            local lines = table.concat(chunks):split('\n')
            if lines[#lines] == '' then
                table.remove(lines)
            end
            for _, line in pairs(lines) do
                line_color_code = self:color_for_line(line) or line_color_code
                io.stdout:write(table.concat({prefix, line_color_code, line, self.class.RESET_TERM, '\n'}))
                fiber.yield()
            end
        end)
    end
end

-- Returns new color code for line or nil if it should not be changed.
function OutputBeautifier.mt:color_for_line(line)
    local mark = line:match(self.class.ERROR_LOG_LINE_PATTERN)
    return mark and self.class.COLOR_CODE_BY_LOG_LEVEL[mark]
end

return OutputBeautifier
