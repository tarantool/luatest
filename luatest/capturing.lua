local utils = require('luatest.utils')

-- Patch luaunit to capture output in tests and show it only for failed ones.
return function(lu, capture)
    utils.patch(lu.LuaUnit, 'startSuite', function(super) return function(self, ...)
        super(self, ...)
        capture:enable()
        capture:flush()
    end end)

    utils.patch(lu.LuaUnit, 'endSuite', function(super) return function(self, ...)
        capture:flush()
        capture:disable()
        super(self, ...)
    end end)

    utils.patch(lu.LuaUnit, 'startTest', function(super) return function(self, ...)
        capture:enable()
        capture:flush()
        super(self, ...)
    end end)

    utils.patch(lu.LuaUnit, 'endTest', function(super) return function(self, ...)
        local node = self.result.currentNode
        if capture.enabled then
            node.capture = capture:flush()
        end
        capture:disable()
        super(self, ...)
        capture:enable()
    end end)

    utils.patch(lu.LuaUnit, 'startClass', function(super) return function(self, ...)
        super(self, ...)
        capture:enable()
        capture:flush()
    end end)

    utils.patch(lu.LuaUnit, 'endClass', function(super) return function(self, ...)
        super(self, ...)
        capture:flush()
        capture:disable()
    end end)

    local function print_capture(name, text)
        if text and text:len() > 0 then
            print('Captured ' .. name .. ':')
            print(text)
            print()
        end
    end

    local TextOutput = lu.LuaUnit.outputType
    utils.patch(TextOutput, 'displayOneFailedTest', function(super) return function(self, index, node)
        super(self, index, node)
        if node.capture then
            print_capture('stdout', node.capture.stdout)
            print_capture('stderr', node.capture.stderr)
        end
    end end)
end
