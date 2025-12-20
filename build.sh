#!/bin/sh -e
# shellcheck disable=2086,2031,2030

if [ "$(uname -s)" = "Darwin" ]; then
    printf 'Toolchain not supported on Darwin\n'
    exit 1
fi

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
        export JOBS
    ;;
esac

if [ -z "$STRIP" ]; then
    if command -v llvm-strip > /dev/null 2>&1; then
        STRIP='llvm-strip'
    elif command -v strip > /dev/null 2>&1; then
        STRIP='strip'
    else
        STRIP='true'
    fi
fi

[ "${0%/*}" = "$0" ] && scriptroot="." || scriptroot="${0%/*}"
scriptroot="$(realpath "$scriptroot")"
pwd="$PWD"

# Move the old SDKs out of the way
[ -d "$pwd/iphoneports-toolchain/share/iphoneports/sdks" ] &&
    mv "$pwd/iphoneports-toolchain/share/iphoneports/sdks" "$scriptroot/iphoneports-sdks"

rm -rf "$pwd/iphoneports-toolchain" "$scriptroot/build"
mkdir -p "$pwd/iphoneports-toolchain/share/iphoneports"

# Put the old SDKs back
[ -d "$scriptroot/iphoneports-sdks" ] && mv "$scriptroot/iphoneports-sdks" "$pwd/iphoneports-toolchain/share/iphoneports/sdks"

