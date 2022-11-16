local utils = require('luatest.utils')
local comparator = require('luatest.comparator')

local export = {}

local function check_params(required, actual)
    for param_name, param_val in pairs(required) do
        if not comparator.equals(param_val, actual[param_name]) then
            return false
        end
    end

    return true
end

local function define_hooks(object, hooks_type)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    object[hooks_type] = function(...)
        local params, fn = ...
        if fn == nil then
            fn = params
            params = {}
        end

        assert(type(params) == 'table',
            string.format('params should be table, got %s', type(params)))
        assert(type(fn) == 'function',
            string.format('hook should be function, got %s', type(fn)))

        params = params or {}
        table.insert(hooks, {fn, params})
    end
    object['_original_' .. hooks_type] = object[hooks_type] -- for leagacy hooks support

    object['run_' .. hooks_type] = function()
        local active_hooks = object[hooks_type .. '_hooks']
        for _, hook in ipairs(active_hooks) do
            if check_params(hook[2], object.params) then
                hook[1](object)
            end
        end
    end
end

local function define_named_hooks(object, hooks_type)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    object[hooks_type] = function(...)
        local test_name, params, fn = ...
        if fn == nil then
            fn = params
            params = {}
        end

        assert(type(test_name) == 'string',
            string.format('test name should be string, got %s', type(test_name)))
        assert(type(params) == 'table',
            string.format('params should be table, got %s', type(params)))
        assert(type(fn) == 'function',
            string.format('hook should be function, got %s', type(fn)))

        test_name = object.name .. '.' .. test_name
        params = params or {}
        if not hooks[test_name] then
            hooks[test_name] = {}
        end
        table.insert(hooks[test_name], {fn, params})
    end

    object['run_' .. hooks_type] = function(test)
        local active_hooks = object[hooks_type .. '_hooks']
        local test_name = test.name

        -- When parametrized groups are defined named hooks saved by
        -- super group test name. When they are called test name is
        -- specific to the parametrized group. So, it should be
        -- converted back to the super one.
        if object.super_group then
            local test_name_parts, parts_amount = utils.split_test_name(test_name)
            test_name = object.super_group.name .. '.' .. test_name_parts[parts_amount]
        end

        if not active_hooks[test_name] then
            return
        end

        for _, hook in ipairs(active_hooks[test_name]) do
            if check_params(hook[2], object.params) then
                hook[1](object)
            end
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

        for _ = 1, self.exe_repeat or 1 do
            if not test:is('success') then
                break
            end

            run_test_hooks(self, test, 'before_each', 'setup')
            run_named_test_hooks(self, test, 'before_test')

            if test:is('success') then
                super(self, test, ...)
            end

            run_named_test_hooks(self, test, 'after_test')
            run_test_hooks(self, test, 'after_each', 'teardown')
        end
    end end)

    -- Run group hook and save possible error to the group object.
    utils.patch(Runner.mt, 'start_group', function(super) return function(self, group)
        super(self, group)
        -- Check while starting group that 'before_test' and 'after_test' hooks are defined only for existing tests.
        for _, hooks_type in ipairs({'before_test', 'after_test'}) do
            for full_test_name in pairs(group[hooks_type .. '_hooks']) do
                local test_name_parts, parts_count = utils.split_test_name(full_test_name)
                local test_name = test_name_parts[parts_count]
                if not group[test_name] then
                    error(string.format("There is no test with name '%s' but hook '%s' is defined for it",
                        test_name, hooks_type))
                end
            end
        end
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
