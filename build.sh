#!/bin/sh -e
{ command -v clang > /dev/null 2>&1 && command -v clang++ > /dev/null 2>&1; } || { printf "clang and clang++ are required to build this\n"; exit 1; }

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

rm -rf "$pwd/toolchain" "$scriptroot/build"

(
mkdir "$scriptroot/build" && cd "$scriptroot/build" || exit 1
printf "Building libtapi\n\n"
git clone https://github.com/tpoechtrager/apple-libtapi.git
(
cd apple-libtapi || exit 1
INSTALLPREFIX="$pwd/toolchain" CC=clang CXX=clang++ ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
git clone https://github.com/OldWorldOrdr/cctools-port.git -b 1009.2-ld64-907
(
cd cctools-port/cctools || exit 1
./configure --prefix="$pwd/toolchain" --bindir="$pwd/toolchain/libexec/cctools" --mandir="$pwd/toolchain/share/cctools" --with-libtapi="$pwd/toolchain"
make -j"$(nproc)"
make install
)

printf "Building ldid\n\n"
curl -# -L https://github.com/ProcursusTeam/ldid/archive/refs/tags/v2.1.5-procursus7.tar.gz | tar xz
(
cd ldid-2.1.5-procursus7 || exit 1
make CXX=clang++
mkdir -p "$pwd/toolchain/bin"
cp ldid "$pwd/toolchain/bin"
)
)

cp -a "$scriptroot"/files/* "$pwd/toolchain"

(
cd "$pwd/toolchain" || exit 1
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
