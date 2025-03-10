#!/bin/sh -e
# shellcheck disable=SC2086

case $JOBS in
    ''|*[!0-9]*)
        if command -v nproc > /dev/null; then
            cpus=$(nproc)
        else
            cpus=$(sysctl -n hw.ncpu 2> /dev/null)
            [ -z "$cpus" ] && cpus=1
        fi

        JOBS=$((cpus * 2 / 3))
        [ "$JOBS" = 0 ] && JOBS=1
    ;;
esac
export JOBS

if [ -z "$STRIP" ]; then
    if command -v llvm-strip > /dev/null 2>&1; then
        STRIP='llvm-strip'
    elif command -v strip > /dev/null 2>&1; then
        STRIP='strip'
    else
        STRIP='touch'
    fi
fi

[ "${0%/*}" = "$0" ] && scriptroot="." || scriptroot="${0%/*}"
scriptroot="$(realpath "$scriptroot")"
pwd="$PWD"

# Move the old SDKs out of the way
[ -d "$pwd/iphoneports-toolchain/share/iphoneports/sdks" ] && mv "$pwd/iphoneports-toolchain/share/iphoneports/sdks" "$scriptroot/iphoneports-sdks"

rm -rf "$pwd/iphoneports-toolchain" "$scriptroot/build"
mkdir -p "$pwd/iphoneports-toolchain/share/iphoneports"

# Put the old SDKs back
[ -d "$scriptroot/iphoneports-sdks" ] && mv "$scriptroot/iphoneports-sdks" "$pwd/iphoneports-toolchain/share/iphoneports/sdks"

