# Token Plan Monitor · Windows 11

Rust + Tauri 2 + Vue 3 desktop widget. Compact monochrome UI, Chinese/English, native dragging, tray menu, DPAPI-encrypted credentials and optional startup.

## Supported Token Plans

Aligned with [cc-switch](https://github.com/farion1231/cc-switch/tree/3217f72596f2d1c0f879f0a05f83803825d9809f), `src/config/codingPlanProviders.ts` and `src-tauri/src/services/coding_plan.rs`.

| Provider | Credentials | Quota windows |
| --- | --- | --- |
| Volcengine Agent / Coding Plan | Account AK + SK, not inference key | 5h / weekly / monthly; Agent first, Coding fallback |
| Kimi For Coding | API Key | 5h / weekly |
| Zhipu GLM (China / Z.ai global) | API Key | 5h / weekly where available |
| Zhipu GLM Team (China) | API Key + organization ID + project ID | 5h / weekly where available |
| MiniMax (China / global) | API Key | 5h; weekly only when activated |
| ZenMux | API Key + full HTTPS usage endpoint on zenmux.ai / zenmux.com | 5h / weekly, including USD amounts when returned |
| OpenCode Go | Workspace API Key with Go subscription | rolling 5h / weekly / monthly |

Only windows actually returned by the service are shown. A missing window is not a zero-usage window. Bars are visually clamped to 0–100%, while reported percentages remain intact. MiniMax remaining percentages and ZenMux fractional usage are converted to used percentages. OpenCode Go zero-usage placeholder reset times are hidden.

These seven integrations cover cc-switch's **Token Plan** tab. Generic API-balance scripts, arbitrary custom scripts, and OAuth-based official subscriptions (Claude/Codex etc.) are separate cc-switch features, not included here. DeepSeek's official balance API is supported separately as described below. A model preset without a quota-query implementation (for example MiMo) is not presented as a supported quota provider.

## DeepSeek 余额 / DeepSeek balance

除以上 7 类套餐外，现支持 **DeepSeek 官方账户余额**。在「设置 → 新增套餐 → DeepSeek 余额」中填写 DeepSeek 官方 API Key 并保存即可。凭据仍使用 Windows DPAPI 加密，支持自动刷新、暂停和多配置切换。

按照 [DeepSeek 官方余额接口](https://api-docs.deepseek.com/api/get-user-balance/)，使用 `GET https://api.deepseek.com/user/balance` 查询总余额、赠送余额和充值余额，按 CNY / USD 分别显示，不合并币种、不伪造已用百分比或重置时间。余额不足会提示，但不视为查询失败；网络或接口错误保留上次成功的余额和时间。该接口不提供套餐额度或累计 Token 消耗。

In addition to the seven Token Plans, select **DeepSeek Balance** in Settings → Add plan and enter an **official DeepSeek API key**. The widget displays total, granted and topped-up balances separately per currency, with the API availability flag. Decimal strings are preserved exactly. No quota percentage, reset time or currency conversion is inferred. API keys issued by other platforms for DeepSeek models must use those platforms' profiles instead.

The endpoint is fixed to DeepSeek's official host; redirects are disabled. No DeepSeek credentials are imported from other tools. This independently implemented integration follows DeepSeek's API documentation, not a cc-switch Token Plan implementation.

## Usage

Open Settings → Add plan → select provider and credentials → Save. Region is offered for Zhipu and MiniMax. Changing provider or region clears the draft credentials to prevent sending them to the wrong service. Use the top dropdown to switch plans. Disable a profile to pause querying. Delete requires a second click and is persisted only on Save; Cancel discards drafts.

All enabled plans refresh every 60 seconds with per-profile caches and request deduplication. A failed refresh keeps the last successful value/timestamp and labels it stale. Click the error status for details. Credentials are not stored in browser localStorage; only language and selected profile ID are stored there.

Existing `%APPDATA%/VolcengineTokenPlan/profiles.dat` profiles are read with defaults as Volcengine, preserving AK/SK. Saving creates an encrypted `profiles.dat.bak`, then replaces the encrypted file using a temporary file. No provider credentials are imported from cc-switch.

## 火山方舟配额预热 / Volcengine quota prewarm

配置云同步后，可在 Windows 或 iOS 的云同步设置中启用配额预热。云服务器会按 `Asia/Shanghai` 时区在工作日 08:00 和 13:00 各执行一次，并在服务重启或短时故障后提供 30 分钟补执行窗口；相同时间槽只执行一次。也可以使用“立即试运行”验证 Key 和模型。

预热使用 Coding Plan 专用地址 `https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions`，默认模型为 `ark-code-latest`。每次发送一个最小请求并最多生成 1 token，因此属于真实套餐调用。查询套餐使用的账号 AK/SK 不能用于预热；需要另填 Coding Plan API Key。该 Key 通过 HTTPS 上传，在服务器使用 XChaCha20-Poly1305 加密保存，查询配置时只返回“是否已配置”，不返回 Key 明文。停用自动预热不会删除已加密保存的 Key。

如需完全绕过自建服务器，可启用 `.github/workflows/volcengine-prewarm.yml`。该 GitHub Actions 工作流在工作日 08:00、13:00（Asia/Shanghai）从 GitHub 云端直接请求火山方舟。仓库必须配置 Actions Secret `VOLCENGINE_CODING_PLAN_API_KEY`；可选变量 `VOLCENGINE_CODING_PLAN_MODEL` 用于覆盖默认模型。使用该方案时，应关闭 TokenPlan 客户端中的服务器自动预热，避免重复调用。

### 多云 Serverless 部署（可选）

`serverless/aliyun-fc` 和 `serverless/tencent-scf` 分别集成了 Serverless Framework 的阿里云 FC、腾讯云 SCF 插件。两个服务都执行同一个最小火山方舟预热请求，默认只在 GitHub Actions 手动确认后部署，不会自动产生云函数资源。使用仓库工作流 `Deploy TokenPlan Serverless provider`，选择 `aliyun` 或 `tencent`，并将确认字段填写为 `DEPLOY`。

部署前需要配置对应的 GitHub Actions Secrets：阿里云使用 `ALIYUN_ACCESS_KEY_ID`、`ALIYUN_ACCESS_KEY_SECRET`、`ALIYUN_ACCOUNT_ID`；腾讯云使用 `TENCENT_SECRET_ID`、`TENCENT_SECRET_KEY`、`TENCENT_APP_ID`。两者共用 `VOLCENGINE_CODING_PLAN_API_KEY`。部署完成后，定时触发器建议在对应云控制台配置为北京时间工作日 08:00 和 13:00；插件只负责函数部署，避免不同插件版本对 Cron 格式的差异。

更通用的自动化代码在 `automation/`：`automation/tasks/` 放业务任务，`automation/local/` 是本地运行入口，GitHub 工作流和两个云函数共享同一个任务定义。以后新增备份、健康检查、通知等场景时，只需新增任务模块和对应平台适配层。

## Development and verification

```powershell
npm install
npm run dev -- --host 127.0.0.1 --port 1420
npm run build
node --test src/providers.test.js
cargo test --manifest-path src-tauri/Cargo.toml --lib
npx tauri build --debug
```

`tests/preview.html` is an isolated Vite-only UI fixture page: fictional keys, no provider network traffic, in-memory saves. It is not included in the production build. Native drag regression: with exactly one built app running, `./scripts/Test-WindowDrag.ps1 -Region text` (also `progress`, `blank`, or `settings -ExpectStationary`). This moves the mouse and window; do not interact during the test.

Backend parsing and local HTTP contract tests do not prove a real account can access a service. Newly added providers require your own active subscription and credentials for live verification. Third-party quota APIs can change; OpenCode Go's usage route is undocumented, so unrecognized responses are surfaced as errors.

## iOS

`ios/` contains the native SwiftUI client with the same eight provider usage queries as Windows, home-screen widgets in small/medium/large sizes, lock-screen widgets, and a Live Activity with Dynamic Island layouts. Foreground usage refresh runs every 60 seconds; background refresh uses iOS `BGAppRefresh` scheduling. The cloud server address is built into both clients; users enter only an account and password. Both clients derive separate authentication and vault keys, then use XChaCha20-Poly1305 with a 24-byte nonce, URL-safe Base64 and the `tokenplan-vault-v2` authenticated-data value. The account and password are stored with Windows DPAPI or iOS Keychain; decrypted iOS profiles use Complete File Protection.

Run the **Build iOS IPA** GitHub Actions workflow to compile on a macOS runner. With no Apple signing secrets, the artifact is `TokenPlan-unsigned.ipa`, intended for signing with a sideloading tool. Direct device installation, Ad Hoc distribution and TestFlight still require an Apple Developer certificate and provisioning profile. See [ios/README.md](ios/README.md).

## 致谢与许可 / Acknowledgments & licensing

软件内可通过「设置 → 致谢与许可」离线查看完整说明。返回设置不会丢弃未保存的配置。

Open Settings → Acknowledgments & licenses to read the full bundled notice offline. Returning to settings preserves unsaved drafts.

感谢 **DeveloperLz** 为本项目提供灵感。

Thanks to **DeveloperLz** for the inspiration behind this project.

此致谢仅说明灵感来源，不代表已获得 DeveloperLz 作品的额外授权或其对本项目的背书。第三方代码的版权与许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，其中保留了 cc-switch 的 MIT 许可全文。

This acknowledgment credits the inspiration only; it does not claim additional permission to use DeveloperLz's work or endorsement of this project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party provenance, copyright notices and the full cc-switch MIT license.
