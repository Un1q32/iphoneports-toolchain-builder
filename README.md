# iOS-toolchain-build

> Builds an iOS toolchain for use with iPhonePorts

## Requirements

- Clang 16+

## Setup

```sh
./build.sh [targets...]
```

`build.sh` will create a toolchain folder in the currect directory containing the toolchain

You can add a target with `cctools-add-target` in `toolchain/bin`, or optionally with the first arguement to `./build.sh`

You may have to crate a clang config file for your target, look in `toolchain/etc/iphoneports` to see if your target already has a config file, if it doesn't then try modifying one of the existing ones.

### SDK

You can download the SDK used for iPhonePorts builds [here](https://github.com/OldWorldOrdr/iphoneports-sdk/raw/master/iPhoneOS5.0.sdk.tar.xz)

SDKs for other versions of iOS can be found at https://invoxiplaygames.uk/sdks

Place your extracted SDK in `toolchain/share/iphoneports/`, the SDK should be named after the target it will be used for

For example, if you want to build for `armv7-apple-darwin11` with the iOS 5.0 SDK, you should extract `iPhoneOS5.0.sdk.tar.xz`, rename the `iPhoneOS5.0.sdk` folder to `armv7-apple-darwin11`, and move it to `toolchain/share/iphoneports`
