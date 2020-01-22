# Unreleased

- `assert_is` treats `box.NULL` and `nil` as different values.
- Add luacov integration.
- Fix `assert_items_equals` for repeated values. Add support for `tuple` items.
- Add `assert_includes_items` matcher.
- `assert_equals` uses same comparison rules for nested values.
- Fix generated group names when running files within specific directory.

# 0.4.0

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

# 0.3.0

- Make --shuffle option accept `group`, `all`, `none` values
- Replace `raw` option for `Server:http_request` with `raise`.
- Remove not documented methods inherited from luaunit.
- Colorize report.

# 0.2.2

- Fix issue with crashes in capture.
- Do not raise error for 2xx responses in Server:http_request

# 0.2.1

- Don't run suite hooks when suite is not going to be run.
- Gracefully shutdown even when luanit calls `os.exit`.
- Show failed tests summary.
- Capture works with large outputs.

# 0.2.0

- GC'ed processes are killed automatically.
- Print captured output when suite/group hook fails.
- Rename Server:console to Server:net_box.
- Use real time instead of CPU time for duration.
- LDoc comments.
- Make assertions box.NULL aware.
- Luarocks 3 tests engine.
- `assert_covers` matcher.

# 0.1.1

- Fix exit code on failure.

# 0.1.0

- Initial implementation.
