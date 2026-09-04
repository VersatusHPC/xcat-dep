fix(xcat-dep): dnf install xCATsn does not resolve on an EL service node

A service node reaches only BaseOS and AppStream from copycds, plus the xcat-core and xcat-dep repositories. It never reaches CRB or EPEL. Against that repo set `dnf install xCATsn` reports "nothing provides" for perl-IO-Tty, perl(IO::Pty), perl-Crypt-CBC, perl-Crypt-Rijndael, perl(Expect), perl(HTML::Form) and, per release, perl-Crypt-SSLeay, perl-Net-Telnet, perl-Digest-SHA1 and perl-Net-DNS. The provisioning then reports only "provision completed with error".

packages-manifest.conf assumes EPEL and CRB stand behind every EL target, which holds for a management node and not for a service node. The perl packages are therefore built only for rocky-10-riscv64-xcat, the one target with no EPEL. mockbuild-perl-packages.pl carries the perl-IO-Tty sources but has no %meta entry for the name, so no target can build it.

Each EL target section, x86_64 and ppc64le, now lists the perl packages BaseOS and AppStream do not carry. The %meta table in mockbuild-perl-packages.pl gains perl-IO-Tty, and its sources move to IO-Tty 1.20 with a spec. The 1.12 Makefile.PL pty probe only takes the address of each candidate function. The current toolchain drops that reference, the build defines HAVE__GETPTY on a glibc without _getpty, and IO/Tty/Tty.so fails to load. The 1.20 probe calls the function.

t/servicenode_perl_deps.t captures both halves, and .github/workflows/genesis-openembedded.yml runs it. It reads packages-manifest.conf, extracts and evaluates the %meta table, and checks each named spec or source rpm exists. It builds no package and resolves no dependency. On the test commit seven EL target sections lack the perl set and %meta lacks perl-IO-Tty, so the test fails.

Commits: 4fbdfe7 test, e3bf491 fix
LANDING ORDER: land first, and publish signed ppc64le rpms to the dep channel, before fix/servicenode-third-party-repo in xcat-core. Reversed, that change removes epel-release before the replacement packages exist, and the service node install breaks.
