local fun = require('fun')
local yaml = require('yaml')

local utils = {}

-- Helper to override methods.
--
--     utils.patch(target, 'method_name', function(super) return function(...)
--       print('from patched method')
--       super(...)
--     end end)
function utils.patch(object, name, fn)
    local super = object[name]
    assert(super)
    object[name] = fn(super)
end

-- Merges multiple maps.
function utils.merge(...)
    return fun.chain(...):tomap()
end

-- Pretty traceback for error.
function utils.traceback(err, skip)
    if type(err) ~= 'string' then
        err = yaml.encode(err)
    end
    return debug.traceback(err, 2 + (skip or 0)) .. '\n'
end

-- Reraises error but calls `ensure` in both cases of success and failure.
function utils.reraise_and_ensure(fn, rescue, ensure)
    local result = {xpcall(fn, rescue)}
    if ensure then
        ensure()
    end
    if result[1] then
        return unpack(result, 2)
    else
        return error(result[2])
    end
end

return utils
