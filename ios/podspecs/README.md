# onnxruntime-c from NuGet

`onnxruntime-c.podspec.json` takes ONNX Runtime 1.30.0 for iOS from Microsoft's
official NuGet package, `Microsoft.ML.OnnxRuntime` 1.30.0. The CocoaPods
archive the original pod pointed at (download.onnxruntime.ai) is gone.

- URL: https://api.nuget.org/v3-flatcontainer/microsoft.ml.onnxruntime/1.30.0/microsoft.ml.onnxruntime.1.30.0.nupkg
- Size: 157,230,753 bytes
- SHA-256 (pinned in the podspec): `30df119bd9164eaa187666d93147448fdd4a9a1a3caf83f1505daf7af2d1c5d2`
- SHA-512 as nuget.org publishes it (`packageHash` in the catalog entry for 1.30.0):
  `xTgo+P2WWI1BrKQb91+G8YR1s/SFH07xZuc42kdgS2I6GLGOAKnMVhFqCk7nmce6L6ajho8wAcqixYAiwfE79g==`
- Signatures (`dotnet nuget verify --all`, exit 0):
  - Author: CN=Microsoft Corporation, O=Microsoft Corporation, L=Redmond, S=Washington, C=US
  - Repository: CN=NuGet.org Repository by Microsoft, O=NuGet.org Repository by Microsoft, L=Redmond, S=Washington, C=US

The podspec's `prepare_command` unpacks `runtimes/ios/native/onnxruntime.xcframework.zip`
as published (device, simulator and Mac Catalyst slices, all static), copies its
headers to `Headers/`, keeps `LICENSE` and `ThirdPartyNotices.txt`, and deletes the
rest of the package. The podspec otherwise matches the original
`onnxruntime-c` 1.30.0 pod (iOS 15.1, static framework, `c++`, weak CoreML).

This is a different build from the original pod's binary: same version, headers
and C API, but fewer KleidiAI kernels in the arm64 code. See the change that
introduced this file for the comparison.
