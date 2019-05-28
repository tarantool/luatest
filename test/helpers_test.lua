local lt = require('luatest')
local t = lt.group('helpers')

local helpers = lt.helpers

t.test_uuid = function()
    lt.assertEquals(helpers.uuid('a'), 'aaaaaaaa-0000-0000-0000-000000000000')
    lt.assertEquals(helpers.uuid('ab', 1), 'abababab-0000-0000-0000-000000000001')
    lt.assertEquals(helpers.uuid(1, 2, 3), '00000001-0002-0000-0000-000000000003')
    lt.assertEquals(helpers.uuid('1', '2', '3'), '11111111-2222-0000-0000-333333333333')
    lt.assertEquals(helpers.uuid('12', '34', '56', '78', '90'), '12121212-3434-5656-7878-909090909090')
end

t.test_rescuing = function()
    local retry = 0
    local result = helpers.retrying({}, function(a, b)
        lt.assertEquals(a, 1)
        lt.assertEquals(b, 2)
        retry = retry + 1
        if (retry < 3) then
            error('test')
        end
        return 'result'
    end, 1, 2)
    lt.assertEquals(retry, 3)
    lt.assertEquals(result, result)
end

t.test_rescuing_failure = function()
    local retry = 0
    lt.assertErrorMsgContains('test-error', function()
        helpers.retrying({delay = 0.1, timeout = 0.5}, function(a, b)
            lt.assertEquals(a, 1)
            lt.assertEquals(b, 2)
            retry = retry + 1
            error('test-error')
        end, 1, 2)
    end)
    lt.assertAlmostEquals(retry, 6, 1)
end
