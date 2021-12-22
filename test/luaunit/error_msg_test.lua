local t = require('luatest')
local g = t.group()

local helper = require('test.helper')
local assert_failure_matches = helper.assert_failure_matches
local assert_failure_contains = helper.assert_failure_contains
local assert_failure_equals = helper.assert_failure_equals

function g.test_assert_equalsMsg()
    assert_failure_equals('expected: 2, actual: 1', t.assert_equals, 1, 2 )
    assert_failure_equals('expected: "exp"\nactual: "act"', t.assert_equals, 'act', 'exp')
    assert_failure_equals('expected: \n"exp\\\npxe"\nactual: \n"act\\\ntca"', t.assert_equals, 'act\ntca', 'exp\npxe')
    assert_failure_equals('expected: true, actual: false', t.assert_equals, false, true)
    assert_failure_equals('expected: 1.2, actual: 1', t.assert_equals, 1.0, 1.2)
    assert_failure_matches('expected: {1, 2}\nactual: {2, 1}', t.assert_equals, {2,1}, {1,2})
    assert_failure_matches('expected: {one = 1, two = 2}\nactual: {3, 2, 1}', t.assert_equals, {3,2,1}, {one=1,two=2})
    assert_failure_equals('expected: 2, actual: nil', t.assert_equals, nil, 2)
    assert_failure_equals('toto\nexpected: 2, actual: nil', t.assert_equals, nil, 2, 'toto')
end

function g.test_assert_almost_equalsMsg()
    assert_failure_equals('Values are not almost equal\nActual: 2, expected: 1, delta 1 above margin of 0.1',
        t.assert_almost_equals, 2, 1, 0.1)
    assert_failure_equals('toto\nValues are not almost equal\nActual: 2, expected: 1, delta 1 above margin of 0.1',
        t.assert_almost_equals, 2, 1, 0.1, 'toto')
end

function g.test_assert_not_almost_equalsMsg()
    -- single precision math Lua won't output an "exact" delta (0.1) here, so we do a partial match
    assert_failure_contains('Values are almost equal\nActual: 1.1, expected: 1, delta 0.1 below margin of 0.2',
        t.assert_not_almost_equals, 1.1, 1, 0.2)
    assert_failure_contains('toto\nValues are almost equal\nActual: 1.1, expected: 1, delta 0.1 below margin of 0.2',
        t.assert_not_almost_equals, 1.1, 1, 0.2, 'toto')
end

function g.test_assert_not_equalsMsg()
    assert_failure_equals('Actual and expected values are equal: 1', t.assert_not_equals, 1, 1)
    assert_failure_matches('Actual and expected values are equal: {1, 2}', t.assert_not_equals, {1,2}, {1,2})
    assert_failure_equals('Actual and expected values are equal: nil', t.assert_not_equals, nil, nil)
    assert_failure_equals('toto\nActual and expected values are equal: 1', t.assert_not_equals, 1, 1, 'toto')
end

function g.test_assert_not()
    assert_failure_equals('expected: a value evaluating to true, actual: false', t.assert, false)
    assert_failure_equals('expected: a value evaluating to true, actual: nil', t.assert, nil)
    assert_failure_equals('expected: false or nil, actual: true', t.assert_not, true)
    assert_failure_equals('expected: false or nil, actual: 0', t.assert_not, 0)
    assert_failure_matches('expected: false or nil, actual: {}', t.assert_not, {})
    assert_failure_equals('expected: false or nil, actual: "abc"', t.assert_not, 'abc')
    assert_failure_contains('expected: false or nil, actual: function', t.assert_not, function () end)

    assert_failure_equals('toto\nexpected: a value evaluating to true, actual: false', t.assert, false, 'toto')
    assert_failure_equals('toto\nexpected: false or nil, actual: 0', t.assert_not, 0, 'toto')
end

