--- Provide extra methods for hooks.
--
-- Preloaded hooks extend base hooks.
-- They behave like the pytest fixture with the `autouse` parameter.
--
-- @usage
--
-- local hooks = require('luatest.hooks')
--
-- hooks.before_suite_preloaded(...)
-- hooks.after_suite_preloaded(...)
--
-- hooks.before_all_preloaded(...)
-- hooks.after_all_preloaded(...)
--
-- hooks.before_each_preloaded(...)
-- hooks.after_each_preloaded(...)
--
-- @module luatest.hooks

local log = require('luatest.log')
local utils = require('luatest.utils')
local comparator = require('luatest.comparator')

local export = {}

local preloaded_hooks = {
    before_suite = {},
    after_suite = {},

    before_all = {},
    after_all = {},

    before_each = {},
    after_each = {}
}

--- Register preloaded before hook in the `suite` scope.
-- It will be done before the classic before_suite() hook in the tests.
--
-- @func fn The function where you will be preparing for the test.
function export.before_suite_preloaded(fn)
    table.insert(preloaded_hooks.before_suite, {fn, {}})
end

--- Register preloaded after hook in the `suite` scope.
-- It will be done after the classic after_suite() hook in the tests.
--
-- @func fn The function where you will be cleaning up for the test.
function export.after_suite_preloaded(fn)
    table.insert(preloaded_hooks.after_suite, {fn, {}})
end

--- Register preloaded before hook in the `all` scope.
-- It will be done before the classic before_all() hook in the tests.
--
-- @func fn The function where you will be preparing for the test.
function export.before_all_preloaded(fn)
    table.insert(preloaded_hooks.before_all, {fn, {}})
end

--- Register preloaded after hook in the `all` scope.
-- It will be done after the classic after_all() hook in the tests.
--
-- @func fn The function where you will be cleaning up for the test.
function export.after_all_preloaded(fn)
    table.insert(preloaded_hooks.after_all, {fn, {}})
end

--- Register preloaded before hook in the `each` scope.
-- It will be done before the classic before_each() hook in the tests.
--
-- @func fn The function where you will be preparing for the test.
function export.before_each_preloaded(fn)
    table.insert(preloaded_hooks.before_each, {fn, {}})
end

--- Register preloaded after hook in the `each` scope.
-- It will be done after the classic after_each() hook in the tests.
--
-- @func fn The function where you will be cleaning up for the test.
function export.after_each_preloaded(fn)
    table.insert(preloaded_hooks.after_each, {fn, {}})
end

local function check_params(required, actual)
    for param_name, param_val in pairs(required) do
        if not comparator.equals(param_val, actual[param_name]) then
            return false
        end
    end

    return true
end

local function set_hook_assignment_guard(object, hooks_type, accessor, opts)
    opts = opts or {}
    local mt = getmetatable(object)
    local guard = mt.__luatest_hook_guard

    if not guard then
        local new_mt = table.copy(mt)
        guard = {
            original_index = mt.__index,
            original_newindex = mt.__newindex,
            values = {},
            error_messages = {},
        }
        new_mt.__luatest_hook_guard = guard
        new_mt.__index = function(tbl, key)
            if guard.values[key] ~= nil then
                return guard.values[key]
            end

            local original_index = guard.original_index
            if type(original_index) == 'function' then
                return original_index(tbl, key)
            end
            if type(original_index) == 'table' then
                return original_index[key]
            end
        end
        new_mt.__newindex = function(tbl, key, value)
            if guard.values[key] ~= nil then
                local message = guard.error_messages[key] or
                    string.format('Hook \'%s\' should be registered ' ..
                                  'using %s(<function>)', key, key)
                error(message)
            end
            if guard.original_newindex then
                return guard.original_newindex(tbl, key, value)
            end
            rawset(tbl, key, value)
        end
        setmetatable(object, new_mt)
    end
    guard.values[hooks_type] = accessor
    guard.error_messages[hooks_type] = opts.error_message
end

local function define_hooks(object, hooks_type, preloaded_hook)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    local register_hook = function(...)
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
    set_hook_assignment_guard(object, hooks_type, register_hook)

    local function run_preloaded_hooks()
        if preloaded_hook == nil then
            return
        end

        -- before_* -- direct order
        -- after_* -- reverse order
        local from = 1
        local to = #preloaded_hook
        local step = 1
        if hooks_type:startswith('after_') then
            from, to = to, from
            step = -step
        end

        for i = from, to, step do
            local hook = preloaded_hook[i]
            if check_params(hook[2], object.params) then
                hook[1](object)
            end
        end
    end

    object['run_' .. hooks_type] = function()
        -- before_* -- run before test hooks
        if hooks_type:startswith('before_') then
            run_preloaded_hooks()
        end

        local active_hooks = object[hooks_type .. '_hooks']
        for _, hook in ipairs(active_hooks) do
            if check_params(hook[2], object.params) then
                hook[1](object)
            end
        end
        -- after_* -- run after test hooks
        if hooks_type:startswith('after_') then
            run_preloaded_hooks()
        end
    end
end

local function define_named_hooks(object, hooks_type)
    local hooks = {}
    object[hooks_type .. '_hooks'] = hooks

    local register_hook = function(...)
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

    set_hook_assignment_guard(object, hooks_type, register_hook)

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
function export._define_group_hooks(group)
    define_hooks(group, 'before_each', preloaded_hooks.before_each)
    define_hooks(group, 'after_each',  preloaded_hooks.after_each)
    define_hooks(group, 'before_all',  preloaded_hooks.before_all)
    define_hooks(group, 'after_all',   preloaded_hooks.after_all)

    local setup_error = 'Hook \'setup\' is removed. Use \'before_each\' instead'
    set_hook_assignment_guard(group, 'setup', function()
        error(setup_error)
    end, {error_message = setup_error})

    local teardown_error = 'Hook \'teardown\' is removed. Use \'after_each\' instead'
    set_hook_assignment_guard(group, 'teardown', function()
        error(teardown_error)
    end, {error_message = teardown_error})

    define_named_hooks(group, 'before_test')
    define_named_hooks(group, 'after_test')
    return group
end

-- Define suite hooks on luatest.
function export._define_suite_hooks(luatest)
    define_hooks(luatest, 'before_suite', preloaded_hooks.before_suite)
    define_hooks(luatest, 'after_suite',  preloaded_hooks.after_suite)
end

local function run_group_hooks(runner, group, hooks_type)
    local result
    local hook = group and group['run_' .. hooks_type]
    if hook then
        result = runner:protected_call(group, hook, group.name .. '.run_before_all_hooks')
    end
    if result and result.status ~= 'success' then
        return result
    end
end

local function run_test_hooks(self, test, hooks_type)
    log.info('Run hook %s', hooks_type)
    local group = test.group
    local hook = group['run_' .. hooks_type]
    if hook then
        self:update_status(test, self:protected_call(group, hook))
    end
end

local function run_named_test_hooks(self, test, hooks_type)
    log.info('Run hook %s', hooks_type)
    local group = test.group
    local hook = group['run_' .. hooks_type]
    if hook then
        self:update_status(test, self:protected_call(test, hook))
    end
end

function export._patch_runner(Runner)
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

            run_test_hooks(self, test, 'before_each')
            run_named_test_hooks(self, test, 'before_test')

            if test:is('success') then
                log.info('Start test %s', test.name)
                super(self, test, ...)
                log.info('End test %s', test.name)
            end

            run_named_test_hooks(self, test, 'after_test')
            run_test_hooks(self, test, 'after_each')
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
