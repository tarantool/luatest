-------------------------------
Overview
-------------------------------

Tool for testing tarantool applications.

Highlights:

- executable to run tests in directory or specific files,
- before/after suite hooks,
- before/after test group hooks,
- `output capturing <Capturing output_>`_,
- `helpers <Test helpers_>`_ for testing tarantool applications,
- `luacov integration <luacov integration_>`_.

---------------------------------
Requirements
---------------------------------

- Tarantool (it requires tarantool-specific ``fio`` module and ``ffi`` from LuaJIT).

---------------------------------
Installation
---------------------------------

.. code-block:: bash

    tarantoolctl rocks install luatest
    .rocks/bin/luatest --help # list available options

---------------------------------
Usage
---------------------------------

Define tests.

.. code-block:: Lua

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

    -- Hooks to run for a specified test in group
    g.before_test('test_example_1', function() ... end)
    g.after_test('test_example_2', function() ... end)
    -- before_test runs after before_each
    -- after_test runs before after_each

    -- test/other_test.lua
    local t = require('luatest')
    local g = t.group('other')
    -- ...
    g.test_example_2 = function() ... end
    g.test_example_m = function() ... end

    -- Define parametrized groups
    local pg = t.group('pgroup', {{engine = 'memtx'}, {engine = 'vinyl'}})
    pg.test_example_3 = function(cg)
        -- Use cg.params here
        box.schema.space.create('test', {
            engine = cg.params.engine,
        })
    end

    -- Hooks can be specified for one parameter
    pg.before_all({engine = 'memtx'}, function() ... end)
    pg.before_each({engine = 'memtx'}, function() ... end)
    pg.before_test('test_example_3', {engine = 'vinyl'}, function() ... end)

Run tests from a path.

.. code-block:: bash

    luatest                               # run all tests from the ./test directory
    luatest test/integration              # run all tests from the specified directory
    luatest test/feature_test.lua         # run all tests from the specified file

Run tests from a group.

.. code-block:: bash

    luatest feature                       # run all tests from the specified group
    luatest other.test_example_2          # run one test from the specified group
    luatest feature other.test_example_2  # run tests by group and test name

Note that luatest recognizes an input parameter as a path only if it contains ``/``, otherwise, it will be considered
as a group name.

.. code-block:: bash

    luatest feature                       # considered as a group name
    luatest ./feature                     # considered as a path
    luatest feature/                      # considered as a path

You can also use ``-p`` option in combination with the examples above for running tests matching to some name pattern.

.. code-block:: bash

    luatest feature -p test_example       # run all tests from the specified group matching to the specified pattern

Luatest automatically requires ``test/helper.lua`` file if it's present.
You can configure luatest or run any bootstrap code there.

See the `getting-started example <https://github.com/tarantool/cartridge-cli/tree/master/examples/getting-started-app/test>`_
in cartridge-cli repo.

---------------------------------
Tests order
---------------------------------

Use the ``--shuffle`` option to tell luatest how to order the tests.
The available ordering schemes are ``group``, ``all`` and ``none``.

``group`` shuffles tests within the groups.

``all`` randomizes execution order across all available tests.
Be careful: ``before_all/after_all`` hooks run always when test group is changed,
so it may run multiple time.

``none`` is the default, which executes examples within the group in the order they
are defined (eventually they are ordered by functions line numbers).

With ``group`` and ``all`` you can also specify a ``seed`` to reproduce specific order.

.. code-block:: bash

    --shuffle none
    --shuffle group
    --shuffle all --seed 123
    --shuffle all:123 # same as above

To change default order use:

.. code-block:: Lua

    -- test/helper.lua
    local t = require('luatest')
    t.configure({shuffle = 'group'})


---------------------------------
List of luatest functions
---------------------------------

