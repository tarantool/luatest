local fiber = require('fiber')

local Class = require('luatest.class')
local utils = require('luatest.utils')

-- Reentrant mutex for fibers.
local Monitor = Class.new()

function Monitor.mt:initialize()
    self.mutex = fiber.cond()
    self.fiber_id = nil
    self.count = 0
end

function Monitor.mt:synchronize(fn)
    local fiber_id = fiber.self():id()
    while self.count > 0 and self.fiber_id ~= fiber_id do
        self.mutex:wait()
    end
    self.fiber_id = fiber_id
    self.count = self.count + 1
    return utils.reraise_and_ensure(fn, nil, function()
        self.count = self.count - 1
        if self.count == 0 then
            self.fiber_id = nil
            self.mutex:signal()
        end
    end)
end

return Monitor
