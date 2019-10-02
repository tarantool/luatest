local t = require('luatest')
local g = t.group('asserts')

g.test_assert_table_has_key = function()
	t.assert_table_has_key({ a = 'b' }, 'a')

	local ok, err = pcall(t.assert_table_has_key, { 'a', 'b', 'c' }, 2)
	t.assert_eval_to_false(ok)
	t.assert_str_contains(err, 'expected: a string value, actual: type number')

	ok, err = pcall(t.assert_table_has_key, { 'a', 'b', 'c' }, 'd')
	t.assert_eval_to_false(ok)
	t.assert_str_contains(err, 'expected {"a", "b", "c"} to have key "d"')
end

g.test_assert_table_has_keys = function()
	local value = { foo = 'bar', bar = 'buzz' }
	t.assert_table_has_keys(value, 'foo', 'bar')

	local ok, err = pcall(t.assert_table_has_keys, value, 'buzz')
	t.assert_eval_to_false(ok)
	t.assert_str_contains(err, 'expected {bar="buzz", foo="bar"} to have key "buzz"')
end

g.test_assert_table_has_pair = function()
	local value = { foo = 'bar', bar = 'buzz' }
	t.assert_table_has_pair(value, 'bar', 'buzz')

	local ok, err = pcall(t.assert_table_has_pair, value, 'foo', 'buzz')
	t.assert_eval_to_false(ok)
	t.assert_str_contains(err,
		'expected {bar="buzz", foo="bar"} to have key-value pair {foo="buzz"}')
end

g.test_assert_table_to_include = function()
	local value = { foo = 'bar', bar = 'buzz' }
	t.assert_table_to_include(value, { foo = 'bar' })
	t.assert_table_to_include(value, { foo = 'bar', bar = 'buzz' })

	local ok, err = pcall(t.assert_table_to_include,
		value, { foo = 'bar', bar = 'buzz', buzz = 'foo' })
	t.assert_eval_to_false(ok)
	t.assert_str_contains(err,
		'expected {bar="buzz", foo="bar"} to have key-value pair {buzz="foo"}')
end