+--------------------------------------------------------------------------------------------------------------------+
| **Assertions**                                                                                                     |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert (value[, message])``                                      | Check that value is truthy.                   |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_almost_equals (actual, expected, margin[, message])``     | Check that two floats are close by margin.    |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_covers (actual, expected[, message])``                    | Checks that actual map includes expected one. |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_lt (left, right[, message])``                             | Compare numbers.                              |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_le (left, right[, message])``                             |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_gt (left, right[, message])``                             |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_ge (left, right[, message])``                             |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_equals (actual, expected[, message[, deep_analysis]])``   | Check that two values are equal.              |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_error (fn, ...)``                                         | Check that calling fn raises an error.        |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_error_msg_contains (expected_partial, fn, ...)``          |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_error_msg_content_equals (expected, fn, ...)``            | Strips location info from message text.       |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_error_msg_equals (expected, fn, ...)``                    | Checks full error: location and text.         |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_error_msg_matches (pattern, fn, ...)``                    |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_eval_to_false (value[, message])``                        | Alias for assert_not.                         |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_eval_to_true (value[, message])``                         | Alias for assert.                             |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_items_include (actual, expected[, message])``             | Checks that one table includes all items of   |
|                                                                    | another, irrespective of their keys.          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_is (actual, expected[, message])``                        | Check that values are the same.               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_is_not (actual, expected[, message])``                    | Check that values are not the same.           |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_items_equals (actual, expected[, message])``              | Checks that two tables contain the same items,|
|                                                                    | irrespective of their keys.                   |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_nan (value[, message])``                                  |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not (value[, message])``                                  | Check that value is falsy.                    |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_almost_equals (actual, expected, margin[, message])`` | Check that two floats are not close by margin |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_covers (actual, expected[, message])``                | Checks that map does not contain the other    |
|                                                                    | one.                                          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_equals (actual, expected[, message])``                | Check that two values are not equal.          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_nan (value[, message])``                              |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_str_contains (actual, expected[, is_pattern[,         | Case-sensitive strings comparison.            |
| message]])``                                                       |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_not_str_icontains (value, expected[, message])``          | Case-insensitive strings comparison.          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_str_contains (value, expected[, is_pattern[, message]])`` | Case-sensitive strings comparison.            |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_str_icontains (value, expected[, message])``              | Case-insensitive strings comparison.          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_str_matches (value, pattern[, start=1[, final=value:len() | Verify a full match for the string.           |
| [, message]]])``                                                   |                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``assert_type (value, expected_type[, message])``                  | Check value's type.                           |
+--------------------------------------------------------------------+-----------------------------------------------+
| **Flow control**                                                                                                   |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``fail (message)``                                                 | Stops a test due to a failure.                |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``fail_if (condition, message)``                                   | Stops a test due to a failure if condition    |
|                                                                    | is met.                                       |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``xfail (message)``                                                | Mark test as xfail.                           |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``xfail_if (condition, message)``                                  | Mark test as xfail if condition is met.       |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``skip (message)``                                                 | Skip a running test.                          |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``skip_if (condition, message)``                                   | Skip a running test if condition is met.      |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``success ()``                                                     | Stops a test with a success.                  |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``success_if (condition)``                                         | Stops a test with a success if condition      |
|                                                                    | is met.                                       |
+--------------------------------------------------------------------+-----------------------------------------------+
| **Suite and groups**                                                                                               |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``after_suite (fn)``                                               | Add after suite hook.                         |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``before_suite (fn)``                                              | Add before suite hook.                        |
+--------------------------------------------------------------------+-----------------------------------------------+
| ``group (name)``                                                   | Create group of tests.                        |
+--------------------------------------------------------------------+-----------------------------------------------+

.. _xfail:

---------------------------------
XFail
---------------------------------

The ``xfail`` mark makes test results to be interpreted vice versa: it's
threated as passed when an assertion fails, and it fails if no errors are
raised. It allows one to mark a test as temporarily broken due to a bug in some
other component which can't be fixed immediately. It's also a good practice to
keep xfail tests in sync with an issue tracker.

.. code-block:: Lua

    local g = t.group()
    g.test_fail = function()
        t.xfail('Must fail no matter what')
        t.assert_equals(3, 4)
    end

XFail only applies to the errors raised by the luatest assertions. Regular Lua
errors still cause the test failure.

.. _capturing-output:

---------------------------------
Capturing output
---------------------------------

By default runner captures all stdout/stderr output and shows it only for failed tests.
Capturing can be disabled with ``-c`` flag.

.. _repeating:

---------------------------------
Tests repeating
---------------------------------

Runners can repeat tests with flags ``-r`` / ``--repeat`` (to repeat all the tests) or
``-R`` / ``--repeat-group`` (to repeat all the tests within the group).

.. _parametrization:

---------------------------------
Parametrization
---------------------------------

Test group can be parametrized.

.. code-block:: Lua

    local g = t.group('pgroup', {{a = 1, b = 4}, {a = 2, b = 3}})

    g.test_params = function(cg)
        ...
        log.info('a = %s', cg.params.a)
        log.info('b = %s', cg.params.b)
        ...
    end

