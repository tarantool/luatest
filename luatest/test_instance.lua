local TestInstance = require('luatest.class').new()

function TestInstance:build(group, method_name)
    local name = group.name .. '.' .. method_name
    local method = assert(group[method_name], 'Could not find method ' .. name)
    assert(type(method) == 'function', name .. ' is not a function')
    return self:from({
        name = name,
        group = group,
        method_name = method_name,
        method = method,
        line = debug.getinfo(method).linedefined or 0,
    })
end

-- default constructor, test are PASS by default
function TestInstance.mt:initialize()
    self.status = 'success'
    self.artifacts = 'server artifacts:\n'
end

function TestInstance.mt:update_status(status, message, trace)
    self.status = status
    self.message = message
    self.trace = trace
end

function TestInstance.mt:add_server_artifacts_directory(alias, workdir)
    local prepared_str = string.format('#\t%s -> %s\n', alias, workdir)
    self.artifacts = self.artifacts .. prepared_str
end

function TestInstance.mt:is(status)
    return self.status == status
end

return TestInstance