cp -a "$scriptroot"/files/* "$pwd/iphoneports-toolchain"

host="$(cc -dumpmachine)"

(
mkdir "$scriptroot/build" && cd "$scriptroot/build"

printf "Building LLVM+Clang\n\n"
llvmver="21.1.8"
curl -# -L "https://github.com/llvm/llvm-project/archive/refs/tags/llvmorg-$llvmver.tar.gz" | tar -xz
mkdir "llvm-project-llvmorg-$llvmver/build"
(
cd "llvm-project-llvmorg-$llvmver"
for patch in "$scriptroot/src"/llvm-*.patch; do
    patch -p1 < "$patch"
done
cd build
export PATH="$scriptroot/src/llvmbin:$PATH"
command -v clang >/dev/null && command -v clang++ >/dev/null && cmakecc='-DCMAKE_C_COMPILER=clang' && cmakecpp='-DCMAKE_CXX_COMPILER=clang++' && lto='Thin'
[ "$(uname -s)" != "Darwin" ] && command -v ld.lld >/dev/null && lld=ON

llvm_components() {
    for component in \
    LLVM \
    LTO \
    clang \
    llvm-headers \
    clang-resource-headers \
    llvm-tblgen \
    clang-tblgen \
    dsymutil \
    llvm-config \
    llvm-objcopy \
    llvm-objdump \
    llvm-cov \
    llvm-nm \
    llvm-profdata \
    llvm-readobj \
    llvm-size \
    llvm-strip \
    llvm-ar \
    llvm-as \
    llvm-dis \
    llvm-link \
    llc \
    opt \
    ; do
        printf '%s;' "$component"
    done
}

cmake -GNinja ../llvm \
    -DCMAKE_BUILD_TYPE=Release \
    $cmakecc \
    $cmakecpp \
    -DLLVM_ENABLE_LLD="${lld:-OFF}" \
    -DLLVM_ENABLE_LTO="${lto:-OFF}" \
    -DCMAKE_INSTALL_PREFIX="$pwd/iphoneports-toolchain/share/iphoneports" \
    -DLLVM_LINK_LLVM_DYLIB=ON \
    -DCLANG_LINK_CLANG_DYLIB=OFF \
    -DLLVM_ENABLE_PROJECTS='clang' \
    -DLLVM_DISTRIBUTION_COMPONENTS="$(llvm_components)" \
    -DLLVM_TARGETS_TO_BUILD='X86;ARM;AArch64' \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$host"
ninja -j"$JOBS" install-distribution
ninja -j"$JOBS" FileCheck
mv bin/FileCheck "$pwd/iphoneports-toolchain/share/iphoneports/bin"
)

printf "Building libtapi\n\n"
tapiver="1300.6.5"
curl -# -L "https://github.com/tpoechtrager/apple-libtapi/archive/refs/heads/$tapiver.tar.gz" | tar -xz
(
cd "apple-libtapi-$tapiver"
INSTALLPREFIX="$pwd/iphoneports-toolchain/share/iphoneports" \
    CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" \
    CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++" \
    NINJA=1 \
    ./build.sh
./install.sh
)

printf "Building cctools-port\n\n"
cctoolsver="1030.6.3-ld64-956.6"
curl -# -L "https://github.com/Un1q32/cctools-port/archive/refs/heads/$cctoolsver.tar.gz" | tar -xz
cp ../src/configure.h "cctools-port-$cctoolsver/cctools/ld64/src"
(
cd "cctools-port-$cctoolsver/cctools"
./configure \
    --prefix="$pwd/iphoneports-toolchain/share/iphoneports" \
    --bindir="$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin" \
    --with-libtapi="$pwd/iphoneports-toolchain/share/iphoneports" \
    --with-llvm-config="$pwd/iphoneports-toolchain/share/iphoneports/bin/llvm-config" \
    --enable-silent-rules \
    CC="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang" \
    CXX="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang++"
make -j"$JOBS"
make install
ln -s ../cctools-bin/lipo "$pwd/iphoneports-toolchain/share/iphoneports/bin"
ln -s ../cctools-bin/otool "$pwd/iphoneports-toolchain/share/iphoneports/bin"
ln -s ../cctools-bin/install_name_tool "$pwd/iphoneports-toolchain/share/iphoneports/bin"
)

printf "Building compiler-rt\n\n"
mkdir "llvm-project-llvmorg-$llvmver/crtbuild"
(
cd "llvm-project-llvmorg-$llvmver/crtbuild"
curl -L -s -o ../compiler-rt/ubsan.c https://raw.githubusercontent.com/Un1q32/ubsan/e1fe5250c54406f32860c9e91a059198d7b25c43/ubsan.c

x64srcs="emutls.c eprintf.c int_util.c extendhfsf2.c truncsfhf2.c truncdfhf2.c truncxfhf2.c"
x32srcs="$x64srcs atomic.c"

arm64srcs="emutls.c"
armv7ssrcs="$arm64srcs atomic.c extendhfsf2.c truncsfhf2.c truncdfhf2.c"
armv7srcs="$armv7ssrcs"
armv6srcs="$armv7srcs floatundisf.c floatundidf.c"
clang="$pwd/iphoneports-toolchain/share/iphoneports/bin/clang"

for src in $armv6srcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv6-apple-ios1 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv6-${src%\.c}.o" &
done
for src in $armv7srcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv7-apple-ios3 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7-${src%\.c}.o" &
done
for src in $armv7ssrcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target armv7s-apple-ios6 "../compiler-rt/lib/builtins/$src" -c -O3 -o "armv7s-${src%\.c}.o" &
done
for src in $arm64srcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target arm64-apple-ios7 "../compiler-rt/lib/builtins/$src" -c -O3 -o "arm64-${src%\.c}.o" &
done
"$clang" -target arm64e-apple-ios14 -xc /dev/null -c -o nothing.o &
wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ios.a ./*.o 2>/dev/null
rm ./*.o

for src in $x32srcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target i386-apple-macos10.4 "../compiler-rt/lib/builtins/$src" -c -O3 -o "i386-${src%\.c}.o" &
done
for src in $x64srcs; do
    "$clang" -isysroot "$scriptroot/src/sysroot" -target x86_64-apple-macos10.4 "../compiler-rt/lib/builtins/$src" -c -O3 -o "x86_64-${src%\.c}.o" &
done
"$clang" -target arm64-apple-macos11.0 -arch arm64 -arch arm64e -xc /dev/null -c -o nothing.o &
wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.osx.a ./*.o 2>/dev/null
rm ./*.o

"${clang}++" -isysroot "$scriptroot/src/sysroot" \
    -o ubsan_minimal_ios.o \
    -target unknown-apple-ios \
    -arch armv6 -Xarch_armv6 -mios-version-min=1.0 \
    -arch armv7 -Xarch_armv7 -mios-version-min=3.0 \
    -arch armv7s -Xarch_armv7s -mios-version-min=6.0 \
    -arch arm64 -Xarch_arm64 -mios-version-min=7.0 \
    -arch arm64e -Xarch_arm64e -mios-version-min=14.0 \
    ../compiler-rt/lib/ubsan_minimal/ubsan_minimal_handlers.cpp \
    -O3 -c -I../compiler-rt/lib &

"${clang}++" -isysroot "$scriptroot/src/sysroot" \
    -o ubsan_minimal_osx.o \
    -target unknown-apple-macos \
    -arch i386 -Xarch_i386 -mmacos-version-min=10.4 \
    -arch x86_64 -Xarch_x86_64 -mmacos-version-min=10.4 \
    -arch arm64 -Xarch_arm64 -mmacos-version-min=11.0 \
    -arch arm64e -Xarch_arm64e -mmacos-version-min=11.0 \
    ../compiler-rt/lib/ubsan_minimal/ubsan_minimal_handlers.cpp \
    -O3 -c -I../compiler-rt/lib &

"$clang" -isysroot "$scriptroot/src/sysroot" \
    -o ubsan_ios.o \
    -target unknown-apple-ios \
    -arch armv6 -Xarch_armv6 -mios-version-min=1.0 \
    -arch armv7 -Xarch_armv7 -mios-version-min=3.0 \
    -arch armv7s -Xarch_armv7s -mios-version-min=6.0 \
    -arch arm64 -Xarch_arm64 -mios-version-min=7.0 \
    -arch arm64e -Xarch_arm64e -mios-version-min=14.0 \
    ../compiler-rt/ubsan.c \
    -O3 -c &

"$clang" -isysroot "$scriptroot/src/sysroot" \
    -o ubsan_osx.o \
    -target unknown-apple-macos \
    -arch i386 -Xarch_i386 -mmacos-version-min=10.4 \
    -arch x86_64 -Xarch_x86_64 -mmacos-version-min=10.4 \
    -arch arm64 -Xarch_arm64 -mmacos-version-min=11.0 \
    -arch arm64e -Xarch_arm64e -mmacos-version-min=11.0 \
    ../compiler-rt/ubsan.c \
    -O3 -c

wait

"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ubsan_minimal_ios.a ubsan_minimal_ios.o
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ubsan_minimal_osx.a ubsan_minimal_osx.o
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ubsan_ios.a ubsan_ios.o
"$pwd/iphoneports-toolchain/share/iphoneports/cctools-bin/libtool" -static -o libclang_rt.ubsan_osx.a ubsan_osx.o
rm ./*.o

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

case $host in
    (x86_64-*-linux-gnu) host=x86_64-unknown-linux-gnu ;;
    (x86_64-*-linux-musl) host=x86_64-unknown-linux-musl ;;
esac
printf "Building rust\n\n"
rustver="1.92.0"
curl -# -L "https://static.rust-lang.org/dist/rustc-${rustver}-src.tar.xz" | tar xJ && success=1
tries=4
[ -z "$success" ] && printf 'Failed to download rust sources, tries remaining: %s\n' "$tries"
while [ -z "$success" ] && [ "$tries" -gt 0 ]; do
    if curl -# -L "https://static.rust-lang.org/dist/rustc-${rustver}-src.tar.xz" | tar xJ; then
        success=1
    else
        printf 'Failed to download rust sources, tries remaining: %s\n' "$tries"
        tries=$((tries - 1))
    fi
done
if [ -z "$success" ]; then
    printf 'Failed to download rust sources after 5 tries\n'
    exit 1
fi
(
cd rustc-*/
sed -e "s|@PREFIX@|$pwd/iphoneports-toolchain/share/iphoneports|g" \
    -e "s|@LLVMCONFIG@|$pwd/iphoneports-toolchain/share/iphoneports/bin/llvm-config|g" \
    -e "s|@HOST@|$host|g" "$scriptroot/src/bootstrap.toml" > bootstrap.toml
