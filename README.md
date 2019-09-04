# luatest

[![Build Status](https://travis-ci.com/tarantool/luatest.svg?branch=master)](https://travis-ci.com/tarantool/luatest)

Tool for testing tarantool applications.

This rock is based on [luanit](https://github.com/bluebird75/luaunit) and additionaly provides:

- executable to run tests in directory or specific files,
- before/after suite hooks,
- before/after test group hooks,
- output capturing.

Please refer to [luanit docs](https://luaunit.readthedocs.io/en/latest/) for original features and examples.

## Requirements

- Tarantool (it requires tarantool-specific `fio` module and `ffi` from LuaJIT).

## Usage

Define tests.

```lua
-- test/feature_test.lua
local t = require('luatest')
local g = t.group('feature')

-- Define suite hooks. can be called multiple times to define hooks from different files
t.before_suite(function() ... end)
t.before_suite(function() ... end)

-- Hooks to run once for tests group
-- This hooks run always when test class is changed.
-- So it may run multiple times when --shuffle option is used.
g.before_all = function() ... end
g.after_all = function() ... end

-- Hooks to run for each test in group
g.setup = function() ... end
g.teardown = function() ... end

-- Tests. All properties with name staring with `test` are treated as test cases.
g.test_example_1 = function() ... end
g.test_example_n = function() ... end

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
```

If `luatest` executable does not appear in $PATH after installing the rock,
it can be found in `.rocks/bin/luatest`.

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
- Process hangs when there is a lot of output within single test.

## Development

- Install dependencies with `make bootstrap`.
- Run it with `make lint` before commiting changes.
- Run tests with `make test` or `bin/luatest`.

## Contributing

Bug reports and pull requests are welcome on at
https://github.com/tarantool/luatest.

## License

MIT
