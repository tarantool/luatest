local t = require('luatest')
local g = t.group('fixtures.log')

local fiber = require('fiber')

g.test_log = function()
    t.log('LUATEST LOG TEST')
    -- XXX: workaround for #418 (logs are lost if tests don't yield)
    fiber.sleep(0.5)
end
