--- Collection of test helpers related to Tarantool instance.
--
-- @module luatest.tarantool

local fiber = require('fiber')
local tarantool = require('tarantool')

local assertions = require('luatest.assertions')

local M = {}

--- Return true if Tarantool build type is Debug.
function M.is_debug_build()
    return tarantool.build.target:endswith('-Debug')
end

--- Return true if Tarantool package is Enterprise.
function M.is_enterprise_package()
    return tarantool.package == 'Tarantool Enterprise'
end

--- Skip a running test unless Tarantool build type is Debug.
--
-- @string[opt] message Message to describe the reason.
function M.skip_if_not_debug(message)
    assertions.skip_if(
        not M.is_debug_build(), message or 'build type is not Debug'
    )
end

--- Skip a running test if Tarantool package is Enterprise.
--
-- @string[opt] message Message to describe the reason.
function M.skip_if_enterprise(message)
    assertions.skip_if(
        M.is_enterprise_package(), message or 'package is Enterprise'
    )
end

--- Skip a running test if Tarantool package is NOT Enterprise.
--
-- @string[opt] message Message to describe the reason.
function M.skip_if_not_enterprise(message)
    assertions.skip_if(
        not M.is_enterprise_package(), message or 'package is not Enterprise'
    )
end

--- Search for a fiber with the specified name and return the fiber object.
--
-- @string name Fiber name.
function M.find_fiber_by_name(name)
    for id, f in pairs(fiber.info()) do
        if f.name == name then
            return fiber.find(id)
        end
    end
    return nil
end

return M
