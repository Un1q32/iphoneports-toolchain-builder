#!/bin/sh -e
rm -rf cctools-port apple-libtapi ldid-2.1.5-procursus7 toolchain
{ command -v clang > /dev/null 2>&1 && command -v clang++ > /dev/null 2>&1; } || { printf "clang and clang++ are required to build this\n"; exit 1; }

[ "${0%/*}" = "$0" ] && scriptroot="." || scriptroot="${0%/*}"
pwd="$PWD"

printf "Building libtapi\n\n"
git clone https://github.com/tpoechtrager/apple-libtapi.git
(
cd apple-libtapi || exit 1
INSTALLPREFIX="$pwd/toolchain" CC=clang CXX=clang++ ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
git clone https://github.com/OldWorldOrdr/cctools-port.git
(
cd cctools-port/cctools || exit 1
./configure --prefix="$pwd/toolchain" --bindir="$pwd/toolchain/libexec/cctools" --mandir="$pwd/toolchain/share/cctools" --with-libtapi="$pwd/toolchain"
make -j"$(nproc)"
make install
)

printf "Building ldid\n\n"
wget https://github.com/ProcursusTeam/ldid/archive/refs/tags/v2.1.5-procursus7.tar.gz -q -O- | tar xz
(
cd ldid-2.1.5-procursus7 || exit 1
make CXX=clang++
mkdir -p "$pwd/toolchain/bin"
cp ldid "$pwd/toolchain/bin"
)

cp -ar "$scriptroot/bin" "$scriptroot/etc" "$scriptroot/libexec" toolchain

(
cd toolchain || exit 1
strip libexec/cctools/*
for as in arm i386 ppc ppc64 x86_64; do
    strip "libexec/as/$as/as"
done
for link in c++ clang clang++ gcc g++; do
    ln -s cc "libexec/iphoneports/$link"
done
rm -rf include
)