cp -a "$scriptroot"/files/* "$pwd/iphoneports-toolchain"

(
mkdir "$scriptroot/build" && cd "$scriptroot/build"

printf "Building LLVM+Clang\n\n"
llvmver="20.1.0"
curl -# -L "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvmver/llvm-project-$llvmver.src.tar.xz" | tar -xJ
mkdir "llvm-project-$llvmver.src/build"
(
cd "llvm-project-$llvmver.src"
patch -p1 < "$scriptroot/src/enable-tls.patch"
patch -p1 < "$scriptroot/src/libgcc.patch"
cd build
export PATH="$scriptroot/src/bin:$PATH"
command -v clang >/dev/null && command -v clang++ >/dev/null && cmakecc='-DCMAKE_C_COMPILER=clang' && cmakecpp='-DCMAKE_CXX_COMPILER=clang++' && lto='Thin'
[ "$(uname -s)" != "Darwin" ] && command -v ld.lld >/dev/null && lld=ON
cmake ../llvm -DCMAKE_BUILD_TYPE=Release $cmakecc $cmakecpp -DLLVM_ENABLE_LLD="${lld:-OFF}" -DLLVM_ENABLE_LTO="${lto:-OFF}" -DCMAKE_INSTALL_PREFIX="$pwd/iphoneports-toolchain/share/iphoneports" -DLLVM_LINK_LLVM_DYLIB=ON -DCLANG_LINK_CLANG_DYLIB=OFF -DLLVM_BUILD_TOOLS=OFF -DLLVM_ENABLE_PROJECTS='clang' -DLLVM_DISTRIBUTION_COMPONENTS='LLVM;LTO;clang;llvm-headers;clang-resource-headers;llvm-tblgen;clang-tblgen' -DLLVM_TARGETS_TO_BUILD='X86;ARM;AArch64' -DLLVM_DEFAULT_TARGET_TRIPLE="$(cc -dumpmachine)"
make -j"$JOBS" install-distribution
make -j"$JOBS" dsymutil
mv bin/dsymutil "$pwd/iphoneports-toolchain/share/iphoneports/bin"
)

printf "Building libtapi\n\n"
tapiver="1300.6.5"
curl -# -L "https://github.com/tpoechtrager/apple-libtapi/archive/refs/heads/$tapiver.tar.gz" | tar -xz
(
cd "apple-libtapi-$tapiver"
patch -p1 < "$scriptroot/src/lseek64.patch"
INSTALLPREFIX="$pwd/iphoneports-toolchain/share/iphoneports" CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++" ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
cctoolsver="1021.4-ld64-954.16"
curl -# -L "https://github.com/Un1q32/cctools-port/archive/refs/heads/$cctoolsver.tar.gz" | tar -xz
cp ../src/configure.h "cctools-port-$cctoolsver/cctools/ld64/src"
(
cd "cctools-port-$cctoolsver/cctools"
./configure --prefix="$pwd/iphoneports-toolchain/share/iphoneports" --bindir="$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin" --with-libtapi="$pwd/iphoneports-toolchain/share/iphoneports" --with-llvm-config="$pwd/iphoneports-toolchain/share/iphoneports/bin/llvm-config" --enable-silent-rules CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++"
make -j"$JOBS"
make install
)

printf "Building compiler-rt\n\n"
mkdir "llvm-project-$llvmver.src/crtbuild"
(
cd "llvm-project-$llvmver.src/crtbuild"

x64srcs="emutls.c eprintf.c int_util.c"
x32srcs="$x64srcs atomic.c"

arm64srcs="emutls.c"
armv7ssrcs="$arm64srcs atomic.c extendhfsf2.c truncsfhf2.c"
armv7srcs="$armv7ssrcs"
armv6srcs="$armv7srcs"
clang="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang"

for src in $armv6srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/iossysroot" -target armv6-apple-ios2 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv6-${src%\.c}.o" &
done
for src in $armv7srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/iossysroot" -target armv7-apple-ios3 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7-${src%\.c}.o" &
done
for src in $armv7ssrcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/iossysroot" -target armv7s-apple-ios6 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7s-${src%\.c}.o" &
done
for src in $arm64srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/iossysroot" -target arm64-apple-ios7 "../compiler-rt/lib/builtins/$src" -c -O3 -o "arm64-${src%\.c}.o" &
done
wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o builtins.a ./*.o
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/ar" rc nothing.a /dev/null
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/lipo" -create builtins.a -arch arm64e nothing.a -output libclang_rt.ios.a
rm ./*.o nothing.a builtins.a

for src in $x32srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/macsysroot" -target i386-apple-macos10.4 "../compiler-rt/lib/builtins/$src" -c -O3 -o "i386-${src%\.c}.o" &
done
for src in $x64srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/macsysroot" -target x86_64-apple-macos10.4 "../compiler-rt/lib/builtins/$src" -c -O3 -o "x86_64-${src%\.c}.o" &
done
wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o builtins.a ./*.o
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/ar" rc nothing.a /dev/null
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/lipo" -create builtins.a -arch arm64e nothing.a -arch arm64 nothing.a -output libclang_rt.osx.a
rm ./*.o nothing.a builtins.a

llvmshortver="$(cd "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang" && echo *)"
mkdir -p "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang/$llvmshortver/lib/darwin"
cp ./*.a "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang/$llvmshortver/lib/darwin"
)

printf "Building ldid\n\n"
ldidver="798f55bab61c6a3cf45f81014527bbe2b473958b"
curl -# -L "https://github.com/ProcursusTeam/ldid/archive/${ldidver}.tar.gz" | tar xz
(
cd "ldid-$ldidver"
make CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++"
mkdir -p "$pwd/iphoneports-toolchain/bin" "$pwd/iphoneports-toolchain/share/man/man1"
"$STRIP" ldid
cp ldid "$pwd/iphoneports-toolchain/bin"
cp docs/ldid.1 "$pwd/iphoneports-toolchain/share/man/man1"
)
)

(
cd "$pwd/iphoneports-toolchain"
mkdir -p share/iphoneports/sdks
if [ -n "$1" ]; then
    printf '\n'
    for target in "$@"; do
        ./bin/iphoneports-add-target "$target"
    done
fi
for target in share/iphoneports/sdks/*; do
    ./bin/iphoneports-add-target "${target##*/}"
done
cd share/iphoneports
for bin in cctools-bin/*; do
    [ "$bin" != "cctools-bin/cc" ] && [ "$bin" != "cctools-bin/sdkpath" ] && "$STRIP" "$bin"
done
rm -rf include bin/llvm-config
for lib in lib/*; do
    if [ ! -h "$lib" ] && [ -f "$lib" ]; then
        "$STRIP" "$lib"
    fi
done
for bin in clang llvm-tblgen clang-tblgen dsymutil; do
    "$STRIP" "$(realpath bin/"$bin")"
done
)
