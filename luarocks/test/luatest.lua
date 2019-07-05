local export = {}

function export.run_tests(_, args)
    local result = require('luatest.sandboxed_runner').run(args)
    if result == 0 then
        return true
    else
        return nil, 'test suite failed.'
    end
end

return export
