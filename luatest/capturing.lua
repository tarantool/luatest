local Capture = require('luatest.capture')
local GenericOutput = require('luatest.output.generic')
local OutputBeautifier = require('luatest.output_beautifier')
local utils = require('luatest.utils')

local function format_captured(name, text)
    if text and text:len() > 0 then
        return 'Captured ' .. name .. ':\n' .. text .. '\n\n'
    else
        return ''
    end
end

-- Shortcut to create proxy methods wrapped with `capture.wrap`.
local function wrap_method(enabled, object, name)
    utils.patch(object, name, function(super) return function(self, ...)
        local args = {self, ...}
        if enabled then
            return self.capture:wrap(enabled, function() return super(unpack(args)) end)
        end
        -- Pause OutputBeautifier when capturing is disabled because
        -- yields inside can make beautified output bypass the capture.
        return OutputBeautifier:synchronize(function()
            return self.capture:wrap(enabled, function() return super(unpack(args)) end)
        end)
    end end)
end

-- Create new output instance with patched methods.
local function patch_output(capture, output)
    output = table.copy(output)
    output.capture = capture

    -- Disable capturing when printing output
    for name, val in pairs(GenericOutput.mt) do
        if type(val) == 'function' then
            wrap_method(false, output, name)
        end
    end

    if output.display_one_failed_test then
        -- Print captured output for failed test
        utils.patch(output, 'display_one_failed_test', function(super) return function(self, index, node)
            super(self, index, node)
            if node.capture then
                io.stdout:write(format_captured('stdout', node.capture.stdout))
                io.stdout:write(format_captured('stderr', node.capture.stderr))
            end
        end end)
    end

    return output
end

-- Patch Runner to capture output in tests and show it only for failed ones.
return function(Runner)
    utils.patch(Runner.mt, 'initialize', function(super) return function(self, ...)
        if not self.capture then
            if self.enable_capture or self.enable_capture == nil then
                self.capture = Capture:new()
            else
                self.capture = Capture:stub()
            end
        end

        super(self, ...)

        self.output = patch_output(self.capture, self.output)
    end end)

    -- Print captured output for any unexpected error.
    utils.patch(Runner.mt, 'run', function(super) return function(self, ...)
        local args = {self, ...}
        local _, code = xpcall(function() return super(unpack(args)) end, function(err)
            local message
            local captured = {}
            if err.type == self.capture.class.CAPTURED_ERROR_TYPE then
                message = err.traceback
                captured = err.captured
            else
                message = utils.traceback(err)
                if self.capture.enabled then
                    captured = self.capture:flush()
                end
            end
            message = message ..
                format_captured('stdout', captured.stdout) ..
                format_captured('stderr', captured.stderr)
            self.capture:wrap(false, function() io.stderr:write(message) end)
            return -1
        end)
        return code
    end end)

    -- This methods are run outside of the suite, so output needs to be captured.
    wrap_method(true, Runner.mt, 'bootstrap')

    -- Main capturing wrapper.
    wrap_method(true, Runner.mt, 'run_tests')

    -- Disable capturing to print possible notices.
    wrap_method(false, Runner.mt, 'end_test')

    -- Save captured output into result in the case of failure.
    utils.patch(Runner.mt, 'protected_call', function(super) return function(self, ...)
        local result = super(self, ...)
        if self.capture.enabled and result and result.status ~= 'success' then
            result.capture = self.capture:flush()
        end
        return result
    end end)

    -- Copy captured output from result to the test node.
    utils.patch(Runner.mt, 'update_status', function(super) return function(self, node, result)
        if result.capture then
            node.capture = result.capture
        end
        return super(self, node, result)
    end end)

    -- Flush capture before and after running a test.
    utils.patch(Runner.mt, 'run_test', function(super) return function(self, ...)
        self.capture:flush()
        local result = super(self, ...)
        self.capture:flush()
        return result
    end end)
end
