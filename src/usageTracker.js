import { credentialIssue, normalizeTiers, normalizeBalances } from './providers.js';

// Per-profile caching: slow requests must never paint another profile's data.
export function createUsageTracker(query, onChange, isCurrent) {
  const records = new Map();
  const pending = new Map();
  function publish(id, record) { records.set(id, record); onChange(Object.fromEntries(records)); }
  function refresh(profile) {
    const snapshot = JSON.parse(JSON.stringify(profile));
    const id = snapshot.id;
    const fingerprint = JSON.stringify(snapshot);
    if (pending.get(id)?.fingerprint === fingerprint) return pending.get(id).promise;
    const previous = records.get(id);
    const base = previous?.fingerprint === fingerprint ? previous : { tiers: [], balances: [], queriedAt: null };
    const issue = credentialIssue(snapshot);
    if (!snapshot.enabled || issue) {
      publish(id, { ...base, fingerprint, status: snapshot.enabled ? 'needsConfig' : 'paused', error: '', issue });
      return Promise.resolve();
    }
    const request = { fingerprint };
    publish(id, { ...base, fingerprint, status: 'loading', error: '', issue: '' });
    pending.set(id, request);
    request.promise = (async () => {
      try {
        const quota = await query(snapshot);
        if (pending.get(id) !== request || !isCurrent(snapshot)) return;
        if (!quota.success) throw new Error(quota.error || 'Query failed / 查询失败');
        let data;
        if (snapshot.provider === 'deepseek') {
          if (quota.kind !== 'balance' || typeof quota.isAvailable !== 'boolean') throw new Error('DeepSeek: unrecognized balance response / 无法识别余额数据');
          data = { kind: 'balance', tiers: [], balances: normalizeBalances(quota.balances), isAvailable: quota.isAvailable };
        } else {
          const tiers = normalizeTiers(quota.tiers);
          if (!tiers.length) throw new Error('No active quota windows / 未找到有效套餐周期');
          data = { kind: 'quota', tiers, balances: [] };
        }
        publish(id, { fingerprint, status: 'success', ...data, queriedAt: quota.queriedAt || Date.now(), plan: quota.credentialMessage || '', error: '', issue: '' });
      } catch (error) {
        if (pending.get(id) === request && isCurrent(snapshot)) {
          publish(id, { ...base, fingerprint, status: 'failed', error: String(error?.message || error), issue: '' });
        }
      } finally { if (pending.get(id) === request) pending.delete(id); }
    })();
    return request.promise;
  }
  function retain(ids) {
    for (const id of records.keys()) if (!ids.includes(id)) { records.delete(id); pending.delete(id); }
    onChange(Object.fromEntries(records));
  }
  return { refresh, retain };
}
