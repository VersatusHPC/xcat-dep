# NOTHING BUILDS THIS FILE. goconserver/mockbuild.pl generates the real spec, in two heredocs,
# and that is where a dependency or a capability has to go. A change made here reaches no rpm:
# the console-backend capability was added here first and the built package never carried it.
Summary: A dummy package.
Name: goconserver
# xCAT requires a console backend but cannot name one: goconserver needs a Go toolchain the SLE
# 12 family does not have, and that family builds conserver-xcat instead. rpm on that family
# cannot parse a boolean dependency at all -- "Dependency tokens must begin with alpha-numeric,
# '_' or '/'" -- so the choice cannot be expressed in xCAT.spec. Both backends declare this
# capability instead, and xCAT requires the capability.
Provides: xcat-console-backend
Version: 0.0
Release: 0
License: EPL
Group: Applications/System
BuildRoot: %{_tmppath}/%{name}-root
BuildArchitectures: noarch

%description
A dummy package.

%files
