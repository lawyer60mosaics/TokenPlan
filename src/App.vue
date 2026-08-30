<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { listen } from '@tauri-apps/api/event';
import { providers, providerInfo, newProfile, migrateProfile, credentialIssue } from './providers.js';
import { createUsageTracker } from './usageTracker.js';
import ThirdPartyNotices from './ThirdPartyNotices.vue';
import './style.css';

const lang = ref(localStorage.getItem('token-plan-language') === 'en' ? 'en' : 'zh');
const copy = {
  zh: { five_hour: '5 小时会话', weekly_limit: '近 1 周', monthly: '近 1 月', waiting: '等待刷新',
    needsConfig: '请在设置中配置套餐', loading: '查询中…', success: '● 查询成功', failed: '查询失败（点击查看）',
    paused: '此套餐已暂停', noProfiles: '尚未添加套餐', settings: '[设置]', refresh: '[刷新]', exit: '[退出]',
    title: '套餐设置', notices: '致谢与许可', back: '返回设置', name: '名称', provider: '套餐供应商', region: '站点', cn: '国内站', global: '国际站',
    add: '+ 新增套餐', remove: '删除', confirmRemove: '确认删除？', cancel: '取消', save: '保存', saving: '保存中…',
    enabled: '启用自动查询', autostart: '开机自动启动', org: '组织 ID', project: '项目 ID', url: 'ZenMux 用量查询地址',
    key: 'API Key', ak: 'AccessKey ID', sk: 'Secret AccessKey', noReset: '暂无重置时间', noData: '尚无用量数据',
    close: '关闭', config: '查询配置', updated: '更新于', stale: '显示上次成功数据', saved: '凭据使用 Windows DPAPI 加密保存',
    missingAksk: '请填写账号 AK/SK（不是推理 API Key）', missingKey: '请填写 API Key',
    missingTeam: '智谱团队版还需要组织 ID 和项目 ID', invalidZenmux: '请填写 zenmux.ai / zenmux.com 的完整 HTTPS 用量接口地址',
    unsupported: '不支持的套餐类型', nameRequired: '请填写配置名称', loadFailed: '配置读取失败，已禁止覆盖原文件',
    saveFailed: '保存失败：', autostartFailed: '套餐已保存，但开机自启动设置失败：', amount: '已用 / 上限',
    cloudSync: '云同步', syncAccount: '账号', syncPassword: '密码',
    configureSync: '保存账号密码', uploadCloud: '上传', downloadCloud: '下载', disableSync: '停用',
    syncReady: '已配置，云端版本', syncOff: '未配置', credentialsRequired: '请输入账号和至少 16 位密码',
    credentialsHint: '其他设备使用相同账号和密码即可同步。认证与加密密钥由应用自动生成。',
    syncConfigured: '云同步配置成功', uploadSuccess: '已上传加密配置', downloadSuccess: '已下载并替换本地配置',
    localSavedSyncFailed: '本地已保存，云同步失败：', syncFailed: '云同步失败：',
    hint: '每 60 秒自动查询所有启用的配置。', dragFailed: '窗口拖动失败：',
    totalBalance: '总余额', grantedBalance: '赠送余额', toppedUpBalance: '充值余额', balanceAccount: '账户余额',
    available: '● 余额可用', insufficient: '● 余额不足，暂不可调用 API',
    deepseekHint: '仅支持 DeepSeek 官方 API Key；查询账户余额，不是套餐进度。通过火山等平台调用 DeepSeek，请使用对应平台的查询配置。',
    dashboard: '套餐总览', monitoring: '正在监控', healthy: '正常', alerts: '异常', lastRefresh: '最近刷新',
    myPlans: '我的套餐', plansUnit: '个', refreshAll: '全部刷新', used: '已使用', editPlan: '编辑套餐',
    viewConfig: '查看配置', notUpdated: '尚未获取数据', staleData: '本次刷新失败，正在显示上次数据',
    addFirst: '添加第一个 AI 套餐', normal: '正常', abnormal: '异常', pending: '待刷新', appSubtitle: 'AI 套餐用量仪表盘' },
  en: { five_hour: '5h session', weekly_limit: 'Last 7 days', monthly: 'Last month', waiting: 'Waiting',
    needsConfig: 'Configure this plan in Settings', loading: 'Refreshing…', success: '● Query successful', failed: 'Query failed (click for details)',
    paused: 'Plan paused', noProfiles: 'No plans configured', settings: '[Settings]', refresh: '[Refresh]', exit: '[Exit]',
    title: 'Token Plan settings', notices: 'Acknowledgments & licenses', back: 'Back to settings', name: 'Name', provider: 'Plan provider', region: 'Region', cn: 'China', global: 'Global',
    add: '+ Add plan', remove: 'Delete', confirmRemove: 'Confirm delete?', cancel: 'Cancel', save: 'Save', saving: 'Saving…',
    enabled: 'Enable automatic queries', autostart: 'Launch at startup', org: 'Organization ID', project: 'Project ID', url: 'ZenMux usage endpoint URL',
    key: 'API Key', ak: 'AccessKey ID', sk: 'Secret AccessKey', noReset: 'No reset scheduled', noData: 'No usage data yet',
    close: 'Close', config: 'Query profile', updated: 'Updated', stale: 'Showing last successful data', saved: 'Credentials encrypted with Windows DPAPI',
    missingAksk: 'Enter account AK/SK, not an inference API key', missingKey: 'Enter an API key',
    missingTeam: 'Zhipu Team also needs organization and project IDs', invalidZenmux: 'Enter a full HTTPS usage URL on zenmux.ai / zenmux.com',
    unsupported: 'Unsupported provider', nameRequired: 'Enter a profile name', loadFailed: 'Cannot read profiles; original file protected from overwrite',
    saveFailed: 'Save failed: ', autostartFailed: 'Plans saved, but startup setting failed: ', amount: 'Used / Limit',
    cloudSync: 'Cloud sync', syncAccount: 'Account', syncPassword: 'Password',
    configureSync: 'Save account and password', uploadCloud: 'Upload', downloadCloud: 'Download', disableSync: 'Disable',
    syncReady: 'Configured, cloud revision', syncOff: 'Not configured', credentialsRequired: 'Enter an account and a password of at least 16 characters',
    credentialsHint: 'Use the same account and password on another device. The app derives separate authentication and encryption keys automatically.',
    syncConfigured: 'Cloud sync configured', uploadSuccess: 'Encrypted profiles uploaded', downloadSuccess: 'Cloud profiles downloaded and applied locally',
    localSavedSyncFailed: 'Saved locally, but cloud sync failed: ', syncFailed: 'Cloud sync failed: ',
    hint: 'Every enabled profile refreshes automatically every 60 seconds.', dragFailed: 'Window drag failed: ',
    totalBalance: 'Total balance', grantedBalance: 'Granted balance', toppedUpBalance: 'Topped-up balance', balanceAccount: 'Account balance',
    available: '● Balance available', insufficient: '● Insufficient balance for API calls',
    deepseekHint: 'Requires an official DeepSeek API key. Queries account balance, not plan usage. For DeepSeek via another platform, use that platform’s profile.',
    dashboard: 'Plan overview', monitoring: 'being monitored', healthy: 'Healthy', alerts: 'Alerts', lastRefresh: 'Last refresh',
    myPlans: 'My plans', plansUnit: 'plans', refreshAll: 'Refresh all', used: 'used', editPlan: 'Edit plan',
    viewConfig: 'View settings', notUpdated: 'No usage fetched yet', staleData: 'Refresh failed; showing previous data',
    addFirst: 'Add your first AI plan', normal: 'Healthy', abnormal: 'Alert', pending: 'Pending', appSubtitle: 'AI plan usage dashboard' },
};
const tr = key => copy[lang.value][key] || key;
const profiles = ref([]);
const selected = ref(localStorage.getItem('token-plan-selected') || '');
const records = ref({});
const showSettings = ref(false), dragError = ref(''), loadError = ref('');
const showNotices = ref(false), noticesButton = ref(null), noticesScroll = ref(null), noticesBack = ref(null);
const drafts = ref([]), draftId = ref(''), saveError = ref(''), saving = ref(false), confirmDelete = ref('');
const autostart = ref(false);
const syncState = ref(null), syncUsername = ref(''), syncPassword = ref('');
const syncMessage = ref(''), syncing = ref(false);
const draft = computed(() => drafts.value.find(p => p.id === draftId.value));
const draftMeta = computed(() => providerInfo(draft.value?.provider));
const enabledCount = computed(() => profiles.value.filter(profile => profile.enabled).length);
const healthyCount = computed(() => profiles.value.filter(profile => profile.enabled && records.value[profile.id]?.status === 'success').length);
const warningCount = computed(() => profiles.value.filter(profile => profile.enabled && records.value[profile.id]?.status === 'failed').length);
const latestQuery = computed(() => Math.max(0, ...Object.values(records.value).map(record => Number(record.queriedAt) || 0)) || null);
let timer, unlisten;
let disposed = false;
const tracker = createUsageTracker(
  profile => invoke('query_profile', { profile }),
  state => { if (!disposed) records.value = state; },
  snapshot => !disposed && profiles.value.some(p => p.id === snapshot.id && JSON.stringify(p) === JSON.stringify(snapshot)),
);

