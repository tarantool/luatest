local t = require('luatest')
local g = t.group()

local helper = require('test.helper')
local assert_failure = helper.assert_failure
local assert_failure_contains = helper.assert_failure_contains

function g.test_assert_equals()
    local f = function() return true end

    t.assert_equals(1, 1)
    t.assert_equals("abc", "abc")
    t.assert_equals(nil, nil)
    t.assert_equals(true, true)
    t.assert_equals(f, f)
    t.assert_equals({1,2,3}, {1,2,3})
    t.assert_equals({one=1,two=2,three=3}, {one=1,two=2,three=3})
    t.assert_equals({one=1,two=2,three=3}, {two=2,three=3,one=1})
    t.assert_equals({one=1,two={1,2},three=3}, {two={1,2},three=3,one=1})
    t.assert_equals({one=1,two={1,{2,nil}},three=3}, {two={1,{2,nil}},three=3,one=1})
    t.assert_equals({nil}, {nil})
    t.assert_equals({[{}] = 1}, {[{}] = 1})
    t.assert_equals({[{one=1, two=2}] = 1}, {[{two=2, one=1}] = 1})
    t.assert_equals({[{1}]=2, [{1}]=3}, {[{1}]=3, [{1}]=2})
    -- try the other order as well, in case pairs() returns items reversed in the test above
    t.assert_equals({[{1}]=2, [{1}]=3}, {[{1}]=2, [{1}]=3})

    -- check assertions for which # operator returns two different length depending
    -- on how the table is built, eventhough the final table is the same
    t.assert_equals({1, nil, 3}, {1, [3]=3})

    assert_failure(t.assert_equals, 1, 2)
    assert_failure(t.assert_equals, 1, "abc")
    assert_failure(t.assert_equals, 0, nil)
    assert_failure(t.assert_equals, false, nil)
    assert_failure(t.assert_equals, true, 1)
    assert_failure(t.assert_equals, f, 1)
    assert_failure(t.assert_equals, f, function() return true end)
    assert_failure(t.assert_equals, {1,2,3}, {2,1,3})
    assert_failure(t.assert_equals, {1,2,3}, nil)
    assert_failure(t.assert_equals, {1,2,3}, 1)
    assert_failure(t.assert_equals, {1,2,3}, true)
    assert_failure(t.assert_equals, {1,2,3}, {one=1,two=2,three=3})
    assert_failure(t.assert_equals, {1,2,3}, {one=1,two=2,three=3,four=4})
    assert_failure(t.assert_equals, {one=1,two=2,three=3}, {2,1,3})
    assert_failure(t.assert_equals, {one=1,two=2,three=3}, nil)
    assert_failure(t.assert_equals, {one=1,two=2,three=3}, 1)
    assert_failure(t.assert_equals, {one=1,two=2,three=3}, true)
    assert_failure(t.assert_equals, {one=1,two=2,three=3}, {1,2,3})
    assert_failure(t.assert_equals, {one=1,two={1,2},three=3}, {two={2,1},three=3,one=1})
    assert_failure(t.assert_equals, {[{}] = 1}, {[{}] = 2})
    assert_failure(t.assert_equals, {[{}] = 1}, {[{one=1}] = 2})
    assert_failure(t.assert_equals, {[{}] = 1}, {[{}] = 1, 2})
    assert_failure(t.assert_equals, {[{}] = 1}, {[{}] = 1, [{}] = 1})
    assert_failure(t.assert_equals, {[{"one"}]=1}, {[{"one", 1}]=2})
    assert_failure(t.assert_equals, {[{"one"}]=1,[{"one"}]=1}, {[{"one"}]=1})
end

function g.test_assert_almost_equals()
    t.assert_almost_equals(1, 1, 0.1)
    t.assert_almost_equals(1, 1) -- default margin (= M.EPS)
    t.assert_almost_equals(1, 1, 0) -- zero margin
    assert_failure(t.assert_almost_equals, 0, t.EPS, 0) -- zero margin

    t.assert_almost_equals(1, 1.1, 0.2)
    t.assert_almost_equals(-1, -1.1, 0.2)
    t.assert_almost_equals(0.1, -0.1, 0.3)
    t.assert_almost_equals(0.1, -0.1, 0.2)

    -- Due to rounding errors, these user-supplied margins are too small.
    -- The tests should respect them, and so are required to fail.
    assert_failure(t.assert_almost_equals, 1, 1.1, 0.1)
    assert_failure(t.assert_almost_equals, -1, -1.1, 0.1)
    -- Check that an explicit zero margin gets respected too
    assert_failure(t.assert_almost_equals, 1.1 - 1, 0.1, 0)
    assert_failure(t.assert_almost_equals, -1 - (-1.1), 0.1, 0)
    -- Tests pass when adding M.EPS, either explicitly or implicitly
    t.assert_almost_equals(1, 1.1, 0.1 + t.EPS)
    t.assert_almost_equals(1.1 - 1, 0.1)
    t.assert_almost_equals(-1, -1.1, 0.1 + t.EPS)
    t.assert_almost_equals(-1 - (-1.1), 0.1)

    assert_failure(t.assert_almost_equals, 1, 1.11, 0.1)
    assert_failure(t.assert_almost_equals, -1, -1.11, 0.1)
    assert_failure_contains("must supply only number arguments", t.assert_almost_equals, -1, 1, "foobar")
    assert_failure_contains("must supply only number arguments", t.assert_almost_equals, -1, nil, 0)
    assert_failure_contains("must supply only number arguments", t.assert_almost_equals, nil, 1, 0)
    assert_failure_contains("margin must not be negative", t.assert_almost_equals, 1, 1.1, -0.1)
end

