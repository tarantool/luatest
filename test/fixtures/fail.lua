local t = require('luatest')
local g = t.group('pass')

g.test_1 = function()
  t.assertEquals(1, 1)
end

g.test_2 = function()
  t.assertEquals(1, 0)
end