Group can be parametrized with a matrix of parameters using `luatest.helpers`:

.. code-block:: Lua

    local g = t.group('pgroup', t.helpers.matrix({a = {1, 2}, b = {3, 4}}))
    -- Will run:
    -- * a = 1, b = 3
    -- * a = 1, b = 4
    -- * a = 2, b = 3
    -- * a = 2, b = 4

Each test will be performed for every params combination. Hooks will work as usual
unless there are specified params. The order of execution in the hook group is
determined by the order of declaration.

.. code-block:: Lua

    -- called before every test
    g.before_each(function(cg) ... end)

    -- called before tests when a == 1
    g.before_each({a = 1}, function(cg) ... end)

    -- called only before the test when a == 1 and b == 3
    g.before_each({a = 1, b = 3}, function(cg) ... end)

    -- called before test named 'test_something' when a == 1
    g.before_test('test_something', {a = 1}, function(cg) ... end)

    --etc

Test from a parameterized group can be called from the command line in such a way:

.. code-block:: Bash

    luatest pgroup.a:1.b:4.test_params
    luatest pgroup.a:2.b:3.test_params

Note that values for ``a`` and ``b`` have to match to defined group params. The command below will give you an error
because such params are not defined for the group.

.. code-block:: Bash

    luatest pgroup.a:2.b:2.test_params  # will raise an error

.. _test-helpers:

---------------------------------
Test helpers
---------------------------------

There are helpers to run tarantool applications and perform basic interaction with it.
If application follows configuration conventions it is possible to use
options to configure server instance and helpers at the same time. For example
``http_port`` is used to perform http request in tests and passed in ``TARANTOOL_HTTP_PORT``
to server process.

.. code-block:: Lua

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
    -- Wait until server is ready to accept connections.
    -- This may vary from app to app: for one server:connect_net_box() is enough,
    -- for another more complex checks are required.
    luatest.helpers.retrying({}, function() server:http_request('get', '/ping') end)

    -- http requests
    server:http_request('get', '/path')
    server:http_request('post', '/path', {body = 'text'})
    server:http_request('post', '/path', {json = {field = value}, http = {
        -- http client options
        headers = {Authorization = 'Basic ' .. credentials},
        timeout = 1,
    }})

    -- This method throws error when response status is outside of then range 200..299.
    -- To change this behaviour, path `raise = false`:
    t.assert_equals(server:http_request('get', '/not_found', {raise = false}).status, 404)
    t.assert_error(function() server:http_request('get', '/not_found') end)

    -- using net_box
    server:connect_net_box()
    server:eval('return do_something(...)', {arg1, arg2})
    server:call('function_name', {arg1, arg2})
    server:exec(function() return box.info() end)
    server:stop()

``luatest.Process:start(path, args, env)`` provides low-level interface to run any other application.

There are several small helpers for common actions:

.. code-block:: Lua

    luatest.helpers.uuid('ab', 2, 1) == 'abababab-0002-0000-0000-000000000001'

    luatest.helpers.retrying({timeout = 1, delay = 0.1}, failing_function, arg1, arg2)
    -- wait until server is up
    luatest.helpers.retrying({}, function() server:http_request('get', '/status') end)

.. _luacov-integration:

---------------------------------
luacov integration
---------------------------------

- Install `luacov <https://github.com/keplerproject/luacov>`_ with ``tarantoolctl rocks install luacov``
- Configure it with ``.luacov`` file
- Clean old reports ``rm -f luacov.*.out*``
- Run luatest with ``--coverage`` option
- Generate report with ``.rocks/bin/luacov .``
- Show summary with ``grep -A999 '^Summary' luacov.report.out``

When running integration tests with coverage collector enabled, luatest
automatically starts new tarantool instances with luacov enabled.
So coverage is collected from all the instances.
However this has some limitations:

- It works only for instances started with ``Server`` helper.
- Process command should be executable lua file or tarantool with script argument.
- Instance must be stopped with ``server:stop()``, because this is the point where stats are saved.
- Don't save stats concurrently to prevent corruption.

---------------------------------
Development
---------------------------------

- Check out the repo.
- Prepare makefile with ``cmake .``.
- Install dependencies with ``make bootstrap``.
- Run it with ``make lint`` before committing changes.
- Run tests with ``bin/luatest``.

---------------------------------
Contributing
---------------------------------

Bug reports and pull requests are welcome on at
https://github.com/tarantool/luatest.

---------------------------------
License
---------------------------------

MIT