function g.test_assert_not_equals()
    local f = function() return true end

    t.assert_not_equals(1, 2)
    t.assert_not_equals("abc", 2)
    t.assert_not_equals("abc", "def")
    t.assert_not_equals(1, 2)
    t.assert_not_equals(1, "abc")
    t.assert_not_equals(0, nil)
    t.assert_not_equals(false, nil)
    t.assert_not_equals(true, 1)
    t.assert_not_equals(f, 1)
    t.assert_not_equals(f, function() return true end)
    t.assert_not_equals({one=1,two=2,three=3}, true)
    t.assert_not_equals({one=1,two={1,2},three=3}, {two={2,1},three=3,one=1})

    assert_failure(t.assert_not_equals, 1, 1)
    assert_failure(t.assert_not_equals, "abc", "abc")
    assert_failure(t.assert_not_equals, nil, nil)
    assert_failure(t.assert_not_equals, true, true)
    assert_failure(t.assert_not_equals, f, f)
    assert_failure(t.assert_not_equals, {one=1,two={1,{2,nil}},three=3}, {two={1,{2,nil}},three=3,one=1})
end

function g.test_assert_not_almost_equals()
    t.assert_not_almost_equals(1, 1.2, 0.1)
    t.assert_not_almost_equals(1, 1.01) -- default margin (= M.EPS)
    t.assert_not_almost_equals(1, 1.01, 0) -- zero margin
    t.assert_not_almost_equals(0, t.EPS, 0) -- zero margin

    t.assert_not_almost_equals(1, 1.3, 0.2)
    t.assert_not_almost_equals(-1, -1.3, 0.2)
    t.assert_not_almost_equals(0.1, -0.1, 0.1)

    t.assert_not_almost_equals(1, 1.1, 0.09)
    t.assert_not_almost_equals(-1, -1.1, 0.09)
    t.assert_not_almost_equals(0.1, -0.1, 0.11)

    -- Due to rounding errors, these user-supplied margins are too small.
    -- The tests should respect them, and so are expected to pass.
    t.assert_not_almost_equals(1, 1.1, 0.1)
    t.assert_not_almost_equals(-1, -1.1, 0.1)
    -- Check that an explicit zero margin gets respected too
    t.assert_not_almost_equals(1.1 - 1, 0.1, 0)
    t.assert_not_almost_equals(-1 - (-1.1), 0.1, 0)
    -- Tests fail when adding M.EPS, either explicitly or implicitly
    assert_failure(t.assert_not_almost_equals, 1, 1.1, 0.1 + t.EPS)
    assert_failure(t.assert_not_almost_equals, 1.1 - 1, 0.1)
    assert_failure(t.assert_not_almost_equals, -1, -1.1, 0.1 + t.EPS)
    assert_failure(t.assert_not_almost_equals, -1 - (-1.1), 0.1)

    assert_failure(t.assert_not_almost_equals, 1, 1.11, 0.2)
    assert_failure(t.assert_not_almost_equals, -1, -1.11, 0.2)
    assert_failure_contains("must supply only number arguments", t.assert_not_almost_equals, -1, 1, "foobar")
    assert_failure_contains("must supply only number arguments", t.assert_not_almost_equals, -1, nil, 0)
    assert_failure_contains("must supply only number arguments", t.assert_not_almost_equals, nil, 1, 0)
    assert_failure_contains("margin must not be negative", t.assert_not_almost_equals, 1, 1.1, -0.1)
end

function g.test_assert_not_equalsDifferentTypes2()
    t.assert_not_equals(2, "abc")
end

function g.test_assert()
    t.assert(true)
    assert_failure(t.assert, false)
    assert_failure(t.assert, nil)
    t.assert(0)
    t.assert(1)
    t.assert("")
    t.assert("abc")
    t.assert(function() return true end)
    t.assert({})
    t.assert({1})
end

function g.test_assert_not()
    t.assert_not(false)
    t.assert_not(nil)
    assert_failure(t.assert_not, true)
    assert_failure(t.assert_not, 0)
    assert_failure(t.assert_not, 1)
    assert_failure(t.assert_not, "")
    assert_failure(t.assert_not, "abc")
    assert_failure(t.assert_not, function() return true end)
    assert_failure(t.assert_not, {})
    assert_failure(t.assert_not, {1})
end

function g.test_assert()
    assert_failure(t.assert, nil)
    assert_failure(t.assert, false)
    t.assert(0)
    t.assert("")
    t.assert("abc")
    t.assert(function() return true end)
    t.assert({})
    t.assert({1})
end

function g.test_assert_str_contains()
    t.assert_str_contains('abcdef', 'abc')
    t.assert_str_contains('abcdef', 'bcd')
    t.assert_str_contains('abcdef', 'abcdef')
    assert_failure(t.assert_str_contains, 'abc0', 0)
    assert_failure(t.assert_str_contains, 'ABCDEF', 'abc')
    assert_failure(t.assert_str_contains, '', 'abc')
    t.assert_str_contains('abcdef', '')
    assert_failure(t.assert_str_contains, 'abcdef', 'abcx')
    assert_failure(t.assert_str_contains, 'abcdef', 'abcdefg')
    assert_failure(t.assert_str_contains, 'abcdef', 0)
    assert_failure(t.assert_str_contains, 'abcdef', {})
    assert_failure(t.assert_str_contains, 'abcdef', nil)

    t.assert_str_contains('abcdef', 'abc', false)
    t.assert_str_contains('abcdef', 'abc', true)
    t.assert_str_contains('abcdef', 'a.c', true)

    assert_failure(t.assert_str_contains, 'abcdef', '.abc', true)
end

function g.test_assert_str_icontains()
    t.assert_str_icontains('ABcdEF', 'aBc')
    t.assert_str_icontains('abCDef', 'bcd')
    t.assert_str_icontains('abcdef', 'abcDef')
    assert_failure(t.assert_str_icontains, '', 'aBc')
    t.assert_str_icontains('abcDef', '')
    assert_failure(t.assert_str_icontains, 'abcdef', 'abcx')
    assert_failure(t.assert_str_icontains, 'abcdef', 'abcdefg')
    assert_failure(t.assert_str_icontains, nil, 'abcdef')
    assert_failure(t.assert_str_icontains, 'abcdef', {})
    assert_failure(t.assert_str_icontains, 'abc0', 0)
