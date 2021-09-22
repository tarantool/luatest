-- Base output class.
local Output = require('luatest.class').new({
    VERBOSITY = {
        DEFAULT = 10,
        QUIET   = 0,
        LOW     = 1,
        VERBOSE = 20,
        REPEAT  = 21,
    },
})

function Output.mt:initialize(runner)
    self.runner = runner
    self.result = runner.result
    self.verbosity = runner.verbosity
end

-- luacheck: push no unused
-- abstract ("empty") methods
function Output.mt:start_suite()
    -- Called once, when the suite is started
end

function Output.mt:start_group(group)
    -- Called each time a new test group is started
end

function Output.mt:start_test(test)
    -- called each time a new test is started, right before the setUp()
end

function Output.mt:update_status(node)
    -- called with status failed or error as soon as the error/failure is encountered
    -- this method is NOT called for a successful test because a test is marked as successful by default
    -- and does not need to be updated
end

function Output.mt:end_test(node)
    -- called when the test is finished, after the tearDown() method
end

function Output.mt:end_group(group)
    -- called when executing the group is finished, before moving on to the next group
    -- of at the end of the test execution
end

function Output.mt:end_suite()
    -- called at the end of the test suite execution
end
-- luacheck: pop

local function conditional_plural(number, singular)
    -- returns a grammatically well-formed string "%d <singular/plural>"
    local suffix = ''
    if number ~= 1 then -- use plural
        suffix = (singular:sub(-2) == 'ss') and 'es' or 's'
    end
    return string.format('%d %s%s', number, singular, suffix)
end

function Output.mt:status_line(colors)
    colors = colors or {success = '', failure = '', reset = '', xfail = ''}
    -- return status line string according to results
    local tests = self.result.tests
    local s = {
        string.format('Ran %d tests in %0.3f seconds', #tests.all - #tests.skip, self.result.duration),
        colors.success .. conditional_plural(#tests.success, 'success') .. colors.reset,
    }
    if #tests.xfail > 0 then
        table.insert(s, colors.xfail .. conditional_plural(#tests.xfail, 'xfail') .. colors.reset)
    end
    if #tests.xsuccess > 0 then
        table.insert(s, colors.failure .. conditional_plural(#tests.xsuccess, 'xsuccess') .. colors.reset)
    end
    if #tests.fail > 0 then
        table.insert(s, colors.failure .. conditional_plural(#tests.fail, 'fail') .. colors.reset)
    end
    if #tests.error > 0 then
        table.insert(s, colors.failure .. conditional_plural(#tests.error, 'error') .. colors.reset)
    end
    if #tests.fail == 0 and #tests.error == 0 and #tests.xsuccess == 0 then
        table.insert(s, '0 failures')
    end
    if #tests.skip > 0 then
        table.insert(s, string.format("%d skipped", #tests.skip))
    end
    if self.result.not_selected_count > 0 then
        table.insert(s, string.format("%d not-selected", self.result.not_selected_count))
    end
    return table.concat(s, ', ')
end

return Output
