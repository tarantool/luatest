local t = require('luatest')
local g = t.group()

local fiber = require('fiber')
local fio = require('fio')
local fun = require('fun')

local Process = t.Process
local Capture = require('luatest.capture')

local process, kill_after_test

g.before_each(function()
    kill_after_test = true
end)

g.after_each(function()
    if process and kill_after_test then
        process:kill()
    end
    process = nil
end)

g.test_start = function()
    process = Process:start('/bin/sleep', {'5'})
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert(process:is_alive())
    end)
    process:kill()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(process:is_alive())
    end)
    kill_after_test = false
end

g.test_start_with_output_prefix = function()
    local capture = Capture:new()
    capture:wrap(true, function()
        process = Process:start('/bin/echo', {'test content'}, nil, {output_prefix = 'test_prefix'})
        t.helpers.retrying({timeout = 0.5}, function()
            t.assert_not(process:is_alive())
        end)
        process.output_beautifier.class:synchronize(function() end)
        process = nil
    end)
    local captured = capture:flush()
    -- Split on 2 assertions, because of color codes
    t.assert_str_contains(captured.stdout, 'test_prefix |')
    t.assert_str_contains(captured.stdout, 'test content')
    _G.collectgarbage()
end

g.test_start_with_output_prefix_and_large_output = function()
    local capture = Capture:new()
    local count = 8000
    capture:wrap(true, function()
        process = Process:start('/bin/bash', {'-c', "printf 'Hello\n%.0s' {1.." .. count .. "}"},
            nil, {output_prefix = 'test_prefix'})
        t.helpers.retrying({timeout = 0.5, delay = 0.01}, function()
            t.assert_not(process:is_alive())
        end)
        process.output_beautifier.class:synchronize(function() end)
        process = nil
    end)
    local captured = capture:flush()
    -- Split on 2 assertions, because of color codes
    t.assert_str_contains(captured.stdout, 'test_prefix |')
    t.assert_str_contains(captured.stdout, 'Hello')
    t.assert_equals(fun.wrap(captured.stdout:gmatch('Hello')):length(), count)
end

g.test_start_with_ignore_gc = function()
    local process1 = Process:start('/bin/sleep', {'5'})
    local pid1 = process1.pid
    local process2 = Process:start('/bin/sleep', {'5'}, {}, {ignore_gc = true})
    local pid2 = process2.pid
    t.assert(Process.is_pid_alive(pid1))
    t.assert(Process.is_pid_alive(pid2))
    process1 = nil -- luacheck: no unused
    process2 = nil -- luacheck: no unused
    _G.collectgarbage()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(Process.is_pid_alive(pid1))
        t.assert(Process.is_pid_alive(pid2))
    end)
    Process.kill_pid(pid2)
end

g.test_autokill_gced_process_with_output_prefix = function()
    local process1 = Process:start('/bin/sleep', {'5'}, {}, {output_prefix = 'test_prefix'})
    local pid1 = process1.pid
    process1 = nil -- luacheck: no unused
    _G.collectgarbage()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(Process.is_pid_alive(pid1))
    end)
end

g.test_kill_non_posix = function()
    process = Process:start('/bin/sleep', {'5'})
    fiber.sleep(0.1)
    process:kill('STOP')
    fiber.sleep(0.1)
    process:kill('CONT')
end

g.test_chdir = function()
    local file = 'luatest-tmp-file'
    local file_copy = file .. '-copy'
    if fio.stat('./tmp/' .. file_copy) ~= nil then
        assert(fio.unlink('./tmp/' .. file_copy))
    end
    os.execute('touch ./tmp/' .. file)

    local proc = Process:start('/bin/cp', {file, file_copy})
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not(proc:is_alive())
        t.assert_equals(fio.stat('./tmp/' .. file_copy), nil)
    end)

    Process:start('/bin/cp', {file, file_copy}, {}, {chdir = './tmp'})
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not_equals(fio.stat('./tmp/' .. file_copy), nil)
    end)
end

g.test_start_with_debug_hook = function()
    local original_hook = {debug.gethook()}
    -- Hook is extracted from luacov. This is minimal implementation which makes fork-execve fail.
    debug.sethook(function(_, _, level) debug.getinfo(level or 2, 'S') end, 'l')
    local n = 100
    local env = table.copy(os.environ())
    local processes = fun.range(n):map(function()
        return t.Process:start('/bin/sleep', {'10'}, env)
    end):totable()
    fiber.sleep(0.5) -- wait until all processes called execve
    debug.sethook(unpack(original_hook))
    local running = fun.iter(processes):filter(function(x) return x:is_alive() end):totable()
    t.assert_equals(#running, n)
end
