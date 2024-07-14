# iOS-toolchain-build

> Darwin toolchain focused on older iOS versions, for use with iPhonePorts

## Requirements

- LLVM+Clang
- libdispatch-dev and libblocksruntime
- libstdc++ or libc++ with C++20 support
- Systems with musl require musl-fts

## Usage

```sh
./build.sh [targets...]
```

`build.sh` will create a toolchain folder in the currect directory containing the toolchain

You can add a target with `iphoneports-add-target` in `toolchain/bin`, or optionally with the first arguement to `./build.sh`

You may have to crate a config file for your target, look in `toolchain/etc/iphoneports` to see if your target already has a config file, if it doesn't then try modifying one of the existing ones.
A config file is just a single line with a clang minimum version arguement, for example `-mios-version-min=3.1` or `-mmacos-version-min=10.6`

### SDK

You can download the SDK used for iPhonePorts builds [here](https://github.com/Un1q32/iphoneports-sdk/raw/master/iPhoneOS3.1.sdk.tar.xz)

SDKs for other versions of iOS can be found at https://invoxiplaygames.uk/sdks

Place your extracted SDK in `toolchain/share/iphoneports/`, the SDK should be named after the target it will be used for

For example, if you want to build for `armv6-apple-darwin10` with the iOS 3.1 SDK, you should extract `iPhoneOS3.1.sdk.tar.xz`, rename the `iPhoneOS3.1.sdk` folder to `armv6-apple-darwin10`, and move it to `toolchain/share/iphoneports`
