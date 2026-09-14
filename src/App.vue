<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
import { invoke } from '@tauri-apps/api/core';
import { getCurrentWindow } from '@tauri-apps/api/window';
import { getCurrentWebview } from '@tauri-apps/api/webview';
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
    changePassword: '修改同步密码', currentPassword: '当前密码', newPassword: '新密码', confirmPassword: '确认新密码',
    passwordMismatch: '两次输入的新密码不一致', passwordUnchanged: '新密码不能与当前密码相同', passwordChanged: '同步密码修改成功，其他设备需要重新登录',
    prewarm: '配额预热', prewarmEnabled: '启用工作日自动预热', prewarmSchedule: '上海时区 · 工作日 08:00、13:00 · 30 分钟补偿',
    prewarmKey: 'Coding Plan API Key', prewarmModel: '套餐模型', prewarmSave: '保存预热设置', prewarmRun: '立即试运行',
    prewarmKeyStored: '服务器已保存加密 Key；留空不会覆盖', prewarmKeyMissing: '尚未配置 API Key',
    prewarmCost: '每次预热会真实调用一次 Coding Plan（最多生成 1 token），用于启动 5 小时窗口。Key 经加密存于云服务器且不会回传。',
    prewarmSaved: '配额预热设置已保存', prewarmSucceeded: '配额预热成功', prewarmFailed: '配额预热失败：', prewarmNever: '尚未执行',
    hint: '每 60 秒自动查询所有启用的配置。', dragFailed: '窗口拖动失败：',
    totalBalance: '总余额', grantedBalance: '赠送余额', toppedUpBalance: '充值余额', balanceAccount: '账户余额',
    available: '● 余额可用', insufficient: '● 余额不足，暂不可调用 API',
    deepseekHint: '仅支持 DeepSeek 官方 API Key；查询账户余额，不是套餐进度。通过火山等平台调用 DeepSeek，请使用对应平台的查询配置。',
    dashboard: '套餐总览', monitoring: '正在监控', healthy: '正常', alerts: '异常', lastRefresh: '最近刷新',
    myPlans: '我的套餐', plansUnit: '个', refreshAll: '全部刷新', used: '已使用', editPlan: '编辑套餐',
    viewConfig: '查看配置', notUpdated: '尚未获取数据', staleData: '本次刷新失败，正在显示上次数据',
    addFirst: '添加第一个 AI 套餐', normal: '正常', abnormal: '异常', pending: '待刷新', appSubtitle: 'AI 套餐用量仪表盘',
    quickGuide: '常用操作', addPlan: '添加套餐', syncSettings: '同步设置', helpTitle: '第一次使用',
    helpStep1: '添加套餐', helpStep1Text: '选择购买套餐的平台，并填写平台提供的访问凭据。',
    helpStep2: '刷新用量', helpStep2Text: '保存后点击刷新，查看套餐窗口、余额与重置时间。',
    helpStep3: '按需开启同步', helpStep3Text: '有多台设备时，再设置云同步和定时任务。',
    profileBasics: '第 1 步 · 基本信息', profileBasicsHint: '选择套餐平台，并设置一个容易识别的本地名称。',
    profileCredentials: '第 2 步 · 访问凭据', profileCredentialsHint: '凭据只用于读取套餐用量，保存时会通过 Windows DPAPI 加密。',
    profileBehavior: '第 3 步 · 查询方式', profileBehaviorHint: '启用后每 60 秒自动刷新；暂停后仍会保留配置。',
    syncGuide: '云同步账号与套餐平台账号无关，请自行设置账号和至少 16 位密码。服务器只保存端到端加密密文。',
    syncDirection: '新设备通常选择下载；刚在本机修改套餐后选择上传。',
    uploadFull: '上传本机套餐', downloadFull: '下载云端套餐', disableFull: '停用本机同步',
    confirmUpload: '上传会用本机套餐替换云端配置，是否继续？', confirmDownload: '下载会用云端套餐替换本机配置，是否继续？',
    confirmDisableSync: '停用只会清除本机登录信息，不会删除本地套餐或云端数据。是否继续？',
    prewarmGuide: '保存后先立即试运行。GitHub、阿里云和腾讯云只应启用一个调度平台，避免重复调用。',
    akHint: '在火山引擎访问控制页面复制账号 AccessKey ID。', skHint: '与 AccessKey ID 配套的 Secret AccessKey，请完整粘贴。',
    apiKeyHint: '在对应套餐平台的 API Key 管理页面复制。', settingsIntro: '按步骤配置套餐；云同步和定时任务属于可选功能。',
    navOverview: '套餐概览', navPlans: '套餐管理', navSync: '云端同步', navAutomation: '定时任务', navHelp: '使用帮助',
    overviewIntro: '集中查看所有套餐的实时用量和重置时间。', plansIntro: '添加、编辑和暂停套餐查询配置。',
    syncIntro: '用账号密码在 Windows 与 iPhone 之间同步加密配置。', automationIntro: '设置工作日定时预热，并查看最近一次执行结果。',
    helpIntro: '第一次使用时，按照下面的顺序完成配置。', saveChanges: '保存套餐修改', schedulerNeedsSync: '请先在“云端同步”中登录账号，再设置定时任务。',
    navNotifications: '通知配置', navCloud: '云平台', notificationsIntro: '任务执行后，通过群机器人通知相关人员。', cloudIntro: '选择定时任务运行平台，并安全保存部署凭据。',
    dingtalk: '钉钉机器人', wecom: '企业微信机器人', webhook: '机器人 Webhook 地址', enableChannel: '启用此通知渠道',
    notifySuccess: '任务成功时通知', notifyFailure: '任务失败时通知', testSend: '发送测试消息', saveIntegration: '保存配置', integrationSaved: '配置已加密保存到本机',
    webhookHint: '在群聊的机器人管理中复制完整 Webhook；地址包含密钥，请勿发送给他人。', notificationSafety: 'TokenPlan 只允许请求钉钉和企业微信官方 HTTPS 域名。',
    cloudProvider: '执行平台', githubActions: 'GitHub Actions', aliyunFc: '阿里云函数计算 FC', tencentScf: '腾讯云云函数 SCF',
    aliyunAk: 'AccessKey ID', aliyunSk: 'AccessKey Secret', aliyunAccount: '阿里云账号 ID', region: '地域', tencentId: 'SecretId', tencentKey: 'SecretKey',
    cloudCredentialHint: '凭据仅在当前 Windows 用户下通过 DPAPI 加密保存，不会随套餐同步上传。建议使用只允许管理函数计算的子账号密钥。',
    githubHint: '免费额度和维护成本通常更适合个人使用。部署时在 GitHub Secrets 中配置密钥。', aliyunHint: '使用 Serverless Framework 部署到阿里云 FC，可能产生函数调用、资源和日志费用。',
    tencentHint: '使用 Serverless Framework 部署到腾讯云 SCF，可能产生函数调用、资源和日志费用。', configureFirst: '请先填写并保存 Webhook。',
    minimize: '最小化', maximize: '最大化', restore: '还原窗口', displaySettings: '显示设置', textSize: '文字大小',
    textSizeHint: '同时放大菜单、说明、按钮和套餐数据。调整后会自动记住。', smaller: '较小', standard: '标准', large: '大', extraLarge: '特大',
    navSystem: '系统设置', systemIntro: '调整界面显示、语言和 Windows 启动行为。', interfaceLanguage: '界面语言', startupSettings: '启动设置',
    autoSaved: '显示和语言设置会自动保存。', currentVersion: '当前版本' },
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
    changePassword: 'Change sync password', currentPassword: 'Current password', newPassword: 'New password', confirmPassword: 'Confirm new password',
    passwordMismatch: 'The new passwords do not match', passwordUnchanged: 'The new password must differ from the current password', passwordChanged: 'Sync password changed; sign in again on other devices',
    prewarm: 'Quota prewarm', prewarmEnabled: 'Enable weekday auto prewarm', prewarmSchedule: 'Asia/Shanghai · weekdays at 08:00 and 13:00 · 30-minute catch-up',
    prewarmKey: 'Coding Plan API Key', prewarmModel: 'Plan model', prewarmSave: 'Save prewarm settings', prewarmRun: 'Run now',
    prewarmKeyStored: 'Encrypted key is stored on the server; leave blank to keep it', prewarmKeyMissing: 'No API key configured',
    prewarmCost: 'Each prewarm makes one real Coding Plan request (up to 1 generated token) to start the 5-hour window. The key is encrypted on the cloud server and never returned.',
    prewarmSaved: 'Quota prewarm settings saved', prewarmSucceeded: 'Quota prewarm succeeded', prewarmFailed: 'Quota prewarm failed: ', prewarmNever: 'Never run',
    hint: 'Every enabled profile refreshes automatically every 60 seconds.', dragFailed: 'Window drag failed: ',
    totalBalance: 'Total balance', grantedBalance: 'Granted balance', toppedUpBalance: 'Topped-up balance', balanceAccount: 'Account balance',
    available: '● Balance available', insufficient: '● Insufficient balance for API calls',
    deepseekHint: 'Requires an official DeepSeek API key. Queries account balance, not plan usage. For DeepSeek via another platform, use that platform’s profile.',
    dashboard: 'Plan overview', monitoring: 'being monitored', healthy: 'Healthy', alerts: 'Alerts', lastRefresh: 'Last refresh',
    myPlans: 'My plans', plansUnit: 'plans', refreshAll: 'Refresh all', used: 'used', editPlan: 'Edit plan',
    viewConfig: 'View settings', notUpdated: 'No usage fetched yet', staleData: 'Refresh failed; showing previous data',
    addFirst: 'Add your first AI plan', normal: 'Healthy', abnormal: 'Alert', pending: 'Pending', appSubtitle: 'AI plan usage dashboard',
    quickGuide: 'Quick actions', addPlan: 'Add plan', syncSettings: 'Sync settings', helpTitle: 'Getting started',
    helpStep1: 'Add a plan', helpStep1Text: 'Choose the platform and enter the credentials supplied by it.',
    helpStep2: 'Refresh usage', helpStep2Text: 'Save, then refresh to see windows, balances, and reset times.',
    helpStep3: 'Enable sync if needed', helpStep3Text: 'Set up cloud sync and scheduled tasks only when you need them.',
    profileBasics: 'Step 1 · Basics', profileBasicsHint: 'Choose the plan platform and give it an easy local name.',
    profileCredentials: 'Step 2 · Credentials', profileCredentialsHint: 'Credentials only query usage and are encrypted with Windows DPAPI.',
    profileBehavior: 'Step 3 · Query behavior', profileBehaviorHint: 'Enabled plans refresh every 60 seconds; paused plans stay saved.',
    syncGuide: 'Cloud sync credentials are separate from provider accounts. Choose an account and a password of at least 16 characters.',
    syncDirection: 'On a new device, download. After editing locally, upload.',
    uploadFull: 'Upload local plans', downloadFull: 'Download cloud plans', disableFull: 'Disable sync on this PC',
    confirmUpload: 'Uploading replaces the cloud profile set with this PC. Continue?', confirmDownload: 'Downloading replaces profiles on this PC. Continue?',
    confirmDisableSync: 'This only clears sync login data on this PC. Local and cloud profiles remain. Continue?',
    prewarmGuide: 'Run a test after saving. Enable only one scheduler among GitHub, Alibaba, and Tencent to avoid duplicates.',
    akHint: 'Copy the account AccessKey ID from Volcengine IAM.', skHint: 'Paste the matching Secret AccessKey.',
    apiKeyHint: 'Copy this from the provider API key page.', settingsIntro: 'Configure plans step by step. Sync and scheduling are optional.',
    navOverview: 'Overview', navPlans: 'Plan management', navSync: 'Cloud sync', navAutomation: 'Scheduled tasks', navHelp: 'Help',
    overviewIntro: 'See live usage and reset times for every plan.', plansIntro: 'Add, edit, and pause plan query profiles.',
    syncIntro: 'Sync encrypted settings between Windows and iPhone with an account and password.', automationIntro: 'Schedule weekday prewarm runs and review the latest result.',
    helpIntro: 'Follow these steps when setting up TokenPlan for the first time.', saveChanges: 'Save plan changes', schedulerNeedsSync: 'Sign in under Cloud sync before configuring scheduled tasks.',
    navNotifications: 'Notifications', navCloud: 'Cloud platforms', notificationsIntro: 'Notify your team after scheduled tasks run.', cloudIntro: 'Choose a scheduler and securely store deployment credentials.',
    dingtalk: 'DingTalk bot', wecom: 'WeCom bot', webhook: 'Bot webhook URL', enableChannel: 'Enable this channel', notifySuccess: 'Notify on success', notifyFailure: 'Notify on failure',
    testSend: 'Send test message', saveIntegration: 'Save settings', integrationSaved: 'Settings encrypted locally', webhookHint: 'Copy the complete webhook from the group bot settings. Treat it as a secret.', notificationSafety: 'TokenPlan only connects to official DingTalk and WeCom HTTPS hosts.',
    cloudProvider: 'Execution platform', githubActions: 'GitHub Actions', aliyunFc: 'Alibaba Cloud Function Compute', tencentScf: 'Tencent Cloud SCF', aliyunAk: 'AccessKey ID', aliyunSk: 'AccessKey Secret', aliyunAccount: 'Alibaba Cloud account ID', region: 'Region', tencentId: 'SecretId', tencentKey: 'SecretKey',
    cloudCredentialHint: 'Credentials are protected with Windows DPAPI for this user and are never uploaded with plan sync. Use a restricted subaccount.', githubHint: 'Usually the simplest option for personal workloads. Store keys in GitHub Secrets.', aliyunHint: 'Deploys through Serverless Framework and may incur function, resource, and logging fees.', tencentHint: 'Deploys through Serverless Framework and may incur function, resource, and logging fees.', configureFirst: 'Enter and save a webhook first.',
    minimize: 'Minimize', maximize: 'Maximize', restore: 'Restore', displaySettings: 'Display settings', textSize: 'Text size',
    textSizeHint: 'Scales menus, descriptions, controls, and plan data together. Your choice is remembered.', smaller: 'Smaller', standard: 'Standard', large: 'Large', extraLarge: 'Extra large',
    navSystem: 'System settings', systemIntro: 'Adjust display, language, and Windows startup behavior.', interfaceLanguage: 'Interface language', startupSettings: 'Startup',
    autoSaved: 'Display and language changes are saved automatically.', currentVersion: 'Current version' },
};
const tr = key => copy[lang.value][key] || key;
const profiles = ref([]);
const selected = ref(localStorage.getItem('token-plan-selected') || '');
const records = ref({});
const activePage = ref('overview');
const isMaximized = ref(false);
const savedTextScale = Number(localStorage.getItem('token-plan-text-scale'));
const textScale = ref(Number.isFinite(savedTextScale) && savedTextScale >= 90 && savedTextScale <= 150 ? savedTextScale : 115);
const showSettings = ref(false), dragError = ref(''), loadError = ref('');
const showNotices = ref(false), noticesButton = ref(null), noticesScroll = ref(null), noticesBack = ref(null);
const drafts = ref([]), draftId = ref(''), saveError = ref(''), saving = ref(false), confirmDelete = ref('');
const autostart = ref(false);
const syncState = ref(null), syncUsername = ref(''), syncPassword = ref('');
const currentSyncPassword = ref(''), newSyncPassword = ref(''), confirmSyncPassword = ref('');
const syncMessage = ref(''), syncing = ref(false);
const prewarmState = ref(null), prewarmEnabled = ref(false), prewarmApiKey = ref(''), prewarmModel = ref('ark-code-latest'), prewarming = ref(false);
const integrations = ref({
  notifications: { dingtalkEnabled: false, dingtalkWebhook: '', wecomEnabled: false, wecomWebhook: '', notifyOnSuccess: true, notifyOnFailure: true },
  cloud: { provider: 'github', aliyunAccessKeyId: '', aliyunAccessKeySecret: '', aliyunAccountId: '', aliyunRegion: 'cn-shanghai', tencentSecretId: '', tencentSecretKey: '', tencentRegion: 'ap-shanghai' },
});
const integrationBusy = ref(false), integrationMessage = ref('');
const prewarmModels = ['ark-code-latest', 'doubao-seed-2.0-code', 'doubao-seed-2.0-pro', 'doubao-seed-2.0-lite', 'doubao-seed-code', 'minimax-m2.5', 'glm-4.7', 'deepseek-v3.2', 'kimi-k2.5'];
const draft = computed(() => drafts.value.find(p => p.id === draftId.value));
const draftMeta = computed(() => providerInfo(draft.value?.provider));
const enabledCount = computed(() => profiles.value.filter(profile => profile.enabled).length);
const healthyCount = computed(() => profiles.value.filter(profile => profile.enabled && records.value[profile.id]?.status === 'success').length);
const warningCount = computed(() => profiles.value.filter(profile => profile.enabled && records.value[profile.id]?.status === 'failed').length);
const latestQuery = computed(() => Math.max(0, ...Object.values(records.value).map(record => Number(record.queriedAt) || 0)) || null);
const pageCopy = computed(() => ({
  overview: ['navOverview', 'overviewIntro'], plans: ['navPlans', 'plansIntro'], sync: ['navSync', 'syncIntro'],
  automation: ['navAutomation', 'automationIntro'], notifications: ['navNotifications', 'notificationsIntro'],
  cloud: ['navCloud', 'cloudIntro'], system: ['navSystem', 'systemIntro'], help: ['navHelp', 'helpIntro'],
})[activePage.value] || ['navOverview', 'overviewIntro']);
let timer, unlisten, resizeUnlisten;
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
async function minimizeWindow() {
  try { await getCurrentWindow().minimize(); } catch (error) { dragError.value = String(error); }
}
async function toggleMaximize() {
  try {
    const window = getCurrentWindow();
    await window.toggleMaximize();
    isMaximized.value = await window.isMaximized();
  } catch (error) { dragError.value = String(error); }
}
function handleTitlebarDoubleClick(event) {
  if (!(event.target instanceof Element) || !event.target.closest('button')) toggleMaximize();
}
async function applyTextScale(value = textScale.value) {
  textScale.value = Math.min(150, Math.max(90, Number(value) || 115));
  localStorage.setItem('token-plan-text-scale', String(textScale.value));
  try { await getCurrentWebview().setZoom(textScale.value / 100); }
  catch (error) { dragError.value = String(error); }
}
function money(value) { return typeof value === 'number' && Number.isFinite(value) ? '$' + value.toFixed(2) : '—'; }

