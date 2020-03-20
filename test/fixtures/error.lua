local t = require('luatest')
local g = t.group('fixtures.error')

g.test_1 = function()
  t.assert_equals(1, 1)
end

g.test_2 = function()
  error('custom-error')
end
