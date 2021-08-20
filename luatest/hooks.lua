local utils = require('luatest.utils')

local export = {}

local function table_len(t)
    local counter = 0
    for _, _ in pairs(t) do
        counter = counter + 1
    end
    return counter
end

local function arrange_hooks(object, hooks, hooks_type, test_name)
    local active_hooks_name = 'active_' .. hooks_type
    if test_name then
        active_hooks_name = active_hooks_name .. '_' .. test_name
        hooks = hooks[test_name]
    end
    active_hooks_name = active_hooks_name .. '_hooks'

    if object[active_hooks_name] then
        return object[active_hooks_name]
    end

    local active_hooks = {}
    for _, entry in ipairs(hooks) do
        local params_is_ok = true
        for name, value in pairs(entry[2]) do
            if object.params
            and object.params[name] ~= value then
                params_is_ok = false
                break
            end
        end

        if params_is_ok then
            table.insert(active_hooks, entry)
        end
    end

    local comparator
    if string.find(hooks_type, 'after') then
        comparator = function(a, b)
            return (table_len(a[2])) > (table_len(b[2]))
        end
    else
        comparator = function(a, b)
            return (table_len(a[2])) < (table_len(b[2]))
        end
    end
    table.sort(active_hooks, comparator)

    object[active_hooks_name] = {}
    for _, entry in ipairs(active_hooks) do
        table.insert(object[active_hooks_name], entry[1])
    end

    return object[active_hooks_name]
end

local function define_hooks(object, hooks_type)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    object[hooks_type] = function(fn, params)
        params = params or {}
        table.insert(hooks, {fn, params})
    end
    object['_original_' .. hooks_type] = object[hooks_type] -- for leagacy hooks support

    object['run_' .. hooks_type] = function()
        local hooks = object[hooks_type .. '_hooks']
        local active_hooks = arrange_hooks(object, hooks, hooks_type)
        for _, hook in ipairs(active_hooks) do
            hook(object)
        end
    end
end

local function define_named_hooks(object, hooks_type)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    object[hooks_type] = function(test_name, fn, params)
        test_name = object.name .. '.' .. test_name
        params = params or {}
        if not hooks[test_name] then
            hooks[test_name] = {}
        end
        table.insert(hooks[test_name], {fn, params})
    end

    object['run_' .. hooks_type] = function(test)
        local hooks = object[hooks_type .. '_hooks']
        local test_name = test.name

        -- When parametrized groups are defined named hooks saved by
        -- super group test name. When they are called test name is
        -- specific to the parametrized group. So, it should be
        -- converted back to the super one.
        if object.super_group then
            local test_name_parts, parts_amount = utils.split_test_name(test_name)
            test_name = object.super_group.name .. '.' .. test_name_parts[parts_amount]
        end

        if not hooks[test_name] then
            return
        end

        local active_hooks = arrange_hooks(object, hooks, hooks_type, test_name)
        for _, hook in ipairs(active_hooks) do
            hook(object)
        end
    end
end

-- Define hooks on group.
function export.define_group_hooks(group)
    define_hooks(group, 'before_each')
    define_hooks(group, 'after_each')
    define_hooks(group, 'before_all')
    define_hooks(group, 'after_all')

    define_named_hooks(group, 'before_test')
    define_named_hooks(group, 'after_test')
    return group
end

-- Define suite hooks on luatest.
function export.define_suite_hooks(luatest)
    define_hooks(luatest, 'before_suite')
    define_hooks(luatest, 'after_suite')
end

local function run_group_hooks(runner, group, hooks_type)
    local result
    local hook = group and group['run_' .. hooks_type]
    -- If _original_%hook_name% is not equal to %hook_name%, it means
    -- that this method was assigned by user (legacy API).
    if hook and group[hooks_type] == group['_original_' .. hooks_type] then
        result = runner:protected_call(group, hook, group.name .. '.run_before_all_hooks')
    elseif group and group[hooks_type] then
        result = runner:protected_call(group, group[hooks_type], group.name .. '.before_all')
    end
    if result and result.status ~= 'success' then
        return result
    end
end

local function run_test_hooks(self, test, hooks_type, legacy_name)
    local group = test.group
    local hook
    -- Support for group.setup/teardown methods (legacy API)
    hook = group[legacy_name]
    if hook and type(hook) == 'function' then
        self:update_status(test, self:protected_call(group, hook, group.name .. '.' .. legacy_name))
    end
    hook = group['run_' .. hooks_type]
    if hook then
        self:update_status(test, self:protected_call(group, hook))
    end
end

local function run_named_test_hooks(self, test, hooks_type)
    local group = test.group
    local hook = group['run_' .. hooks_type]
    if hook then
        self:update_status(test, self:protected_call(test, hook))
    end
end

function export.patch_runner(Runner)
    -- Last run test to set error for when group.after_all hook fails.
    local last_test = nil

    -- Run test hooks.
    -- If test's group hook failed with error, then test does not run and
    -- hook's error is copied for the test.
    utils.patch(Runner.mt, 'invoke_test_function', function(super) return function(self, test, ...)
        last_test = test
        if test.group._before_all_hook_error then
            return self:update_status(test, test.group._before_all_hook_error)
        end
        run_test_hooks(self, test, 'before_each', 'setup')
        run_named_test_hooks(self, test, 'before_test')
        if test:is('success') then
            super(self, test, ...)
        end
        run_named_test_hooks(self, test, 'after_test')
        run_test_hooks(self, test, 'after_each', 'teardown')
    end end)

    -- Run group hook and save possible error to the group object.
    utils.patch(Runner.mt, 'start_group', function(super) return function(self, group)
        super(self, group)
        group._before_all_hook_error = run_group_hooks(self, group, 'before_all')
    end end)

    -- Run group hook and save possible error to the `last_test`.
    utils.patch(Runner.mt, 'end_group', function(super) return function(self, group)
        local err = run_group_hooks(self, group, 'after_all')
        if err then
            err.message = 'Failure in after_all hook: ' .. tostring(err.message)
            self:update_status(last_test, err)
        end
        super(self, group)
    end end)

    -- Run suite hooks
    utils.patch(Runner.mt, 'run_tests', function(super) return function(self, tests)
        if #tests == 0 then
            return
        end
        return utils.reraise_and_ensure(function()
            self.luatest.run_before_suite()
            super(self, tests)
        end, nil, function()
            self.luatest.run_after_suite()
        end)
    end end)
end

return export
