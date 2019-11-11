local t = require('luatest')
local g = t.group()

g.test_default_group_name = function()
    t.assert_is(t.groups['sub_dir.group'], g)
end