end

function g.test_assert_not_str_contains()
    assert_failure(t.assert_not_str_contains, 'abcdef', 'abc')
    assert_failure(t.assert_not_str_contains, 'abcdef', 'bcd')
    assert_failure(t.assert_not_str_contains, 'abcdef', 'abcdef')
    t.assert_not_str_contains('', 'abc')
    assert_failure(t.assert_not_str_contains, 'abcdef', '')
    assert_failure(t.assert_not_str_contains, 'abc0', 0)
    t.assert_not_str_contains('abcdef', 'abcx')
    t.assert_not_str_contains('abcdef', 'abcdefg')
    assert_failure(t.assert_not_str_contains, 'abcdef', {})
    assert_failure(t.assert_not_str_contains, 'abcdef', nil)

    assert_failure(t.assert_not_str_contains, 'abcdef', 'abc', false)
    assert_failure(t.assert_not_str_contains, 'abcdef', 'a.c', true)
    t.assert_not_str_contains('abcdef', 'a.cx', true)
end

function g.test_assert_not_str_icontains()
    assert_failure(t.assert_not_str_icontains, 'aBcdef', 'abc')
    assert_failure(t.assert_not_str_icontains, 'abcdef', 'aBc')
    assert_failure(t.assert_not_str_icontains, 'abcdef', 'bcd')
    assert_failure(t.assert_not_str_icontains, 'abcdef', 'abcdef')
    t.assert_not_str_icontains('', 'abc')
    assert_failure(t.assert_not_str_icontains, 'abcdef', '')
    assert_failure(t.assert_not_str_icontains, 'abc0', 0)
    t.assert_not_str_icontains('abcdef', 'abcx')
    t.assert_not_str_icontains('abcdef', 'abcdefg')
    assert_failure(t.assert_not_str_icontains, 'abcdef', {})
    assert_failure(t.assert_not_str_icontains, 'abcdef', nil)
end

function g.test_assert_str_matches()
    t.assert_str_matches('abcdef', 'abcdef')
    t.assert_str_matches('abcdef', '..cde.')
    assert_failure(t.assert_str_matches, 'abcdef', '..def')
    assert_failure(t.assert_str_matches, 'abCDEf', '..cde.')
    t.assert_str_matches('abcdef', 'bcdef', 2)
    t.assert_str_matches('abcdef', 'bcde', 2, 5)
    t.assert_str_matches('abcdef', 'b..e', 2, 5)
    t.assert_str_matches('abcdef', 'ab..e', nil, 5)
    assert_failure(t.assert_str_matches, 'abcdef', '')
    assert_failure(t.assert_str_matches, '', 'abcdef')

    assert_failure(t.assert_str_matches, nil, 'abcdef')
    assert_failure(t.assert_str_matches, 'abcdef', 0)
    assert_failure(t.assert_str_matches, 'abcdef', {})
    assert_failure(t.assert_str_matches, 'abcdef', nil)
end

function g.test_assert_items_equals()
    t.assert_items_equals({},{})
    t.assert_items_equals({1,2,3}, {3,1,2})
    t.assert_items_equals({nil},{nil})
    t.assert_items_equals({one=1,two=2,three=3}, {two=2,one=1,three=3})
    t.assert_items_equals({one=1,two=2,three=3}, {a=1,b=2,c=3})
    t.assert_items_equals({1,2,three=3}, {3,1,two=2})

    assert_failure(t.assert_items_equals, {1}, {})
    assert_failure(t.assert_items_equals, nil, {1,2,3})
    assert_failure(t.assert_items_equals, {1,2,3}, nil)
    assert_failure(t.assert_items_equals, {1,2,3,4}, {3,1,2})
    assert_failure(t.assert_items_equals, {1,2,3}, {3,1,2,4})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3,four=4}, {a=1,b=2,c=3})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {a=1,b=2,c=3,d=4})
    assert_failure(t.assert_items_equals, {1,2,three=3}, {3,4,a=1,b=2})
    assert_failure(t.assert_items_equals, {1,2,three=3,four=4}, {3,a=1,b=2})

    assert_failure(t.assert_items_equals, {1,1,2,3}, {1,2,3})
    assert_failure(t.assert_items_equals, {1,2,3}, {1,1,2,3})
    assert_failure(t.assert_items_equals, {1,1,2,3}, {1,2,3,3})

    t.assert_items_equals({one=1,two={1,2},three=3}, {one={1,2},two=1,three=3})
    t.assert_items_equals({one=1,
                       two={1,{3,2,one=1}},
                       three=3},
                    {two={1,{3,2,one=1}},
                     one=1,
                     three=3})
    -- itemsEquals is not recursive:
    assert_failure(t.assert_items_equals,{1,{2,1},3}, {3,1,{1,2}})
    assert_failure(t.assert_items_equals,{one=1,two={1,2},three=3}, {one={2,1},two=1,three=3})
    assert_failure(t.assert_items_equals,{one=1,two={1,{3,2,one=1}},three=3}, {two={{3,one=1,2},1},one=1,three=3})
    assert_failure(t.assert_items_equals,{one=1,two={1,{3,2,one=1}},three=3}, {two={{3,2,one=1},1},one=1,three=3})

    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {two=2,one=1,three=2})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {two=2,one=1,four=4})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {two=2,one=1,'three'})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {two=2,one=1,nil})
    assert_failure(t.assert_items_equals, {one=1,two=2,three=3}, {two=2,one=1})
end

