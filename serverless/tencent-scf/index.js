'use strict';

const ENDPOINT = 'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions';

async function sendNotifications(content, success) {
  const enabled = success ? process.env.NOTIFY_ON_SUCCESS !== 'false' : process.env.NOTIFY_ON_FAILURE !== 'false';
  if (!enabled) return;
  const targets = [['dingtalk', process.env.DINGTALK_WEBHOOK], ['wecom', process.env.WECOM_WEBHOOK]].filter(([, url]) => url);
  await Promise.allSettled(targets.map(async ([kind, url]) => {
    const response = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ msgtype: 'text', text: { content } }) });
    if (!response.ok) throw new Error(`${kind} notification HTTP ${response.status}`);
    const result = await response.json();
    if (result.errcode !== 0) throw new Error(`${kind} notification error ${result.errcode}`);
  }));
}

exports.prewarm = async function prewarm() {
  try {
    const apiKey = process.env.VOLCENGINE_CODING_PLAN_API_KEY;
    if (!apiKey) throw new Error('VOLCENGINE_CODING_PLAN_API_KEY is not configured');

    const response = await fetch(ENDPOINT, {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ model: process.env.VOLCENGINE_CODING_PLAN_MODEL || 'ark-code-latest', messages: [{ role: 'user', content: 'Reply with OK.' }], max_tokens: 1, stream: false }),
    });

    const text = await response.text();
    if (!response.ok) throw new Error(`Volcengine HTTP ${response.status}: ${text.slice(0, 300)}`);
    await sendNotifications('TokenPlan：腾讯云 SCF 预热成功', true);
    console.log(JSON.stringify({ provider: 'tencent-scf', status: response.status }));
    return { success: true, status: response.status };
  } catch (error) {
    await sendNotifications(`TokenPlan：腾讯云 SCF 预热失败\n${String(error).slice(0, 300)}`, false);
    throw error;
  }
};
