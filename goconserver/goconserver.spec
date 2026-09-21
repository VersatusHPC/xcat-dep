# Nothing builds this file. goconserver/mockbuild.pl writes the spec that reaches rpmbuild, so
# a dependency or a capability added here reaches no rpm. The line below is kept in step with
# the generator only to stop the next reader from adding it here alone.
Summary: A dummy package.
Name: goconserver
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
