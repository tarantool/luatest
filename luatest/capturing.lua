local utils = require('luatest.utils')

local function format_captured(name, text)
    if text and text:len() > 0 then
        return 'Captured ' .. name .. ':\n' .. text .. '\n\n'
    else
        return ''
    end
end

-- Shortcut to create proxy methods wrapped with `capture.wrap`.
local function wrap_methods(capture, enabled, object, ...)
    for _, name in pairs({...}) do
        utils.patch(object, name, function(super) return function(...)
            local args = {...}
            return capture:wrap(enabled, function() return super(unpack(args)) end)
        end end)
    end
end

-- Disable capturing when printing output.
local function patch_output(capture, output, genericOutput)
    for name, val in pairs(genericOutput) do
        if type(val) == 'function' then
            wrap_methods(capture, false, output, name)
        end
    end
end

-- Patch luaunit to capture output in tests and show it only for failed ones.
return function(lu, capture)
    -- Add captured output if any when printing error.
    function lu.print_error(err)
        local message
        local captured = {}
        if err.type == capture.CAPTURED_ERROR_TYPE then
            message = err.traceback
            captured = err.captured
        else
            message = utils.traceback(err)
            if capture.enabled then
                captured = capture:flush()
            end
        end
        message = message ..
            format_captured('stdout', captured.stdout) ..
            format_captured('stderr', captured.stderr)
        capture:wrap(false, function() io.stderr:write(message) end)
    end

    -- This methods are run outside of the suite, so output needs to be captured.
    wrap_methods(capture, true, lu, 'load_tests')

    -- Patch output here because it's created in `super`
    utils.patch(lu.LuaUnit, 'start_suite', function(super) return function(self, ...)
        super(self, ...)
        patch_output(capture, self.output, lu.genericOutput)
    end end)

    -- Main capturing wrapper.
    wrap_methods(capture, true, lu.LuaUnit, 'run_tests')

    -- Disable capture in case of failure because `end_suite` is not called.
    for _, name in pairs({'start_group', 'end_group'}) do
        utils.patch(lu.LuaUnit, name, function(super) return function(...)
            local args = {...}
            utils.reraise_and_ensure(function()
                -- Wrap error with capture to save original traceback.
                return capture:wrap(true, function() return super(unpack(args)) end)
            end, function(err)
                capture:disable()
                return err
            end)
        end end)
    end

    -- Disable capturing to print possible notices.
    wrap_methods(capture, false, lu.LuaUnit, 'end_test')

    -- Save captured output into the current test.
    utils.patch(lu.LuaUnit, 'end_test', function(super) return function(self, test)
        if capture.enabled then
            test.capture = capture:flush()
        end
        super(self, test)
    end end)

    local TextOutput = lu.OutputTypes.text

    -- Print captured output for failed test.
    utils.patch(TextOutput, 'display_one_failed_test', function(super) return function(self, index, node)
        super(self, index, node)
        if node.capture then
            io.stdout:write(format_captured('stdout', node.capture.stdout))
            io.stdout:write(format_captured('stderr', node.capture.stderr))
        end
    end end)
end
