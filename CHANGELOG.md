# Changelog

## 1.2.0

- Fixed a bug when `server:grep_log()` failed to find a string logged in
  `server:exec()` called immediately before it (gh-421).
- Fixed a bug when it wasn't possible to reload the cluster config with
  `cluster:reload()` after removing an instance with `cluster:sync()`.
  Also added an option to `cluster:sync()` to start/stop added/removed
  instances (gh-423).

## 1.1.0

- Added logging to unified file (gh-324).
- Added memory leak detection during server process execution (gh-349).
- Added `assert_error_covers`.
- Added more logs (gh-326).
- Added `justrun` helper as a tarantool runner and output catcher (gh-365).
- Changed error message for too long Unix domain socket paths (gh-341).
- Added `cbuilder` helper as a declarative configuration builder (gh-366).
- Made `assert_error_*` additionally check error trace if required.
- Added `--list-test-cases` and `--run-test-case` CLI options.
- Introduced preloaded hooks (gh-380).
- Added `treegen` helper as a tree generator (gh-364).
- Added support for declarative configuration to `server.lua` (gh-367).
- Made `assert_covers` recursive (gh-379).
- Added alias `--no-capture` for the option `-c` (gh-391).
- Fixed reporting of an assertion failure in `Server:exec()` in case verbose
  error serialization is enabled in Tarantool (gh-376).
- Added `assert_items_exclude`.
- Stripped useless `...` lines from error trace.
- Fixed error trace reporting for functions executed with `Server:exec()`
  (gh-396).
- Removed pretty-printing of `luatest.log` arguments.
- Added `cluster` helper as a tool for managing a Tarantool cluster (gh-368).
- Fixed `Server:grep_log()` to work with a server instance started using
  the `cluster` helper (gh-389).
- Fixed `Server:grep_log()` to work with a stopped server instance (gh-397).

## 1.0.1

- Fixed incorrect Unix domain socket path length check (gh-341).
- Now `net_box_uri` can be accepted as a table (gh-342).
- Fixed returning values from `Server:exec()` if some of them are nil (gh-350).
- Introduce `luatest.log` helper (gh-326).

## 1.0.0

- Extend `server.lua` API:
  * Update parameters of the `Server:new()` function:
    - The `alias` parameter defaults to 'server'.
    - The `command` parameter is optional.
    - The `workdir` parameter is optional.
    - New parameter `datadir` (optional).
    - New parameter `box_cfg` (optional).
  * Add waiting until the started server is ready.
  * Add waiting until the process of the stopped server is terminated.
  * Add new functions:
    - `Server.build_listen_uri()`
    - `Server:drop()`
    - `Server:wait_until_ready()`
    - `Server:get_instance_id()`
    - `Server:get_instance_uuid()`
    - `Server:grep_log()`
    - `Server:assert_follows_upstream()`
    - `Server:get_election_term()`
    - `Server:wait_for_election_term()`
    - `Server:wait_for_election_state()`
    - `Server:wait_for_election_leader()`
    - `Server:wait_until_election_leader_found()`
    - `Server:get_synchro_queue_term()`
    - `Server:wait_for_synchro_queue_term()`
    - `Server:play_wal_until_synchro_queue_is_busy()`
    - `Server:get_vclock()`
    - `Server:get_downstream_vclock()`
    - `Server:wait_for_vclock()`
    - `Server:wait_for_downstream_to()`
    - `Server:wait_for_vclock_of()`
    - `Server:update_box_cfg()`
    - `Server:get_box_cfg()`
- Add new module `replica_proxy.lua`.
- Add new module `replica_set.lua`.
- Add new module `tarantool.lua`.
- Check docs generation with LDoc.
- Add the `--repeat-group` (`-R`) option to run tests in a circle within the
  group.
- Forbid negative values for the `--repeat` (`-r`) option.
- Change the `coverage_report` parameter type to boolean in the `Server:new()`
  function.
- Print Tarantool version used by luatest.
- Auto-require the `luatest` module in the `Server:exec()` function where it is
  available via the corresponding upvalue.
- Raise an error when non-array arguments passed to the `Server:exec()`
  function.
