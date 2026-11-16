#!/bin/sh
# Regenerate the top-level go.sum for the OBS scm-sync build.
#
# OBS (obs-build PBuild/RemoteAssets.pm, golang_parse/golang_fetch) turns every
# go.sum entry into a build-gomodcache/ GOPROXY asset, fetched server-side and
# checked against its h1: hash before the offline build. The top-level go.sum
# is backrest/go.sum (the submodule's, which the build uses unchanged) plus:
#
#   Go toolchain  golang.org/toolchain module hashes from `go mod download`,
#                 which verifies them against sum.golang.org. The go used for
#                 that is checked against the sha256 go.dev publishes.
#   restic        SHA256SUMS checked with gpgv against restic's release key
#                 (the one backrest embeds in internal/resticinstaller/verify.go),
#                 the source tarball against SHA256SUMS, and the module zip
#                 must have exactly the tarball's files. restic's own go.sum
#                 is taken from that tarball.
#
# Run after moving the backrest/ submodule or bumping versions in debian/rules.
# Needs curl, gpg, jq, unzip.
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)

GO_VERSION=$(sed -n 's/^GO_VERSION := //p' debian/rules)
RESTIC_VERSION=$(sed -n 's/^RESTIC_VERSION := //p' debian/rules)
case "$(uname -m)" in
	x86_64) host=amd64 ;;
	aarch64) host=arm64 ;;
	*) echo "unsupported host $(uname -m)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'chmod -R u+w "$tmp"; rm -rf "$tmp"' EXIT
cd "$tmp"

# --- Host go, checked against the sha256 go.dev publishes ---
go=go$GO_VERSION.linux-$host.tar.gz
curl -fsSLO "https://dl.google.com/go/$go"
echo "$(curl -fsSL "https://dl.google.com/go/$go.sha256")  $go" | sha256sum -c -
tar -xzf "$go"

# --- Module hashes, verified by go against sum.golang.org ---
export GOMODCACHE="$tmp/gomodcache" GOTOOLCHAIN=local GOFLAGS=-mod=mod \
	GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
go/bin/go mod download -json \
	"golang.org/toolchain@v0.0.1-go$GO_VERSION.linux-amd64" \
	"golang.org/toolchain@v0.0.1-go$GO_VERSION.linux-arm64" \
	"github.com/restic/restic@v$RESTIC_VERSION" > mods.json || { cat mods.json >&2; exit 1; }
# Each module becomes two go.sum lines: one for its zip, one for its go.mod.
jq -r '"\(.Path) \(.Version) \(.Sum)", "\(.Path) \(.Version)/go.mod \(.GoModSum)"' mods.json > extra.sum

# --- restic: signed SHA256SUMS -> source tarball -> module zip ---
base=https://github.com/restic/restic/releases/download/v$RESTIC_VERSION
src=restic-$RESTIC_VERSION.tar.gz
curl -fsSL -O "$base/SHA256SUMS" -O "$base/SHA256SUMS.asc" -O "$base/$src"
# restic's release key, as embedded in backrest's Go source
sed -n '/BEGIN PGP PUBLIC KEY/,/END PGP PUBLIC KEY/p' "$ROOT/backrest/internal/resticinstaller/verify.go" \
	| gpg --batch --dearmor -o restic.gpg
gpgv --keyring ./restic.gpg SHA256SUMS.asc SHA256SUMS
grep " $src\$" SHA256SUMS | sha256sum -c -
tar -xzf "$src"
unzip -q "$GOMODCACHE/cache/download/github.com/restic/restic/@v/v$RESTIC_VERSION.zip" -d zip
diff -r "restic-$RESTIC_VERSION" "zip/github.com/restic/restic@v$RESTIC_VERSION"
echo "restic module zip matches $src"

cat "$ROOT/backrest/go.sum" extra.sum "restic-$RESTIC_VERSION/go.sum" | LC_ALL=C sort -u > "$ROOT/go.sum"
echo "go.sum: $(wc -l < "$ROOT/go.sum") lines"