function g.test_assert_items_include()
    local subject = t.assert_items_include
    subject({},{})
    subject({1,2,3}, {3,1,2})
    subject({nil},{nil})
    subject({one=1,two=2,three=3}, {two=2,one=1,three=3})
    subject({one=1,two=2,three=3}, {a=1,b=2,c=3})
    subject({1,2,three=3}, {3,1,two=2})

    subject({1},{})
    subject({1,2,3,4}, {3,1,2})
    subject({1,1,2,3}, {3,1,2})

    assert_failure(subject, {}, {1})
    assert_failure(subject, nil, {1})
    assert_failure(subject, {}, nil)
    assert_failure(subject, {1,2,3}, {1,2,3,4})
    assert_failure(subject, {1,2,3}, {1,1,2,3})
end

function g.test_assert_nan()
    assert_failure(t.assert_nan, "hi there!")
    assert_failure(t.assert_nan, nil)
    assert_failure(t.assert_nan, {})
    assert_failure(t.assert_nan, {1,2,3})
    assert_failure(t.assert_nan, {1})
    assert_failure(t.assert_nan, coroutine.create(function() end))
    t.assert_nan(0 / 0)
    t.assert_nan(-0 / 0)
    t.assert_nan(0 / -0)
    t.assert_nan(-0 / -0)
    local inf = math.huge
    t.assert_nan(inf / inf)
    t.assert_nan(-inf / inf)
    t.assert_nan(inf / -inf)
    t.assert_nan(-inf / -inf)
    t.assert_nan(inf - inf)
    t.assert_nan((-inf) + inf)
    t.assert_nan(inf + (-inf))
    t.assert_nan((-inf) - (-inf))
    t.assert_nan(0 * inf)
    t.assert_nan(-0 * inf)
    t.assert_nan(0 * -inf)
    t.assert_nan(-0 * -inf)
    t.assert_nan(math.sqrt(-1))
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.2" then
        -- Lua 5.3 will complain/error "bad argument #2 to 'fmod' (zero)"
        t.assert_nan(math.fmod(1, 0))
        t.assert_nan(math.fmod(1, -0))
    end
    t.assert_nan(math.fmod(inf, 1))
    t.assert_nan(math.fmod(-inf, 1))
    assert_failure(t.assert_nan, 0 / 1) -- 0.0
    assert_failure(t.assert_nan, 1 / 0) -- inf
    assert_failure(t.assert_nan, -1 / 0)-- -inf
end

function g.test_assert_not_nan()
    t.assert_not_nan("hi there!")
    t.assert_not_nan(nil)
    t.assert_not_nan({})
    t.assert_not_nan({1,2,3})
    t.assert_not_nan({1})
    t.assert_not_nan(coroutine.create(function() end))
    assert_failure(t.assert_not_nan, 0 / 0)
    assert_failure(t.assert_not_nan, -0 / 0)
    assert_failure(t.assert_not_nan, 0 / -0)
    assert_failure(t.assert_not_nan, -0 / -0)
    local inf = math.huge
    assert_failure(t.assert_not_nan, inf / inf)
    assert_failure(t.assert_not_nan, -inf / inf)
    assert_failure(t.assert_not_nan, inf / -inf)
    assert_failure(t.assert_not_nan, -inf / -inf)
    assert_failure(t.assert_not_nan, inf - inf)
    assert_failure(t.assert_not_nan, (-inf) + inf)
    assert_failure(t.assert_not_nan, inf + (-inf))
    assert_failure(t.assert_not_nan, (-inf) - (-inf))
    assert_failure(t.assert_not_nan, 0 * inf)
    assert_failure(t.assert_not_nan, -0 * inf)
    assert_failure(t.assert_not_nan, 0 * -inf)
    assert_failure(t.assert_not_nan, -0 * -inf)
    assert_failure(t.assert_not_nan, math.sqrt(-1))
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.2" then
        -- Lua 5.3 will complain/error "bad argument #2 to 'fmod' (zero)"
        assert_failure(t.assert_not_nan, math.fmod(1, 0))
        assert_failure(t.assert_not_nan, math.fmod(1, -0))
    end
    assert_failure(t.assert_not_nan, math.fmod(inf, 1))
    assert_failure(t.assert_not_nan, math.fmod(-inf, 1))
    t.assert_not_nan(0 / 1) -- 0.0
    t.assert_not_nan(1 / 0) -- inf
end

function g.test_assert_inf()
    assert_failure(t.assert_inf, "hi there!")
    assert_failure(t.assert_inf, nil)
    assert_failure(t.assert_inf, {})
    assert_failure(t.assert_inf, {1,2,3})
    assert_failure(t.assert_inf, {1})
    assert_failure(t.assert_inf, coroutine.create(function() end))

    assert_failure(t.assert_inf, 0)
    assert_failure(t.assert_inf, 1)
    assert_failure(t.assert_inf, 0 / 0) -- NaN
    assert_failure(t.assert_inf, -0 / 0) -- NaN
    assert_failure(t.assert_inf, 0 / 1) -- 0.0

    t.assert_inf(1 / 0) -- inf
    t.assert_inf(math.log(0)) -- -inf
    t.assert_inf(math.huge) -- inf
    t.assert_inf(-math.huge) -- -inf
end

