local utils = require('luatest.utils')

-- suite hooks
local function define_suite_hooks(lu, type)
    local hooks = {}
    lu[type .. '_hooks'] = hooks

    lu[type] = function(fn)
        table.insert(hooks, fn)
    end

    lu['run_' .. type] = function()
        for _, fn in ipairs(hooks) do
            fn()
        end
    end
end

-- test group (class) hooks
local function run_class_callback(runner, className, type)
    local classInstance = runner.testsContainer()[className]
    local func = classInstance and classInstance[type]
    return func and func()
end

-- Adds suite and test group hooks.
return function(lu)
    define_suite_hooks(lu, 'before_suite')
    define_suite_hooks(lu, 'after_suite')

    utils.patch(lu.LuaUnit, 'startClass', function(super) return function(self, className)
        super(self, className)
        run_class_callback(self, className, 'before_all')
    end end)

    utils.patch(lu.LuaUnit, 'endClass', function(super) return function(self)
        run_class_callback(self, self.lastClassName, 'after_all')
        super(self)
    end end)

    utils.patch(lu.LuaUnit, 'runTestsList', function(super) return function(self, tests)
        if #tests == 0 then
            return
        end
        return utils.reraise_and_ensure(function()
            lu.run_before_suite()
            super(self, tests)
        end, function(err)
            return err
        end, function()
            lu.run_after_suite()
        end)
    end end)
end
