local t = require('luatest')
local g = t.group('fixtures.fail')

g.test_1 = function()
  t.assert_equals(1, 1)
end

g.test_2 = function()
  t.assert_equals(1, 0)
end
