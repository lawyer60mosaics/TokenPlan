# 云函数入口契约

阿里云 FC 和腾讯云 SCF 的入口都必须遵循以下约定：

```js
exports.prewarm = async function prewarm(event, context) {
  // 读取云函数环境变量，执行一个幂等任务
  return { success: true };
};
```

云端入口不保存 TokenPlan 本地 profile，也不接收客户端提交的明文密钥。运行凭据只能通过云平台环境变量配置。新任务应在 `automation/tasks/` 先实现本地版本，再为需要的云平台增加薄入口。
