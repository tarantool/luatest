local t = require('luatest')
local g = t.group()

local helpers = t.helpers

g.test_uuid = function()
    t.assert_equals(helpers.uuid('a'), 'aaaaaaaa-0000-0000-0000-000000000000')
    t.assert_equals(helpers.uuid('ab', 1), 'abababab-0000-0000-0000-000000000001')
    t.assert_equals(helpers.uuid(1, 2, 3), '00000001-0002-0000-0000-000000000003')
    t.assert_equals(helpers.uuid('1', '2', '3'), '11111111-2222-0000-0000-333333333333')
    t.assert_equals(helpers.uuid('12', '34', '56', '78', '90'), '12121212-3434-5656-7878-909090909090')
end

g.test_rescuing = function()
    local retry = 0
    local result = helpers.retrying({}, function(a, b)
        t.assert_equals(a, 1)
        t.assert_equals(b, 2)
        retry = retry + 1
        if (retry < 3) then
            error('test')
        end
        return 'result'
    end, 1, 2)
    t.assert_equals(retry, 3)
    t.assert_equals(result, result)
end

g.test_rescuing_failure = function()
    local retry = 0
    t.assert_error_msg_equals('test-error', function()
        helpers.retrying({delay = 0.1, timeout = 0.5}, function(a, b)
            t.assert_equals(a, 1)
            t.assert_equals(b, 2)
            retry = retry + 1
            error('test-error', 0)
        end, 1, 2)
    end)
    t.assert_almost_equals(retry, 6, 1)
end

g.test_matrix = function()
    t.assert_equals(t.helpers.matrix({}), {{}})
    t.assert_equals(t.helpers.matrix({a = {1}}), {{a = 1}})
    t.assert_equals(t.helpers.matrix({a = {1, 2}}), {{a = 1}, {a = 2}})
    t.assert_equals(t.helpers.matrix({a = {1}, b = {2}}), {{a = 1, b = 2}})

    t.assert_equals(t.helpers.matrix({a = {1, 3}, b = {{2}, {4}}}), {
        {a = 1, b = {2}},
        {a = 3, b = {2}},
        {a = 1, b = {4}},
        {a = 3, b = {4}},
    })

    t.assert_equals(t.helpers.matrix({a = {1, 3}, b = {2, 4}, c = {5, 6}}), {
        {a = 1, b = 2, c = 5},
        {a = 3, b = 2, c = 5},
        {a = 1, b = 4, c = 5},
        {a = 3, b = 4, c = 5},
        {a = 1, b = 2, c = 6},
        {a = 3, b = 2, c = 6},
        {a = 1, b = 4, c = 6},
        {a = 3, b = 4, c = 6},
    })

    t.assert_equals(t.helpers.matrix({{1, 3}, {2, 4}}), {
        {1, 2},
        {3, 2},
        {1, 4},
        {3, 4},
    })
end
