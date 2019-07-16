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

-- Merges multiple maps into first one. Later arguments has lower precedence, so
-- existing keys are not overwritten.
function utils.reverse_merge(target, ...)
    for _, source in ipairs({...}) do
        for k, v in pairs(source) do
            if target[k] == nil then
                target[k] = v
            end
        end
    end
    return target
end

-- Pretty traceback for error.
function utils.traceback(err, skip)
    if type(err) ~= 'string' then
        err = yaml.encode(err)
    end
    return debug.traceback(err, 2 + (skip or 0)) .. '\n'
end

return utils
