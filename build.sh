#!/bin/sh -e
{ command -v clang > /dev/null 2>&1 && command -v clang++ > /dev/null 2>&1 && command -v llvm-config > /dev/null 2>&1; } || { printf "clang, clang++, and llvm-config are required to build this\n"; exit 1; }

if [ -z "$STRIP" ]; then
    if command -v llvm-strip > /dev/null 2>&1; then
        STRIP="llvm-strip"
    elif command -v strip > /dev/null 2>&1; then
        STRIP="strip"
    else
        STRIP="true"
    fi
fi

[ "${0%/*}" = "$0" ] && scriptroot="." || scriptroot="${0%/*}"
pwd="$PWD"

# Move the old SDKs out of the way
[ -d "$pwd/ios-toolchain/share/iphoneports" ] && mv "$pwd/ios-toolchain/share/iphoneports" "$scriptroot/iphoneports-sdks"

rm -rf "$pwd/ios-toolchain" "$scriptroot/build"
mkdir -p "$pwd/ios-toolchain/share"

# Put the old SDKs back
[ -d "$scriptroot/iphoneports-sdks" ] && mv "$scriptroot/iphoneports-sdks" "$pwd/ios-toolchain/share/iphoneports"

(
mkdir "$scriptroot/build" && cd "$scriptroot/build" || exit 1
printf "Building libtapi\n\n"
tapiver="1300.6.5"
curl -# -L "https://github.com/tpoechtrager/apple-libtapi/archive/refs/heads/$tapiver.tar.gz" | tar xz
(
cd "apple-libtapi-$tapiver" || exit 1
INSTALLPREFIX="$pwd/ios-toolchain" CC=clang CXX=clang++ ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
cctoolsver="1010.6-ld64-951.9"
curl -# -L "https://github.com/Un1q32/cctools-port/archive/refs/heads/$cctoolsver.tar.gz" | tar xz
(
cd "cctools-port-$cctoolsver/cctools" || exit 1
./configure --prefix="$pwd/ios-toolchain" --bindir="$pwd/ios-toolchain/libexec/cctools" --mandir="$pwd/ios-toolchain/share/cctools" --with-libtapi="$pwd/ios-toolchain" --enable-silent-rules
make -j"$(nproc)"
make install
)

if [ "$(uname -s)" != "Darwin" ]; then
    mkdir -p "$pwd/ios-toolchain/libexec/lib"
    ln -s "$(llvm-config --libdir)/libLTO.so" "$pwd/ios-toolchain/libexec/lib"
fi

printf "Building ldid\n\n"
ldidver="2.1.5-procursus7"
curl -# -L "https://github.com/ProcursusTeam/ldid/archive/refs/tags/v$ldidver.tar.gz" | tar xz
(
cd "ldid-$ldidver" || exit 1
make CXX=clang++
mkdir -p "$pwd/ios-toolchain/bin"
cp ldid "$pwd/ios-toolchain/bin"
cp docs/ldid.1 "$pwd/ios-toolchain/share/cctools/man1"
)
)

cp -a "$scriptroot"/files/* "$pwd/ios-toolchain"

(
cd "$pwd/ios-toolchain" || exit 1
"$STRIP" libexec/cctools/*
for arch in arm i386 ppc ppc64 x86_64; do
    "$STRIP" "libexec/as/$arch/as"
done
for link in c++ clang clang++ gcc g++; do
    ln -s cc "libexec/iphoneports/$link"
done
rm -rf include
for lib in lib/*; do
    if [ -h "$lib" ]; then
        rm "$lib"
    else
        "$STRIP" "$lib"
    fi
done
mkdir -p share/iphoneports
if [ -n "$1" ]; then
    printf '\n'
    for target in "$@"; do
        ./bin/iphoneports-add-target "$target"
    done
fi
)
