<div align="center">

# 喵扑 iOS

iOS 第三方虎扑赛事评分客户端

[下载应用](https://github.com/liansishen/Miaopu-ios/releases/latest) · [问题反馈](https://github.com/liansishen/Miaopu-ios/issues)

</div>

## 简介

喵扑专注于电竞与体育赛事的赛程、选手评分和赛事讨论，涵盖英雄联盟、无畏契约、CS2、篮球、足球等项目。用户可以按关注的赛事订阅内容，查看比赛结果、各局选手表现及虎扑社区讨论。本客户端使用 SwiftUI 开发，最低支持 iOS 17。

iOS 版参考 [喵扑 Android 版](https://github.com/KiritoXDone/Miaopu) 的接口、页面布局与跳转流程实现，感谢原作者的开源工作。

## 下载与使用

在 [Releases](https://github.com/liansishen/Miaopu-ios/releases/latest) 下载 IPA，支持 **iOS 17.0 及以上** 版本。CI 产出的是**未签名 IPA**，安装前需要自行签名；每个 Release 附带 `.sha256` 文件用于校验下载完整性。

赛事订阅位于 **我的 → 赛事订阅**，支持调整订阅顺序。首页汇总已订阅项目的近期赛程（本机今天前后各两天），可一键刷新；赛事页提供各项目完整赛程、日期分组、快速跳转今天与按日期快速定位。

比赛详情包含比分、全场评分、单局与队伍切换、排序和选手卡片；有技术统计的比赛会显示「数据」标签页。选手评分页包含资料卡、评分分布、我的评分（5 星）与评论列表，评论可按最热或最新排序，支持图片预览与保存、查看回复、点赞与取消点赞。

浏览赛程、评分和评论无需登录。参与评分、发表评论、回复或点赞需在 **我的** 中登录虎扑账号。

桌面提供 **单场赛况**与**近期赛程**两种小组件，跟随应用内的赛事订阅；点击比赛可跳转到详情。

## 本地构建

在 macOS 安装 XcodeGen，然后运行：

```sh
brew install xcodegen
cd ios && xcodegen generate && cd ..
xcodebuild -project ios/Miaopu.xcodeproj -scheme Miaopu -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

针对真机 SDK 构建未签名应用并打包 IPA：

```sh
xcodebuild -project ios/Miaopu.xcodeproj -scheme Miaopu \
  -configuration Release -sdk iphoneos -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
APP_PATH="$(pwd)/build/DerivedData/Build/Products/Release-iphoneos/Miaopu.app" \
  OUTPUT_IPA="$(pwd)/unsigned.ipa" scripts/package-unsigned-ipa.sh
```

打包脚本检查应用与 WidgetKit 扩展的 arm64 架构、无签名状态和应用图标，并生成 SHA-256 校验文件。

## 发布

推送 `vX.Y.Z` 标签后，`.github/workflows/ios-release.yml` 在测试、无签名构建、图标与包校验通过时创建 GitHub Release，并附上 IPA 和 SHA-256 校验文件。标签版本必须等于 `ios/project.yml` 中的 `MARKETING_VERSION`，仓库还需包含 `docs/releases/X.Y.Z.md`。

`ios.yml` 只在 `ios/**`、`scripts/**` 与工作流文件发生变化时运行，文档与许可证改动不会触发；标签推送由发布工作流负责测试与打包。

## 反馈与贡献

问题反馈和功能建议请提交至 [Issues](https://github.com/liansishen/Miaopu-ios/issues)。问题报告请附上应用版本、iOS 版本、相关赛事及复现步骤，必要时提供截图，并隐去个人信息。

## 致谢

感谢 [喵扑 Android 版](https://github.com/KiritoXDone/Miaopu) 在接口、页面布局与跳转流程上提供的参考，虎扑及其社区用户提供的赛事内容与讨论，以及 XcodeGen 等开源项目。

## 开源协议

Copyright (c) 2026 liansishen

本项目原创代码采用 [MIT 许可证](LICENSE) 授权。第三方依赖遵循各自的许可证；虎扑赛事数据、用户评论，以及界面中的头像、队标等第三方内容不属于本项目的授权范围，其权利归各自权利人所有。

## 声明

喵扑是独立的第三方项目，与虎扑官方无隶属关系。赛事、评分与评论内容归其各自权利人所有。
