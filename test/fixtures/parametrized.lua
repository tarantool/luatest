local t = require('luatest')
local g = t.group('parametrized_fixture', t.helpers.matrix{a = {1, 2, 3}, b = {4, 5, 6}})

g.test_something = function(cg)
    t.assert_not_equals(cg.params.a, 3)
end
