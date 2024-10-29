local checks = require('checks')
local errno = require('errno')
local fun = require('fun')
local ffi = require('ffi')
local fio = require('fio')

local log = require('luatest.log')
local Class = require('luatest.class')
local OutputBeautifier = require('luatest.output_beautifier')

ffi.cdef([[
    pid_t fork(void);
    int execve(const char *pathname, char *const argv[], char *const envp[]);
    int kill(pid_t pid, int sig);
]])

local Process = Class.new()

-- luacov: disable
local function to_const_char(input)
    local result = ffi.new('char const*[?]', #input + 1, input)
    result[#input] = nil
    return ffi.cast('char *const*', result)
end
-- luacov: enable

--- Starts process and returns immediately, not waiting until process is finished.
-- @param path Executable path.
-- @param[opt] args
-- @param[opt] env
-- @param[opt] options
-- @param[opt] options.chdir Directory to chdir into before starting process.
-- @param[opt] options.ignore_gc Don't install handler which kills GC'ed processes.
function Process:start(path, args, env, options)
    checks('table', 'string', '?table', '?table', {
        chdir = '?string',
        ignore_gc = '?boolean',
        output_prefix = '?string',
    })
    args = args and table.copy(args) or {}
    env = env or {}
    options = options or {}

    table.insert(args, 1, path)

    local output_beautifier = options.output_prefix and OutputBeautifier:new({
        prefix = options.output_prefix,
    })

    local env_list = fun.iter(env):map(function(k, v) return k .. '=' .. v end):totable()
    local pid = ffi.C.fork()
    if pid == -1 then
        error('fork failed: ' .. pid)
    elseif pid > 0 then
        if output_beautifier then
            output_beautifier:enable({track_pid = pid})
        end
        return self:from({pid = pid, ignore_gc = options.ignore_gc, output_beautifier = output_beautifier})
    end
    -- luacov: disable
    if options.chdir then
        fio.chdir(options.chdir)
    end
    if output_beautifier then
        output_beautifier:hijack_output()
    end
    local argv = to_const_char(args)
    local envp = to_const_char(env_list)
    ffi.C.execve(path, argv, envp)
    io.stderr:write('execve failed (' .. path ..  '): ' .. errno.strerror() .. '\n')
    os.exit(1)
    -- luacov: enable
end

function Process.mt:initialize()
    if not self.ignore_gc then
        self._pid_ull = ffi.cast('void*', 0ULL + self.pid)
        ffi.gc(self._pid_ull, function(x)
            local pid = tonumber(ffi.cast(ffi.typeof(0ULL), x))
            log.info("Killing GC'ed process %d", pid)
            Process.kill_pid(pid, nil, {quiet = true})
        end)
    end
end

function Process.mt:kill(signal, options)
    self.class.kill_pid(self.pid, signal, options)
end

function Process.mt:is_alive()
    return self.pid ~= nil and self.class.is_pid_alive(self.pid)
end

function Process.kill_pid(pid, signal, options)
    checks('number|string', '?number|string', {quiet = '?boolean'})
    -- Signal values are platform-dependent so we can not use ffi here
    signal = signal or 15
    local exit_code = os.execute('kill -' .. signal .. ' ' .. pid .. ' 2> /dev/null')
    if exit_code ~= 0 and not (options and options.quiet) then
        error('kill failed: ' .. exit_code)
    end
end

function Process.is_pid_alive(pid)
    return ffi.C.kill(tonumber(pid), 0) == 0
end

return Process
