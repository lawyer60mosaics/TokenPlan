import { createApp } from 'vue';
import { mockIPC, mockWindows } from '@tauri-apps/api/mocks';
import App from '../src/App.vue';
import { newProfile, providers } from '../src/providers.js';

let profiles = providers.map(p => ({ ...newProfile(p.id), id: p.id, api_key: 'fictional-api', access_key: 'fictional-ak', secret_key: 'fictional-sk', organization_id: 'fictional-org', project_id: 'fictional-project', base_url: 'https://api.zenmux.com/usage' }));
let startup = false;
let syncState = null;
let prewarmState = { enabled: false, model: 'ark-code-latest', schedule: '工作日 08:00、13:00', timezone: 'Asia/Shanghai', hasApiKey: false, lastRun: null };
// URL-only fixture scenarios; never bundled with the application.
const balanceScenario = new URLSearchParams(location.search).get('balance');
let balanceQueries = 0;
mockWindows('main');
mockIPC((command, args) => {
  if (command === 'load_profiles') return structuredClone(profiles);
  if (command === 'save_profiles') { profiles = structuredClone(args.profiles); return; }
  if (command === 'get_autostart') return startup;
  if (command === 'set_autostart') { startup = args.enabled; return; }
  if (command === 'get_sync_state') return syncState;
  if (command === 'configure_sync') { syncState = { enabled: true, username: args.username, revision: 1 }; return syncState; }
  if (command === 'disable_sync') { syncState = null; return; }
  if (command === 'push_sync') return syncState || { enabled: true, username: 'fixture', revision: 1 };
  if (command === 'pull_sync') return { profiles: structuredClone(profiles), state: syncState || { enabled: true, username: 'fixture', revision: 1 } };
  if (command === 'change_sync_password') { syncState = { ...(syncState || { enabled: true, username: 'fixture' }), revision: 2 }; return syncState; }
  if (command === 'get_prewarm') return prewarmState;
  if (command === 'save_prewarm') { prewarmState = { ...prewarmState, enabled: args.enabled, model: args.model, hasApiKey: prewarmState.hasApiKey || !!args.apiKey }; return prewarmState; }
  if (command === 'run_prewarm') { const result = { id: 1, triggeredAt: Math.floor(Date.now() / 1000), source: 'manual', success: true, httpStatus: 200, error: null }; prewarmState = { ...prewarmState, lastRun: result }; return result; }
  if (command === 'query_profile') {
    if (args.profile.provider === 'deepseek') {
      balanceQueries++;
      if (balanceScenario === 'stale' && balanceQueries > 1) throw Error('Fixture: network unavailable');
      const depleted = balanceScenario === 'depleted';
      const balances = [{ currency: 'CNY', totalBalance: depleted ? '0.00' : '110.0000', grantedBalance: depleted ? '0.00' : '10.0000', toppedUpBalance: depleted ? '0.00' : '100.00' }];
      if (balanceScenario === 'multi') balances.push({ currency: 'USD', totalBalance: '0.0010', grantedBalance: '0.0000', toppedUpBalance: '0.0010' });
      return { kind: 'balance', success: true, isAvailable: !depleted, queriedAt: Date.now(), balances };
    }
    const names = ['five_hour', 'weekly_limit', 'monthly'];
    const count = ['volcengine', 'opencode_go'].includes(args.profile.provider) ? 3 : 2;
    return { success: true, queriedAt: Date.now(), tiers: names.slice(0, count).map((name, index) => ({ name, utilization: 12.5 + index * 23, resetsAt: index === 0 ? null : '2026-09-01T08:00:00Z', usedValueUsd: args.profile.provider === 'zenmux' ? 2.5 : null, maxValueUsd: args.profile.provider === 'zenmux' ? 10 : null })) };
  }
  if (command === 'plugin:window|start_dragging') return;
  if (command === 'exit_app') { document.getElementById('app').textContent = 'Test exit called'; return; }
  throw Error('Unexpected test command: ' + command);
}, { shouldMockEvents: true });
createApp(App).mount('#app');
