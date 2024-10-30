local json = require('json')
local Output = require('luatest.output.generic'):new_class()

local res = {}

function Output.mt:start_suite()
    res = {
        started_on = self.result.start_time,
        tests = {},
    }
end

function Output.mt:end_test(node)
    local test = {
        name = node.name,
        message = node.message,
        group = node.group.name,
    }

    if node:is('xfail') then
        test.xfail = true
    end

    if node:is('skip') then
        test.skip = true
    end

    if node:is('success') then
        test.status = 'OK'
    end

    if node:is('fail')then
        test.status = 'FAIL'
    end

    if node:is('error')then
        test.status = 'ERROR'
    end

    table.insert(res.tests, test)
end

function Output.mt:end_suite()
    local tests = self.result.tests
    res.xfail = #tests.xfail
    res.xsuccess = #tests.xsuccess
    res.fail = #tests.fail
    res.error = #tests.error
    res.skip = #tests.skip
    res.all = #tests.all
    res.success = #tests.success
    res.duration = self.result.duration

    print(json.encode(res))
end

return Output
