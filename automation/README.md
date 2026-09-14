# TokenPlan 通用自动化任务层

这里是 TokenPlan 之外可复用的定时任务代码。任务与执行平台分离：同一个任务可以由本地 Windows、GitHub Actions、阿里云 FC 或腾讯云 SCF 执行。

## 目录

```text
automation/
  config/                 任务和调度配置示例
  shared/                 不依赖云厂商的任务运行器
  tasks/                  具体业务任务（当前包含火山方舟预热）
  local/                  Windows/macOS/Linux 本地一次性执行入口
  cloud/                  云函数入口契约和扩展说明
```

任务函数只接收环境变量和上下文，不读取 TokenPlan 的本地数据库；敏感信息通过本地 `.env`、GitHub Secrets 或云函数环境变量注入。

## 执行方式

```powershell
$env:VOLCENGINE_CODING_PLAN_API_KEY = '...'
node automation/local/run-task.mjs --task volcengine-prewarm
```

GitHub、阿里云和腾讯云的部署目录仍在 `serverless/`，它们使用同一套任务协议。新增任务时，先在 `automation/tasks/` 增加任务，再按需增加平台入口，不需要修改 Windows 主程序。

## 多场景方案

1. **单平台定时**：生产只启用一个平台，避免同一个任务重复执行。
2. **主备切换**：GitHub 作为主调度，云函数只在 GitHub 失败时人工触发。
3. **多平台并行**：同一任务分别部署到阿里云和腾讯云，适合两个独立账号或不同地域；需要任务幂等键防止重复副作用。
4. **任务编排**：先执行同步，再执行通知或备份；每一步产生结构化结果，失败时停止后续步骤。
5. **本地调试**：本地入口执行完全相同的任务代码，云端只负责触发和注入密钥。

当前 TokenPlan 预热属于“单平台定时”任务，GitHub 工作流继续作为零云资源成本的默认方案。
