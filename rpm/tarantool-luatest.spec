Name: luatest
Version: 0.5.0
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
