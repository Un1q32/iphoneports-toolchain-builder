# iPhonePorts toolchain builder

> Darwin toolchain focused on older versions, for use with iPhonePorts

## Requirements

- libdispatch-dev and libblocksruntime
- libstdc++ or libc++ with C++20 support
- Systems with musl require musl-fts

## Building

```sh
git clone https://github.com/Un1q32/iphoneports-toolchain-builder.git
./iphoneports-toolchain-builder/build.sh
export PATH="$PWD/iphoneports-toolchain/bin:$PATH"
```

build.sh will create an iphoneports-toolchain folder in the currect directory containing the toolchain

### Adding targets

You can download the SDKs used for iPhonePorts [here](https://github.com/Un1q32/iphoneports-sdk), this will allow you to build the packages in https://github.com/Un1q32/iphoneports

SDKs for other versions of iOS can be found at https://invoxiplaygames.uk/sdks or by extracting old Xcode versions

Place your extracted SDK in iphoneports-toolchain/share/iphoneports/sdks, the SDK should be named after the target it will be used for.

For example, if you want to build for armv6-apple-darwin10 with the iPhonePorts iOS 3.0 SDK, you should extract iPhoneOS3.0.sdk.tar.xz, and move the armv6-apple-darwin10 folder to iphoneports-toolchain/share/iphoneports/sdks, then run `iphoneports-add-target armv6-apple-darwin10`

You may have to crate a config file for your target, look in iphoneports-toolchain/etc/iphoneports to see if your target already has a config file, if it doesn't then try modifying one of the existing ones.
A config file is just a single line shell script that sets arguements to be passed to clang, for example `set -- -mios-version-min=3.0 "$@"` or `set -- -mmacos-version-min=10.5 "$@"`
