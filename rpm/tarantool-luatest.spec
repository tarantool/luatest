Name: luatest
Version: 0.5.4
Release: 1%{?dist}
Summary: Tarantool test framework
Group: Applications/Databases
License: MIT
URL: https://github.com/tarantool/luatest
Source0: https://github.com/tarantool/luatest/archive/%{version}/luatest-%{version}.tar.gz
BuildArch: noarch
BuildRequires: tarantool-devel >= 1.9.0
BuildRequires: tarantool-checks
Requires: tarantool >= 1.9.0
Requires: tarantool-checks
%description
Simple Tarantool test framework for both unit and integration testing.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo -DVERSION=%{version}
make %{?_smp_mflags}

%check
ctest -VV

%install
%make_install

%files
#%{_libdir}/tarantool/*/
%{_datarootdir}/tarantool/*/
%{_bindir}/luatest
%doc README.md
%{!?_licensedir:%global license %doc}
%license LICENSE

%changelog
* Thu Aug 5 2021 Aleksandr Shemenev <a.shemenev@corp.mail.ru> 0.5.4-1
- Add `after_test` and `before_test` hooks.
- Add tap version to the output.
- New `restart` server method.
- Add new `eval` and `call` server methods for convenient net_box calls.
- Server can use a unix socket as a listen port.
- Add `TARANTOOL_ALIAS` in the server env space.
- Server args are updated on start.

* Thu Jun 10 2021 Aleksandr Shemenev <a.shemenev@corp.mail.ru> 0.5.3-1
- Add `_le`, `_lt`, `_ge`, `_gt` assertions.
- Write execution time for each test in the verbose mode.
- When capture is disabled and verbose mode is on test names are printed
  twice: at the start and at the end with result.
- `assert_error_msg_` assertions print return values if no error is generated.
- Fix `--repeat` runner option.

* Thu Jun 25 2020 Maxim Melentiev <m.melentiev@corp.mail.ru> 0.5.2-1
- Throw parser error when .json is accessed on response with invalid body.
- Set `Content-Type: application/json` for `:http_request(..., {json = ...})` requests.

* Tue Apr 21 2020 Maxim Melentiev <m.melentiev@corp.mail.ru> 0.5.1-1
- Assertions pretty-prints non-string extra messages (useful for custom errors as tables).
- String values in errors are printed as valid Lua strings (with `%q` formatter).
- Add `TARANTOOL_DIR` to rockspec build.variables
- Replace `--error` and  `--failure` options with `--fail-fast`.
- Fix stripping luatest trace from backtrace.
- Fix luarocks 3 test engine installation.

* Wed Jan 22 2020 Maxim Melentiev <m.melentiev@corp.mail.ru> 0.5.0-1
- `assert_is` treats `box.NULL` and `nil` as different values.
- Add luacov integration.
- Fix `assert_items_equals` for repeated values. Add support for `tuple` items.
- Add `assert_items_include` matcher.
- `assert_equals` uses same comparison rules for nested values.
- Fix generated group names when running files within specific directory.

* Thu Dec 26 2019 Maxim Melentiev <m.melentiev@corp.mail.ru> 0.4.0-1
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

* Wed Oct 2 2019 Konstantin Nazarov <mail@knazarov.com> 0.3.0-1
- Initial release
