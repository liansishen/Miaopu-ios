# Miaopu iOS

这是独立开发的 iOS 客户端。原 Android 应用仅供核对赛事接口、页面布局和跳转流程。此仓库使用全新的代码、资源、测试数据及 Git 历史。iOS 源码和测试分别位于 `ios/Miaopu`、`ios/MiaopuTests`；Xcode 工程由 `ios/project.yml` 生成。

## 当前功能

首页显示关注赛事的赛程；赛事页支持切换项目与搜索；比赛详情显示评分和分局，评论支持分页与回复浏览；个人页提供订阅管理与虎扑网页登录。WidgetKit 提供单场赛况及近期赛程两个小组件。登录后的评分、评论、回复和点赞请求已有客户端接口，交互页面仍在完善。图片保存、更新检查与完整赛事覆盖也待实现。

## 本地构建

在 macOS 安装 XcodeGen，然后运行：

```sh
brew install xcodegen
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/Miaopu.xcodeproj -scheme Miaopu -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

工程最低支持 iOS 17，Bundle ID 暂定为 `com.liansishen.miaopu`。GitHub Actions 在模拟器运行测试，并针对 iPhoneOS SDK 构建未签名应用。使用以下命令在 macOS 打包本地构建的应用：

```sh
APP_PATH="$(pwd)/build/DerivedData/Build/Products/Release-iphoneos/Miaopu.app" \
  OUTPUT_IPA="$(pwd)/unsigned.ipa" scripts/package-unsigned-ipa.sh
```

打包脚本检查应用及 WidgetKit 扩展的 arm64 架构和无签名状态，并生成 SHA-256 校验文件。未签名 IPA 需要后续签名才能安装；当前只进行模拟器与 CI 验证。
