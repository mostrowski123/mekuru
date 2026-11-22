# onnxruntime-objc 1.30.0 (vendored)

ONNX Runtime's Objective-C API, used by `AppDelegate.swift` (`import onnxruntime_objc`).
These are the Core sources of the `onnxruntime-objc` 1.30.0 CocoaPods pod
(MIT, Copyright (c) Microsoft Corporation), fetched from download.onnxruntime.ai
before that archive went away, and copied here **unmodified**: the 24 files of
the pod's `Core` subspec in their original paths, plus its `LICENSE`. The pod's
test files are left out. NuGet has no Objective-C wrapper, so it lives here; the
C library comes from `ios/podspecs/onnxruntime-c.podspec.json`.

`onnxruntime-objc.podspec.json` mirrors the original pod's `Core` subspec
(ARC, the same source files, public headers and compiler flags, depending on
`onnxruntime-c` 1.30.0). The Podfile takes it with `:path`, so its `source`
is never fetched.

SHA-256 of each file:

```
2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c  LICENSE
aab93d9425d536d977c81645dcf8ec75716e99c7821ee7957b4b1ddcd80ab162  objectivec/assert_arc_enabled.mm
75e3e9310cb87b84a6fb23c5c8434615d1c579b5532d9cdb9a2369e1acfc6dcd  objectivec/cxx_api.h
744a798406533692ccbd50b62b239879a1c6d45ac400b8dcc88f4263c91c827a  objectivec/cxx_utils.h
135427cf4731534883b43488657508e2b2579bcada8b50d2ac1f9d452f9c255a  objectivec/cxx_utils.mm
707fcf877787e194676d126e360d79a8e852fe5afe6c8923ece6daa22a7b6fa1  objectivec/error_utils.h
c2ae7e19e671c740e16e51cbd95da6a102b31451e5f09ac00269749b60c42057  objectivec/error_utils.mm
d6ab3c3a663be02ffd410c7518f41a8b7f32c7c08c0ddef2fb76cb7a8752644e  objectivec/include/onnxruntime.h
fc1fc2c2fae71fba26b614e45360e4a2c010b6ae640b0c59fef04ee2d8527c71  objectivec/include/ort_coreml_execution_provider.h
d97dd2b71938cf4b061d2d449e4a2ba3b1560117c679471adb2b30b09d0e9f40  objectivec/include/ort_custom_op_registration.h
8c4e682f88542aa8aeabe37728ca968f5c1e3594df48337d6f8da21da0e62c43  objectivec/include/ort_enums.h
efc7114700f6fbcba1dc50f1a28d2412ab11b113239184659cee277ccb2c145b  objectivec/include/ort_env.h
3c02b4e667c5a3d6915050045bb457427da267f768be0e22f64624bd97310df3  objectivec/include/ort_session.h
a0a184d646c923ceaa03316bcc05804906742e4cb3e13b10cba62d073c8c3479  objectivec/include/ort_value.h
9077d53609bf0a8d730294838f8564bb81b1fff156d44c5e97ad057949bc2b78  objectivec/include/ort_xnnpack_execution_provider.h
8e144810c98171909d45a40f957fe52457d3a74869315da6b8c8d6e80124a97a  objectivec/ort_coreml_execution_provider.mm
1e571c5518fa429dfd4879ad6b7908defa0bb1920bb56889d85fa4d1b0ff20f7  objectivec/ort_enums.mm
a902dc8256f4baf92aa2bef85f7fad5699ca97348fb681610296f07114dba5e8  objectivec/ort_enums_internal.h
ecb64e72f4893d28c098a9673827ba298fe8fb0d3ea7c0e96adf17c1ef495830  objectivec/ort_env.mm
c5ef9dad85280fcbb80b61416c2aed12cda223e48936b9566a9f55732619a64a  objectivec/ort_env_internal.h
addb7875db82efbb38a58c33bd13e272a591a1fe09b1ffed223acb82ff293656  objectivec/ort_session.mm
3d7857679ca64872f629870212468f55e6ed7347dd867924fcaff9ace31f4ceb  objectivec/ort_session_internal.h
9e00f7c574a5da57ccd83387c6948d8911e2a1fce7faa4de5f711fbd5ad8a6a5  objectivec/ort_value.mm
1440dc2e2f5645da8302fa28643691cba92410e18b8787caf561edd8c735b074  objectivec/ort_value_internal.h
f2b53c623ca4e2007a91bf835bee155cee0cbee4c1358b1b51898c7c4d6407ee  objectivec/ort_xnnpack_execution_provider.mm
```
