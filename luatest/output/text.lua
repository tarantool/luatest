local utils = require('luatest.utils')
local Output = require('luatest.output.generic'):new_class()

Output.BOLD_CODE = '\x1B[1m'
Output.ERROR_COLOR_CODE = Output.BOLD_CODE .. '\x1B[31m' -- red
Output.SUCCESS_COLOR_CODE = Output.BOLD_CODE .. '\x1B[32m' -- green
Output.WARN_COLOR_CODE = Output.BOLD_CODE .. '\x1B[33m' -- yellow
Output.RESET_TERM = '\x1B[0m'

function Output.mt:start_suite()
    if self.runner.seed then
        print('Running with --shuffle ' .. self.runner.shuffle .. ':' .. self.runner.seed)
    end
    if self.verbosity >= self.class.VERBOSITY.VERBOSE then
        print('Started on '.. os.date(nil, self.result.start_time))
    end
end

function Output.mt:start_test(test) -- luacheck: no unused
    if self.verbosity >= self.class.VERBOSITY.VERBOSE then
        io.stdout:write("    ", test.name, " ... ")
        if self.verbosity >= self.class.VERBOSITY.REPEAT then
            io.stdout:write("\n")
        end
    end
end

function Output.mt:end_test(node)
    if node:is('success') or node:is('xfail') then
        if self.verbosity >= self.class.VERBOSITY.VERBOSE then
            if self.verbosity >= self.class.VERBOSITY.REPEAT then
                io.stdout:write("    ", node.name, " ... ")
            end
            local duration = string.format("(%0.3fs) ", node.duration)
            io.stdout:write(duration)
            io.stdout:write(node:is('xfail') and "xfail\n" or "Ok\n")
            if node:is('xfail') then
                print(node.message)
            end
        else
            io.stdout:write(".")
            io.stdout:flush()
        end
    else
        if self.verbosity >= self.class.VERBOSITY.VERBOSE then
            if self.verbosity >= self.class.VERBOSITY.REPEAT then
                io.stdout:write("    ", node.name, " ... ")
            end
            local duration = string.format("(%0.3fs) ", node.duration)
            print(duration .. node.status)
            print(node.message)
        else
            -- write only the first character of status E, F, S or X
            io.stdout:write(string.sub(node.status, 1, 1):upper())
            io.stdout:flush()
        end
    end
end

function Output.mt:display_one_failed_test(index, fail) -- luacheck: no unused
    print(index..") " .. fail.name .. self.class.ERROR_COLOR_CODE)
    print(fail.message .. self.class.RESET_TERM)
    print(fail.trace)
    if utils.table_len(fail.servers) > 0 then
        print('artifacts:')
        for _, server in pairs(fail.servers) do
            print(('\t%s -> %s'):format(server.alias, server.artifacts))
        end
    end
end

function Output.mt:display_errored_tests()
    if #self.result.tests.error > 0 then
        print(self.class.BOLD_CODE)
        print("Tests with errors:")
        print("------------------")
        print(self.class.RESET_TERM)
        for i, v in ipairs(self.result.tests.error) do
            self:display_one_failed_test(i, v)
        end
    end
end

function Output.mt:display_failed_tests()
    if #self.result.tests.fail > 0 then
        print(self.class.BOLD_CODE)
        print("Failed tests:")
        print("-------------")
        print(self.class.RESET_TERM)
        for i, v in ipairs(self.result.tests.fail) do
            self:display_one_failed_test(i, v)
        end
    end
end

function Output.mt:display_xsucceeded_tests()
    if #self.result.tests.xsuccess > 0 then
        print(self.class.BOLD_CODE)
        print("Tests with an unexpected success:")
        print("-------------")
        print(self.class.RESET_TERM)
        for i, v in ipairs(self.result.tests.xsuccess) do
            self:display_one_failed_test(i, v)
        end
    end
end

function Output.mt:end_suite()
    if self.verbosity >= self.class.VERBOSITY.VERBOSE then
        print("=========================================================")
    else
        print()
    end
    self:display_errored_tests()
    self:display_failed_tests()
    self:display_xsucceeded_tests()
    print(self:status_line({
        success = self.class.SUCCESS_COLOR_CODE,
        failure = self.class.ERROR_COLOR_CODE,
        reset = self.class.RESET_TERM,
        xfail = self.class.WARN_COLOR_CODE,
    }))
    if self.result.notSuccessCount == 0 then
        print('OK')
    end

    local list = table.copy(self.result.tests.fail)
    for _, x in pairs(self.result.tests.error) do
        table.insert(list, x)
    end
    if #list > 0 then
        table.sort(list, function(a, b) return a.name < b.name end)
        if self.verbosity >= self.class.VERBOSITY.VERBOSE then
            print("\n=========================================================")
        else
            print()
        end
        print(self.class.BOLD_CODE .. 'Failed tests:\n' .. self.class.ERROR_COLOR_CODE)
        for _, x in pairs(list) do
            print(x.name)
        end
        io.stdout:write(self.class.RESET_TERM)
    end
end

return Output
