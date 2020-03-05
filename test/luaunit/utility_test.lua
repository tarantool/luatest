local t = require('luatest')
local g = t.group()

local fun = require('fun')
local Runner = require('luatest.runner')
local utils = require('luatest.utils')

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

local sorted_pairs = require('luatest.sorted_pairs')

function g.test_genSortedIndex()
    local subject = function(x)
        local _, state = sorted_pairs(x)
        return state.sortedIdx
    end
    t.assert_equals(subject({2, 5, 7}), {1,2,3})
    t.assert_equals(subject({a='1', h='2', c='3'}), {'a', 'c', 'h'})
    t.assert_equals(subject({1, 'z', a='1', h='2', c='3'}), {1, 2, 'a', 'c', 'h'})
    t.assert_equals(
        subject({b=4, a=3, true, foo="bar", nil, bar=false, 42, c=5}),
        {1, 3, 'a', 'b', 'bar', 'c', 'foo'}
    )
end

function g.test_sorted_nextWorks()
    local t1 = {}
    t1['aaa'] = 'abc'
    t1['ccc'] = 'def'
    t1['bbb'] = 'cba'

    -- mimic semantics of "generic for" loop
    local sorted_next, state = sorted_pairs(t1)

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
    for _, val in sorted_pairs(t1) do table.insert(tested, val) end
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
    _, state1 = sorted_pairs(t1)
    sorted_next, state2 = sorted_pairs(t2)

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

    utils.randomize_table(tab)
    t.assert_equals(#tab, n)
    t.assert_not_equals(tab, tref)
    table.sort(tab)
    t.assert_equals(tab, tref)
end

function g.test_equals_for_recursive_tables()
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

local mismatch_formatter = require('luatest.mismatch_formatter')

function g.test_suitableForMismatchFormatting()
    local subject = mismatch_formatter.format
    t.assert_not(subject({1,2}, {2,1}))
    t.assert_not(subject(nil, {1,2,3}))
    t.assert_not(subject({1,2,3}, {}))
    t.assert_not(subject("123", "123"))
    t.assert_not(subject("123", "123"))
    t.assert_not(subject({'a','b','c'}, {'c', 'b', 'a'}))
    t.assert_not(subject({1,2,3, toto='tutu'}, {1,2,3, toto='tata', tutu="bloup"}))
    t.assert_not(subject({1,2,3, [5]=1000}, {1,2,3}))

    local i=0
    local l1, l2={}, {}
    while i <= mismatch_formatter.LIST_DIFF_ANALYSIS_THRESHOLD + 1 do
        i = i + 1
        table.insert(l1, i)
        table.insert(l2, i+1)
    end

    t.assert(subject(l1, l2))
end


function g.test_diffAnalysisThreshold()
    local subject = mismatch_formatter.format
    local threshold =  mismatch_formatter.LIST_DIFF_ANALYSIS_THRESHOLD
    t.assert_not(subject(range(1,threshold-1), range(1,threshold-2)))
    t.assert(subject(range(1,threshold),   range(1,threshold)))

    t.assert_not(subject(range(1,threshold-1), range(1,threshold-2), false))
    t.assert_not(subject(range(1,threshold),   range(1,threshold),   false))

    t.assert(subject(range(1,threshold-1), range(1,threshold-2), true))
    t.assert(subject(range(1,threshold),   range(1,threshold),   true))
end

local pp = require('luatest.pp')

function g.test_table_ref()
    local subject = pp.table_ref
    local t1 = {'1','2'}
    t.assert_str_matches(tostring(t1), 'table: 0?x?[%x]+')
    t.assert_str_matches(subject(t1), 'table: 0?x?[%x]+')

    local ts = function(tab) return tab[1]..tab[2] end
    local mt = {__tostring = ts}
    setmetatable(t1, mt)
    t.assert_str_matches(tostring(t1), '12')
    t.assert_str_matches(subject(t1), 'table: 0?x?[%x]+')
end

function g.test_prettystr_numbers()
    t.assert_equals(pp.tostring(1), "1")
    t.assert_equals(pp.tostring(1.0), "1")
    t.assert_equals(pp.tostring(1.1), "1.1")
    t.assert_equals(pp.tostring(1/0), "#Inf")
    t.assert_equals(pp.tostring(-1/0), "-#Inf")
    t.assert_equals(pp.tostring(0/0), "#NaN")
end

function g.test_prettystr_strings()
    t.assert_equals(pp.tostring('x\0'), '"x\\0"')
    t.assert_equals(pp.tostring('abc'), '"abc"')
    t.assert_equals(pp.tostring('ab\ncd'), '"ab\\\ncd"')
    t.assert_equals(pp.tostring('ab"cd'), '"ab\\"cd"')
    t.assert_equals(pp.tostring("ab'cd"), '"ab\'cd"')
end

function g.test_prettystr_tables1()
    t.assert_equals(pp.tostring({1,2,3}), "{1, 2, 3}")
    t.assert_equals(pp.tostring({a=1,bb=2,ab=3}), '{a = 1, ab = 3, bb = 2}')
    t.assert_equals(pp.tostring({[{}] = 1}), '{[{}] = 1}')
    t.assert_equals(pp.tostring({1, [{}] = 1, 2}), '{1, 2, [{}] = 1}')
    t.assert_equals(pp.tostring({1, [{one=1}] = 1, 2, "test", false}), '{1, 2, "test", false, [{one = 1}] = 1}')
end

function g.test_prettystr_tables2()
    -- test the (private) key string formatting within _table_tostring()
    t.assert_equals(pp.tostring({a = 1}), '{a = 1}')
    t.assert_equals(pp.tostring({a0 = 2}), '{a0 = 2}')
    t.assert_equals(pp.tostring({['a0!'] = 3}), '{["a0!"] = 3}')
    t.assert_equals(pp.tostring({["foo\nbar"] = 1}), [[{["foo\
bar"] = 1}]])
    t.assert_equals(pp.tostring({["foo'bar"] = 2}), [[{["foo'bar"] = 2}]])
    t.assert_equals(pp.tostring({['foo"bar'] = 3}), [[{["foo\"bar"] = 3}]])
end

function g.test_prettystr_tables3()
    -- test with a table containing a metatable for __tostring
    local t1 = {'1','2'}
    t.assert_str_matches(tostring(t1), 'table: 0?x?[%x]+')
    t.assert_equals(pp.tostring(t1), '{"1", "2"}')

    -- add metatable
    local function ts(tab) return string.format('Point<%s,%s>', tab[1], tab[2]) end
    setmetatable(t1, {__tostring = ts})

    t.assert_equals(tostring(t1), 'Point<1,2>')
    t.assert_equals(pp.tostring(t1), 'Point<1,2>')

    local function ts2(tab)
        return string.format('Point:\n    x=%s\n    y=%s', tab[1], tab[2])
    end

    local t2 = {'1','2'}
    setmetatable(t2, {__tostring = ts2})

    t.assert_equals(tostring(t2), [[Point:
    x=1
    y=2]])
    t.assert_equals(pp.tostring(t2), [[Point:
    x=1
    y=2]])

    -- nested table
    local t3 = {'3', t1}
    t.assert_equals(pp.tostring(t3), [[{"3", Point<1,2>}]])

    local t4 = {'3', t2}
    t.assert_equals(pp.tostring(t4), [[{"3", Point:
        x=1
        y=2}]])

    local t5 = {1,2,{3,4},string.rep('W', pp.LINE_LENGTH), t2, 33}
    t.assert_equals(pp.tostring(t5), [[{
    1,
    2,
    {3, 4},
    "]]..string.rep('W', pp.LINE_LENGTH)..[[",
    Point:
        x=1
        y=2,
    33,
}]])

    local t6 = {}
    local function t6_tostring() end
    setmetatable(t6, {__tostring = t6_tostring})
    t.assert_equals(pp.tostring(t6), '<invalid tostring() result: "nil" >')
end

function g.test_prettystr_adv_tables()
    local t1 = {1,2,3,4,5,6}
    t.assert_equals(pp.tostring(t1), "{1, 2, 3, 4, 5, 6}")

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
    t.assert_equals(pp.tostring(t2), table.concat({
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

    local t2bis = {1,2,3,'12345678901234567890123456789012345678901234567890123456789012345678901234567890', 4,5,6}
    t.assert_equals(pp.tostring(t2bis), [[{
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
    t.assert_equals(pp.tostring(t3), [[{
    l1a = {
        l2a = {l3a = "012345678901234567890123456789012345678901234567890123456789"},
        l2b = "bbb",
    },
    l1b = 4,
}]])

    local t4 = {a=1, b=2, c=3}
    t.assert_equals(pp.tostring(t4), '{a = 1, b = 2, c = 3}')

    local t5 = {t1, t2, t3}
    t.assert_equals(pp.tostring(t5), [[{
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
    t.assert_equals(pp.tostring(t6),[[{
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
    t.assert_str_matches(pp.tostring(tab), "(<table: 0?x?[%x]+>) {__index = %1}")

    local t1 = {}
    local t2 = {}
    t1.t2 = t2
    t2.t1 = t1
    local t3 = {t1 = t1, t2 = t2}
    t.assert_str_matches(pp.tostring(t1), "(<table: 0?x?[%x]+>) {t2 = (<table: 0?x?[%x]+>) {t1 = %1}}")
    t.assert_str_matches(pp.tostring(t3), [[(<table: 0?x?[%x]+>) {
    t1 = (<table: 0?x?[%x]+>) {t2 = (<table: 0?x?[%x]+>) {t1 = %2}},
    t2 = %3,
}]])

    local t4 = {1,2}
    local t5 = {3,4,t4}
    t4[3] = t5
    t.assert_str_matches(pp.tostring(t5), "(<table: 0?x?[%x]+>) {3, 4, (<table: 0?x?[%x]+>) {1, 2, %1}}")

    local t6 = {}
    t6[t6] = 1
    t.assert_str_matches(pp.tostring(t6), "(<table: 0?x?[%x]+>) {%1=1}")

    local t7, t8 = {"t7"}, {"t8"}
    t7[t8] = 1
    t8[t7] = 2
    t.assert_str_matches(pp.tostring(t7), '(<table: 0?x?[%x]+>) {"t7", %[(<table: 0?x?[%x]+>) {"t8", %1=2}%] = 1}')

    local t9 = {"t9", {}}
    t9[{t9}] = 1

    t.assert_str_matches(pp.tostring(t9, true), [[(<table: 0?x?[%x]+>) {
?%s*"t9",
?%s*(<table: 0?x?[%x]+>) {},
?%s*%[%s*(<table: 0?x?[%x]+>) {%1}%] = 1,?
?}]])
end

function g.test_prettystr_pairs()
    local subject = pp.tostring_pair
    local foo, bar, str1, str2 = nil, nil

    -- test all combinations of: foo = nil, "foo", "fo\no" (embedded
    -- newline); and bar = nil, "bar", "bar\n" (trailing newline)

    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, "nil")
    t.assert_equals(str2, "nil")
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, "nil_B")
    t.assert_equals(str2, "nil")

    bar = "bar"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, "nil")
    t.assert_equals(str2, '"bar"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, "nil_B")
    t.assert_equals(str2, '"bar"')

    bar = "bar\n"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, "\nnil")
    t.assert_equals(str2, '\n"bar\\\n"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, "\nnil_A")
    t.assert_equals(str2, '\n"bar\\\n"')

    foo = "foo"
    bar = nil
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '"foo"')
    t.assert_equals(str2, "nil")
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '"foo"_B')
    t.assert_equals(str2, "nil")

    bar = "bar"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '"foo"')
    t.assert_equals(str2, '"bar"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '"foo"_B')
    t.assert_equals(str2, '"bar"')

    bar = "bar\n"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '\n"foo"')
    t.assert_equals(str2, '\n"bar\\\n"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"foo"_A')
    t.assert_equals(str2, '\n"bar\\\n"')

    foo = "fo\no"
    bar = nil
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '\n"fo\\\no"')
    t.assert_equals(str2, "\nnil")
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\\\no"_A')
    t.assert_equals(str2, "\nnil")

    bar = "bar"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '\n"fo\\\no"')
    t.assert_equals(str2, '\n"bar"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\\\no"_A')
    t.assert_equals(str2, '\n"bar"')

    bar = "bar\n"
    str1, str2 = subject(foo, bar)
    t.assert_equals(str1, '\n"fo\\\no"')
    t.assert_equals(str2, '\n"bar\\\n"')
    str1, str2 = subject(foo, bar, "_A", "_B")
    t.assert_equals(str1, '\n"fo\\\no"_A')
    t.assert_equals(str2, '\n"bar\\\n"')
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
    local subject = Runner.split_test_method_name
    t.assert_equals({subject('toto')}, {nil, 'toto'})
    t.assert_equals({subject('toto.tutu')}, {'toto', 'tutu'})
end

function g.test_is_test_name()
    local subject = Runner.is_test_name
    t.assert_equals(subject('testToto'), true)
    t.assert_equals(subject('TestToto'), true)
    t.assert_equals(subject('TESTToto'), true)
    t.assert_equals(subject('xTESTToto'), false)
    t.assert_equals(subject(''), false)
end

function g.test_parse_cmd_line()
    local subject = Runner.parse_cmd_line
    local function assert_subject(args, expected)
        t.assert_equals(subject(args), expected)
    end
    --test names
    assert_subject(nil, {})
    assert_subject({'someTest'}, {test_names={'someTest'}})
    assert_subject({'someTest', 'someOtherTest'}, {test_names={'someTest', 'someOtherTest'}})

    local VERBOSITY = require('luatest.output.generic').VERBOSITY
    -- verbosity
    assert_subject({'--verbose'}, {verbosity=VERBOSITY.VERBOSE})
    assert_subject({'-v'}, {verbosity=VERBOSITY.VERBOSE})
    assert_subject({'--quiet'}, {verbosity=VERBOSITY.QUIET})
    assert_subject({'-q'}, {verbosity=VERBOSITY.QUIET})
    assert_subject({'-v', '-q'}, {verbosity=VERBOSITY.QUIET})

    --output
    assert_subject({'--output', 'toto'}, {output='toto'})
    assert_subject({'-o', 'toto'}, {output='toto'})
    t.assert_error_msg_contains('Missing argument after -o', subject, {'-o',})

    --name
    assert_subject({'--name', 'toto'}, {output_file_name='toto'})
    assert_subject({'-n', 'toto'}, {output_file_name='toto'})
    t.assert_error_msg_contains('Missing argument after -n', subject, {'-n',})

    --patterns
    assert_subject({'--pattern', 'toto'}, {tests_pattern={'toto'}})
    assert_subject({'-p', 'toto'}, {tests_pattern={'toto'}})
    assert_subject({'-p', 'tutu', '-p', 'toto'}, {tests_pattern={'tutu', 'toto'}})
    t.assert_error_msg_contains('Missing argument after -p', subject, {'-p',})
    assert_subject({'--exclude', 'toto'}, {tests_pattern={'!toto'}})
    assert_subject({'-x', 'toto'}, {tests_pattern={'!toto'}})
    assert_subject({'-x', 'tutu', '-x', 'toto'}, {tests_pattern={'!tutu', '!toto'}})
    assert_subject({'-x', 'tutu', '-p', 'foo', '-x', 'toto'}, {tests_pattern={'!tutu', 'foo', '!toto'}})
    t.assert_error_msg_contains('Missing argument after -x', subject, {'-x',})

    -- repeat
    assert_subject({'--repeat', '123'}, {exe_repeat=123})
    assert_subject({'-r', '123'}, {exe_repeat=123})
    t.assert_error_msg_contains('Invalid value for -r option. Integer required', subject, {'-r', 'bad'})
    t.assert_error_msg_contains('Missing argument after -r', subject, {'-r',})

    -- shuffle
    assert_subject({'--shuffle', 'all'}, {shuffle='all'})
    assert_subject({'-s', 'group'}, {shuffle='group'})

    --megamix
    assert_subject({'-p', 'toto', 'tutu', '-v', 'tata', '-o', 'tintin', '-p', 'tutu', 'prout', '-n', 'toto.xml'}, {
        tests_pattern = {'toto', 'tutu'},
        verbosity = VERBOSITY.VERBOSE,
        output = 'tintin',
        test_names = {'tutu', 'tata', 'prout'},
        output_file_name='toto.xml',
    })

    t.assert_error_msg_contains('option: -$', subject, {'-$',})
end

function g.test_pattern_filter()
    local subject = utils.pattern_filter
    t.assert_equals(subject(nil, 'toto'), true)
    t.assert_equals(subject({}, 'toto'), true)

    -- positive pattern
    t.assert_equals(subject({'toto'}, 'toto'), true)
    t.assert_equals(subject({'toto'}, 'yyytotoxxx'), true)
    t.assert_equals(subject({'tutu', 'toto'}, 'yyytotoxxx'), true)
    t.assert_equals(subject({'tutu', 'toto'}, 'tutu'), true)
    t.assert_equals(subject({'tutu', 'to..'}, 'yyytoxxx'), true)

    -- negative pattern
    t.assert_equals(subject({'!toto'}, 'toto'), false)
    t.assert_equals(subject({'!t.t.'}, 'tutu'), false)
    t.assert_equals(subject({'!toto'}, 'tutu'), true)
    t.assert_equals(subject({'!toto'}, 'yyytotoxxx'), false)
    t.assert_equals(subject({'!tutu', '!toto'}, 'yyytotoxxx'), false)
    t.assert_equals(subject({'!tutu', '!toto'}, 'tutu'), false)
    t.assert_equals(subject({'!tutu', '!to..'}, 'yyytoxxx'), false)

    -- combine patterns
    t.assert_equals(subject({'foo'}, 'foo'), true)
    t.assert_equals(subject({'foo', '!foo'}, 'foo'), false)
    t.assert_equals(subject({'foo', '!foo', 'foo'}, 'foo'), true)
    t.assert_equals(subject({'foo', '!foo', 'foo', '!foo'}, 'foo'), false)

    t.assert_equals(subject({'!foo'}, 'foo'), false)
    t.assert_equals(subject({'!foo', 'foo'}, 'foo'), true)
    t.assert_equals(subject({'!foo', 'foo', '!foo'}, 'foo'), false)
    t.assert_equals(subject({'!foo', 'foo', '!foo', 'foo'}, 'foo'), true)

    t.assert_equals(subject({'f..', '!foo', '__foo__'}, 'toto'), false)
    t.assert_equals(subject({'f..', '!foo', '__foo__'}, 'fii'), true)
    t.assert_equals(subject({'f..', '!foo', '__foo__'}, 'foo'), false)
    t.assert_equals(subject({'f..', '!foo', '__foo__'}, '__foo__'), true)

    t.assert_equals(subject({'!f..', 'foo', '!__foo__'}, 'toto'), false)
    t.assert_equals(subject({'!f..', 'foo', '!__foo__'}, 'fii'), false)
    t.assert_equals(subject({'!f..', 'foo', '!__foo__'}, 'foo'), true)
    t.assert_equals(subject({'!f..', 'foo', '!__foo__'}, '__foo__'), false)
end

function g.test_filter_tests()
    local subject = function(...)
        local result = Runner.filter_tests(...)
        return result[true], result[false]
    end
    local dummy = function() end
    local testset = {
        {name = 'toto.foo', dummy}, {name = 'toto.bar', dummy},
        {name = 'tutu.foo', dummy}, {name = 'tutu.bar', dummy},
        {name = 'tata.foo', dummy}, {name = 'tata.bar', dummy},
        {name = 'foo.bar', dummy}, {name = 'foobar.test', dummy},
    }

    -- default action: include everything
    local included, excluded = subject(testset, nil)
    t.assert_equals(#included, 8)
    t.assert_equals(excluded, {})

    -- single exclude pattern (= select anything not matching "bar")
    included, excluded = subject(testset, {'!bar'})
    t.assert_equals(included, {testset[1], testset[3], testset[5]})
    t.assert_equals(#excluded, 5)

    -- single include pattern
    included, excluded = subject(testset, {'t.t.'})
    t.assert_equals(#included, 6)
    t.assert_equals(excluded, {testset[7], testset[8]})

    -- single include and exclude patterns
    included, excluded = subject(testset, {'foo', '!test'})
    t.assert_equals(included, {testset[1], testset[3], testset[5], testset[7]})
    t.assert_equals(#excluded, 4)

    -- multiple (specific) includes
    included, excluded = subject(testset, {'toto', 'tutu'})
    t.assert_equals(included, {testset[1], testset[2], testset[3], testset[4]})
    t.assert_equals(#excluded, 4)

    -- multiple excludes
    included, excluded = subject(testset, {'!tata', '!%.bar'})
    t.assert_equals(included, {testset[1], testset[3], testset[8]})
    t.assert_equals(#excluded, 5)

    -- combined test
    included, excluded = subject(testset, {'t[oai]', 'bar$', 'test', '!%.b', '!tutu'})
    t.assert_equals(included, {testset[1], testset[5], testset[8]})
    t.assert_equals(#excluded, 5)

    --[[ Combining positive and negative filters ]]--
    included, excluded = subject(testset, {'foo', 'bar', '!t.t.', '%.bar'})
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
    local function subject(...)
        return Runner:expand_group(...)
    end

    t.assert_equals(subject({}), {})

    local MyTestToto1 = {name = 'MyTestToto1'}
    MyTestToto1.test1 = function() end
    MyTestToto1.testb = function() end
    MyTestToto1.test3 = function() end
    MyTestToto1.testa = function() end
    MyTestToto1.test2 = function() end
    MyTestToto1.not_test = function() end
    t.assert_equals(fun.iter(subject(MyTestToto1)):map(function(x) return x.name end):totable(), {
        'MyTestToto1.test1',
        'MyTestToto1.test2',
        'MyTestToto1.test3',
        'MyTestToto1.testa',
        'MyTestToto1.testb',
  })
end

local JUNitOutput = require('luatest.output.junit')

function g.test_xml_escape()
    local subject = JUNitOutput.xml_escape
    t.assert_equals(subject('abc'), 'abc')
    t.assert_equals(subject('a"bc'), 'a&quot;bc')
    t.assert_equals(subject("a'bc"), 'a&apos;bc')
    t.assert_equals(subject("a<b&c>"), 'a&lt;b&amp;c&gt;')
end

function g.test_xml_c_data_escape()
    local subject = JUNitOutput.xml_c_data_escape
    t.assert_equals(subject('abc'), 'abc')
    t.assert_equals(subject('a"bc'), 'a"bc')
    t.assert_equals(subject("a'bc"), "a'bc")
    t.assert_equals(subject("a<b&c>"), 'a<b&c>')
    t.assert_equals(subject("a<b]]>--"), 'a<b]]&gt;--')
end

function g.test_stripStackTrace()
    local subject = utils.strip_luatest_trace

    t.assert_equals(subject([[stack traceback:
    example_with_luaunit.lua:130: in function 'test2_withFailure'
    ./luatest/luaunit.lua:1449: in function <./luatest/luaunit.lua:1449>
    [C]: in function 'xpcall'
    ./luatest/luaunit.lua:1449: in function 'protected_call'
    ./luatest/luaunit.lua:1508: in function 'exec_one_function'
    ./luatest/luaunit.lua:1596: in function 'run_suite_by_instances'
    ./luatest/luaunit.lua:1660: in function 'run_suite_by_names'
    ./luatest/luaunit.lua:1736: in function 'run_suite']]
        ),
        [[stack traceback:
    example_with_luaunit.lua:130: in function 'test2_withFailure']]
    )


    t.assert_equals(subject([[stack traceback:
    ./luatest/luaunit.lua:545: in function 't.assert_equals'
    example_with_luaunit.lua:58: in function 'TestToto.test7'
    ./luatest/luaunit.lua:1517: in function <./luatest/luaunit.lua:1517>
    [C]: in function 'xpcall'
    ./luatest/luaunit.lua:1517: in function 'protected_call'
    ./luatest/luaunit.lua:1578: in function 'exec_one_function'
    ./luatest/luaunit.lua:1677: in function 'run_suite_by_instances'
    ./luatest/luaunit.lua:1730: in function 'run_suite_by_names'
    ./luatest/luaunit.lua:1806: in function 'run_suite']]
        ),
        [[stack traceback:
    example_with_luaunit.lua:58: in function 'TestToto.test7']]
    )

    t.assert_equals(subject([[stack traceback:
    luaunit2/example_with_luaunit.lua:124: in function 'test1_withFailure'
    luaunit2/luatest/luaunit.lua:1532: in function <luaunit2/luatest/luaunit.lua:1532>
    [C]: in function 'xpcall'
    luaunit2/luatest/luaunit.lua:1532: in function 'protected_call'
    luaunit2/luatest/luaunit.lua:1591: in function 'exec_one_function'
    luaunit2/luatest/luaunit.lua:1679: in function 'run_suite_by_instances'
    luaunit2/luatest/luaunit.lua:1743: in function 'run_suite_by_names'
    luaunit2/luatest/luaunit.lua:1819: in function 'run_suite']]
        ),
        [[stack traceback:
    luaunit2/example_with_luaunit.lua:124: in function 'test1_withFailure']]
    )
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

