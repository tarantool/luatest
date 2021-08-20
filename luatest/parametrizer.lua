local utils = require('luatest.utils')

local Group = require('luatest.group')

local export = {}

local function params_combinations(params)
    local combinations = {}

    local params_names = {}
    for name, _ in pairs(params) do
        table.insert(params_names, name)
    end
    table.sort(params_names)

    local function combinator(params, ind, ...)
        if ind < 1 then
            local combination = {}
            for _, entry in ipairs({...}) do
                combination[entry[1]] = entry[2]
            end
            table.insert(combinations, combination)
        else
            local name = params_names[ind]
            for i=1,#(params[name]) do combinator(params, ind - 1, {name, params[name][i]}, ...) end
        end
    end

    combinator(params, #params_names)
    return combinations
end

local function get_group_name(params)
    local params_names = {}
    for name, _ in pairs(params) do
        table.insert(params_names, name)
    end
    table.sort(params_names)

    for ind, param_name in ipairs(params_names) do
        params_names[ind] = param_name .. '_' .. params[param_name]
    end
    return table.concat(params_names, ".")
end

local function redefine_hooks(group, hooks_type)
    for _, pgroup in ipairs(group.pgroups) do
        pgroup[hooks_type .. '_hooks'] = group[hooks_type .. '_hooks']
    end
end

local function redefine_pgroups_hooks(group)
    redefine_hooks(group, 'before_each')
    redefine_hooks(group, 'after_each')
    redefine_hooks(group, 'before_all')
    redefine_hooks(group, 'after_all')

    redefine_hooks(group, 'before_test')
    redefine_hooks(group, 'after_test')
end

local function redirect_index(group)
    local super_group_mt = table.deepcopy(getmetatable(group))
    super_group_mt.__newindex = function(group, key, value)
        for _, pgroup in ipairs(group.pgroups) do
            pgroup[key] = value
        end
    end
    setmetatable(group, super_group_mt)
end

function export.parametrize(object, params)
    checks('table', 'table')
    -- Validate params' name and values
    for parameter_name, parameter_values in pairs(params) do
        assert(type(parameter_name) == 'string',
            string.format('Parameter name should be string, got %s', type(parameter_name)))
        assert(type(parameter_values) == 'table',
            string.format('Parameter values should be table, got %s', type(parameter_values)))
    end
    object.params = params

    object.pgroups = {}
    local params_combinations = params_combinations(object.params)
    for _, pgroup_params in ipairs(params_combinations) do
        local pgroup_name = get_group_name(pgroup_params)
        local pgroup = Group:new(object.name .. '.' .. pgroup_name)
        pgroup.params = pgroup_params

        pgroup.super_group = object
        -- for easy access
        object[pgroup_name] = pgroup
        -- for simple iteration
        table.insert(object.pgroups, pgroup)
    end

    redirect_index(object)
    redefine_pgroups_hooks(object)
end

return export