patch -p1 < "$scriptroot/src/rust-legacy-darwin.patch"
PATH="$pwd/iphoneports-toolchain/share/iphoneports/bin:$PATH" \
    SDKROOT="$scriptroot/src/sysroot" \
    LD_LIBRARY_PATH="$LD_LIBRARY_PATH:$pwd/iphoneports-toolchain/share/iphoneports/lib" \
    CC=clang \
    BOOTSTRAP_SKIP_TARGET_SANITY=1 \
    ./x install -j "$JOBS"
ln -s "../../../$(readlink "$pwd/iphoneports-toolchain/share/iphoneports/lib/libLLVM.so")" "$pwd/iphoneports-toolchain/share/iphoneports/lib/rustlib/$host/lib"
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
    [ "$target" != "share/iphoneports/sdks/*" ] && ./bin/iphoneports-add-target "${target##*/}"
done
cd share/iphoneports
for bin in cctools-bin/*; do
    [ "$bin" != "cctools-bin/cc" ] && [ "$bin" != "cctools-bin/sdkpath" ] && "$STRIP" "$bin"
done
rm -rf \
    include \
    bin/llc \
    bin/opt \
    bin/llvm-link \
    bin/llvm-config \
    bin/llvm-objcopy \
    bin/llvm-size \
    bin/llvm-strip \
    bin/llvm-ar \
    bin/llvm-as \
    bin/llvm-readobj \
    bin/llvm-profdata \
    bin/llvm-objdump \
    bin/llvm-dis \
    bin/llvm-cov \
    bin/FileCheck \
    bin/rust-*
for bin in bin/* lib/*; do
    if [ ! -h "$bin" ] && [ -f "$bin" ]; then
        "$STRIP" "$bin"
    fi
done
)