function g.test_assert_plus_inf()
    assert_failure(t.assert_plus_inf, "hi there!")
    assert_failure(t.assert_plus_inf, nil)
    assert_failure(t.assert_plus_inf, {})
    assert_failure(t.assert_plus_inf, {1,2,3})
    assert_failure(t.assert_plus_inf, {1})
    assert_failure(t.assert_plus_inf, coroutine.create(function() end))

    assert_failure(t.assert_plus_inf, 0)
    assert_failure(t.assert_plus_inf, 1)
    assert_failure(t.assert_plus_inf, 0 / 0) -- NaN
    assert_failure(t.assert_plus_inf, -0 / 0) -- NaN
    assert_failure(t.assert_plus_inf, 0 / 1) -- 0.0
    assert_failure(t.assert_plus_inf, math.log(0)) -- -inf
    assert_failure(t.assert_plus_inf, -math.huge) -- -inf

    t.assert_plus_inf(1 / 0) -- inf
    t.assert_plus_inf(math.huge) -- inf

    -- behavior with -0 is lua version dependant:
    -- lua51, lua53: -0 does NOT represent the value minus zero BUT plus zero
    -- lua52, luajit: -0 represents the value minus zero
    -- this is verified with the value 1/-0
    -- lua 5.1, 5.3: 1/-0 = inf
    -- lua 5.2, luajit: 1/-0 = -inf
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        t.assert_plus_inf(1/-0)
    else
        assert_failure(t.assert_plus_inf, 1/-0)
    end
end


function g.test_assert_minus_inf()
    assert_failure(t.assert_minus_inf, "hi there!")
    assert_failure(t.assert_minus_inf, nil)
    assert_failure(t.assert_minus_inf, {})
    assert_failure(t.assert_minus_inf, {1,2,3})
    assert_failure(t.assert_minus_inf, {1})
    assert_failure(t.assert_minus_inf, coroutine.create(function() end))

    assert_failure(t.assert_minus_inf, 0)
    assert_failure(t.assert_minus_inf, 1)
    assert_failure(t.assert_minus_inf, 0 / 0) -- NaN
    assert_failure(t.assert_minus_inf, -0 / 0) -- NaN
    assert_failure(t.assert_minus_inf, 0 / 1) -- 0.0
    assert_failure(t.assert_minus_inf, -math.log(0)) -- inf
    assert_failure(t.assert_minus_inf, math.huge)    -- inf

    t.assert_minus_inf(math.log(0)) -- -inf
    t.assert_minus_inf(-1 / 0)       -- -inf
    t.assert_minus_inf(-math.huge)   -- -inf

    -- behavior with -0 is lua version dependant:
    -- lua51, lua53: -0 does NOT represent the value minus zero BUT plus zero
    -- lua52, luajit: -0 represents the value minus zero
    -- this is verified with the value 1/-0
    -- lua 5.1, 5.3: 1/-0 = inf
    -- lua 5.2, luajit: 1/-0 = -inf
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        assert_failure(t.assert_minus_inf, 1/-0)
    else
        t.assert_minus_inf(1/-0)
    end

end

function g.test_assert_not_inf()
    t.assert_not_inf("hi there!")
    t.assert_not_inf(nil)
    t.assert_not_inf({})
    t.assert_not_inf({1,2,3})
    t.assert_not_inf({1})
    t.assert_not_inf(coroutine.create(function() end))
    t.assert_not_inf(0 / 0) -- NaN
    t.assert_not_inf(0 / 1) -- 0.0
    assert_failure(t.assert_not_inf, 1 / 0)
    assert_failure(t.assert_not_inf, math.log(0))
    assert_failure(t.assert_not_inf, math.huge)
    assert_failure(t.assert_not_inf, -math.huge)
end


function g.test_assert_not_plus_inf()
    -- not inf
    t.assert_not_plus_inf("hi there!")
    t.assert_not_plus_inf(nil)
    t.assert_not_plus_inf({})
    t.assert_not_plus_inf({1,2,3})
    t.assert_not_plus_inf({1})
    t.assert_not_plus_inf(coroutine.create(function() end))

    t.assert_not_plus_inf(0)
    t.assert_not_plus_inf(1)
    t.assert_not_plus_inf(0 / 0) -- NaN
    t.assert_not_plus_inf(-0 / 0) -- NaN
    t.assert_not_plus_inf(0 / 1) -- 0.0
    t.assert_not_plus_inf(math.log(0)) -- -inf
    t.assert_not_plus_inf(-math.huge) -- -inf

    -- inf
    assert_failure(t.assert_not_plus_inf, 1 / 0) -- inf
    assert_failure(t.assert_not_plus_inf, math.huge) -- inf
end


function g.test_assert_not_isMinusInf()
    -- not inf
    t.assert_not_minus_inf("hi there!")
    t.assert_not_minus_inf(nil)
    t.assert_not_minus_inf({})
    t.assert_not_minus_inf({1,2,3})
    t.assert_not_minus_inf({1})
    t.assert_not_minus_inf(coroutine.create(function() end))

    t.assert_not_minus_inf(0)
    t.assert_not_minus_inf(1)
    t.assert_not_minus_inf(0 / 0) -- NaN
    t.assert_not_minus_inf(-0 / 0) -- NaN
    t.assert_not_minus_inf(0 / 1) -- 0.0
    t.assert_not_minus_inf(-math.log(0)) -- inf
    t.assert_not_minus_inf(math.huge)    -- inf

    -- inf
    assert_failure(t.assert_not_minus_inf, math.log(0)) -- -inf
    assert_failure(t.assert_not_minus_inf, -1 / 0)       -- -inf
    assert_failure(t.assert_not_minus_inf, -math.huge)   -- -inf
end

-- enable it only for debugging
--[[
function Xtest_printHandlingOfZeroAndInf()
    local inf = 1/0
    print(' inf    = ' .. inf)
    print('-inf    = ' .. -inf)
    print(' 1/inf  = ' .. 1/inf)
    print('-1/inf  = ' .. -1/inf)
    print(' 1/-inf = ' .. 1/-inf)
    print('-1/-inf = ' .. -1/-inf)
    print()
    print(' 1/-0 = '   .. 1/-0)
    print()
    print(' -0     = ' .. -0)
    print(' 0/-1   = ' .. 0/-1)
    print(' 0*-1   = ' .. 0*-1)
    print('-0/-1   = ' .. -0/-1)
    print('-0*-1   = ' .. -0*-1)
    print('(-0)/-1 = ' .. (-0)/-1)
    print(' 1/(0/-1)   = ' .. 1/(0/-1))
    print(' 1/(-0/-1)  = ' .. 1/(-0/-1))
    print('-1/(0/-1)   = ' .. -1/(0/-1))
    print('-1/(-0/-1)  = ' .. -1/(-0/-1))

    print()
    local minusZero = -1 / (1/0)
    print('minusZero  = -1 / (1/0)')
    print('minusZero  = '..minusZero)
    print(' 1/minusZero = '   .. 1/minusZero)
    print()
    print('minusZero/-1   = ' .. minusZero/-1)
    print('minusZero*-1   = ' .. minusZero*-1)
    print(' 1/(minusZero/-1)  = ' .. 1/(minusZero/-1))
    print('-1/(minusZero/-1)  = ' .. -1/(minusZero/-1))

end
]]

