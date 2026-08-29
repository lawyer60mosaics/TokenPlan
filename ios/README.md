# TokenPlan iOS

原生 SwiftUI 客户端，兼容 Windows TokenPlan 当前的云端密文格式。

## 当前功能

- 查看、新增、编辑、删除八类套餐配置。
- 云服务器地址内置，设置页只需要输入账号和密码。
- 从账号密码分别派生认证密钥和数据密钥，两种用途不会共用密钥。
- 使用 Swift-Sodium XChaCha20-Poly1305、24 字节随机 nonce 和 `tokenplan-vault-v2` AAD，与 Rust 客户端互通。
- 账号和密码存入 Keychain，访问级别为 `WhenUnlockedThisDeviceOnly`。
- 解密后的本地套餐文件使用 iOS Complete File Protection 和原子写入。
- 使用 revision + `If-Match` 阻止离线设备静默覆盖较新的云端数据。

## 在 macOS 生成工程

```bash
brew install xcodegen
cd ios
xcodegen generate
open TokenPlan.xcodeproj
```

在 Xcode 的 Signing & Capabilities 中选择自己的 Team。Bundle ID 默认是 `com.xuwenxu.tokenplan`，如已被占用需同时修改 `project.yml`。

## 验证

```bash
xcodegen generate
xcodebuild -project TokenPlan.xcodeproj \
  -scheme TokenPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

当前 Windows 工作站没有 Swift、Xcode 和 Apple 签名环境，不能在本机编译或导出 IPA。第一次产出 IPA 前还需要：

1. macOS + 当前版 Xcode；
2. Apple Developer Team；
3. 真机或 TestFlight 分发所需的签名身份和 provisioning profile。

## 导出 IPA

在真机验证通过后，用 Xcode 选择 Generic iOS Device，执行 Product → Archive → Distribute App。自用可选择已注册设备分发；持续测试优先使用 TestFlight。

也可以在已经登录 Apple 开发者账户的 macOS 终端执行：

```bash
cd ios
DEVELOPMENT_TEAM=你的团队ID sh ./scripts/build-ipa.sh
```

默认导出注册设备可安装的 development IPA。设置 `EXPORT_METHOD=app-store-connect` 可改为 App Store Connect 分发归档。
