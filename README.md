# luatest

[![Build Status](https://travis-ci.com/tarantool/luatest.svg?branch=master)](https://travis-ci.com/tarantool/luatest)

Tool for testing tarantool applications.

This rock is based on [luanit](https://github.com/bluebird75/luaunit) and additionaly provides:

- executable to run tests in directory or specific files,
- before/after suite hooks,
- before/after test group hooks,
- [output capturing](#capturing-output),
- [test helpers](#test-helpers).

Please refer to [luanit docs](https://luaunit.readthedocs.io/en/latest/) for original features and examples.

## Requirements

- Tarantool (it requires tarantool-specific `fio` module and `ffi` from LuaJIT).

## Usage

Define tests.

```lua
-- test/feature_test.lua
local t = require('luatest')
local g = t.group('feature')

-- Tests. All properties with name staring with `test` are treated as test cases.
g.test_example_1 = function() ... end
g.test_example_n = function() ... end

-- Define suite hooks. can be called multiple times to define hooks from different files
t.before_suite(function() ... end)
t.before_suite(function() ... end)

-- Hooks to run once for tests group
g.before_all = function() ... end
g.after_all = function() ... end

-- Hooks to run for each test in group
g.setup = function() ... end
g.teardown = function() ... end

-- test/other_test.lua
local t = require('luatest')
local g = t.group('other')
-- ...
g.test_example_2 = function() ... end
g.test_example_m = function() ... end
```

Run them.

```
luatest                               # all in ./test direcroy
luatest test/feature_test.lua         # by file
luatest test/integration              # all within directory
luatest test/ -f                      # luaunit options are supported
luatest feature other.test_example_2  # by group or test name
luater --help                         # list available options
```

If `luatest` executable does not appear in $PATH after installing the rock,
it can be found in `.rocks/bin/luatest`.

## Tests order

Use the `--shuffle` option to tell luatest how to order the tests.
The available ordering schemes are `group`, `all` and `none`.

`group` is the default, which shuffles tests within the groups.

`all` randomizes execution order across all available tests.
Be careful: `before_all/after_all` hooks run always when test class is changed,
so it may run multiple time.

`none` executes examples within the group in the order they
are defined (eventually they are ordered by functions line numbers).

With `group` and `all` you can also specify a `seed` to reproduce specific order.

```
--shuffle none
--shuffle group
--shuffle all --seed 123
--shuffle all:123 # same as above
```

To change default order use:

```lua
local t = require('luatest')
t.defaults({shuffle = 'none'})
```

## List of luatest functions

| Assertions |  |
| :--- | --- |
| `assert (value[, message])` | Check that value is truthy. |
| `assert_almost_equals (actual, expected, margin[, message])` | Check that two floats are close by margin. |
| `assert_covers (actual, expected[, message])` | Checks that map contains the other one. |
| `assert_equals (actual, expected[, message[, deep_analysis]])` | Check that two values are equal. |
| `assert_error (fn, ...)` | Check that calling fn raises an error. |
| `assert_error_msg_contains (expected_partial, fn, ...)` | |
| `assert_error_msg_content_equals (expected, fn, ...)` | Strips location info from message text. |
| `assert_error_msg_equals (expected, fn, ...)` | Checks full error: location and text. |
| `assert_error_msg_matches (pattern, fn, ...)` | |
| `assert_eval_to_false (value[, message])` | Alias for assert_not. |
| `assert_eval_to_true (value[, message])` | Alias for assert. |
| `assert_is (actual, expected[, message])` | Check that values are the same. |
| `assert_items_equals (actual, expected[, message])` | Check that the items of table expected are contained in table actual. |
| `assert_nan (value[, message])` | |
| `assert_not (value[, message])` | Check that value is falsy. |
| `assert_not_almost_equals (actual, expected, margin[, message])` | Check that two floats are not close by margin. |
| `assert_not_covers (actual, expected[, message])` | Checks that map does not contain the other one. |
| `assert_not_equals (actual, expected[, message])` | Check that two values are not equal. |
| `assert_not_is (actual, expected[, message])` | Check that values are not the same. |
| `assert_not_nan (value[, message])` | |
| `assert_not_str_contains (actual, expected[, is_pattern[, message]])` | Case-sensitive strings comparison. |
| `assert_not_str_icontains (value, expected[, message])` | Case-insensitive strings comparison. |
| `assert_str_contains (value, expected[, is_pattern[, message]])` | Case-sensitive strings comparison. |
| `assert_str_icontains (value, expected[, message])` | Case-insensitive strings comparison. |
| `assert_str_matches (value, pattern[, start=1[, final=value:len()[, message]]])` | Verify a full match for the string. |
| `assert_type (value, expected_type[, message])` | Check value's type. |
| **Flow control** |  |
| `fail (message)` | Stops a test due to a failure. |
| `fail_if (condition, message)` | Stops a test due to a failure if condition is met. |
| `skip (message)` | Skip a running test. |
| `skip_if (condition, message)` | Skip a running test if condition is met. |
| `success ()` | Stops a test with a success. |
| `success_if (condition)` | Stops a test with a success if condition is met. |
| **Suite and groups** |  |
| `after_suite (fn)` | Add after suite hook. |
| `before_suite (fn)` | Add before suite hook. |
| `group (name)` | Create group of tests. |

## Capturing output

By default runner captures all stdout/stderr output and shows it only for failed tests.
Capturing can be disabled with `-c` flag.

## Test helpers

There are helpers to run tarantool applications and perform basic interaction with it.
If application follows configuration conventions it's possible to use
options to confegure server instance and helpers at the same time. For example
`http_port` is used to perform http request in tests and passed in `TARANTOOL_HTTP_PORT`
to server process.

```lua
local server = luatest.Server:new({
    command = '/path/to/executable.lua',
    -- arguments for process
    args = {'--no-bugs', '--fast'},
    -- additional envars to pass to process
    env = {SOME_FIELD = 'value'},
    -- passed as TARANTOOL_WORKDIR
    workdir = '/path/to/test/workdir',
    -- passed as TARANTOOL_HTTP_PORT, used in http_request
    http_port = 8080,
    -- passed as TARANTOOL_LISTEN, used in connect_net_box
    net_box_port = 3030,
    -- passed to net_box.connect in connect_net_box
    net_box_credentials = {user = 'username', password = 'secret'},
})
server:start()

-- http requests
server:http_request('get', '/path')
server:http_request('post', '/path', {body = 'text'})
server:http_request('post', '/path', {json = {field = value}})

-- using net_box
server:connect_net_box()
server.net_box:eval('return do_something(...)', {arg1, arg2})

server:stop()
```

`luatest.Process:start(path, args, env)` provides low-level interface to run any other application.

There are several small helpers for common actions:

```lua
luatest.helpers.uuid('ab', 2, 1) == 'abababab-0002-0000-0000-000000000001'

luatest.helpers.retrying({timeout = 1, delay = 0.1}, failing_function, arg1, arg2)
-- wait until server is up
luatest.helpers.retrying({}, function() server:http_request('get', '/status') end)
```

## Known issues

- When `before_all/after_all` hook fails with error, all other tests even from other classes
are not executed.

## Development

- Install dependencies with `make bootstrap`.
- Run it with `make lint` before commiting changes.
- Run tests with `make test` or `bin/luatest`.

## Contributing

Bug reports and pull requests are welcome on at
https://github.com/tarantool/luatest.

## License

MIT
