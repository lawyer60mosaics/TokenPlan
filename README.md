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

`ios/` contains the native SwiftUI client and XcodeGen project definition. It shares the cloud vault format with Windows: XChaCha20-Poly1305, a 24-byte nonce, URL-safe Base64 and the `tokenplan-vault-v1` authenticated-data value. The sync token and recovery key are stored in Keychain; decrypted profiles use iOS Complete File Protection.

Run the **Build iOS IPA** GitHub Actions workflow to compile on a macOS runner. With no Apple signing secrets, the artifact is `TokenPlan-unsigned.ipa`, intended for signing with a sideloading tool. Direct device installation, Ad Hoc distribution and TestFlight still require an Apple Developer certificate and provisioning profile. See [ios/README.md](ios/README.md).

## 致谢与许可 / Acknowledgments & licensing

软件内可通过「设置 → 致谢与许可」离线查看完整说明。返回设置不会丢弃未保存的配置。

Open Settings → Acknowledgments & licenses to read the full bundled notice offline. Returning to settings preserves unsaved drafts.

感谢 **DeveloperLz** 为本项目提供灵感。

Thanks to **DeveloperLz** for the inspiration behind this project.

此致谢仅说明灵感来源，不代表已获得 DeveloperLz 作品的额外授权或其对本项目的背书。第三方代码的版权与许可声明见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)，其中保留了 cc-switch 的 MIT 许可全文。

This acknowledgment credits the inspiration only; it does not claim additional permission to use DeveloperLz's work or endorsement of this project. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party provenance, copyright notices and the full cc-switch MIT license.
