import { run as runVolcenginePrewarm } from '../tasks/volcengine-prewarm.mjs';

const tasks = new Map([["volcengine-prewarm", runVolcenginePrewarm]]);

export function listTasks() {
  return [...tasks.keys()];
}

export async function runTask(taskId, options = {}) {
  const task = tasks.get(taskId);
  if (!task) throw new Error(`Unknown task: ${taskId}. Available: ${listTasks().join(', ')}`);
  const startedAt = new Date().toISOString();
  try {
    const result = await task(options);
    return { ...result, startedAt, finishedAt: new Date().toISOString() };
  } catch (error) {
    error.taskId = taskId;
    throw error;
  }
}
