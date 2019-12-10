local fiber = require('fiber')
local utils = require('luatest.utils')

-- Reentrant mutex for fibers.
local Monitor = {mt = {}}
Monitor.mt.__index = Monitor.mt

function Monitor:new()
    return setmetatable({
        mutex = fiber.cond(),
        fiber_id = nil,
        count = 0,
    }, self.mt)
end

function Monitor.mt:synchronize(fn)
    local fiber_id = fiber.self():id()
    while self.count > 0 and self.fiber_id ~= fiber_id do
        self.mutex:wait()
    end
    self.fiber_id = fiber_id
    self.count = self.count + 1
    return utils.reraise_and_ensure(fn, function(err) return err end, function()
        self.count = self.count - 1
        if self.count == 0 then
            self.fiber_id = nil
            self.mutex:signal()
        end
    end)
end

return Monitor
