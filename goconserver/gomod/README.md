# Pinned `go.mod` / `go.sum` for the goconserver build

These pin the Go module graph for goconserver at the commit built by `../sbuild.pl` (Ubuntu) and
`../mockbuild.pl` (EL): `REF=6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f`. Both builders overlay them
into the freshly cloned upstream tree and compile with `GOFLAGS=-mod=mod`, so modules are downloaded
from the Go proxy but **pinned and integrity-checked by `go.sum`** — the build is reproducible, with
**no `go mod tidy`** at build time (which would float transitive versions from the network).

The `go` directive (currently go 1.25.0) is the highest requirement in the pinned graph, and every
builder toolchain must meet it: the `GO_PIN` of `../sbuild.pl` (1.25.12), the `golang` of the EL10
mock chroot (1.26.4) and the `golang` of the Leap 15.6 chroot (go1.25-1.25.8). All three build with
`GOTOOLCHAIN=local`, so a directive above the LOWEST of them stops that build before the compiler
starts. Do not raise the directive to the version of the toolchain that regenerated the file; set it
to what the graph needs. Read the graph with:

```sh
go list -m -f '{{.Path}} {{.GoVersion}}' all | sort -k2 -V | tail -1
```

`t/goconserver_gomod_toolchain.t` builds the pinned graph with the lowest toolchain and fails when
the directive climbs above it.

## Regenerate (when bumping `REF` or `GO_PIN`, or a dependency)

On a host with network, using the pinned toolchain:

```sh
REF=6166fe5ec1c5b3c20475e322a9f0e8e93c87e45f
git clone https://github.com/xcat2/goconserver gcsrc && cd gcsrc
git checkout "$REF"
rm -rf storage/etcd.go storage/etcd/                            # the build drops the broken etcd backend
[ -f go.mod ] || go mod init github.com/xcat2/goconserver       # only if upstream ships no go.mod
go mod edit -replace github.com/kr/pty=github.com/creack/pty@v1.1.21
go mod tidy
cp go.mod go.sum <this dir>
```

Notes:
- `kr/pty → creack/pty` fixes console fork (`pty.Start` sets `Ctty` in a way Go ≥1.15 rejects).
- The **etcd removal is required**: goconserver's etcd storage backend drags in `github.com/coreos/bbolt`,
  which now declares its module path as `go.etcd.io/bbolt`, so `go mod tidy` aborts on it. The build
  removes `storage/etcd*` anyway (CGO-free static console server), so the pinned graph omits it.
