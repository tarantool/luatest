local t = require('luatest')
local g = t.group()

local helper = require('test.helper')

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

g.test_assert_equals_for_cdata = function()
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

g.test_assert_almost_equals_for_cdata = function()
    t.assert_almost_equals(1, 2ULL, 1)
    t.assert_almost_equals(1LL, 2, 1)

    helper.assert_failure_contains('Values are not almost equal', t.assert_almost_equals, 1, 3ULL, 1)
    helper.assert_failure_contains('Values are not almost equal', t.assert_almost_equals, 1LL, 3, 1)
    helper.assert_failure_contains('must supply only number arguments.\n'..
        'Arguments supplied: cdata<void *>: NULL, 3, 1', t.assert_almost_equals, box.NULL, 3, 1)

    t.assert_not_almost_equals(1, 3ULL, 1)
    t.assert_not_almost_equals(1LL, 3, 1LL)
end

g.test_assert_with_extra_message_not_string = function()
    local raw_msg = 'expected: a value evaluating to true, actual: nil'
    helper.assert_failure_equals('{custom = "error"}\n' .. raw_msg, t.assert, nil, {custom = 'error'})
    helper.assert_failure_equals(raw_msg, t.assert, nil, nil)
    helper.assert_failure_equals(raw_msg, t.assert, nil, box.NULL)
    helper.assert_failure_equals('321\n' .. raw_msg, t.assert, nil, 321)
end

g.test_assert_comparisons_error = function()
    helper.assert_failure_contains('must supply only number arguments.\n'..
    'Arguments supplied: \"one\", 3', t.assert_le, 'one', 3)
    helper.assert_failure_contains('must supply only number arguments.\n'..
    'Arguments supplied: \"one\", 3', t.assert_lt, 'one', 3)
    helper.assert_failure_contains('must supply only number arguments.\n'..
    'Arguments supplied: \"one\", 3', t.assert_ge, 'one', 3)
    helper.assert_failure_contains('must supply only number arguments.\n'..
    'Arguments supplied: \"one\", 3', t.assert_gt, 'one', 3)
end
