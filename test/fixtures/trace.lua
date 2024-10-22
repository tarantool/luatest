local fio = require('fio')

local t = require('luatest')
local server = require('luatest.server')

local g = t.group('fixtures.trace')

local root = fio.dirname(fio.abspath('test.helpers'))

g.before_all(function(cg)
    cg.server = server:new{
        env = {
            LUA_PATH = root .. '/?.lua;' ..
                root .. '/?/init.lua;' ..
                root .. '/.rocks/share/tarantool/?.lua'
        }
    }
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