--[[    #### Important note when dealing with -0 and infinity ####

1. Dealing with infinity is consistent, the only difference is whether the resulting 0 is integer or float

Lua 5.3: dividing by infinity yields float 0
With inf = 1/0:
    -inf    = -inf
     1/inf  =  0.0
    -1/inf  = -0.0
     1/-inf = -0.0
    -1/-inf =  0.0

Lua 5.2 and 5.1 and luajit: dividing by infinity yields integer 0
    -inf    =-1.#INF
     1/inf  =  0
    -1/inf  = -0
     1/-inf = -0
    -1/-inf =  0

2. Dealing with minus 0 is totally inconsistent mathematically and accross lua versions if you use the syntax -0.
   It works correctly if you create the value by minusZero = -1 / (1/0)

   Enable the function above to see the extent of the damage of -0 :

   Lua 5.1:
   * -0 is consistently considered as 0
   *  0 multipllied or diveded by -1 is still 0
   * -0 multipllied or diveded by -1 is still 0

   Lua 5.2 and LuaJIT:
   * -0 is consistently -0
   *  0 multipllied or diveded by -1 is correctly -0
   * -0 multipllied or diveded by -1 is correctly 0

   Lua 5.3:
   * -0 is consistently considered as 0
   *  0 multipllied by -1 is correctly -0 but divided by -1 yields 0
   * -0 multipllied by -1 is 0 but diveded by -1 is -0
]]

function g.test_assert_plus_zero()
    assert_failure(t.assert_plus_zero, "hi there!")
    assert_failure(t.assert_plus_zero, nil)
    assert_failure(t.assert_plus_zero, {})
    assert_failure(t.assert_plus_zero, {1,2,3})
    assert_failure(t.assert_plus_zero, {1})
    assert_failure(t.assert_plus_zero, coroutine.create(function() end))

    local inf = 1/0
    assert_failure(t.assert_plus_zero, 1)
    assert_failure(t.assert_plus_zero, 0 / 0) -- NaN
    assert_failure(t.assert_plus_zero, -0 / 0) -- NaN
    assert_failure(t.assert_plus_zero, math.log(0))  -- inf
    assert_failure(t.assert_plus_zero, math.huge)    -- inf
    assert_failure(t.assert_plus_zero, -math.huge)   -- -inf
    assert_failure(t.assert_plus_zero, -1/inf)       -- -0.0

    t.assert_plus_zero(0 / 1)
    t.assert_plus_zero(0)
    t.assert_plus_zero(1/inf)

    -- behavior with -0 is lua version dependant, see note above
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        t.assert_plus_zero(-0)
    else
        assert_failure(t.assert_plus_zero, -0)
    end
end

function g.test_assert_not_plus_zero()
    -- not plus zero
    t.assert_not_plus_zero("hi there!")
    t.assert_not_plus_zero(nil)
    t.assert_not_plus_zero({})
    t.assert_not_plus_zero({1,2,3})
    t.assert_not_plus_zero({1})
    t.assert_not_plus_zero(coroutine.create(function() end))

    local inf = 1/0
    t.assert_not_plus_zero(1)
    t.assert_not_plus_zero(0 / 0) -- NaN
    t.assert_not_plus_zero(-0 / 0) -- NaN
    t.assert_not_plus_zero(math.log(0))  -- inf
    t.assert_not_plus_zero(math.huge)    -- inf
    t.assert_not_plus_zero(-math.huge)   -- -inf
    t.assert_not_plus_zero(-1/inf)       -- -0.0

    -- plus zero
    assert_failure(t.assert_not_plus_zero, 0 / 1)
    assert_failure(t.assert_not_plus_zero, 0)
    assert_failure(t.assert_not_plus_zero, 1/inf)

    -- behavior with -0 is lua version dependant, see note above
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        assert_failure(t.assert_not_plus_zero, -0)
    else
        t.assert_not_plus_zero(-0)
    end
end


function g.test_assert_minus_zero()
    assert_failure(t.assert_minus_zero, "hi there!")
    assert_failure(t.assert_minus_zero, nil)
    assert_failure(t.assert_minus_zero, {})
    assert_failure(t.assert_minus_zero, {1,2,3})
    assert_failure(t.assert_minus_zero, {1})
    assert_failure(t.assert_minus_zero, coroutine.create(function() end))

    local inf = 1/0
    assert_failure(t.assert_minus_zero, 1)
    assert_failure(t.assert_minus_zero, 0 / 0) -- NaN
    assert_failure(t.assert_minus_zero, -0 / 0) -- NaN
    assert_failure(t.assert_minus_zero, math.log(0))  -- inf
    assert_failure(t.assert_minus_zero, math.huge)    -- inf
    assert_failure(t.assert_minus_zero, -math.huge)   -- -inf
    assert_failure(t.assert_minus_zero, 1/inf)        -- -0.0
    assert_failure(t.assert_minus_zero, 0)


    t.assert_minus_zero(-1/inf)
    t.assert_minus_zero(1/-inf)

    -- behavior with -0 is lua version dependant, see note above
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        assert_failure(t.assert_minus_zero, -0)
    else
        t.assert_minus_zero(-0)
    end
