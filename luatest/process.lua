local checks = require('checks')
local errno = require('errno')
local fun = require('fun')
local ffi = require('ffi')
local fio = require('fio')
local log = require('log')

ffi.cdef([[
    pid_t fork(void);

    int execve(const char *pathname, char *const argv[], char *const envp[]);
]])

local Process = {}

local function to_const_char(input)
    local result = ffi.new('char const*[?]', #input + 1, input)
    result[#input] = nil
    return ffi.cast('char *const*', result)
end

--- Starts process and returns immediately, not waiting until process is finished.
-- @param path Executable path.
-- @param[opt] args
-- @param[opt] env
-- @param[opt] options
-- @param[opt] options.chdir Directory to chdir into before starting process.
-- @param[opt] options.ignore_gc Don't install handler which kills GC'ed processes.
function Process:start(path, args, env, options)
    checks('table', 'string', '?table', '?table', {chdir = '?string', ignore_gc = '?boolean'})
    args = args or {}
    env = env or {}
    options = options or {}

    table.insert(args, 1, path)

    local argv = to_const_char(args)
    local env_list = fun.iter(env):map(function(k, v) return k .. '=' .. v end):totable()
    local envp = to_const_char(env_list)
    local pid = ffi.C.fork()
    if pid == -1 then
        error('fork failed: ' .. pid)
    elseif pid > 0 then
        return self:new({pid = pid, ignore_gc = options.ignore_gc})
    end
    if options.chdir then
        fio.chdir(options.chdir)
    end
    ffi.C.execve(path, argv, envp)
    io.stderr:write('execve failed (' .. path ..  '): ' .. errno.strerror() .. '\n')
    os.exit(1)
end

function Process:new(object)
    setmetatable(object, self)
    self.__index = self
    if not object.ignore_gc then
        object._pid_ull = ffi.cast('void*', 0ULL + object.pid)
        ffi.gc(object._pid_ull, function(x)
            local pid = tonumber(ffi.cast(ffi.typeof(0ULL), x))
            log.debug("Killing GC'ed process " .. pid)
            Process.kill_pid(pid, nil, {quiet = true})
        end)
    end
    return object
end

function Process:kill(signal, options)
    self.kill_pid(self.pid, signal, options)
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

return Process
