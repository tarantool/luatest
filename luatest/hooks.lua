local utils = require('luatest.utils')

-- suite hooks
local function define_hooks(object, type)
    local hooks = {}
    object[type .. '_hooks'] = hooks

    object[type] = function(fn)
        table.insert(hooks, fn)
    end
    object['_original_' .. type] = object[type] -- for leagacy hooks support

    object['run_' .. type] = function()
        for _, fn in ipairs(hooks) do
            fn()
        end
    end
end

local function run_group_hooks(group, type)
    local hook = group and group['run_' .. type]
    -- If _original_%hook_name% is not equal to %hook_name%, it means
    -- that this method was assigned by user (legacy API).
    if hook and group[type] == group['_original_' .. type] then
        hook()
    elseif group and group[type] then
        group[type]()
    end
end

local function run_test_hooks(self, group, type, legacy_name)
    local hook
    -- Support for group.setup/teardown methods (legacy API)
    hook = self.as_function(group[legacy_name])
    if hook then
        self:update_status(self:protected_call(group, hook, group.name .. '.' .. legacy_name))
    end
    hook = group['run_' .. type]
    if hook then
        self:update_status(self:protected_call(group, hook))
    end
end

-- Adds suite and test group hooks.
return function(lu)
    define_hooks(lu, 'before_suite')
    define_hooks(lu, 'after_suite')

    utils.patch(lu, 'group', function(super) return function(...)
        local group = super(...)
        define_hooks(group, 'before_each')
        define_hooks(group, 'after_each')
        define_hooks(group, 'before_all')
        define_hooks(group, 'after_all')
        return group
    end end)

    utils.patch(lu.LuaUnit, 'invoke_test_function', function(super) return function(self, test)
        run_test_hooks(self, test.group, 'before_each', 'setup')
        if self.result.currentNode:is_success() then
            super(self, test)
        end
        run_test_hooks(self, test.group, 'after_each', 'teardown')
    end end)


    utils.patch(lu.LuaUnit, 'start_group', function(super) return function(self, ...)
        super(self, ...)
        run_group_hooks(self.result.current_group, 'before_all')
    end end)

    utils.patch(lu.LuaUnit, 'end_group', function(super) return function(self)
        run_group_hooks(self.result.current_group, 'after_all')
        super(self)
    end end)

    utils.patch(lu.LuaUnit, 'run_tests', function(super) return function(self, tests)
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