function g.test_assert_eval_to_trueFalse()
    assert_failure_equals('expected: a value evaluating to true, actual: false', t.assert_eval_to_true, false)
    assert_failure_equals('expected: a value evaluating to true, actual: nil', t.assert_eval_to_true, nil)
    assert_failure_equals('expected: false or nil, actual: true', t.assert_eval_to_false, true)
    assert_failure_equals('expected: false or nil, actual: 0', t.assert_eval_to_false, 0)
    assert_failure_matches('expected: false or nil, actual: {}', t.assert_eval_to_false, {})
    assert_failure_equals('expected: false or nil, actual: "abc"', t.assert_eval_to_false, 'abc')
    assert_failure_contains('expected: false or nil, actual: function', t.assert_eval_to_false, function () end)
    assert_failure_equals('toto\nexpected: a value evaluating to true, actual: false',
        t.assert_eval_to_true, false, 'toto')
    assert_failure_equals('toto\nexpected: false or nil, actual: 0', t.assert_eval_to_false, 0, 'toto')
end

function g.test_assert()
    assert_failure_equals('expected: a value evaluating to true, actual: nil', t.assert, nil)
    assert_failure_equals('toto\nexpected: a value evaluating to true, actual: nil', t.assert, nil, 'toto')
end

function g.test_assert_str_contains()
    assert_failure_equals('Could not find substring "xxx" in string "abcdef"', t.assert_str_contains, 'abcdef', 'xxx')
    assert_failure_equals('Could not find substring "aBc" in string "abcdef"', t.assert_str_contains, 'abcdef', 'aBc')
    assert_failure_equals('Could not find substring "xxx" in string ""', t.assert_str_contains, '', 'xxx')

    assert_failure_equals('Could not find substring "xxx" in string "abcdef"',
        t.assert_str_contains, 'abcdef', 'xxx', false)
    assert_failure_equals('Could not find substring "aBc" in string "abcdef"',
        t.assert_str_contains, 'abcdef', 'aBc', false)
    assert_failure_equals('Could not find substring "xxx" in string ""', t.assert_str_contains, '', 'xxx', false)

    assert_failure_equals('Could not find pattern "xxx" in string "abcdef"',
        t.assert_str_contains, 'abcdef', 'xxx', true)
    assert_failure_equals('Could not find pattern "aBc" in string "abcdef"',
        t.assert_str_contains, 'abcdef', 'aBc', true)
    assert_failure_equals('Could not find pattern "xxx" in string ""', t.assert_str_contains, '', 'xxx', true)

    assert_failure_equals('toto\nCould not find pattern "xxx" in string ""',
        t.assert_str_contains, '', 'xxx', true, 'toto')
end

function g.test_assert_str_icontains()
    assert_failure_equals('Could not find (case insensitively) substring "xxx" in string "abcdef"',
        t.assert_str_icontains, 'abcdef', 'xxx')
    assert_failure_equals('Could not find (case insensitively) substring "xxx" in string ""',
        t.assert_str_icontains, '', 'xxx')

    assert_failure_equals('toto\nCould not find (case insensitively) substring "xxx" in string "abcdef"',
        t.assert_str_icontains, 'abcdef', 'xxx', 'toto')
end

function g.test_assert_not_str_contains()
    assert_failure_equals('Found unexpected substring "abc" in string "abcdef"',
        t.assert_not_str_contains, 'abcdef', 'abc')
    assert_failure_equals('Found unexpected substring "abc" in string "abcdef"',
        t.assert_not_str_contains, 'abcdef', 'abc', false)
    assert_failure_equals('Found unexpected pattern "..." in string "abcdef"',
        t.assert_not_str_contains, 'abcdef', '...', true)

    assert_failure_equals('toto\nFound unexpected substring "abc" in string "abcdef"',
        t.assert_not_str_contains, 'abcdef', 'abc', false, 'toto')
end

function g.test_assert_not_str_icontains()
    assert_failure_equals('Found (case insensitively) unexpected substring "aBc" in string "abcdef"',
        t.assert_not_str_icontains, 'abcdef', 'aBc')
    assert_failure_equals('Found (case insensitively) unexpected substring "abc" in string "abcdef"',
        t.assert_not_str_icontains, 'abcdef', 'abc')
    assert_failure_equals('toto\nFound (case insensitively) unexpected substring "abc" in string "abcdef"',
        t.assert_not_str_icontains, 'abcdef', 'abc', 'toto')
end

function g.test_assert_str_matches()
    assert_failure_equals('Could not match pattern "xxx" with string "abcdef"',
        t.assert_str_matches, 'abcdef', 'xxx')
    assert_failure_equals('toto\nCould not match pattern "xxx" with string "abcdef"',
        t.assert_str_matches, 'abcdef', 'xxx', nil, nil, 'toto')
