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

return utils
