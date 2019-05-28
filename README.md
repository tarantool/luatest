# luatest

Tool for testing tarantool applications.

This rock is based on [https://github.com/bluebird75/luaunit](luanit) and additionaly provides:

- executable to run tests in directory or specific files,
- before/after suite hooks,
- before/after test group hooks,
- output capturing.

Please refer to [https://luaunit.readthedocs.io/en/latest/](luanit docs) for original features and examples.

## Requirements

- Tarantool (it requires tarantool-specific `fio` module and `ffi` from LuaJIT).

## Usage

Define tests.

```lua
-- test/feature_test.lua
local luatest = require('luatest')
local t = luatest.group('feature')

-- Define suite hooks. can be called multiple times to define hooks from different files
luatest.before_suite(function() ... end)
luatest.before_suite(function() ... end)

-- Hooks to run once for tests group
-- This hooks run always when test class is changed.
-- So it may run multiple times when --shuffle otion is used.
t.before_all = function() ... end
t.after_all = function() ... end

-- Hooks to run for each test in group
t.setup = function() ... end
t.teardown = function() ... end

-- Tests. All properties with name staring with `test` are treated as test cases.
t.test_example_1 = function() ... end
t.test_example_n = function() ... end

-- test/other_test.lua
local luatest = require('luatest')
local t = luatest.group('other')
-- ...
t.test_example_2 = function() ... end
t.test_example_m = function() ... end
```

Run them.

```
luatest                               # all in ./test direcroy
luatest test/feature_test.lua         # by file
luatest test/integration              # all within directory
luatest test/ -f                      # luaunit options can be passed after test path
luatest feature other.test_example_2  # by group or test name
```

If `luatest` executable does not appear in $PATH after installing the rock,
it can be found in `.rocks/bin/luatest`.

## Capturing output

By default runner captures all stdout/stderr output and shows it only for failed tests.
Capturing can be disabled with `-c` flag.

## Known issues

- When `before_all/after_all` hook fails with error, all other tests even from other classes
are not executed.
- Process hangs when there is a lot of output within single test.

## Development

- Install luacheck with `luarocks install luacheck`.
- Run it with `luacheck ./` before commiting changes.
- Run tests with `bin/luatest`.

## Contributing

Bug reports and pull requests are welcome on at
https://github.com/tarantool/luatest.

## License

MIT