end

function g.test_assert_type()
    assert_failure_equals('expected: a number value, actual: type string, value "abc"',
        t.assert_type, 'abc', 'number')
    assert_failure_equals('expected: a number value, actual: type nil, value nil',
        t.assert_type, nil, 'number')
    assert_failure_equals('toto\nexpected: a number value, actual: type string, value "abc"',
        t.assert_type, 'abc', 'number', 'toto')

    assert_failure_equals('expected: a string value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'string')
    assert_failure_equals('expected: a string value, actual: type nil, value nil',
        t.assert_type, nil, 'string')
    assert_failure_equals('toto\nexpected: a string value, actual: type nil, value nil',
        t.assert_type, nil, 'string', 'toto')

    assert_failure_equals('expected: a table value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'table')
    assert_failure_equals('expected: a table value, actual: type nil, value nil',
        t.assert_type, nil, 'table')
    assert_failure_equals('toto\nexpected: a table value, actual: type nil, value nil',
        t.assert_type, nil, 'table', 'toto')

    assert_failure_equals('expected: a boolean value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'boolean')
    assert_failure_equals('expected: a boolean value, actual: type nil, value nil',
        t.assert_type, nil, 'boolean')
    assert_failure_equals('toto\nexpected: a boolean value, actual: type nil, value nil',
        t.assert_type, nil, 'boolean', 'toto')

    assert_failure_equals('expected: a function value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'function')
    assert_failure_equals('expected: a function value, actual: type nil, value nil',
        t.assert_type, nil, 'function')
    assert_failure_equals('toto\nexpected: a function value, actual: type nil, value nil',
        t.assert_type, nil, 'function', 'toto')

    assert_failure_equals('expected: a thread value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'thread')
    assert_failure_equals('expected: a thread value, actual: type nil, value nil',
        t.assert_type, nil, 'thread')
    assert_failure_equals('toto\nexpected: a thread value, actual: type nil, value nil',
        t.assert_type, nil, 'thread', 'toto')

    assert_failure_equals('expected: a userdata value, actual: type number, value 1.2',
        t.assert_type, 1.2, 'userdata')
    assert_failure_equals('expected: a userdata value, actual: type nil, value nil',
        t.assert_type, nil, 'userdata')
    assert_failure_equals('toto\nexpected: a userdata value, actual: type nil, value nil',
        t.assert_type, nil, 'userdata', 'toto')
end

function g.test_assert_nan()
    assert_failure_equals('expected: NaN, actual: 33', t.assert_nan, 33)
    assert_failure_equals('toto\nexpected: NaN, actual: 33', t.assert_nan, 33, 'toto')
end

function g.test_assert_not_nan()
    assert_failure_equals('expected: not NaN, actual: NaN', t.assert_not_nan, 0 / 0)
    assert_failure_equals('toto\nexpected: not NaN, actual: NaN', t.assert_not_nan, 0 / 0, 'toto')
end

function g.test_assert_inf()
    assert_failure_equals('expected: #Inf, actual: 33', t.assert_inf, 33)
    assert_failure_equals('toto\nexpected: #Inf, actual: 33', t.assert_inf, 33, 'toto')
end

function g.test_assert_plus_inf()
    assert_failure_equals('expected: #Inf, actual: 33', t.assert_plus_inf, 33)
    assert_failure_equals('toto\nexpected: #Inf, actual: 33', t.assert_plus_inf, 33, 'toto')
end

function g.test_assert_minus_inf()
    assert_failure_equals('expected: -#Inf, actual: 33', t.assert_minus_inf, 33)
    assert_failure_equals('toto\nexpected: -#Inf, actual: 33', t.assert_minus_inf, 33, 'toto')
end

function g.test_assert_not_inf()
    assert_failure_equals('expected: not infinity, actual: #Inf', t.assert_not_inf, 1 / 0)
    assert_failure_equals('toto\nexpected: not infinity, actual: -#Inf', t.assert_not_inf, -1 / 0, 'toto')
end

function g.test_assert_not_plus_inf()
    assert_failure_equals('expected: not #Inf, actual: #Inf', t.assert_not_plus_inf, 1 / 0)
    assert_failure_equals('toto\nexpected: not #Inf, actual: #Inf', t.assert_not_plus_inf, 1 / 0, 'toto')
end

function g.test_assert_not_minus_inf()
    assert_failure_equals('expected: not -#Inf, actual: -#Inf',      t.assert_not_minus_inf, -1 / 0)
    assert_failure_equals('toto\nexpected: not -#Inf, actual: -#Inf', t.assert_not_minus_inf, -1 / 0, 'toto')
end

function g.test_assertPlusZero()
    assert_failure_equals('expected: +0.0, actual: 33', t.assert_plus_zero, 33)
    assert_failure_equals('toto\nexpected: +0.0, actual: 33', t.assert_plus_zero, 33, 'toto')
end

function g.test_assertMinusZero()
    assert_failure_equals('expected: -0.0, actual: 33', t.assert_minus_zero, 33)
    assert_failure_equals('toto\nexpected: -0.0, actual: 33', t.assert_minus_zero, 33, 'toto')
end

function g.test_assert_notPlusZero()
    assert_failure_equals('expected: not +0.0, actual: +0.0', t.assert_not_plus_zero, 0)
    assert_failure_equals('toto\nexpected: not +0.0, actual: +0.0', t.assert_not_plus_zero, 0, 'toto')
end

function g.test_assert_notMinusZero()
    local minusZero = -1 / (1/0)
    assert_failure_equals('expected: not -0.0, actual: -0.0', t.assert_not_minus_zero, minusZero)
    assert_failure_equals('toto\nexpected: not -0.0, actual: -0.0', t.assert_not_minus_zero, minusZero, 'toto')
end

function g.test_assert_is()
    assert_failure_equals('expected and actual object should not be different\nExpected: 1\nReceived: 2',
        t.assert_is, 2, 1)
    assert_failure_equals('expected and actual object should not be different\n'..
                            'Expected: {1, 2, 3, 4, 5, 6, 7, 8}\n'..
                            'Received: {1, 2, 3, 4, 5, 6, 7, 8}',
        t.assert_is, {1,2,3,4,5,6,7,8}, {1,2,3,4,5,6,7,8})
end

function g.test_assert_is_not()
    local v = {1,2}
    assert_failure_matches('expected and actual object should be different: {1, 2}', t.assert_is_not, v, v)
end

function g.test_assert_items_equals()
    assert_failure_matches([[Item values of the tables are not identical
Expected table: {one = 2, two = 3}
Actual table: {1, 2}]], t.assert_items_equals, {1,2}, {one=2, two=3})
    -- actual table empty, = doesn't contain expected value
    assert_failure_contains('Item values of the tables are not identical' , t.assert_items_equals, {}, {1})
    -- type mismatch
    assert_failure_contains('Item values of the tables are not identical' , t.assert_items_equals, nil, 'foobar')
    -- value mismatch
    assert_failure_contains('Item values of the tables are not identical' , t.assert_items_equals, 'foo', 'bar')
    -- value mismatch
    assert_failure_contains('toto\nItem values of the tables are not identical',
        t.assert_items_equals, 'foo', 'bar', 'toto')
end

function g.test_assert_error()
    assert_failure_equals('Expected an error when calling function but no error generated',
        t.assert_error, function(v) return v+1 end, 3)
end

function g.test_assert_error_msg_equals()
    assert_failure_equals('Function successfully returned: nil\nExpected error: "bla bla bla"' ,
        t.assert_error_msg_equals, 'bla bla bla', function() end)
    assert_failure_equals('Function successfully returned: 4\nExpected error: "bla bla bla"' ,
        t.assert_error_msg_equals, 'bla bla bla', function(v) return v+1 end, 3)
    assert_failure_equals('Function successfully returned: {4, 5, 6}\nExpected error: "bla bla bla"' ,
        t.assert_error_msg_equals, 'bla bla bla', function(v) return {v+1, v+2, v+3} end, 3)
    assert_failure_equals('Error message expected: "bla bla bla"\n' ..
                        'Error message received: "toto xxx"\n' ,
        t.assert_error_msg_equals, 'bla bla bla', function() error('toto xxx',2) end, 3)
    assert_failure_equals('Error message expected: {1, 2, 3, 4}\nError message received: {1, 2, 3}\n' ,
        t.assert_error_msg_equals, {1,2,3,4}, function(v) error(v) end, {1,2,3})
    assert_failure_equals([[Error message expected: {details = "bla bla bla"}
Error message received: {details = "ble ble ble"}
]] ,
        t.assert_error_msg_equals, {details="bla bla bla"}, function(v) error(v) end, {details="ble ble ble"})
end

function g.test_assert_errorMsgContains()
    assert_failure_equals('Function successfully returned: nil\nExpected error containing: "bla bla bla"' ,
        t.assert_error_msg_contains, 'bla bla bla', function() end)
    assert_failure_equals('Function successfully returned: 4\nExpected error containing: "bla bla bla"' ,
        t.assert_error_msg_contains, 'bla bla bla', function(v) return v+1 end, 3)
    assert_failure_equals('Function successfully returned: {4, 5, 6}\nExpected error containing: "bla bla bla"' ,
        t.assert_error_msg_contains, 'bla bla bla', function(v) return {v+1, v+2, v+3} end, 3)
    assert_failure_equals('Error message does not contain: "bla bla bla"\nError message received: "toto xxx"\n' ,
        t.assert_error_msg_contains, 'bla bla bla', function() error('toto xxx',2) end, 3)
end

function g.test_assert_errorMsgMatches()
    assert_failure_equals('Function successfully returned: nil\nExpected error matching: "bla bla bla"' ,
        t.assert_error_msg_matches, 'bla bla bla', function() end)
    assert_failure_equals('Function successfully returned: 4\nExpected error matching: "bla bla bla"' ,
        t.assert_error_msg_matches, 'bla bla bla', function(v) return v+1 end, 3)
    assert_failure_equals('Function successfully returned: {4, 5, 6}\nExpected error matching: "bla bla bla"' ,
        t.assert_error_msg_matches, 'bla bla bla', function(v) return {v+1, v+2, v+3} end, 3)
    assert_failure_equals('Error message does not match pattern: "bla bla bla"\n' ..
                        'Error message received: "toto xxx"\n' ,
        t.assert_error_msg_matches, 'bla bla bla', function() error('toto xxx',2) end, 3)
end

function g.test_assert_errorMsgContentEquals()
    local f = function() error("This is error message") end
    t.assert_error_msg_content_equals("This is error message", f)
    t.assert_error_msg_content_equals("This is error message", f, 1, 2)
end

local pp = require('luatest.pp')

function g.test_printTableWithRef()
    pp.TABLE_REF_IN_ERROR_MSG = true
    assert_failure_matches('Actual and expected values are equal: <table: 0?x?[%x]+> {1, 2}',
        t.assert_not_equals, {1,2}, {1,2})
    -- trigger multiline prettystr
    assert_failure_matches('Actual and expected values are equal: <table: 0?x?[%x]+> {1, 2, 3, 4}',
        t.assert_not_equals, {1,2,3,4}, {1,2,3,4})
    assert_failure_matches('expected: false or nil, actual: <table: 0?x?[%x]+> {}', t.assert_not, {})
    local v = {1,2}
    assert_failure_matches('expected and actual object should be different: <table: 0?x?[%x]+> {1, 2}',
        t.assert_is_not, v, v)
    assert_failure_matches([[Item values of the tables are not identical
Expected table: <table: 0?x?[%x]+> {one = 2, two = 3}
Actual table: <table: 0?x?[%x]+> {1, 2}]], t.assert_items_equals, {1,2}, {one=2, two=3})
    assert_failure_matches([[expected: <table: 0?x?[%x]+> {1, 2}
actual: <table: 0?x?[%x]+> {2, 1}]], t.assert_equals, {2,1}, {1,2})
    -- trigger multiline prettystr
    assert_failure_matches([[expected: <table: 0?x?[%x]+> {one = 1, two = 2}
actual: <table: 0?x?[%x]+> {3, 2, 1}]], t.assert_equals, {3,2,1}, {one=1,two=2})
    -- trigger mismatch formatting
    assert_failure_contains([[lists <table: ]] , t.assert_equals, {3,2,1,4,1,1,1,1,1,1,1}, {1,2,3,4,1,1,1,1,1,1,1})
    assert_failure_contains([[and <table: ]] , t.assert_equals, {3,2,1,4,1,1,1,1,1,1,1}, {1,2,3,4,1,1,1,1,1,1,1})
    pp.TABLE_REF_IN_ERROR_MSG = false
end
