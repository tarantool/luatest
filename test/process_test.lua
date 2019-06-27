local t = require('luatest')
local g = t.group('process')
local fiber = require('fiber')
local fio = require('fio')

local Process = t.Process

local process, kill_after_test

g.setup = function() kill_after_test = true end
g.teardown = function()
    if process and kill_after_test then
        process:kill()
    end
    process = nil
end

local function test_pid(pid)
    return os.execute('ps -p ' .. tonumber(pid) .. ' > /dev/null')
end

g.test_start = function()
    process = Process:start('/bin/sleep', {'5'})
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_equals(test_pid(process.pid), 0)
    end)
    process:kill()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not_equals(test_pid(process.pid), 0)
    end)
    kill_after_test = false
end

g.test_start_with_ignore_gc = function()
    local process1 = Process:start('/bin/sleep', {'5'})
    local pid1 = process1.pid
    local process2 = Process:start('/bin/sleep', {'5'}, {}, {ignore_gc = true})
    local pid2 = process2.pid
    t.assert_equals(test_pid(pid1), 0)
    t.assert_equals(test_pid(pid2), 0)
    process1 = nil -- luacheck: no unused
    process2 = nil -- luacheck: no unused
    _G.collectgarbage()
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not_equals(test_pid(pid1), 0)
        t.assert_equals(test_pid(pid2), 0)
    end)
    Process.kill_pid(pid2)
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
        t.assert_not_equals(test_pid(proc.pid), 0)
        t.assert_equals(fio.stat('./tmp/' .. file_copy), nil)
    end)

    Process:start('/bin/cp', {file, file_copy}, {}, {chdir = './tmp'})
    t.helpers.retrying({timeout = 0.5}, function()
        t.assert_not_equals(fio.stat('./tmp/' .. file_copy), nil)
    end)
end
