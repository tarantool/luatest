Name: luatest
Version: 0.2.2
Release: 1%{?dist}
Summary: Tarantool test framework
Group: Applications/Databases
License: MIT
URL: https://github.com/tarantool/luatest
Source0: https://github.com/tarantool/luatest/archive/%{version}/luatest-%{version}.tar.gz
BuildArch: noarch
BuildRequires: tarantool-devel >= 1.6.8.0
BuildRequires: tarantool-luacheck
BuildRequires: tarantool-http
BuildRequires: tarantool-checks
Requires: tarantool >= 1.6.8.0
Requires: tarantool-checks
%description
A simple Tarantool test framework for both unit and integration testing.

%prep
%setup -q -n %{name}-%{version}

%build
%cmake . -DCMAKE_BUILD_TYPE=RelWithDebInfo
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
* Wed Oct 2 2019 Konstantin Nazarov <mail@knazarov.com> 0.2.2-1
- Initial release
