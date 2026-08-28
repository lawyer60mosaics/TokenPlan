import test from 'node:test';
import assert from 'node:assert/strict';
import { providers, newProfile, migrateProfile, credentialIssue, normalizeTiers, normalizeBalances } from './providers.js';
import { createUsageTracker } from './usageTracker.js';

test('seven upstream plans plus DeepSeek balance; migration preserves the original AK/SK', () => {
  assert.equal(providers.length, 8);
  assert.equal(providers.filter(p => p.kind === 'balance').length, 1);
  assert.equal(providers.find(p => p.id === 'deepseek').kind, 'balance');
  const p = migrateProfile({ name: 'Old', access_key: 'fake-ak', secret_key: 'fake-sk', type: 'auto' });
  assert.equal(p.provider, 'volcengine');
  assert.equal(p.id, 'legacy-1');
  assert.equal(p.secret_key, 'fake-sk');
  assert.equal(credentialIssue(p), '');
});
test('credentials differ for each provider, team and ZenMux require additional fields', () => {
  for (const provider of providers) {
    const p = { ...newProfile(provider.id), access_key: 'fake-ak', secret_key: 'fake-sk', api_key: 'fake-api', organization_id: 'fake-org', project_id: 'fake-project', base_url: 'https://api.zenmux.com/usage' };
    assert.equal(credentialIssue(p), '', provider.id);
  }
  assert.equal(credentialIssue({ ...newProfile('zhipu_team'), api_key: 'fake' }), 'missingTeam');
  assert.equal(credentialIssue({ ...newProfile('zenmux'), api_key: 'fake', base_url: 'https://evil.test/zenmux' }), 'invalidZenmux');
});
test('display real windows only, sorted by window ID; clamp bar but not reported percent', () => {
  const tiers = normalizeTiers([{ name: 'monthly', utilization: 140 }, { name: 'five_hour', utilization: 0 }, { name: 'weekly_limit', utilization: null }]);
  assert.deepEqual(tiers.map(t => t.name), ['five_hour', 'monthly']);
  assert.equal(tiers[1].utilization, 140);
  assert.equal(tiers[1].fill, 100);
});
test('concurrent profile requests stay isolated and identical refreshes are deduplicated', async () => {
  const pending = new Map();
  let state;
  let calls = 0;
  const tracker = createUsageTracker(p => { calls++; return new Promise(resolve => pending.set(p.id, resolve)); }, s => { state = s; }, () => true);
  const a = { ...newProfile('kimi'), api_key: 'fake-a' };
  const b = { ...newProfile('minimax'), api_key: 'fake-b' };
  const first = tracker.refresh(a);
  assert.equal(tracker.refresh(a), first);
  const second = tracker.refresh(b);
  pending.get(b.id)({ success: true, tiers: [{ name: 'five_hour', utilization: 22 }] });
  await second;
  pending.get(a.id)({ success: true, tiers: [{ name: 'weekly_limit', utilization: 55 }] });
  await first;
  assert.equal(calls, 2);
  assert.equal(state[a.id].tiers[0].utilization, 55);
  assert.equal(state[b.id].tiers[0].utilization, 22);
});
test('a stale response after editing or removing a profile is discarded', async () => {
  let finish;
  let current = true;
  let state;
  const tracker = createUsageTracker(() => new Promise(resolve => { finish = resolve; }), s => { state = s; }, () => current);
  const p = { ...newProfile('kimi'), api_key: 'fake' };
  const request = tracker.refresh(p);
  current = false;
  tracker.retain([]);
  finish({ success: true, tiers: [{ name: 'five_hour', utilization: 55 }] });
  await request;
  assert.equal(state[p.id], undefined);
});
test('failed refresh keeps last success and timestamp without pretending zero usage', async () => {
  let state;
  let fails = false;
  const tracker = createUsageTracker(async () => { if (fails) throw Error('offline'); return { success: true, queriedAt: 1234, tiers: [{ name: 'five_hour', utilization: 35 }] }; }, s => { state = s; }, () => true);
  const p = { ...newProfile('kimi'), api_key: 'fake' };
  await tracker.refresh(p);
  fails = true;
  await tracker.refresh(p);
  assert.equal(state[p.id].status, 'failed');
  assert.equal(state[p.id].tiers[0].utilization, 35);
  assert.equal(state[p.id].queriedAt, 1234);
});
test('paused and unconfigured profiles do not make network requests', async () => {
  let calls = 0;
  const tracker = createUsageTracker(async () => { calls++; }, () => {}, () => true);
  await tracker.refresh(newProfile('kimi'));
  await tracker.refresh({ ...newProfile('kimi'), enabled: false, api_key: 'fake' });
  await tracker.refresh(newProfile('deepseek'));
  await tracker.refresh({ ...newProfile('deepseek'), enabled: false, api_key: 'fake' });
  assert.equal(calls, 0);
});

