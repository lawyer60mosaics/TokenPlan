// Seven cc-switch Token Plans at 3217f725 plus DeepSeek's official balance API.
// See THIRD_PARTY_NOTICES.md.
export const providers = [
  { id: 'volcengine', name: 'Volcengine', zh: '火山方舟', defaultName: 'Volcengine Coding Plan', credentials: 'aksk' },
  { id: 'kimi', name: 'Kimi For Coding', zh: 'Kimi For Coding', defaultName: 'Kimi For Coding', credentials: 'key' },
  { id: 'zhipu', name: 'Zhipu GLM', zh: '智谱 GLM', defaultName: 'Zhipu GLM', credentials: 'key', regions: true },
  { id: 'zhipu_team', name: 'Zhipu GLM Team', zh: '智谱 GLM 团队', defaultName: 'Zhipu GLM Team', credentials: 'team' },
  { id: 'minimax', name: 'MiniMax', zh: 'MiniMax', defaultName: 'MiniMax', credentials: 'key', regions: true },
  { id: 'zenmux', name: 'ZenMux', zh: 'ZenMux', defaultName: 'ZenMux', credentials: 'urlKey' },
  { id: 'opencode_go', name: 'OpenCode Go', zh: 'OpenCode Go', defaultName: 'OpenCode Go', credentials: 'key' },
  { id: 'deepseek', name: 'DeepSeek Balance', zh: 'DeepSeek 余额', defaultName: 'DeepSeek Balance', credentials: 'key', kind: 'balance' },
];
export const providerInfo = id => providers.find(provider => provider.id === id);
export function newProfile(provider = 'volcengine') {
  return { id: crypto.randomUUID(), name: providerInfo(provider)?.defaultName || provider, provider,
    type: 'auto', access_key: '', secret_key: '', api_key: '', region: 'cn', base_url: '',
    organization_id: '', project_id: '', enabled: true };
}
export function migrateProfile(profile, index = 0) {
  return { ...newProfile(), ...profile, id: profile.id || `legacy-${index + 1}`, provider: profile.provider || 'volcengine' };
}
export function credentialIssue(profile) {
  if (!profile || !providerInfo(profile.provider)) return 'unsupported';
  if (profile.provider === 'volcengine') {
    if (!profile.access_key?.trim() || !profile.secret_key?.trim()) return 'missingAksk';
  } else if (!profile.api_key?.trim()) return 'missingKey';
  if (profile.provider === 'zhipu_team' && (!profile.organization_id?.trim() || !profile.project_id?.trim())) return 'missingTeam';
  if (profile.provider === 'zenmux') {
    try {
      const url = new URL(profile.base_url);
      if (url.protocol !== 'https:' || !/(^|\.)zenmux\.(ai|com)$/.test(url.hostname) || url.username || url.password || url.hash || url.port) return 'invalidZenmux';
    } catch { return 'invalidZenmux'; }
  }
  return '';
}
export function normalizeTiers(tiers = []) {
  const order = ['five_hour', 'weekly_limit', 'monthly'];
  return tiers.filter(tier => typeof tier.utilization === 'number' && Number.isFinite(tier.utilization))
    .map(tier => ({ ...tier, fill: Math.min(100, Math.max(0, tier.utilization)) }))
    .sort((a, b) => (order.indexOf(a.name) < 0 ? 99 : order.indexOf(a.name)) - (order.indexOf(b.name) < 0 ? 99 : order.indexOf(b.name)));
}

export function normalizeBalances(balances) {
  const currencies = new Set();
  const amount = value => typeof value === 'string' && /^-?\d+(\.\d+)?$/.test(value) && Number.isFinite(Number(value));
  if (!Array.isArray(balances) || !balances.length || balances.some(balance => {
    if (!balance || !['CNY', 'USD'].includes(balance.currency) || currencies.has(balance.currency)) return true;
    currencies.add(balance.currency);
    return !['totalBalance', 'grantedBalance', 'toppedUpBalance'].every(key => amount(balance[key]));
  })) throw new Error('DeepSeek: unrecognized balance response / 无法识别余额数据');
  return balances.map(balance => ({ ...balance }));
}
