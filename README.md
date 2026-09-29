# Miaopu iOS

这是独立开发的 iOS 客户端。原 Android 应用仅供核对赛事接口、页面布局和跳转流程。此仓库使用全新的代码、资源、测试数据及 Git 历史。iOS 源码和测试分别位于 `ios/Miaopu`、`ios/MiaopuTests`；Xcode 工程由 `ios/project.yml` 生成。

## Generate and build

Install XcodeGen, then run:

```sh
brew install xcodegen
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/Miaopu.xcodeproj -scheme Miaopu -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

The generated project targets iOS 17 and uses the temporary bundle identifier `com.liansishen.miaopu`. GitHub Actions runs available simulator tests and builds an unsigned iPhoneOS app. A local unsigned IPA can be packaged on macOS with:

```sh
APP_PATH="$(pwd)/build/DerivedData/Build/Products/Release-iphoneos/Miaopu.app" \
  OUTPUT_IPA="$(pwd)/unsigned.ipa" scripts/package-unsigned-ipa.sh
```

The script verifies the app executable, arm64 architecture, Info.plist, and absence of a code signature; it outputs a SHA-256 checksum alongside the IPA. The IPA is unsigned and is not installable until properly signed.
