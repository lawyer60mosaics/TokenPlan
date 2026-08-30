# TokenPlan iOS 重签名要求

TokenPlan 主程序与小组件扩展通过 App Group 共享不含密钥的套餐用量快照。若重签名时丢失 App Group，主程序仍可使用，但桌面和锁屏小组件无法读取套餐。

## 必需配置

- 主程序 Bundle ID：`com.xuwenxu.tokenplan`
- 小组件 Bundle ID：`com.xuwenxu.tokenplan.widgets`
- App Group：`group.com.xuwenxu.tokenplan`
- 两个 App ID 必须属于同一 Apple Developer Team。
- 两个 Provisioning Profile 都必须包含上述 App Group。
- 重签名工具必须单独签名 `TokenPlanWidgets.appex`，再签名主程序。
- 同时保留 Widget Extension、Live Activities 和 Background Modes 权限。

对应权限源文件：

- `TokenPlan/TokenPlan.entitlements`
- `TokenPlanWidgets/TokenPlanWidgets.entitlements`

## 安装后检查

1. 打开 TokenPlan，进入云同步页面的“小组件数据共享”。
2. 状态应显示“正常”和“已共享 N 个套餐”。
3. 点击“重新写入小组件数据”。
4. 若页面显示“签名缺少 App Group 权限”，需要重新生成包含 App Group 的 Provisioning Profile，代码无法绕过 iOS 沙盒限制。