function rememberSelection() { localStorage.setItem('token-plan-selected', selected.value); }
function toggleLanguage() {
  lang.value = lang.value === 'zh' ? 'en' : 'zh';
  localStorage.setItem('token-plan-language', lang.value);
  document.documentElement.lang = lang.value === 'zh' ? 'zh-CN' : 'en';
}
function refreshAll() { return Promise.all(profiles.value.map(p => tracker.refresh(p))); }
function stateFor(profile) { return records.value[profile.id] || { status: profile.enabled ? 'waiting' : 'paused', tiers: [], balances: [], queriedAt: null }; }
function hasUsage(state) { return !!(state.tiers?.length || state.balances?.length); }
function providerLabel(profile) {
  const info = providerInfo(profile.provider);
  return lang.value === 'zh' ? (info?.zh || profile.provider) : (info?.name || profile.provider);
}
function providerMark(profile) {
  return ({ volcengine: 'V', kimi: 'K', zhipu: 'GLM', zhipu_team: 'GLM', minimax: 'M', zenmux: 'Z', opencode_go: '</>', deepseek: 'D' })[profile.provider] || 'TP';
}
function statusLabel(profile, state) {
  if (!profile.enabled || state.status === 'paused') return tr('paused');
  if (state.status === 'success') return tr('normal');
  if (state.status === 'failed') return tr('abnormal');
  if (state.status === 'loading') return tr('loading');
  if (state.status === 'needsConfig') return tr('needsConfig');
  return tr('pending');
}
function statusTone(profile, state) {
  if (!profile.enabled || state.status === 'paused') return 'paused';
  if (state.status === 'success') return 'success';
  if (state.status === 'failed' || state.status === 'needsConfig') return 'failed';
  if (state.status === 'loading') return 'loading';
  return 'waiting';
}
function metricTone(fill) { return fill >= 90 ? 'danger' : fill >= 70 ? 'warning' : 'accent'; }
function editProfile(profile) {
  selected.value = profile.id;
  rememberSelection();
  settings();
}
function refreshProfile(profile) { return tracker.refresh(profile); }
async function closeApp() {
  try { await invoke('exit_app'); } catch (error) { dragError.value = String(error); }
}
function money(value) { return typeof value === 'number' && Number.isFinite(value) ? '$' + value.toFixed(2) : '—'; }

