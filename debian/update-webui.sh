#!/bin/sh
# Rebuild webui-dist/ from the backrest/ submodule's webui. It is committed
# because the OBS build has no network and no suitable Node; debian/rules
# copies it to backrest/webui/dist, which the binary embeds via //go:embed.
# Node and pnpm are pinned and checked against recorded hashes (Node:
# SHASUMS256.txt of the release; pnpm: npm registry dist.integrity). npm
# dependencies are checked by pnpm against pnpm-lock.yaml integrity.
set -eu
cd "$(dirname "$0")/.."

NODE_VERSION=22.23.5
NODE_SHA256_x64=cdeb8670a0c81f51b4dc4ac61919f9b1ad917b304bf8221eb939570663d240f8
NODE_SHA256_arm64=2babb9eb5264860d540849f4b064a6fbdebcdc323657d9d382ce23d313fd5e09
PNPM_VERSION=9.15.9
PNPM_INTEGRITY=sha512-aARhQYk8ZvrQHAeSMRKOmvuJ74fiaR1p5NQO7iKJiClf1GghgbrlW1hBjDolO95lpQXsfF+UA+zlzDzTfc8lMQ==

case "$(uname -m)" in
	x86_64) arch=x64 node_sha=$NODE_SHA256_x64 ;;
	aarch64) arch=arm64 node_sha=$NODE_SHA256_arm64 ;;
	*) echo "unsupported host $(uname -m)" >&2; exit 1 ;;
esac
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

node=node-v$NODE_VERSION-linux-$arch.tar.xz
curl -fsSL -o "$tmp/$node" "https://nodejs.org/dist/v$NODE_VERSION/$node"
echo "$node_sha  $tmp/$node" | sha256sum -c -
mkdir "$tmp/node" && tar -C "$tmp/node" --strip-components=1 -xJf "$tmp/$node"

curl -fsSL -o "$tmp/pnpm.tgz" "https://registry.npmjs.org/pnpm/-/pnpm-$PNPM_VERSION.tgz"
got="sha512-$(openssl dgst -sha512 -binary "$tmp/pnpm.tgz" | base64 -w0)"
[ "$got" = "$PNPM_INTEGRITY" ] || { echo "pnpm-$PNPM_VERSION.tgz: integrity mismatch" >&2; exit 1; }
echo "pnpm-$PNPM_VERSION.tgz: OK"
mkdir "$tmp/pnpm" && tar -C "$tmp/pnpm" --strip-components=1 -xzf "$tmp/pnpm.tgz"

export PATH="$tmp/node/bin:$PATH"
pnpm="node $tmp/pnpm/bin/pnpm.cjs"
(
	cd backrest/webui
	$pnpm install --frozen-lockfile
	$pnpm run build
)
rm -rf webui-dist
mv backrest/webui/dist webui-dist