const balanceFixture = (total = '110.0000', available = true) => ({
  kind: 'balance', success: true, isAvailable: available, queriedAt: 1234,
  balances: [{ currency: 'CNY', totalBalance: total, grantedBalance: '10.0000', toppedUpBalance: '100.00' }],
});

test('balance preserves exact amounts and separate currencies, never inventing utilization', () => {
  const input = balanceFixture().balances;
  input.push({ ...input[0], currency: 'USD', totalBalance: '0.0001' });
  const result = normalizeBalances(input);
  assert.equal(result[0].totalBalance, '110.0000');
  assert.equal(result[1].totalBalance, '0.0001');
  assert.equal(result[0].utilization, undefined);
  assert.notEqual(input[0], result[0]);
});

test('malformed balances are errors, not false zeroes or partial currency results', () => {
  const valid = balanceFixture().balances[0];
  for (const invalid of [undefined, [], [null], [valid, valid], [{ ...valid, currency: 'EUR' }]]) {
    assert.throws(() => normalizeBalances(invalid));
  }
  for (const field of ['totalBalance', 'grantedBalance', 'toppedUpBalance']) {
    for (const value of [null, undefined, '', ' ', 'NaN', 'Infinity', '1e4', 110]) {
      assert.throws(() => normalizeBalances([{ ...valid, [field]: value }]));
    }
  }
});

test('depleted DeepSeek balance is a successful query without quota bars', async () => {
  let state;
  const tracker = createUsageTracker(async () => balanceFixture('0.00', false), s => { state = s; }, () => true);
  const p = { ...newProfile('deepseek'), api_key: 'fake' };
  await tracker.refresh(p);
  assert.equal(state[p.id].status, 'success');
  assert.equal(state[p.id].isAvailable, false);
  assert.deepEqual(state[p.id].tiers, []);
  assert.equal(state[p.id].balances[0].totalBalance, '0.00');
});

test('balance refresh failures preserve the previous balance and success timestamp', async () => {
  let state, fail = false;
  const tracker = createUsageTracker(async () => { if (fail) throw Error('offline'); return balanceFixture(); }, s => { state = s; }, () => true);
  const p = { ...newProfile('deepseek'), api_key: 'fake' };
  await tracker.refresh(p);
  fail = true;
  await tracker.refresh(p);
  assert.equal(state[p.id].status, 'failed');
  assert.equal(state[p.id].kind, 'balance');
  assert.equal(state[p.id].balances[0].totalBalance, '110.0000');
  assert.equal(state[p.id].queriedAt, 1234);
});

test('edited DeepSeek profile rejects old responses and does not reuse old balances', async () => {
  let state;
  const pending = [];
  const tracker = createUsageTracker(() => new Promise(resolve => pending.push(resolve)), s => { state = s; }, () => true);
  const p = { ...newProfile('deepseek'), api_key: 'fake-old' };
  const old = tracker.refresh(p);
  const newer = tracker.refresh({ ...p, api_key: 'fake-new' });
  pending[1](balanceFixture('50.00'));
  await newer;
  pending[0](balanceFixture('110.00'));
  await old;
  assert.equal(state[p.id].balances[0].totalBalance, '50.00');
});

test('balance and quota profiles refresh independently', async () => {
  let state;
  const tracker = createUsageTracker(async p => p.provider === 'deepseek' ? balanceFixture() : { success: true, tiers: [{ name: 'five_hour', utilization: 35 }] }, s => { state = s; }, () => true);
  const balance = { ...newProfile('deepseek'), api_key: 'fake-balance' };
  const quota = { ...newProfile('kimi'), api_key: 'fake-quota' };
  await Promise.all([tracker.refresh(balance), tracker.refresh(quota)]);
  assert.equal(state[balance.id].kind, 'balance');
  assert.deepEqual(state[balance.id].tiers, []);
  assert.equal(state[quota.id].kind, 'quota');
  assert.deepEqual(state[quota.id].balances, []);
});

test('missing availability or wrong response kind must fail a balance query', async () => {
  for (const result of [{ ...balanceFixture(), isAvailable: undefined }, { success: true, tiers: [{ name: 'five_hour', utilization: 10 }] }]) {
    let state;
    const tracker = createUsageTracker(async () => result, s => { state = s; }, () => true);
    const p = { ...newProfile('deepseek'), api_key: 'fake' };
    await tracker.refresh(p);
    assert.equal(state[p.id].status, 'failed');
    assert.deepEqual(state[p.id].balances, []);
    assert.deepEqual(state[p.id].tiers, []);
  }
});
