# 任务配置约定

`tasks.example.json` 是跨平台配置样例，不包含真实密钥。配置分成三层：

- `tasks`：任务 ID、任务类型、参数和所需密钥环境变量。
- `schedule`：业务时区中的 Cron 表达式；平台部署时转换为对应云厂商的 Cron 格式。
- `enabled`：是否启用该任务。默认只启用 TokenPlan 的预热样例。

建议为每个任务定义幂等键，例如 `taskId + date + scheduleSlot`，这样同一任务在 GitHub、阿里云和腾讯云发生重复触发时不会产生重复副作用。
