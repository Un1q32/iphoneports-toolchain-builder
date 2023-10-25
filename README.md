# iOS-toolchain-build

> Builds an iOS toolchain for use with iPhonePorts

## Requirements

- Clang 16+

## Setup

```sh
./build.sh [target]
```

`build.sh` will create a toolchain folder in the currect directory containing the toolchain

You can add a target with `cctools-add-target` in `toolchain/bin`, or optionally with the first arguement to `./build.sh`

### SDK

You can download a compatible iOS SDK from https://github.com/OldWorldOrdr/ios-sdks

Place your extracted SDK in `toolchain/share/iphoneports/`, the SDK should be named after the target it will be used for

For example, if you want to build for `armv7-apple-darwin11` with the iOS 5.0 SDK, you should extract `iPhoneOS5.0.sdk.tar.lzma`, rename the `iPhoneOS5.0.sdk` folder to `armv7-apple-darwin11`, and move it to `toolchain/share/iphoneports`
