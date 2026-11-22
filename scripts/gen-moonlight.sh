#!/bin/bash
# Makes Sources/CMoonlight1, 2 and 3: Moonlight's stream core (Native/moonlight) three times over, every global
# name given its own prefix (pxr1_, pxr2_, pxr3_), so three PC screens can stream at once in one iOS app.
# moonlight-common-c keeps its connection in process-wide globals; Android and Windows give each PC screen its own
# process, which iOS does not allow.
#
# Runs on a Mac (CI does it before every build). The symbols to rename are read with nm from a build of the same
# files for macOS, so nothing has to be listed by hand. The made folders are not kept in git.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
N="$ROOT/Native/moonlight"
MC="moonlight-common-c"
SHARED="$ROOT/Native/shared/include"

SOURCES=()
for f in "$N/$MC"/src/*.c; do
    b="$(basename "$f")"
    [ "$b" = "PlatformCrypto.c" ] && continue
    SOURCES+=("$MC/src/$b")
done
for e in callbacks compress host list packet peer protocol unix; do SOURCES+=("$MC/enet/$e.c"); done
SOURCES+=("$MC/nanors/rs.c" "$MC/nanors/deps/obl/oblas_common.c" "$MC/nanors/deps/obl/oblas_lite.c")
SOURCES+=("pxr_moonlight.c" "pxr_crypto_apple.c")

DEFS=(-DNDEBUG -DHAS_SOCKLEN_T=1 -DHAS_FCNTL=1 -DHAS_IOCTL=1 -DHAS_POLL=1 -DHAS_GETADDRINFO=1 -DHAS_GETNAMEINFO=1
      -DHAS_INET_PTON=1 -DHAS_INET_NTOP=1 -DHAS_MSGHDR_FLAGS=1)
INCS=(-I "$N/$MC/src" -I "$N/$MC/enet/include" -I "$N/$MC/nanors" -I "$N/$MC/nanors/deps" -I "$N/$MC/nanors/deps/obl"
      -I "$SHARED")

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
for s in "${SOURCES[@]}"; do
    clang -c -O0 -w "${DEFS[@]}" "${INCS[@]}" "$N/$s" -o "$TMP/$(echo "$s" | tr '/' '_').o"
done
nm -gUj "$TMP"/*.o | grep -E '^_[A-Za-z_][A-Za-z0-9_]*$' | sed 's/^_//' | sort -u > "$TMP/symbols.txt"
echo "gen-moonlight: $(wc -l < "$TMP/symbols.txt" | tr -d ' ') global names to prefix"
grep -qx 'pxr_api' "$TMP/symbols.txt" || { echo "gen-moonlight: pxr_api not found"; exit 1; }

for i in 1 2 3; do
    D="$ROOT/Sources/CMoonlight$i"
    rm -rf "$D"
    mkdir -p "$D/include" "$D/src"
    # Every header, and only the sources built.
    (cd "$N" && find "$MC" -name '*.h' -print0 | xargs -0 -I{} sh -c 'mkdir -p "$0/$(dirname "{}")" && cp "{}" "$0/{}"' "$D/src")
    {
        echo "// Made by scripts/gen-moonlight.sh: this copy's names, so three copies live in one app."
        echo "#pragma once"
        while read -r sym; do echo "#define $sym pxr${i}_$sym"; done < "$TMP/symbols.txt"
    } > "$D/src/pxr_prefix.h"
    for s in "${SOURCES[@]}"; do
        mkdir -p "$D/src/$(dirname "$s")"
        { echo '#include "pxr_prefix.h"'; cat "$N/$s"; } > "$D/src/$s"
    done
    cat > "$D/include/CMoonlight$i.h" <<EOF
// Made by scripts/gen-moonlight.sh: Moonlight's stream core, copy $i of 3.
#pragma once
#include "pxr_api.h"
const PXR_API* pxr${i}_pxr_api(void);
EOF
done
echo "gen-moonlight: made Sources/CMoonlight1, 2 and 3"