end

function g.test_assert_not_isMinusZero()
    t.assert_not_minus_zero("hi there!")
    t.assert_not_minus_zero(nil)
    t.assert_not_minus_zero({})
    t.assert_not_minus_zero({1,2,3})
    t.assert_not_minus_zero({1})
    t.assert_not_minus_zero(coroutine.create(function() end))

    local inf = 1/0
    t.assert_not_minus_zero(1)
    t.assert_not_minus_zero(0 / 0) -- NaN
    t.assert_not_minus_zero(-0 / 0) -- NaN
    t.assert_not_minus_zero(math.log(0))  -- inf
    t.assert_not_minus_zero(math.huge)    -- inf
    t.assert_not_minus_zero(-math.huge)   -- -inf
    t.assert_not_minus_zero(0)
    t.assert_not_minus_zero(1/inf)        -- -0.0

    assert_failure(t.assert_not_minus_zero, -1/inf)
    assert_failure(t.assert_not_minus_zero, 1/-inf)

    -- behavior with -0 is lua version dependant, see note above
    if t._LUAVERSION == "Lua 5.1" or t._LUAVERSION == "Lua 5.3" then
        t.assert_not_minus_zero(-0)
    else
        assert_failure(t.assert_not_minus_zero, -0)
    end
end

function g.test_assert_type()
    assert_failure(t.assert_type, 1, 'string')
    assert_failure(t.assert_type, 1.4, 'string')
    t.assert_type("hi there!", 'string')
    assert_failure(t.assert_type, nil, 'string')
    assert_failure(t.assert_type, {}, 'string')
    assert_failure(t.assert_type, {1,2,3}, 'string')
    assert_failure(t.assert_type, {1}, 'string')
    assert_failure(t.assert_type, coroutine.create(function() end), 'string')
    assert_failure(t.assert_type, true, 'string')

    assert_failure(t.assert_type, 1, 'table')
    assert_failure(t.assert_type, 1.4, 'table')
    assert_failure(t.assert_type, "hi there!", 'table')
    assert_failure(t.assert_type, nil, 'table')
    t.assert_type({}, 'table')
    t.assert_type({1,2,3}, 'table')
    t.assert_type({1}, 'table')
    assert_failure(t.assert_type, true, 'table')
    assert_failure(t.assert_type, coroutine.create(function() end), 'table')

    assert_failure(t.assert_type, 1, 'boolean')
    assert_failure(t.assert_type, 1.4, 'boolean')
    assert_failure(t.assert_type, "hi there!", 'boolean')
    assert_failure(t.assert_type, nil, 'boolean')
    assert_failure(t.assert_type, {}, 'boolean')
    assert_failure(t.assert_type, {1,2,3}, 'boolean')
    assert_failure(t.assert_type, {1}, 'boolean')
    assert_failure(t.assert_type, coroutine.create(function() end), 'boolean')
    t.assert_type(true, 'boolean')
    t.assert_type(false, 'boolean')

    assert_failure(t.assert_type, 1, 'function')
    assert_failure(t.assert_type, 1.4, 'function')
    assert_failure(t.assert_type, "hi there!", 'function')
    assert_failure(t.assert_type, nil, 'function')
    assert_failure(t.assert_type, {}, 'function')
    assert_failure(t.assert_type, {1,2,3}, 'function')
    assert_failure(t.assert_type, {1}, 'function')
    assert_failure(t.assert_type, false, 'function')
    assert_failure(t.assert_type, coroutine.create(function() end), 'function')
    t.assert_type(function() return true end, 'function')

    assert_failure(t.assert_type, 1, 'thread')
    assert_failure(t.assert_type, 1.4, 'thread')
    assert_failure(t.assert_type, "hi there!", 'thread')
    assert_failure(t.assert_type, nil, 'thread')
    assert_failure(t.assert_type, {}, 'thread')
    assert_failure(t.assert_type, {1,2,3}, 'thread')
    assert_failure(t.assert_type, {1}, 'thread')
    assert_failure(t.assert_type, false, 'thread')
    assert_failure(t.assert_type, function() end, 'thread')
    t.assert_type(coroutine.create(function() end), 'thread')

    assert_failure(t.assert_type, 1, 'userdata')
    assert_failure(t.assert_type, 1.4, 'userdata')
    assert_failure(t.assert_type, "hi there!", 'userdata')
    assert_failure(t.assert_type, nil, 'userdata')
    assert_failure(t.assert_type, {}, 'userdata')
    assert_failure(t.assert_type, {1,2,3}, 'userdata')
    assert_failure(t.assert_type, {1}, 'userdata')
    assert_failure(t.assert_type, false, 'userdata')
    assert_failure(t.assert_type, function() end, 'userdata')
    assert_failure(t.assert_type, coroutine.create(function() end), 'userdata')

    t.assert_type(1, 'number')
    t.assert_type(1.4, 'number')
    assert_failure(t.assert_type, "hi there!", 'number')
    assert_failure(t.assert_type, nil, 'number')
    assert_failure(t.assert_type, {}, 'number')
    assert_failure(t.assert_type, {1,2,3}, 'number')
    assert_failure(t.assert_type, {1}, 'number')
    assert_failure(t.assert_type, coroutine.create(function() end), 'number')
    assert_failure(t.assert_type, true, 'number')
end

