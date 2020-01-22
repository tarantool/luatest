local t = require('luatest')
local g = t.group()

local fun = require('fun')

local helper = require('test.helper')
local assert_failure_matches = helper.assert_failure_matches

local function range(start, stop)
    -- return list of {start ... stop}
    local i
    local ret = {}
    i=start
    while i <= stop do
        table.insert(ret, i)
        i = i + 1
    end
    return ret
end

function g.test_genSortedIndex()
    t.assert_equals(t.private.__gen_sorted_index({2, 5, 7}), {1,2,3})
    t.assert_equals(t.private.__gen_sorted_index({a='1', h='2', c='3'}), {'a', 'c', 'h'})
    t.assert_equals(t.private.__gen_sorted_index({1, 'z', a='1', h='2', c='3'}), {1, 2, 'a', 'c', 'h'})
    t.assert_equals(t.private.__gen_sorted_index({b=4, a=3, true, foo="bar", nil, bar=false, 42, c=5}),
                                                  {1, 3, 'a', 'b', 'bar', 'c', 'foo'})
end

function g.test_sorted_nextWorks()
    local t1 = {}
    t1['aaa'] = 'abc'
    t1['ccc'] = 'def'
    t1['bbb'] = 'cba'

    -- mimic semantics of "generic for" loop
    local sorted_next, state = t.private.sorted_pairs(t1)

    local k, v = sorted_next(state, nil)
    t.assert_equals(k, 'aaa')
    t.assert_equals(v, 'abc')
    k, v = sorted_next(state, k)
    t.assert_equals(k, 'bbb')
    t.assert_equals(v, 'cba')
    k, v = sorted_next(state, k)
    t.assert_equals(k, 'ccc')
    t.assert_equals(v, 'def')
    k, v = sorted_next(state, k)
    t.assert_equals(k, nil)
    t.assert_equals(v, nil)

    -- check if starting the iteration a second time works
    k, v = sorted_next(state, nil)
    t.assert_equals(k, 'aaa')
    t.assert_equals(v, 'abc')

    -- run a generic for loop (internally using a separate state)
    local tested = {}
    for _, val in t.private.sorted_pairs(t1) do table.insert(tested, val) end
    t.assert_equals(tested, {'abc', 'cba', 'def'})

    -- test bisection algorithm by searching for non-existing key values
    k, v = sorted_next(state, '') -- '' would come before any of the keys
    t.assert_equals(k, nil)
    t.assert_equals(v, nil)
    k, v = sorted_next(state, 'xyz') -- 'xyz' would be after any other key
    t.assert_equals(k, nil)
    t.assert_equals(v, nil)

    -- finally let's see if we successfully find an "out of sequence" key
    k, v = sorted_next(state, 'bbb')
    t.assert_equals(k, 'ccc')
    t.assert_equals(v, 'def')
end

function g.test_sorted_nextWorksOnTwoTables()
    local t1 = {aaa = 'abc', ccc = 'def'}
    local t2 = {['3'] = '33', ['1'] = '11'}

    local sorted_next, state1, state2, _
    _, state1 = t.private.sorted_pairs(t1)
    sorted_next, state2 = t.private.sorted_pairs(t2)

    local k, v = sorted_next(state1, nil)
    t.assert_equals(k, 'aaa')
    t.assert_equals(v, 'abc')

    k, v = sorted_next(state2, nil)
    t.assert_equals(k, '1')
    t.assert_equals(v, '11')

    k, v = sorted_next(state1, 'aaa')
    t.assert_equals(k, 'ccc')
    t.assert_equals(v, 'def')

    k, v = sorted_next(state2, '1')
    t.assert_equals(k, '3')
    t.assert_equals(v, '33')
end

