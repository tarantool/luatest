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

g.test_start = function()
    process = Process:start('/bin/sleep', {'5'})
    fiber.sleep(0.1)
    t.assertEquals(os.execute('ps -p ' .. process.pid .. ' > /dev/null'), 0)
    process:kill()
    fiber.sleep(0.1)
    t.assertNotEquals(os.execute('ps -p ' .. process.pid .. ' > /dev/null'), 0)
    kill_after_test = false
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

    Process:start('/bin/cp', {file, file_copy})
    fiber.sleep(0.1)
    t.assertEquals(fio.stat('./tmp/' .. file_copy), nil)

    Process:start('/bin/cp', {file, file_copy}, {}, {chdir = './tmp'})
    fiber.sleep(0.1)
    t.assertNotEquals(fio.stat('./tmp/' .. file_copy), nil)
end
