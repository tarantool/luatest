--- Collection of Tarantool related functions.
--
-- @module luatest.tarantool

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
-- @string[opt] message
function M.skip_if_not_debug(message)
    assertions.skip_if(
        not M.is_debug_build(), message or 'build type is not Debug'
    )
end

--- Skip a running test if Tarantool package is Enterprise.
--
-- @string[opt] message
function M.skip_if_enterprise(message)
    assertions.skip_if(
        M.is_enterprise_package(), message or 'package is Enterprise'
    )
end

return M