function settings(add = false) {
  if (loadError.value) return;
  showNotices.value = false;
  drafts.value = JSON.parse(JSON.stringify(profiles.value));
  draftId.value = selected.value;
  saveError.value = '';
  confirmDelete.value = '';
  if (add || !drafts.value.length) addDraft();
  showSettings.value = true;
  invoke('get_autostart').then(value => { autostart.value = value; }).catch(error => { saveError.value = String(error); });
  loadSyncState();
}
function formatCompactTime(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);
  return new Intl.DateTimeFormat(lang.value === 'zh' ? 'zh-CN' : 'en-US', { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' }).format(date);
}
function formatClock(value) {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '—' : new Intl.DateTimeFormat(lang.value === 'zh' ? 'zh-CN' : 'en-US', { hour: '2-digit', minute: '2-digit' }).format(date);
}
async function loadSyncState() {
  try {
    syncState.value = await invoke('get_sync_state');
    if (syncState.value?.username) syncUsername.value = syncState.value.username;
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
}
async function configureCloudSync() {
  if (syncing.value) return;
  if (!syncUsername.value.trim() || syncPassword.value.length < 16) { syncMessage.value = tr('credentialsRequired'); return; }
  syncing.value = true;
  syncMessage.value = '';
  try {
    syncState.value = await invoke('configure_sync', {
      username: syncUsername.value,
      password: syncPassword.value,
    });
    syncPassword.value = '';
    syncMessage.value = tr('syncConfigured');
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
  finally { syncing.value = false; }
}
async function uploadCloud() {
  if (syncing.value) return;
  syncing.value = true;
  syncMessage.value = '';
  try {
    syncState.value = await invoke('push_sync', { profiles: profiles.value });
    syncMessage.value = tr('uploadSuccess');
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
  finally { syncing.value = false; }
}
async function downloadCloud() {
  if (syncing.value) return;
  syncing.value = true;
  syncMessage.value = '';
  try {
    const result = await invoke('pull_sync');
    profiles.value = result.profiles.map(migrateProfile);
    drafts.value = JSON.parse(JSON.stringify(profiles.value));
    if (!profiles.value.some(p => p.id === selected.value)) selected.value = profiles.value[0]?.id || '';
    draftId.value = selected.value;
    rememberSelection();
    tracker.retain(profiles.value.map(p => p.id));
    refreshAll();
    syncState.value = result.state;
    syncMessage.value = tr('downloadSuccess');
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
  finally { syncing.value = false; }
}
async function disableCloudSync() {
  if (syncing.value) return;
  syncing.value = true;
  try {
    await invoke('disable_sync');
    syncState.value = null;
    syncUsername.value = '';
    syncPassword.value = '';
    syncMessage.value = tr('syncOff');
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
  finally { syncing.value = false; }
}
async function openNotices() {
  showNotices.value = true;
  await nextTick();
  noticesScroll.value?.focus();
}
async function closeNotices() {
  showNotices.value = false;
  await nextTick();
  noticesButton.value?.focus();
}
function settingsEscape() {
  if (showNotices.value) closeNotices();
  else if (!saving.value) showSettings.value = false;
}
function addDraft() {
  const p = newProfile();
  drafts.value.push(p);
  draftId.value = p.id;
  confirmDelete.value = '';
}
function changeProvider(event) {
  const previous = draft.value;
  if (!previous) return;
  // Never reuse a provider's credentials for a different provider.
  const replacement = { ...newProfile(event.target.value), id: previous.id, enabled: previous.enabled };
  drafts.value = drafts.value.map(p => p.id === previous.id ? replacement : p);
  saveError.value = '';
}
function removeDraft() {
  if (!draft.value) return;
  if (confirmDelete.value !== draftId.value) { confirmDelete.value = draftId.value; return; }
  drafts.value = drafts.value.filter(p => p.id !== draftId.value);
  draftId.value = drafts.value[0]?.id || '';
  confirmDelete.value = '';
}
async function saveSettings() {
  if (saving.value || loadError.value) return;
  saveError.value = '';
  for (const p of drafts.value) {
    const issue = !p.name.trim() ? 'nameRequired' : p.enabled ? credentialIssue(p) : '';
    if (issue) { draftId.value = p.id; saveError.value = tr(issue); return; }
  }
  saving.value = true;
  try {
    const next = JSON.parse(JSON.stringify(drafts.value));
    await invoke('save_profiles', { profiles: next });
    profiles.value = next;
    selected.value = next.some(p => p.id === draftId.value) ? draftId.value : (next[0]?.id || '');
    rememberSelection();
    tracker.retain(next.map(p => p.id));
    refreshAll();
    try { await invoke('set_autostart', { enabled: autostart.value }); }
    catch (error) { saveError.value = tr('autostartFailed') + String(error); return; }
    if (syncState.value?.enabled) {
      try { syncState.value = await invoke('push_sync', { profiles: next }); }
      catch (error) { saveError.value = tr('localSavedSyncFailed') + String(error); return; }
    }
    showSettings.value = false;
  } catch (error) { saveError.value = tr('saveFailed') + String(error); }
  finally { saving.value = false; }
}

async function beginDrag(event) {
  if (event.button !== 0 || !(event.target instanceof Element)) return;
  if (event.target.closest('button, select, input, option, textarea, label, a, [contenteditable], [role="dialog"], [data-no-drag]')) return;
  event.preventDefault();
  dragError.value = '';
  try { await getCurrentWindow().startDragging(); }
  catch (error) { dragError.value = tr('dragFailed') + String(error); }
}

onMounted(async () => {
  document.documentElement.lang = lang.value === 'zh' ? 'zh-CN' : 'en';
  try {
    profiles.value = (await invoke('load_profiles')).map(migrateProfile);
    await loadSyncState();
    if (!profiles.value.some(p => p.id === selected.value)) selected.value = profiles.value[0]?.id || '';
    refreshAll();
    timer = setInterval(refreshAll, 60000);
    const stopListening = await listen('refresh-requested', refreshAll);
    if (disposed) stopListening(); else unlisten = stopListening;
  } catch (error) { loadError.value = tr('loadFailed') + ': ' + String(error); }
});
onUnmounted(() => { disposed = true; clearInterval(timer); unlisten?.(); });
</script>

<template>
  <section class="app-window" @mousedown.left="beginDrag">
    <header class="titlebar">
      <div class="brand-block">
        <span class="brand-icon" aria-hidden="true">TP</span>
        <span><strong>TokenPlan</strong><small>{{ tr('appSubtitle') }}</small></span>
      </div>
      <nav class="window-actions" data-no-drag>
        <button class="icon-button language" @click="toggleLanguage" aria-label="中文 / English">{{ lang === 'zh' ? 'EN' : '中' }}</button>
        <button class="icon-button" @click="settings()" :disabled="!!loadError" :aria-label="tr('settings')" title="Settings">⚙</button>
        <button class="icon-button close-button" @click="closeApp" :aria-label="tr('exit')" title="Close">×</button>
      </nav>
    </header>

    <main class="dashboard-scroll">
      <section class="overview-card" :aria-label="tr('dashboard')">
        <div class="overview-top">
          <div><span class="eyebrow">{{ tr('dashboard') }}</span><h1>{{ enabledCount }} {{ tr('plansUnit') }}{{ lang === 'zh' ? tr('monitoring') : ' ' + tr('monitoring') }}</h1></div>
          <span class="pulse-icon" :class="{ spinning: profiles.some(profile => stateFor(profile).status === 'loading') }" aria-hidden="true">∿</span>
        </div>
        <div class="overview-metrics">
          <div><strong>{{ healthyCount }}</strong><span><i class="dot success"></i>{{ tr('healthy') }}</span></div>
          <div><strong>{{ warningCount }}</strong><span><i class="dot failed"></i>{{ tr('alerts') }}</span></div>
          <div><strong>{{ formatClock(latestQuery) }}</strong><span><i class="clock-mark"></i>{{ tr('lastRefresh') }}</span></div>
        </div>
      </section>

      <section class="plans-section">
        <div class="section-heading">
          <div><h2>{{ tr('myPlans') }}</h2><span>{{ profiles.length }} {{ tr('plansUnit') }}</span></div>
          <button class="secondary-button" @click="refreshAll" :disabled="!profiles.length">↻ {{ tr('refreshAll') }}</button>
        </div>

        <div v-if="profiles.length" class="plan-list">
          <article v-for="profile in profiles" :key="profile.id" class="plan-card" :class="'provider-' + profile.provider" data-no-drag @click="editProfile(profile)">
            <div class="plan-header">
              <span class="provider-mark" aria-hidden="true">{{ providerMark(profile) }}</span>
              <div class="plan-identity">
                <h3>{{ profile.name }}</h3>
                <p>{{ providerLabel(profile) }}<template v-if="stateFor(profile).plan"> · {{ stateFor(profile).plan }}</template></p>
              </div>
              <span class="status-chip" :class="statusTone(profile, stateFor(profile))"><i></i>{{ statusLabel(profile, stateFor(profile)) }}</span>
            </div>

            <div v-if="stateFor(profile).kind === 'balance' && stateFor(profile).balances?.length" class="balance-metrics">
              <div v-for="balance in stateFor(profile).balances" :key="balance.currency" class="balance-card">
                <div><span>{{ balance.currency }} {{ tr('totalBalance') }}</span><strong>{{ balance.totalBalance }}</strong></div>
                <dl><div><dt>{{ tr('grantedBalance') }}</dt><dd>{{ balance.grantedBalance }}</dd></div><div><dt>{{ tr('toppedUpBalance') }}</dt><dd>{{ balance.toppedUpBalance }}</dd></div></dl>
              </div>
            </div>

            <div v-else-if="stateFor(profile).tiers?.length" class="tier-list">
              <div v-for="(tier, index) in stateFor(profile).tiers" :key="tier.name + index" class="tier-row">
                <div class="tier-heading">
                  <div><strong>{{ tr(tier.name) }}</strong><span v-if="tier.resetsAt">↺ {{ formatCompactTime(tier.resetsAt) }}</span></div>
                  <div class="tier-value"><small v-if="tier.usedValueUsd != null || tier.maxValueUsd != null">{{ money(tier.usedValueUsd) }} / {{ money(tier.maxValueUsd) }}</small><strong>{{ tier.utilization.toFixed(1) }}%</strong></div>
                </div>
                <div class="progress-track" role="progressbar" :aria-label="tr(tier.name)" aria-valuemin="0" aria-valuemax="100" :aria-valuenow="tier.fill"><i :class="metricTone(tier.fill)" :style="{ width: tier.fill + '%' }"></i></div>
              </div>
            </div>

            <div v-else class="plan-empty">
              <span>{{ stateFor(profile).status === 'loading' ? tr('loading') : stateFor(profile).issue ? tr(stateFor(profile).issue) : tr('notUpdated') }}</span>
            </div>

            <p v-if="stateFor(profile).status === 'failed' && hasUsage(stateFor(profile))" class="stale-warning">⚠ {{ tr('staleData') }}</p>
            <p v-else-if="stateFor(profile).error" class="stale-warning" :title="stateFor(profile).error">⚠ {{ stateFor(profile).error }}</p>

            <footer class="plan-footer">
              <span>{{ stateFor(profile).queriedAt ? formatCompactTime(stateFor(profile).queriedAt) : tr('notUpdated') }}</span>
              <span class="card-actions" data-no-drag>
                <button class="card-refresh" @click.stop="refreshProfile(profile)" :disabled="!profile.enabled || stateFor(profile).status === 'loading'" :aria-label="tr('refresh')">↻</button>
                <span>{{ tr('viewConfig') }} ›</span>
              </span>
            </footer>
          </article>
        </div>

        <div v-else class="empty-dashboard">
          <span class="empty-icon" aria-hidden="true">+</span>
          <h2>{{ tr('noProfiles') }}</h2>
          <p>{{ tr('addFirst') }}</p>
          <button class="primary-button" @click="settings(true)" :disabled="!!loadError">{{ tr('add') }}</button>
        </div>
      </section>
    </main>

    <p v-if="dragError || loadError" class="error-popover" role="alert" data-no-drag>{{ loadError || dragError }}<button v-if="!loadError" @click="dragError = ''">{{ tr('close') }}</button></p>

    <section v-if="showSettings" class="settings-panel" role="dialog" aria-modal="true" :aria-label="tr(showNotices ? 'notices' : 'title')" @keydown.esc.stop.prevent="settingsEscape">
      <div class="settings-title">{{ tr(showNotices ? 'notices' : 'title') }}</div>
      <template v-if="showNotices">
        <div ref="noticesScroll" class="notices-scroll" tabindex="0" role="region" :aria-label="tr('notices')" @keydown.tab.prevent="noticesBack?.focus()">
          <ThirdPartyNotices />
        </div>
        <div class="settings-actions"><button ref="noticesBack" type="button" @click="closeNotices" @keydown.tab.prevent="noticesScroll?.focus()">{{ tr('back') }}</button></div>
      </template>
      <form v-show="!showNotices" @submit.prevent="saveSettings" class="settings-form">
        <div class="settings-scroll">
          <div class="profile-tools">
            <select v-model="draftId" :aria-label="tr('config')" :disabled="saving"><option v-for="p in drafts" :key="p.id" :value="p.id">{{ p.name }}</option></select>
            <button type="button" @click="addDraft" :disabled="saving">{{ tr('add') }}</button>
          </div>
          <fieldset v-if="draft" :disabled="saving">
            <label>{{ tr('provider') }}<select :value="draft.provider" @change="changeProvider"><option v-for="p in providers" :key="p.id" :value="p.id">{{ lang === 'zh' ? p.zh : p.name }}</option></select></label>
            <label>{{ tr('name') }}<input v-model="draft.name" autocomplete="off" /></label>
            <label v-if="draftMeta?.regions">{{ tr('region') }}<select v-model="draft.region" @change="draft.api_key = ''"><option value="cn">{{ tr('cn') }}</option><option value="global">{{ tr('global') }}</option></select></label>
            <template v-if="draftMeta?.credentials === 'aksk'">
              <label>{{ tr('ak') }}<input v-model="draft.access_key" type="password" autocomplete="off" spellcheck="false" /></label>
              <label>{{ tr('sk') }}<input v-model="draft.secret_key" type="password" autocomplete="off" spellcheck="false" /></label>
            </template>
            <label v-else>{{ tr('key') }}<input v-model="draft.api_key" type="password" autocomplete="off" spellcheck="false" /></label>
            <p v-if="draftMeta?.kind === 'balance'" class="hint">{{ tr('deepseekHint') }}</p>
            <template v-if="draftMeta?.credentials === 'team'">
              <label>{{ tr('org') }}<input v-model="draft.organization_id" autocomplete="off" spellcheck="false" /></label>
              <label>{{ tr('project') }}<input v-model="draft.project_id" autocomplete="off" spellcheck="false" /></label>
            </template>
            <label v-if="draftMeta?.credentials === 'urlKey'">{{ tr('url') }}<input v-model="draft.base_url" type="url" placeholder="https://api.zenmux.com/…" autocomplete="off" /><small>{{ tr('invalidZenmux') }}</small></label>
            <div class="profile-actions"><label class="switch-row"><input v-model="draft.enabled" type="checkbox" />{{ tr('enabled') }}</label><button type="button" class="delete" @click="removeDraft">{{ tr(confirmDelete === draftId ? 'confirmRemove' : 'remove') }}</button></div>
          </fieldset>
          <p v-else>{{ tr('noProfiles') }}</p>
          <label class="switch-row"><input v-model="autostart" type="checkbox" :disabled="saving" />{{ tr('autostart') }}</label>
          <p class="hint">{{ tr('hint') }} {{ tr('saved') }}</p>
          <section class="sync-settings" :aria-label="tr('cloudSync')">
            <div class="sync-heading"><strong>{{ tr('cloudSync') }}</strong><span>{{ syncState?.enabled ? tr('syncReady') + ' ' + syncState.revision : tr('syncOff') }}</span></div>
            <label>{{ tr('syncAccount') }}<input v-model="syncUsername" type="text" autocomplete="username" spellcheck="false" :disabled="syncing" /></label>
            <label>{{ tr('syncPassword') }}<input v-model="syncPassword" type="password" autocomplete="current-password" spellcheck="false" :disabled="syncing" /></label>
            <p class="hint">{{ tr('credentialsHint') }}</p>
            <div class="sync-actions">
              <button type="button" @click="configureCloudSync" :disabled="syncing">{{ tr('configureSync') }}</button>
              <button v-if="syncState?.enabled" type="button" @click="uploadCloud" :disabled="syncing">{{ tr('uploadCloud') }}</button>
              <button v-if="syncState?.enabled" type="button" @click="downloadCloud" :disabled="syncing">{{ tr('downloadCloud') }}</button>
              <button v-if="syncState?.enabled" type="button" class="delete" @click="disableCloudSync" :disabled="syncing">{{ tr('disableSync') }}</button>
            </div>
            <p v-if="syncMessage" class="sync-message" aria-live="polite">{{ syncMessage }}</p>
          </section>
        </div>
        <p v-if="saveError" class="form-error" role="alert">{{ saveError }}</p>
        <div class="settings-actions"><button ref="noticesButton" class="notices-link" type="button" @click="openNotices" :disabled="saving">{{ tr('notices') }}</button><button type="button" @click="showSettings = false" :disabled="saving">{{ tr('cancel') }}</button><button type="submit" :disabled="saving">{{ tr(saving ? 'saving' : 'save') }}</button></div>
      </form>
    </section>
  </section>
</template>
