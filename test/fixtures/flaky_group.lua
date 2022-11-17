local t = require('luatest')

local g_flaky = t.group('flaky_group')

local counter_group = 1

g_flaky.test_flaky_group_one = function()
    t.fail_if(counter_group > 3, 'Boo!')
    counter_group = counter_group + 1
end

g_flaky.test_flaky_group_two = function()
    t.fail_if(counter_group > 3, 'Boo!')
    counter_group = counter_group + 1
end
