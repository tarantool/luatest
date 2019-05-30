local checks = require('checks')
local fun = require('fun')
local ffi = require('ffi')
local fio = require('fio')

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

-- Starts process and returns immediately, not waiting until process is finished.
function Process:start(path, args, env, options)
    checks('table', 'string', '?table', '?table', {chdir = '?string'})
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
        return self:new({pid = pid})
    end
    if options.chdir then
        fio.chdir(options.chdir)
    end
    ffi.C.execve(path, argv, envp)
    error('execve failed')
end

function Process:new(object)
    setmetatable(object, self)
    self.__index = self
    return object
end

function Process:kill(signal)
    -- Signal values are platform-dependent so we can not use ffi here
    signal = signal or 15
    local exit_code = os.execute('kill -' .. signal .. ' ' .. self.pid)
    if exit_code ~= 0 then
        error('kill failed: ' .. exit_code)
    end
end

return Process
