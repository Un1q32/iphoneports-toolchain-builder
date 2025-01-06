#!/bin/sh -e

if command -v nproc > /dev/null 2>&1; then
    JOBS="$(nproc)"
else
    if ! JOBS="$(sysctl -n hw.ncpu 2> /dev/null)"; then
        JOBS=1
    fi
fi

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
mkdir "$scriptroot/build" && cd "$scriptroot/build" || exit 1

printf "Building LLVM+Clang\n\n"
llvmver="19.1.6"
curl -# -L "https://github.com/llvm/llvm-project/releases/download/llvmorg-$llvmver/llvm-project-$llvmver.src.tar.xz" | tar -xJ
mkdir "llvm-project-$llvmver.src/build"
(
cd "llvm-project-$llvmver.src" || exit 1
patch -p1 < "$scriptroot/src/enable-tls.patch"
cd build || exit 1
export PATH="$scriptroot/src/bin:$PATH"
command -v clang >/dev/null && command -v clang++ >/dev/null && cmakecc='-DCMAKE_C_COMPILER=clang' && cmakecpp='-DCMAKE_CXX_COMPILER=clang++' && cmakelto='-DLLVM_ENABLE_LTO=Thin'
[ "$(uname -s)" != "Darwin" ] && command -v ld.lld >/dev/null && cmakeld='-DLLVM_ENABLE_LLD=ON'
cmake ../llvm -DCMAKE_BUILD_TYPE=Release "$cmakecc" "$cmakecpp" "$cmakeld" "$cmakelto" -DCMAKE_INSTALL_PREFIX="$pwd/iphoneports-toolchain/share/iphoneports" -DLLVM_LINK_LLVM_DYLIB=ON -DCLANG_LINK_CLANG_DYLIB=OFF -DLLVM_BUILD_TOOLS=OFF -DLLVM_ENABLE_PROJECTS='clang' -DLLVM_DISTRIBUTION_COMPONENTS='LLVM;LTO;clang;llvm-headers;clang-resource-headers;llvm-tblgen;clang-tblgen' -DLLVM_TARGETS_TO_BUILD='X86;ARM;AArch64'
make -j"$JOBS" install-distribution
make -j"$JOBS" dsymutil
mv bin/dsymutil "$pwd/iphoneports-toolchain/share/iphoneports/bin"
)

printf "Building libtapi\n\n"
tapiver="1300.6.5"
curl -# -L "https://github.com/tpoechtrager/apple-libtapi/archive/refs/heads/$tapiver.tar.gz" | tar -xz
(
cd "apple-libtapi-$tapiver" || exit 1
INSTALLPREFIX="$pwd/iphoneports-toolchain/share/iphoneports" CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++" ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
cctoolsver="1010.6-ld64-951.9"
curl -# -L "https://github.com/tpoechtrager/cctools-port/archive/refs/heads/$cctoolsver.tar.gz" | tar -xz
cp ../src/configure.h "cctools-port-$cctoolsver/cctools/ld64/src"
(
cd "cctools-port-$cctoolsver/cctools" || exit 1
./configure --prefix="$pwd/iphoneports-toolchain/share/iphoneports" --bindir="$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin" --with-libtapi="$pwd/iphoneports-toolchain/share/iphoneports" --with-llvm-config="$pwd/iphoneports-toolchain/share/iphoneports/bin/llvm-config" --enable-silent-rules CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++"
make -j"$JOBS"
make install
)

printf "Building compiler-rt\n\n"
mkdir "llvm-project-$llvmver.src/crtbuild"
(
cd "llvm-project-$llvmver.src/crtbuild"

arm64srcs="emutls.c"
armv7ssrcs="$arm64srcs atomic.c extendhfsf2.c truncsfhf2.c"
armv7srcs="$armv7ssrcs"
armv6srcs="$armv7srcs"
clang="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang"

for src in $armv6srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv6-apple-ios2 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv6-${src%\.c}.o" &
done
for src in $armv7srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv7-apple-ios3 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7-${src%\.c}.o" &
done
for src in $armv7ssrcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv7s-apple-ios6 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7s-${src%\.c}.o" &
done
for src in $arm64srcs; do
    while [ "$(pgrep clang | wc -l)" -ge "$JOBS" ]; do
        sleep 0.1
    done
    "$clang" -isysroot "$scriptroot/src/sysroot" -target arm64-apple-ios7 "../compiler-rt/lib/builtins/$src" -c -O3 -o "arm64-${src%\.c}.o" &
done
wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ios.a ./*.o
llvmshortver="$(cd "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang" && echo *)"
mkdir -p "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang/$llvmshortver/lib/darwin"
cp libclang_rt.ios.a "$pwd/iphoneports-toolchain/share/iphoneports/lib/clang/$llvmshortver/lib/darwin"
)

printf "Building ldid\n\n"
ldidver="798f55bab61c6a3cf45f81014527bbe2b473958b"
curl -# -L "https://github.com/ProcursusTeam/ldid/archive/${ldidver}.tar.gz" | tar xz
(
cd "ldid-$ldidver" || exit 1
make CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++"
mkdir -p "$pwd/iphoneports-toolchain/bin" "$pwd/iphoneports-toolchain/share/man/man1"
"$STRIP" ldid
cp ldid "$pwd/iphoneports-toolchain/bin"
cp docs/ldid.1 "$pwd/iphoneports-toolchain/share/man/man1"
)
)

(
cd "$pwd/iphoneports-toolchain" || exit 1
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
cd share/iphoneports || exit 1
for bin in cctools-bin/*; do
    [ "$bin" != "cctools-bin/cc" ] && [ "$bin" != "cctools-bin/sdkpath" ] && "$STRIP" "$bin"
done
for arch in arm i386 ppc ppc64 x86_64; do
    "$STRIP" "libexec/as/$arch/as"
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
