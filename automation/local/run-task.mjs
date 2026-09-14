#!/usr/bin/env node
import { listTasks, runTask } from '../shared/task-runner.mjs';

const args = process.argv.slice(2);
const taskIndex = args.indexOf('--task');
const taskId = taskIndex >= 0 ? args[taskIndex + 1] : undefined;

if (!taskId || taskId === '--help') {
  console.log(`Usage: node automation/local/run-task.mjs --task <id>\nAvailable tasks: ${listTasks().join(', ')}`);
  process.exit(taskId ? 0 : 2);
}

try {
  console.log(JSON.stringify(await runTask(taskId), null, 2));
} catch (error) {
  console.error(JSON.stringify({ task: taskId, success: false, error: error.message }));
  process.exit(1);
}
