local json = require('json')

local t = require('luatest')
local g = t.group()

local utils = require('luatest.utils')

g.test_is_tarantool_binary = function()
    local cases = {
        {'/usr/bin/tarantool', true},
        {'/usr/local/bin/tarantool', true},
        {'/usr/local/bin/tt', false},
        {'/usr/bin/ls', false},
        {'/home/myname/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/go-server', false},
        {'/usr/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
        {'/home/tarantool/app/bin/tarantool', true},
        {'/home/tarantool/app/bin/tarantool-ee_gc64-2.11.0-0-r577', true},
    }

    for _, case in ipairs(cases) do
        local path, result = unpack(case)
        t.assert_equals(utils.is_tarantool_binary(path), result,
                        ("Unexpected result for %q"):format(path))
    end
end

g.test_unpack_sparse_array_with_values = function()
    local non_sparse_input = {
        {{1, 2, 3, 4}, nil},
        {{1, 2, 3, 4}, 3},
    }

    -- Test unpack_sparse_array() is unpack() if non-sparse input.
    local non_sparse_cases = {}
    for _, v in ipairs(non_sparse_input) do
        table.insert(non_sparse_cases, {v[1], v[2], {unpack(v[1], v[2])}})
    end

    local sparse_cases = {
        {{1, nil, 3}, nil, {1, nil, 3}},
        {{1, nil, 3}, 2, {nil, 3}},
        {{nil, 2, nil}, nil, {nil, 2}},
        {{nil, 2, nil}, 2, {2}},
        {{nil, 2, box.NULL}, nil, {nil, 2, box.NULL}},
        {{nil, 2, box.NULL}, 3 ,{box.NULL}},
        {{nil, nil, nil, nil, 5}, 4, {nil, 5}},
        {{nil, nil, nil, nil, 5}, 5, {5}},
    }

    local cases = {unpack(non_sparse_cases), unpack(sparse_cases)}

    for _, case in ipairs(cases) do
        local array, index, result_packed = unpack(case)

        local assert_msg
        if index ~= nil then
            assert_msg = ("Unexpected result for unpack_sparse_array(%q, %d)"):format(
                json.encode(array), index)
        else
            assert_msg = ("Unexpected result for unpack_sparse_array(%q)"):format(
                json.encode(array))
        end

        t.assert_equals(
            {utils.unpack_sparse_array(array, index)},
            result_packed,
            assert_msg
        )
    end
end

local function assert_return_no_values(func, ...)
    -- http://lua-users.org/lists/lua-l/2011-09/msg00312.html
    t.assert_error_msg_contains(
        "bad argument #1 to 'assert' (value expected)",
        function(...)
            assert(func(...))
        end,
        ...
    )
end

g.test_unpack_sparse_array_no_values = function()
    local non_sparse_cases = {
        {{1, 2, 3, 4}, 5},
        {{}, 1},
    }

    local sparse_cases = {
        {{1, nil, 3}, 6},
    }

    -- Assert built-in unpack() symmetric behavior.
    for _, case in ipairs(sparse_cases) do
        local array, index = unpack(case)
        assert_return_no_values(unpack, array, index)
    end

    local cases = {unpack(non_sparse_cases), unpack(sparse_cases)}
    for _, case in ipairs(cases) do
        local array, index = unpack(case)
        assert_return_no_values(utils.unpack_sparse_array, array, index)
    end
end
