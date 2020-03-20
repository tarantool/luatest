local t = require('luatest')
local g = t.group('fixtures.pass')

g.test_1 = function()
  t.assert_equals(1, 1)
end
