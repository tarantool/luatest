local t = require('luatest')
local server = require('luatest.server')

local g = t.group('fixtures.trace')

g.before_all(function(cg)
    cg.server = server:new()
    cg.server:start()
end)

g.after_all(function(cg)
    cg.server:drop()
end)

g.test_error = function(cg)
    local function outer()
        cg.server:exec(function()
            local function inner()
                error('test error')
            end
            inner()
        end)
    end
    outer()
end

g.test_fail = function(cg)
    local function outer()
        cg.server:exec(function()
            local function inner()
                t.assert(false)
            end
            inner()
        end)
    end
    outer()
end
