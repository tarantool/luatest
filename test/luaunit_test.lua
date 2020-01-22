local t = require('luatest')
local g = t.group()

local helper = require('test.helper')
local clock = require('clock')

g.test_pretystr = function()
    local subject = t.prettystr
    t.assert_equals(subject({['a-b'] = 1, ab = 2, [10] = 10}), '{[10] = 10, ["a-b"] = 1, ab = 2}')

    local large_table = {}
    local expected_large_format = {'{'}
    for i = 0, 9 do
        large_table['a' .. i] = i
        table.insert(expected_large_format, string.format('    a%d = %d,', i, i))
    end
    table.insert(expected_large_format, '}')
    t.assert_equals(subject(large_table), table.concat(expected_large_format, '\n'))
end

g.test_pretystr_huge_table = function()
    local str_table = {}
    for _ = 1, 15000 do table.insert(str_table, 'a') end
    local str = table.concat(str_table, '\n')
    local start = clock.time()
    local result = helper.run_suite(function(lu2)
        lu2.group().test = function() t.skip(str) end
    end)
    t.assert_equals(result, 0)
    t.assert_almost_equals(clock.time() - start, 0, 0.5)
end

g.test_custom_errors = function()
    local function assert_no_exception(fn)
        local result = helper.run_suite(function(lu2)
            lu2.group().test = fn
        end)
        t.assert_equals(result, 1)
    end
    assert_no_exception(function() error(123ULL) end)
    assert_no_exception(function() error({a = 1}) end)
end

g.test_assert_eqals_for_cdata = function()
    t.assert_equals(1, 1ULL)
    t.assert_equals(1ULL, 1ULL)
    t.assert_equals(1, 1LL)
    t.assert_equals(1LL, 1ULL)

    helper.assert_failure_contains('expected: 2ULL, actual: 1', t.assert_equals, 1, 2ULL)
    helper.assert_failure_contains('expected: 2LL, actual: 1', t.assert_equals, 1, 2LL)
    helper.assert_failure_contains('expected: 2LL, actual: 1ULL', t.assert_equals, 1ULL, 2LL)
    helper.assert_failure_contains('expected: cdata<void *>: NULL, actual: 1', t.assert_equals, 1, box.NULL)

    t.assert_not_equals(1, 2ULL)
    t.assert_not_equals(1, 2LL)
    t.assert_not_equals(1ULL, 2LL)
    t.assert_not_equals(1ULL, box.NULL)
end

g.test_assert_almost_eqals_for_cdata = function()
    t.assert_almost_equals(1, 2ULL, 1)
    t.assert_almost_equals(1LL, 2, 1)

    helper.assert_failure_contains('Values are not almost equal', t.assert_almost_equals, 1, 3ULL, 1)
    helper.assert_failure_contains('Values are not almost equal', t.assert_almost_equals, 1LL, 3, 1)
    helper.assert_failure_contains('must supply only number arguments', t.assert_almost_equals, box.NULL, 3, 1)

    t.assert_not_almost_equals(1, 3ULL, 1)
    t.assert_not_almost_equals(1LL, 3, 1)
end
