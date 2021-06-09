local t = require('luatest')

local g_flaky = t.group('flaky')

local counter = 1
g_flaky.test_flaky = function()
    t.fail_if(counter > 1, 'Boo!')
    counter = counter + 1
end
