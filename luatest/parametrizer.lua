local checks = require('checks')

local Group = require('luatest.group')
local pp = require('luatest.pp')

local export = {}

local function get_group_name(params)
    local params_names = {}
    for name, _ in pairs(params) do
        table.insert(params_names, name)
    end
    table.sort(params_names)

    for ind, param_name in ipairs(params_names) do
        params_names[ind] = param_name .. ':' .. pp.tostring(params[param_name])
    end
    return table.concat(params_names, ".")
end

local function redefine_hooks(group, hooks_type)
    -- Super group shares its hooks with pgroups
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
    local super_group_mt = getmetatable(group)
    if super_group_mt.__newindex then
        return
    end

    super_group_mt.__newindex = function(_group, key, value)
        if _group.pgroups then
            for _, pgroup in ipairs(_group.pgroups) do
                pgroup[key] = value
            end
        else
            rawset(_group, key, value)
        end
    end
end

function export.parametrize(object, parameters_combinations)
    checks('table', 'table')
    -- Validate params' name and values
    local counter = 0
    for _, _ in pairs(parameters_combinations) do
        counter = counter + 1
        assert(parameters_combinations[counter] ~= nil,
            'parameters_combinations should be a contiguous array')

        assert(type(parameters_combinations[counter]) == 'table',
            string.format('parameters_combinations\' entry should be table, got %s',
                type(parameters_combinations[counter])))

        for parameter_name, _ in pairs(parameters_combinations[counter]) do
            assert(type(parameter_name) == 'string',
                string.format('parameter name should be string, got %s', type(parameter_name)))
        end
    end

    -- Create a subgroup on every param combination
    object.pgroups = {}
    for _, pgroup_params in ipairs(parameters_combinations) do
        local pgroup_name = get_group_name(pgroup_params)
        local pgroup = Group:new(object.name .. '.' .. pgroup_name)
        pgroup.params = pgroup_params

        pgroup.super_group = object
        table.insert(object.pgroups, pgroup)
    end

    redirect_index(object)
    redefine_pgroups_hooks(object)
end

return export