function settings(add = false, page = 'plans') {
  if (loadError.value) return;
  showNotices.value = false;
  drafts.value = JSON.parse(JSON.stringify(profiles.value));
  draftId.value = selected.value;
  saveError.value = '';
  confirmDelete.value = '';
  if (add || !drafts.value.length) addDraft();
  showSettings.value = true;
  activePage.value = page;
  invoke('get_autostart').then(value => { autostart.value = value; }).catch(error => { saveError.value = String(error); });
  loadSyncState();
}
function navigate(page) {
  if (page === 'plans' || page === 'sync' || page === 'automation') settings(false, page);
  else {
    activePage.value = page;
    if (page === 'notifications' || page === 'cloud') loadIntegrations();
  }
}
async function updateAutostart() {
  try { await invoke('set_autostart', { enabled: autostart.value }); }
  catch (error) { dragError.value = tr('autostartFailed') + String(error); }
}
async function loadIntegrations() {
  integrationMessage.value = '';
  try { integrations.value = await invoke('load_integrations'); }
  catch (error) { integrationMessage.value = String(error); }
}
async function saveIntegrations() {
  if (integrationBusy.value) return;
  integrationBusy.value = true;
  integrationMessage.value = '';
  try { integrations.value = await invoke('save_integrations', { settings: integrations.value }); integrationMessage.value = tr('integrationSaved'); }
  catch (error) { integrationMessage.value = String(error); }
  finally { integrationBusy.value = false; }
}
async function testNotification(kind) {
  const webhook = kind === 'dingtalk' ? integrations.value.notifications.dingtalkWebhook : integrations.value.notifications.wecomWebhook;
  if (!webhook.trim()) { integrationMessage.value = tr('configureFirst'); return; }
  integrationBusy.value = true;
  integrationMessage.value = '';
  try { integrationMessage.value = await invoke('test_notification', { kind, webhook }); }
  catch (error) { integrationMessage.value = String(error); }
  finally { integrationBusy.value = false; }
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
    if (syncState.value?.enabled) await loadPrewarm();
  } catch (error) { syncMessage.value = tr('syncFailed') + String(error); }
}
async function loadPrewarm() {
  try {
    prewarmState.value = await invoke('get_prewarm');
    prewarmEnabled.value = prewarmState.value.enabled;
    prewarmModel.value = prewarmState.value.model;
  } catch (error) { syncMessage.value = tr('prewarmFailed') + String(error); }
}
async function savePrewarm() {
  if (prewarming.value) return;
  prewarming.value = true;
  syncMessage.value = '';
  try {
    prewarmState.value = await invoke('save_prewarm', { enabled: prewarmEnabled.value, apiKey: prewarmApiKey.value, model: prewarmModel.value });
    prewarmApiKey.value = '';
    syncMessage.value = tr('prewarmSaved');
  } catch (error) { syncMessage.value = tr('prewarmFailed') + String(error); }
  finally { prewarming.value = false; }
}
async function runPrewarm() {
  if (prewarming.value) return;
  prewarming.value = true;
  syncMessage.value = '';
  try {
    const result = await invoke('run_prewarm');
    prewarmState.value = { ...prewarmState.value, lastRun: result };
    syncMessage.value = result.success ? tr('prewarmSucceeded') : tr('prewarmFailed') + (result.error || `HTTP ${result.httpStatus || '—'}`);
  } catch (error) { syncMessage.value = tr('prewarmFailed') + String(error); }
  finally { prewarming.value = false; }
}
function prewarmRunLabel() {
  const run = prewarmState.value?.lastRun;
  if (!run) return tr('prewarmNever');
  const time = formatCompactTime(run.triggeredAt * 1000);
  return `${run.success ? '✓' : '⚠'} ${time}${run.httpStatus ? ` · HTTP ${run.httpStatus}` : ''}`;
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
  if (!window.confirm(tr('confirmUpload'))) return;
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
  if (!window.confirm(tr('confirmDownload'))) return;
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
  if (!window.confirm(tr('confirmDisableSync'))) return;
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
async function changeCloudPassword() {
  if (syncing.value) return;
  if (!currentSyncPassword.value || newSyncPassword.value.length < 16) { syncMessage.value = tr('credentialsRequired'); return; }
  if (newSyncPassword.value !== confirmSyncPassword.value) { syncMessage.value = tr('passwordMismatch'); return; }
  if (newSyncPassword.value === currentSyncPassword.value) { syncMessage.value = tr('passwordUnchanged'); return; }
  syncing.value = true;
  syncMessage.value = '';
  try {
    syncState.value = await invoke('change_sync_password', {
      currentPassword: currentSyncPassword.value,
      newPassword: newSyncPassword.value,
    });
    currentSyncPassword.value = '';
    newSyncPassword.value = '';
    confirmSyncPassword.value = '';
    syncMessage.value = tr('passwordChanged');
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
    const window = getCurrentWindow();
    isMaximized.value = await window.isMaximized();
    resizeUnlisten = await window.onResized(async () => { isMaximized.value = await window.isMaximized(); });
    await applyTextScale();
    autostart.value = await invoke('get_autostart');
    profiles.value = (await invoke('load_profiles')).map(migrateProfile);
    await loadSyncState();
    await loadIntegrations();
    if (!profiles.value.some(p => p.id === selected.value)) selected.value = profiles.value[0]?.id || '';
    refreshAll();
    timer = setInterval(refreshAll, 60000);
    const stopListening = await listen('refresh-requested', refreshAll);
    if (disposed) stopListening(); else unlisten = stopListening;
  } catch (error) { loadError.value = tr('loadFailed') + ': ' + String(error); }
});
onUnmounted(() => { disposed = true; clearInterval(timer); unlisten?.(); resizeUnlisten?.(); });
</script>

