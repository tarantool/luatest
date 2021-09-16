# Changelog

## Unreleased

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