- Save server artifacts (logs, snapshots, etc.) to the `${VARDIR}/artifacts`
  directory if the test fails.
- Fix requiring the internal test helper when running tests.
- Fix collecting coverage if the tarantool binary has a suffix.

## 0.5.7

- Fix invalid arguments logging in some assertions.
- Fix confusing error message from `assert_not_equals` function.
- Fix confusing error message from `assert_items_equals` function.
- Fix confusing error message from `assert_items_include` function.
- Print `(no reason specified)` message instead of `nil` value when the test is
  skipped and no reason is specified.
- Check `net_box_uri` param is less than max Unix domain socket path length.
- Change test run summary report: use verbs in past simple tense (succeeded,
  failed, xfailed, etc.) instead of nouns (success(es), fail(s), xfail(s), etc.)

## 0.5.6

- Add `xfail` status.
- Add new `Server:exec()` function which runs a Lua function remotely.

## 0.5.5

- Repeat `_each` and `_test` hooks when `--repeat` is specified.
- Add group parametrization.

## 0.5.4

- Add `after_test` and `before_test` hooks.
- Add tap version to the output.
- New `restart` server method.
- Add new `eval` and `call` server methods for convenient net_box calls.
- Server can use a unix socket as a listen port.
- Add `TARANTOOL_ALIAS` in the server env space.
- Server args are updated on start.

## 0.5.3

- Add `_le`, `_lt`, `_ge`, `_gt` assertions.
- Write execution time for each test in the verbose mode.
- When capture is disabled and verbose mode is on test names are printed
  twice: at the start and at the end with result.
- `assert_error_msg_` assertions print return values if no error is generated.
- Fix `--repeat` runner option.

## 0.5.2

- Throw parser error when .json is accessed on response with invalid body.
- Set `Content-Type: application/json` for `:http_request(..., {json = ...})` requests.

## 0.5.1

- Assertions pretty-prints non-string extra messages (useful for custom errors as tables).
- String values in errors are printed as valid Lua strings (with `%q` formatter).
- Add `TARANTOOL_DIR` to rockspec build.variables
- Replace `--error` and  `--failure` options with `--fail-fast`.
- Fix stripping luatest trace from backtrace.
- Fix luarocks 3 test engine installation.

## 0.5.0

- `assert_is` treats `box.NULL` and `nil` as different values.
- Add luacov integration.
- Fix `assert_items_equals` for repeated values. Add support for `tuple` items.
- Add `assert_items_include` matcher.
- `assert_equals` uses same comparison rules for nested values.
- Fix generated group names when running files within specific directory.

## 0.4.0

- Fix not working `--exclude`, `--pattern` options
- Fix error messages for `*_covers` matchers
- Raise error when `group()` is called with existing group name.
- Allow dot in group name.
- Prevent using `/` in group name.
- Decide group name from filename for `group()` call without args.
- `assert` returns input values.
- `assert[_not]_equals` works for Tarantool's box.tuple.
- Print tables in lua-compatible way in errors.
- Fix performance issue with large errors messages.
- Unify hooks definition: group hooks are defined via function calls.
- Keep running other groups when group hook failed.
- Prefix and colorize captured output.
- Fix numeric assertions for cdata values.

## 0.3.0

- Make --shuffle option accept `group`, `all`, `none` values
- Replace `raw` option for `Server:http_request` with `raise`.
- Remove not documented methods inherited from luaunit.
- Colorize report.

## 0.2.2

- Fix issue with crashes in capture.
- Do not raise error for 2xx responses in Server:http_request

## 0.2.1

- Don't run suite hooks when suite is not going to be run.
- Gracefully shutdown even when luanit calls `os.exit`.
- Show failed tests summary.
- Capture works with large outputs.

## 0.2.0

- GC'ed processes are killed automatically.
- Print captured output when suite/group hook fails.
- Rename Server:console to Server:net_box.
- Use real time instead of CPU time for duration.
- LDoc comments.
- Make assertions box.NULL aware.
- Luarocks 3 tests engine.
- `assert_covers` matcher.

## 0.1.1

- Fix exit code on failure.

## 0.1.0

- Initial implementation.