<template>
  <section class="app-window" @mousedown.left="beginDrag">
    <header class="titlebar" @dblclick.left="handleTitlebarDoubleClick">
      <div class="brand-block"><span class="brand-icon" aria-hidden="true">TP</span><span><strong>TokenPlan</strong><small>{{ tr('appSubtitle') }}</small></span></div>
      <nav class="window-actions" data-no-drag>
        <button class="icon-button language" @click.stop="toggleLanguage" aria-label="中文 / English">{{ lang === 'zh' ? 'EN' : '中' }}</button>
        <button class="caption-button minimize-button" @click.stop="minimizeWindow" :aria-label="tr('minimize')" :title="tr('minimize')"><span aria-hidden="true">—</span></button>
        <button class="caption-button maximize-button" @click.stop="toggleMaximize" :aria-label="tr(isMaximized ? 'restore' : 'maximize')" :title="tr(isMaximized ? 'restore' : 'maximize')"><span aria-hidden="true">{{ isMaximized ? '❐' : '□' }}</span></button>
        <button class="caption-button close-button" @click.stop="closeApp" :aria-label="tr('exit')" :title="tr('exit')"><span aria-hidden="true">×</span></button>
      </nav>
    </header>

    <div class="workspace-layout">
      <aside class="sidebar" data-no-drag aria-label="TokenPlan navigation">
        <nav class="sidebar-nav">
          <button :class="{ active: activePage === 'overview' }" @click="navigate('overview')"><span>⌂</span><strong>{{ tr('navOverview') }}</strong></button>
          <button :class="{ active: activePage === 'plans' }" @click="navigate('plans')" :disabled="!!loadError"><span>▤</span><strong>{{ tr('navPlans') }}</strong><i>{{ profiles.length }}</i></button>
          <button :class="{ active: activePage === 'sync' }" @click="navigate('sync')" :disabled="!!loadError"><span>☁</span><strong>{{ tr('navSync') }}</strong><i :class="{ online: syncState?.enabled }"></i></button>
          <button :class="{ active: activePage === 'automation' }" @click="navigate('automation')" :disabled="!!loadError"><span>◷</span><strong>{{ tr('navAutomation') }}</strong></button>
          <button :class="{ active: activePage === 'notifications' }" @click="navigate('notifications')"><span>◉</span><strong>{{ tr('navNotifications') }}</strong></button>
          <button :class="{ active: activePage === 'cloud' }" @click="navigate('cloud')"><span>◇</span><strong>{{ tr('navCloud') }}</strong></button>
          <button :class="{ active: activePage === 'system' }" @click="navigate('system')"><span>⚙</span><strong>{{ tr('navSystem') }}</strong></button>
          <button :class="{ active: activePage === 'help' }" @click="navigate('help')"><span>?</span><strong>{{ tr('navHelp') }}</strong></button>
        </nav>
        <div class="sidebar-footer">
          <span><i :class="syncState?.enabled ? 'online' : ''"></i>{{ syncState?.enabled ? tr('syncReady') + ' ' + syncState.revision : tr('syncOff') }}</span>
          <small>TokenPlan 0.8.0</small>
        </div>
      </aside>

      <main class="content-pane" data-no-drag>
        <header class="page-heading">
          <div>
            <h1>{{ tr(pageCopy[0]) }}</h1>
            <p>{{ tr(pageCopy[1]) }}</p>
          </div>
          <button v-if="activePage === 'overview'" class="secondary-button" @click="refreshAll" :disabled="!profiles.length">↻ {{ tr('refreshAll') }}</button>
          <button v-else-if="activePage === 'plans'" class="primary-button" @click="addDraft" :disabled="saving">＋ {{ tr('addPlan') }}</button>
        </header>

        <div v-if="activePage === 'overview'" class="page-scroll dashboard-scroll">
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

      <section class="quick-actions-card" :aria-label="tr('quickGuide')">
        <span class="card-section-label">{{ tr('quickGuide') }}</span>
        <div class="quick-actions-grid">
          <button type="button" @click="refreshAll" :disabled="!profiles.length"><span aria-hidden="true">↻</span><strong>{{ tr('refreshAll') }}</strong><small>{{ tr('helpStep2Text') }}</small></button>
          <button type="button" @click="settings(true, 'plans')" :disabled="!!loadError"><span aria-hidden="true">＋</span><strong>{{ tr('addPlan') }}</strong><small>{{ tr('helpStep1Text') }}</small></button>
          <button type="button" @click="navigate('sync')" :disabled="!!loadError"><span aria-hidden="true">☁</span><strong>{{ tr('syncSettings') }}</strong><small>{{ tr('helpStep3Text') }}</small></button>
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
          <span class="empty-icon" aria-hidden="true">TP</span>
          <h2>{{ tr('helpTitle') }}</h2>
          <p>{{ tr('addFirst') }}</p>
          <ol class="beginner-steps">
            <li><span>1</span><div><strong>{{ tr('helpStep1') }}</strong><small>{{ tr('helpStep1Text') }}</small></div></li>
            <li><span>2</span><div><strong>{{ tr('helpStep2') }}</strong><small>{{ tr('helpStep2Text') }}</small></div></li>
            <li><span>3</span><div><strong>{{ tr('helpStep3') }}</strong><small>{{ tr('helpStep3Text') }}</small></div></li>
          </ol>
          <button class="primary-button large-action" @click="settings(true, 'plans')" :disabled="!!loadError">＋ {{ tr('addFirst') }}</button>
        </div>
      </section>
      </div>

        <form v-else-if="activePage === 'plans'" @submit.prevent="saveSettings" class="page-scroll settings-panel embedded-settings">
          <div class="profile-tools">
            <select v-model="draftId" :aria-label="tr('config')" :disabled="saving"><option v-for="p in drafts" :key="p.id" :value="p.id">{{ p.name }}</option></select>
            <button type="button" @click="addDraft" :disabled="saving">{{ tr('add') }}</button>
          </div>
          <fieldset v-if="draft" :disabled="saving" class="profile-editor">
            <section class="form-card">
              <div class="form-card-heading"><span class="step-number">1</span><div><strong>{{ tr('profileBasics') }}</strong><small>{{ tr('profileBasicsHint') }}</small></div></div>
              <label>{{ tr('provider') }}<select :value="draft.provider" @change="changeProvider"><option v-for="p in providers" :key="p.id" :value="p.id">{{ lang === 'zh' ? p.zh : p.name }}</option></select></label>
              <label>{{ tr('name') }}<input v-model="draft.name" autocomplete="off" :placeholder="providerLabel(draft)" /></label>
              <label v-if="draftMeta?.regions">{{ tr('region') }}<select v-model="draft.region" @change="draft.api_key = ''"><option value="cn">{{ tr('cn') }}</option><option value="global">{{ tr('global') }}</option></select></label>
            </section>

            <section class="form-card">
              <div class="form-card-heading"><span class="step-number">2</span><div><strong>{{ tr('profileCredentials') }}</strong><small>{{ tr('profileCredentialsHint') }}</small></div></div>
              <template v-if="draftMeta?.credentials === 'aksk'">
                <label>{{ tr('ak') }}<input v-model="draft.access_key" autocomplete="off" spellcheck="false" /><small>{{ tr('akHint') }}</small></label>
                <label>{{ tr('sk') }}<input v-model="draft.secret_key" type="password" autocomplete="off" spellcheck="false" /><small>{{ tr('skHint') }}</small></label>
              </template>
              <label v-else>{{ tr('key') }}<input v-model="draft.api_key" type="password" autocomplete="off" spellcheck="false" /><small>{{ tr('apiKeyHint') }}</small></label>
              <p v-if="draftMeta?.kind === 'balance'" class="inline-help">ⓘ {{ tr('deepseekHint') }}</p>
              <template v-if="draftMeta?.credentials === 'team'">
                <label>{{ tr('org') }}<input v-model="draft.organization_id" autocomplete="off" spellcheck="false" /></label>
                <label>{{ tr('project') }}<input v-model="draft.project_id" autocomplete="off" spellcheck="false" /></label>
              </template>
              <label v-if="draftMeta?.credentials === 'urlKey'">{{ tr('url') }}<input v-model="draft.base_url" type="url" placeholder="https://api.zenmux.com/…" autocomplete="off" /><small>{{ tr('invalidZenmux') }}</small></label>
            </section>

            <section class="form-card">
              <div class="form-card-heading"><span class="step-number">3</span><div><strong>{{ tr('profileBehavior') }}</strong><small>{{ tr('profileBehaviorHint') }}</small></div></div>
              <div class="profile-actions"><label class="switch-row"><input v-model="draft.enabled" type="checkbox" />{{ tr('enabled') }}</label><button type="button" class="delete" @click="removeDraft">{{ tr(confirmDelete === draftId ? 'confirmRemove' : 'remove') }}</button></div>
              <p class="inline-help success-help">✓ {{ tr('hint') }} {{ tr('saved') }}</p>
            </section>
          </fieldset>
          <p v-else>{{ tr('noProfiles') }}</p>
          <p v-if="saveError" class="form-error" role="alert">{{ saveError }}</p>
          <div class="sticky-save"><button type="submit" class="primary-button" :disabled="saving">{{ tr(saving ? 'saving' : 'saveChanges') }}</button></div>
        </form>

        <div v-else-if="activePage === 'sync'" class="page-scroll settings-panel embedded-settings">
          <section class="sync-settings feature-card" :aria-label="tr('cloudSync')">
            <div class="sync-heading"><div><span class="section-symbol" aria-hidden="true">☁</span><strong>{{ tr('cloudSync') }}</strong></div><span>{{ syncState?.enabled ? tr('syncReady') + ' ' + syncState.revision : tr('syncOff') }}</span></div>
            <p class="inline-help">ⓘ {{ tr('syncGuide') }}</p>
            <label>{{ tr('syncAccount') }}<input v-model="syncUsername" type="text" autocomplete="username" spellcheck="false" :disabled="syncing" /></label>
            <label>{{ tr('syncPassword') }}<input v-model="syncPassword" type="password" autocomplete="current-password" spellcheck="false" :disabled="syncing" placeholder="至少 16 位 / at least 16 characters" /></label>
            <p class="hint">🔒 {{ tr('credentialsHint') }}</p>
            <div class="sync-actions">
              <button class="primary-inline" type="button" @click="configureCloudSync" :disabled="syncing">🔐 {{ tr('configureSync') }}</button>
            </div>
            <template v-if="syncState?.enabled">
              <div class="sync-direction">
                <strong>{{ tr('helpStep2') }}</strong><small>{{ tr('syncDirection') }}</small>
                <div class="sync-actions two-column">
                  <button type="button" @click="downloadCloud" :disabled="syncing">↓ {{ tr('downloadFull') }}</button>
                  <button type="button" @click="uploadCloud" :disabled="syncing">↑ {{ tr('uploadFull') }}</button>
                </div>
              </div>
              <button type="button" class="delete subtle-delete" @click="disableCloudSync" :disabled="syncing">{{ tr('disableFull') }}</button>
            </template>
            <details v-if="syncState?.enabled" class="password-change">
              <summary>{{ tr('changePassword') }}</summary>
              <p class="inline-help">ⓘ {{ lang === 'zh' ? '修改后云端配置会重新加密，其他设备必须使用新密码重新登录。' : 'Cloud data is re-encrypted and other devices must sign in with the new password.' }}</p>
              <label>{{ tr('currentPassword') }}<input v-model="currentSyncPassword" type="password" autocomplete="current-password" spellcheck="false" :disabled="syncing" /></label>
              <label>{{ tr('newPassword') }}<input v-model="newSyncPassword" type="password" autocomplete="new-password" spellcheck="false" :disabled="syncing" /></label>
              <label>{{ tr('confirmPassword') }}<input v-model="confirmSyncPassword" type="password" autocomplete="new-password" spellcheck="false" :disabled="syncing" /></label>
              <button type="button" @click="changeCloudPassword" :disabled="syncing">{{ tr('changePassword') }}</button>
            </details>
            <p v-if="syncMessage" class="sync-message" aria-live="polite">{{ syncMessage }}</p>
          </section>
        </div>

        <div v-else-if="activePage === 'automation'" class="page-scroll settings-panel embedded-settings">
          <section v-if="syncState?.enabled" class="sync-settings feature-card prewarm-settings">
            <div class="sync-heading"><div><span class="section-symbol" aria-hidden="true">◷</span><strong>{{ tr('prewarm') }}</strong></div><span>{{ tr('prewarmSchedule') }}</span></div>
            <p class="inline-help">ⓘ {{ tr('prewarmGuide') }}</p>
            <label class="switch-row"><input v-model="prewarmEnabled" type="checkbox" :disabled="prewarming" />{{ tr('prewarmEnabled') }}</label>
            <label>{{ tr('prewarmModel') }}<select v-model="prewarmModel" :disabled="prewarming"><option v-for="model in prewarmModels" :key="model" :value="model">{{ model }}</option></select></label>
            <label>{{ tr('prewarmKey') }}<input v-model="prewarmApiKey" type="password" autocomplete="off" spellcheck="false" :placeholder="prewarmState?.hasApiKey ? tr('prewarmKeyStored') : tr('prewarmKeyMissing')" :disabled="prewarming" /></label>
            <small>{{ tr('prewarmCost') }}</small>
            <div class="automation-status"><span>{{ tr('lastRefresh') }}</span><strong>{{ prewarmRunLabel() }}</strong></div>
            <div class="sync-actions two-column"><button type="button" class="primary-inline" @click="savePrewarm" :disabled="prewarming">✓ {{ tr('prewarmSave') }}</button><button type="button" @click="runPrewarm" :disabled="prewarming || !prewarmState?.hasApiKey">▶ {{ tr('prewarmRun') }}</button></div>
            <p v-if="syncMessage" class="sync-message" aria-live="polite">{{ syncMessage }}</p>
          </section>
          <section v-else class="empty-dashboard compact-empty"><span class="empty-icon">◷</span><h2>{{ tr('schedulerNeedsSync') }}</h2><button class="primary-button" @click="navigate('sync')">{{ tr('navSync') }} ›</button></section>
        </div>

        <form v-else-if="activePage === 'notifications'" class="page-scroll settings-panel embedded-settings" @submit.prevent="saveIntegrations">
          <div class="integration-grid">
            <section class="feature-card integration-card">
              <div class="integration-heading"><span class="channel-mark dingtalk-mark">钉</span><div><h2>{{ tr('dingtalk') }}</h2><p>{{ tr('webhookHint') }}</p></div></div>
              <label class="switch-row"><input v-model="integrations.notifications.dingtalkEnabled" type="checkbox" :disabled="integrationBusy" />{{ tr('enableChannel') }}</label>
              <label>{{ tr('webhook') }}<input v-model="integrations.notifications.dingtalkWebhook" type="password" autocomplete="off" spellcheck="false" placeholder="https://oapi.dingtalk.com/robot/send?access_token=…" :disabled="integrationBusy" /></label>
              <button type="button" class="secondary-button test-button" @click="testNotification('dingtalk')" :disabled="integrationBusy">▷ {{ tr('testSend') }}</button>
            </section>
            <section class="feature-card integration-card">
              <div class="integration-heading"><span class="channel-mark wecom-mark">企</span><div><h2>{{ tr('wecom') }}</h2><p>{{ tr('webhookHint') }}</p></div></div>
              <label class="switch-row"><input v-model="integrations.notifications.wecomEnabled" type="checkbox" :disabled="integrationBusy" />{{ tr('enableChannel') }}</label>
              <label>{{ tr('webhook') }}<input v-model="integrations.notifications.wecomWebhook" type="password" autocomplete="off" spellcheck="false" placeholder="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=…" :disabled="integrationBusy" /></label>
              <button type="button" class="secondary-button test-button" @click="testNotification('wecom')" :disabled="integrationBusy">▷ {{ tr('testSend') }}</button>
            </section>
          </div>
          <section class="feature-card notification-rules">
            <h2>{{ lang === 'zh' ? '通知规则' : 'Notification rules' }}</h2>
            <label class="switch-row"><input v-model="integrations.notifications.notifyOnSuccess" type="checkbox" :disabled="integrationBusy" />{{ tr('notifySuccess') }}</label>
            <label class="switch-row"><input v-model="integrations.notifications.notifyOnFailure" type="checkbox" :disabled="integrationBusy" />{{ tr('notifyFailure') }}</label>
            <p class="inline-help">🔒 {{ tr('notificationSafety') }}</p>
          </section>
          <p v-if="integrationMessage" class="integration-message" aria-live="polite">{{ integrationMessage }}</p>
          <div class="sticky-save"><button type="submit" class="primary-button" :disabled="integrationBusy">{{ tr('saveIntegration') }}</button></div>
        </form>

        <form v-else-if="activePage === 'cloud'" class="page-scroll settings-panel embedded-settings" @submit.prevent="saveIntegrations">
          <section class="feature-card cloud-selector">
            <h2>{{ tr('cloudProvider') }}</h2>
            <div class="provider-choice">
              <label :class="{ selected: integrations.cloud.provider === 'github' }"><input v-model="integrations.cloud.provider" type="radio" value="github" /><span>GH</span><strong>{{ tr('githubActions') }}</strong><small>{{ tr('githubHint') }}</small></label>
              <label :class="{ selected: integrations.cloud.provider === 'aliyun' }"><input v-model="integrations.cloud.provider" type="radio" value="aliyun" /><span>阿</span><strong>{{ tr('aliyunFc') }}</strong><small>{{ tr('aliyunHint') }}</small></label>
              <label :class="{ selected: integrations.cloud.provider === 'tencent' }"><input v-model="integrations.cloud.provider" type="radio" value="tencent" /><span>腾</span><strong>{{ tr('tencentScf') }}</strong><small>{{ tr('tencentHint') }}</small></label>
            </div>
          </section>
          <section v-if="integrations.cloud.provider === 'github'" class="feature-card integration-card cloud-form"><div class="integration-heading"><span class="channel-mark github-mark">GH</span><div><h2>{{ tr('githubActions') }}</h2><p>{{ tr('githubHint') }}</p></div></div><p class="inline-help">ⓘ {{ lang === 'zh' ? 'GitHub 凭据请继续在仓库 Settings → Secrets and variables → Actions 中维护，TokenPlan 不在本机重复保存。' : 'Manage credentials in repository Settings → Secrets and variables → Actions.' }}</p></section>
          <section v-else-if="integrations.cloud.provider === 'aliyun'" class="feature-card integration-card cloud-form">
            <div class="integration-heading"><span class="channel-mark aliyun-mark">阿</span><div><h2>{{ tr('aliyunFc') }}</h2><p>{{ tr('aliyunHint') }}</p></div></div>
            <div class="field-grid"><label>{{ tr('aliyunAk') }}<input v-model="integrations.cloud.aliyunAccessKeyId" autocomplete="off" spellcheck="false" /></label><label>{{ tr('aliyunSk') }}<input v-model="integrations.cloud.aliyunAccessKeySecret" type="password" autocomplete="off" spellcheck="false" /></label><label>{{ tr('aliyunAccount') }}<input v-model="integrations.cloud.aliyunAccountId" autocomplete="off" spellcheck="false" /></label><label>{{ tr('region') }}<input v-model="integrations.cloud.aliyunRegion" autocomplete="off" spellcheck="false" /></label></div>
          </section>
          <section v-else class="feature-card integration-card cloud-form">
            <div class="integration-heading"><span class="channel-mark tencent-mark">腾</span><div><h2>{{ tr('tencentScf') }}</h2><p>{{ tr('tencentHint') }}</p></div></div>
            <div class="field-grid"><label>{{ tr('tencentId') }}<input v-model="integrations.cloud.tencentSecretId" autocomplete="off" spellcheck="false" /></label><label>{{ tr('tencentKey') }}<input v-model="integrations.cloud.tencentSecretKey" type="password" autocomplete="off" spellcheck="false" /></label><label>{{ tr('region') }}<input v-model="integrations.cloud.tencentRegion" autocomplete="off" spellcheck="false" /></label></div>
          </section>
          <p class="inline-help cloud-security">🔒 {{ tr('cloudCredentialHint') }}</p>
          <p v-if="integrationMessage" class="integration-message" aria-live="polite">{{ integrationMessage }}</p>
          <div class="sticky-save"><button type="submit" class="primary-button" :disabled="integrationBusy">{{ tr('saveIntegration') }}</button></div>
        </form>

        <div v-else-if="activePage === 'system'" class="page-scroll system-page">
          <section class="feature-card system-card">
            <div class="text-scale-panel system-section">
              <div class="text-scale-heading"><div><h2>{{ tr('displaySettings') }}</h2><p>{{ tr('textSizeHint') }}</p></div><strong>{{ textScale }}%</strong></div>
              <label for="text-scale">{{ tr('textSize') }}</label>
              <input id="text-scale" v-model.number="textScale" type="range" min="90" max="150" step="5" @input="applyTextScale()" />
              <div class="scale-presets">
                <button v-for="preset in [{ value: 90, label: 'smaller' }, { value: 100, label: 'standard' }, { value: 125, label: 'large' }, { value: 150, label: 'extraLarge' }]" :key="preset.value" type="button" :class="{ active: textScale === preset.value }" @click="applyTextScale(preset.value)">{{ tr(preset.label) }}<small>{{ preset.value }}%</small></button>
              </div>
            </div>
            <div class="system-section system-row"><div><h2>{{ tr('interfaceLanguage') }}</h2><p>{{ tr('autoSaved') }}</p></div><div class="segmented-control"><button type="button" :class="{ active: lang === 'zh' }" @click="lang !== 'zh' && toggleLanguage()">中文</button><button type="button" :class="{ active: lang === 'en' }" @click="lang !== 'en' && toggleLanguage()">English</button></div></div>
            <div class="system-section system-row"><div><h2>{{ tr('startupSettings') }}</h2><p>{{ tr('autostart') }}</p></div><label class="toggle-control"><input v-model="autostart" type="checkbox" @change="updateAutostart" /><span></span></label></div>
            <div class="system-row version-row"><div><h2>{{ tr('currentVersion') }}</h2><p>TokenPlan for Windows</p></div><strong>0.8.0</strong></div>
          </section>
        </div>

        <div v-else class="page-scroll help-page">
          <section v-if="!showNotices" class="feature-card help-card">
            <ol class="beginner-steps">
              <li><span>1</span><div><strong>{{ tr('helpStep1') }}</strong><small>{{ tr('helpStep1Text') }}</small><button @click="settings(true, 'plans')">{{ tr('addPlan') }} ›</button></div></li>
              <li><span>2</span><div><strong>{{ tr('helpStep2') }}</strong><small>{{ tr('helpStep2Text') }}</small><button @click="navigate('overview')">{{ tr('navOverview') }} ›</button></div></li>
              <li><span>3</span><div><strong>{{ tr('helpStep3') }}</strong><small>{{ tr('helpStep3Text') }}</small><button @click="navigate('sync')">{{ tr('navSync') }} ›</button></div></li>
            </ol>
            <button ref="noticesButton" class="secondary-button" type="button" @click="openNotices">{{ tr('notices') }}</button>
          </section>
          <section v-else class="feature-card notices-card"><button ref="noticesBack" class="secondary-button" type="button" @click="closeNotices">‹ {{ tr('back') }}</button><div ref="noticesScroll" class="notices-scroll" tabindex="0"><ThirdPartyNotices /></div></section>
        </div>
      </main>
    </div>

    <p v-if="dragError || loadError" class="error-popover" role="alert" data-no-drag>{{ loadError || dragError }}<button v-if="!loadError" @click="dragError = ''">{{ tr('close') }}</button></p>
  </section>
</template>
