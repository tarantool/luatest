local t = require('luatest')
local g1 = t.group('first_group')
local g2 = t.group('second_group')

function g1.test_make_mock()
    package.loaded.math.pi = 3
    t.assert_not_almost_equals(package.loaded.math.pi, 3.14, 0.01)

    package.loaded.new_package = 'sup'
end

function g2.test_check_mock()
    t.assert_almost_equals(package.loaded.math.pi, 3.14, 0.01)
    t.assert_equals(package.loaded.new_package, nil)
end

