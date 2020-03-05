# luatest

[![Build Status](https://travis-ci.com/tarantool/luatest.svg?branch=master)](https://travis-ci.com/tarantool/luatest)

Tool for testing tarantool applications.

Highlights:

- executable to run tests in directory or specific files,
- before/after suite hooks,
- before/after test group hooks,
- [output capturing](#capturing-output),
- [helpers](#test-helpers) for testing tarantool applications,
- [luacov integration](#luacov-integration).

## Requirements

- Tarantool (it requires tarantool-specific `fio` module and `ffi` from LuaJIT).

## Installation

```
tarantoolctl rocks install luatest

.rocks/bin/luatest --help # list available options
```

## Usage

Define tests.

```lua
-- test/feature_test.lua
local t = require('luatest')
local g = t.group('feature')
-- Default name is inferred from caller filename when possible.
-- For `test/a/b/c_d_test.lua` it will be `a.b.c_d`.
-- So `local g = t.group()` works the same way.

-- Tests. All properties with name staring with `test` are treated as test cases.
g.test_example_1 = function() ... end
g.test_example_n = function() ... end

-- Define suite hooks
t.before_suite(function() ... end)
t.before_suite(function() ... end)

-- Hooks to run once for tests group
g.before_all(function() ... end)
g.after_all(function() ... end)

-- Hooks to run for each test in group
g.before_each(function() ... end)
g.after_each(function() ... end)

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
luatest feature other.test_example_2  # by group or test name
luatest --help # list available options
```

Luatest automatically requires `test/helper.lua` file if it's present.
You can configure luatest or run any bootstrap code there.

See test directory template in
[cartridge-cli repo](https://github.com/tarantool/cartridge-cli/tree/master/templates/cartridge/test)
or in its [getting-started example](https://github.com/tarantool/cartridge-cli/tree/master/examples/getting-started-app/test).

## Tests order

Use the `--shuffle` option to tell luatest how to order the tests.
The available ordering schemes are `group`, `all` and `none`.

`group` shuffles tests within the groups.

`all` randomizes execution order across all available tests.
Be careful: `before_all/after_all` hooks run always when test group is changed,
so it may run multiple time.

`none` is the default, which executes examples within the group in the order they
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
-- test/helper.lua
local t = require('luatest')
t.configure({shuffle = 'group'})
```

## List of luatest functions

| Assertions |  |
| :--- | --- |
| `assert (value[, message])` | Check that value is truthy. |
| `assert_almost_equals (actual, expected, margin[, message])` | Check that two floats are close by margin. |
| `assert_covers (actual, expected[, message])` | Checks that actual map includes expected one. |
| `assert_equals (actual, expected[, message[, deep_analysis]])` | Check that two values are equal. |
| `assert_error (fn, ...)` | Check that calling fn raises an error. |
| `assert_error_msg_contains (expected_partial, fn, ...)` | |
| `assert_error_msg_content_equals (expected, fn, ...)` | Strips location info from message text. |
| `assert_error_msg_equals (expected, fn, ...)` | Checks full error: location and text. |
| `assert_error_msg_matches (pattern, fn, ...)` | |
| `assert_eval_to_false (value[, message])` | Alias for assert_not. |
| `assert_eval_to_true (value[, message])` | Alias for assert. |
| `assert_items_include (actual, expected[, message])` | Checks that actual includes all items of expected. |
| `assert_is (actual, expected[, message])` | Check that values are the same. |
| `assert_is_not (actual, expected[, message])` | Check that values are not the same. |
| `assert_items_equals (actual, expected[, message])` | Checks equality of tables regardless of the order of elements. |
| `assert_nan (value[, message])` | |
| `assert_not (value[, message])` | Check that value is falsy. |
| `assert_not_almost_equals (actual, expected, margin[, message])` | Check that two floats are not close by margin. |
| `assert_not_covers (actual, expected[, message])` | Checks that map does not contain the other one. |
| `assert_not_equals (actual, expected[, message])` | Check that two values are not equal. |
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

-- This method throws error when response status is outside of then range 200..299.
-- To change this behaviour, path `raise = false`:
t.assert_equals(server:http_request('get', '/not_found', {raise = false}).status, 404)
t.assert_error(function() server:http_request('get', '/not_found') end)

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

## luacov integration

- Install [luacov](https://github.com/keplerproject/luacov) with `tarantoolctl rocks install luacov`
- Configure it with `.luacov` file
- Clean old reports `rm -f luacov.*.out*`
- Run luatest with `--coverage` option
- Generate report with `.rocks/bin/luacov .`
- Show summary with `grep -A999 '^Summary' luacov.report.out`

When running integration tests with coverage collector enabled, luatest
automatically starts new tarantool instances with luacov enabled.
So coverage is collected from all the instances.
However this has some limitations:

- It works only for instances started with `Server` helper.
- Process command should be executable lua file or tarantool with script argument.
- Instance must be stopped with `server:stop()`, because this is the point where stats are saved.
- Don't save stats concurrently to prevent corruption.

## Development

- Check out the repo.
- Prepare makefile with `cmake .`.
- Install dependencies with `make bootstrap`.
- Run it with `make lint` before commiting changes.
- Run tests with `bin/luatest`.

## Contributing

Bug reports and pull requests are welcome on at
https://github.com/tarantool/luatest.

## License

MIT