function g.test_assert_is()
    local f = function() return true end
    local t1= {}
    local t2={1,2}
    local t3={1,2}
    local t4= {a=1,{1,2},day="today"}
    local s1='toto'
    local s2='toto'
    local s3='to'..'to'
    local b1=true
    local b2=false

    t.assert_is(1,1)
    t.assert_is(f,f)
    t.assert_is('toto', 'toto')
    t.assert_is(s1, s2)
    t.assert_is(s1, s3)
    t.assert_is(t1,t1)
    t.assert_is(t4,t4)
    t.assert_is(b1, true)
    t.assert_is(b2, false)

    assert_failure(t.assert_is, 1, 2)
    assert_failure(t.assert_is, 1.4, 1)
    assert_failure(t.assert_is, "hi there!", "hola")
    assert_failure(t.assert_is, nil, 1)
    assert_failure(t.assert_is, {}, {})
    assert_failure(t.assert_is, {1,2,3}, f)
    assert_failure(t.assert_is, f, function() return true end)
    assert_failure(t.assert_is, t2,t3)
    assert_failure(t.assert_is, b2, nil)
end

function g.test_assert_not_is()
    local f = function() return true end
    local t1= {}
    local t2={1,2}
    local t3={1,2}
    local t4= {a=1,{1,2},day="today"}
    local s1='toto'
    local s2='toto'
    local b1=true
    local b2=false

    assert_failure(t.assert_is_not, 1,1)
    assert_failure(t.assert_is_not, f,f)
    assert_failure(t.assert_is_not, t1,t1)
    assert_failure(t.assert_is_not, t4,t4)
    assert_failure(t.assert_is_not, s1,s2)
    assert_failure(t.assert_is_not, 'toto', 'toto')
    assert_failure(t.assert_is_not, b1, true)
    assert_failure(t.assert_is_not, b2, false)

    t.assert_is_not(1, 2)
    t.assert_is_not(1.4, 1)
    t.assert_is_not("hi there!", "hola")
    t.assert_is_not(nil, 1)
    t.assert_is_not({}, {})
    t.assert_is_not({1,2,3}, f)
    t.assert_is_not(f, function() return true end)
    t.assert_is_not(t2,t3)
    t.assert_is_not(b1, false)
    t.assert_is_not(b2, true)
    t.assert_is_not(b2, nil)
end

function g.test_assertTableNum()
    t.assert_equals(3, 3)
    t.assert_not_equals(3, 4)
    t.assert_equals({3}, {3})
    t.assert_not_equals({3}, 3)
    t.assert_not_equals({3}, {4})
    t.assert_equals({x=1}, {x=1})
    t.assert_not_equals({x=1}, {x=2})
    t.assert_not_equals({x=1}, {y=1})
end
function g.test_assertTableStr()
    t.assert_equals('3', '3')
    t.assert_not_equals('3', '4')
    t.assert_equals({'3'}, {'3'})
    t.assert_not_equals({'3'}, '3')
    t.assert_not_equals({'3'}, {'4'})
    t.assert_equals({x='1'}, {x='1'})
    t.assert_not_equals({x='1'}, {x='2'})
    t.assert_not_equals({x='1'}, {y='1'})
end
function g.test_assertTableLev2()
    t.assert_equals({x={'a'}}, {x={'a'}})
    t.assert_not_equals({x={'a'}}, {x={'b'}})
    t.assert_not_equals({x={'a'}}, {z={'a'}})
    t.assert_equals({{x=1}}, {{x=1}})
    t.assert_not_equals({{x=1}}, {{y=1}})
    t.assert_equals({{x='a'}}, {{x='a'}})
    t.assert_not_equals({{x='a'}}, {{x='b'}})
end
function g.test_assertTableList()
    t.assert_equals({3,4,5}, {3,4,5})
    t.assert_not_equals({3,4,5}, {3,4,6})
    t.assert_not_equals({3,4,5}, {3,5,4})
    t.assert_equals({3,4,x=5}, {3,4,x=5})
    t.assert_not_equals({3,4,x=5}, {3,4,x=6})
    t.assert_not_equals({3,4,x=5}, {3,x=4,5})
    t.assert_not_equals({3,4,5}, {2,3,4,5})
    t.assert_not_equals({3,4,5}, {3,2,4,5})
    t.assert_not_equals({3,4,5}, {3,4,5,6})
end

function g.test_assertTableNil()
    t.assert_equals({3,4,5}, {3,4,5})
    t.assert_not_equals({3,4,5}, {nil,3,4,5})
    t.assert_not_equals({3,4,5}, {nil,4,5})
    t.assert_equals({3,4,5}, {3,4,5,nil}) -- lua quirk
    t.assert_not_equals({3,4,5}, {3,4,nil})
    t.assert_not_equals({3,4,5}, {3,nil,5})
    t.assert_not_equals({3,4,5}, {3,4,nil,5})
end

function g.test_assertTableNilFront()
    t.assert_equals({nil,4,5}, {nil,4,5})
    t.assert_not_equals({nil,4,5}, {nil,44,55})
    t.assert_equals({nil,'4','5'}, {nil,'4','5'})
    t.assert_not_equals({nil,'4','5'}, {nil,'44','55'})
    t.assert_equals({nil,{4,5}}, {nil,{4,5}})
    t.assert_not_equals({nil,{4,5}}, {nil,{44,55}})
    t.assert_not_equals({nil,{4}}, {nil,{44}})
    t.assert_equals({nil,{x=4,5}}, {nil,{x=4,5}})
    t.assert_equals({nil,{x=4,5}}, {nil,{5,x=4}}) -- lua quirk
    t.assert_equals({nil,{x=4,y=5}}, {nil,{y=5,x=4}}) -- lua quirk
    t.assert_not_equals({nil,{x=4,5}}, {nil,{y=4,5}})
end

function g.test_assertTableAdditions()
    t.assert_equals({1,2,3}, {1,2,3})
    t.assert_not_equals({1,2,3}, {1,2,3,4})
    t.assert_not_equals({1,2,3,4}, {1,2,3})
    t.assert_equals({1,x=2,3}, {1,x=2,3})
    t.assert_not_equals({1,x=2,3}, {1,x=2,3,y=4})
    t.assert_not_equals({1,x=2,3,y=4}, {1,x=2,3})
end
