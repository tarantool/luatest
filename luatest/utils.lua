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

function utils.print_captured(name, text, stream)
    stream = stream or io.stdout
    if text and text:len() > 0 then
        stream:write('Captured ' .. name .. ':\n' .. text .. '\n\n')
    end
end

return utils
