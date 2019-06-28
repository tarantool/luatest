local t = require('luatest')
local g = t.group('luaunit')

g.test_assert_aliases = function ()
    t.assert_is(t.assert, t.assert_eval_to_true)
    t.assert_is(t.assert_not, t.assert_eval_to_false)
end
