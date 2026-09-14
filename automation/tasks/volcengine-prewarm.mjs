import { requestJson } from '../shared/http-task.mjs';

export const id = 'volcengine-prewarm';

export async function run({ env = process.env, log = console }) {
  const apiKey = env.VOLCENGINE_CODING_PLAN_API_KEY;
  if (!apiKey) throw new Error('VOLCENGINE_CODING_PLAN_API_KEY is not configured');
  const model = env.VOLCENGINE_CODING_PLAN_MODEL || 'ark-code-latest';
  const result = await requestJson({
    endpoint: 'https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions',
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
    body: { model, messages: [{ role: 'user', content: 'Reply with OK.' }], max_tokens: 1, stream: false },
    timeoutMs: 60000,
    retries: 2,
  });
  log.log(JSON.stringify({ task: id, model, status: result.status }));
  return { task: id, success: true, status: result.status };
}
