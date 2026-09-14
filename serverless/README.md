# TokenPlan 多云 Serverless 集成

本目录提供两个可选的 Serverless Framework 云端部署服务：

- `aliyun-fc/`：通过 `serverless-aliyun-function-compute` 部署到阿里云函数计算 FC。
- `tencent-scf/`：通过 `serverless-tencent-scf` 部署到腾讯云云函数 SCF。

两个函数都只做一件事：向火山方舟 Coding Plan 发送最小请求，作为 5 小时额度预热。密钥只从云函数环境变量读取，不写入仓库。通用任务协议、本地执行器和新增场景位于根目录 `automation/`，云函数目录是云平台所需的薄适配层。

两个函数也支持在任务结束后发送钉钉或企业微信机器人通知。部署前可以按需设置：

- `DINGTALK_WEBHOOK`：钉钉自定义机器人完整 Webhook。
- `WECOM_WEBHOOK`：企业微信群机器人完整 Webhook。
- `NOTIFY_ON_SUCCESS`：成功时通知，默认为 `true`。
- `NOTIFY_ON_FAILURE`：失败时通知，默认为 `true`。

Webhook 和云平台密钥均属于敏感信息，只能放在本机环境变量、云函数环境变量或 GitHub Secrets 中，不能提交到仓库。

## 本地部署

先设置 `VOLCENGINE_CODING_PLAN_API_KEY`，然后在对应目录执行：

```bash
npm install
npx serverless deploy
```

阿里云插件要求本机存在 credentials 文件；腾讯云插件使用腾讯云 CLI 的凭据或 `serverless.yml` 中指定的 credentials 文件。详细变量名见根目录的 GitHub Actions 工作流。

## 定时触发

两个插件的版本和云端触发器格式不同，服务文件只负责部署函数，定时触发建议在对应云控制台创建，避免插件升级后改变 Cron 解析方式。目标时间为北京时间工作日 08:00、13:00。函数默认时区通过 `TZ=Asia/Shanghai` 设置。

如果需要完全不依赖云函数，继续使用根目录 `.github/workflows/volcengine-prewarm.yml` 即可。