function g.test_randomize_table()
    local tab, tref, n = {}, {}, 20
    for i = 1, n do
        tab[i], tref[i] = i, i
    end
    t.assert_equals(#tab, n)

    t.private.randomize_table(tab)
    t.assert_equals(#tab, n)
    t.assert_not_equals(tab, tref)
    table.sort(tab)
    t.assert_equals(tab, tref)
end

function g.test_strSplitOneCharDelim()
    local tab = t.private.strsplit('\n', '122333')
    t.assert_equals(tab[1], '122333')
    t.assert_equals(#tab, 1)

    tab = t.private.strsplit('\n', '1\n22\n333\n')
    t.assert_equals(tab[1], '1')
    t.assert_equals(tab[2], '22')
    t.assert_equals(tab[3], '333')
    t.assert_equals(tab[4], '')
    t.assert_equals(#tab, 4)
    -- test invalid (empty) delimiter
    t.assert_error_msg_contains('delimiter is nil or empty string!',
                              t.private.strsplit, '', '1\n22\n333\n')
    t.assert_error_msg_contains('delimiter is nil or empty string!',
                              t.private.strsplit, nil, '1\n22\n333\n')
end

function g.test_strSplit3CharDelim()
    local tab = t.private.strsplit('2\n3', '1\n22\n332\n3')
    t.assert_equals(tab[1], '1\n2')
    t.assert_equals(tab[2], '3')
    t.assert_equals(tab[3], '')
    t.assert_equals(#tab, 3)
end

function g.test_strSplitWithNil()
    t.assert_equals(nil, t.private.strsplit('-', nil))
end

function g.test_protected_call()
    local function boom() error("Something went wrong.") end
    local err = t.LuaUnit:protected_call(nil, boom, "kaboom")

    -- check that err received the expected fields
    t.assert_equals(err.status, "error")
    t.assert_str_contains(err.message, "Something went wrong.")
    t.assert_str_matches(err.trace, "^stack traceback:.*in %a+ 'kaboom'.*")
end

function g.test_prefix_string()
    t.assert_equals(t.private.prefix_string('12 ', 'ab\ncd\nde'), '12 ab\n12 cd\n12 de')
end

function g.test_equals_for_tables()
    -- Make sure that _is_table_equals() doesn't fall for these traps
    -- (See https://github.com/bluebird75/luaunit/issues/48)
    local A, B, C = {}, {}, {}

    A.self = A
    B.self = B
    t.assert_not_equals(A, B)
    t.assert_equals(A, A)

    A, B = {}, {}
    A.circular = C
    B.circular = A
    C.circular = B
    t.assert_not_equals(A, B)
    t.assert_equals(C, C)

    A = {}
    A[{}] = A
    t.assert_equals(A, A)

    A = {}
    A[A] = 1
    t.assert_equals(A, A)
end

function g.test_suitableForMismatchFormatting()
    t.assert_not(t.private.try_mismatch_formatting({1,2}, {2,1}))
    t.assert_not(t.private.try_mismatch_formatting(nil, {1,2,3}))
    t.assert_not(t.private.try_mismatch_formatting({1,2,3}, {}))
    t.assert_not(t.private.try_mismatch_formatting("123", "123"))
    t.assert_not(t.private.try_mismatch_formatting("123", "123"))
    t.assert_not(t.private.try_mismatch_formatting({'a','b','c'}, {'c', 'b', 'a'}))
    t.assert_not(t.private.try_mismatch_formatting({1,2,3, toto='tutu'}, {1,2,3, toto='tata', tutu="bloup"}))
    t.assert_not(t.private.try_mismatch_formatting({1,2,3, [5]=1000}, {1,2,3}))

    local i=0
    local l1, l2={}, {}
    while i <= t.LIST_DIFF_ANALYSIS_THRESHOLD+1 do
        i = i + 1
        table.insert(l1, i)
        table.insert(l2, i+1)
    end

    t.assert(t.private.try_mismatch_formatting(l1, l2))
end


function g.test_diffAnalysisThreshold()
    local threshold =  t.LIST_DIFF_ANALYSIS_THRESHOLD
    t.assert_not(t.private.try_mismatch_formatting(range(1,threshold-1), range(1,threshold-2), t.DEFAULT_DEEP_ANALYSIS))
    t.assert(t.private.try_mismatch_formatting(range(1,threshold),   range(1,threshold),   t.DEFAULT_DEEP_ANALYSIS))

    t.assert_not(t.private.try_mismatch_formatting(range(1,threshold-1), range(1,threshold-2), t.DISABLE_DEEP_ANALYSIS))
    t.assert_not(t.private.try_mismatch_formatting(range(1,threshold),   range(1,threshold),   t.DISABLE_DEEP_ANALYSIS))

    t.assert(t.private.try_mismatch_formatting(range(1,threshold-1), range(1,threshold-2), t.FORCE_DEEP_ANALYSIS))
    t.assert(t.private.try_mismatch_formatting(range(1,threshold),   range(1,threshold),   t.FORCE_DEEP_ANALYSIS))
end

function g.test_table_raw_tostring()
    local t1 = {'1','2'}
    t.assert_str_matches(tostring(t1), 'table: 0?x?[%x]+')
    t.assert_str_matches(t.private._table_raw_tostring(t1), 'table: 0?x?[%x]+')

    local ts = function(tab) return tab[1]..tab[2] end
    local mt = {__tostring = ts}
    setmetatable(t1, mt)
    t.assert_str_matches(tostring(t1), '12')
    t.assert_str_matches(t.private._table_raw_tostring(t1), 'table: 0?x?[%x]+')
end

function g.test_prettystr_numbers()
    t.assert_equals(t.prettystr(1), "1")
    t.assert_equals(t.prettystr(1.0), "1")
    t.assert_equals(t.prettystr(1.1), "1.1")
    t.assert_equals(t.prettystr(1/0), "#Inf")
    t.assert_equals(t.prettystr(-1/0), "-#Inf")
    t.assert_equals(t.prettystr(0/0), "#NaN")
end

function g.test_prettystr_strings()
    t.assert_equals(t.prettystr('abc'), '"abc"')
    t.assert_equals(t.prettystr('ab\ncd'), '"ab\ncd"')
    t.assert_equals(t.prettystr('ab"cd'), "'ab\"cd'")
    t.assert_equals(t.prettystr("ab'cd"), '"ab\'cd"')
end

function g.test_prettystr_tables1()
    t.assert_equals(t.prettystr({1,2,3}), "{1, 2, 3}")
    t.assert_equals(t.prettystr({a=1,bb=2,ab=3}), '{a = 1, ab = 3, bb = 2}')
    t.assert_equals(t.prettystr({[{}] = 1}), '{[{}] = 1}')
    t.assert_equals(t.prettystr({1, [{}] = 1, 2}), '{1, 2, [{}] = 1}')
    t.assert_equals(t.prettystr({1, [{one=1}] = 1, 2, "test", false}), '{1, 2, "test", false, [{one = 1}] = 1}')
end

function g.test_prettystr_tables2()
    -- test the (private) key string formatting within _table_tostring()
    t.assert_equals(t.prettystr({a = 1}), '{a = 1}')
    t.assert_equals(t.prettystr({a0 = 2}), '{a0 = 2}')
    t.assert_equals(t.prettystr({['a0!'] = 3}), '{["a0!"] = 3}')
    t.assert_equals(t.prettystr({["foo\nbar"] = 1}), [[{["foo
bar"] = 1}]])
    t.assert_equals(t.prettystr({["foo'bar"] = 2}), [[{["foo'bar"] = 2}]])
    t.assert_equals(t.prettystr({['foo"bar'] = 3}), [[{['foo"bar'] = 3}]])
end

function g.test_prettystr_tables3()
    -- test with a table containing a metatable for __tostring
    local t1 = {'1','2'}
    t.assert_str_matches(tostring(t1), 'table: 0?x?[%x]+')
    t.assert_equals(t.prettystr(t1), '{"1", "2"}')

    -- add metatable
    local function ts(tab) return string.format('Point<%s,%s>', tab[1], tab[2]) end
    setmetatable(t1, {__tostring = ts})

    t.assert_equals(tostring(t1), 'Point<1,2>')
    t.assert_equals(t.prettystr(t1), 'Point<1,2>')

    local function ts2(tab)
        return string.format('Point:\n    x=%s\n    y=%s', tab[1], tab[2])
    end

    local t2 = {'1','2'}
    setmetatable(t2, {__tostring = ts2})

    t.assert_equals(tostring(t2), [[Point:
    x=1
    y=2]])
    t.assert_equals(t.prettystr(t2), [[Point:
    x=1
    y=2]])

    -- nested table
    local t3 = {'3', t1}
    t.assert_equals(t.prettystr(t3), [[{"3", Point<1,2>}]])

    local t4 = {'3', t2}
    t.assert_equals(t.prettystr(t4), [[{"3", Point:
        x=1
        y=2}]])

    local t5 = {1,2,{3,4},string.rep('W', t.LINE_LENGTH), t2, 33}
    t.assert_equals(t.prettystr(t5), [[{
    1,
    2,
    {3, 4},
    "]]..string.rep('W', t.LINE_LENGTH)..[[",
    Point:
        x=1
        y=2,
    33,
}]])

    local t6 = {}
    local function t6_tostring() end
    setmetatable(t6, {__tostring = t6_tostring})
    t.assert_equals(t.prettystr(t6), '<invalid tostring() result: "nil" >')
end

function g.test_prettystr_adv_tables()
    local t1 = {1,2,3,4,5,6}
    t.assert_equals(t.prettystr(t1), "{1, 2, 3, 4, 5, 6}")

    local t2 = {
        'aaaaaaaaaaaaaaaaa',
        'bbbbbbbbbbbbbbbbbbbb',
        'ccccccccccccccccc',
        'ddddddddddddd',
        'eeeeeeeeeeeeeeeeee',
        'ffffffffffffffff',
        'ggggggggggg',
        'hhhhhhhhhhhhhh',
    }
    t.assert_equals(t.prettystr(t2), table.concat({
        '{',
        '    "aaaaaaaaaaaaaaaaa",',
        '    "bbbbbbbbbbbbbbbbbbbb",',
        '    "ccccccccccccccccc",',
        '    "ddddddddddddd",',
        '    "eeeeeeeeeeeeeeeeee",',
        '    "ffffffffffffffff",',
        '    "ggggggggggg",',
        '    "hhhhhhhhhhhhhh",',
        '}',
  } , '\n'))

    t.assert(t.private.has_new_line(t.prettystr(t2)))

    local t2bis = {1,2,3,'12345678901234567890123456789012345678901234567890123456789012345678901234567890', 4,5,6}
    t.assert_equals(t.prettystr(t2bis), [[{
    1,
    2,
    3,
    "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
    4,
    5,
    6,
}]])

    local t3 = {l1a = {l2a = {l3a='012345678901234567890123456789012345678901234567890123456789'},
    l2b='bbb'}, l1b = 4}
    t.assert_equals(t.prettystr(t3), [[{
    l1a = {
        l2a = {l3a = "012345678901234567890123456789012345678901234567890123456789"},
        l2b = "bbb",
    },
    l1b = 4,
}]])

    local t4 = {a=1, b=2, c=3}
    t.assert_equals(t.prettystr(t4), '{a = 1, b = 2, c = 3}')

    local t5 = {t1, t2, t3}
    t.assert_equals(t.prettystr(t5), [[{
    {1, 2, 3, 4, 5, 6},
    {
        "aaaaaaaaaaaaaaaaa",
        "bbbbbbbbbbbbbbbbbbbb",
        "ccccccccccccccccc",
        "ddddddddddddd",
        "eeeeeeeeeeeeeeeeee",
        "ffffffffffffffff",
        "ggggggggggg",
        "hhhhhhhhhhhhhh",
    },
    {
        l1a = {
            l2a = {l3a = "012345678901234567890123456789012345678901234567890123456789"},
            l2b = "bbb",
        },
        l1b = 4,
    },
}]])

    local t6 = {t1=t1, t2=t2, t3=t3, t4=t4}
    t.assert_equals(t.prettystr(t6),[[{
    t1 = {1, 2, 3, 4, 5, 6},
    t2 = {
        "aaaaaaaaaaaaaaaaa",
        "bbbbbbbbbbbbbbbbbbbb",
        "ccccccccccccccccc",
        "ddddddddddddd",
        "eeeeeeeeeeeeeeeeee",
        "ffffffffffffffff",
        "ggggggggggg",
        "hhhhhhhhhhhhhh",
    },
    t3 = {
        l1a = {
            l2a = {l3a = "012345678901234567890123456789012345678901234567890123456789"},
            l2b = "bbb",
        },
        l1b = 4,
    },
    t4 = {a = 1, b = 2, c = 3},
}]])
end

function g.test_prettystrTableRecursion()
    local tab = {}
    tab.__index = tab
    t.assert_str_matches(t.prettystr(tab), "(<table: 0?x?[%x]+>) {__index = %1}")

    local t1 = {}
    local t2 = {}
    t1.t2 = t2
    t2.t1 = t1
    local t3 = {t1 = t1, t2 = t2}
    t.assert_str_matches(t.prettystr(t1), "(<table: 0?x?[%x]+>) {t2 = (<table: 0?x?[%x]+>) {t1 = %1}}")
    t.assert_str_matches(t.prettystr(t3), [[(<table: 0?x?[%x]+>) {
    t1 = (<table: 0?x?[%x]+>) {t2 = (<table: 0?x?[%x]+>) {t1 = %2}},
    t2 = %3,
}]])

    local t4 = {1,2}
    local t5 = {3,4,t4}
    t4[3] = t5
    t.assert_str_matches(t.prettystr(t5), "(<table: 0?x?[%x]+>) {3, 4, (<table: 0?x?[%x]+>) {1, 2, %1}}")

    local t6 = {}
    t6[t6] = 1
    t.assert_str_matches(t.prettystr(t6), "(<table: 0?x?[%x]+>) {%1=1}")

    local t7, t8 = {"t7"}, {"t8"}
    t7[t8] = 1
    t8[t7] = 2
    t.assert_str_matches(t.prettystr(t7), '(<table: 0?x?[%x]+>) {"t7", %[(<table: 0?x?[%x]+>) {"t8", %1=2}%] = 1}')

    local t9 = {"t9", {}}
    t9[{t9}] = 1

    t.assert_str_matches(t.prettystr(t9, true), [[(<table: 0?x?[%x]+>) {
?%s*"t9",
?%s*(<table: 0?x?[%x]+>) {},
?%s*%[%s*(<table: 0?x?[%x]+>) {%1}%] = 1,?
?}]])
end

function g.test_prettystr_pairs()
    local foo, bar, str1, str2 = nil, nil

    -- test all combinations of: foo = nil, "foo", "fo\no" (embedded
    -- newline); and bar = nil, "bar", "bar\n" (trailing newline)

    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, "nil")
    t.assert_equals(str2, "nil")
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, "nil_B")
    t.assert_equals(str2, "nil")

    bar = "bar"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, "nil")
    t.assert_equals(str2, '"bar"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, "nil_B")
    t.assert_equals(str2, '"bar"')

    bar = "bar\n"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, "\nnil")
    t.assert_equals(str2, '\n"bar\n"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, "\nnil_A")
    t.assert_equals(str2, '\n"bar\n"')

    foo = "foo"
    bar = nil
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '"foo"')
    t.assert_equals(str2, "nil")
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '"foo"_B')
    t.assert_equals(str2, "nil")

    bar = "bar"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '"foo"')
    t.assert_equals(str2, '"bar"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '"foo"_B')
    t.assert_equals(str2, '"bar"')

    bar = "bar\n"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '\n"foo"')
    t.assert_equals(str2, '\n"bar\n"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"foo"_A')
    t.assert_equals(str2, '\n"bar\n"')

    foo = "fo\no"
    bar = nil
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '\n"fo\no"')
    t.assert_equals(str2, "\nnil")
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\no"_A')
    t.assert_equals(str2, "\nnil")

    bar = "bar"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '\n"fo\no"')
    t.assert_equals(str2, '\n"bar"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\no"_A')
    t.assert_equals(str2, '\n"bar"')

    bar = "bar\n"
    str1, str2 = t.private.prettystr_pairs(foo, bar)
    t.assert_equals(str1, '\n"fo\no"')
    t.assert_equals(str2, '\n"bar\n"')
    str1, str2 = t.private.prettystr_pairs(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\no"_A')
    t.assert_equals(str2, '\n"bar\n"')
end

function g.test_fail_fmt()
    -- raise failure from within nested functions
    local function babar(level)
        t.private.fail_fmt(level, 'toto', "hex=%X", 123)
    end
    local function bar(level)
        t.private.fail_fmt(level, nil, "hex=%X", 123)
    end
    local function foo(level)
        bar(level)
    end

    assert_failure_matches(".*test[\\/]luaunit[\\/]utility_test%.lua:(%d+): (.*)hex=7B$", foo)
    assert_failure_matches(".*test[\\/]luaunit[\\/]utility_test%.lua:(%d+): (.*)hex=7B$", foo, 2)
    assert_failure_matches(".*test[\\/]luaunit[\\/]utility_test%.lua:(%d+): toto\n(.*)hex=7B$", babar, 1)
end

function g.test_split_test_method_name()
    t.assert_equals(t.LuaUnit.split_test_method_name('toto'), nil)
    t.assert_equals({t.LuaUnit.split_test_method_name('toto.tutu')},
                     {'toto', 'tutu'})
end

function g.test_is_method_test_name()
    t.assert_equals(t.LuaUnit.is_method_test_name('testToto'), true)
    t.assert_equals(t.LuaUnit.is_method_test_name('TestToto'), true)
    t.assert_equals(t.LuaUnit.is_method_test_name('TESTToto'), true)
    t.assert_equals(t.LuaUnit.is_method_test_name('xTESTToto'), false)
    t.assert_equals(t.LuaUnit.is_method_test_name(''), false)
end

function g.test_parse_cmd_line()
    local function assert_subject(args, expected)
        expected.paths = {}
        t.assert_equals(t.LuaUnit.parse_cmd_line(args), expected)
    end
    --test names
    assert_subject(nil, {})
    assert_subject({'someTest'}, {test_names={'someTest'}})
    assert_subject({'someTest', 'someOtherTest'}, {test_names={'someTest', 'someOtherTest'}})

    -- verbosity
    assert_subject({'--verbose'}, {verbosity=t.VERBOSITY_VERBOSE})
    assert_subject({'-v'}, {verbosity=t.VERBOSITY_VERBOSE})
    assert_subject({'--quiet'}, {verbosity=t.VERBOSITY_QUIET})
    assert_subject({'-q'}, {verbosity=t.VERBOSITY_QUIET})
    assert_subject({'-v', '-q'}, {verbosity=t.VERBOSITY_QUIET})

    --output
    assert_subject({'--output', 'toto'}, {output='toto'})
    assert_subject({'-o', 'toto'}, {output='toto'})
    t.assert_error_msg_contains('Missing argument after -o', t.LuaUnit.parse_cmd_line, {'-o',})

    --name
    assert_subject({'--name', 'toto'}, {output_file_name='toto'})
    assert_subject({'-n', 'toto'}, {output_file_name='toto'})
    t.assert_error_msg_contains('Missing argument after -n', t.LuaUnit.parse_cmd_line, {'-n',})

    --patterns
    assert_subject({'--pattern', 'toto'}, {tests_pattern={'toto'}})
    assert_subject({'-p', 'toto'}, {tests_pattern={'toto'}})
    assert_subject({'-p', 'tutu', '-p', 'toto'}, {tests_pattern={'tutu', 'toto'}})
    t.assert_error_msg_contains('Missing argument after -p', t.LuaUnit.parse_cmd_line, {'-p',})
    assert_subject({'--exclude', 'toto'}, {tests_pattern={'!toto'}})
    assert_subject({'-x', 'toto'}, {tests_pattern={'!toto'}})
    assert_subject({'-x', 'tutu', '-x', 'toto'}, {tests_pattern={'!tutu', '!toto'}})
    assert_subject({'-x', 'tutu', '-p', 'foo', '-x', 'toto'}, {tests_pattern={'!tutu', 'foo', '!toto'}})
    t.assert_error_msg_contains('Missing argument after -x', t.LuaUnit.parse_cmd_line, {'-x',})

    -- repeat
    assert_subject({'--repeat', '123'}, {exe_repeat=123})
    assert_subject({'-r', '123'}, {exe_repeat=123})
    t.assert_error_msg_contains('Malformed -r argument', t.LuaUnit.parse_cmd_line, {'-r', 'bad'})
    t.assert_error_msg_contains('Missing argument after -r', t.LuaUnit.parse_cmd_line, {'-r',})

    -- shuffle
    assert_subject({'--shuffle', 'all'}, {shuffle='all'})
    assert_subject({'-s', 'group'}, {shuffle='group'})

    --megamix
    assert_subject({'-p', 'toto', 'tutu', '-v', 'tata', '-o', 'tintin', '-p', 'tutu', 'prout', '-n', 'toto.xml'}, {
        tests_pattern = {'toto', 'tutu'},
        verbosity = t.VERBOSITY_VERBOSE,
        output = 'tintin',
        test_names = {'tutu', 'tata', 'prout'},
        output_file_name='toto.xml',
    })

    t.assert_error_msg_contains('option: -$', t.LuaUnit.parse_cmd_line, {'-$',})
end

function g.test_pattern_filter()
    t.assert_equals(t.private.pattern_filter(nil, 'toto'), true)
    t.assert_equals(t.private.pattern_filter({}, 'toto'), true)

    -- positive pattern
    t.assert_equals(t.private.pattern_filter({'toto'}, 'toto'), true)
    t.assert_equals(t.private.pattern_filter({'toto'}, 'yyytotoxxx'), true)
    t.assert_equals(t.private.pattern_filter({'tutu', 'toto'}, 'yyytotoxxx'), true)
    t.assert_equals(t.private.pattern_filter({'tutu', 'toto'}, 'tutu'), true)
    t.assert_equals(t.private.pattern_filter({'tutu', 'to..'}, 'yyytoxxx'), true)

    -- negative pattern
    t.assert_equals(t.private.pattern_filter({'!toto'}, 'toto'), false)
    t.assert_equals(t.private.pattern_filter({'!t.t.'}, 'tutu'), false)
    t.assert_equals(t.private.pattern_filter({'!toto'}, 'tutu'), true)
    t.assert_equals(t.private.pattern_filter({'!toto'}, 'yyytotoxxx'), false)
    t.assert_equals(t.private.pattern_filter({'!tutu', '!toto'}, 'yyytotoxxx'), false)
    t.assert_equals(t.private.pattern_filter({'!tutu', '!toto'}, 'tutu'), false)
    t.assert_equals(t.private.pattern_filter({'!tutu', '!to..'}, 'yyytoxxx'), false)

    -- combine patterns
    t.assert_equals(t.private.pattern_filter({'foo'}, 'foo'), true)
    t.assert_equals(t.private.pattern_filter({'foo', '!foo'}, 'foo'), false)
    t.assert_equals(t.private.pattern_filter({'foo', '!foo', 'foo'}, 'foo'), true)
    t.assert_equals(t.private.pattern_filter({'foo', '!foo', 'foo', '!foo'}, 'foo'), false)

    t.assert_equals(t.private.pattern_filter({'!foo'}, 'foo'), false)
    t.assert_equals(t.private.pattern_filter({'!foo', 'foo'}, 'foo'), true)
    t.assert_equals(t.private.pattern_filter({'!foo', 'foo', '!foo'}, 'foo'), false)
    t.assert_equals(t.private.pattern_filter({'!foo', 'foo', '!foo', 'foo'}, 'foo'), true)

    t.assert_equals(t.private.pattern_filter({'f..', '!foo', '__foo__'}, 'toto'), false)
    t.assert_equals(t.private.pattern_filter({'f..', '!foo', '__foo__'}, 'fii'), true)
    t.assert_equals(t.private.pattern_filter({'f..', '!foo', '__foo__'}, 'foo'), false)
    t.assert_equals(t.private.pattern_filter({'f..', '!foo', '__foo__'}, '__foo__'), true)

    t.assert_equals(t.private.pattern_filter({'!f..', 'foo', '!__foo__'}, 'toto'), false)
    t.assert_equals(t.private.pattern_filter({'!f..', 'foo', '!__foo__'}, 'fii'), false)
    t.assert_equals(t.private.pattern_filter({'!f..', 'foo', '!__foo__'}, 'foo'), true)
    t.assert_equals(t.private.pattern_filter({'!f..', 'foo', '!__foo__'}, '__foo__'), false)
end

function g.test_filter_tests()
    local dummy = function() end
    local testset = {
        {name = 'toto.foo', dummy}, {name = 'toto.bar', dummy},
        {name = 'tutu.foo', dummy}, {name = 'tutu.bar', dummy},
        {name = 'tata.foo', dummy}, {name = 'tata.bar', dummy},
        {name = 'foo.bar', dummy}, {name = 'foobar.test', dummy},
  }

    -- default action: include everything
    local included, excluded = t.LuaUnit.filter_tests(testset, nil)
    t.assert_equals(#included, 8)
    t.assert_equals(excluded, {})

    -- single exclude pattern (= select anything not matching "bar")
    included, excluded = t.LuaUnit.filter_tests(testset, {'!bar'})
    t.assert_equals(included, {testset[1], testset[3], testset[5]})
    t.assert_equals(#excluded, 5)

    -- single include pattern
    included, excluded = t.LuaUnit.filter_tests(testset, {'t.t.'})
    t.assert_equals(#included, 6)
    t.assert_equals(excluded, {testset[7], testset[8]})

    -- single include and exclude patterns
    included, excluded = t.LuaUnit.filter_tests(testset, {'foo', '!test'})
    t.assert_equals(included, {testset[1], testset[3], testset[5], testset[7]})
    t.assert_equals(#excluded, 4)

    -- multiple (specific) includes
    included, excluded = t.LuaUnit.filter_tests(testset, {'toto', 'tutu'})
    t.assert_equals(included, {testset[1], testset[2], testset[3], testset[4]})
    t.assert_equals(#excluded, 4)

    -- multiple excludes
    included, excluded = t.LuaUnit.filter_tests(testset, {'!tata', '!%.bar'})
    t.assert_equals(included, {testset[1], testset[3], testset[8]})
    t.assert_equals(#excluded, 5)

    -- combined test
    included, excluded = t.LuaUnit.filter_tests(testset, {'t[oai]', 'bar$', 'test', '!%.b', '!tutu'})
    t.assert_equals(included, {testset[1], testset[5], testset[8]})
    t.assert_equals(#excluded, 5)

    --[[ Combining positive and negative filters ]]--
    included, excluded = t.LuaUnit.filter_tests(testset, {'foo', 'bar', '!t.t.', '%.bar'})
    t.assert_equals(included, {testset[2], testset[4], testset[6], testset[7], testset[8]})
    t.assert_equals(#excluded, 3)
end

function g.test_str_match()
    t.assert_equals(t.private.str_match('toto', 't.t.'), true)
    t.assert_equals(t.private.str_match('toto', 't.t.', 1, 4), true)
    t.assert_equals(t.private.str_match('toto', 't.t.', 2, 5), false)
    t.assert_equals(t.private.str_match('toto', '.t.t.'), false)
    t.assert_equals(t.private.str_match('ototo', 't.t.'), false)
    t.assert_equals(t.private.str_match('totot', 't.t.'), false)
    t.assert_equals(t.private.str_match('ototot', 't.t.'), false)
    t.assert_equals(t.private.str_match('ototot', 't.t.',2,3), false)
    t.assert_equals(t.private.str_match('ototot', 't.t.',2,5), true)
    t.assert_equals(t.private.str_match('ototot', 't.t.',2,6), false)
end

function g.test_expand_group()
    t.assert_equals(t.LuaUnit:expand_group({}), {})

    local MyTestToto1 = {name = 'MyTestToto1'}
    MyTestToto1.test1 = function() end
    MyTestToto1.testb = function() end
    MyTestToto1.test3 = function() end
    MyTestToto1.testa = function() end
    MyTestToto1.test2 = function() end
    MyTestToto1.not_test = function() end
    t.assert_equals(fun.iter(t.LuaUnit:expand_group(MyTestToto1)):map(function(x) return x.name end):totable(), {
        'MyTestToto1.test1',
        'MyTestToto1.test2',
        'MyTestToto1.test3',
        'MyTestToto1.testa',
        'MyTestToto1.testb',
  })
end

function g.test_xml_escape()
    t.assert_equals(t.private.xml_escape('abc'), 'abc')
    t.assert_equals(t.private.xml_escape('a"bc'), 'a&quot;bc')
    t.assert_equals(t.private.xml_escape("a'bc"), 'a&apos;bc')
    t.assert_equals(t.private.xml_escape("a<b&c>"), 'a&lt;b&amp;c&gt;')
end

function g.test_xml_c_data_escape()
    t.assert_equals(t.private.xml_c_data_escape('abc'), 'abc')
    t.assert_equals(t.private.xml_c_data_escape('a"bc'), 'a"bc')
    t.assert_equals(t.private.xml_c_data_escape("a'bc"), "a'bc")
    t.assert_equals(t.private.xml_c_data_escape("a<b&c>"), 'a<b&c>')
    t.assert_equals(t.private.xml_c_data_escape("a<b]]>--"), 'a<b]]&gt;--')
end

function g.test_hasNewline()
    t.assert_equals(t.private.has_new_line(''), false)
    t.assert_equals(t.private.has_new_line('abc'), false)
    t.assert_equals(t.private.has_new_line('ab\nc'), true)
end

function g.test_stripStackTrace()
    local realStackTrace=[[stack traceback:
    example_with_luaunit.lua:130: in function 'test2_withFailure'
    ./luatest/luaunit.lua:1449: in function <./luatest/luaunit.lua:1449>
    [C]: in function 'xpcall'
    ./luatest/luaunit.lua:1449: in function 'protected_call'
    ./luatest/luaunit.lua:1508: in function 'exec_one_function'
    ./luatest/luaunit.lua:1596: in function 'run_suite_by_instances'
    ./luatest/luaunit.lua:1660: in function 'run_suite_by_names'
    ./luatest/luaunit.lua:1736: in function 'run_suite']]


    local realStackTrace2=[[stack traceback:
    ./luatest/luaunit.lua:545: in function 't.assert_equals'
    example_with_luaunit.lua:58: in function 'TestToto.test7'
    ./luatest/luaunit.lua:1517: in function <./luatest/luaunit.lua:1517>
    [C]: in function 'xpcall'
    ./luatest/luaunit.lua:1517: in function 'protected_call'
    ./luatest/luaunit.lua:1578: in function 'exec_one_function'
    ./luatest/luaunit.lua:1677: in function 'run_suite_by_instances'
    ./luatest/luaunit.lua:1730: in function 'run_suite_by_names'
    ./luatest/luaunit.lua:1806: in function 'run_suite']]

    local realStackTrace3 = [[stack traceback:
    luaunit2/example_with_luaunit.lua:124: in function 'test1_withFailure'
    luaunit2/luatest/luaunit.lua:1532: in function <luaunit2/luatest/luaunit.lua:1532>
    [C]: in function 'xpcall'
    luaunit2/luatest/luaunit.lua:1532: in function 'protected_call'
    luaunit2/luatest/luaunit.lua:1591: in function 'exec_one_function'
    luaunit2/luatest/luaunit.lua:1679: in function 'run_suite_by_instances'
    luaunit2/luatest/luaunit.lua:1743: in function 'run_suite_by_names'
    luaunit2/luatest/luaunit.lua:1819: in function 'run_suite']]


    local strippedStackTrace=t.private.strip_luaunit_trace(realStackTrace)
    -- print(strippedStackTrace)

    local expectedStackTrace=[[stack traceback:
    example_with_luaunit.lua:130: in function 'test2_withFailure']]
    t.assert_equals(strippedStackTrace, expectedStackTrace)

    strippedStackTrace=t.private.strip_luaunit_trace(realStackTrace2)
    expectedStackTrace=[[stack traceback:
    example_with_luaunit.lua:58: in function 'TestToto.test7']]
    t.assert_equals(strippedStackTrace, expectedStackTrace)

    strippedStackTrace=t.private.strip_luaunit_trace(realStackTrace3)
    expectedStackTrace=[[stack traceback:
    luaunit2/example_with_luaunit.lua:124: in function 'test1_withFailure']]
    t.assert_equals(strippedStackTrace, expectedStackTrace)


end

function g.test_eps_value()
    -- calculate epsilon
    local local_eps = 1.0
    while (1.0 + 0.5 * local_eps) ~= 1.0 do
        local_eps = 0.5 * local_eps
    end
    -- print(local_eps, t.EPS)
    t.assert_equals(local_eps, t.EPS)
end

