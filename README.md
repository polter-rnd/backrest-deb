# backrest-deb

Debian packaging for [backrest](https://github.com/garethgeorge/backrest),
built on OBS (`home:polter:devass/backrest`) straight from this repo via
scm-sync. The upstream source is the `backrest/` git submodule; everything
else the offline build needs is either committed (`webui-dist/`) or fetched
by OBS from the top-level `go.sum` (Go modules, the Go toolchain, restic).

Clone with `git clone --recurse-submodules`.

## Bumping to a new upstream release

```sh
git -C backrest fetch --tags
git -C backrest checkout v1.15.0
# if upstream changed RequiredResticVersion or needs a newer Go:
# update RESTIC_VERSION / GO_VERSION in debian/rules
debian/update-go-sum.sh      # top-level go.sum, verifies every download
debian/update-webui.sh       # webui-dist/, pinned Node and pnpm
dch -v 1.15.0+devass1 "New upstream release."
git add -A && git commit -m "Bump upstream to v1.15.0"
```

## Local build

The build needs `build-gomodcache/`, which OBS fetches from `go.sum`. `osc`
downloads the same assets, so build locally through it:

```sh
osc co home:polter:devass backrest && cd home:polter:devass/backrest
osc build Debian_13 x86_64
```
