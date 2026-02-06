const TILE_MODE_KEY = 'ui_tiles_mode';
const TILE_EXPANDED_KEY = 'ui_tiles_expanded';
const TILE_COLLAPSED_KEY = 'ui_tiles_collapsed';
const VIEW_DEFAULT_VERSION_KEY = 'ui_view_default_version';
const TILE_DEFAULT_VERSION_KEY = 'ui_tiles_default_version';
const SETTINGS_ADVANCED_KEY = 'astral.settings.advanced';
const SETTINGS_DENSITY_KEY = 'astral.settings.density';
const SHOW_DISABLED_KEY = 'astra.showDisabledStreams';

function getStoredBool(key, fallback) {
  const value = localStorage.getItem(key);
  if (value === null || value === undefined || value === '') return fallback;
  return value === '1' || value === 'true';
}

function normalizeTilesMode(value) {
  const mode = String(value || '').toLowerCase();
  if (mode === 'compact' || mode === 'expanded') return mode;
  return 'expanded';
}

function parseTilesIdList(value) {
  if (!value) return [];
  try {
    const parsed = JSON.parse(value);
    if (!Array.isArray(parsed)) return [];
    return parsed.map((id) => String(id));
  } catch (err) {
    return [];
  }
}

function loadTilesUiState() {
  const storedMode = localStorage.getItem(TILE_MODE_KEY);
  const version = localStorage.getItem(TILE_DEFAULT_VERSION_KEY);
  const mode = normalizeTilesMode((storedMode && version === '20260205') ? storedMode : 'compact');
  if (version !== '20260205') {
    localStorage.setItem(TILE_MODE_KEY, mode);
    localStorage.setItem(TILE_DEFAULT_VERSION_KEY, '20260205');
  }
  const expandedIds = new Set(parseTilesIdList(localStorage.getItem(TILE_EXPANDED_KEY)));
  const collapsedIds = new Set(parseTilesIdList(localStorage.getItem(TILE_COLLAPSED_KEY)));
  return { mode, expandedIds, collapsedIds };
}

function loadViewModeState() {
  const stored = localStorage.getItem('astra.viewMode');
  const version = localStorage.getItem(VIEW_DEFAULT_VERSION_KEY);
  const mode = normalizeViewMode((stored && version === '20260205') ? stored : 'cards');
  if (version !== '20260205') {
    localStorage.setItem('astra.viewMode', mode);
    localStorage.setItem(VIEW_DEFAULT_VERSION_KEY, '20260205');
  }
  return mode;
}

function loadShowDisabledState() {
  const stored = localStorage.getItem(SHOW_DISABLED_KEY);
  if (stored === null || stored === undefined || stored === '') {
    localStorage.setItem(SHOW_DISABLED_KEY, '1');
    return true;
  }
  return stored === '1' || stored === 'true';
}

function saveTilesUiState() {
  if (!state.tilesUi) return;
  localStorage.setItem(TILE_MODE_KEY, state.tilesUi.mode);
  localStorage.setItem(TILE_EXPANDED_KEY, JSON.stringify(Array.from(state.tilesUi.expandedIds)));
  localStorage.setItem(TILE_COLLAPSED_KEY, JSON.stringify(Array.from(state.tilesUi.collapsedIds)));
}

function isTileExpanded(streamId) {
  const id = String(streamId);
  if (!state.tilesUi) return true;
  if (state.tilesUi.mode === 'compact') {
    return state.tilesUi.expandedIds.has(id);
  }
  return !state.tilesUi.collapsedIds.has(id);
}

function setTileExpanded(streamId, expanded) {
  if (!state.tilesUi) return;
  const id = String(streamId);
  if (state.tilesUi.mode === 'compact') {
    if (expanded) {
      state.tilesUi.expandedIds.add(id);
    } else {
      state.tilesUi.expandedIds.delete(id);
    }
  } else {
    if (expanded) {
      state.tilesUi.collapsedIds.delete(id);
    } else {
      state.tilesUi.collapsedIds.add(id);
    }
  }
  saveTilesUiState();
  applyTilesUiState();
}

function setTilesMode(mode, opts) {
  if (!state.tilesUi) return;
  const next = normalizeTilesMode(mode);
  state.tilesUi.mode = next;
  if (!opts || opts.persist !== false) {
    saveTilesUiState();
  }
  applyTilesUiState();
  updateViewMenuSelection();
}

function applyTileUiState(tile) {
  if (!tile || !state.tilesUi) return;
  const id = tile.dataset.id;
  if (!id) return;
  const expanded = isTileExpanded(id);
  tile.classList.toggle('is-expanded', expanded);
  tile.classList.toggle('is-compact', !expanded);
  const toggleBtn = tile.querySelector('[data-action="tile-toggle"]');
  if (toggleBtn) {
    toggleBtn.setAttribute('aria-expanded', expanded ? 'true' : 'false');
    toggleBtn.textContent = expanded ? '⯆' : '⯈';
    toggleBtn.title = expanded ? 'Collapse' : 'Expand';
  }
  const details = tile.querySelector('.tile-details');
  if (details) {
    details.setAttribute('aria-hidden', expanded ? 'false' : 'true');
  }
}

function applyTilesUiState() {
  if (elements && elements.dashboardStreams) {
    elements.dashboardStreams.dataset.tilesMode = state.tilesUi.mode;
  }
  if (!elements || !elements.dashboardStreams || state.viewMode !== 'cards') return;
  $$('.tile').forEach(applyTileUiState);
}

const state = {
  streams: [],
  adapters: [],
  dvbAdapters: [],
  dvbAdaptersLoaded: false,
  settings: {},
  stats: {},
  adapterStatus: {},
  sessions: [],
  splitters: [],
  splitterStatus: {},
  splitterLinks: [],
  splitterAllow: [],
  splitterEditing: null,
  splitterEditingNew: false,
  splitterDirty: false,
  splitterLinkEditing: null,
  splitterAllowEditing: null,
  splitterTimer: null,
  buffers: [],
  bufferStatus: {},
  bufferInputs: [],
  bufferAllow: [],
  bufferEditing: null,
  bufferEditingNew: false,
  bufferDirty: false,
  bufferInputEditing: null,
  bufferAllowEditing: null,
  bufferTimer: null,
  users: [],
  accessLogEntries: [],
  auditEntries: [],
  token: localStorage.getItem('astra_token'),
  editing: null,
  streamIdAuto: false,
  adapterEditing: null,
  outputs: [],
  outputEditingIndex: null,
  transcodeOutputs: [],
  transcodeOutputEditingIndex: null,
  transcodeOutputMonitorIndex: null,
  transcodeWatchdogDefaults: null,
  inputs: [],
  mptsServices: [],
  mptsCa: [],
  inputEditingIndex: null,
  inputExtras: {},
  settingsSection: 'general',
  licenseLoaded: false,
  configRevisions: [],
  configEditorDirty: false,
  configEditorLoaded: false,
  generalMode: getStoredBool(SETTINGS_ADVANCED_KEY, false) ? 'advanced' : 'basic',
  // Компактный режим для карточек Settings -> General (визуально плотнее, на конфиг не влияет).
  generalCompact: getStoredBool(SETTINGS_DENSITY_KEY, false),
  generalDirty: false,
  generalSnapshot: '',
  generalCardOpen: {},
  generalSearchQuery: '',
  generalRendered: false,
  generalCards: [],
  generalSectionEls: {},
  generalSearchEls: [],
  generalObserver: null,
  generalActiveSection: '',
  aiApplyConfirmTarget: null,
  aiApplyConfirmPending: false,
  player: null,
  playerStreamId: null,
  playerMode: null,
  playerUrl: '',
  playerShareUrl: '',
  playerShareKind: 'play',
  playerToken: null,
  playerTriedVideoOnly: false,
  playerStartTimer: null,
  playerStarting: false,
  analyzeJobId: null,
  analyzePoll: null,
  analyzeStreamId: null,
  analyzeCopyText: '',
  statusTimer: null,
  adapterTimer: null,
  dvbTimer: null,
  adapterScanJobId: null,
  adapterScanPoll: null,
  adapterScanResults: null,
  currentView: 'streams',
  sessionTimer: null,
  accessLogTimer: null,
  logTimer: null,
  observabilityTimer: null,
  logCursor: 0,
  logEntries: [],
  logLevelFilter: 'all',
  logTextFilter: '',
  logStreamFilter: '',
  logPaused: false,
  logLimit: 500,
  sessionFilterText: '',
  sessionGroupBy: false,
  sessionLimit: 200,
  sessionPaused: false,
  accessLogCursor: 0,
  accessEventFilter: 'all',
  accessTextFilter: '',
  accessLimit: 200,
  accessPaused: false,
  auditLimit: 200,
  auditActionFilter: '',
  auditActorFilter: '',
  auditOkFilter: '',
  accessMode: 'access',
  streamSyncTimer: null,
  groups: [],
  groupEditing: null,
  groupIdAuto: false,
  servers: [],
  serverEditing: null,
  serverIdAuto: false,
  serverStatus: {},
  serverStatusTimer: null,
  softcams: [],
  softcamEditing: null,
  softcamIdAuto: false,
  userEditing: null,
  userMode: 'edit',
  activeAnalyzeId: null,
  aiChatJobId: null,
  aiChatPoll: null,
  aiChatPendingEl: null,
  aiChatBusy: false,
  aiChatPreviewUrls: [],
  viewMode: loadViewModeState(),
  themeMode: localStorage.getItem('astra.theme') || 'auto',
  tilesUi: loadTilesUiState(),
  showDisabledStreams: loadShowDisabledState(),
  dashboardNoticeTimer: null,
  streamIndex: {},
  streamTableRows: {},
  streamCompactRows: {},
};

const POLL_STATUS_MS = 5000;
const POLL_ADAPTER_MS = 5000;
const POLL_SESSION_MS = 10000;
const POLL_ACCESS_MS = 8000;
const POLL_LOG_MS = 8000;
const POLL_SPLITTER_MS = 10000;
const POLL_BUFFER_MS = 10000;
const POLL_SERVER_STATUS_MS = 60000;
const POLL_OBSERVABILITY_MS = 60000;

const $ = (sel, root = document) => root.querySelector(sel);
const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
const createEl = (tag, className, text) => {
  const el = document.createElement(tag);
  if (className) el.className = className;
  if (text !== undefined) el.textContent = text;
  return el;
};

const elements = {
  navLinks: $$('.nav-link'),
  views: $$('.view'),
  settingsMenu: $('#settings-menu'),
  settingsItems: $$('#settings-menu .settings-item'),
  observabilityRange: $('#obs-range'),
  observabilityScope: $('#obs-scope'),
  observabilityStream: $('#obs-stream'),
  observabilityStreamField: $('#obs-stream-field'),
  observabilityRefresh: $('#obs-refresh'),
  observabilitySummary: $('#obs-summary'),
  observabilityEmpty: $('#obs-empty'),
  observabilityHint: $('#obs-hint'),
  observabilityChartBitrate: $('#obs-chart-bitrate'),
  observabilityChartStreams: $('#obs-chart-streams'),
  observabilityChartSwitches: $('#obs-chart-switches'),
  observabilityLogs: $('#obs-logs'),
  observabilityAiSummary: $('#obs-ai-summary'),
  aiChatLog: $('#ai-chat-log'),
  aiChatInput: $('#ai-chat-input'),
  aiChatSend: $('#ai-chat-send'),
  aiChatStop: $('#ai-chat-stop'),
  aiChatClear: $('#ai-chat-clear'),
  aiChatStatus: $('#ai-chat-status'),
  aiChatFiles: $('#ai-chat-files'),
  aiChatFilesLabel: $('#ai-chat-files-label'),
  aiChatFilePreviews: $('#ai-chat-file-previews'),
  aiChatIncludeLogs: $('#ai-chat-logs'),
  aiChatCliStream: $('#ai-chat-cli-stream'),
  aiChatCliDvbls: $('#ai-chat-cli-dvbls'),
  aiChatCliAnalyze: $('#ai-chat-cli-analyze'),
  aiChatCliFemon: $('#ai-chat-cli-femon'),
  aiChatStreamId: $('#ai-chat-stream-id'),
  aiChatAnalyzeUrl: $('#ai-chat-analyze-url'),
  aiChatFemonUrl: $('#ai-chat-femon-url'),
  settingsGeneralRoot: $('#settings-general-root'),
  settingsGeneralSearch: $('#settings-general-search'),
  settingsGeneralMode: $('#settings-general-mode'),
  settingsGeneralDirty: $('#settings-general-dirty'),
  settingsGeneralNav: $('#settings-general-nav'),
  settingsGeneralNavSelect: $('#settings-general-nav-select'),
  settingsActionBar: $('#settings-action-bar'),
  settingsActionSave: $('#settings-action-save'),
  settingsActionCancel: $('#settings-action-cancel'),
  settingsActionReset: $('#settings-action-reset'),
  settingsActionStatus: $('#settings-action-status'),
  settingsShowSplitter: $('#settings-show-splitter'),
  settingsShowBuffer: $('#settings-show-buffer'),
  settingsShowAccess: $('#settings-show-access'),
  settingsShowEpg: $('#settings-show-epg'),
  settingsShowWebhook: $('#settings-show-webhook'),
  settingsShowLogLimits: $('#settings-show-log-limits'),
  settingsShowAccessLogLimits: $('#settings-show-access-log-limits'),
  settingsShowTools: $('#settings-show-tools'),
  settingsShowSecurityLimits: $('#settings-show-security-limits'),
  settingsShowStreamDefaults: $('#settings-show-stream-defaults'),
  settingsShowAdvanced: $('#settings-show-advanced'),
  casDefault: $('#cas-default'),
  btnApplyCas: $('#btn-apply-cas'),
  licenseMeta: $('#license-meta'),
  licenseText: $('#license-text'),
  aiApplyConfirmOverlay: $('#ai-apply-confirm-overlay'),
  aiApplyConfirmClose: $('#ai-apply-confirm-close'),
  aiApplyConfirmCancel: $('#ai-apply-confirm-cancel'),
  aiApplyConfirmOk: $('#ai-apply-confirm-ok'),
  viewMenu: $('#view-menu'),
  viewOptions: $$('#view-menu .view-option'),
  searchInput: $('#search-input'),
  dashboardStreams: $('#dashboard-streams'),
  streamViews: $('#stream-views'),
  streamTable: $('#stream-table'),
  streamTableBody: $('#stream-table-body'),
  streamCompact: $('#stream-compact'),
  splitterList: $('#splitter-list'),
  splitterListEmpty: $('#splitter-list-empty'),
  splitterEditor: $('#splitter-editor'),
  splitterForm: $('#splitter-form'),
  splitterTitle: $('#splitter-title'),
  splitterState: $('#splitter-state'),
  splitterRuntime: $('#splitter-runtime'),
  splitterEnabled: $('#splitter-enabled'),
  splitterId: $('#splitter-id'),
  splitterName: $('#splitter-name'),
  splitterPort: $('#splitter-port'),
  splitterInInterface: $('#splitter-in-interface'),
  splitterOutInterface: $('#splitter-out-interface'),
  splitterLogtype: $('#splitter-logtype'),
  splitterLogpath: $('#splitter-logpath'),
  splitterConfigPath: $('#splitter-config-path'),
  splitterPreset: $('#splitter-preset'),
  splitterPresetApply: $('#splitter-preset-apply'),
  splitterUrlTemplate: $('#splitter-url-template'),
  splitterSave: $('#splitter-save'),
  splitterError: $('#splitter-error'),
  splitterStart: $('#splitter-start'),
  splitterStop: $('#splitter-stop'),
  splitterRestart: $('#splitter-restart'),
  splitterApply: $('#splitter-apply'),
  splitterConfig: $('#splitter-config'),
  splitterNew: $('#splitter-new'),
  splitterAllowNew: $('#splitter-allow-new'),
  splitterLinkNew: $('#splitter-link-new'),
  splitterAllowTable: $('#splitter-allow-table'),
  splitterAllowEmpty: $('#splitter-allow-empty'),
  splitterLinkTable: $('#splitter-link-table'),
  splitterLinkEmpty: $('#splitter-link-empty'),
  splitterConfigOverlay: $('#splitter-config-overlay'),
  configErrorOverlay: $('#config-error-overlay'),
  configErrorTitle: $('#config-error-title'),
  configErrorMeta: $('#config-error-meta'),
  configErrorBody: $('#config-error-body'),
  configErrorClose: $('#config-error-close'),
  configErrorDone: $('#config-error-done'),
  configErrorCopy: $('#config-error-copy'),
  splitterConfigPreview: $('#splitter-config-preview'),
  splitterConfigError: $('#splitter-config-error'),
  splitterConfigClose: $('#splitter-config-close'),
  splitterConfigCopy: $('#splitter-config-copy'),
  splitterConfigDismiss: $('#splitter-config-dismiss'),
  bufferList: $('#buffer-list'),
  bufferListEmpty: $('#buffer-list-empty'),
  bufferEditor: $('#buffer-editor'),
  bufferForm: $('#buffer-form'),
  bufferTitle: $('#buffer-title'),
  bufferState: $('#buffer-state'),
  bufferEnabled: $('#buffer-enabled'),
  bufferId: $('#buffer-id'),
  bufferName: $('#buffer-name'),
  bufferPath: $('#buffer-path'),
  bufferOutputUrl: $('#buffer-output-url'),
  bufferCopyUrl: $('#buffer-copy-url'),
  bufferPreset: $('#buffer-preset'),
  bufferPresetApply: $('#buffer-preset-apply'),
  bufferBackupType: $('#buffer-backup-type'),
  bufferNoDataTimeout: $('#buffer-no-data-timeout'),
  bufferBackupStartDelay: $('#buffer-backup-start-delay'),
  bufferBackupReturnDelay: $('#buffer-backup-return-delay'),
  bufferBackupProbeInterval: $('#buffer-backup-probe-interval'),
  bufferBufferingSec: $('#buffer-buffering-sec'),
  bufferBandwidthKbps: $('#buffer-bandwidth-kbps'),
  bufferClientStartOffset: $('#buffer-client-start-offset'),
  bufferMaxClientLag: $('#buffer-max-client-lag'),
  bufferSmartEnabled: $('#buffer-smart-enabled'),
  bufferSmartTargetDelay: $('#buffer-smart-target-delay'),
  bufferSmartLookback: $('#buffer-smart-lookback'),
  bufferSmartWaitReady: $('#buffer-smart-wait-ready'),
  bufferSmartMaxLead: $('#buffer-smart-max-lead'),
  bufferSmartRequirePatPmt: $('#buffer-smart-require-patpmt'),
  bufferSmartRequireKeyframe: $('#buffer-smart-require-keyframe'),
  bufferSmartRequirePcr: $('#buffer-smart-require-pcr'),
  bufferKeyframeDetect: $('#buffer-keyframe-detect'),
  bufferAvAlignEnabled: $('#buffer-av-align-enabled'),
  bufferAvMaxDesync: $('#buffer-av-max-desync'),
  bufferParamsetRequired: $('#buffer-paramset-required'),
  bufferStartDebug: $('#buffer-start-debug'),
  bufferTsResync: $('#buffer-ts-resync'),
  bufferTsDrop: $('#buffer-ts-drop'),
  bufferTsRewrite: $('#buffer-ts-rewrite'),
  bufferPacingMode: $('#buffer-pacing-mode'),
  bufferSave: $('#buffer-save'),
  bufferDelete: $('#buffer-delete'),
  bufferNew: $('#buffer-new'),
  bufferReload: $('#buffer-reload'),
  bufferRestartReader: $('#buffer-restart-reader'),
  bufferInputNew: $('#buffer-input-new'),
  bufferInputTable: $('#buffer-input-table'),
  bufferInputEmpty: $('#buffer-input-empty'),
  bufferAllowNew: $('#buffer-allow-new'),
  bufferAllowTable: $('#buffer-allow-table'),
  bufferAllowEmpty: $('#buffer-allow-empty'),
  bufferDiagnostics: $('#buffer-diagnostics'),
  sessionTotal: $('#session-total'),
  sessionTable: $('#session-table'),
  accessTotal: $('#access-total'),
  accessTable: $('#access-table'),
  usersTable: $('#users-table'),
  usersEmpty: $('#users-empty'),
  btnUserNew: $('#btn-user-new'),
  userOverlay: $('#user-overlay'),
  userForm: $('#user-form'),
  userTitle: $('#user-title'),
  userClose: $('#user-close'),
  userCancel: $('#user-cancel'),
  userError: $('#user-error'),
  userUsername: $('#user-username'),
  userPassword: $('#user-password'),
  userAdmin: $('#user-admin'),
  userEnabled: $('#user-enabled'),
  userComment: $('#user-comment'),
  userFieldUsername: $('#user-field-username'),
  userFieldAdmin: $('#user-field-admin'),
  userFieldEnabled: $('#user-field-enabled'),
  userFieldComment: $('#user-field-comment'),
  configEditor: $('#config-editor'),
  configEditMode: $('#config-edit-mode'),
  btnConfigLoad: $('#btn-config-load'),
  btnConfigSave: $('#btn-config-save'),
  configEditHint: $('#config-edit-hint'),
  configHistoryTable: $('#config-history-table'),
  configActiveRevision: $('#config-active-revision'),
  configLkgRevision: $('#config-lkg-revision'),
  btnConfigRefresh: $('#btn-config-refresh'),
  btnConfigDeleteAll: $('#btn-config-delete-all'),
  logOutput: $('#log-output'),
  logPause: $('#log-pause'),
  logClear: $('#log-clear'),
  logLevel: $('#log-level-filter'),
  logFilter: $('#log-text-filter'),
  logStream: $('#log-stream-filter'),
  logLimit: $('#log-limit'),
  logCount: $('#log-count'),
  sessionFilter: $('#session-filter'),
  sessionGroup: $('#session-group'),
  sessionLimit: $('#session-limit'),
  sessionPause: $('#session-pause'),
  sessionRefresh: $('#session-refresh'),
  accessEvent: $('#access-event-filter'),
  accessFilter: $('#access-text-filter'),
  accessLimit: $('#access-limit'),
  accessCount: $('#access-count'),
  accessPause: $('#access-pause'),
  accessClear: $('#access-clear'),
  accessMode: $('#access-mode'),
  accessControls: $('#access-controls'),
  auditControls: $('#audit-controls'),
  auditActionFilter: $('#audit-action-filter'),
  auditActorFilter: $('#audit-actor-filter'),
  auditOkFilter: $('#audit-ok-filter'),
  auditLimit: $('#audit-limit'),
  auditRefresh: $('#audit-refresh'),
  auditCount: $('#audit-count'),
  auditAiOnly: $('#audit-ai-only'),
  auditTable: $('#audit-table'),
  groupNew: $('#group-new'),
  groupTable: $('#group-table'),
  groupEmpty: $('#group-empty'),
  groupOverlay: $('#group-overlay'),
  groupTitle: $('#group-title'),
  groupForm: $('#group-form'),
  groupId: $('#group-id'),
  groupName: $('#group-name'),
  groupSave: $('#group-save'),
  groupCancel: $('#group-cancel'),
  groupClose: $('#group-close'),
  groupError: $('#group-error'),
  softcamNew: $('#softcam-new'),
  softcamTable: $('#softcam-table'),
  softcamEmpty: $('#softcam-empty'),
  softcamOverlay: $('#softcam-overlay'),
  softcamTitle: $('#softcam-title'),
  softcamForm: $('#softcam-form'),
  softcamEnabled: $('#softcam-enabled'),
  softcamId: $('#softcam-id'),
  softcamName: $('#softcam-name'),
  softcamType: $('#softcam-type'),
  softcamHost: $('#softcam-host'),
  softcamPort: $('#softcam-port'),
  softcamUser: $('#softcam-user'),
  softcamPass: $('#softcam-pass'),
  softcamPassHint: $('#softcam-pass-hint'),
  softcamDisableEmm: $('#softcam-disable-emm'),
  softcamSplitCam: $('#softcam-split-cam'),
  softcamShift: $('#softcam-shift'),
  softcamComment: $('#softcam-comment'),
  softcamSave: $('#softcam-save'),
  softcamCancel: $('#softcam-cancel'),
  softcamClose: $('#softcam-close'),
  softcamError: $('#softcam-error'),
  serverNew: $('#server-new'),
  serverTable: $('#server-table'),
  serverEmpty: $('#server-empty'),
  serverOverlay: $('#server-overlay'),
  serverTitle: $('#server-title'),
  serverForm: $('#server-form'),
  serverEnabled: $('#server-enabled'),
  serverId: $('#server-id'),
  serverName: $('#server-name'),
  serverType: $('#server-type'),
  serverHost: $('#server-host'),
  serverPort: $('#server-port'),
  serverLogin: $('#server-login'),
  serverPassword: $('#server-password'),
  serverPasswordHint: $('#server-password-hint'),
  serverSave: $('#server-save'),
  serverCancel: $('#server-cancel'),
  serverClose: $('#server-close'),
  serverTest: $('#server-test'),
  serverError: $('#server-error'),
  settingsEpgInterval: $('#settings-epg-interval'),
  settingsEventRequest: $('#settings-event-request'),
  settingsMonitorAnalyzeMax: $('#settings-monitor-analyze-max'),
  settingsPreviewMaxSessions: $('#settings-preview-max-sessions'),
  settingsPreviewIdleTimeout: $('#settings-preview-idle-timeout'),
  settingsPreviewTokenTtl: $('#settings-preview-token-ttl'),
  settingsLogMaxEntries: $('#settings-log-max-entries'),
  settingsLogRetentionSec: $('#settings-log-retention-sec'),
  settingsAccessLogMaxEntries: $('#settings-access-log-max-entries'),
  settingsAccessLogRetentionSec: $('#settings-access-log-retention-sec'),
  settingsObservabilityEnabled: $('#settings-observability-enabled'),
  settingsObservabilityLogsDays: $('#settings-observability-logs-days'),
  settingsObservabilityMetricsDays: $('#settings-observability-metrics-days'),
  settingsObservabilityRollup: $('#settings-observability-rollup'),
  settingsObservabilityOnDemand: $('#settings-observability-on-demand'),
  settingsTelegramEnabled: $('#settings-telegram-enabled'),
  settingsTelegramLevel: $('#settings-telegram-level'),
  settingsTelegramToken: $('#settings-telegram-token'),
  settingsTelegramTokenHint: $('#settings-telegram-token-hint'),
  settingsTelegramChatId: $('#settings-telegram-chat-id'),
  settingsTelegramTest: $('#settings-telegram-test'),
  settingsTelegramBackupEnabled: $('#settings-telegram-backup-enabled'),
  settingsTelegramBackupSchedule: $('#settings-telegram-backup-schedule'),
  settingsTelegramBackupTime: $('#settings-telegram-backup-time'),
  settingsTelegramBackupWeekday: $('#settings-telegram-backup-weekday'),
  settingsTelegramBackupMonthday: $('#settings-telegram-backup-monthday'),
  settingsTelegramBackupSecrets: $('#settings-telegram-backup-secrets'),
  settingsTelegramBackupWeekdayField: $('#settings-telegram-backup-weekday-field'),
  settingsTelegramBackupMonthdayField: $('#settings-telegram-backup-monthday-field'),
  settingsTelegramBackupNow: $('#settings-telegram-backup-now'),
  settingsTelegramSummaryEnabled: $('#settings-telegram-summary-enabled'),
  settingsTelegramSummarySchedule: $('#settings-telegram-summary-schedule'),
  settingsTelegramSummaryTime: $('#settings-telegram-summary-time'),
  settingsTelegramSummaryWeekday: $('#settings-telegram-summary-weekday'),
  settingsTelegramSummaryMonthday: $('#settings-telegram-summary-monthday'),
  settingsTelegramSummaryCharts: $('#settings-telegram-summary-charts'),
  settingsTelegramSummaryWeekdayField: $('#settings-telegram-summary-weekday-field'),
  settingsTelegramSummaryMonthdayField: $('#settings-telegram-summary-monthday-field'),
  settingsTelegramSummaryNow: $('#settings-telegram-summary-now'),
  settingsAiEnabled: $('#settings-ai-enabled'),
  settingsAiApiKey: $('#settings-ai-api-key'),
  settingsAiApiKeyHint: $('#settings-ai-api-key-hint'),
  settingsAiApiBase: $('#settings-ai-api-base'),
  settingsAiModel: $('#settings-ai-model'),
  settingsAiModelHint: $('#settings-ai-model-hint'),
  settingsAiChartMode: $('#settings-ai-chart-mode'),
  settingsAiMaxTokens: $('#settings-ai-max-tokens'),
  settingsAiTemperature: $('#settings-ai-temperature'),
  settingsAiAllowedChats: $('#settings-ai-allowed-chats'),
  settingsAiStore: $('#settings-ai-store'),
  settingsAiAllowApply: $('#settings-ai-allow-apply'),
  settingsWatchdogEnabled: $('#settings-watchdog-enabled'),
  settingsWatchdogCpu: $('#settings-watchdog-cpu'),
  settingsWatchdogRssMb: $('#settings-watchdog-rss-mb'),
  settingsWatchdogRssPct: $('#settings-watchdog-rss-pct'),
  settingsWatchdogInterval: $('#settings-watchdog-interval'),
  settingsWatchdogStrikes: $('#settings-watchdog-strikes'),
  settingsWatchdogUptime: $('#settings-watchdog-uptime'),
  settingsInfluxEnabled: $('#settings-influx-enabled'),
  settingsInfluxUrl: $('#settings-influx-url'),
  settingsInfluxOrg: $('#settings-influx-org'),
  settingsInfluxBucket: $('#settings-influx-bucket'),
  settingsInfluxToken: $('#settings-influx-token'),
  settingsInfluxInstance: $('#settings-influx-instance'),
  settingsInfluxMeasurement: $('#settings-influx-measurement'),
  settingsInfluxInterval: $('#settings-influx-interval'),
  settingsFfmpegPath: $('#settings-ffmpeg-path'),
  settingsFfprobePath: $('#settings-ffprobe-path'),
  settingsHttpsBridgeEnabled: $('#settings-https-bridge-enabled'),
  settingsHttpCsrf: $('#settings-http-csrf'),
  settingsAuthSessionTtl: $('#settings-auth-session-ttl'),
  settingsLoginRateLimit: $('#settings-login-rate-limit'),
  settingsLoginRateWindow: $('#settings-login-rate-window'),
  settingsDefaultNoDataTimeout: $('#settings-default-no-data-timeout'),
  settingsDefaultProbeInterval: $('#settings-default-probe-interval'),
  settingsDefaultStableOk: $('#settings-default-stable-ok'),
  settingsDefaultBackupInitial: $('#settings-default-backup-initial'),
  settingsDefaultBackupStart: $('#settings-default-backup-start'),
  settingsDefaultBackupReturn: $('#settings-default-backup-return'),
  settingsDefaultBackupStop: $('#settings-default-backup-stop'),
  settingsDefaultBackupWarmMax: $('#settings-default-backup-warm-max'),
  settingsDefaultHttpKeepActive: $('#settings-default-http-keep-active'),
  passwordMinLength: $('#password-min-length'),
  passwordRequireLetter: $('#password-require-letter'),
  passwordRequireNumber: $('#password-require-number'),
  passwordRequireSymbol: $('#password-require-symbol'),
  passwordRequireMixed: $('#password-require-mixed'),
  passwordDisallowUsername: $('#password-disallow-username'),
  btnApplyPasswordPolicy: $('#btn-apply-password-policy'),
  status: $('#status'),
  loginOverlay: $('#login-overlay'),
  loginForm: $('#login-form'),
  loginError: $('#login-error'),
  loginUser: $('#login-user'),
  loginPass: $('#login-pass'),
  editorOverlay: $('#editor-overlay'),
  editorTitle: $('#editor-title'),
  editorClose: $('#editor-close'),
  editorCancel: $('#editor-cancel'),
  editorError: $('#editor-error'),
  tabbars: $$('.tabbar'),
  tabs: $$('.tab'),
  tabContents: $$('.tab-content'),
  streamForm: $('#stream-form'),
  streamId: $('#stream-id'),
  streamName: $('#stream-name'),
  streamType: $('#stream-type'),
  streamEnabled: $('#stream-enabled'),
  streamMpts: $('#stream-mpts'),
  streamDesc: $('#stream-desc'),
  streamGroup: $('#stream-group'),
  streamGroupList: $('#stream-group-list'),
  streamServiceType: $('#stream-service-type'),
  streamServiceCodepage: $('#stream-service-codepage'),
  streamServiceProvider: $('#stream-service-provider'),
  streamServiceName: $('#stream-service-name'),
  streamServiceHbbtv: $('#stream-service-hbbtv'),
  streamServiceCas: $('#stream-service-cas'),
  streamSetPnr: $('#stream-set-pnr'),
  streamSetTsid: $('#stream-set-tsid'),
  streamMap: $('#stream-map'),
  streamFilter: $('#stream-filter'),
  streamFilterExclude: $('#stream-filter-exclude'),
  streamEpgId: $('#stream-epg-id'),
  streamEpgFormat: $('#stream-epg-format'),
  streamEpgDestination: $('#stream-epg-destination'),
  streamEpgCodepage: $('#stream-epg-codepage'),
  mptsCountry: $('#mpts-country'),
  mptsUtcOffset: $('#mpts-utc-offset'),
  mptsDstTimeOfChange: $('#mpts-dst-time-of-change'),
  mptsDstNextOffset: $('#mpts-dst-next-offset'),
  mptsNetworkId: $('#mpts-network-id'),
  mptsNetworkName: $('#mpts-network-name'),
  mptsProviderName: $('#mpts-provider-name'),
  mptsCodepage: $('#mpts-codepage'),
  mptsTsid: $('#mpts-tsid'),
  mptsOnid: $('#mpts-onid'),
  mptsDelivery: $('#mpts-delivery'),
  mptsFrequency: $('#mpts-frequency'),
  mptsSymbolrate: $('#mpts-symbolrate'),
  mptsBandwidth: $('#mpts-bandwidth'),
  mptsOrbitalPosition: $('#mpts-orbital-position'),
  mptsPolarization: $('#mpts-polarization'),
  mptsRolloff: $('#mpts-rolloff'),
  mptsFec: $('#mpts-fec'),
  mptsModulation: $('#mpts-modulation'),
  mptsNetworkSearch: $('#mpts-network-search'),
  mptsLcnTag: $('#mpts-lcn-tag'),
  mptsLcnTags: $('#mpts-lcn-tags'),
  mptsLcnTagsWarning: $('#mpts-lcn-tags-warning'),
  mptsLcnVersion: $('#mpts-lcn-version'),
  mptsLcnVersionWarning: $('#mpts-lcn-version-warning'),
  mptsDeliveryWarning: $('#mpts-delivery-warning'),
  mptsSiInterval: $('#mpts-si-interval'),
  mptsTargetBitrate: $('#mpts-target-bitrate'),
  mptsAutoProbe: $('#mpts-auto-probe'),
  mptsAutoProbeDuration: $('#mpts-auto-probe-duration'),
  mptsPcrRestamp: $('#mpts-pcr-restamp'),
  mptsPcrSmoothing: $('#mpts-pcr-smoothing'),
  mptsPcrSmoothAlpha: $('#mpts-pcr-smooth-alpha'),
  mptsPcrSmoothMax: $('#mpts-pcr-smooth-max'),
  mptsPatVersion: $('#mpts-pat-version'),
  mptsNitVersion: $('#mpts-nit-version'),
  mptsCatVersion: $('#mpts-cat-version'),
  mptsSdtVersion: $('#mpts-sdt-version'),
  mptsDisableAutoremap: $('#mpts-disable-autoremap'),
  mptsPassNit: $('#mpts-pass-nit'),
  mptsPassSdt: $('#mpts-pass-sdt'),
  mptsPassEit: $('#mpts-pass-eit'),
  mptsPassCat: $('#mpts-pass-cat'),
  mptsPassTdt: $('#mpts-pass-tdt'),
  mptsDisableTot: $('#mpts-disable-tot'),
  mptsEitSource: $('#mpts-eit-source'),
  mptsEitTableIds: $('#mpts-eit-table-ids'),
  mptsCatSource: $('#mpts-cat-source'),
  mptsStrictPnr: $('#mpts-strict-pnr'),
  mptsSptsOnly: $('#mpts-spts-only'),
  mptsPassWarning: $('#mpts-pass-warning'),
  mptsAutoremapWarning: $('#mpts-autoremap-warning'),
  mptsPnrWarning: $('#mpts-pnr-warning'),
  mptsPnrMissing: $('#mpts-pnr-missing'),
  mptsDupInputWarning: $('#mpts-dup-input-warning'),
  mptsSptsWarning: $('#mpts-spts-warning'),
  mptsManual: $('#mpts-manual'),
  mptsEnabledStatus: $('#mpts-enabled-status'),
  btnMptsManualToggle: $('#btn-mpts-manual-toggle'),
  btnMptsEnable: $('#btn-mpts-enable'),
  mptsCallout: $('#mpts-callout'),
  mptsCalloutText: $('#mpts-callout-text'),
  btnMptsEnableCallout: $('#btn-mpts-enable-callout'),
  mptsRuntime: $('#mpts-runtime'),
  mptsRuntimeBitrate: $('#mpts-runtime-bitrate'),
  mptsRuntimeNull: $('#mpts-runtime-null'),
  mptsRuntimePsi: $('#mpts-runtime-psi'),
  mptsRuntimeNote: $('#mpts-runtime-note'),
  btnMptsConvertInputs: $('#btn-mpts-convert-inputs'),
  btnMptsAddStreams: $('#btn-mpts-add-streams'),
  mptsStreamsOverlay: $('#mpts-streams-overlay'),
  mptsStreamsClose: $('#mpts-streams-close'),
  mptsStreamsCancel: $('#mpts-streams-cancel'),
  mptsStreamsAdd: $('#mpts-streams-add'),
  mptsStreamsSearch: $('#mpts-streams-search'),
  mptsStreamsList: $('#mpts-streams-list'),
  streamTimeout: $('#stream-timeout'),
  streamHttpKeep: $('#stream-http-keep-active'),
  streamNoSdt: $('#stream-no-sdt'),
  streamNoEit: $('#stream-no-eit'),
  streamPassSdt: $('#stream-pass-sdt'),
  streamPassEit: $('#stream-pass-eit'),
  streamNoReload: $('#stream-no-reload'),
  streamBackupType: $('#stream-backup-type'),
  streamBackupWarmMax: $('#stream-backup-warm-max'),
  streamBackupInitialDelay: $('#stream-backup-initial-delay'),
  streamBackupStartDelay: $('#stream-backup-start-delay'),
  streamBackupReturnDelay: $('#stream-backup-return-delay'),
  streamBackupStopInactiveSec: $('#stream-backup-stop-inactive-sec'),
  streamBackupWarmMaxField: $('.backup-warm-max'),
  streamBackupReturnDelayField: $('.backup-return-delay'),
  streamBackupStopInactiveField: $('.backup-stop-inactive'),
  streamStableOkSec: $('#stream-stable-ok-sec'),
  streamNoDataTimeoutSec: $('#stream-no-data-timeout-sec'),
  streamProbeIntervalSec: $('#stream-probe-interval-sec'),
  streamAuthEnabled: $('#stream-auth-enabled'),
  streamOnPlay: $('#stream-on-play'),
  streamOnPublish: $('#stream-on-publish'),
  streamSessionKeys: $('#stream-session-keys'),
  streamTranscodeEngine: $('#stream-transcode-engine'),
  streamTranscodeGpuDevice: $('#stream-transcode-gpu-device'),
  streamTranscodeFfmpegPath: $('#stream-transcode-ffmpeg-path'),
  streamTranscodeLogFile: $('#stream-transcode-log-file'),
  streamTranscodeLogMain: $('#stream-transcode-log-main'),
  streamTranscodeProcessPerOutput: $('#stream-transcode-process-per-output'),
  streamTranscodeSeamlessUdpProxy: $('#stream-transcode-seamless-udp-proxy'),
  streamTranscodePreset: $('#stream-transcode-preset'),
  streamTranscodePresetApply: $('#stream-transcode-preset-apply'),
  streamTranscodeInputUrl: $('#stream-transcode-input-url'),
  streamTranscodeStatus: $('#stream-transcode-status'),
  streamTranscodeWorkers: $('#stream-transcode-workers'),
  streamTranscodeGlobalArgs: $('#stream-transcode-global-args'),
  streamTranscodeDecoderArgs: $('#stream-transcode-decoder-args'),
  streamTranscodeCommonArgs: $('#stream-transcode-common-args'),
  streamTranscodeInputProbeUdp: $('#stream-transcode-input-probe-udp'),
  streamTranscodeInputProbeRestart: $('#stream-transcode-input-probe-restart'),
  streamTranscodeWarmup: $('#stream-transcode-warmup'),
  streamTranscodeRestart: $('#stream-transcode-restart'),
  streamTranscodeStderr: $('#stream-transcode-stderr'),
  transcodeOutputList: $('#transcode-output-list'),
  btnAddTranscodeOutput: $('#btn-add-transcode-output'),
  transcodeOutputOverlay: $('#transcode-output-overlay'),
  transcodeOutputForm: $('#transcode-output-form'),
  transcodeOutputPreset: $('#transcode-output-preset'),
  transcodeOutputClose: $('#transcode-output-close'),
  transcodeOutputCancel: $('#transcode-output-cancel'),
  transcodeOutputName: $('#transcode-output-name'),
  transcodeOutputUrl: $('#transcode-output-url'),
  transcodeOutputVf: $('#transcode-output-vf'),
  transcodeOutputVcodec: $('#transcode-output-vcodec'),
  transcodeOutputRepeatHeaders: $('#transcode-output-repeat-headers'),
  transcodeOutputVArgs: $('#transcode-output-v-args'),
  transcodeOutputAcodec: $('#transcode-output-acodec'),
  transcodeOutputAArgs: $('#transcode-output-a-args'),
  transcodeOutputFormatArgs: $('#transcode-output-format-args'),
  transcodeOutputMetadata: $('#transcode-output-metadata'),
  transcodeOutputError: $('#transcode-output-error'),
  transcodeMonitorOverlay: $('#transcode-monitor-overlay'),
  transcodeMonitorForm: $('#transcode-monitor-form'),
  transcodeMonitorTitle: $('#transcode-monitor-title'),
  transcodeMonitorTarget: $('#transcode-monitor-target'),
  transcodeMonitorProbeTarget: $('#transcode-monitor-probe-target'),
  transcodeMonitorRestartDelay: $('#transcode-monitor-restart-delay'),
  transcodeMonitorNoProgress: $('#transcode-monitor-no-progress'),
  transcodeMonitorMaxErrors: $('#transcode-monitor-max-errors'),
  transcodeMonitorDesyncMs: $('#transcode-monitor-desync-ms'),
  transcodeMonitorDesyncCount: $('#transcode-monitor-desync-count'),
  transcodeMonitorMaxRestarts: $('#transcode-monitor-max-restarts'),
  transcodeMonitorEngine: $('#transcode-monitor-engine'),
  transcodeMonitorProbeInterval: $('#transcode-monitor-probe-interval'),
  transcodeMonitorProbeDuration: $('#transcode-monitor-probe-duration'),
  transcodeMonitorProbeTimeout: $('#transcode-monitor-probe-timeout'),
  transcodeMonitorProbeFail: $('#transcode-monitor-probe-fail'),
  transcodeMonitorLowEnabled: $('#transcode-monitor-low-enabled'),
  transcodeMonitorLowMin: $('#transcode-monitor-low-min'),
  transcodeMonitorLowHold: $('#transcode-monitor-low-hold'),
  transcodeMonitorCooldown: $('#transcode-monitor-cooldown'),
  transcodeMonitorError: $('#transcode-monitor-error'),
  transcodeMonitorClose: $('#transcode-monitor-close'),
  transcodeMonitorCancel: $('#transcode-monitor-cancel'),
  streamInputBlock: $('#stream-input-block'),
  inputList: $('#input-list'),
  inputPreset: $('#input-preset'),
  inputPresetApply: $('#input-preset-apply'),
  outputList: $('#output-list'),
  btnAddInput: $('#btn-add-input'),
  btnAddMptsService: $('#btn-add-mpts-service'),
  btnMptsProbe: $('#btn-mpts-probe'),
  mptsServiceList: $('#mpts-service-list'),
  btnAddMptsCa: $('#btn-add-mpts-ca'),
  mptsCaList: $('#mpts-ca-list'),
  mptsBulkPnrStart: $('#mpts-bulk-pnr-start'),
  mptsBulkPnrStep: $('#mpts-bulk-pnr-step'),
  mptsBulkLcnStart: $('#mpts-bulk-lcn-start'),
  mptsBulkLcnStep: $('#mpts-bulk-lcn-step'),
  mptsBulkProvider: $('#mpts-bulk-provider'),
  mptsBulkServiceType: $('#mpts-bulk-service-type'),
  btnMptsBulkApply: $('#btn-mpts-bulk-apply'),
  btnAddOutput: $('#btn-add-output'),
  btnApplyStream: $('#btn-apply'),
  btnDelete: $('#btn-delete'),
  btnClone: $('#btn-clone'),
  btnAnalyze: $('#btn-analyze'),
  outputOverlay: $('#output-overlay'),
  outputForm: $('#output-form'),
  outputClose: $('#output-close'),
  outputCancel: $('#output-cancel'),
  outputPreset: $('#output-preset'),
  outputPresetApply: $('#output-preset-apply'),
  outputType: $('#output-type'),
  outputBiss: $('#output-biss'),
  outputHttpMode: $('#output-http-mode'),
  outputHttpHost: $('#output-http-host'),
  outputHttpPort: $('#output-http-port'),
  outputHttpPath: $('#output-http-path'),
  outputHttpBuffer: $('#output-http-buffer'),
  outputHttpBufferFill: $('#output-http-buffer-fill'),
  outputHttpKeep: $('#output-http-keep'),
  outputHttpSctp: $('#output-http-sctp'),
  outputHlsPath: $('#output-hls-path'),
  outputHlsBase: $('#output-hls-base'),
  outputHlsPlaylist: $('#output-hls-playlist'),
  outputHlsPrefix: $('#output-hls-prefix'),
  outputHlsTarget: $('#output-hls-target'),
  outputHlsWindow: $('#output-hls-window'),
  outputHlsCleanup: $('#output-hls-cleanup'),
  outputHlsWall: $('#output-hls-wall'),
  outputHlsNaming: $('#output-hls-naming'),
  outputHlsRound: $('#output-hls-round'),
  outputHlsTsExtension: $('#output-hls-ts-extension'),
  outputHlsPassData: $('#output-hls-pass-data'),
  outputUdpAddr: $('#output-udp-addr'),
  outputUdpPort: $('#output-udp-port'),
  outputUdpTtl: $('#output-udp-ttl'),
  outputUdpLocal: $('#output-udp-local'),
  outputUdpSocket: $('#output-udp-socket'),
  outputUdpSync: $('#output-udp-sync'),
  outputUdpCbr: $('#output-udp-cbr'),
  outputUdpAudioFixBlock: $('#output-udp-audio-fix'),
  outputUdpAudioFixEnabled: $('#output-udp-audio-fix-enabled'),
  outputUdpAudioFixForce: $('#output-udp-audio-fix-force'),
  outputUdpAudioFixMode: $('#output-udp-audio-fix-mode'),
  outputUdpAudioFixBitrate: $('#output-udp-audio-fix-bitrate'),
  outputUdpAudioFixSampleRate: $('#output-udp-audio-fix-sr'),
  outputUdpAudioFixChannels: $('#output-udp-audio-fix-ch'),
  outputUdpAudioFixProfile: $('#output-udp-audio-fix-profile'),
  outputUdpAudioFixAsync: $('#output-udp-audio-fix-async'),
  outputUdpAudioFixSilence: $('#output-udp-audio-fix-silence'),
  outputUdpAudioFixInterval: $('#output-udp-audio-fix-interval'),
  outputUdpAudioFixDuration: $('#output-udp-audio-fix-duration'),
  outputUdpAudioFixHold: $('#output-udp-audio-fix-hold'),
  outputUdpAudioFixCooldown: $('#output-udp-audio-fix-cooldown'),
  outputSrtUrl: $('#output-srt-url'),
  outputSrtBridgePort: $('#output-srt-bridge-port'),
  outputSrtBridgeAddr: $('#output-srt-bridge-addr'),
  outputSrtBridgeLocaladdr: $('#output-srt-bridge-localaddr'),
  outputSrtBridgePktSize: $('#output-srt-bridge-pkt-size'),
  outputSrtBridgeSocket: $('#output-srt-bridge-socket'),
  outputSrtBridgeTtl: $('#output-srt-bridge-ttl'),
  outputSrtBridgeBin: $('#output-srt-bridge-bin'),
  outputSrtBridgeLog: $('#output-srt-bridge-log'),
  outputSrtBridgeInputArgs: $('#output-srt-bridge-input-args'),
  outputSrtBridgeOutputArgs: $('#output-srt-bridge-output-args'),
  outputNpHost: $('#output-np-host'),
  outputNpPort: $('#output-np-port'),
  outputNpPath: $('#output-np-path'),
  outputNpTimeout: $('#output-np-timeout'),
  outputNpBuffer: $('#output-np-buffer'),
  outputNpBufferFill: $('#output-np-buffer-fill'),
  outputNpSctp: $('#output-np-sctp'),
  outputFileName: $('#output-file-name'),
  outputFileBuffer: $('#output-file-buffer'),
  outputFileM2ts: $('#output-file-m2ts'),
  outputFileAio: $('#output-file-aio'),
  outputFileDirectio: $('#output-file-directio'),
  inputOverlay: $('#input-overlay'),
  splitterLinkOverlay: $('#splitter-link-overlay'),
  splitterLinkForm: $('#splitter-link-form'),
  splitterLinkClose: $('#splitter-link-close'),
  splitterLinkCancel: $('#splitter-link-cancel'),
  splitterLinkError: $('#splitter-link-error'),
  splitterLinkEnabled: $('#splitter-link-enabled'),
  splitterLinkUrl: $('#splitter-link-url'),
  splitterLinkBandwidth: $('#splitter-link-bandwidth'),
  splitterLinkBuffering: $('#splitter-link-buffering'),
  splitterLinkSave: $('#splitter-link-save'),
  splitterAllowOverlay: $('#splitter-allow-overlay'),
  splitterAllowForm: $('#splitter-allow-form'),
  splitterAllowClose: $('#splitter-allow-close'),
  splitterAllowCancel: $('#splitter-allow-cancel'),
  splitterAllowError: $('#splitter-allow-error'),
  splitterAllowKind: $('#splitter-allow-kind'),
  splitterAllowValue: $('#splitter-allow-value'),
  splitterAllowSave: $('#splitter-allow-save'),
  bufferInputOverlay: $('#buffer-input-overlay'),
  bufferInputForm: $('#buffer-input-form'),
  bufferInputClose: $('#buffer-input-close'),
  bufferInputCancel: $('#buffer-input-cancel'),
  bufferInputError: $('#buffer-input-error'),
  bufferInputEnabled: $('#buffer-input-enabled'),
  bufferInputUrl: $('#buffer-input-url'),
  bufferInputPriority: $('#buffer-input-priority'),
  bufferInputSave: $('#buffer-input-save'),
  bufferAllowOverlay: $('#buffer-allow-overlay'),
  bufferAllowForm: $('#buffer-allow-form'),
  bufferAllowClose: $('#buffer-allow-close'),
  bufferAllowCancel: $('#buffer-allow-cancel'),
  bufferAllowError: $('#buffer-allow-error'),
  bufferAllowKind: $('#buffer-allow-kind'),
  bufferAllowValue: $('#buffer-allow-value'),
  bufferAllowSave: $('#buffer-allow-save'),
  inputForm: $('#input-form'),
  inputClose: $('#input-close'),
  inputCancel: $('#input-cancel'),
  inputType: $('#input-type'),
  inputDvbId: $('#input-dvb-id'),
  inputUdpIface: $('#input-udp-iface'),
  inputUdpAddr: $('#input-udp-addr'),
  inputUdpPort: $('#input-udp-port'),
  inputUdpSocket: $('#input-udp-socket'),
  inputHttpLogin: $('#input-http-login'),
  inputHttpPass: $('#input-http-pass'),
  inputHttpHost: $('#input-http-host'),
  inputHttpPort: $('#input-http-port'),
  inputHttpPath: $('#input-http-path'),
  inputHttpUa: $('#input-http-ua'),
  inputHttpTimeout: $('#input-http-timeout'),
  inputHttpBuffer: $('#input-http-buffer'),
  inputBridgeUrl: $('#input-bridge-url'),
  inputBridgePort: $('#input-bridge-port'),
  inputFileName: $('#input-file-name'),
  inputFileLoop: $('#input-file-loop'),
  inputStreamId: $('#input-stream-id'),
  inputPnr: $('#input-pnr'),
  inputSetPnr: $('#input-set-pnr'),
  inputSetTsid: $('#input-set-tsid'),
  inputBiss: $('#input-biss'),
  inputCamId: $('#input-cam-id'),
  inputEcmPid: $('#input-ecm-pid'),
  inputShift: $('#input-shift'),
  inputMap: $('#input-map'),
  inputFilter: $('#input-filter'),
  inputFilterNot: $('#input-filter-not'),
  inputCcLimit: $('#input-cc-limit'),
  inputBitrateLimit: $('#input-bitrate-limit'),
  inputCam: $('#input-cam'),
  inputCas: $('#input-cas'),
  inputPassSdt: $('#input-pass-sdt'),
  inputPassEit: $('#input-pass-eit'),
  inputNoReload: $('#input-no-reload'),
  inputNoAnalyze: $('#input-no-analyze'),
  adapterList: $('#adapter-list'),
  adapterListEmpty: $('#adapter-list-empty'),
  adapterEditor: $('#adapter-editor'),
  adapterTitle: $('#adapter-title'),
  adapterClear: $('#adapter-clear'),
  adapterNew: $('#adapter-new'),
  adapterForm: $('#adapter-form'),
  adapterSelect: $('#adapter-select'),
  adapterDetected: $('#adapter-detected'),
  adapterDetectedBadge: $('#adapter-detected-badge'),
  adapterDetectedRefresh: $('#adapter-detected-refresh'),
  adapterDetectedHint: $('#adapter-detected-hint'),
  adapterBusyWarning: $('#adapter-busy-warning'),
  adapterScan: $('#adapter-scan'),
  adapterScanOverlay: $('#adapter-scan-overlay'),
  adapterScanSub: $('#adapter-scan-sub'),
  adapterScanStatus: $('#adapter-scan-status'),
  adapterScanSignal: $('#adapter-scan-signal'),
  adapterScanList: $('#adapter-scan-list'),
  adapterScanAdd: $('#adapter-scan-add'),
  adapterScanRefresh: $('#adapter-scan-refresh'),
  adapterScanClose: $('#adapter-scan-close'),
  adapterScanCancel: $('#adapter-scan-cancel'),
  adapterCancel: $('#adapter-cancel'),
  adapterDelete: $('#adapter-delete'),
  adapterError: $('#adapter-error'),
  adapterEnabled: $('#adapter-enabled'),
  adapterId: $('#adapter-id'),
  adapterIndex: $('#adapter-index'),
  adapterDevice: $('#adapter-device'),
  adapterType: $('#adapter-type'),
  adapterModulation: $('#adapter-modulation'),
  adapterCaPmtDelay: $('#adapter-ca-pmt-delay'),
  adapterBufferSize: $('#adapter-buffer-size'),
  adapterBudget: $('#adapter-budget'),
  adapterRawSignal: $('#adapter-raw-signal'),
  adapterLogSignal: $('#adapter-log-signal'),
  adapterStreamId: $('#adapter-stream-id'),
  adapterTp: $('#adapter-tp'),
  adapterLnb: $('#adapter-lnb'),
  adapterLnbSharing: $('#adapter-lnb-sharing'),
  adapterDiseqc: $('#adapter-diseqc'),
  adapterTone: $('#adapter-tone'),
  adapterRolloff: $('#adapter-rolloff'),
  adapterUniScr: $('#adapter-uni-scr'),
  adapterUniFrequency: $('#adapter-uni-frequency'),
  adapterTFrequency: $('#adapter-t-frequency'),
  adapterBandwidth: $('#adapter-bandwidth'),
  adapterGuardinterval: $('#adapter-guardinterval'),
  adapterTransmitmode: $('#adapter-transmitmode'),
  adapterHierarchy: $('#adapter-hierarchy'),
  adapterCFrequency: $('#adapter-c-frequency'),
  adapterCSymbolrate: $('#adapter-c-symbolrate'),
  adapterAtscFrequency: $('#adapter-atsc-frequency'),
  analyzeOverlay: $('#analyze-overlay'),
  analyzeRestart: $('#analyze-restart'),
  analyzeCopy: $('#analyze-copy'),
  analyzeClose: $('#analyze-close'),
  analyzeBody: $('#analyze-body'),
  analyzeRate: $('#analyze-rate'),
  analyzeCc: $('#analyze-cc'),
  analyzePes: $('#analyze-pes'),
  dashboardNotice: $('#dashboard-notice'),
  playerOverlay: $('#player-overlay'),
  playerVideo: $('#player-video'),
  playerClose: $('#player-close'),
  playerSub: $('#player-sub'),
  playerUrl: $('#player-url'),
  playerStatus: $('#player-status'),
  playerInput: $('#player-input'),
  playerOpenTab: $('#player-open-tab'),
  playerCopyLink: $('#player-copy-link'),
  playerLinkPlay: $('#player-link-play'),
  playerLinkHls: $('#player-link-hls'),
  playerRetry: $('#player-retry'),
  playerError: $('#player-error'),
  playerLoading: $('#player-loading'),
  btnNewStream: $('#btn-new-stream'),
  btnNewAdapter: $('#btn-new-adapter'),
  btnView: $('#btn-view'),
  btnLogout: $('#btn-logout'),
  hlsStorage: $('#hls-storage'),
  hlsOnDemand: $('#hls-on-demand'),
  hlsIdleTimeout: $('#hls-idle-timeout'),
  hlsMaxBytesMb: $('#hls-max-bytes-mb'),
  hlsMaxSegments: $('#hls-max-segments'),
  hlsDuration: $('#hls-duration'),
  hlsQuantity: $('#hls-quantity'),
  hlsNaming: $('#hls-naming'),
  hlsSessionTimeout: $('#hls-session-timeout'),
  hlsResourcePath: $('#hls-resource-path'),
  hlsRoundDuration: $('#hls-round-duration'),
  hlsExpires: $('#hls-expires'),
  hlsPassData: $('#hls-pass-data'),
  hlsM3uHeaders: $('#hls-m3u-headers'),
  hlsTsExtension: $('#hls-ts-extension'),
  hlsTsMime: $('#hls-ts-mime'),
  hlsTsHeaders: $('#hls-ts-headers'),
  btnSaveHls: $('#btn-save-hls'),
  btnApplyHls: $('#btn-apply-hls'),
  httpPlayAllow: $('#http-play-allow'),
  httpPlayHls: $('#http-play-hls'),
  httpPlayHlsStorageWarning: $('#http-play-hls-storage-warning'),
  btnHlsSwitchMemfd: $('#btn-hls-switch-memfd'),
  httpPlayPort: $('#http-play-port'),
  httpPlayNoTls: $('#http-play-no-tls'),
  httpPlayLogos: $('#http-play-logos'),
  httpPlayScreens: $('#http-play-screens'),
  httpPlayPlaylistName: $('#http-play-playlist-name'),
  httpPlayArrange: $('#http-play-arrange'),
  httpPlayBuffer: $('#http-play-buffer'),
  httpPlayM3uHeader: $('#http-play-m3u-header'),
  httpPlayXspfTitle: $('#http-play-xspf-title'),
  btnSaveHttpPlay: $('#btn-save-http-play'),
  btnApplyHttpPlay: $('#btn-apply-http-play'),
  bufferSettingEnabled: $('#buffer-setting-enabled'),
  bufferSettingHost: $('#buffer-setting-host'),
  bufferSettingPort: $('#buffer-setting-port'),
  bufferSettingSourceInterface: $('#buffer-setting-source-interface'),
  bufferSettingMaxClients: $('#buffer-setting-max-clients'),
  bufferSettingClientTimeout: $('#buffer-setting-client-timeout'),
  btnApplyBuffer: $('#btn-apply-buffer'),
  httpAuthEnabled: $('#http-auth-enabled'),
  httpAuthUsers: $('#http-auth-users'),
  httpAuthAllow: $('#http-auth-allow'),
  httpAuthDeny: $('#http-auth-deny'),
  httpAuthTokens: $('#http-auth-tokens'),
  httpAuthRealm: $('#http-auth-realm'),
  btnSaveHttpAuth: $('#btn-save-http-auth'),
  btnApplyHttpAuth: $('#btn-apply-http-auth'),
  authOnPlayUrl: $('#auth-on-play-url'),
  authOnPublishUrl: $('#auth-on-publish-url'),
  authTimeoutMs: $('#auth-timeout-ms'),
  authDefaultDuration: $('#auth-default-duration'),
  authDenyCache: $('#auth-deny-cache'),
  authHashAlgo: $('#auth-hash-algo'),
  authHlsRewrite: $('#auth-hls-rewrite'),
  authAdminBypass: $('#auth-admin-bypass'),
  authAllowNoToken: $('#auth-allow-no-token'),
  authOverlimitPolicy: $('#auth-overlimit-policy'),
  btnRestart: $('#btn-restart'),
  importFile: $('#import-file'),
  importMode: $('#import-mode'),
  importButton: $('#btn-import-json'),
  importResult: $('#import-result'),
};

const defaults = {
  hlsBase: '/hls',
  hlsDir: '/tmp/astra-data/hls',
};

const OUTPUT_AUDIO_FIX_DEFAULTS = {
  enabled: false,
  force_on: false,
  mode: 'aac',
  target_audio_type: 0x0f,
  probe_interval_sec: 30,
  probe_duration_sec: 2,
  mismatch_hold_sec: 10,
  restart_cooldown_sec: 1200,
  aac_bitrate_kbps: 128,
  aac_sample_rate: 48000,
  aac_channels: 2,
  aac_profile: '',
  aresample_async: 1,
  silence_fallback: false,
};

let searchTerm = '';

// Настройки: схема и вспомогательные функции для вкладки Settings → General.
function readInputValue(id) {
  const el = document.getElementById(id);
  if (!el) return null;
  if (el.type === 'checkbox') return !!el.checked;
  if (el.tagName === 'SELECT') return el.value;
  return el.value;
}

function readBoolValue(id, fallback) {
  const value = readInputValue(id);
  if (value === null || value === undefined) return fallback;
  return value === true || value === 'true' || value === '1';
}

function readNumberValue(id, fallback) {
  const value = readInputValue(id);
  const num = Number(value);
  if (!Number.isFinite(num)) return fallback;
  return num;
}

function readStringValue(id, fallback) {
  const value = readInputValue(id);
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function formatOnOff(value) {
  return value ? 'вкл' : 'выкл';
}

function formatDays(value) {
  return `${value}д`;
}

function formatSeconds(value) {
  return `${value}с`;
}

function formatOptionalNumber(value, suffix, emptyLabel) {
  if (!Number.isFinite(value) || value === 0) return emptyLabel || '—';
  return `${value}${suffix || ''}`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

const SETTINGS_GENERAL_SECTIONS = [
  {
    id: 'interface',
    title: 'Интерфейс',
    description: 'Видимость инструментов и настройки EPG.',
    cards: [
      {
        id: 'ui-tools',
        title: 'Интерфейс',
        description: 'Показывать или скрывать основные инструменты.',
        level: 'basic',
        collapsible: false,
        fields: [
          {
            id: 'settings-show-splitter',
            label: 'Показывать HLSSplitter',
            type: 'switch',
            key: 'ui_splitter_enabled',
            level: 'basic',
          },
          {
            id: 'settings-show-buffer',
            label: 'Показывать Buffer',
            type: 'switch',
            key: 'ui_buffer_enabled',
            level: 'basic',
          },
          {
            id: 'settings-show-access',
            label: 'Показывать Access',
            type: 'switch',
            key: 'ui_access_enabled',
            level: 'basic',
          },
          {
            id: 'settings-show-epg',
            label: 'Показывать настройки EPG‑экспорта',
            type: 'switch',
            key: 'epg_export_interval_sec',
            level: 'basic',
            uiOnly: true,
          },
          {
            id: 'settings-epg-interval',
            label: 'EPG export interval (sec)',
            type: 'input',
            inputType: 'number',
            key: 'epg_export_interval_sec',
            level: 'basic',
            placeholder: '0 (disabled)',
            dependsOn: { id: 'settings-show-epg', value: true },
          },
        ],
        summary: () => {
          const splitter = readBoolValue('settings-show-splitter', false);
          const buffer = readBoolValue('settings-show-buffer', false);
          const access = readBoolValue('settings-show-access', true);
          const epgOn = readBoolValue('settings-show-epg', false);
          const epgInterval = readNumberValue('settings-epg-interval', 0);
          const epgText = epgOn && epgInterval > 0 ? `${epgInterval}с` : 'выкл';
          return `HLSSplitter: ${formatOnOff(splitter)} · Buffer: ${formatOnOff(buffer)} · Access: ${formatOnOff(access)} · EPG: ${epgText}`;
        },
      },
    ],
  },
  {
    id: 'preview',
    title: 'Preview',
    description: 'Лимиты предпросмотра и авто-остановка.',
    cards: [
      {
        id: 'preview-core',
        title: 'Stream preview',
        description: 'Ограничения и таймауты для on-demand просмотра.',
        level: 'basic',
        collapsible: true,
        fields: [
          {
            id: 'settings-preview-max-sessions',
            label: 'Max preview sessions (global)',
            type: 'input',
            inputType: 'number',
            key: 'preview_max_sessions',
            level: 'basic',
            placeholder: '2',
          },
          {
            id: 'settings-preview-idle-timeout',
            label: 'Idle timeout (sec)',
            type: 'input',
            inputType: 'number',
            key: 'preview_idle_timeout_sec',
            level: 'basic',
            placeholder: '45',
          },
          {
            id: 'settings-preview-token-ttl',
            label: 'Token TTL (sec)',
            type: 'input',
            inputType: 'number',
            key: 'preview_token_ttl_sec',
            level: 'basic',
            placeholder: '180',
          },
        ],
        summary: () => {
          const max = readNumberValue('settings-preview-max-sessions', 2);
          const idle = readNumberValue('settings-preview-idle-timeout', 45);
          const ttl = readNumberValue('settings-preview-token-ttl', 180);
          return `Max: ${max} · Idle: ${formatSeconds(idle)} · TTL: ${formatSeconds(ttl)}`;
        },
      },
    ],
  },
  {
    id: 'observability',
    title: 'Наблюдаемость',
    description: 'Сбор логов, метрик и автоматический контроль процесса.',
    cards: [
      {
        id: 'observability-core',
        title: 'Observability',
        description: 'Логи, метрики и rollup.',
        level: 'basic',
        toggle: { id: 'settings-observability-enabled', label: 'Включено' },
        collapsible: true,
        fields: [
          {
            id: 'settings-observability-logs-days',
            label: 'Log retention (days)',
            type: 'select',
            key: 'ai_logs_retention_days',
            level: 'basic',
            options: [
              { value: '1', label: '1' },
              { value: '7', label: '7' },
              { value: '30', label: '30' },
            ],
          },
          {
            id: 'settings-observability-metrics-days',
            label: 'Metrics retention (days)',
            type: 'select',
            key: 'ai_metrics_retention_days',
            level: 'advanced',
            options: [
              { value: '7', label: '7' },
              { value: '30', label: '30' },
              { value: '90', label: '90' },
            ],
            dependsOn: () => !readBoolValue('settings-observability-on-demand', false),
          },
          {
            id: 'settings-observability-rollup',
            label: 'Rollup interval (sec)',
            type: 'select',
            key: 'ai_rollup_interval_sec',
            level: 'advanced',
            options: [
              { value: '60', label: '60' },
              { value: '300', label: '300' },
              { value: '3600', label: '3600' },
            ],
            dependsOn: () => !readBoolValue('settings-observability-on-demand', false),
          },
          {
            id: 'settings-observability-on-demand',
            label: 'On‑demand metrics (без фонового rollup)',
            type: 'switch',
            key: 'ai_metrics_on_demand',
            level: 'advanced',
          },
          {
            type: 'note',
            text: 'Метрики всегда считаются по запросу (фоновый rollup отключён).',
            level: 'advanced',
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-observability-enabled', false);
          if (!enabled) return 'Выключено';
          const logs = readNumberValue('settings-observability-logs-days', 7);
          const onDemand = readBoolValue('settings-observability-on-demand', false);
          const metrics = onDemand
            ? 'по запросу'
            : formatDays(readNumberValue('settings-observability-metrics-days', 30));
          const rollup = onDemand
            ? '—'
            : formatSeconds(readNumberValue('settings-observability-rollup', 60));
          return `Включено · Logs: ${formatDays(logs)} · Metrics: ${metrics} · Rollup: ${rollup}`;
        },
      },
      {
        id: 'monitoring-logs',
        title: 'Monitoring & Logs',
        description: 'Вебхуки, лимиты и диагностика.',
        level: 'advanced',
        collapsible: true,
        fields: [
          {
            id: 'settings-event-request',
            label: 'Event webhook URL',
            type: 'input',
            inputType: 'text',
            key: 'event_request',
            level: 'advanced',
            placeholder: 'http://127.0.0.1:9005/event',
          },
          {
            id: 'settings-monitor-analyze-max',
            label: 'Analyze concurrency limit',
            type: 'input',
            inputType: 'number',
            key: 'monitor_analyze_max_concurrency',
            level: 'advanced',
            placeholder: '4',
          },
          {
            id: 'settings-psi-debug',
            label: 'PSI debug logs (NIT/TOT/TDT)',
            type: 'switch',
            key: 'psi_debug_logs',
            level: 'advanced',
          },
          {
            id: 'settings-log-max-entries',
            label: 'Log max entries',
            type: 'input',
            inputType: 'number',
            key: 'log_max_entries',
            level: 'advanced',
            placeholder: '0 (unlimited)',
          },
          {
            id: 'settings-log-retention-sec',
            label: 'Log retention (sec)',
            type: 'input',
            inputType: 'number',
            key: 'log_retention_sec',
            level: 'advanced',
            placeholder: '0 (unlimited)',
          },
          {
            id: 'settings-access-log-max-entries',
            label: 'Access log max entries',
            type: 'input',
            inputType: 'number',
            key: 'access_log_max_entries',
            level: 'advanced',
            placeholder: '0 (unlimited)',
          },
          {
            id: 'settings-access-log-retention-sec',
            label: 'Access log retention (sec)',
            type: 'input',
            inputType: 'number',
            key: 'access_log_retention_sec',
            level: 'advanced',
            placeholder: '0 (unlimited)',
          },
        ],
        summary: () => {
          const webhook = readStringValue('settings-event-request', '');
          const logMax = readNumberValue('settings-log-max-entries', 0);
          const accessMax = readNumberValue('settings-access-log-max-entries', 0);
          const webhookText = webhook ? 'Webhook: задан' : 'Webhook: нет';
          const logsText = `Logs: ${formatOptionalNumber(logMax, '', '∞')}`;
          const accessText = `Access: ${formatOptionalNumber(accessMax, '', '∞')}`;
          return `${webhookText} · ${logsText} · ${accessText}`;
        },
      },
      {
        id: 'process-watchdog',
        title: 'Process Watchdog',
        description: 'Авто‑рестарт при превышении CPU/RAM.',
        level: 'advanced',
        toggle: { id: 'settings-watchdog-enabled', label: 'Включено' },
        collapsible: true,
        fields: [
          {
            id: 'settings-watchdog-cpu',
            label: 'CPU limit (%)',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_cpu_pct',
            level: 'advanced',
            placeholder: '95',
          },
          {
            id: 'settings-watchdog-rss-mb',
            label: 'RSS limit (MB)',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_rss_mb',
            level: 'advanced',
            placeholder: '0 (use %)',
          },
          {
            id: 'settings-watchdog-rss-pct',
            label: 'RSS limit (%)',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_rss_pct',
            level: 'advanced',
            placeholder: '80',
          },
          {
            id: 'settings-watchdog-interval',
            label: 'Interval (sec)',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_interval_sec',
            level: 'advanced',
            placeholder: '10',
          },
          {
            id: 'settings-watchdog-strikes',
            label: 'Max strikes',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_max_strikes',
            level: 'advanced',
            placeholder: '6',
          },
          {
            id: 'settings-watchdog-uptime',
            label: 'Min uptime (sec)',
            type: 'input',
            inputType: 'number',
            key: 'resource_watchdog_min_uptime_sec',
            level: 'advanced',
            placeholder: '180',
          },
          {
            type: 'note',
            text: 'При превышении лимитов процесс завершается (используйте systemd Restart=always).',
            level: 'advanced',
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-watchdog-enabled', false);
          if (!enabled) return 'Выключено';
          const cpu = readNumberValue('settings-watchdog-cpu', 95);
          const rss = readNumberValue('settings-watchdog-rss-pct', 80);
          return `Включено · CPU: ${cpu}% · RSS: ${rss}%`;
        },
      },
    ],
  },
  {
    id: 'alerts',
    title: 'Оповещения',
    description: 'Уведомления о событиях.',
    cards: [
      {
        id: 'telegram-alerts',
        title: 'Telegram Alerts',
        description: 'Короткие уведомления в Telegram.',
        level: 'basic',
        toggle: { id: 'settings-telegram-enabled', label: 'Включено', disableCard: false },
        collapsible: true,
        fields: [
          {
            id: 'settings-telegram-level',
            label: 'Level',
            type: 'select',
            key: 'telegram_level',
            level: 'basic',
            options: [
              { value: 'OFF', label: 'OFF' },
              { value: 'CRITICAL', label: 'CRITICAL' },
              { value: 'ERROR', label: 'ERROR' },
              { value: 'WARNING', label: 'WARNING' },
              { value: 'INFO', label: 'INFO' },
              { value: 'DEBUG', label: 'DEBUG' },
            ],
          },
          {
            id: 'settings-telegram-token',
            label: 'Bot Token',
            type: 'input',
            inputType: 'password',
            key: 'telegram_bot_token',
            level: 'basic',
            placeholder: '123456:ABCDEF',
            hintId: 'settings-telegram-token-hint',
          },
          {
            id: 'settings-telegram-chat-id',
            label: 'Chat ID / Channel',
            type: 'input',
            inputType: 'text',
            key: 'telegram_chat_id',
            level: 'basic',
            placeholder: '-1001234567890 or @channel',
          },
          {
            id: 'settings-telegram-test',
            type: 'button',
            buttonText: 'Отправить тест',
            level: 'basic',
          },
          {
            type: 'heading',
            text: 'Бэкапы конфигурации',
            level: 'advanced',
          },
          {
            id: 'settings-telegram-backup-enabled',
            label: 'Отправлять бэкапы',
            type: 'switch',
            key: 'telegram_backup_enabled',
            level: 'advanced',
          },
          {
            id: 'settings-telegram-backup-schedule',
            label: 'Schedule',
            type: 'select',
            key: 'telegram_backup_schedule',
            level: 'advanced',
            options: [
              { value: 'DAILY', label: 'Daily' },
              { value: 'WEEKLY', label: 'Weekly' },
              { value: 'MONTHLY', label: 'Monthly' },
            ],
            dependsOn: { id: 'settings-telegram-backup-enabled', value: true },
          },
          {
            id: 'settings-telegram-backup-time',
            label: 'Time',
            type: 'input',
            inputType: 'time',
            key: 'telegram_backup_time',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-backup-enabled', value: true },
          },
          {
            id: 'settings-telegram-backup-weekday',
            label: 'Weekday',
            type: 'select',
            key: 'telegram_backup_weekday',
            level: 'advanced',
            wrapperId: 'settings-telegram-backup-weekday-field',
            options: [
              { value: '1', label: 'Monday' },
              { value: '2', label: 'Tuesday' },
              { value: '3', label: 'Wednesday' },
              { value: '4', label: 'Thursday' },
              { value: '5', label: 'Friday' },
              { value: '6', label: 'Saturday' },
              { value: '7', label: 'Sunday' },
            ],
            dependsOn: () => {
              const enabled = readBoolValue('settings-telegram-backup-enabled', false);
              const schedule = readStringValue('settings-telegram-backup-schedule', 'DAILY');
              return enabled && schedule === 'WEEKLY';
            },
          },
          {
            id: 'settings-telegram-backup-monthday',
            label: 'Month day',
            type: 'input',
            inputType: 'number',
            key: 'telegram_backup_monthday',
            level: 'advanced',
            wrapperId: 'settings-telegram-backup-monthday-field',
            min: 1,
            max: 31,
            dependsOn: () => {
              const enabled = readBoolValue('settings-telegram-backup-enabled', false);
              const schedule = readStringValue('settings-telegram-backup-schedule', 'DAILY');
              return enabled && schedule === 'MONTHLY';
            },
          },
          {
            id: 'settings-telegram-backup-secrets',
            label: 'Include secrets in backup',
            type: 'switch',
            key: 'telegram_backup_include_secrets',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-backup-enabled', value: true },
          },
          {
            id: 'settings-telegram-backup-now',
            type: 'button',
            buttonText: 'Отправить бэкап сейчас',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-backup-enabled', value: true },
          },
          {
            type: 'note',
            text: 'Бэкапы приходят JSON‑файлом в тот же чат.',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-backup-enabled', value: true },
          },
          {
            type: 'heading',
            text: 'AI‑summary',
            level: 'advanced',
          },
          {
            id: 'settings-telegram-summary-enabled',
            label: 'Отправлять AI‑summary',
            type: 'switch',
            key: 'telegram_summary_enabled',
            level: 'advanced',
          },
          {
            id: 'settings-telegram-summary-schedule',
            label: 'Schedule',
            type: 'select',
            key: 'telegram_summary_schedule',
            level: 'advanced',
            options: [
              { value: 'DAILY', label: 'Daily' },
              { value: 'WEEKLY', label: 'Weekly' },
              { value: 'MONTHLY', label: 'Monthly' },
            ],
            dependsOn: { id: 'settings-telegram-summary-enabled', value: true },
          },
          {
            id: 'settings-telegram-summary-time',
            label: 'Time',
            type: 'input',
            inputType: 'time',
            key: 'telegram_summary_time',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-summary-enabled', value: true },
          },
          {
            id: 'settings-telegram-summary-weekday',
            label: 'Weekday',
            type: 'select',
            key: 'telegram_summary_weekday',
            level: 'advanced',
            wrapperId: 'settings-telegram-summary-weekday-field',
            options: [
              { value: '1', label: 'Monday' },
              { value: '2', label: 'Tuesday' },
              { value: '3', label: 'Wednesday' },
              { value: '4', label: 'Thursday' },
              { value: '5', label: 'Friday' },
              { value: '6', label: 'Saturday' },
              { value: '7', label: 'Sunday' },
            ],
            dependsOn: () => {
              const enabled = readBoolValue('settings-telegram-summary-enabled', false);
              const schedule = readStringValue('settings-telegram-summary-schedule', 'DAILY');
              return enabled && schedule === 'WEEKLY';
            },
          },
          {
            id: 'settings-telegram-summary-monthday',
            label: 'Month day',
            type: 'input',
            inputType: 'number',
            key: 'telegram_summary_monthday',
            level: 'advanced',
            wrapperId: 'settings-telegram-summary-monthday-field',
            min: 1,
            max: 31,
            dependsOn: () => {
              const enabled = readBoolValue('settings-telegram-summary-enabled', false);
              const schedule = readStringValue('settings-telegram-summary-schedule', 'DAILY');
              return enabled && schedule === 'MONTHLY';
            },
          },
          {
            id: 'settings-telegram-summary-charts',
            label: 'Include charts',
            type: 'switch',
            key: 'telegram_summary_include_charts',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-summary-enabled', value: true },
          },
          {
            id: 'settings-telegram-summary-now',
            type: 'button',
            buttonText: 'Отправить summary сейчас',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-summary-enabled', value: true },
          },
          {
            type: 'note',
            text: 'Используются rollup‑метрики за последние 24 часа.',
            level: 'advanced',
            dependsOn: { id: 'settings-telegram-summary-enabled', value: true },
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-telegram-enabled', false);
          if (!enabled) return 'Выключено';
          const level = readStringValue('settings-telegram-level', 'OFF');
          const chat = readStringValue('settings-telegram-chat-id', '');
          const chatText = chat ? truncateText(chat, 16) : 'чат не задан';
          return `Включено · ${level} · ${chatText}`;
        },
      },
    ],
  },
  {
    id: 'integrations',
    title: 'Интеграции',
    description: 'Экспорт метрик и внешние сервисы.',
    cards: [
      {
        id: 'influx',
        title: 'InfluxDB export',
        description: 'Экспорт метрик по HTTP.',
        level: 'advanced',
        toggle: { id: 'settings-influx-enabled', label: 'Включено' },
        collapsible: true,
        fields: [
          {
            id: 'settings-influx-url',
            label: 'Influx URL',
            type: 'input',
            inputType: 'text',
            key: 'influx_url',
            level: 'advanced',
            placeholder: 'http://127.0.0.1:8086',
          },
          {
            id: 'settings-influx-org',
            label: 'Org',
            type: 'input',
            inputType: 'text',
            key: 'influx_org',
            level: 'advanced',
            placeholder: 'my-org',
          },
          {
            id: 'settings-influx-bucket',
            label: 'Bucket',
            type: 'input',
            inputType: 'text',
            key: 'influx_bucket',
            level: 'advanced',
            placeholder: 'astra',
          },
          {
            id: 'settings-influx-token',
            label: 'Token',
            type: 'input',
            inputType: 'password',
            key: 'influx_token',
            level: 'advanced',
            placeholder: 'optional',
          },
          {
            id: 'settings-influx-instance',
            label: 'Instance name',
            type: 'input',
            inputType: 'text',
            key: 'influx_instance',
            level: 'advanced',
            placeholder: 'astra-1',
          },
          {
            id: 'settings-influx-measurement',
            label: 'Measurement',
            type: 'input',
            inputType: 'text',
            key: 'influx_measurement',
            level: 'advanced',
            placeholder: 'astra_metrics',
          },
          {
            id: 'settings-influx-interval',
            label: 'Interval (sec)',
            type: 'input',
            inputType: 'number',
            key: 'influx_interval_sec',
            level: 'advanced',
            placeholder: '30',
          },
          {
            type: 'note',
            text: 'Используется line protocol через HTTP (без TLS).',
            level: 'advanced',
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-influx-enabled', false);
          if (!enabled) return 'Выключено';
          const url = readStringValue('settings-influx-url', '');
          const interval = readNumberValue('settings-influx-interval', 30);
          return `Включено · ${url || 'URL не задан'} · ${formatSeconds(interval)}`;
        },
      },
    ],
  },
  {
    id: 'transcoding',
    title: 'Транскодинг',
    description: 'Инструменты и HTTPS‑входы.',
    cards: [
      {
        id: 'transcode-tools',
        title: 'Transcode tools',
        description: 'Переопределение путей к FFmpeg/FFprobe.',
        level: 'advanced',
        collapsible: true,
        fields: [
          {
            id: 'settings-ffmpeg-path',
            label: 'FFmpeg path',
            type: 'input',
            inputType: 'text',
            key: 'ffmpeg_path',
            level: 'advanced',
            placeholder: '(auto)',
          },
          {
            id: 'settings-ffprobe-path',
            label: 'FFprobe path',
            type: 'input',
            inputType: 'text',
            key: 'ffprobe_path',
            level: 'advanced',
            placeholder: '(auto)',
          },
          {
            type: 'note',
            text: 'Оставьте пустым, чтобы использовать bundled‑binary или PATH.',
            level: 'advanced',
          },
        ],
        summary: () => {
          const ffmpeg = readStringValue('settings-ffmpeg-path', '');
          const ffprobe = readStringValue('settings-ffprobe-path', '');
          const ffmpegText = ffmpeg ? 'FFmpeg: задан' : 'FFmpeg: auto';
          const ffprobeText = ffprobe ? 'FFprobe: задан' : 'FFprobe: auto';
          return `${ffmpegText} · ${ffprobeText}`;
        },
      },
      {
        id: 'https-inputs',
        title: 'HTTP inputs',
        description: 'HTTPS‑входы через FFmpeg‑мост.',
        level: 'basic',
        toggle: { id: 'settings-https-bridge-enabled', label: 'Включено' },
        collapsible: true,
        fields: [
          {
            type: 'note',
            text: 'Когда выключено, HTTPS‑входы отклоняются, если не переопределены в input.',
            level: 'basic',
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-https-bridge-enabled', false);
          return `HTTPS bridge: ${formatOnOff(enabled)}`;
        },
      },
    ],
  },
  {
    id: 'security',
    title: 'Безопасность',
    description: 'Сессии и защита доступа.',
    cards: [
      {
        id: 'security-sessions',
        title: 'Security & Sessions',
        description: 'CSRF и лимиты входа.',
        level: 'basic',
        collapsible: true,
        fields: [
          {
            id: 'settings-http-csrf',
            label: 'Включить CSRF‑защиту для cookie‑сессий',
            type: 'switch',
            key: 'http_csrf_enabled',
            level: 'basic',
          },
          {
            id: 'settings-show-security-limits',
            label: 'Показать лимиты сессий и rate limit',
            type: 'switch',
            level: 'basic',
            uiOnly: true,
          },
          {
            id: 'settings-auth-session-ttl',
            label: 'Session TTL (sec)',
            type: 'input',
            inputType: 'number',
            key: 'auth_session_ttl_sec',
            level: 'advanced',
            placeholder: '3600',
            dependsOn: { id: 'settings-show-security-limits', value: true },
          },
          {
            id: 'settings-login-rate-limit',
            label: 'Login rate limit (per min)',
            type: 'input',
            inputType: 'number',
            key: 'rate_limit_login_per_min',
            level: 'advanced',
            placeholder: '30',
            dependsOn: { id: 'settings-show-security-limits', value: true },
          },
          {
            id: 'settings-login-rate-window',
            label: 'Login rate limit window (sec)',
            type: 'input',
            inputType: 'number',
            key: 'rate_limit_login_window_sec',
            level: 'advanced',
            placeholder: '60',
            dependsOn: { id: 'settings-show-security-limits', value: true },
          },
        ],
        summary: () => {
          const csrf = readBoolValue('settings-http-csrf', true);
          const ttl = readNumberValue('settings-auth-session-ttl', 3600);
          const rate = readNumberValue('settings-login-rate-limit', 30);
          return `CSRF: ${formatOnOff(csrf)} · TTL: ${formatSeconds(ttl)} · ${rate}/min`;
        },
      },
    ],
  },
  {
    id: 'experimental',
    title: 'Экспериментальное',
    description: 'AI‑возможности и небезопасные опции.',
    cards: [
      {
        id: 'astra-ai',
        title: 'AstraAI',
        description: 'Планирование и применение изменений.',
        level: 'advanced',
        toggle: { id: 'settings-ai-enabled', label: 'Включено' },
        collapsible: true,
        fields: [
          {
            id: 'settings-ai-api-key',
            label: 'API Key',
            type: 'input',
            inputType: 'password',
            key: 'ai_api_key',
            level: 'advanced',
            placeholder: 'sk-...',
            hintId: 'settings-ai-api-key-hint',
          },
          {
            id: 'settings-ai-api-base',
            label: 'API Base',
            type: 'input',
            inputType: 'text',
            key: 'ai_api_base',
            level: 'advanced',
            placeholder: 'https://api.openai.com',
          },
          {
            id: 'settings-ai-model',
            label: 'Model',
            type: 'input',
            inputType: 'text',
            key: 'ai_model',
            level: 'advanced',
            placeholder: 'gpt-5.2',
            hintId: 'settings-ai-model-hint',
          },
          {
            type: 'note',
            text: 'Charts mode: Spec only (PNG rendering отключён).',
            level: 'advanced',
          },
          {
            id: 'settings-ai-max-tokens',
            label: 'Max tokens',
            type: 'input',
            inputType: 'number',
            key: 'ai_max_tokens',
            level: 'advanced',
            placeholder: '512',
          },
          {
            id: 'settings-ai-temperature',
            label: 'Temperature',
            type: 'input',
            inputType: 'number',
            key: 'ai_temperature',
            level: 'advanced',
            placeholder: '0.2',
            step: 0.1,
            min: 0,
            max: 2,
          },
          {
            id: 'settings-ai-allowed-chats',
            label: 'Allowed chat IDs',
            type: 'input',
            inputType: 'text',
            key: 'ai_telegram_allowed_chat_ids',
            level: 'advanced',
            placeholder: '-1001234567890, @channel',
          },
          {
            id: 'settings-ai-store',
            label: 'Allow provider storage',
            type: 'switch',
            key: 'ai_store',
            level: 'advanced',
          },
          {
            id: 'settings-ai-allow-apply',
            label: 'Allow apply (write changes)',
            type: 'switch',
            key: 'ai_allow_apply',
            level: 'advanced',
          },
          {
            type: 'note',
            text: 'Apply использует backup → validate → diff → reload. Включайте только при полном доверии.',
            level: 'advanced',
            tone: 'warning',
          },
        ],
        summary: () => {
          const enabled = readBoolValue('settings-ai-enabled', false);
          if (!enabled) return 'Выключено';
          const model = readStringValue('settings-ai-model', '');
          return `Включено · ${model || 'модель не задана'}`;
        },
      },
    ],
  },
  {
    id: 'defaults',
    title: 'Значения по умолчанию',
    description: 'Шаблоны для новых стримов.',
    cards: [
      {
        id: 'stream-defaults',
        title: 'Stream defaults',
        description: 'Параметры для новых стримов.',
        level: 'advanced',
        collapsible: true,
        fields: [
          {
            id: 'settings-show-stream-defaults',
            label: 'Показывать значения по умолчанию',
            type: 'switch',
            level: 'advanced',
            uiOnly: true,
          },
          {
            id: 'settings-default-no-data-timeout',
            label: 'No data timeout (sec)',
            type: 'input',
            inputType: 'number',
            key: 'no_data_timeout_sec',
            level: 'advanced',
            placeholder: '3',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-probe-interval',
            label: 'Probe interval (sec)',
            type: 'input',
            inputType: 'number',
            key: 'probe_interval_sec',
            level: 'advanced',
            placeholder: '3',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-stable-ok',
            label: 'Stable OK window (sec)',
            type: 'input',
            inputType: 'number',
            key: 'stable_ok_sec',
            level: 'advanced',
            placeholder: '5',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-backup-initial',
            label: 'Backup initial delay (sec)',
            type: 'input',
            inputType: 'number',
            key: 'backup_initial_delay_sec',
            level: 'advanced',
            placeholder: '0',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-backup-start',
            label: 'Backup start delay (sec)',
            type: 'input',
            inputType: 'number',
            key: 'backup_start_delay_sec',
            level: 'advanced',
            placeholder: '5',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-backup-return',
            label: 'Backup return delay (sec)',
            type: 'input',
            inputType: 'number',
            key: 'backup_return_delay_sec',
            level: 'advanced',
            placeholder: '10',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-backup-stop',
            label: 'Stop if all inactive (sec)',
            type: 'input',
            inputType: 'number',
            key: 'backup_stop_if_all_inactive_sec',
            level: 'advanced',
            placeholder: '20',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-backup-warm-max',
            label: 'Active warm inputs max',
            type: 'input',
            inputType: 'number',
            key: 'backup_active_warm_max',
            level: 'advanced',
            placeholder: '2',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
          {
            id: 'settings-default-http-keep-active',
            label: 'HTTP keep active (sec, -1=always)',
            type: 'input',
            inputType: 'number',
            key: 'http_keep_active',
            level: 'advanced',
            placeholder: '0',
            dependsOn: { id: 'settings-show-stream-defaults', value: true },
          },
        ],
        summary: () => {
          const show = readBoolValue('settings-show-stream-defaults', false);
          if (!show) return 'Скрыто';
          const anyValue = [
            readNumberValue('settings-default-no-data-timeout', 0),
            readNumberValue('settings-default-probe-interval', 0),
            readNumberValue('settings-default-stable-ok', 0),
            readNumberValue('settings-default-backup-initial', 0),
            readNumberValue('settings-default-backup-start', 0),
            readNumberValue('settings-default-backup-return', 0),
            readNumberValue('settings-default-backup-stop', 0),
            readNumberValue('settings-default-backup-warm-max', 0),
            readNumberValue('settings-default-http-keep-active', 0),
          ].some((val) => Number.isFinite(val) && val !== 0);
          return anyValue ? 'Переопределены' : 'По умолчанию';
        },
      },
    ],
  },
];

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function buildSearchTokens(query) {
  return String(query || '')
    .toLowerCase()
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function highlightText(text, tokens) {
  if (!tokens.length) return escapeHtml(text);
  const pattern = tokens.map(escapeRegExp).join('|');
  const re = new RegExp(pattern, 'gi');
  let result = '';
  let lastIndex = 0;
  let match = null;
  while ((match = re.exec(text)) !== null) {
    result += escapeHtml(text.slice(lastIndex, match.index));
    result += `<span class="settings-highlight">${escapeHtml(match[0])}</span>`;
    lastIndex = match.index + match[0].length;
  }
  result += escapeHtml(text.slice(lastIndex));
  return result;
}

function registerSearchHighlight(el, text) {
  if (!el) return;
  const value = String(text || '');
  el.dataset.originalText = value;
  state.generalSearchEls.push({ el, text: value });
}

function matchesSearch(text, tokens) {
  if (!tokens.length) return true;
  const source = String(text || '').toLowerCase();
  return tokens.every((token) => source.includes(token));
}

function buildFieldSearchText(field) {
  const parts = [];
  if (field.label) parts.push(field.label);
  if (field.text) parts.push(field.text);
  if (field.buttonText) parts.push(field.buttonText);
  if (field.key) parts.push(field.key);
  if (field.id) parts.push(field.id);
  if (Array.isArray(field.options)) {
    field.options.forEach((option) => {
      if (option && option.label) parts.push(option.label);
      if (option && option.value) parts.push(option.value);
    });
  }
  return parts.join(' ').toLowerCase();
}

function renderSwitchControl(id) {
  const wrapper = createEl('label', 'switch');
  const input = document.createElement('input');
  input.type = 'checkbox';
  input.id = id;
  const slider = createEl('span', 'switch-slider');
  wrapper.append(input, slider);
  return { wrapper, input };
}

function renderSettingsHeader() {
  const header = createEl('div', 'settings-general-header');

  const searchWrap = createEl('div', 'settings-search');
  const searchInput = document.createElement('input');
  searchInput.type = 'search';
  searchInput.id = 'settings-general-search';
  searchInput.placeholder = 'Найти настройку…';
  searchInput.autocomplete = 'off';
  searchWrap.appendChild(searchInput);

  const controls = createEl('div', 'settings-general-controls');
  const modeToggle = createEl('div', 'settings-mode-toggle');
  modeToggle.id = 'settings-general-mode';
  const basicBtn = createEl('button', '', 'Базовые');
  basicBtn.type = 'button';
  basicBtn.dataset.mode = 'basic';
  const advancedBtn = createEl('button', '', 'Расширенные');
  advancedBtn.type = 'button';
  advancedBtn.dataset.mode = 'advanced';
  modeToggle.append(basicBtn, advancedBtn);

  const densityWrap = createEl('div', 'settings-switch-inline');
  const densityLabel = createEl('span', 'settings-switch-label', 'Компактно');
  const densityControl = renderSwitchControl('settings-general-density');
  densityWrap.append(densityLabel, densityControl.wrapper);

  const dirty = createEl('div', 'settings-dirty-indicator hidden', 'Есть несохранённые изменения');
  dirty.id = 'settings-general-dirty';

  controls.append(modeToggle, densityWrap, dirty);
  header.append(searchWrap, controls);
  return header;
}

function renderSidebarNav(sections) {
  const nav = createEl('nav', 'settings-sidebar');
  nav.id = 'settings-general-nav';
  sections.forEach((section) => {
    const btn = createEl('button', '', section.title);
    btn.type = 'button';
    btn.dataset.section = section.id;
    nav.appendChild(btn);
  });
  return nav;
}

function renderSidebarSelect(sections) {
  const wrap = createEl('div', 'settings-sidebar-select');
  const select = document.createElement('select');
  select.id = 'settings-general-nav-select';
  sections.forEach((section) => {
    const option = document.createElement('option');
    option.value = section.id;
    option.textContent = section.title;
    select.appendChild(option);
  });
  wrap.appendChild(select);
  return wrap;
}

function renderField(field) {
  let wrapper = null;
  let input = null;

  if (field.type === 'heading') {
    wrapper = createEl('div', 'settings-subheading settings-field-full', field.text || '');
    registerSearchHighlight(wrapper, field.text || '');
  } else if (field.type === 'note') {
    const toneClass = field.tone === 'warning' ? ' settings-note is-warning' : ' settings-note';
    wrapper = createEl('div', `settings-field-full${toneClass}`, field.text || '');
    registerSearchHighlight(wrapper, field.text || '');
  } else if (field.type === 'button') {
    wrapper = createEl('div', 'field settings-field settings-field-full');
    const button = createEl('button', 'btn ghost', field.buttonText || 'Действие');
    button.type = 'button';
    button.id = field.id;
    wrapper.appendChild(button);
    input = button;
    registerSearchHighlight(button, field.buttonText || '');
  } else if (field.type === 'switch') {
    wrapper = createEl('div', 'settings-switch-line field settings-field');
    const label = createEl('label', 'settings-switch-label', field.label || '');
    label.setAttribute('for', field.id);
    const control = renderSwitchControl(field.id);
    wrapper.append(label, control.wrapper);
    input = control.input;
    registerSearchHighlight(label, field.label || '');
  } else {
    wrapper = createEl('div', 'field settings-field');
    const label = createEl('label', '', field.label || '');
    label.setAttribute('for', field.id);
    wrapper.appendChild(label);

    if (field.type === 'select') {
      const select = document.createElement('select');
      select.id = field.id;
      (field.options || []).forEach((option) => {
        const opt = document.createElement('option');
        opt.value = option.value;
        opt.textContent = option.label;
        select.appendChild(opt);
      });
      wrapper.appendChild(select);
      input = select;
    } else {
      const inputEl = document.createElement('input');
      inputEl.id = field.id;
      inputEl.type = field.inputType || 'text';
      if (field.placeholder !== undefined) inputEl.placeholder = field.placeholder;
      if (field.min !== undefined) inputEl.min = field.min;
      if (field.max !== undefined) inputEl.max = field.max;
      if (field.step !== undefined) inputEl.step = field.step;
      wrapper.appendChild(inputEl);
      input = inputEl;
    }

    if (field.hintId) {
      const hint = createEl('div', 'settings-note', '');
      hint.id = field.hintId;
      wrapper.appendChild(hint);
    }

    registerSearchHighlight(label, field.label || '');
  }

  if (wrapper && field.wrapperId) {
    wrapper.id = field.wrapperId;
  }

  const searchText = buildFieldSearchText(field);
  return {
    def: field,
    el: wrapper,
    input,
    level: field.level || 'basic',
    searchText,
  };
}

function renderCard(sectionId, card) {
  const cardEl = createEl('div', 'settings-card');
  cardEl.dataset.cardId = card.id;
  cardEl.dataset.section = sectionId;
  cardEl.dataset.level = card.level || 'basic';

  const header = createEl('div', 'settings-card-header');
  const meta = createEl('div', '');
  const title = createEl('div', 'settings-card-title', card.title || '');
  const desc = createEl('div', 'settings-card-desc', card.description || '');
  meta.append(title, desc);

  const actions = createEl('div', 'settings-card-actions');
  let toggleInput = null;
  if (card.toggle) {
    const toggleWrap = createEl('div', 'settings-switch-inline');
    const toggleLabel = createEl('span', 'settings-switch-label', card.toggle.label || 'Включено');
    const toggleControl = renderSwitchControl(card.toggle.id);
    toggleWrap.append(toggleLabel, toggleControl.wrapper);
    actions.appendChild(toggleWrap);
    toggleInput = toggleControl.input;
    registerSearchHighlight(toggleLabel, card.toggle.label || '');
  }
  if (card.collapsible) {
    const btn = createEl('button', 'btn ghost', 'Настроить');
    btn.type = 'button';
    btn.dataset.action = 'card-toggle';
    btn.dataset.cardId = card.id;
    actions.appendChild(btn);
  }

  header.append(meta, actions);

  const summary = createEl('div', 'settings-card-summary', '');
  const body = createEl('div', 'settings-card-body');
  body.hidden = !!card.collapsible;
  const grid = createEl('div', 'settings-card-grid');

  const fieldStates = [];
  (card.fields || []).forEach((field) => {
    const fieldState = renderField(field);
    if (fieldState && fieldState.el) {
      grid.appendChild(fieldState.el);
      fieldStates.push(fieldState);
    }
  });

  body.appendChild(grid);
  cardEl.append(header, summary, body);

  registerSearchHighlight(title, card.title || '');
  registerSearchHighlight(desc, card.description || '');

  const cardSearchSelf = `${card.title || ''} ${card.description || ''}`.toLowerCase();

  const cardState = {
    id: card.id,
    level: card.level || 'basic',
    sectionId,
    card,
    cardEl,
    bodyEl: body,
    summaryEl: summary,
    toggleInput,
    fields: fieldStates,
    searchSelf: cardSearchSelf,
  };

  state.generalCards.push(cardState);
  return cardEl;
}

function renderSection(section) {
  const block = createEl('section', 'settings-section-block');
  block.id = `settings-section-${section.id}`;
  block.dataset.section = section.id;
  const title = createEl('div', 'settings-section-title', section.title || '');
  const desc = createEl('div', 'settings-section-desc', section.description || '');
  block.append(title, desc);
  (section.cards || []).forEach((card) => {
    block.appendChild(renderCard(section.id, card));
  });
  registerSearchHighlight(title, section.title || '');
  registerSearchHighlight(desc, section.description || '');
  return block;
}

function renderSettingsActionBar() {
  const bar = createEl('div', 'settings-action-bar is-disabled');
  bar.id = 'settings-action-bar';
  const status = createEl('div', 'settings-action-status', 'Нет несохранённых изменений');
  status.id = 'settings-action-status';
  const buttons = createEl('div', 'settings-action-buttons');
  const save = createEl('button', 'btn', 'Сохранить');
  save.id = 'settings-action-save';
  save.type = 'button';
  const cancel = createEl('button', 'btn ghost', 'Отмена');
  cancel.id = 'settings-action-cancel';
  cancel.type = 'button';
  const reset = createEl('button', 'btn ghost danger', 'Сбросить изменения');
  reset.id = 'settings-action-reset';
  reset.type = 'button';
  buttons.append(save, cancel, reset);
  bar.append(status, buttons);
  return bar;
}

function bindGeneralElements() {
  const map = {
    settingsGeneralSearch: 'settings-general-search',
    settingsGeneralMode: 'settings-general-mode',
    settingsGeneralDensity: 'settings-general-density',
    settingsGeneralDirty: 'settings-general-dirty',
    settingsGeneralNav: 'settings-general-nav',
    settingsGeneralNavSelect: 'settings-general-nav-select',
    settingsActionBar: 'settings-action-bar',
    settingsActionSave: 'settings-action-save',
    settingsActionCancel: 'settings-action-cancel',
    settingsActionReset: 'settings-action-reset',
    settingsActionStatus: 'settings-action-status',
    settingsShowSplitter: 'settings-show-splitter',
    settingsShowBuffer: 'settings-show-buffer',
    settingsShowAccess: 'settings-show-access',
    settingsShowEpg: 'settings-show-epg',
    settingsEpgInterval: 'settings-epg-interval',
    settingsEventRequest: 'settings-event-request',
    settingsMonitorAnalyzeMax: 'settings-monitor-analyze-max',
    settingsPreviewMaxSessions: 'settings-preview-max-sessions',
    settingsPreviewIdleTimeout: 'settings-preview-idle-timeout',
    settingsPreviewTokenTtl: 'settings-preview-token-ttl',
    settingsLogMaxEntries: 'settings-log-max-entries',
    settingsLogRetentionSec: 'settings-log-retention-sec',
    settingsAccessLogMaxEntries: 'settings-access-log-max-entries',
    settingsAccessLogRetentionSec: 'settings-access-log-retention-sec',
    settingsObservabilityEnabled: 'settings-observability-enabled',
    settingsObservabilityLogsDays: 'settings-observability-logs-days',
    settingsObservabilityMetricsDays: 'settings-observability-metrics-days',
    settingsObservabilityRollup: 'settings-observability-rollup',
    settingsObservabilityOnDemand: 'settings-observability-on-demand',
    settingsWatchdogEnabled: 'settings-watchdog-enabled',
    settingsWatchdogCpu: 'settings-watchdog-cpu',
    settingsWatchdogRssMb: 'settings-watchdog-rss-mb',
    settingsWatchdogRssPct: 'settings-watchdog-rss-pct',
    settingsWatchdogInterval: 'settings-watchdog-interval',
    settingsWatchdogStrikes: 'settings-watchdog-strikes',
    settingsWatchdogUptime: 'settings-watchdog-uptime',
    settingsTelegramEnabled: 'settings-telegram-enabled',
    settingsTelegramLevel: 'settings-telegram-level',
    settingsTelegramToken: 'settings-telegram-token',
    settingsTelegramTokenHint: 'settings-telegram-token-hint',
    settingsTelegramChatId: 'settings-telegram-chat-id',
    settingsTelegramTest: 'settings-telegram-test',
    settingsTelegramBackupEnabled: 'settings-telegram-backup-enabled',
    settingsTelegramBackupSchedule: 'settings-telegram-backup-schedule',
    settingsTelegramBackupTime: 'settings-telegram-backup-time',
    settingsTelegramBackupWeekday: 'settings-telegram-backup-weekday',
    settingsTelegramBackupMonthday: 'settings-telegram-backup-monthday',
    settingsTelegramBackupSecrets: 'settings-telegram-backup-secrets',
    settingsTelegramBackupWeekdayField: 'settings-telegram-backup-weekday-field',
    settingsTelegramBackupMonthdayField: 'settings-telegram-backup-monthday-field',
    settingsTelegramBackupNow: 'settings-telegram-backup-now',
    settingsTelegramSummaryEnabled: 'settings-telegram-summary-enabled',
    settingsTelegramSummarySchedule: 'settings-telegram-summary-schedule',
    settingsTelegramSummaryTime: 'settings-telegram-summary-time',
    settingsTelegramSummaryWeekday: 'settings-telegram-summary-weekday',
    settingsTelegramSummaryMonthday: 'settings-telegram-summary-monthday',
    settingsTelegramSummaryCharts: 'settings-telegram-summary-charts',
    settingsTelegramSummaryWeekdayField: 'settings-telegram-summary-weekday-field',
    settingsTelegramSummaryMonthdayField: 'settings-telegram-summary-monthday-field',
    settingsTelegramSummaryNow: 'settings-telegram-summary-now',
    settingsAiEnabled: 'settings-ai-enabled',
    settingsAiApiKey: 'settings-ai-api-key',
    settingsAiApiKeyHint: 'settings-ai-api-key-hint',
    settingsAiApiBase: 'settings-ai-api-base',
    settingsAiModel: 'settings-ai-model',
    settingsAiModelHint: 'settings-ai-model-hint',
    settingsAiChartMode: 'settings-ai-chart-mode',
    settingsAiMaxTokens: 'settings-ai-max-tokens',
    settingsAiTemperature: 'settings-ai-temperature',
    settingsAiAllowedChats: 'settings-ai-allowed-chats',
    settingsAiStore: 'settings-ai-store',
    settingsAiAllowApply: 'settings-ai-allow-apply',
    settingsInfluxEnabled: 'settings-influx-enabled',
    settingsInfluxUrl: 'settings-influx-url',
    settingsInfluxOrg: 'settings-influx-org',
    settingsInfluxBucket: 'settings-influx-bucket',
    settingsInfluxToken: 'settings-influx-token',
    settingsInfluxInstance: 'settings-influx-instance',
    settingsInfluxMeasurement: 'settings-influx-measurement',
    settingsInfluxInterval: 'settings-influx-interval',
    settingsFfmpegPath: 'settings-ffmpeg-path',
    settingsFfprobePath: 'settings-ffprobe-path',
    settingsHttpsBridgeEnabled: 'settings-https-bridge-enabled',
    settingsHttpCsrf: 'settings-http-csrf',
    settingsShowSecurityLimits: 'settings-show-security-limits',
    settingsAuthSessionTtl: 'settings-auth-session-ttl',
    settingsLoginRateLimit: 'settings-login-rate-limit',
    settingsLoginRateWindow: 'settings-login-rate-window',
    settingsShowStreamDefaults: 'settings-show-stream-defaults',
    settingsDefaultNoDataTimeout: 'settings-default-no-data-timeout',
    settingsDefaultProbeInterval: 'settings-default-probe-interval',
    settingsDefaultStableOk: 'settings-default-stable-ok',
    settingsDefaultBackupInitial: 'settings-default-backup-initial',
    settingsDefaultBackupStart: 'settings-default-backup-start',
    settingsDefaultBackupReturn: 'settings-default-backup-return',
    settingsDefaultBackupStop: 'settings-default-backup-stop',
    settingsDefaultBackupWarmMax: 'settings-default-backup-warm-max',
    settingsDefaultHttpKeepActive: 'settings-default-http-keep-active',
  };
  Object.entries(map).forEach(([key, id]) => {
    elements[key] = document.getElementById(id);
  });
}

function renderGeneralSettings() {
  if (!elements.settingsGeneralRoot) return;
  const root = elements.settingsGeneralRoot;
  root.innerHTML = '';

  state.generalSearchEls = [];
  state.generalCards = [];
  state.generalSectionEls = {};

  const header = renderSettingsHeader();
  const body = createEl('div', 'settings-general-body');
  const sidebarColumn = createEl('div', 'settings-sidebar-column');
  const sidebarSelect = renderSidebarSelect(SETTINGS_GENERAL_SECTIONS);
  const sidebar = renderSidebarNav(SETTINGS_GENERAL_SECTIONS);
  sidebarColumn.append(sidebarSelect, sidebar);

  const content = createEl('div', 'settings-general-content');
  SETTINGS_GENERAL_SECTIONS.forEach((section) => {
    const sectionEl = renderSection(section);
    content.appendChild(sectionEl);
    state.generalSectionEls[section.id] = sectionEl;
  });

  body.append(sidebarColumn, content);
  const actionBar = renderSettingsActionBar();

  root.append(header, body, actionBar);
  bindGeneralElements();
  state.generalRendered = true;

  if (elements.settingsGeneralSearch) {
    elements.settingsGeneralSearch.value = state.generalSearchQuery;
  }
  setGeneralMode(state.generalMode, { persist: false });
  setGeneralDensity(state.generalCompact, { persist: false });
  updateGeneralCardSummaries();
  updateGeneralCardStates();
  applySearchFilter(state.generalSearchQuery);
  if (SETTINGS_GENERAL_SECTIONS.length) {
    setActiveGeneralNav(SETTINGS_GENERAL_SECTIONS[0].id);
  }
  observeGeneralSections();
}

function setGeneralMode(mode, options = {}) {
  const next = mode === 'advanced' ? 'advanced' : 'basic';
  state.generalMode = next;
  if (options.persist !== false) {
    localStorage.setItem(SETTINGS_ADVANCED_KEY, next === 'advanced' ? '1' : '0');
  }
  if (elements.settingsGeneralMode) {
    $$('#settings-general-mode button').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.mode === next);
    });
  }
  applySearchFilter(state.generalSearchQuery);
}

function setGeneralDensity(compact, options = {}) {
  state.generalCompact = !!compact;
  if (options.persist !== false) {
    localStorage.setItem(SETTINGS_DENSITY_KEY, state.generalCompact ? '1' : '0');
  }
  if (elements.settingsGeneralDensity) {
    elements.settingsGeneralDensity.checked = state.generalCompact;
  }
  if (elements.settingsGeneralRoot) {
    elements.settingsGeneralRoot.classList.toggle('is-compact', state.generalCompact);
  }
}

function setActiveGeneralNav(sectionId) {
  state.generalActiveSection = sectionId;
  if (elements.settingsGeneralNav) {
    $$('#settings-general-nav button').forEach((btn) => {
      btn.classList.toggle('active', btn.dataset.section === sectionId);
    });
  }
  if (elements.settingsGeneralNavSelect) {
    elements.settingsGeneralNavSelect.value = sectionId;
  }
}

function scrollToGeneralSection(sectionId) {
  const sectionEl = state.generalSectionEls[sectionId];
  if (!sectionEl) return;
  sectionEl.scrollIntoView({ behavior: 'smooth', block: 'start' });
  setActiveGeneralNav(sectionId);
}

function updateActiveGeneralNavFromVisibility() {
  const nextSection = SETTINGS_GENERAL_SECTIONS.find((section) => {
    const el = state.generalSectionEls[section.id];
    return el && !el.classList.contains('hidden');
  });
  if (nextSection) {
    setActiveGeneralNav(nextSection.id);
  }
}

function observeGeneralSections() {
  if (!('IntersectionObserver' in window)) return;
  if (state.generalObserver) {
    state.generalObserver.disconnect();
  }
  state.generalObserver = new IntersectionObserver((entries) => {
    const visible = entries
      .filter((entry) => entry.isIntersecting && !entry.target.classList.contains('hidden'))
      .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
    if (!visible.length) return;
    const nextId = visible[0].target.dataset.section;
    if (nextId && nextId !== state.generalActiveSection) {
      setActiveGeneralNav(nextId);
    }
  }, {
    root: null,
    rootMargin: '-20% 0px -70% 0px',
    threshold: [0, 0.1, 0.5],
  });
  Object.values(state.generalSectionEls).forEach((sectionEl) => {
    if (sectionEl) state.generalObserver.observe(sectionEl);
  });
}

function evaluateFieldDependency(dep) {
  if (!dep) return true;
  if (typeof dep === 'function') return !!dep();
  if (typeof dep === 'object' && dep.id) {
    const el = document.getElementById(dep.id);
    if (!el) return true;
    const current = el.type === 'checkbox' ? el.checked : el.value;
    if (Array.isArray(dep.value)) {
      return dep.value.map(String).includes(String(current));
    }
    return current === dep.value;
  }
  return true;
}

function setCardOpen(cardState, open, options = {}) {
  const shouldOpen = !!open;
  cardState.bodyEl.hidden = !shouldOpen;
  const toggleBtn = cardState.cardEl.querySelector('[data-action="card-toggle"]');
  if (toggleBtn) {
    toggleBtn.textContent = shouldOpen ? 'Свернуть' : 'Настроить';
    toggleBtn.setAttribute('aria-expanded', shouldOpen ? 'true' : 'false');
  }
  if (!options.force) {
    state.generalCardOpen[cardState.id] = shouldOpen;
  }
}

function updateGeneralCardStates() {
  if (!state.generalRendered) return;
  state.generalCards.forEach((card) => {
    const disableCard = card.card.toggle && card.card.toggle.disableCard !== false;
    const enabled = !disableCard || !card.toggleInput || card.toggleInput.checked;
    card.cardEl.classList.toggle('is-disabled', disableCard && !enabled);
    if (disableCard) {
      const inputs = card.bodyEl.querySelectorAll('input, select, textarea, button');
      inputs.forEach((input) => {
        input.disabled = !enabled;
      });
    }
  });
}

function updateGeneralCardSummaries() {
  if (!state.generalRendered) return;
  state.generalCards.forEach((card) => {
    if (!card.summaryEl) return;
    if (typeof card.card.summary === 'function') {
      card.summaryEl.textContent = card.card.summary();
    } else {
      card.summaryEl.textContent = '';
    }
  });
}

function serializeGeneralSettings(payload) {
  const keys = Object.keys(payload || {}).sort();
  const normalized = {};
  keys.forEach((key) => {
    normalized[key] = payload[key];
  });
  return JSON.stringify(normalized);
}

function computeDirtyState(options = {}) {
  if (!state.generalRendered) return { dirty: false, error: '' };
  let payload = null;
  let error = '';
  try {
    payload = collectGeneralSettings();
  } catch (err) {
    error = err.message || 'Ошибка в настройках';
  }
  if (options.resetSnapshot && payload) {
    state.generalSnapshot = serializeGeneralSettings(payload);
  }
  const snapshot = state.generalSnapshot || '';
  const current = payload ? serializeGeneralSettings(payload) : snapshot;
  const dirty = payload ? current !== snapshot : true;
  state.generalDirty = dirty;

  if (elements.settingsGeneralDirty) {
    elements.settingsGeneralDirty.classList.toggle('hidden', !dirty);
  }
  if (elements.settingsActionBar) {
    elements.settingsActionBar.classList.toggle('is-disabled', !dirty);
  }
  if (elements.settingsActionSave) {
    elements.settingsActionSave.disabled = !dirty || !!error;
  }
  if (elements.settingsActionCancel) {
    elements.settingsActionCancel.disabled = !dirty;
  }
  if (elements.settingsActionReset) {
    elements.settingsActionReset.disabled = !dirty;
  }
  if (elements.settingsActionStatus) {
    if (error) {
      elements.settingsActionStatus.textContent = `Исправьте ошибки: ${error}`;
    } else if (dirty) {
      elements.settingsActionStatus.textContent = 'Есть несохранённые изменения';
    } else {
      elements.settingsActionStatus.textContent = 'Нет несохранённых изменений';
    }
  }
  return { dirty, error };
}

function applySearchFilter(query) {
  if (!state.generalRendered) return;
  state.generalSearchQuery = String(query || '');
  const tokens = buildSearchTokens(state.generalSearchQuery);

  state.generalSearchEls.forEach((entry) => {
    entry.el.innerHTML = highlightText(entry.text, tokens);
  });

  state.generalCards.forEach((card) => {
    const cardModeVisible = state.generalMode === 'advanced' || card.level !== 'advanced';
    const cardMatchesSelf = matchesSearch(card.searchSelf, tokens);

    let anyFieldMatches = false;
    card.fields.forEach((field) => {
      field.matchesSearch = matchesSearch(field.searchText, tokens);
      if (field.matchesSearch) anyFieldMatches = true;
    });

    card.fields.forEach((field) => {
      const depVisible = evaluateFieldDependency(field.def.dependsOn);
      const modeVisible = state.generalMode === 'advanced' || field.level !== 'advanced';
      let searchVisible = true;
      if (tokens.length) {
        if (anyFieldMatches) {
          searchVisible = field.matchesSearch;
        } else {
          searchVisible = cardMatchesSelf;
        }
      }
      const visible = depVisible && modeVisible && searchVisible;
      field.el.hidden = !visible;
    });

    const anyVisibleField = card.fields.some((field) => !field.el.hidden);
    const searchMatch = tokens.length ? (cardMatchesSelf || anyFieldMatches) : true;
    const cardVisible = cardModeVisible && searchMatch && anyVisibleField;
    card.cardEl.classList.toggle('hidden', !cardVisible);

    const forceOpen = tokens.length ? cardVisible : false;
    const openState = forceOpen || !card.card.collapsible || !!state.generalCardOpen[card.id];
    setCardOpen(card, openState, { force: forceOpen });
  });

  Object.entries(state.generalSectionEls).forEach(([sectionId, sectionEl]) => {
    const hasVisible = state.generalCards.some(
      (card) => card.sectionId === sectionId && !card.cardEl.classList.contains('hidden')
    );
    sectionEl.classList.toggle('hidden', !hasVisible);
  });

  if (tokens.length) {
    updateActiveGeneralNavFromVisibility();
  } else if (!state.generalActiveSection) {
    updateActiveGeneralNavFromVisibility();
  }
}

function syncGeneralSettingsUi(options = {}) {
  updateGeneralCardStates();
  updateGeneralCardSummaries();
  applySearchFilter(state.generalSearchQuery);
  computeDirtyState({ resetSnapshot: options.resetSnapshot });
}

function openAiApplyConfirm(target) {
  if (!elements.aiApplyConfirmOverlay) return;
  state.aiApplyConfirmTarget = target || null;
  state.aiApplyConfirmPending = true;
  setOverlay(elements.aiApplyConfirmOverlay, true);
}

function closeAiApplyConfirm() {
  if (!elements.aiApplyConfirmOverlay) return;
  setOverlay(elements.aiApplyConfirmOverlay, false);
}

function confirmAiApplyChange(allow) {
  const target = state.aiApplyConfirmTarget;
  state.aiApplyConfirmTarget = null;
  state.aiApplyConfirmPending = false;
  if (target && !allow) {
    target.checked = false;
  }
  closeAiApplyConfirm();
  syncGeneralSettingsUi();
}

function handleGeneralInputChange(event) {
  const target = event.target;
  if (!target || !target.id) return;
  if (target.id === 'settings-general-search') return;
  if (target.id === 'settings-general-density') return;

  if (target.id === 'settings-ai-allow-apply' && target.checked) {
    if (state.aiApplyConfirmPending) return;
    openAiApplyConfirm(target);
    return;
  }

  syncGeneralSettingsUi();
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function setStatus(message, mode) {
  if (!message) {
    elements.status.classList.remove('active');
    elements.status.textContent = '';
    return;
  }
  elements.status.textContent = message;
  elements.status.classList.add('active');
  if (mode !== 'sticky') {
    setTimeout(() => setStatus(''), 3000);
  }
}

function showDashboardNotice(message, ttl) {
  if (!elements.dashboardNotice) return;
  if (state.dashboardNoticeTimer) {
    clearTimeout(state.dashboardNoticeTimer);
    state.dashboardNoticeTimer = null;
  }
  if (!message) {
    elements.dashboardNotice.classList.remove('active');
    elements.dashboardNotice.textContent = '';
    return;
  }
  elements.dashboardNotice.textContent = message;
  elements.dashboardNotice.classList.add('active');
  const timeout = Number.isFinite(ttl) ? ttl : 6000;
  if (timeout > 0) {
    state.dashboardNoticeTimer = setTimeout(() => {
      state.dashboardNoticeTimer = null;
      showDashboardNotice('');
    }, timeout);
  }
}

function setStreamEditorBusy(isBusy, label) {
  if (elements.btnApplyStream) {
    elements.btnApplyStream.disabled = isBusy;
    elements.btnApplyStream.textContent = isBusy ? (label || 'Saving...') : 'Save';
  }
  if (elements.btnDelete) elements.btnDelete.disabled = isBusy;
  if (elements.btnClone) elements.btnClone.disabled = isBusy;
  if (elements.btnAnalyze) elements.btnAnalyze.disabled = isBusy;
  if (isBusy && elements.editorError) {
    elements.editorError.textContent = label || 'Saving...';
  }
}

function setOverlay(overlay, show) {
  overlay.classList.toggle('active', show);
  overlay.setAttribute('aria-hidden', show ? 'false' : 'true');
}

function setView(name) {
  if (state.currentView === 'settings' && name !== 'settings' && state.generalDirty) {
    const proceed = window.confirm('Есть несохранённые изменения в Settings → General. Перейти без сохранения?');
    if (!proceed) return;
  }
  state.currentView = name;
  elements.views.forEach((view) => {
    view.classList.toggle('active', view.id === `view-${name}`);
  });
  elements.navLinks.forEach((item) => {
    item.classList.toggle('active', item.dataset.view === name);
  });
  if (name !== 'settings') {
    closeSettingsMenu();
    stopServerStatusPolling();
  }
  if (name === 'adapters') {
    loadDvbAdapters().catch(() => {});
    if (!document.hidden) {
      startDvbPolling();
    }
  } else {
    stopDvbPolling();
  }
  if (name === 'observability') {
    updateObservabilityStreamOptions();
    updateObservabilityScopeFields();
    loadObservability(true);
  }
  syncPollingForView();
}

function openSettingsMenu() {
  elements.settingsMenu.classList.add('open');
  elements.settingsMenu.setAttribute('aria-hidden', 'false');
}

function closeSettingsMenu() {
  elements.settingsMenu.classList.remove('open');
  elements.settingsMenu.setAttribute('aria-hidden', 'true');
}

function toggleSettingsMenu() {
  if (elements.settingsMenu.classList.contains('open')) {
    closeSettingsMenu();
  } else {
    openSettingsMenu();
  }
}

function setSettingsSection(section) {
  const sectionEl = document.querySelector(`.settings-section[data-section="${section}"]`);
  const menuEl = elements.settingsItems.find((item) => item.dataset.section === section);
  if (!sectionEl || sectionEl.hidden || (menuEl && menuEl.hidden)) {
    section = 'general';
  }
  state.settingsSection = section;
  $$('.settings-section').forEach((item) => {
    item.classList.toggle('active', item.dataset.section === section);
  });
  elements.settingsItems.forEach((item) => {
    item.classList.toggle('active', item.dataset.section === section);
  });
  if (section === 'config-history') {
    loadConfigHistory();
  }
  if (section === 'edit-config') {
    if (!state.configEditorLoaded) {
      loadFullConfig(false);
    }
  }
  if (section === 'license') {
    loadLicense();
  }
  if (section === 'servers') {
    startServerStatusPolling();
  } else {
    stopServerStatusPolling();
  }
}

function applyFeatureVisibility() {
  const showSplitter = isViewEnabled('splitters');
  const showBuffer = isViewEnabled('buffers');
  const showAccess = isViewEnabled('access');
  const helpEnabled = isViewEnabled('help');
  const showObservability = isViewEnabled('observability');

  const splitterNav = document.querySelector('.nav-link[data-view="splitters"]');
  const bufferNav = document.querySelector('.nav-link[data-view="buffers"]');
  const accessNav = document.querySelector('.nav-link[data-view="access"]');
  const helpNav = document.querySelector('.nav-link[data-view="help"]');
  const observabilityNav = document.querySelector('.nav-link[data-view="observability"]');
  if (splitterNav) splitterNav.hidden = !showSplitter;
  if (bufferNav) bufferNav.hidden = !showBuffer;
  if (accessNav) accessNav.hidden = !showAccess;
  if (helpNav) helpNav.hidden = !helpEnabled;
  if (observabilityNav) observabilityNav.hidden = !showObservability;

  const splitterView = document.querySelector('#view-splitters');
  const bufferView = document.querySelector('#view-buffers');
  const accessView = document.querySelector('#view-access');
  const helpView = document.querySelector('#view-help');
  const observabilityView = document.querySelector('#view-observability');
  if (splitterView) splitterView.hidden = !showSplitter;
  if (bufferView) bufferView.hidden = !showBuffer;
  if (accessView) accessView.hidden = !showAccess;
  if (helpView) helpView.hidden = !helpEnabled;
  if (observabilityView) observabilityView.hidden = !showObservability;

  const bufferSettingsItem = elements.settingsItems.find((item) => item.dataset.section === 'buffer');
  if (bufferSettingsItem) bufferSettingsItem.hidden = !showBuffer;

  if (!showBuffer && state.settingsSection === 'buffer') {
    setSettingsSection('general');
  }

  const activeView = document.querySelector('.view.active');
  if (activeView) {
    const activeId = activeView.id || '';
    if (
      (!showSplitter && activeId === 'view-splitters')
      || (!showBuffer && activeId === 'view-buffers')
      || (!showAccess && activeId === 'view-access')
      || (!helpEnabled && activeId === 'view-help')
      || (!showObservability && activeId === 'view-observability')
    ) {
      setView('streams');
    }
  }
}

function isViewEnabled(name) {
  if (name === 'splitters') return getSettingBool('ui_splitter_enabled', false);
  if (name === 'buffers') return getSettingBool('ui_buffer_enabled', false);
  if (name === 'access') return getSettingBool('ui_access_enabled', true);
  if (name === 'help') return getSettingBool('ai_enabled', false);
  if (name === 'observability') {
    const onDemand = getSettingBool('ai_metrics_on_demand', true);
    const logsDays = getSettingNumber('ai_logs_retention_days', 0);
    const metricsDays = getSettingNumber('ai_metrics_retention_days', 0);
    return logsDays > 0 || (!onDemand && metricsDays > 0);
  }
  return true;
}

function toNumber(value) {
  if (value === null || value === undefined) return undefined;
  if (typeof value === 'string' && value.trim() === '') return undefined;
  const num = Number(value);
  return Number.isFinite(num) ? num : undefined;
}

function parseCommaList(value) {
  if (!value) return [];
  if (Array.isArray(value)) {
    return value.map((item) => String(item)).filter(Boolean);
  }
  return String(value)
    .split(/[\s,]+/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function formatCommaList(values) {
  return (values || []).filter(Boolean).join(', ');
}

function debounce(fn, delay = 250) {
  let timer = null;
  return (...args) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => {
      timer = null;
      fn(...args);
    }, delay);
  };
}

function slugifyStreamId(name) {
  const source = String(name || '').toLowerCase();
  let slug = source.replace(/[^a-z0-9_-]+/g, '_');
  slug = slug.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug) {
    slug = `stream_${Date.now()}`;
  }
  return slug;
}

function slugifyGroupId(name) {
  const source = String(name || '').toLowerCase();
  let slug = source.replace(/[^a-z0-9_-]+/g, '_');
  slug = slug.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug) {
    slug = `group_${Date.now()}`;
  }
  return slug;
}

function normalizeGroups(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  value.forEach((entry) => {
    if (!entry) return;
    if (typeof entry === 'string') {
      const name = entry.trim();
      if (!name) return;
      out.push({ id: slugifyGroupId(name), name });
      return;
    }
    const id = String(entry.id || '').trim();
    const name = String(entry.name || '').trim();
    if (!id && !name) return;
    out.push({ id: id || slugifyGroupId(name), name: name || id });
  });
  return out;
}

function slugifyServerId(name) {
  const source = String(name || '').toLowerCase();
  let slug = source.replace(/[^a-z0-9_-]+/g, '_');
  slug = slug.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug) {
    slug = `server_${Date.now()}`;
  }
  return slug;
}

function normalizeServers(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  value.forEach((entry) => {
    if (!entry) return;
    if (typeof entry === 'string') {
      const host = entry.trim();
      if (!host) return;
      const id = slugifyServerId(host);
      out.push({ id, name: host, host, enabled: true, type: 'streamer' });
      return;
    }
    const idRaw = String(entry.id || '').trim();
    const nameRaw = String(entry.name || '').trim();
    const hostRaw = String(entry.host || entry.address || '').trim();
    if (!idRaw && !nameRaw && !hostRaw) return;
    const id = idRaw || slugifyServerId(nameRaw || hostRaw);
    const name = nameRaw || id;
    const port = entry.port !== undefined ? Number(entry.port) : undefined;
    const enabled = entry.enabled !== undefined ? entry.enabled !== false : entry.enable !== false;
    const login = entry.login || entry.user || '';
    const password = entry.password || entry.pass || '';
    const type = entry.type || '';
    out.push({
      id,
      name,
      host: hostRaw,
      port: Number.isFinite(port) ? port : undefined,
      login,
      password,
      enabled,
      type,
      enable: entry.enable,
      user: entry.user,
      pass: entry.pass,
    });
  });
  return out;
}

function slugifySoftcamId(name) {
  const source = String(name || '').toLowerCase();
  let slug = source.replace(/[^a-z0-9_-]+/g, '_');
  slug = slug.replace(/_+/g, '_').replace(/^_+|_+$/g, '');
  if (!slug) {
    slug = `softcam_${Date.now()}`;
  }
  return slug;
}

function normalizeSoftcams(value) {
  if (!Array.isArray(value)) return [];
  const out = [];
  value.forEach((entry) => {
    if (!entry) return;
    if (typeof entry === 'string') {
      const name = entry.trim();
      if (!name) return;
      out.push({ id: slugifySoftcamId(name), name, type: 'newcamd', host: name, enable: true });
      return;
    }
    const idRaw = String(entry.id || '').trim();
    const nameRaw = String(entry.name || '').trim();
    const typeRaw = String(entry.type || '').trim();
    const hostRaw = String(entry.host || '').trim();
    if (!idRaw && !nameRaw && !hostRaw) return;
    const id = idRaw || slugifySoftcamId(nameRaw || hostRaw || typeRaw || 'softcam');
    const name = nameRaw || id;
    const port = entry.port !== undefined ? Number(entry.port) : undefined;
    const enableVal = entry.enable !== undefined ? entry.enable : entry.enabled;
    const enabled = enableVal === undefined ? true : (enableVal === true || enableVal === 1 || enableVal === '1');
    const disableEmm = entry.disable_emm === true || entry.disable_emm === 1 || entry.disable_emm === '1';
    const splitCam = entry.split_cam === true || entry.split_cam === 1 || entry.split_cam === '1';
    const shift = entry.shift !== undefined && entry.shift !== null ? String(entry.shift) : '';
    const comment = entry.comment ? String(entry.comment) : '';
    out.push({
      id,
      name,
      type: typeRaw,
      host: hostRaw,
      port: Number.isFinite(port) ? port : undefined,
      user: entry.user || '',
      pass: entry.pass || '',
      enable: enabled,
      disable_emm: disableEmm,
      split_cam: splitCam,
      shift,
      comment,
    });
  });
  return out;
}

function formatSoftcamOptionLabel(softcam) {
  if (!softcam) return '';
  const id = String(softcam.id || '');
  const name = String(softcam.name || '');
  let label = id;
  if (name && name !== id) {
    label = `${name} (${id})`;
  }
  if (softcam.enable === false) {
    label = `${label} [disabled]`;
  }
  return label;
}

function refreshInputCamOptions(selectedValue) {
  if (!elements.inputCamId) return;
  const select = elements.inputCamId;
  const desired = selectedValue !== undefined ? String(selectedValue || '') : String(select.value || '');
  const softcams = (Array.isArray(state.softcams) ? state.softcams : [])
    .slice()
    .sort((a, b) => {
      const al = (a.name || a.id || '').toLowerCase();
      const bl = (b.name || b.id || '').toLowerCase();
      return al.localeCompare(bl);
    });

  const fragment = document.createDocumentFragment();
  const addOption = (value, label, disabled) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = label;
    if (disabled) option.disabled = true;
    fragment.appendChild(option);
    return option;
  };

  addOption('', 'None');
  let hasSelected = false;
  softcams.forEach((softcam) => {
    const id = softcam && softcam.id ? String(softcam.id) : '';
    if (!id) return;
    addOption(id, formatSoftcamOptionLabel(softcam));
    if (id === desired) {
      hasSelected = true;
    }
  });

  if (desired && !hasSelected) {
    addOption(desired, `Unknown: ${desired}`);
    hasSelected = true;
  }

  select.replaceChildren(fragment);
  select.value = hasSelected ? desired : '';
}

function getSettingNumber(key, fallback) {
  const value = Number(state.settings[key]);
  return Number.isFinite(value) ? value : fallback;
}

function getSettingString(key, fallback) {
  const value = state.settings[key];
  if (value === null || value === undefined || value === '') {
    return fallback;
  }
  return String(value);
}

function getSettingBool(key, fallback) {
  const value = state.settings[key];
  if (value === null || value === undefined) {
    return fallback;
  }
  return value === true || value === 1 || value === '1';
}

function hasSettingValue(key) {
  if (!state.settings) return false;
  if (!Object.prototype.hasOwnProperty.call(state.settings, key)) {
    return false;
  }
  const value = state.settings[key];
  return value !== undefined && value !== null && value !== '';
}

function syncToggleTargets() {
  $$('[data-toggle-target]').forEach((toggle) => {
    const targetId = toggle.dataset.toggleTarget;
    if (!targetId) return;
    const target = document.getElementById(targetId);
    if (!target) return;
    target.hidden = !toggle.checked;
  });
}


function bindToggleTargets() {
  $$('[data-toggle-target]').forEach((toggle) => {
    toggle.addEventListener('change', () => {
      if (toggle.id === 'settings-show-advanced') {
        localStorage.setItem(SETTINGS_ADVANCED_KEY, toggle.checked ? '1' : '0');
      }
      syncToggleTargets();
    });
  });
  syncToggleTargets();
}

function updateTelegramBackupScheduleFields() {
  if (!elements.settingsTelegramBackupSchedule) return;
  const schedule = elements.settingsTelegramBackupSchedule.value || 'DAILY';
  if (elements.settingsTelegramBackupWeekdayField) {
    elements.settingsTelegramBackupWeekdayField.hidden = schedule !== 'WEEKLY';
  }
  if (elements.settingsTelegramBackupMonthdayField) {
    elements.settingsTelegramBackupMonthdayField.hidden = schedule !== 'MONTHLY';
  }
}

function updateTelegramSummaryScheduleFields() {
  if (!elements.settingsTelegramSummarySchedule) return;
  const schedule = elements.settingsTelegramSummarySchedule.value || 'DAILY';
  if (elements.settingsTelegramSummaryWeekdayField) {
    elements.settingsTelegramSummaryWeekdayField.hidden = schedule !== 'WEEKLY';
  }
  if (elements.settingsTelegramSummaryMonthdayField) {
    elements.settingsTelegramSummaryMonthdayField.hidden = schedule !== 'MONTHLY';
  }
}

function updateStreamGroupOptions() {
  if (!elements.streamGroupList) return;
  elements.streamGroupList.innerHTML = '';
  const groups = Array.isArray(state.groups) ? state.groups : [];
  groups.forEach((group) => {
    if (!group || !group.id) return;
    const option = document.createElement('option');
    option.value = group.id;
    option.label = group.name ? `${group.name} (${group.id})` : group.id;
    elements.streamGroupList.appendChild(option);
  });
}

function renderGroups() {
  if (!elements.groupTable || !elements.groupEmpty) return;
  const header = `
    <div class="table-row header">
      <div>ID</div>
      <div>Name</div>
      <div></div>
    </div>
  `;
  elements.groupTable.innerHTML = header;

  const groups = (Array.isArray(state.groups) ? state.groups : [])
    .slice()
    .sort((a, b) => {
      const al = (a.name || a.id || '').toLowerCase();
      const bl = (b.name || b.id || '').toLowerCase();
      return al.localeCompare(bl);
    });

  if (!groups.length) {
    elements.groupEmpty.hidden = false;
    return;
  }
  elements.groupEmpty.hidden = true;

  groups.forEach((group) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const idCell = createEl('div', '', group.id || '');
    const nameCell = createEl('div', '', group.name || '');
    const actionCell = document.createElement('div');

    const editBtn = createEl('button', 'btn ghost', 'Edit');
    editBtn.type = 'button';
    editBtn.dataset.action = 'group-edit';
    editBtn.dataset.id = group.id || '';

    const deleteBtn = createEl('button', 'btn ghost', 'Delete');
    deleteBtn.type = 'button';
    deleteBtn.dataset.action = 'group-delete';
    deleteBtn.dataset.id = group.id || '';

    actionCell.appendChild(editBtn);
    actionCell.appendChild(deleteBtn);
    row.appendChild(idCell);
    row.appendChild(nameCell);
    row.appendChild(actionCell);
    elements.groupTable.appendChild(row);
  });
}

function renderSoftcams() {
  if (!elements.softcamTable || !elements.softcamEmpty) return;
  const header = `
    <div class="table-row header">
      <div>ID</div>
      <div>Name</div>
      <div>Type</div>
      <div>Address</div>
      <div>User</div>
      <div>Status</div>
      <div></div>
    </div>
  `;
  elements.softcamTable.innerHTML = header;

  const softcams = (Array.isArray(state.softcams) ? state.softcams : [])
    .slice()
    .sort((a, b) => {
      const al = (a.name || a.id || '').toLowerCase();
      const bl = (b.name || b.id || '').toLowerCase();
      return al.localeCompare(bl);
    });

  if (!softcams.length) {
    elements.softcamEmpty.hidden = false;
    return;
  }
  elements.softcamEmpty.hidden = true;

  softcams.forEach((softcam) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const idCell = createEl('div', '', softcam.id || '');
    const nameCell = createEl('div', '', softcam.name || '');
    const typeCell = createEl('div', '', softcam.type || '-');
    const address = softcam.host ? `${softcam.host}${softcam.port ? `:${softcam.port}` : ''}` : '-';
    const hostCell = createEl('div', '', address);
    const userCell = createEl('div', '', softcam.user || '-');
    const statusCell = createEl('div', '', softcam.enable !== false ? 'Enabled' : 'Disabled');
    const actionCell = document.createElement('div');

    const editBtn = createEl('button', 'btn ghost', 'Edit');
    editBtn.type = 'button';
    editBtn.dataset.action = 'softcam-edit';
    editBtn.dataset.id = softcam.id || '';

    const deleteBtn = createEl('button', 'btn ghost', 'Delete');
    deleteBtn.type = 'button';
    deleteBtn.dataset.action = 'softcam-delete';
    deleteBtn.dataset.id = softcam.id || '';

    actionCell.appendChild(editBtn);
    actionCell.appendChild(deleteBtn);

    row.appendChild(idCell);
    row.appendChild(nameCell);
    row.appendChild(typeCell);
    row.appendChild(hostCell);
    row.appendChild(userCell);
    row.appendChild(statusCell);
    row.appendChild(actionCell);
    elements.softcamTable.appendChild(row);
  });
}

function openSoftcamModal(softcam) {
  state.softcamEditing = softcam ? { ...softcam } : null;
  state.softcamIdAuto = !softcam;
  if (elements.softcamTitle) {
    elements.softcamTitle.textContent = softcam ? 'Edit softcam' : 'New softcam';
  }
  if (elements.softcamEnabled) elements.softcamEnabled.checked = softcam ? softcam.enable !== false : true;
  if (elements.softcamId) elements.softcamId.value = softcam ? softcam.id || '' : '';
  if (elements.softcamName) elements.softcamName.value = softcam ? softcam.name || '' : '';
  if (elements.softcamType) elements.softcamType.value = softcam ? softcam.type || '' : '';
  if (elements.softcamHost) elements.softcamHost.value = softcam ? softcam.host || '' : '';
  if (elements.softcamPort) elements.softcamPort.value = softcam && softcam.port ? String(softcam.port) : '';
  if (elements.softcamUser) elements.softcamUser.value = softcam ? softcam.user || '' : '';
  if (elements.softcamPass) elements.softcamPass.value = '';
  if (elements.softcamPassHint) {
    elements.softcamPassHint.textContent = softcam && softcam.pass ? 'Password set (stored)' : 'Password not set';
  }
  if (elements.softcamDisableEmm) elements.softcamDisableEmm.checked = softcam ? !!softcam.disable_emm : false;
  if (elements.softcamSplitCam) elements.softcamSplitCam.checked = softcam ? !!softcam.split_cam : false;
  if (elements.softcamShift) elements.softcamShift.value = softcam && softcam.shift ? String(softcam.shift) : '';
  if (elements.softcamComment) elements.softcamComment.value = softcam ? softcam.comment || '' : '';
  if (elements.softcamError) elements.softcamError.textContent = '';
  setOverlay(elements.softcamOverlay, true);
}

function closeSoftcamModal() {
  state.softcamEditing = null;
  state.softcamIdAuto = false;
  setOverlay(elements.softcamOverlay, false);
}

function openGroupModal(group) {
  state.groupEditing = group ? { ...group } : null;
  state.groupIdAuto = !group;
  if (elements.groupTitle) {
    elements.groupTitle.textContent = group ? 'Edit group' : 'New group';
  }
  if (elements.groupId) {
    elements.groupId.value = group ? group.id || '' : '';
  }
  if (elements.groupName) {
    elements.groupName.value = group ? group.name || '' : '';
  }
  if (elements.groupError) {
    elements.groupError.textContent = '';
  }
  setOverlay(elements.groupOverlay, true);
}

function closeGroupModal() {
  state.groupEditing = null;
  state.groupIdAuto = false;
  setOverlay(elements.groupOverlay, false);
}

function renderServers() {
  if (!elements.serverTable || !elements.serverEmpty) return;
  const header = `
    <div class="table-row header">
      <div>ID</div>
      <div>Name</div>
      <div>Type</div>
      <div>Address</div>
      <div>Login</div>
      <div>Status</div>
      <div></div>
    </div>
  `;
  elements.serverTable.innerHTML = header;

  const servers = (Array.isArray(state.servers) ? state.servers : [])
    .slice()
    .sort((a, b) => {
      const al = (a.name || a.id || '').toLowerCase();
      const bl = (b.name || b.id || '').toLowerCase();
      return al.localeCompare(bl);
    });

  if (!servers.length) {
    elements.serverEmpty.hidden = false;
    return;
  }
  elements.serverEmpty.hidden = true;

  servers.forEach((server) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const idCell = createEl('div', '', server.id || '');
    const nameCell = createEl('div', '', server.name || '');
    const typeCell = createEl('div', '', server.type || '-');
    const address = server.host ? `${server.host}${server.port ? `:${server.port}` : ''}` : '';
    const hostCell = createEl('div', '', address || '-');
    const loginCell = createEl('div', '', server.login || '-');
    const statusCell = document.createElement('div');
    const statusInfo = getServerStatusInfo(server);
    const statusBadge = document.createElement('div');
    statusBadge.className = `stream-status-badge ${statusInfo.className}`;
    statusBadge.title = statusInfo.title || '';
    const statusDot = createEl('span', 'stream-status-dot');
    const statusText = createEl('span', '', statusInfo.label);
    statusBadge.appendChild(statusDot);
    statusBadge.appendChild(statusText);
    statusCell.appendChild(statusBadge);
    const actionCell = document.createElement('div');

    const editBtn = createEl('button', 'btn ghost', 'Edit');
    editBtn.type = 'button';
    editBtn.dataset.action = 'server-edit';
    editBtn.dataset.id = server.id || '';

    const openBtn = createEl('button', 'btn ghost', 'Open');
    openBtn.type = 'button';
    openBtn.dataset.action = 'server-open';
    openBtn.dataset.id = server.id || '';

    const testBtn = createEl('button', 'btn ghost', 'Test');
    testBtn.type = 'button';
    testBtn.dataset.action = 'server-test';
    testBtn.dataset.id = server.id || '';

    const pullBtn = createEl('button', 'btn ghost', 'Pull streams');
    pullBtn.type = 'button';
    pullBtn.dataset.action = 'server-pull';
    pullBtn.dataset.id = server.id || '';

    const importBtn = createEl('button', 'btn ghost', 'Import config');
    importBtn.type = 'button';
    importBtn.dataset.action = 'server-import';
    importBtn.dataset.id = server.id || '';

    const deleteBtn = createEl('button', 'btn ghost', 'Delete');
    deleteBtn.type = 'button';
    deleteBtn.dataset.action = 'server-delete';
    deleteBtn.dataset.id = server.id || '';

    actionCell.appendChild(editBtn);
    actionCell.appendChild(openBtn);
    actionCell.appendChild(testBtn);
    actionCell.appendChild(pullBtn);
    actionCell.appendChild(importBtn);
    actionCell.appendChild(deleteBtn);

    row.appendChild(idCell);
    row.appendChild(nameCell);
    row.appendChild(typeCell);
    row.appendChild(hostCell);
    row.appendChild(loginCell);
    row.appendChild(statusCell);
    row.appendChild(actionCell);
    elements.serverTable.appendChild(row);
  });
}

function openServerModal(server) {
  state.serverEditing = server ? { ...server } : null;
  state.serverIdAuto = !server;
  if (elements.serverTitle) {
    elements.serverTitle.textContent = server ? 'Edit server' : 'New server';
  }
  if (elements.serverEnabled) elements.serverEnabled.checked = server ? server.enabled !== false : true;
  if (elements.serverId) elements.serverId.value = server ? server.id || '' : '';
  if (elements.serverName) elements.serverName.value = server ? server.name || '' : '';
  if (elements.serverType) elements.serverType.value = server ? server.type || '' : '';
  if (elements.serverHost) elements.serverHost.value = server ? server.host || '' : '';
  if (elements.serverPort) elements.serverPort.value = server && server.port ? String(server.port) : '';
  if (elements.serverLogin) elements.serverLogin.value = server ? (server.login || server.user || '') : '';
  if (elements.serverPassword) elements.serverPassword.value = '';
  if (elements.serverPasswordHint) {
    elements.serverPasswordHint.textContent = server && (server.password || server.pass)
      ? 'Password set (stored)'
      : 'Password not set';
  }
  if (elements.serverError) elements.serverError.textContent = '';
  setOverlay(elements.serverOverlay, true);
}

function closeServerModal() {
  state.serverEditing = null;
  state.serverIdAuto = false;
  setOverlay(elements.serverOverlay, false);
}

function getServerStatusInfo(server) {
  if (!server || server.enabled === false) {
    return { label: 'Disabled', className: 'disabled', title: '' };
  }
  const status = state.serverStatus && server.id ? state.serverStatus[server.id] : null;
  if (!status) {
    return { label: 'Pending', className: 'pending', title: '' };
  }
  if (status.ok) {
    return { label: 'OK', className: 'ok', title: status.message || '' };
  }
  return { label: 'Down', className: 'warn', title: status.message || '' };
}

async function loadServerStatus() {
  try {
    const data = await apiJson('/api/v1/servers/status');
    const items = Array.isArray(data) ? data : (data.items || []);
    const next = {};
    items.forEach((item) => {
      if (item && item.id) {
        next[item.id] = item;
      }
    });
    state.serverStatus = next;
    renderServers();
  } catch (err) {
  }
}

function startServerStatusPolling() {
  if (state.serverStatusTimer) {
    clearInterval(state.serverStatusTimer);
  }
  state.serverStatusTimer = setInterval(() => loadServerStatus(), POLL_SERVER_STATUS_MS);
  loadServerStatus();
}

function stopServerStatusPolling() {
  if (state.serverStatusTimer) {
    clearInterval(state.serverStatusTimer);
    state.serverStatusTimer = null;
  }
}

async function pullServerStreams(id) {
  if (!id) return;
  const confirmed = window.confirm('Pull streams from this server? Streams will be merged by ID.');
  if (!confirmed) return;
  setStatus('Pulling streams...', 'sticky');
  await apiJson('/api/v1/servers/pull-streams', {
    method: 'POST',
    body: JSON.stringify({ id }),
  });
  setStatus('Streams pulled');
  await refreshAll();
  setView('streams');
}

async function importServerConfig(id) {
  if (!id) return;
  const confirmed = window.confirm('Import configuration from this server? This will merge streams/adapters/softcam (users/settings are skipped).');
  if (!confirmed) return;
  setStatus('Importing config...', 'sticky');
  await apiJson('/api/v1/servers/import', {
    method: 'POST',
    body: JSON.stringify({ id, mode: 'merge' }),
  });
  setStatus('Config imported');
  await refreshAll();
  setView('streams');
}

function syncServerIdFromName() {
  if (!state.serverIdAuto) return;
  if (!elements.serverName || !elements.serverId) return;
  const name = elements.serverName.value.trim();
  const nextId = name ? slugifyServerId(name) : '';
  if (elements.serverId.value !== nextId) {
    elements.serverId.value = nextId;
  }
}

function handleServerIdInput() {
  if (!elements.serverId) return;
  const current = elements.serverId.value.trim();
  if (!current) {
    state.serverIdAuto = true;
    syncServerIdFromName();
    return;
  }
  state.serverIdAuto = false;
}

function handleServerNameInput() {
  syncServerIdFromName();
}

async function saveServer() {
  const id = elements.serverId ? elements.serverId.value.trim() : '';
  const name = elements.serverName ? elements.serverName.value.trim() : '';
  const type = elements.serverType ? elements.serverType.value.trim() : '';
  const host = elements.serverHost ? elements.serverHost.value.trim() : '';
  const port = toNumber(elements.serverPort && elements.serverPort.value);
  const login = elements.serverLogin ? elements.serverLogin.value.trim() : '';
  const password = elements.serverPassword ? elements.serverPassword.value : '';
  const enabled = elements.serverEnabled ? elements.serverEnabled.checked : true;
  if (!id) throw new Error('Server id is required');
  if (!name) throw new Error('Server name is required');
  if (!host) throw new Error('Server address is required');

  const servers = Array.isArray(state.servers) ? state.servers.slice() : [];
  const existingIdx = servers.findIndex((s) => s && s.id === id);
  if (state.serverEditing && state.serverEditing.id && state.serverEditing.id !== id) {
    if (existingIdx !== -1) {
      throw new Error(`Server id "${id}" already exists`);
    }
    const currentIdx = servers.findIndex((s) => s && s.id === state.serverEditing.id);
    if (currentIdx !== -1) {
      const existing = servers[currentIdx];
      servers[currentIdx] = {
        ...existing,
        id,
        name,
        host,
        port,
        login,
        user: login || existing.user || '',
        password: password || existing.password || existing.pass || '',
        pass: password || existing.pass || existing.password || '',
        enabled,
        enable: enabled,
        type: type || existing.type || '',
      };
    } else {
      servers.push({
        id,
        name,
        host,
        port,
        login,
        user: login,
        password,
        pass: password,
        enabled,
        enable: enabled,
        type: type || 'streamer',
      });
    }
  } else if (!state.serverEditing) {
    if (existingIdx !== -1) {
      throw new Error(`Server id "${id}" already exists`);
    }
    servers.push({
      id,
      name,
      host,
      port,
      login,
      user: login,
      password,
      pass: password,
      enabled,
      enable: enabled,
      type: type || 'streamer',
    });
  } else {
    const existing = servers[existingIdx];
    servers[existingIdx] = {
      ...existing,
      id,
      name,
      host,
      port,
      login,
      user: login || existing.user || '',
      password: password || (existing && (existing.password || existing.pass)) || '',
      pass: password || (existing && (existing.pass || existing.password)) || '',
      enabled,
      enable: enabled,
      type: type || existing.type || '',
    };
  }

  await saveSettings({ servers });
  state.servers = normalizeServers(state.settings.servers);
  renderServers();
  closeServerModal();
}

async function deleteServer(id) {
  const servers = Array.isArray(state.servers) ? state.servers.slice() : [];
  const next = servers.filter((s) => s && s.id !== id);
  await saveSettings({ servers: next });
  state.servers = normalizeServers(state.settings.servers);
  renderServers();
}

function syncSoftcamIdFromName() {
  if (!state.softcamIdAuto || !elements.softcamId || !elements.softcamName) return;
  const nextId = slugifySoftcamId(elements.softcamName.value);
  if (nextId) {
    elements.softcamId.value = nextId;
  }
}

function handleSoftcamIdInput() {
  if (!elements.softcamId) return;
  const current = elements.softcamId.value.trim();
  if (!current) {
    state.softcamIdAuto = true;
    syncSoftcamIdFromName();
    return;
  }
  state.softcamIdAuto = false;
}

function handleSoftcamNameInput() {
  syncSoftcamIdFromName();
}

async function saveSoftcam() {
  const id = elements.softcamId ? elements.softcamId.value.trim() : '';
  const name = elements.softcamName ? elements.softcamName.value.trim() : '';
  const type = elements.softcamType ? elements.softcamType.value.trim() : '';
  const host = elements.softcamHost ? elements.softcamHost.value.trim() : '';
  const port = toNumber(elements.softcamPort && elements.softcamPort.value);
  const user = elements.softcamUser ? elements.softcamUser.value.trim() : '';
  const pass = elements.softcamPass ? elements.softcamPass.value : '';
  const enable = elements.softcamEnabled ? elements.softcamEnabled.checked : true;
  const disableEmm = elements.softcamDisableEmm ? elements.softcamDisableEmm.checked : false;
  const splitCam = elements.softcamSplitCam ? elements.softcamSplitCam.checked : false;
  const shift = elements.softcamShift ? elements.softcamShift.value.trim() : '';
  const comment = elements.softcamComment ? elements.softcamComment.value.trim() : '';

  if (!id) throw new Error('Softcam id is required');
  if (!type) throw new Error('Softcam type is required');

  const softcams = Array.isArray(state.softcams) ? state.softcams.slice() : [];
  const existingIdx = softcams.findIndex((s) => s && s.id === id);
  const payload = {
    id,
    name: name || id,
    type,
    host,
    port,
    user,
    pass,
    enable,
    disable_emm: disableEmm,
    split_cam: splitCam,
    shift,
    comment,
  };

  if (state.softcamEditing && state.softcamEditing.id && state.softcamEditing.id !== id) {
    if (existingIdx !== -1) {
      throw new Error(`Softcam id \"${id}\" already exists`);
    }
    const currentIdx = softcams.findIndex((s) => s && s.id === state.softcamEditing.id);
    if (currentIdx !== -1) {
      const existing = softcams[currentIdx];
      softcams[currentIdx] = {
        ...payload,
        pass: pass || (existing && existing.pass) || '',
      };
    } else {
      softcams.push(payload);
    }
  } else if (!state.softcamEditing) {
    if (existingIdx !== -1) {
      throw new Error(`Softcam id \"${id}\" already exists`);
    }
    softcams.push(payload);
  } else {
    const existing = softcams[existingIdx];
    softcams[existingIdx] = {
      ...payload,
      pass: pass || (existing && existing.pass) || '',
    };
  }

  await saveSettings({ softcam: softcams });
  state.softcams = normalizeSoftcams(state.settings.softcam);
  renderSoftcams();
  refreshInputCamOptions();
  closeSoftcamModal();
}

async function deleteSoftcam(id) {
  const softcams = Array.isArray(state.softcams) ? state.softcams.slice() : [];
  const next = softcams.filter((s) => s && s.id !== id);
  await saveSettings({ softcam: next });
  state.softcams = normalizeSoftcams(state.settings.softcam);
  renderSoftcams();
  refreshInputCamOptions();
}

async function testServer(id, payload) {
  const body = id ? { id } : payload;
  await apiJson('/api/v1/servers/test', {
    method: 'POST',
    body: JSON.stringify(body || {}),
  });
  setStatus('Server test: OK');
}

function openServerUrl(id) {
  const server = (state.servers || []).find((s) => s && s.id === id);
  if (!server) return;
  let url = server.host || '';
  if (!/^https?:\/\//i.test(url)) {
    url = `http://${url}`;
  }
  if (server.port) {
    const hostPart = url.replace(/^https?:\/\//i, '').split('/')[0];
    const hasPort = /:\d+$/.test(hostPart);
    if (!hasPort) {
      const base = url.replace(/\/$/, '');
      url = `${base}:${server.port}`;
    }
  }
  window.open(url, '_blank');
}

function syncGroupIdFromName() {
  if (!state.groupIdAuto) return;
  if (!elements.groupName || !elements.groupId) return;
  const name = elements.groupName.value.trim();
  const nextId = name ? slugifyGroupId(name) : '';
  if (elements.groupId.value !== nextId) {
    elements.groupId.value = nextId;
  }
}

function handleGroupIdInput() {
  if (!elements.groupId) return;
  const current = elements.groupId.value.trim();
  if (!current) {
    state.groupIdAuto = true;
    syncGroupIdFromName();
    return;
  }
  state.groupIdAuto = false;
}

function handleGroupNameInput() {
  syncGroupIdFromName();
}

async function saveGroup() {
  const id = elements.groupId ? elements.groupId.value.trim() : '';
  const name = elements.groupName ? elements.groupName.value.trim() : '';
  if (!id) throw new Error('Group id is required');
  if (!name) throw new Error('Group name is required');

  const groups = Array.isArray(state.groups) ? state.groups.slice() : [];
  const existingIdx = groups.findIndex((g) => g && g.id === id);
  if (state.groupEditing && state.groupEditing.id && state.groupEditing.id !== id) {
    if (existingIdx !== -1) {
      throw new Error(`Group id "${id}" already exists`);
    }
    const currentIdx = groups.findIndex((g) => g && g.id === state.groupEditing.id);
    if (currentIdx !== -1) {
      groups[currentIdx] = { id, name };
    } else {
      groups.push({ id, name });
    }
  } else if (!state.groupEditing) {
    if (existingIdx !== -1) {
      throw new Error(`Group id "${id}" already exists`);
    }
    groups.push({ id, name });
  } else {
    groups[existingIdx] = { id, name };
  }

  await saveSettings({ groups });
  state.groups = normalizeGroups(state.settings.groups);
  renderGroups();
  updateStreamGroupOptions();
  closeGroupModal();
}

async function deleteGroup(id) {
  const groups = Array.isArray(state.groups) ? state.groups.slice() : [];
  const next = groups.filter((g) => g && g.id !== id);
  await saveSettings({ groups: next });
  state.groups = normalizeGroups(state.settings.groups);
  renderGroups();
  updateStreamGroupOptions();
}

function formatBitrate(value) {
  const rate = Number.isFinite(value) ? Math.max(0, Math.round(value)) : 0;
  return `${rate}Kbit/s`;
}

function formatBitrateBps(value) {
  const rate = Number(value);
  if (!Number.isFinite(rate)) return '-';
  return formatBitrate(rate / 1000);
}

function formatPercentOneDecimal(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '-';
  return `${num.toFixed(1)}%`;
}

function formatMaybeBitrate(value) {
  if (value === null || value === undefined) return '-';
  const rate = Number(value);
  if (!Number.isFinite(rate)) return '-';
  return formatBitrate(rate);
}

function formatTranscodeBitrates(transcode) {
  const inputRate = transcode && transcode.input_bitrate_kbps;
  const outputRate = transcode && transcode.output_bitrate_kbps;
  const inputLabel = formatMaybeBitrate(inputRate);
  const outputLabel = formatMaybeBitrate(outputRate);
  return `In ${inputLabel} / Out ${outputLabel}`;
}

const VIEW_MODE_LABELS = {
  table: 'Table',
  compact: 'Compact',
  cards: 'Cards',
};

const THEME_MODE_LABELS = {
  auto: 'Auto',
  light: 'Light',
  dark: 'Dark',
};

function normalizeViewMode(value) {
  const mode = String(value || '').toLowerCase();
  if (mode === 'table' || mode === 'compact' || mode === 'cards') return mode;
  return 'cards';
}

function normalizeThemeMode(value) {
  const mode = String(value || '').toLowerCase();
  if (mode === 'light' || mode === 'dark' || mode === 'auto') return mode;
  return 'auto';
}

function applyThemeMode(mode) {
  const root = document.documentElement;
  root.classList.remove('theme-light', 'theme-dark');
  if (mode === 'light') {
    root.classList.add('theme-light');
  } else if (mode === 'dark') {
    root.classList.add('theme-dark');
  }
}

function updateViewButtonLabel() {
  if (!elements.btnView) return;
  const label = VIEW_MODE_LABELS[state.viewMode] || 'View';
  elements.btnView.textContent = `View: ${label}`;
}

function updateViewMenuSelection() {
  elements.viewOptions.forEach((option) => {
    const viewMode = option.dataset.viewMode;
    const themeMode = option.dataset.theme;
    const tilesMode = option.dataset.tilesMode;
    const viewToggle = option.dataset.viewToggle;
    const isActive = viewMode
      ? viewMode === state.viewMode
      : themeMode
      ? themeMode === state.themeMode
      : tilesMode
      ? (state.tilesUi && tilesMode === state.tilesUi.mode)
      : viewToggle
      ? (viewToggle === 'disabled' ? state.showDisabledStreams : false)
      : false;
    option.classList.toggle('active', isActive);
    if (viewToggle) {
      option.setAttribute('aria-pressed', isActive ? 'true' : 'false');
    }
  });
  updateViewButtonLabel();
}

function setViewMode(mode, opts) {
  const next = normalizeViewMode(mode);
  state.viewMode = next;
  if (!opts || opts.persist !== false) {
    localStorage.setItem('astra.viewMode', next);
  }
  if (elements.streamViews) {
    elements.streamViews.dataset.viewMode = next;
  }
  updateViewMenuSelection();
  if (!opts || opts.render !== false) {
    renderStreams();
  }
  applyTilesUiState();
}

function setShowDisabledStreams(value, opts) {
  state.showDisabledStreams = !!value;
  if (!opts || opts.persist !== false) {
    localStorage.setItem(SHOW_DISABLED_KEY, state.showDisabledStreams ? '1' : '0');
  }
  updateViewMenuSelection();
  if (!opts || opts.render !== false) {
    renderStreams();
  }
}

function setThemeMode(mode, opts) {
  const next = normalizeThemeMode(mode);
  state.themeMode = next;
  if (!opts || opts.persist !== false) {
    localStorage.setItem('astra.theme', next);
  }
  applyThemeMode(next);
  updateViewMenuSelection();
}

function cycleViewMode() {
  const order = ['cards', 'table', 'compact'];
  const idx = order.indexOf(state.viewMode);
  const next = order[(idx + 1) % order.length];
  setViewMode(next);
}

function openViewMenu() {
  if (!elements.viewMenu) return;
  elements.viewMenu.classList.add('open');
  elements.viewMenu.setAttribute('aria-hidden', 'false');
}

function closeViewMenu() {
  if (!elements.viewMenu) return;
  elements.viewMenu.classList.remove('open');
  elements.viewMenu.setAttribute('aria-hidden', 'true');
}

function toggleViewMenu() {
  if (!elements.viewMenu) return;
  if (elements.viewMenu.classList.contains('open')) {
    closeViewMenu();
  } else {
    openViewMenu();
  }
}

const AUTO_FIT_SELECTOR = '[data-autofit="true"]';
let autoFitPending = false;
const autoFitScopes = new Set();

function autoFitText(el) {
  if (!el) return;
  if (el.clientWidth <= 0) return;
  const maxPx = Number(el.dataset.autofitMax)
    || Math.round(parseFloat(getComputedStyle(el).fontSize) || 14);
  const minPx = Number(el.dataset.autofitMin) || 11;
  let size = maxPx;
  el.style.fontSize = `${size}px`;
  const maxSteps = Math.max(0, maxPx - minPx);
  for (let step = 0; step < maxSteps && el.scrollWidth > el.clientWidth; step += 1) {
    size -= 1;
    el.style.fontSize = `${size}px`;
  }
}

function autoFitWithin(scope) {
  const root = scope || document;
  root.querySelectorAll(AUTO_FIT_SELECTOR).forEach(autoFitText);
}

function scheduleAutoFit(scope) {
  if (!scope) {
    autoFitScopes.clear();
    autoFitScopes.add(document);
  } else {
    autoFitScopes.add(scope);
  }
  if (autoFitPending) return;
  autoFitPending = true;
  requestAnimationFrame(() => {
    autoFitPending = false;
    if (autoFitScopes.has(document)) {
      autoFitScopes.clear();
      autoFitWithin(document);
      return;
    }
  autoFitScopes.forEach(autoFitWithin);
  autoFitScopes.clear();
  });
}

const autoFitObserver = typeof ResizeObserver === 'function'
  ? new ResizeObserver((entries) => {
    entries.forEach((entry) => autoFitText(entry.target));
  })
  : null;

function registerAutoFit(el) {
  if (!autoFitObserver || !el) return;
  autoFitObserver.observe(el);
}

window.addEventListener('resize', () => scheduleAutoFit());

function formatBytes(value) {
  const bytes = Number(value) || 0;
  if (bytes < 1024) return `${bytes}B`;
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(1)}KB`;
  const mb = kb / 1024;
  if (mb < 1024) return `${mb.toFixed(1)}MB`;
  const gb = mb / 1024;
  return `${gb.toFixed(1)}GB`;
}

function formatTimestamp(ts) {
  if (!ts) return 'n/a';
  return new Date(ts * 1000).toLocaleString();
}

function formatRevisionStatus(status, isActive, isLkg) {
  const label = String(status || 'pending').toUpperCase();
  if (isLkg) return { label: 'LKG', className: 'ok' };
  if (isActive) return { label: 'ACTIVE', className: 'ok' };
  if (label === 'BAD') return { label, className: 'bad' };
  if (label === 'PENDING') return { label, className: 'pending' };
  return { label, className: 'pending' };
}

function isValidIpv4(value) {
  const text = String(value || '').trim();
  const match = text.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (!match) return false;
  return match.slice(1).every((part) => {
    const num = Number(part);
    return Number.isInteger(num) && num >= 0 && num <= 255;
  });
}

function isValidCidr(value) {
  const text = String(value || '').trim();
  const match = text.match(/^(.+)\/(\d{1,2})$/);
  if (!match) return false;
  const prefix = Number(match[2]);
  if (!Number.isInteger(prefix) || prefix < 0 || prefix > 32) return false;
  return isValidIpv4(match[1].trim());
}

function isValidIpRange(value) {
  const text = String(value || '').trim();
  let from = '';
  let to = '';
  if (text.includes('..')) {
    const parts = text.split('..');
    if (parts.length !== 2) return false;
    from = parts[0];
    to = parts[1];
  } else {
    const match = text.match(/^([^,\-]+)[,\-]([^,\-]+)$/);
    if (!match) return false;
    from = match[1];
    to = match[2];
  }
  return isValidIpv4(from.trim()) && isValidIpv4(to.trim());
}

function isValidAllowRange(value) {
  return isValidCidr(value) || isValidIpRange(value);
}

function formatTranscodeProgress(progress) {
  if (!progress) return 'n/a';
  const outTimeMs = Number(progress.out_time_ms);
  const time = Number.isFinite(outTimeMs)
    ? formatUptime(Math.floor(outTimeMs / 1000000))
    : 'n/a';
  const fps = progress.fps ? String(progress.fps) : 'n/a';
  const speed = progress.speed ? String(progress.speed) : 'n/a';
  return `time=${time} fps=${fps} speed=${speed}`;
}

function formatRestartMeta(meta) {
  if (!meta || typeof meta !== 'object') return 'n/a';
  const parts = [];
  if (meta.input_index !== undefined) parts.push(`input #${meta.input_index}`);
  if (meta.output_index !== undefined) parts.push(`output #${meta.output_index}`);
  if (meta.desync_ms !== undefined) parts.push(`desync ${Math.round(meta.desync_ms)} ms`);
  if (meta.bitrate_kbps !== undefined) parts.push(`bitrate ${Math.round(meta.bitrate_kbps)} Kbit/s`);
  if (meta.timeout_sec !== undefined) parts.push(`timeout ${meta.timeout_sec}s`);
  if (meta.count !== undefined) parts.push(`errors ${meta.count}`);
  if (meta.bad_pts) parts.push('bad pts');
  if (meta.hang) parts.push('hang');
  if (meta.error_line) parts.push(`error "${meta.error_line}"`);
  if (meta.exit_code !== undefined) parts.push(`exit ${meta.exit_code}`);
  if (meta.exit_signal !== undefined && meta.exit_signal !== 0) parts.push(`signal ${meta.exit_signal}`);
  if (!parts.length) return 'n/a';
  return parts.join(' · ');
}

function formatGpuInfo(transcode) {
  if (!transcode) return 'n/a';
  const device = transcode.gpu_device_selected ?? transcode.gpu_device;
  if (device === undefined || device === null || device === '') return 'n/a';
  let stats = transcode.gpu_stats;
  if (!stats && Array.isArray(transcode.gpu_metrics)) {
    stats = transcode.gpu_metrics.find((gpu) => gpu && gpu.index === device) || transcode.gpu_metrics[0];
  }
  if (stats) {
    const util = Number.isFinite(stats.util) ? `${stats.util}%` : 'n/a';
    const enc = Number.isFinite(stats.enc) ? `${stats.enc}%` : null;
    const memUsed = Number.isFinite(stats.mem_used) ? stats.mem_used : 'n/a';
    const memTotal = Number.isFinite(stats.mem_total) ? stats.mem_total : 'n/a';
    const sessions = Number.isFinite(transcode.gpu_sessions)
      ? transcode.gpu_sessions
      : (Number.isFinite(stats.session_count) ? stats.session_count : null);
    const limit = Number.isFinite(transcode.gpu_sessions_limit) ? transcode.gpu_sessions_limit : null;
    const sessionLabel = sessions !== null
      ? ` sess ${sessions}${limit !== null ? `/${limit}` : ''}`
      : '';
    const overload = transcode.gpu_overload_active ? ' OVERLOAD' : '';
    const encLabel = enc ? ` enc ${enc}` : '';
    return `#${device} util ${util}${encLabel} mem ${memUsed}/${memTotal} MB${sessionLabel}${overload}`;
  }
  return `#${device}`;
}

function formatGpuOverloadReason(reason) {
  if (!reason || typeof reason !== 'object') return 'n/a';
  const parts = [];
  if (reason.gpu !== undefined) parts.push(`#${reason.gpu}`);
  if (reason.util !== undefined || reason.util_limit !== undefined) {
    const util = reason.util !== undefined ? `${reason.util}%` : 'n/a';
    const limit = reason.util_limit !== undefined ? `${reason.util_limit}%` : 'n/a';
    parts.push(`util ${util}/${limit}`);
  }
  if (reason.mem_used !== undefined || reason.mem_limit !== undefined) {
    const used = reason.mem_used !== undefined ? reason.mem_used : 'n/a';
    const limit = reason.mem_limit !== undefined ? reason.mem_limit : 'n/a';
    parts.push(`mem ${used}/${limit} MB`);
  }
  if (reason.session_count !== undefined || reason.session_limit !== undefined) {
    const count = reason.session_count !== undefined ? reason.session_count : 'n/a';
    const limit = reason.session_limit !== undefined ? reason.session_limit : 'n/a';
    parts.push(`sess ${count}/${limit}`);
  }
  return parts.length ? parts.join(' ') : 'n/a';
}

function linesToArgs(text) {
  if (!text) return [];
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
}

function argsToLines(args) {
  if (!Array.isArray(args) || !args.length) return '';
  return args.join('\n');
}

function getResourcePath(url) {
  if (!url) return '/';
  try {
    const parsed = new URL(url);
    return `${parsed.pathname || '/'}${parsed.search || ''}`;
  } catch (err) {
    const idx = url.indexOf('://');
    if (idx === -1) return '/';
    const pathStart = url.indexOf('/', idx + 3);
    if (pathStart === -1) return '/';
    return url.slice(pathStart);
  }
}

function buildSplitterOutputUrl(port, resourcePath) {
  const path = resourcePath && resourcePath.startsWith('/') ? resourcePath : `/${resourcePath || ''}`;
  if (!port) {
    return `http://127.0.0.1${path}`;
  }
  return `http://127.0.0.1:${port}${path}`;
}

function normalizeBufferPath(path) {
  if (!path) return '/';
  return path.startsWith('/') ? path : `/${path}`;
}

function buildBufferOutputUrl(path) {
  const host = getSettingString('buffer_listen_host', '<server_ip>');
  const port = getSettingNumber('buffer_listen_port', 8089);
  const displayHost = host === '0.0.0.0' ? '<server_ip>' : host;
  return `http://${displayHost}:${port}${normalizeBufferPath(path || '/')}`;
}

function getSplitterStatus(id) {
  return state.splitterStatus && state.splitterStatus[id] ? state.splitterStatus[id] : null;
}

function getBufferStatus(id) {
  return state.bufferStatus && state.bufferStatus[id] ? state.bufferStatus[id] : null;
}

function normalizeArgList(value) {
  if (Array.isArray(value)) return value.map((item) => String(item));
  if (value === null || value === undefined || value === '') return [];
  return [String(value)];
}

function cleanArgList(value) {
  return normalizeArgList(value).map((item) => item.trim()).filter(Boolean);
}

function parseJsonArray(text, label) {
  const trimmed = (text || '').trim();
  if (!trimmed) return [];
  let parsed;
  try {
    parsed = JSON.parse(trimmed);
  } catch (err) {
    throw new Error(`${label} must be valid JSON`);
  }
  if (!Array.isArray(parsed)) {
    throw new Error(`${label} must be a JSON array`);
  }
  return parsed;
}

function setTranscodeMode(enabled) {
  if (!elements.streamForm) return;
  elements.streamForm.classList.toggle('is-transcode', enabled);
}

function updateStreamBackupFields() {
  if (!elements.streamBackupType) return;
  const value = elements.streamBackupType.value.trim();
  const showActiveFields = value === 'active' || value === 'active_stop_if_all_inactive';
  const showStopInactive = value === 'active_stop_if_all_inactive';
  if (elements.streamBackupReturnDelayField) {
    elements.streamBackupReturnDelayField.classList.toggle('hidden', !showActiveFields);
  }
  if (elements.streamBackupWarmMaxField) {
    elements.streamBackupWarmMaxField.classList.toggle('hidden', !showActiveFields);
  }
  if (elements.streamBackupStopInactiveField) {
    elements.streamBackupStopInactiveField.classList.toggle('hidden', !showStopInactive);
  }
}

function updateMptsFields() {
  if (!elements.streamMpts) return;
  const enabled = elements.streamMpts.checked;
  $$('.mpts-field').forEach((field) => {
    field.disabled = !enabled;
  });
  $$('.mpts-section').forEach((section) => {
    section.classList.toggle('is-disabled', !enabled);
  });
  // Длительность автосканирования доступна только при включённом auto-probe.
  if (elements.mptsAutoProbeDuration && elements.mptsAutoProbe) {
    elements.mptsAutoProbeDuration.disabled = !enabled || !elements.mptsAutoProbe.checked;
  }
  if (elements.streamInputBlock) {
    elements.streamInputBlock.classList.toggle('is-hidden', enabled);
  }
  if (elements.mptsEnabledStatus) {
    elements.mptsEnabledStatus.textContent = enabled ? 'Status: Enabled' : 'Status: Disabled';
    elements.mptsEnabledStatus.classList.toggle('is-enabled', enabled);
    elements.mptsEnabledStatus.classList.toggle('is-disabled', !enabled);
  }
  if (elements.btnMptsEnable) {
    elements.btnMptsEnable.disabled = enabled;
  }
  if (elements.mptsCallout) {
    elements.mptsCallout.classList.toggle('is-hidden', enabled);
  }
  if (elements.btnMptsEnableCallout) {
    elements.btnMptsEnableCallout.disabled = enabled;
  }
  updateMptsPassWarning();
  updateMptsAutoremapWarning();
  updateMptsPnrWarning();
  updateMptsInputWarning();
  updateMptsDeliveryWarning();
  updateMptsLcnTagsWarning();
  updateMptsLcnVersionWarning();
  updateEditorMptsStatus();
}

function focusMptsManual(message) {
  if (message) {
    setStatus(message);
  }
  if (elements.mptsManual) {
    elements.mptsManual.classList.add('is-attention');
    try {
      elements.mptsManual.scrollIntoView({ behavior: 'smooth', block: 'start' });
    } catch (err) {
      elements.mptsManual.scrollIntoView(true);
    }
    window.setTimeout(() => {
      elements.mptsManual.classList.remove('is-attention');
    }, 1200);
  }
  if (elements.btnMptsEnable && !elements.btnMptsEnable.disabled) {
    elements.btnMptsEnable.focus();
  }
}

function truncateText(text, max) {
  if (!text) return '';
  if (text.length <= max) return text;
  return `${text.slice(0, max)}…`;
}

function shortInputLabel(url) {
  if (!url) return 'n/a';
  const cleaned = String(url).split('#')[0];
  const parts = cleaned.split('://');
  if (parts.length < 2) return truncateText(cleaned, 28);
  const scheme = parts[0].toLowerCase();
  const rest = parts.slice(1).join('://');

  if (scheme === 'http' || scheme === 'https' || scheme === 'hls' || scheme === 'np') {
    const normalized = `${scheme === 'hls' || scheme === 'np' ? 'http' : scheme}://${rest}`;
    try {
      const parsed = new URL(normalized);
      const path = parsed.pathname || '/';
      const shortPath = truncateText(path, 20);
      return `${parsed.host}${shortPath}`;
    } catch (err) {
      return truncateText(rest, 28);
    }
  }

  if (scheme === 'udp' || scheme === 'rtp') {
    return truncateText(rest, 28);
  }

  if (scheme === 'file' || scheme === 'dvb') {
    return truncateText(rest, 28);
  }

  return truncateText(rest, 28);
}

function getInputLabel(input, index) {
  const url = input && input.url ? input.url : '';
  if (url) return shortInputLabel(url);
  if (input && input.name) return input.name;
  return `Input ${index + 1}`;
}

function getActiveInputIndex(stats) {
  if (!stats) return null;
  if (Number.isFinite(stats.active_input_index)) {
    return stats.active_input_index;
  }
  if (stats.active_input_id) {
    return stats.active_input_id - 1;
  }
  return null;
}

function getActiveInputLabel(inputs, activeIndex) {
  if (!Number.isFinite(activeIndex)) return '';
  const input = inputs[activeIndex];
  if (!input) return '';
  return `#${activeIndex + 1} ${getInputLabel(input, activeIndex)}`;
}

function getInputState(input, index, activeIndex) {
  const stateValue = String((input && input.state) || '').toUpperCase();
  const onAir = input && input.on_air === true;
  const isActive = Number.isFinite(activeIndex) && index === activeIndex;

  if (stateValue) {
    if (stateValue === 'DOWN' && onAir) {
      return isActive ? 'ACTIVE' : 'STANDBY';
    }
    if (stateValue === 'ACTIVE' && !isActive && Number.isFinite(activeIndex)) {
      return 'STANDBY';
    }
    if (stateValue === 'STANDBY' && isActive) {
      return onAir ? 'ACTIVE' : 'DOWN';
    }
    return stateValue;
  }

  if (isActive) {
    return onAir ? 'ACTIVE' : 'DOWN';
  }
  if (onAir) return 'STANDBY';
  return 'DOWN';
}

function summarizeInputStates(inputs, activeIndex) {
  let okCount = 0;
  let downCount = 0;
  let unkCount = 0;
  inputs.forEach((input, index) => {
    const stateValue = String(getInputState(input, index, activeIndex) || '').toUpperCase();
    if (stateValue === 'ACTIVE' || stateValue === 'STANDBY' || stateValue === 'OK') {
      okCount += 1;
      return;
    }
    if (stateValue === 'DOWN') {
      downCount += 1;
      return;
    }
    unkCount += 1;
  });
  return { okCount, downCount, unkCount };
}

function formatInputSummary(inputs, activeIndex) {
  if (!inputs.length) return 'Inputs: -';
  const summary = summarizeInputStates(inputs, activeIndex);
  return `Inputs: ${summary.okCount} OK • ${summary.downCount} DOWN • ${summary.unkCount} UNK`;
}

function isStreamVisible(stream) {
  const term = searchTerm.toLowerCase();
  if (!state.showDisabledStreams && stream && stream.enabled === false) {
    return false;
  }
  if (!term) return true;
  const name = (stream.config && stream.config.name) || '';
  return (stream.id + ' ' + name).toLowerCase().includes(term);
}

function rebuildStreamIndex(list) {
  state.streamIndex = {};
  list.forEach((stream) => {
    state.streamIndex[stream.id] = stream;
  });
}

function findTileById(id) {
  return $$('.tile').find((tile) => tile.dataset.id === id) || null;
}

function ensureDashboardEmptyState() {
  if (!elements.dashboardStreams) return;
  const hasTile = Boolean(elements.dashboardStreams.querySelector('.tile'));
  const empty = elements.dashboardStreams.querySelector('[data-role="streams-empty"]');
  if (hasTile) {
    if (empty) empty.remove();
    return;
  }
  if (!empty) {
    const panel = createEl('div', 'panel', 'No streams yet. Create the first one.');
    panel.dataset.role = 'streams-empty';
    elements.dashboardStreams.appendChild(panel);
  }
}

function buildStreamTile(stream) {
  const tile = document.createElement('div');
  const stats = state.stats[stream.id] || {};
  const enabled = stream.enabled !== false;
  const onAir = enabled && stats.on_air === true;
  const tileState = enabled ? (onAir ? 'ok' : 'warn') : 'disabled';
  const rateState = enabled ? (onAir ? '' : 'warn') : 'disabled';
  const metaText = enabled ? (onAir ? 'Active' : 'Inactive') : 'Disabled';
  const statusInfo = getStreamStatusInfo(stream, stats);
  const inputs = Array.isArray(stats.inputs) ? stats.inputs : [];
  const activeIndex = getActiveInputIndex(stats);
  const activeLabel = getActiveInputLabel(inputs, activeIndex);
  const compactInputText = activeLabel ? `Active input: ${activeLabel}` : 'Active input: -';
  const inputSummaryText = formatInputSummary(inputs, activeIndex);
  tile.className = `tile ${tileState}`;
  tile.dataset.id = stream.id;
  tile.dataset.enabled = enabled ? '1' : '0';

  const displayName = (stream.config && stream.config.name) || stream.id;
  const detailsId = `tile-details-${stream.id}`;

  tile.innerHTML = `
    <div class="tile-header">
      <div class="tile-head">
        <div class="tile-title" data-autofit="true" data-autofit-min="12" data-autofit-max="14">${displayName}</div>
        <div class="tile-actions">
          <button class="tile-toggle" data-action="tile-toggle" aria-expanded="false" aria-controls="${detailsId}">⯈</button>
          <button class="kebab" data-action="menu" aria-label="Menu"><span></span></button>
        </div>
      </div>
      <div class="tile-summary">
        <div class="tile-rate ${rateState}" data-autofit="true" data-autofit-min="11" data-autofit-max="14">${formatBitrate(stats.bitrate || 0)}</div>
        <div class="tile-meta" data-autofit="true" data-autofit-min="11" data-autofit-max="12">${metaText}</div>
        <div class="tile-compact-status stream-status-badge ${statusInfo.className}" data-role="tile-compact-status">
          <span class="stream-status-dot"></span>
          <span data-role="tile-compact-status-label">${statusInfo.label}</span>
        </div>
        <div class="tile-compact-input" data-role="tile-compact-input">${compactInputText}</div>
        <div class="tile-compact-input-summary" data-role="tile-compact-input-summary">${inputSummaryText}</div>
      </div>
    </div>
    <div class="tile-details" id="${detailsId}">
      <div class="tile-inputs" data-role="tile-inputs"></div>
      <div class="tile-mpts-meta is-hidden" data-role="tile-mpts-meta">MPTS: -</div>
    </div>
    <div class="tile-menu">
      <button class="menu-item" data-action="edit">Edit</button>
      <button class="menu-item" data-action="analyze">Analyze</button>
      <button class="menu-item" data-action="play">▶ Play</button>
      <button class="menu-item" data-action="toggle">${enabled ? 'Disable' : 'Enable'}</button>
      <button class="menu-item" data-action="delete">Delete</button>
    </div>
  `;

  tile.querySelectorAll(AUTO_FIT_SELECTOR).forEach(registerAutoFit);
  scheduleAutoFit(tile);
  applyTileUiState(tile);
  return tile;
}

function updateStreamTile(stream) {
  if (!elements.dashboardStreams) return;
  const visible = isStreamVisible(stream);
  const existing = findTileById(stream.id);
  if (!visible) {
    if (existing) existing.remove();
    delete state.streamIndex[stream.id];
    ensureDashboardEmptyState();
    return;
  }
  const tile = buildStreamTile(stream);
  if (existing) {
    existing.replaceWith(tile);
  } else {
    elements.dashboardStreams.appendChild(tile);
  }
  state.streamIndex[stream.id] = stream;
  ensureDashboardEmptyState();
  scheduleAutoFit(elements.dashboardStreams);
}

function removeStreamFromState(streamId) {
  const id = String(streamId);
  state.streams = state.streams.filter((stream) => stream && stream.id !== id);
  delete state.streamIndex[id];
  if (state.stats) {
    delete state.stats[id];
  }
}

function upsertStreamInState(stream) {
  if (!stream) return;
  const id = String(stream.id);
  const index = state.streams.findIndex((item) => item && item.id === id);
  if (index === -1) {
    state.streams.push(stream);
  } else {
    state.streams[index] = stream;
  }
  if (isStreamVisible(stream)) {
    state.streamIndex[id] = stream;
  } else {
    delete state.streamIndex[id];
  }
}

function applyStreamUpdate(stream) {
  if (state.viewMode === 'cards') {
    updateStreamTile(stream);
    updateTiles();
    return;
  }
  renderStreams();
}

function applyStreamRemoval(streamId) {
  if (state.viewMode === 'cards') {
    const tile = findTileById(streamId);
    if (tile) tile.remove();
    delete state.streamIndex[streamId];
    ensureDashboardEmptyState();
    scheduleAutoFit(elements.dashboardStreams);
    return;
  }
  renderStreams();
}

function scheduleStreamSync(delayMs = 1500) {
  if (state.streamSyncTimer) {
    clearTimeout(state.streamSyncTimer);
  }
  state.streamSyncTimer = setTimeout(() => {
    state.streamSyncTimer = null;
    syncStreamsSilently();
  }, delayMs);
}

async function syncStreamsSilently() {
  try {
    const data = await apiJson('/api/v1/streams');
    state.streams = Array.isArray(data) ? data : [];
    const filtered = state.streams.filter(isStreamVisible);
    rebuildStreamIndex(filtered);
  } catch (err) {
  }
}

function isTranscodeStream(stream) {
  const typeValue = String(stream && stream.config && stream.config.type || '').toLowerCase();
  return typeValue === 'transcode' || typeValue === 'ffmpeg';
}

function normalizeOutputList(outputs) {
  if (!outputs) return [];
  if (typeof outputs === 'string') return [outputs];
  if (Array.isArray(outputs)) return outputs;
  if (typeof outputs === 'object') return [outputs];
  return [];
}

function inferOutputFormat(entry) {
  if (!entry) return '';
  if (typeof entry === 'string') {
    const scheme = entry.split('://')[0];
    return scheme ? scheme.toLowerCase() : '';
  }
  if (entry.format) {
    return String(entry.format).toLowerCase();
  }
  if (entry.url) {
    const scheme = String(entry.url).split('://')[0];
    return scheme ? scheme.toLowerCase() : '';
  }
  return '';
}

function outputFormatLabel(format) {
  const map = {
    http: 'HTTP',
    https: 'HTTP',
    hls: 'HLS',
    udp: 'UDP',
    rtp: 'RTP',
    srt: 'SRT',
    rtsp: 'RTSP',
    file: 'File',
    np: 'NetworkPush',
    npull: 'NetworkPush',
  };
  if (!format) return '-';
  return map[format] || format.toUpperCase();
}

function getOutputSummary(stream) {
  if (!stream || !stream.config) return '-';
  const outputs = isTranscodeStream(stream)
    ? normalizeOutputList(stream.config.transcode && stream.config.transcode.outputs)
    : normalizeOutputList(stream.config.output);
  if (!outputs.length) return '-';
  const labels = [];
  outputs.forEach((entry) => {
    const format = inferOutputFormat(entry);
    const label = outputFormatLabel(format);
    if (label && !labels.includes(label)) {
      labels.push(label);
    }
  });
  return labels.length ? labels.join(' / ') : '-';
}

function getActiveInputStats(stats) {
  const inputs = Array.isArray(stats && stats.inputs) ? stats.inputs : [];
  const activeIndex = getActiveInputIndex(stats);
  const activeInput = Number.isFinite(activeIndex) ? inputs[activeIndex] : null;
  return { inputs, activeIndex, activeInput };
}

function getStreamStatusInfo(stream, stats) {
  if (stream.enabled === false) {
    return { label: 'Disabled', className: 'disabled' };
  }
  if (stats && stats.transcode_state) {
    const state = stats.transcode_state;
    if (state === 'RUNNING') return { label: 'Online', className: 'ok' };
    if (state === 'STARTING' || state === 'RESTARTING') return { label: state, className: 'pending' };
    if (state === 'ERROR') return { label: 'Error', className: 'warn' };
    return { label: state, className: 'warn' };
  }
  return stats && stats.on_air === true
    ? { label: 'Online', className: 'ok' }
    : { label: 'Offline', className: 'warn' };
}

function copyText(text, message) {
  if (!text) return;
  const label = message || 'Copied URL';
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(() => {
      setStatus(label);
    }).catch(() => {
      copyTextFallback(text, label);
    });
    return;
  }
  copyTextFallback(text, label);
}

function copyTextFallback(text, message) {
  const label = message || 'Copied URL';
  const area = document.createElement('textarea');
  area.value = text;
  area.style.position = 'fixed';
  area.style.opacity = '0';
  document.body.appendChild(area);
  area.focus();
  area.select();
  try {
    document.execCommand('copy');
    setStatus(label);
  } catch (err) {
  }
  document.body.removeChild(area);
}

function joinPath(base, suffix) {
  if (!base) return suffix || '';
  if (!suffix) return base;
  const cleanBase = base.endsWith('/') ? base.slice(0, -1) : base;
  const cleanSuffix = suffix.startsWith('/') ? suffix.slice(1) : suffix;
  return `${cleanBase}/${cleanSuffix}`;
}

function getHlsDefaults(id) {
  const hlsDir = state.settings.hls_dir || defaults.hlsDir;
  const hlsBase = state.settings.hls_base_url || defaults.hlsBase;
  const resourcePath = getSettingString('hls_resource_path', 'absolute');
  const baseUrl = resourcePath === 'relative' ? '' : joinPath(hlsBase, id || 'stream');
  return {
    path: joinPath(hlsDir, id || 'stream'),
    base_url: baseUrl,
  };
}

function defaultHlsOutput(streamId) {
  const defaults = getHlsDefaults(streamId);
  const duration = getSettingNumber('hls_duration', 3);
  const window = getSettingNumber('hls_quantity', 4);
  const cleanup = getSettingNumber('hls_cleanup', window * 2);
  return {
    format: 'hls',
    path: defaults.path,
    base_url: defaults.base_url,
    playlist: 'index.m3u8',
    prefix: 'segment',
    target_duration: duration,
    window: window,
    cleanup: cleanup,
    use_wall: true,
    auto: true,
  };
}

function formatAudioTypeHex(value) {
  const numeric = Number(value);
  if (!Number.isFinite(numeric)) return null;
  return `0x${numeric.toString(16).toUpperCase().padStart(2, '0')}`;
}

function normalizeOutputAudioFix(config) {
  const src = (config && typeof config === 'object') ? config : {};
  const modeRaw = String(src.mode || OUTPUT_AUDIO_FIX_DEFAULTS.mode || 'aac').toLowerCase();
  const mode = (modeRaw === 'auto' || modeRaw === 'aac') ? modeRaw : OUTPUT_AUDIO_FIX_DEFAULTS.mode;
  const target = Number.isFinite(Number(src.target_audio_type))
    ? Number(src.target_audio_type)
    : OUTPUT_AUDIO_FIX_DEFAULTS.target_audio_type;
  const interval = toNumber(src.probe_interval_sec);
  const duration = toNumber(src.probe_duration_sec);
  const hold = toNumber(src.mismatch_hold_sec);
  const cooldown = toNumber(src.restart_cooldown_sec);
  const bitrate = toNumber(src.aac_bitrate_kbps);
  const sampleRate = toNumber(src.aac_sample_rate);
  const channels = toNumber(src.aac_channels);
  const asyncValue = src.aresample_async !== undefined ? toNumber(src.aresample_async) : undefined;
  const profile = typeof src.aac_profile === 'string' ? src.aac_profile.trim() : '';
  return {
    enabled: src.enabled === true,
    force_on: src.force_on === true,
    mode,
    target_audio_type: target,
    probe_interval_sec: Number.isFinite(interval) ? interval : OUTPUT_AUDIO_FIX_DEFAULTS.probe_interval_sec,
    probe_duration_sec: Number.isFinite(duration) ? duration : OUTPUT_AUDIO_FIX_DEFAULTS.probe_duration_sec,
    mismatch_hold_sec: Number.isFinite(hold) ? hold : OUTPUT_AUDIO_FIX_DEFAULTS.mismatch_hold_sec,
    restart_cooldown_sec: Number.isFinite(cooldown) ? cooldown : OUTPUT_AUDIO_FIX_DEFAULTS.restart_cooldown_sec,
    aac_bitrate_kbps: Number.isFinite(bitrate) ? bitrate : OUTPUT_AUDIO_FIX_DEFAULTS.aac_bitrate_kbps,
    aac_sample_rate: Number.isFinite(sampleRate) ? sampleRate : OUTPUT_AUDIO_FIX_DEFAULTS.aac_sample_rate,
    aac_channels: Number.isFinite(channels) ? channels : OUTPUT_AUDIO_FIX_DEFAULTS.aac_channels,
    aac_profile: profile || OUTPUT_AUDIO_FIX_DEFAULTS.aac_profile,
    aresample_async: Number.isFinite(asyncValue) ? asyncValue : OUTPUT_AUDIO_FIX_DEFAULTS.aresample_async,
    silence_fallback: src.silence_fallback === true,
  };
}

function getOutputAudioFixMeta(output, status) {
  const config = normalizeOutputAudioFix(output && output.audio_fix);
  const targetHex = formatAudioTypeHex(config.target_audio_type);
  const detectedHex = status && status.detected_audio_type_hex ? status.detected_audio_type_hex : null;
  const audioText = detectedHex ? `Audio: ${detectedHex}` : 'Audio: —';
  const audioOk = detectedHex && targetHex && detectedHex.toUpperCase() === targetHex.toUpperCase();
  const fixState = status && status.audio_fix_state
    ? status.audio_fix_state
    : (config.enabled ? 'PROBING' : 'OFF');
  let fixClass = '';
  if (fixState === 'RUNNING') fixClass = 'is-ok';
  else if (fixState === 'COOLDOWN') fixClass = 'is-warn';
  const effectiveMode = status && status.audio_fix_effective_mode ? String(status.audio_fix_effective_mode) : '';
  const silence = status && status.audio_fix_silence_active === true;
  const drift = status && Number.isFinite(Number(status.audio_fix_last_drift_ms))
    ? Number(status.audio_fix_last_drift_ms)
    : null;
  const modeHint = effectiveMode ? ` (${effectiveMode}${silence ? ',silence' : ''})` : (silence ? ' (silence)' : '');
  const driftHint = drift !== null ? ` drift=${drift}ms` : '';
  return {
    config,
    audioText,
    audioClass: audioOk ? 'is-ok' : (detectedHex ? 'is-bad' : ''),
    fixText: `Fix: ${fixState}${modeHint}${driftHint}`,
    fixClass,
  };
}

function normalizeOutputs(outputs, streamId) {
  if (!outputs || outputs.length === 0) {
    return [];
  }
  return outputs.map((out) => {
    if (typeof out === 'string') return out;
    if (out && typeof out === 'object') return { ...out };
    return out;
  });
}

function normalizeTranscodeOutputs(outputs) {
  if (!Array.isArray(outputs) || outputs.length === 0) {
    return [];
  }
  return outputs.map((out) => ({
    ...out,
    v_args: normalizeArgList(out && out.v_args),
    a_args: normalizeArgList(out && out.a_args),
    format_args: normalizeArgList(out && out.format_args),
    metadata: normalizeArgList(out && out.metadata),
  }));
}

function isLibx264Codec(value) {
  const text = String(value || '').trim().toLowerCase();
  return text === '' || text.startsWith('libx264');
}

function hasX264RepeatHeaders(vArgs) {
  if (!Array.isArray(vArgs)) return false;
  const idx = vArgs.findIndex((item) => item === '-x264-params');
  if (idx === -1) return false;
  const value = String(vArgs[idx + 1] || '');
  return value.split(':').some((part) => part.trim().startsWith('repeat-headers='));
}

function toggleX264RepeatHeaders(vArgs, enabled) {
  const args = Array.isArray(vArgs) ? vArgs.slice() : [];
  const idx = args.findIndex((item) => item === '-x264-params');
  if (enabled) {
    if (idx === -1) {
      args.push('-x264-params', 'repeat-headers=1');
      return args;
    }
    const raw = String(args[idx + 1] || '');
    const parts = raw ? raw.split(':').filter(Boolean) : [];
    const filtered = parts.filter((part) => !part.trim().startsWith('repeat-headers='));
    filtered.push('repeat-headers=1');
    args[idx + 1] = filtered.join(':');
    return args;
  }
  if (idx === -1) return args;
  const raw = String(args[idx + 1] || '');
  const parts = raw ? raw.split(':').filter(Boolean) : [];
  const filtered = parts.filter((part) => !part.trim().startsWith('repeat-headers='));
  if (filtered.length) {
    args[idx + 1] = filtered.join(':');
  } else {
    args.splice(idx, 2);
  }
  return args;
}

function updateRepeatHeadersToggle() {
  if (!elements.transcodeOutputRepeatHeaders || !elements.transcodeOutputVcodec) return;
  const isX264 = isLibx264Codec(elements.transcodeOutputVcodec.value);
  elements.transcodeOutputRepeatHeaders.disabled = !isX264;
  if (!isX264) {
    elements.transcodeOutputRepeatHeaders.checked = false;
  }
}

function updateInputProbeRestartToggle() {
  if (!elements.streamTranscodeInputProbeRestart || !elements.streamTranscodeInputProbeUdp) return;
  const enabled = elements.streamTranscodeInputProbeUdp.checked;
  elements.streamTranscodeInputProbeRestart.disabled = !enabled;
  if (!enabled) {
    elements.streamTranscodeInputProbeRestart.checked = false;
  }
}

function updateSeamlessProxyToggle() {
  if (!elements.streamTranscodeProcessPerOutput || !elements.streamTranscodeSeamlessUdpProxy) return;
  const enabled = elements.streamTranscodeProcessPerOutput.checked;
  elements.streamTranscodeSeamlessUdpProxy.disabled = !enabled;
  if (!enabled) {
    elements.streamTranscodeSeamlessUdpProxy.checked = false;
  }
}

const TRANSCODE_OUTPUT_PRESETS = {
  cpu_1080p: {
    name: '1080p',
    vf: 'scale=1920:1080,fps=25',
    vcodec: 'libx264',
    v_args: [
      '-preset', 'slow',
      '-b:v', '5000k',
      '-maxrate', '6000k',
      '-g', '75',
      '-x264-params', 'repeat-headers=1',
    ],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
  cpu_720p: {
    name: '720p',
    vf: 'scale=1280:720,fps=25',
    vcodec: 'libx264',
    v_args: [
      '-preset', 'slow',
      '-b:v', '2500k',
      '-maxrate', '3000k',
      '-g', '75',
      '-x264-params', 'repeat-headers=1',
    ],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
  cpu_540p: {
    name: '540p',
    vf: 'scale=960:540,fps=25',
    vcodec: 'libx264',
    v_args: [
      '-preset', 'slow',
      '-b:v', '1000k',
      '-maxrate', '1500k',
      '-g', '75',
      '-x264-params', 'repeat-headers=1',
    ],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
  nvidia_1080p: {
    name: '1080p',
    vf: 'scale_npp=1920:1080,fps=25',
    vcodec: 'h264_nvenc',
    v_args: ['-preset', 'slow', '-rc', 'vbr_hq', '-b:v', '5000k', '-maxrate', '6000k', '-g', '75'],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
  nvidia_720p: {
    name: '720p',
    vf: 'scale_npp=1280:720,fps=25',
    vcodec: 'h264_nvenc',
    v_args: ['-preset', 'slow', '-rc', 'vbr_hq', '-b:v', '2500k', '-maxrate', '3000k', '-g', '75'],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
  nvidia_540p: {
    name: '540p',
    vf: 'scale_npp=960:540,fps=25',
    vcodec: 'h264_nvenc',
    v_args: ['-preset', 'slow', '-rc', 'vbr_hq', '-b:v', '1000k', '-maxrate', '1500k', '-g', '75'],
    acodec: 'aac',
    a_args: ['-ab', '128k', '-ac', '2', '-strict', '-2'],
    format_args: ['-f', 'mpegts'],
  },
};

const TRANSCODE_WATCHDOG_DEFAULTS = {
  restart_delay_sec: 4,
  restart_jitter_sec: 2,
  restart_backoff_max_sec: 60,
  no_progress_timeout_sec: 8,
  max_error_lines_per_min: 20,
  desync_threshold_ms: 500,
  desync_fail_count: 2,
  probe_interval_sec: 3600,
  probe_duration_sec: 2,
  probe_timeout_sec: 8,
  max_restarts_per_10min: 10,
  probe_fail_count: 2,
  keyframe_miss_count: 3,
  monitor_engine: 'auto',
  low_bitrate_enabled: true,
  low_bitrate_min_kbps: 400,
  low_bitrate_hold_sec: 60,
  restart_cooldown_sec: 1200,
};

const TRANSCODE_PRESETS = {
  cpu_1080p: {
    engine: 'cpu',
    output_preset: 'cpu_1080p',
  },
  cpu_720p: {
    engine: 'cpu',
    output_preset: 'cpu_720p',
  },
  cpu_540p: {
    engine: 'cpu',
    output_preset: 'cpu_540p',
  },
  nvidia_1080p: {
    engine: 'nvidia',
    gpu_device: 0,
    decoder_args: ['-hwaccel', 'nvdec', '-c:v', 'h264_cuvid'],
    output_preset: 'nvidia_1080p',
  },
  nvidia_720p: {
    engine: 'nvidia',
    gpu_device: 0,
    decoder_args: ['-hwaccel', 'nvdec', '-c:v', 'h264_cuvid'],
    output_preset: 'nvidia_720p',
  },
  nvidia_540p: {
    engine: 'nvidia',
    gpu_device: 0,
    decoder_args: ['-hwaccel', 'nvdec', '-c:v', 'h264_cuvid'],
    output_preset: 'nvidia_540p',
  },
};

function normalizeMonitorEngine(value) {
  const text = String(value || '').toLowerCase();
  if (text === 'ffprobe' || text === 'astra_analyze' || text === 'auto') return text;
  return 'auto';
}

function normalizeOutputWatchdog(watchdog, defaults) {
  const base = defaults || TRANSCODE_WATCHDOG_DEFAULTS;
  const wd = watchdog || {};
  const num = (value, fallback) => {
    const parsed = toNumber(value);
    if (parsed !== undefined) return Math.max(0, parsed);
    return Math.max(0, fallback);
  };
  const flag = (value, fallback) => {
    if (value === undefined || value === null) return Boolean(fallback);
    return Boolean(value);
  };
  return {
    restart_delay_sec: num(wd.restart_delay_sec, base.restart_delay_sec),
    restart_jitter_sec: num(wd.restart_jitter_sec, base.restart_jitter_sec),
    restart_backoff_max_sec: num(wd.restart_backoff_max_sec, base.restart_backoff_max_sec),
    no_progress_timeout_sec: num(wd.no_progress_timeout_sec, base.no_progress_timeout_sec),
    max_error_lines_per_min: num(wd.max_error_lines_per_min, base.max_error_lines_per_min),
    desync_threshold_ms: num(wd.desync_threshold_ms, base.desync_threshold_ms),
    desync_fail_count: num(wd.desync_fail_count, base.desync_fail_count),
    probe_interval_sec: num(wd.probe_interval_sec, base.probe_interval_sec),
    probe_duration_sec: num(wd.probe_duration_sec, base.probe_duration_sec),
    probe_timeout_sec: num(wd.probe_timeout_sec, base.probe_timeout_sec),
    max_restarts_per_10min: num(wd.max_restarts_per_10min, base.max_restarts_per_10min),
    probe_fail_count: num(wd.probe_fail_count, base.probe_fail_count),
    keyframe_miss_count: num(wd.keyframe_miss_count, base.keyframe_miss_count),
    monitor_engine: normalizeMonitorEngine(wd.monitor_engine || base.monitor_engine),
    low_bitrate_enabled: flag(wd.low_bitrate_enabled, base.low_bitrate_enabled),
    low_bitrate_min_kbps: num(wd.low_bitrate_min_kbps, base.low_bitrate_min_kbps),
    low_bitrate_hold_sec: num(wd.low_bitrate_hold_sec, base.low_bitrate_hold_sec),
    restart_cooldown_sec: num(wd.restart_cooldown_sec, base.restart_cooldown_sec),
  };
}

function ensureTranscodeOutputWatchdog(output) {
  if (!output || typeof output !== 'object') return output;
  const base = state.transcodeWatchdogDefaults || normalizeOutputWatchdog(null, TRANSCODE_WATCHDOG_DEFAULTS);
  return {
    ...output,
    watchdog: normalizeOutputWatchdog(output.watchdog, base),
  };
}

function isOutputMonitorEnabled(watchdog) {
  if (!watchdog) return false;
  return (watchdog.probe_interval_sec > 0)
    || (watchdog.no_progress_timeout_sec > 0)
    || (watchdog.max_error_lines_per_min > 0)
    || (watchdog.low_bitrate_enabled === true);
}

function formatShortDuration(seconds) {
  const value = Math.max(0, Math.round(seconds || 0));
  if (value >= 3600) {
    const hours = Math.floor(value / 3600);
    const mins = Math.floor((value % 3600) / 60);
    return `${hours}h ${mins}m`;
  }
  if (value >= 60) {
    const mins = Math.floor(value / 60);
    const secs = value % 60;
    return `${mins}m ${secs}s`;
  }
  return `${value}s`;
}

function applyTranscodeOutputPreset(key) {
  const preset = TRANSCODE_OUTPUT_PRESETS[key];
  if (!preset) return;
  if (elements.transcodeOutputName && !elements.transcodeOutputName.value.trim()) {
    elements.transcodeOutputName.value = preset.name || '';
  }
  if (elements.transcodeOutputVf) elements.transcodeOutputVf.value = preset.vf || '';
  if (elements.transcodeOutputVcodec) elements.transcodeOutputVcodec.value = preset.vcodec || '';
  if (elements.transcodeOutputVArgs) elements.transcodeOutputVArgs.value = argsToLines(preset.v_args);
  if (elements.transcodeOutputRepeatHeaders) {
    elements.transcodeOutputRepeatHeaders.checked = hasX264RepeatHeaders(preset.v_args);
    updateRepeatHeadersToggle();
  }
  if (elements.transcodeOutputAcodec) elements.transcodeOutputAcodec.value = preset.acodec || '';
  if (elements.transcodeOutputAArgs) elements.transcodeOutputAArgs.value = argsToLines(preset.a_args);
  if (elements.transcodeOutputFormatArgs) elements.transcodeOutputFormatArgs.value = argsToLines(preset.format_args);
}

function buildTranscodeOutputFromPreset(key) {
  const preset = TRANSCODE_OUTPUT_PRESETS[key];
  if (!preset) return null;
  return {
    name: preset.name || '',
    vf: preset.vf || '',
    vcodec: preset.vcodec || '',
    v_args: Array.isArray(preset.v_args) ? preset.v_args.slice() : [],
    acodec: preset.acodec || '',
    a_args: Array.isArray(preset.a_args) ? preset.a_args.slice() : [],
    format_args: Array.isArray(preset.format_args) ? preset.format_args.slice() : [],
  };
}

function getDefaultTranscodeOutputUrl(presetKey) {
  const basePort = 1234;
  let offset = 0;
  if (presetKey && presetKey.indexOf('720p') !== -1) offset = 1;
  if (presetKey && presetKey.indexOf('540p') !== -1) offset = 2;
  const port = basePort + offset;
  return `udp://239.1.1.1:${port}?pkt_size=1316`;
}

function isTranscodeOutputEmpty(output) {
  if (!output) return true;
  const hasVArgs = Array.isArray(output.v_args) && output.v_args.length > 0;
  const hasAArgs = Array.isArray(output.a_args) && output.a_args.length > 0;
  const hasFArgs = Array.isArray(output.format_args) && output.format_args.length > 0;
  const hasMeta = Array.isArray(output.metadata) && output.metadata.length > 0;
  return !output.url && !output.name && !output.vf && !output.vcodec && !output.acodec
    && !hasVArgs && !hasAArgs && !hasFArgs && !hasMeta;
}

function applyStreamTranscodePreset(key) {
  const preset = TRANSCODE_PRESETS[key];
  if (!preset) return;

  if (elements.streamType) {
    elements.streamType.value = 'transcode';
    setTranscodeMode(true);
  }
  if (elements.streamTranscodeEngine) {
    elements.streamTranscodeEngine.value = preset.engine || '';
  }
  if (elements.streamTranscodeGpuDevice) {
    elements.streamTranscodeGpuDevice.value = preset.gpu_device !== undefined ? preset.gpu_device : '';
  }
  if (elements.streamTranscodeGlobalArgs) {
    elements.streamTranscodeGlobalArgs.value = argsToLines(preset.global_args);
  }
  if (elements.streamTranscodeDecoderArgs) {
    elements.streamTranscodeDecoderArgs.value = argsToLines(preset.decoder_args);
  }
  if (elements.streamTranscodeCommonArgs) {
    elements.streamTranscodeCommonArgs.value = argsToLines(preset.common_output_args);
  }
  if (elements.streamTranscodeLogMain) {
    elements.streamTranscodeLogMain.checked = true;
  }

  const outputPreset = preset.output_preset;
  if (outputPreset) {
    if (!Array.isArray(state.transcodeOutputs)) {
      state.transcodeOutputs = [];
    }
    let targetIndex = state.transcodeOutputs.findIndex(isTranscodeOutputEmpty);
    if (targetIndex === -1) {
      targetIndex = state.transcodeOutputs.length;
      state.transcodeOutputs.push({});
    }
    const presetOutput = buildTranscodeOutputFromPreset(outputPreset);
    if (presetOutput) {
      const existing = state.transcodeOutputs[targetIndex];
      if (!existing || !existing.url) {
        presetOutput.url = getDefaultTranscodeOutputUrl(outputPreset);
      }
      state.transcodeOutputs[targetIndex] = { ...state.transcodeOutputs[targetIndex], ...presetOutput };
    }
    state.transcodeOutputs = state.transcodeOutputs.map(ensureTranscodeOutputWatchdog);
    renderTranscodeOutputList();
  }
}

function getOutputUiType(output) {
  if (!output || !output.format) return 'http';
  if (output.format === 'http' || output.format === 'hls') return 'http';
  return output.format;
}

function getOutputUiMode(output) {
  if (!output || output.format !== 'hls') return 'http';
  return 'hls';
}

const INPUT_PRESETS = {
  udp_multicast: {
    type: 'udp',
    iface: '',
    addr: '239.1.1.1',
    port: 1234,
    socket_size: 0,
  },
  rtp_multicast: {
    type: 'rtp',
    iface: '',
    addr: '239.1.1.1',
    port: 1234,
    socket_size: 0,
  },
  http_ts: {
    type: 'http',
    host: 'example.com',
    port: 80,
    path: '/stream',
    ua: 'Astra',
    timeout: 10,
    buffer_size: 1024,
  },
  hls_m3u8: {
    type: 'hls',
    host: 'example.com',
    port: 80,
    path: '/index.m3u8',
    ua: 'Astra',
    timeout: 10,
    buffer_size: 1024,
  },
  srt_caller: {
    type: 'srt',
    url: 'srt://host:port?mode=caller',
    bridge_port: 14000,
  },
  rtsp_tcp: {
    type: 'rtsp',
    url: 'rtsp://host:554/stream',
    bridge_port: 14000,
    extra_options: {
      rtsp_transport: 'tcp',
    },
  },
  file_loop: {
    type: 'file',
    filename: '/mnt/raid0/file.ts',
    loop: true,
  },
};

function applyInputPreset(key) {
  const preset = INPUT_PRESETS[key];
  if (!preset) return;
  const format = preset.type || 'udp';
  elements.inputType.value = format;
  const group = (format === 'rtp') ? 'udp'
    : (format === 'hls' ? 'http'
      : (format === 'srt' || format === 'rtsp' ? 'bridge' : format));
  setInputGroup(group);

  if (format === 'udp' || format === 'rtp') {
    elements.inputUdpIface.value = preset.iface || '';
    elements.inputUdpAddr.value = preset.addr || '239.1.1.1';
    elements.inputUdpPort.value = preset.port || 1234;
    elements.inputUdpSocket.value = preset.socket_size || 0;
  } else if (format === 'http' || format === 'hls') {
    elements.inputHttpHost.value = preset.host || '';
    elements.inputHttpPort.value = preset.port || 80;
    elements.inputHttpPath.value = preset.path || '/stream';
    elements.inputHttpUa.value = preset.ua || '';
    elements.inputHttpTimeout.value = preset.timeout || 10;
    elements.inputHttpBuffer.value = preset.buffer_size || 1024;
  } else if (format === 'srt' || format === 'rtsp') {
    elements.inputBridgeUrl.value = preset.url || '';
    elements.inputBridgePort.value = preset.bridge_port || 14000;
  } else if (format === 'file') {
    elements.inputFileName.value = preset.filename || '';
    elements.inputFileLoop.checked = preset.loop === true;
  }

  if (preset.extra_options && state.inputEditingIndex !== null) {
    const current = state.inputExtras[state.inputEditingIndex] || {};
    state.inputExtras[state.inputEditingIndex] = { ...current, ...preset.extra_options };
  }
}

const OUTPUT_PRESETS = {
  http_ts: {
    type: 'http',
    mode: 'http',
    host: '0.0.0.0',
    port: 8000,
    path: '/stream',
    buffer_size: 1024,
    buffer_fill: 256,
    keep_active: false,
  },
  hls_basic: {
    type: 'http',
    mode: 'hls',
    playlist: 'index.m3u8',
    prefix: 'segment',
    target_duration: 6,
    window: 5,
    cleanup: 10,
    use_wall: true,
  },
  udp_multicast: {
    type: 'udp',
    addr: '239.0.0.1',
    port: 1234,
    ttl: 1,
    localaddr: '',
    socket_size: '',
    sync: '',
    cbr: '',
  },
  rtp_multicast: {
    type: 'rtp',
    addr: '239.0.0.1',
    port: 1234,
    ttl: 1,
    localaddr: '',
    socket_size: '',
    sync: '',
    cbr: '',
  },
  srt_bridge: {
    type: 'srt',
    url: 'srt://host:port?mode=caller',
    bridge_port: 14000,
  },
  np_push: {
    type: 'np',
    host: 'example.com',
    port: 80,
    path: '/push',
    timeout: 5,
    buffer_size: 1024,
  },
  file_ts: {
    type: 'file',
    filename: '/tmp/stream.ts',
    buffer_size: 32,
    m2ts: false,
    aio: false,
    directio: false,
  },
};

function applyOutputPreset(key) {
  const preset = OUTPUT_PRESETS[key];
  if (!preset) return;

  const type = preset.type;
  elements.outputType.value = type;
  setOutputGroup(type === 'rtp' ? 'udp' : type);

  if (type === 'http') {
    const mode = preset.mode || 'http';
    elements.outputHttpMode.value = mode;
    setOutputHttpMode(mode);

    if (mode === 'http') {
      elements.outputHttpHost.value = preset.host || '0.0.0.0';
      elements.outputHttpPort.value = preset.port || 8000;
      elements.outputHttpPath.value = preset.path || '/stream';
      elements.outputHttpBuffer.value = preset.buffer_size || 1024;
      elements.outputHttpBufferFill.value = preset.buffer_fill || 256;
      elements.outputHttpKeep.checked = preset.keep_active === true;
      if (elements.outputHttpSctp) {
        elements.outputHttpSctp.checked = preset.sctp === true;
      }
    } else {
      const defaults = defaultHlsOutput(elements.streamId.value || 'stream');
      const useWall = preset.use_wall !== undefined ? preset.use_wall : defaults.use_wall;
      elements.outputHlsPath.value = defaults.path;
      elements.outputHlsBase.value = defaults.base_url;
      elements.outputHlsPlaylist.value = preset.playlist || defaults.playlist || 'index.m3u8';
      elements.outputHlsPrefix.value = preset.prefix || defaults.prefix || 'segment';
      elements.outputHlsTarget.value = preset.target_duration || defaults.target_duration || 6;
      elements.outputHlsWindow.value = preset.window || defaults.window || 5;
      elements.outputHlsCleanup.value = preset.cleanup || defaults.cleanup || 10;
      elements.outputHlsWall.checked = useWall !== false;
      if (elements.outputHlsNaming) {
        elements.outputHlsNaming.value = preset.naming || defaults.naming || getSettingString('hls_naming', 'sequence');
      }
      if (elements.outputHlsRound) {
        elements.outputHlsRound.checked = preset.round_duration === true;
      }
      if (elements.outputHlsTsExtension) {
        elements.outputHlsTsExtension.value = preset.ts_extension || getSettingString('hls_ts_extension', 'ts');
      }
      if (elements.outputHlsPassData) {
        elements.outputHlsPassData.checked = preset.pass_data !== false;
      }
    }
    return;
  }

  if (type === 'udp' || type === 'rtp') {
    elements.outputUdpAddr.value = preset.addr || '239.0.0.1';
    elements.outputUdpPort.value = preset.port || 1234;
    elements.outputUdpTtl.value = preset.ttl || 1;
    elements.outputUdpLocal.value = preset.localaddr || '';
    elements.outputUdpSocket.value = preset.socket_size || '';
    elements.outputUdpSync.value = preset.sync || '';
    elements.outputUdpCbr.value = preset.cbr || '';
    return;
  }

  if (type === 'srt') {
    elements.outputSrtUrl.value = preset.url || '';
    elements.outputSrtBridgePort.value = preset.bridge_port || '';
    if (elements.outputSrtBridgeAddr) {
      elements.outputSrtBridgeAddr.value = preset.bridge_addr || '127.0.0.1';
    }
    if (elements.outputSrtBridgeLocaladdr) {
      elements.outputSrtBridgeLocaladdr.value = preset.bridge_localaddr || '';
    }
    if (elements.outputSrtBridgePktSize) {
      elements.outputSrtBridgePktSize.value = preset.bridge_pkt_size || 1316;
    }
    if (elements.outputSrtBridgeSocket) {
      elements.outputSrtBridgeSocket.value = preset.bridge_socket_size || '';
    }
    if (elements.outputSrtBridgeTtl) {
      elements.outputSrtBridgeTtl.value = preset.bridge_ttl || '';
    }
    if (elements.outputSrtBridgeBin) {
      elements.outputSrtBridgeBin.value = preset.bridge_bin || '';
    }
    if (elements.outputSrtBridgeLog) {
      elements.outputSrtBridgeLog.value = preset.bridge_log_level || 'warning';
    }
    return;
  }

  if (type === 'np') {
    elements.outputNpHost.value = preset.host || '';
    elements.outputNpPort.value = preset.port || 80;
    elements.outputNpPath.value = preset.path || '/push';
    elements.outputNpTimeout.value = preset.timeout || 5;
    elements.outputNpBuffer.value = preset.buffer_size || '';
    if (elements.outputNpBufferFill) {
      elements.outputNpBufferFill.value = preset.buffer_fill || '';
    }
    if (elements.outputNpSctp) {
      elements.outputNpSctp.checked = preset.sctp === true;
    }
    return;
  }

  if (type === 'file') {
    elements.outputFileName.value = preset.filename || '/tmp/stream.ts';
    elements.outputFileBuffer.value = preset.buffer_size || 32;
    elements.outputFileM2ts.checked = preset.m2ts === true;
    elements.outputFileAio.checked = preset.aio === true;
    elements.outputFileDirectio.checked = preset.directio === true;
  }
}

function normalizeUrlText(value) {
  return String(value || '').trim();
}

function hasUrlScheme(value) {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(value);
}

function isLikelyLocalPath(value) {
  if (!value) return false;
  if (value.startsWith('file:')) return true;
  if (value.startsWith('/') || value.startsWith('./') || value.startsWith('../')) return true;
  return /^[a-zA-Z]:[\\/]/.test(value);
}

function ensureLeadingSlash(value) {
  if (!value) return '';
  return value.startsWith('/') ? value : `/${value}`;
}

function formatFileUrl(pathValue) {
  const path = normalizeUrlText(pathValue);
  if (!path) return '';
  if (path.startsWith('file:')) return path;
  return `file:${path}`;
}

function formatHostUrl(schemeValue, hostValue, portValue, pathValue) {
  const scheme = normalizeUrlText(schemeValue || 'http').toLowerCase();
  const host = normalizeUrlText(hostValue);
  const port = Number(portValue);
  const portPart = Number.isFinite(port) && port > 0 ? `:${port}` : '';
  const path = ensureLeadingSlash(normalizeUrlText(pathValue));
  if (!host) return path || '';
  return `${scheme}://${host}${portPart}${path}`;
}

function formatSchemeUrl(schemeValue, output, rawUrl) {
  const scheme = normalizeUrlText(schemeValue).toLowerCase();
  if (rawUrl) {
    if (hasUrlScheme(rawUrl)) return rawUrl;
    if (rawUrl.startsWith('/')) return rawUrl;
    return `${scheme}://${rawUrl}`;
  }
  const host = normalizeUrlText(output && (output.host || output.addr || output.ip));
  const port = Number(output && output.port);
  const portPart = Number.isFinite(port) && port > 0 ? `:${port}` : '';
  if (!host && !portPart) return scheme;
  return `${scheme}://${host}${portPart}`;
}

function formatUdpUrl(formatValue, output, rawUrl) {
  const format = normalizeUrlText(formatValue || 'udp').toLowerCase();
  const addr = normalizeUrlText(output && (output.addr || output.ip || output.host));
  const port = Number(output && output.port);
  const portPart = Number.isFinite(port) && port > 0 ? `:${port}` : '';
  const iface = normalizeUrlText(output && (output.iface || output.interface || output.localaddr));
  const query = normalizeUrlText(output && (output.query || output.params || output.options));
  if (!addr && rawUrl) {
    if (hasUrlScheme(rawUrl)) return rawUrl;
    return `${format}://${rawUrl}`;
  }
  if (!addr && !portPart) return '';
  let base = `${format}://`;
  if (iface) base += `${iface}@`;
  base += addr;
  base += portPart;
  if (query) {
    base += `?${query.replace(/^\?/, '')}`;
  }
  return base;
}

function formatHlsOutput(output, settings, rawUrl) {
  const playlist = normalizeUrlText(output && output.playlist) || 'index.m3u8';
  const baseUrl = normalizeUrlText(output && (output.publish_url || output.base_url));
  if (baseUrl) {
    return joinPath(baseUrl, playlist);
  }
  if (rawUrl) {
    if (hasUrlScheme(rawUrl)) return rawUrl;
    if (rawUrl.startsWith('/')) return rawUrl;
  }
  const path = normalizeUrlText(output && (output.path || output.dir));
  if (path) {
    const hlsDir = normalizeUrlText(settings && settings.hls_dir);
    const hlsBase = normalizeUrlText(settings && settings.hls_base_url);
    if (hlsDir && hlsBase && path.startsWith(hlsDir)) {
      let relative = path.slice(hlsDir.length);
      relative = relative.replace(/^\/+/, '');
      if (relative) {
        return joinPath(joinPath(hlsBase, relative), playlist);
      }
    }
    return formatFileUrl(path);
  }
  return rawUrl || '';
}

function splitHlsPath(value) {
  let path = value || '';
  let suffix = '';
  const qIdx = path.indexOf('?');
  const hIdx = path.indexOf('#');
  let cutIdx = -1;
  if (qIdx >= 0 && hIdx >= 0) cutIdx = Math.min(qIdx, hIdx);
  else if (qIdx >= 0) cutIdx = qIdx;
  else if (hIdx >= 0) cutIdx = hIdx;
  if (cutIdx >= 0) {
    suffix = path.slice(cutIdx);
    path = path.slice(0, cutIdx);
  }
  const idx = path.lastIndexOf('/');
  const dir = idx >= 0 ? path.slice(0, idx) : '';
  const file = idx >= 0 ? path.slice(idx + 1) : path;
  return { dir, file, suffix };
}

function parseHlsInlineUrl(text, existing) {
  const output = {};
  const raw = String(text || '').trim();
  if (!raw) return output;

  if (hasUrlScheme(raw)) {
    try {
      const parsed = new URL(raw);
      const split = splitHlsPath(parsed.pathname || '');
      const suffix = `${parsed.search || ''}${parsed.hash || ''}`;
      if (split.file && split.file.toLowerCase().endsWith('.m3u8')) {
        output.base_url = parsed.origin + (split.dir ? (split.dir.startsWith('/') ? split.dir : `/${split.dir}`) : '');
        output.playlist = `${split.file}${suffix}`;
      } else {
        let base = parsed.origin + (parsed.pathname || '');
        base = base.replace(/\/+$/, '');
        output.base_url = base || parsed.origin;
        if (existing && existing.playlist) output.playlist = existing.playlist;
      }
      return output;
    } catch (err) {
    }
  }

  let local = raw;
  if (local.startsWith('file://')) local = local.slice(7);
  if (local.startsWith('file:')) local = local.slice(5);
  const split = splitHlsPath(local);
  if (split.file && split.file.toLowerCase().endsWith('.m3u8')) {
    output.path = split.dir || '';
    output.playlist = `${split.file}${split.suffix}`;
  } else {
    output.path = local;
  }
  return output;
}

function parseBissKey(value) {
  const raw = String(value || '').trim();
  if (!raw) return { value: '', error: null };
  if (/[^0-9a-fA-F:\s-]/.test(raw)) {
    return { value: '', error: 'BISS key must contain only hex characters' };
  }
  const compact = raw.replace(/[\s:-]/g, '');
  if (compact.length !== 16) {
    return { value: '', error: 'BISS key must be 16 hex characters' };
  }
  return { value: compact.toLowerCase(), error: null };
}

function formatOutputDisplay(output, settings) {
  if (!output) return '';
  if (typeof output === 'string') return normalizeUrlText(output);

  const rawUrl = normalizeUrlText(output.url || output.source_url);
  if (rawUrl && hasUrlScheme(rawUrl)) return rawUrl;

  const format = normalizeUrlText(output.format || output.type).toLowerCase();
  if (format === 'hls') {
    return formatHlsOutput(output, settings, rawUrl);
  }
  if (format === 'http' || format === 'https') {
    return formatHostUrl(output.scheme || format, output.host, output.port, output.path);
  }
  if (format === 'udp' || format === 'rtp') {
    return formatUdpUrl(format, output, rawUrl);
  }
  if (format === 'srt' || format === 'rtsp' || format === 'rtmp') {
    return formatSchemeUrl(format, output, rawUrl);
  }
  if (format === 'np') {
    return formatHostUrl(output.scheme || 'http', output.host, output.port, output.path);
  }
  if (format === 'file') {
    return formatFileUrl(output.filename || rawUrl || output.path);
  }
  if (rawUrl) return rawUrl;
  return normalizeUrlText(output.path || output.filename || output.dir || '');
}

function getOutputInlineValue(output, settings) {
  if (!output) return '';
  if (typeof output === 'string') return normalizeUrlText(output);
  return formatOutputDisplay(output, settings) || '';
}

function parseHostPortPath(text) {
  let hostPart = text || '';
  let path = '/';
  const slashIdx = hostPart.indexOf('/');
  if (slashIdx >= 0) {
    path = hostPart.slice(slashIdx) || '/';
    hostPart = hostPart.slice(0, slashIdx);
  }
  const atIdx = hostPart.lastIndexOf('@');
  if (atIdx >= 0) {
    hostPart = hostPart.slice(atIdx + 1);
  }
  let host = hostPart;
  let port = '';
  if (hostPart.startsWith('[')) {
    const end = hostPart.indexOf(']');
    if (end >= 0) {
      host = hostPart.slice(0, end + 1);
      const rest = hostPart.slice(end + 1);
      if (rest.startsWith(':')) port = rest.slice(1);
    }
  } else {
    const colonIdx = hostPart.lastIndexOf(':');
    if (colonIdx >= 0) {
      host = hostPart.slice(0, colonIdx);
      port = hostPart.slice(colonIdx + 1);
    }
  }
  return { host, port, path };
}

function parseOutputInlineValue(value, existing) {
  const text = String(value || '').trim();
  if (!text) return { output: existing, valid: false };

  const existingFormat = String(existing && (existing.format || existing.type) || '').toLowerCase();
  const looksLikeHls = existingFormat === 'hls' || text.toLowerCase().includes('.m3u8');
  let scheme = '';
  let rest = text;
  const match = rest.match(/^([a-zA-Z][a-zA-Z0-9+.-]*):\/\//);
  if (match) {
    scheme = match[1].toLowerCase();
    rest = rest.slice(match[0].length);
  }

  let format = '';
  const next = {};

  if (scheme === 'file') {
    if (existingFormat === 'hls') {
      format = 'hls';
      Object.assign(next, parseHlsInlineUrl(text, existing));
    } else {
      format = 'file';
      next.filename = rest;
    }
  } else if (scheme === 'udp' || scheme === 'rtp') {
    format = scheme;
    let addrPart = rest;
    const queryIdx = addrPart.indexOf('?');
    if (queryIdx >= 0) addrPart = addrPart.slice(0, queryIdx);
    const atIdx = addrPart.indexOf('@');
    if (atIdx >= 0) {
      next.localaddr = addrPart.slice(0, atIdx);
      addrPart = addrPart.slice(atIdx + 1);
    }
    const colonIdx = addrPart.lastIndexOf(':');
    if (colonIdx >= 0) {
      next.addr = addrPart.slice(0, colonIdx);
      next.port = toNumber(addrPart.slice(colonIdx + 1));
    } else {
      next.addr = addrPart;
    }
  } else if (scheme === 'srt' || scheme === 'rtsp' || scheme === 'rtmp') {
    format = scheme;
    next.url = text;
  } else if (scheme === 'np') {
    format = 'np';
    const parsed = parseHostPortPath(rest);
    next.host = parsed.host;
    next.port = toNumber(parsed.port);
    next.path = parsed.path;
    next.scheme = 'np';
  } else if (scheme === 'http' || scheme === 'https') {
    if (looksLikeHls && existingFormat !== 'np') {
      format = 'hls';
      Object.assign(next, parseHlsInlineUrl(text, existing));
    } else {
      const parsed = parseHostPortPath(rest);
      format = existingFormat === 'np' ? 'np' : 'http';
      next.host = parsed.host;
      next.port = toNumber(parsed.port);
      next.path = parsed.path;
      next.scheme = scheme;
    }
  } else if (!scheme) {
    if (text.endsWith('.m3u8') || existingFormat === 'hls') {
      format = 'hls';
      Object.assign(next, parseHlsInlineUrl(text, existing));
    } else if (existingFormat === 'file') {
      format = 'file';
      next.filename = text;
    } else if (existingFormat === 'np') {
      format = 'np';
      const parsed = parseHostPortPath(text);
      next.host = parsed.host;
      next.port = toNumber(parsed.port);
      next.path = parsed.path;
    } else if (existingFormat === 'udp' || existingFormat === 'rtp') {
      format = existingFormat || 'udp';
      let addrPart = text;
      const queryIdx = addrPart.indexOf('?');
      if (queryIdx >= 0) addrPart = addrPart.slice(0, queryIdx);
      const atIdx = addrPart.indexOf('@');
      if (atIdx >= 0) {
        next.localaddr = addrPart.slice(0, atIdx);
        addrPart = addrPart.slice(atIdx + 1);
      }
      const colonIdx = addrPart.lastIndexOf(':');
      if (colonIdx >= 0) {
        next.addr = addrPart.slice(0, colonIdx);
        next.port = toNumber(addrPart.slice(colonIdx + 1));
      } else {
        next.addr = addrPart;
      }
    }
  }

  if (!format) return { output: existing, valid: false };

  const base = existing && String(existing.format || existing.type || '').toLowerCase() === format
    ? { ...existing }
    : {};

  const applyField = (key, value) => {
    if (value === undefined || value === null || value === '') {
      delete base[key];
    } else {
      base[key] = value;
    }
  };

  base.format = format;
  applyField('scheme', next.scheme);
  applyField('addr', next.addr);
  applyField('port', next.port);
  applyField('host', next.host);
  applyField('path', next.path);
  applyField('localaddr', next.localaddr);
  applyField('url', next.url);
  applyField('filename', next.filename);

  if (format === 'hls') {
    applyField('base_url', next.base_url);
    applyField('playlist', next.playlist);
    if (next.path !== undefined) {
      applyField('path', next.path);
      delete base.base_url;
    } else if (next.base_url !== undefined || next.playlist !== undefined) {
      delete base.path;
    }
  }

  delete base._inline_value;
  delete base._inline_invalid;

  return { output: base, valid: true };
}

function applyOutputInlineValue(index, value) {
  const current = state.outputs[index];
  if (!current) return;
  const text = String(value || '').trim();
  if (typeof current === 'string') {
    state.outputs[index] = text;
    renderOutputList();
    return;
  }
  if (!text) {
    state.outputs[index] = '';
    renderOutputList();
    return;
  }
  const result = parseOutputInlineValue(value, current);
  if (!result || !result.output) return;
  if (!result.valid) {
    state.outputs[index] = text;
    renderOutputList();
    return;
  }
  const updated = result.output;
  updated._inline_value = value;
  updated._inline_invalid = false;
  state.outputs[index] = updated;
  renderOutputList();
}

function syncOutputInlineValues() {
  if (!Array.isArray(state.outputs)) return;
  state.outputs = state.outputs.map((output) => {
    if (!output || output._inline_value === undefined) return output;
    const text = String(output._inline_value || '').trim();
    if (!text) return '';
    const result = parseOutputInlineValue(output._inline_value, output);
    if (!result || !result.output) return output;
    if (!result.valid) return text;
    const updated = result.output;
    updated._inline_value = output._inline_value;
    updated._inline_invalid = false;
    return updated;
  });
}

function transcodeOutputSummary(output, index) {
  const name = output && output.name ? output.name : `Output #${index + 1}`;
  const url = output && output.url ? shortInputLabel(output.url) : 'missing URL';
  return `${name} — ${url}`;
}

function normalizeInputs(inputs) {
  if (!inputs || inputs.length === 0) {
    return [''];
  }
  return inputs.map((input) => {
    if (typeof input === 'string') return input;
    if (input && typeof input === 'object') {
      return buildInputUrl(input);
    }
    return '';
  });
}

function mapToString(value) {
  if (!value) return '';
  if (typeof value === 'string') return value;
  if (Array.isArray(value)) {
    return value.map((entry) => {
      if (Array.isArray(entry)) return entry.join('=');
      if (typeof entry === 'string') return entry;
      return String(entry);
    }).join(',');
  }
  return String(value);
}

function hasAnyValue(obj) {
  if (!obj || typeof obj !== 'object') return false;
  return Object.values(obj).some((value) => {
    if (value === undefined || value === null || value === '') return false;
    if (typeof value === 'object') return hasAnyValue(value);
    return true;
  });
}

function parseOptionsString(optionString) {
  const options = {};
  const mapEntries = [];
  if (!optionString) return options;
  optionString.split('&').forEach((pair) => {
    if (!pair) return;
    const idx = pair.indexOf('=');
    const key = idx >= 0 ? pair.slice(0, idx) : pair;
    const value = idx >= 0 ? pair.slice(idx + 1) : true;
    if (key.startsWith('map.')) {
      const mapKey = key.slice(4);
      mapEntries.push(`${mapKey}=${value}`);
    } else {
      options[key] = value;
    }
  });
  if (!options.map && mapEntries.length) {
    options.map = mapEntries.join(',');
  }
  return options;
}

function parseInputUrl(url) {
  const out = {
    format: '',
    options: {},
    dvbId: '',
    iface: '',
    addr: '',
    port: '',
    login: '',
    password: '',
    host: '',
    path: '',
    url: '',
    file: '',
    streamId: '',
  };
  if (!url) return out;
  const parts = url.split('#');
  const base = parts[0];
  out.options = parseOptionsString(parts[1] || '');

  const schemeIndex = base.indexOf('://');
  if (schemeIndex === -1) return out;
  out.format = base.slice(0, schemeIndex).toLowerCase();
  let rest = base.slice(schemeIndex + 3);

  if (out.format === 'udp' || out.format === 'rtp') {
    const atIdx = rest.indexOf('@');
    if (atIdx >= 0) {
      out.iface = rest.slice(0, atIdx);
      rest = rest.slice(atIdx + 1);
    }
    const colon = rest.lastIndexOf(':');
    if (colon >= 0) {
      out.addr = rest.slice(0, colon);
      out.port = rest.slice(colon + 1);
    } else {
      out.addr = rest;
    }
    return out;
  }

  if (out.format === 'http' || out.format === 'https' || out.format === 'hls') {
    let hostPart = rest;
    const slashIdx = rest.indexOf('/');
    if (slashIdx >= 0) {
      hostPart = rest.slice(0, slashIdx);
      out.path = rest.slice(slashIdx);
    } else {
      out.path = '/';
    }
    const atIdx = hostPart.indexOf('@');
    if (atIdx >= 0) {
      const auth = hostPart.slice(0, atIdx);
      hostPart = hostPart.slice(atIdx + 1);
      const colonIdx = auth.indexOf(':');
      if (colonIdx >= 0) {
        out.login = auth.slice(0, colonIdx);
        out.password = auth.slice(colonIdx + 1);
      } else {
        out.login = auth;
      }
    }
    const colonIdx = hostPart.lastIndexOf(':');
    if (colonIdx >= 0) {
      out.host = hostPart.slice(0, colonIdx);
      out.port = hostPart.slice(colonIdx + 1);
    } else {
      out.host = hostPart;
    }
    return out;
  }

  if (out.format === 'srt' || out.format === 'rtsp') {
    out.url = base;
    return out;
  }

  if (out.format === 'file') {
    out.file = rest;
    return out;
  }

  if (out.format === 'stream') {
    out.streamId = rest;
    return out;
  }

  if (out.format === 'dvb') {
    out.dvbId = rest;
    return out;
  }

  return out;
}

function buildInputUrl(data) {
  if (!data) return '';
  if (typeof data === 'string') return data;

  let format = (data.format || '').toLowerCase();
  if (!format && data.url) return data.url;

  if (format === 'rtp') {
    format = 'rtp';
  }

  let base = '';
  if (format === 'dvb') {
    base = `dvb://${data.dvbId || ''}`;
  } else if (format === 'udp' || format === 'rtp') {
    const iface = data.iface ? `${data.iface}@` : '';
    const addr = data.addr || '';
    const port = data.port ? `:${data.port}` : '';
    base = `${format}://${iface}${addr}${port}`;
  } else if (format === 'http' || format === 'https' || format === 'hls') {
    const auth = data.login ? `${data.login}${data.password ? `:${data.password}` : ''}@` : '';
    const host = data.host || '';
    const port = data.port ? `:${data.port}` : '';
    const path = data.path || '/';
    base = `${format}://${auth}${host}${port}${path}`;
  } else if (format === 'srt' || format === 'rtsp') {
    base = data.url || '';
    if (!base) return '';
  } else if (format === 'file') {
    base = `file://${data.file || ''}`;
  } else if (format === 'stream') {
    base = `stream://${data.streamId || ''}`;
  } else {
    return data.url || '';
  }

  const opts = [];
  const addOpt = (key, value) => {
    if (value === undefined || value === null || value === '') return;
    if (value === true) {
      opts.push(key);
    } else {
      opts.push(`${key}=${value}`);
    }
  };

  const o = data.options || data;
  addOpt('pnr', o.pnr);
  addOpt('set_pnr', o.set_pnr);
  addOpt('set_tsid', o.set_tsid);
  addOpt('biss', o.biss);
  addOpt('cam', o.cam);
  addOpt('ecm_pid', o.ecm_pid);
  addOpt('shift', o.shift);
  addOpt('cas', o.cas);
  addOpt('map', o.map);
  addOpt('filter', o.filter);
  addOpt('filter~', o['filter~']);
  addOpt('pass_sdt', o.pass_sdt);
  addOpt('pass_eit', o.pass_eit);
  addOpt('no_reload', o.no_reload);
  addOpt('no_analyze', o.no_analyze);
  addOpt('cc_limit', o.cc_limit);
  addOpt('bitrate_limit', o.bitrate_limit);
  addOpt('ua', o.ua);
  addOpt('timeout', o.timeout);
  addOpt('buffer_size', o.buffer_size);
  addOpt('socket_size', o.socket_size);
  addOpt('loop', o.loop);
  addOpt('bridge_port', o.bridge_port);

  if (data.options) {
    const known = new Set([
      'pnr',
      'set_pnr',
      'set_tsid',
      'biss',
      'cam',
      'ecm_pid',
      'shift',
      'cas',
      'map',
      'filter',
      'filter~',
      'pass_sdt',
      'pass_eit',
      'no_reload',
      'no_analyze',
      'cc_limit',
      'bitrate_limit',
      'ua',
      'timeout',
      'buffer_size',
      'socket_size',
      'loop',
      'bridge_port',
    ]);
    Object.keys(data.options).forEach((key) => {
      if (!known.has(key)) {
        addOpt(key, data.options[key]);
      }
    });
  }

  if (opts.length === 0) return base;
  return `${base}#${opts.join('&')}`;
}

function renderOutputList() {
  elements.outputList.innerHTML = '';
  if (state.outputs.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'panel subtle';
    empty.textContent = 'No outputs configured.';
    elements.outputList.appendChild(empty);
    return;
  }

  state.outputs.forEach((output, index) => {
    const row = document.createElement('div');
    row.className = 'list-row output-row';
    row.dataset.index = String(index);

    const idx = document.createElement('div');
    idx.className = 'list-index';
    idx.textContent = `#${index + 1}`;

    const label = document.createElement('div');
    label.className = 'output-label';
    const displayUrl = getOutputInlineValue(output, state.settings);
    const inlineInput = document.createElement('input');
    inlineInput.className = 'list-input output-inline';
    inlineInput.type = 'text';
    inlineInput.value = output._inline_value !== undefined ? output._inline_value : (displayUrl || '');
    inlineInput.placeholder = 'Output URL';
    if (displayUrl) {
      inlineInput.title = displayUrl;
    }
    if (output._inline_invalid) {
      inlineInput.classList.add('is-invalid');
    }
    inlineInput.addEventListener('input', () => {
      output._inline_value = inlineInput.value;
    });
    inlineInput.addEventListener('change', () => {
      applyOutputInlineValue(index, inlineInput.value);
    });
    inlineInput.addEventListener('blur', () => {
      applyOutputInlineValue(index, inlineInput.value);
    });
    label.appendChild(inlineInput);

    const isUdp = String(output.format || '').toLowerCase() === 'udp';
    let audioFixMeta = null;
    if (isUdp) {
      const status = getEditingOutputStatus(index);
      audioFixMeta = getOutputAudioFixMeta(output, status);
      const meta = document.createElement('div');
      meta.className = 'output-meta';
      meta.dataset.role = 'output-audio-meta';

      const audioSpan = document.createElement('span');
      audioSpan.className = `output-audio-status ${audioFixMeta.audioClass}`.trim();
      audioSpan.dataset.role = 'output-audio-type';
      audioSpan.textContent = audioFixMeta.audioText;

      const fixSpan = document.createElement('span');
      fixSpan.className = `output-audio-status ${audioFixMeta.fixClass}`.trim();
      fixSpan.dataset.role = 'output-audio-fix';
      fixSpan.textContent = audioFixMeta.fixText;

      meta.appendChild(audioSpan);
      meta.appendChild(fixSpan);
      label.appendChild(meta);
    }

    const options = document.createElement('button');
    options.className = 'icon-btn';
    options.type = 'button';
    options.dataset.action = 'output-options';
    options.textContent = '...';

    const remove = document.createElement('button');
    remove.className = 'icon-btn';
    remove.type = 'button';
    remove.dataset.action = 'output-remove';
    remove.textContent = 'x';

    row.appendChild(idx);
    row.appendChild(label);
    if (isUdp) {
      const audioFix = audioFixMeta ? audioFixMeta.config : normalizeOutputAudioFix(output.audio_fix);
      const audioToggle = document.createElement('button');
      audioToggle.type = 'button';
      audioToggle.className = `output-audio-toggle ${audioFix.enabled ? 'is-on' : 'is-off'}`;
      audioToggle.dataset.action = 'output-audio-fix';
      audioToggle.textContent = audioFix.enabled ? 'Audio Fix: ON' : 'Audio Fix: OFF';
      row.appendChild(audioToggle);
    } else {
      const spacer = document.createElement('div');
      spacer.className = 'output-action-spacer';
      row.appendChild(spacer);
    }
    row.appendChild(options);
    row.appendChild(remove);

    elements.outputList.appendChild(row);
  });
}

function toggleOutputAudioFix(index) {
  const output = state.outputs[index];
  if (!output || String(output.format || '').toLowerCase() !== 'udp') return;
  const audioFix = normalizeOutputAudioFix(output.audio_fix);
  audioFix.enabled = !audioFix.enabled;
  output.audio_fix = audioFix;
  renderOutputList();
}

function getEditingOutputStatus(index) {
  if (!state.editing || !state.editing.stream) return null;
  const stats = state.stats[state.editing.stream.id];
  if (!stats || !Array.isArray(stats.outputs_status)) return null;
  const targetIndex = index + 1;
  return stats.outputs_status.find((entry) => entry.output_index === targetIndex) || null;
}

function renderTileInputs(container, inputs, activeIndex) {
  container.innerHTML = '';
  if (!inputs.length) {
    const empty = document.createElement('div');
    empty.className = 'tile-input-empty';
    empty.textContent = 'No input stats yet.';
    container.appendChild(empty);
    return;
  }

  inputs.forEach((input, index) => {
    const stateValue = getInputState(input, index, activeIndex);
    const row = document.createElement('div');
    row.className = `tile-input-row state-${stateValue.toLowerCase()}`;
    if (index === activeIndex) {
      row.classList.add('is-active');
    }

    const badge = document.createElement('span');
    badge.className = 'input-badge';
    badge.textContent = stateValue;

    const label = document.createElement('span');
    label.className = 'tile-input-label';
    label.textContent = `#${index + 1} ${getInputLabel(input, index)}`;
    if (input && input.url) {
      label.title = input.url;
    }

    const bitrateValue = Number.isFinite(input && input.bitrate_kbps)
      ? input.bitrate_kbps
      : (input && input.bitrate);
    const bitrate = formatBitrate(Number(bitrateValue) || 0);
    const bitrateEl = document.createElement('span');
    bitrateEl.className = 'tile-input-bitrate';
    bitrateEl.textContent = bitrate;

    row.appendChild(badge);
    row.appendChild(label);
    row.appendChild(bitrateEl);
    const url = input && input.url ? input.url : '';
    if (url) {
      const copyButton = document.createElement('button');
      copyButton.type = 'button';
      copyButton.className = 'tile-input-copy';
      copyButton.textContent = 'Copy';
      copyButton.addEventListener('click', (event) => {
        event.stopPropagation();
        copyText(url);
      });
      row.appendChild(copyButton);
    }
    container.appendChild(row);
  });
}

function getEditingTranscodeStatus() {
  if (!state.editing || !state.editing.stream) return null;
  const stats = state.stats[state.editing.stream.id];
  if (!stats || !stats.transcode) return null;
  return stats.transcode;
}

function getTranscodeOutputStatus(index) {
  const status = getEditingTranscodeStatus();
  if (!status || !Array.isArray(status.outputs_status)) return null;
  const targetIndex = index + 1;
  return status.outputs_status.find((entry) => entry.output_index === targetIndex) || null;
}

function formatTranscodeOutputMonitorMeta(output, status) {
  const watchdog = output && output.watchdog ? output.watchdog : null;
  const enabled = status ? status.monitor_enabled : isOutputMonitorEnabled(watchdog);
  const engine = status ? status.monitor_engine : (watchdog && watchdog.monitor_engine) || 'auto';
  const bits = [`Monitor: ${enabled ? 'ON' : 'OFF'} (${engine})`];
  const now = Math.floor(Date.now() / 1000);
  const formatPsiState = (label, ts, timeout) => {
    if (!ts) return '';
    const age = Math.max(0, now - ts);
    if (timeout && timeout > 0) {
      return age > timeout
        ? `${label}:late ${formatShortDuration(age)}`
        : `${label}:ok`;
    }
    return `${label}:${formatShortDuration(age)} ago`;
  };
  if (status) {
    if (status.current_bitrate_kbps !== null && status.current_bitrate_kbps !== undefined) {
      bits.push(`Rate: ${formatMaybeBitrate(status.current_bitrate_kbps)}`);
    }
    if (status.last_probe_ts) {
      bits.push(`Last: ${status.last_probe_ok ? 'OK' : 'FAIL'}`);
    }
    if (status.cc_errors !== null && status.cc_errors !== undefined) {
      bits.push(`CC:${status.cc_errors}`);
    }
    if (status.pes_errors !== null && status.pes_errors !== undefined) {
      bits.push(`PES:${status.pes_errors}`);
    }
    if (status.scrambled_active) {
      bits.push('Scr:ON');
    } else if (status.scrambled_errors !== null && status.scrambled_errors !== undefined) {
      bits.push(`Scr:${status.scrambled_errors}`);
    }
    const patState = formatPsiState('PAT', status.psi_pat_ts, status.pat_timeout_sec);
    if (patState) bits.push(patState);
    const pmtState = formatPsiState('PMT', status.psi_pmt_ts, status.pmt_timeout_sec);
    if (pmtState) bits.push(pmtState);
    if (status.restart_cooldown_remaining_sec && status.restart_cooldown_remaining_sec > 0) {
      bits.push(`Cooldown: ${formatShortDuration(status.restart_cooldown_remaining_sec)}`);
    }
  }
  return bits.join(' • ');
}

function renderTranscodeOutputList() {
  if (!elements.transcodeOutputList) return;
  elements.transcodeOutputList.innerHTML = '';
  if (!state.transcodeOutputs || state.transcodeOutputs.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'panel subtle';
    empty.textContent = 'No transcode outputs configured.';
    elements.transcodeOutputList.appendChild(empty);
    return;
  }

  state.transcodeOutputs.forEach((output, index) => {
    const normalized = ensureTranscodeOutputWatchdog(output);
    if (normalized !== output) {
      state.transcodeOutputs[index] = normalized;
    }
    const row = document.createElement('div');
    row.className = 'list-row transcode-output-row';
    row.dataset.index = String(index);

    const idx = document.createElement('div');
    idx.className = 'list-index';
    idx.textContent = `#${index + 1}`;

    const label = document.createElement('div');
    label.className = 'list-input transcode-output-label';
    const title = document.createElement('div');
    title.className = 'transcode-output-title';
    title.textContent = transcodeOutputSummary(normalized, index);
    const meta = document.createElement('div');
    meta.className = 'transcode-output-meta';
    meta.dataset.role = 'transcode-output-monitor';
    meta.textContent = formatTranscodeOutputMonitorMeta(normalized, getTranscodeOutputStatus(index));
    label.title = normalized && normalized.url ? normalized.url : '';
    label.appendChild(title);
    label.appendChild(meta);

    const monitor = document.createElement('button');
    monitor.className = 'icon-btn';
    monitor.type = 'button';
    monitor.dataset.action = 'transcode-output-monitor';
    monitor.textContent = 'M';
    monitor.title = 'Restart/Monitor settings';

    const options = document.createElement('button');
    options.className = 'icon-btn';
    options.type = 'button';
    options.dataset.action = 'transcode-output-options';
    options.textContent = '...';

    const remove = document.createElement('button');
    remove.className = 'icon-btn';
    remove.type = 'button';
    remove.dataset.action = 'transcode-output-remove';
    remove.textContent = 'x';

    row.appendChild(idx);
    row.appendChild(label);
    row.appendChild(monitor);
    row.appendChild(options);
    row.appendChild(remove);

    elements.transcodeOutputList.appendChild(row);
  });
}

function setTab(name, scope) {
  const tabs = scope ? $$('.tab[data-tab-scope="' + scope + '"]') : elements.tabs;
  const contents = scope ? $$('.tab-content[data-tab-scope="' + scope + '"]') : elements.tabContents;
  let activeTab = null;
  tabs.forEach((tab) => {
    const active = tab.dataset.tab === name;
    tab.classList.toggle('active', active);
    if (active) activeTab = tab;
  });
  if (activeTab && typeof activeTab.scrollIntoView === 'function') {
    activeTab.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    const tabbar = activeTab.closest('.tabbar');
    if (tabbar) updateTabbarScrollState(tabbar);
  }
  contents.forEach((content) => {
    content.classList.toggle('active', content.dataset.tabContent === name);
  });
}

function updateTabbarScrollState(tabbar) {
  if (!tabbar) return;
  const scrollable = tabbar.scrollWidth > tabbar.clientWidth + 2;
  tabbar.classList.toggle('is-scrollable', scrollable);
}

function initTabbars() {
  const list = Array.isArray(elements.tabbars) ? elements.tabbars : [];
  if (!list.length) return;
  const updateAll = () => list.forEach((tabbar) => updateTabbarScrollState(tabbar));
  const onResize = debounce(updateAll, 150);
  window.addEventListener('resize', onResize);
  list.forEach((tabbar) => {
    updateTabbarScrollState(tabbar);
    tabbar.addEventListener('focusin', (event) => {
      const target = event.target;
      if (target && target.classList && target.classList.contains('tab')) {
        target.scrollIntoView({ block: 'nearest', inline: 'nearest' });
      }
    });
  });
}

function renderInputList() {
  elements.inputList.innerHTML = '';
  if (!state.inputs || state.inputs.length === 0) {
    state.inputs = [''];
  }

  state.inputs.forEach((value, index) => {
    const row = document.createElement('div');
    row.className = 'list-row';
    row.dataset.index = String(index);

    const idx = document.createElement('div');
    idx.className = 'list-index';
    idx.textContent = `#${index + 1}`;

    const input = document.createElement('input');
    input.className = 'list-input';
    input.type = 'text';
    input.value = value || '';
    input.dataset.role = 'input';
    input.addEventListener('input', () => {
      state.inputs[index] = input.value;
    });

    const options = document.createElement('button');
    options.className = 'icon-btn';
    options.type = 'button';
    options.dataset.action = 'input-options';
    options.textContent = '...';

    const remove = document.createElement('button');
    remove.className = 'icon-btn';
    remove.type = 'button';
    remove.dataset.action = 'input-remove';
    remove.textContent = 'x';

    row.appendChild(idx);
    row.appendChild(input);
    row.appendChild(options);
    row.appendChild(remove);

    elements.inputList.appendChild(row);
  });
}

function normalizeMptsServices(list) {
  if (!Array.isArray(list)) return [];
  return list.map((item) => {
    if (typeof item === 'string') {
      return { input: item };
    }
    return {
      input: item.input || item.url || '',
      service_name: item.service_name || '',
      service_provider: item.service_provider || item.provider_name || '',
      service_type_id: item.service_type_id || '',
      lcn: item.lcn || '',
      pnr: item.pnr || '',
      scrambled: item.scrambled === true,
      name: item.name || '',
    };
  });
}

function normalizeMptsCa(list) {
  if (!Array.isArray(list)) return [];
  return list.map((item) => {
    if (!item || typeof item !== 'object') {
      return { ca_system_id: '', ca_pid: '', private_data: '' };
    }
    return {
      ca_system_id: item.ca_system_id !== undefined ? item.ca_system_id : (item.caid || ''),
      ca_pid: item.ca_pid !== undefined ? item.ca_pid : (item.pid || ''),
      private_data: item.private_data || item.data || '',
    };
  });
}

function renderMptsCaList() {
  if (!elements.mptsCaList) return;
  elements.mptsCaList.innerHTML = '';
  state.mptsCa = Array.isArray(state.mptsCa) ? state.mptsCa : [];

  if (state.mptsCa.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'panel subtle';
    empty.textContent = 'No CA descriptors configured.';
    elements.mptsCaList.appendChild(empty);
    return;
  }

  state.mptsCa.forEach((entry, index) => {
    const row = document.createElement('div');
    row.className = 'list-row mpts-ca-row';
    row.dataset.index = String(index);

    const idx = document.createElement('div');
    idx.className = 'list-index';
    idx.textContent = `#${index + 1}`;

    const grid = document.createElement('div');
    grid.className = 'mpts-ca-grid';

    const caid = document.createElement('input');
    caid.className = 'list-input mpts-field mpts-service-input';
    caid.type = 'text';
    caid.placeholder = 'CAID (0x0B00)';
    caid.title = 'CA system id (hex or decimal), 0..65535';
    caid.value = entry.ca_system_id !== undefined && entry.ca_system_id !== null ? String(entry.ca_system_id) : '';
    caid.addEventListener('input', () => {
      entry.ca_system_id = caid.value;
    });

    const capid = document.createElement('input');
    capid.className = 'list-input mpts-field mpts-service-input';
    capid.type = 'number';
    capid.placeholder = 'CA PID';
    capid.min = '0';
    capid.max = '8190';
    capid.value = entry.ca_pid !== undefined && entry.ca_pid !== null ? String(entry.ca_pid) : '';
    capid.addEventListener('input', () => {
      entry.ca_pid = capid.value;
    });

    const priv = document.createElement('input');
    priv.className = 'list-input mpts-field mpts-service-input';
    priv.type = 'text';
    priv.placeholder = 'private_data (hex, optional)';
    priv.title = 'Optional descriptor private_data (hex string, even length)';
    priv.value = entry.private_data !== undefined && entry.private_data !== null ? String(entry.private_data) : '';
    priv.addEventListener('input', () => {
      entry.private_data = priv.value;
    });

    grid.appendChild(caid);
    grid.appendChild(capid);
    grid.appendChild(priv);

    const actions = document.createElement('div');
    actions.className = 'mpts-ca-actions';

    const remove = document.createElement('button');
    remove.className = 'icon-btn';
    remove.type = 'button';
    remove.dataset.action = 'mpts-ca-remove';
    remove.textContent = 'x';

    actions.appendChild(remove);

    row.appendChild(idx);
    row.appendChild(grid);
    row.appendChild(actions);

    elements.mptsCaList.appendChild(row);
  });
}

function isMptsServiceEffectivelyEmpty(service) {
  if (!service) return true;
  const input = String(service.input || '').trim();
  const name = String(service.service_name || '').trim();
  const provider = String(service.service_provider || '').trim();
  const pnr = String(service.pnr || '').trim();
  const lcn = String(service.lcn || '').trim();
  const st = String(service.service_type_id || '').trim();
  const hasScrambled = service.scrambled === true;
  return !input && !name && !provider && !pnr && !lcn && !st && !hasScrambled;
}

function normalizeMptsServicesList() {
  if (!Array.isArray(state.mptsServices)) {
    state.mptsServices = [];
  }
  if (state.mptsServices.length === 1 && isMptsServiceEffectivelyEmpty(state.mptsServices[0])) {
    state.mptsServices = [];
  }
}

function convertInputsToMptsServices() {
  normalizeMptsServicesList();
  const inputs = collectInputs().map((value) => String(value || '').trim()).filter(Boolean);
  if (!inputs.length) {
    setStatus('No inputs to convert');
    return;
  }

  const hasExisting = (state.mptsServices || []).some((svc) => !isMptsServiceEffectivelyEmpty(svc));
  if (hasExisting) {
    const proceed = window.confirm('Replace current MPTS service list with INPUT LIST?');
    if (!proceed) return;
  }

  const pnrStart = toNumber(elements.mptsBulkPnrStart && elements.mptsBulkPnrStart.value);
  const pnrStep = toNumber(elements.mptsBulkPnrStep && elements.mptsBulkPnrStep.value) || 1;
  const lcnStart = toNumber(elements.mptsBulkLcnStart && elements.mptsBulkLcnStart.value);
  const lcnStep = toNumber(elements.mptsBulkLcnStep && elements.mptsBulkLcnStep.value) || 1;
  const bulkProvider = (elements.mptsBulkProvider && elements.mptsBulkProvider.value || '').trim();
  const serviceTypeId = toNumber(elements.mptsBulkServiceType && elements.mptsBulkServiceType.value);

  state.mptsServices = inputs.map((url, idx) => {
    const svc = { input: url };
    if (bulkProvider) svc.service_provider = bulkProvider;
    if (Number.isFinite(pnrStart)) svc.pnr = String(pnrStart + idx * pnrStep);
    if (Number.isFinite(lcnStart)) svc.lcn = String(lcnStart + idx * lcnStep);
    if (Number.isFinite(serviceTypeId)) svc.service_type_id = String(serviceTypeId);
    return svc;
  });

  renderMptsServiceList();
  setStatus(`Converted ${inputs.length} input(s) to services`);
}

function renderMptsStreamsModal() {
  if (!elements.mptsStreamsList) return;
  const modal = state.mptsStreamsModal || { selected: new Set(), search: '' };
  const search = String(modal.search || '').trim().toLowerCase();

  elements.mptsStreamsList.innerHTML = '';

  const currentId = state.editing && state.editing.stream ? state.editing.stream.id : '';
  const streams = Array.isArray(state.streams) ? state.streams.slice() : [];
  const filtered = streams
    .filter((stream) => stream && stream.id && stream.id !== currentId)
    .filter((stream) => {
      if (!search) return true;
      const id = String(stream.id || '').toLowerCase();
      const name = String((stream.config && stream.config.name) || '').toLowerCase();
      return id.includes(search) || name.includes(search);
    })
    .sort((a, b) => String(a.id).localeCompare(String(b.id)));

  if (!filtered.length) {
    const empty = document.createElement('div');
    empty.className = 'form-hint';
    empty.textContent = search ? 'No streams matched the filter.' : 'No streams found.';
    elements.mptsStreamsList.appendChild(empty);
  } else {
    filtered.forEach((stream) => {
      const id = String(stream.id || '');
      const cfg = stream.config || {};
      const name = String(cfg.name || '');

      const row = document.createElement('label');
      row.className = 'checkline mpts-stream-row';

      const cb = document.createElement('input');
      cb.type = 'checkbox';
      cb.checked = modal.selected.has(id);
      cb.addEventListener('change', () => {
        if (cb.checked) modal.selected.add(id);
        else modal.selected.delete(id);
        state.mptsStreamsModal = modal;
        if (elements.mptsStreamsAdd) {
          elements.mptsStreamsAdd.disabled = modal.selected.size === 0;
        }
      });

      const text = document.createElement('span');
      text.textContent = name ? `${id} (${name})` : id;

      row.appendChild(cb);
      row.appendChild(text);
      elements.mptsStreamsList.appendChild(row);
    });
  }

  if (elements.mptsStreamsAdd) {
    elements.mptsStreamsAdd.disabled = modal.selected.size === 0;
  }
}

function openMptsStreamsModal() {
  if (!elements.mptsStreamsOverlay) return;
  state.mptsStreamsModal = { selected: new Set(), search: '' };
  if (elements.mptsStreamsSearch) elements.mptsStreamsSearch.value = '';
  renderMptsStreamsModal();
  setOverlay(elements.mptsStreamsOverlay, true);
  if (elements.mptsStreamsSearch) elements.mptsStreamsSearch.focus();
}

function closeMptsStreamsModal() {
  if (!elements.mptsStreamsOverlay) return;
  setOverlay(elements.mptsStreamsOverlay, false);
}

function addMptsServicesFromSelectedStreams() {
  const modal = state.mptsStreamsModal;
  if (!modal || !modal.selected || modal.selected.size === 0) {
    closeMptsStreamsModal();
    return;
  }

  normalizeMptsServicesList();
  const existing = new Set((state.mptsServices || []).map((svc) => String(svc.input || '').trim().toLowerCase()));
  const added = [];

  modal.selected.forEach((id) => {
    const input = `stream://${id}`;
    const normalized = input.toLowerCase();
    if (existing.has(normalized)) return;
    existing.add(normalized);

    const stream = (state.streams || []).find((s) => s && s.id === id);
    const cfg = stream && stream.config ? stream.config : {};
    const serviceName = (cfg && (cfg.service_name || cfg.name)) ? String(cfg.service_name || cfg.name) : '';
    const providerName = cfg && cfg.service_provider ? String(cfg.service_provider) : '';
    const typeId = cfg && cfg.service_type_id !== undefined ? toNumber(cfg.service_type_id) : undefined;

    const svc = { input };
    if (serviceName) svc.service_name = serviceName;
    if (providerName) svc.service_provider = providerName;
    if (Number.isFinite(typeId)) svc.service_type_id = String(typeId);
    state.mptsServices.push(svc);
    added.push(id);
  });

  closeMptsStreamsModal();
  renderMptsServiceList();
  setStatus(added.length ? `Added ${added.length} stream(s) to services` : 'No new streams were added');
}

function renderMptsServiceList() {
  if (!elements.mptsServiceList) return;
  elements.mptsServiceList.innerHTML = '';
  if (!state.mptsServices || state.mptsServices.length === 0) {
    state.mptsServices = [{ input: '' }];
  }

  state.mptsServices.forEach((service, index) => {
    const row = document.createElement('div');
    row.className = 'list-row mpts-service-row';
    row.dataset.index = String(index);

    const idx = document.createElement('div');
    idx.className = 'list-index';
    idx.textContent = `#${index + 1}`;

    const grid = document.createElement('div');
    grid.className = 'mpts-service-grid';

    const input = document.createElement('input');
    input.className = 'list-input mpts-field mpts-service-input';
    input.type = 'text';
    input.placeholder = 'Input URL (udp://... или stream://<id>)';
    input.value = service.input || '';
    input.addEventListener('input', () => {
      service.input = input.value;
      updateMptsInputWarning();
    });

    const serviceName = document.createElement('input');
    serviceName.className = 'list-input mpts-field mpts-service-input';
    serviceName.type = 'text';
    serviceName.placeholder = 'Service name';
    serviceName.value = service.service_name || '';
    serviceName.addEventListener('input', () => {
      service.service_name = serviceName.value;
    });

    const provider = document.createElement('input');
    provider.className = 'list-input mpts-field mpts-service-input';
    provider.type = 'text';
    provider.placeholder = 'Provider';
    provider.value = service.service_provider || '';
    provider.addEventListener('input', () => {
      service.service_provider = provider.value;
    });

    const pnr = document.createElement('input');
    pnr.className = 'list-input mpts-field mpts-service-input';
    pnr.type = 'number';
    pnr.placeholder = 'PNR';
    pnr.min = '1';
    pnr.max = '65535';
    pnr.value = service.pnr || '';
    pnr.addEventListener('input', () => {
      service.pnr = pnr.value;
      updateMptsPnrWarning();
    });

    const lcn = document.createElement('input');
    lcn.className = 'list-input mpts-field mpts-service-input';
    lcn.type = 'number';
    lcn.placeholder = 'LCN';
    lcn.min = '1';
    lcn.max = '1023';
    lcn.value = service.lcn || '';
    lcn.addEventListener('input', () => {
      service.lcn = lcn.value;
    });

    const serviceType = document.createElement('input');
    serviceType.className = 'list-input mpts-field mpts-service-input';
    serviceType.type = 'number';
    serviceType.placeholder = 'Service type (1..255)';
    serviceType.min = '1';
    serviceType.max = '255';
    serviceType.title = 'DVB service_type_id (1..255); пусто = 1';
    serviceType.value = service.service_type_id || '';
    serviceType.addEventListener('input', () => {
      service.service_type_id = serviceType.value;
    });

    const scrambledLabel = document.createElement('label');
    scrambledLabel.className = 'mpts-service-scrambled';
    const scrambled = document.createElement('input');
    scrambled.type = 'checkbox';
    scrambled.className = 'mpts-field';
    scrambled.checked = service.scrambled === true;
    scrambled.addEventListener('change', () => {
      service.scrambled = scrambled.checked;
    });
    const scrambledText = document.createElement('span');
    scrambledText.textContent = 'Scrambled';
    scrambledLabel.appendChild(scrambled);
    scrambledLabel.appendChild(scrambledText);

    grid.appendChild(input);
    grid.appendChild(serviceName);
    grid.appendChild(provider);
    grid.appendChild(pnr);
    grid.appendChild(lcn);
    grid.appendChild(serviceType);
    grid.appendChild(scrambledLabel);

    const actions = document.createElement('div');
    actions.className = 'mpts-service-actions';

    const moveUp = document.createElement('button');
    moveUp.className = 'icon-btn';
    moveUp.type = 'button';
    moveUp.dataset.action = 'mpts-service-up';
    moveUp.textContent = '↑';
    moveUp.disabled = index === 0;

    const moveDown = document.createElement('button');
    moveDown.className = 'icon-btn';
    moveDown.type = 'button';
    moveDown.dataset.action = 'mpts-service-down';
    moveDown.textContent = '↓';
    moveDown.disabled = index === state.mptsServices.length - 1;

    const remove = document.createElement('button');
    remove.className = 'icon-btn';
    remove.type = 'button';
    remove.dataset.action = 'mpts-service-remove';
    remove.textContent = 'x';

    actions.appendChild(moveUp);
    actions.appendChild(moveDown);
    actions.appendChild(remove);

    row.appendChild(idx);
    row.appendChild(grid);
    row.appendChild(actions);

    elements.mptsServiceList.appendChild(row);
  });

  updateMptsPassWarning();
  updateMptsAutoremapWarning();
  updateMptsPnrWarning();
  updateMptsInputWarning();
  updateMptsDeliveryWarning();
}

function updateMptsPassWarning() {
  if (!elements.mptsPassWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const passEnabled = (!!(elements.mptsPassNit && elements.mptsPassNit.checked))
    || (!!(elements.mptsPassSdt && elements.mptsPassSdt.checked))
    || (!!(elements.mptsPassTdt && elements.mptsPassTdt.checked));
  const serviceCount = (state.mptsServices || []).length;
  const shouldShow = mptsEnabled && passEnabled && serviceCount > 1;
  elements.mptsPassWarning.classList.toggle('is-hidden', !shouldShow);
  if (shouldShow) {
    elements.mptsPassWarning.textContent = 'Pass NIT/SDT/TDT корректен только для одного сервиса.';
  }
}

function updateMptsAutoremapWarning() {
  if (!elements.mptsAutoremapWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const disableAuto = !!(elements.mptsDisableAutoremap && elements.mptsDisableAutoremap.checked);
  elements.mptsAutoremapWarning.classList.toggle('is-hidden', !(mptsEnabled && disableAuto));
}

function updateMptsPnrWarning() {
  if (!elements.mptsPnrWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const counts = new Map();
  let missingCount = 0;
  const strictPnr = !!(elements.mptsStrictPnr && elements.mptsStrictPnr.checked);
  (state.mptsServices || []).forEach((service) => {
    const value = Number(service.pnr);
    if (!Number.isFinite(value) || value <= 0) {
      missingCount += 1;
      return;
    }
    counts.set(value, (counts.get(value) || 0) + 1);
  });
  const duplicates = Array.from(counts.entries())
    .filter((entry) => entry[1] > 1)
    .map((entry) => entry[0])
    .sort((a, b) => a - b);
  if (!mptsEnabled || duplicates.length === 0) {
    elements.mptsPnrWarning.classList.add('is-hidden');
    elements.mptsPnrWarning.textContent = '';
  } else {
    elements.mptsPnrWarning.textContent = `PNR duplicates: ${duplicates.join(', ')}`;
    elements.mptsPnrWarning.classList.remove('is-hidden');
  }
  if (elements.mptsPnrMissing) {
    if (!mptsEnabled || missingCount === 0) {
      elements.mptsPnrMissing.classList.add('is-hidden');
      elements.mptsPnrMissing.textContent = '';
    } else {
      const suffix = strictPnr
        ? 'Strict PNR включён: такие сервисы будут отклонены.'
        : 'Для MPTS лучше задавать PNR явно.';
      elements.mptsPnrMissing.textContent = `PNR missing: ${missingCount}. ${suffix}`;
      elements.mptsPnrMissing.classList.remove('is-hidden');
    }
  }
}

function updateMptsInputWarning() {
  if (!elements.mptsDupInputWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const counts = new Map();
  (state.mptsServices || []).forEach((service) => {
    const raw = String(service.input || '').trim();
    if (!raw) return;
    const normalized = raw.toLowerCase();
    counts.set(normalized, (counts.get(normalized) || 0) + 1);
  });
  const duplicates = Array.from(counts.entries())
    .filter((entry) => entry[1] > 1)
    .map((entry) => entry[0]);
  if (!mptsEnabled || duplicates.length === 0) {
    elements.mptsDupInputWarning.classList.add('is-hidden');
    elements.mptsDupInputWarning.textContent = '';
    if (elements.mptsSptsWarning) {
      elements.mptsSptsWarning.classList.add('is-hidden');
      elements.mptsSptsWarning.textContent = '';
    }
    return;
  }
  elements.mptsDupInputWarning.textContent = `Duplicate inputs: ${duplicates.join(', ')}`;
  elements.mptsDupInputWarning.classList.remove('is-hidden');
  if (elements.mptsSptsWarning) {
    const sptsOnly = !!(elements.mptsSptsOnly && elements.mptsSptsOnly.checked);
    if (sptsOnly) {
      elements.mptsSptsWarning.textContent = 'SPTS only включён: дублирование входов обычно означает multi-PAT и будет отклонено.';
      elements.mptsSptsWarning.classList.remove('is-hidden');
    } else {
      elements.mptsSptsWarning.classList.add('is-hidden');
      elements.mptsSptsWarning.textContent = '';
    }
  }
}

function updateMptsNitFields() {
  const delivery = String(elements.mptsDelivery && elements.mptsDelivery.value || '').toLowerCase();
  // Если delivery не выбран, показываем как для DVB-C (самый частый кейс).
  const effective = delivery || 'dvb-c';
  const isCable = effective === 'dvb-c' || effective === 'cable' || effective === 'dvb_c';
  const isTerrestrial = effective === 'dvb-t' || effective === 'terrestrial' || effective === 'dvb_t';
  const isSatellite = effective === 'dvb-s' || effective === 'satellite' || effective === 'dvb_s' ||
    effective === 'dvb-s2' || effective === 'dvb_s2';

  $$('.mpts-nit-sat-cable').forEach((node) => {
    node.classList.toggle('is-hidden', !(isCable || isSatellite));
  });
  $$('.mpts-nit-dvbt').forEach((node) => {
    node.classList.toggle('is-hidden', !isTerrestrial);
  });
  $$('.mpts-nit-sat-only').forEach((node) => {
    node.classList.toggle('is-hidden', !isSatellite);
  });
}

function updateMptsDeliveryWarning() {
  if (!elements.mptsDeliveryWarning) return;
  updateMptsNitFields();
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const delivery = String(elements.mptsDelivery && elements.mptsDelivery.value || '').toLowerCase();
  if (!mptsEnabled || !delivery) {
    elements.mptsDeliveryWarning.classList.add('is-hidden');
    elements.mptsDeliveryWarning.textContent = '';
    return;
  }
  const isCable = delivery === 'dvb-c' || delivery === 'cable' || delivery === 'dvb_c';
  const isTerrestrial = delivery === 'dvb-t' || delivery === 'terrestrial' || delivery === 'dvb_t';
  const isSatellite = delivery === 'dvb-s' || delivery === 'satellite' || delivery === 'dvb_s' || delivery === 'dvb-s2' || delivery === 'dvb_s2';
  if (!isCable && !isTerrestrial && !isSatellite) {
    elements.mptsDeliveryWarning.textContent = `Delivery ${delivery} не поддерживается: доступен только DVB-C/DVB-T/DVB-S.`;
    elements.mptsDeliveryWarning.classList.remove('is-hidden');
    return;
  }
  const freq = Number(elements.mptsFrequency && elements.mptsFrequency.value);
  const missing = [];
  if (!Number.isFinite(freq) || freq <= 0) missing.push('frequency');
  if (isCable || isSatellite) {
    const sr = Number(elements.mptsSymbolrate && elements.mptsSymbolrate.value);
    if (!Number.isFinite(sr) || sr <= 0) missing.push('symbolrate');
  }
  if (isCable) {
    const mod = String(elements.mptsModulation && elements.mptsModulation.value || '').trim();
    if (!mod) missing.push('modulation');
  }
  if (isTerrestrial) {
    const bw = Number(elements.mptsBandwidth && elements.mptsBandwidth.value);
    if (Number.isFinite(bw) && bw > 0 && ![5, 6, 7, 8].includes(bw)) {
      elements.mptsDeliveryWarning.textContent = 'DVB-T bandwidth поддерживается только 5/6/7/8 MHz.';
      elements.mptsDeliveryWarning.classList.remove('is-hidden');
      return;
    }
  }
  if (missing.length === 0) {
    elements.mptsDeliveryWarning.classList.add('is-hidden');
    elements.mptsDeliveryWarning.textContent = '';
    return;
  }
  const label = isCable ? 'DVB-C' : isSatellite ? 'DVB-S' : 'DVB-T';
  elements.mptsDeliveryWarning.textContent = `${label} delivery requires: ${missing.join(', ')}`;
  elements.mptsDeliveryWarning.classList.remove('is-hidden');
}

function updateMptsLcnTagsWarning() {
  if (!elements.mptsLcnTagsWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const tagsRaw = String(elements.mptsLcnTags && elements.mptsLcnTags.value || '').trim();
  const tagRaw = String(elements.mptsLcnTag && elements.mptsLcnTag.value || '').trim();
  if (!mptsEnabled || !tagsRaw) {
    elements.mptsLcnTagsWarning.classList.add('is-hidden');
    elements.mptsLcnTagsWarning.textContent = '';
    return;
  }
  if (tagRaw) {
    elements.mptsLcnTagsWarning.textContent = 'LCN tags override single LCN tag.';
    elements.mptsLcnTagsWarning.classList.remove('is-hidden');
    return;
  }
  elements.mptsLcnTagsWarning.classList.add('is-hidden');
  elements.mptsLcnTagsWarning.textContent = '';
}

function updateMptsLcnVersionWarning() {
  if (!elements.mptsLcnVersionWarning) return;
  const mptsEnabled = !elements.streamMpts || elements.streamMpts.checked;
  const lcnVersionRaw = String(elements.mptsLcnVersion && elements.mptsLcnVersion.value || '').trim();
  const nitVersionRaw = String(elements.mptsNitVersion && elements.mptsNitVersion.value || '').trim();
  if (!mptsEnabled || !lcnVersionRaw) {
    elements.mptsLcnVersionWarning.classList.add('is-hidden');
    elements.mptsLcnVersionWarning.textContent = '';
    return;
  }
  if (nitVersionRaw) {
    elements.mptsLcnVersionWarning.textContent = 'LCN version игнорируется, когда задан NIT version.';
    elements.mptsLcnVersionWarning.classList.remove('is-hidden');
    return;
  }
  elements.mptsLcnVersionWarning.classList.add('is-hidden');
  elements.mptsLcnVersionWarning.textContent = '';
}

function bindMptsWarningHandlers() {
  if (elements.mptsDisableAutoremap) {
    elements.mptsDisableAutoremap.addEventListener('change', updateMptsAutoremapWarning);
  }
  if (elements.streamMpts) {
    elements.streamMpts.addEventListener('change', updateMptsAutoremapWarning);
    elements.streamMpts.addEventListener('change', updateMptsPnrWarning);
    elements.streamMpts.addEventListener('change', updateMptsLcnVersionWarning);
    elements.streamMpts.addEventListener('change', updateMptsLcnTagsWarning);
    elements.streamMpts.addEventListener('change', updateMptsInputWarning);
  }
  if (elements.mptsStrictPnr) {
    elements.mptsStrictPnr.addEventListener('change', updateMptsPnrWarning);
  }
  if (elements.mptsSptsOnly) {
    elements.mptsSptsOnly.addEventListener('change', updateMptsInputWarning);
  }
}

function collectMptsServices() {
  return (state.mptsServices || []).map((service) => {
    const input = (service.input || '').trim();
    return {
      input,
      service_name: (service.service_name || '').trim(),
      service_provider: (service.service_provider || '').trim(),
      service_type_id: service.service_type_id,
      lcn: service.lcn,
      pnr: service.pnr,
      scrambled: service.scrambled === true,
      name: (service.name || '').trim(),
    };
  }).filter((service) => service.input);
}

function applyMptsBulkActions() {
  if (!state.mptsServices || state.mptsServices.length === 0) {
    setStatus('No MPTS services to update');
    return;
  }
  const pnrStart = toNumber(elements.mptsBulkPnrStart && elements.mptsBulkPnrStart.value);
  const pnrStep = toNumber(elements.mptsBulkPnrStep && elements.mptsBulkPnrStep.value);
  const lcnStart = toNumber(elements.mptsBulkLcnStart && elements.mptsBulkLcnStart.value);
  const lcnStep = toNumber(elements.mptsBulkLcnStep && elements.mptsBulkLcnStep.value);
  const provider = (elements.mptsBulkProvider && elements.mptsBulkProvider.value || '').trim();
  const serviceType = toNumber(elements.mptsBulkServiceType && elements.mptsBulkServiceType.value);

  if (serviceType !== undefined && (serviceType < 0 || serviceType > 255)) {
    setStatus('Bulk service type must be between 0 and 255');
    return;
  }
  if (pnrStart !== undefined && (pnrStart < 1 || pnrStart > 65535)) {
    setStatus('Bulk PNR start must be between 1 and 65535');
    return;
  }
  if (lcnStart !== undefined && (lcnStart < 1 || lcnStart > 1023)) {
    setStatus('Bulk LCN start must be between 1 and 1023');
    return;
  }

  const pnrDelta = pnrStep !== undefined ? pnrStep : 1;
  const lcnDelta = lcnStep !== undefined ? lcnStep : 1;

  state.mptsServices = state.mptsServices.map((service, index) => {
    const updated = { ...service };
    if (pnrStart !== undefined) {
      updated.pnr = pnrStart + (index * pnrDelta);
    }
    if (lcnStart !== undefined) {
      updated.lcn = lcnStart + (index * lcnDelta);
    }
    if (provider) {
      updated.service_provider = provider;
    }
    if (serviceType !== undefined) {
      updated.service_type_id = serviceType;
    }
    return updated;
  });
  renderMptsServiceList();
}

async function probeMptsServices() {
  if (!elements.btnMptsProbe) return;
  const existingInput = (state.mptsServices || [])
    .map((service) => (service && service.input ? String(service.input) : ''))
    .find((value) => value && value.trim());
  const input = prompt('Enter UDP/RTP input (udp://host:port) to scan services:', existingInput || '');
  if (!input) return;
  const trimmed = input.trim();
  const lower = trimmed.toLowerCase();
  if (!lower.startsWith('udp://') && !lower.startsWith('rtp://')) {
    setStatus('Probe supports UDP/RTP inputs only');
    return;
  }
  const durationRaw = prompt('Scan duration (seconds)', '3');
  let duration = Number(durationRaw);
  if (!Number.isFinite(duration) || duration <= 0) duration = 3;
  duration = Math.min(Math.max(duration, 1), 10);

  setStatus('Scanning MPTS services...', 'sticky');
  try {
    const payload = await apiJson('/api/v1/mpts/scan', {
      method: 'POST',
      body: JSON.stringify({ input: trimmed, duration }),
    });
    const services = Array.isArray(payload.services) ? payload.services : [];
    if (!services.length) {
      setStatus('No services found', 'sticky');
      return;
    }
    const replace = confirm('Replace current service list with scanned services?');
    if (replace) {
      state.mptsServices = services;
    } else {
      state.mptsServices = (state.mptsServices || []).concat(services);
    }
    renderMptsServiceList();
    setStatus(`Loaded ${services.length} services`);
  } catch (err) {
    setStatus(`Scan failed: ${err.message || err}`);
  }
}

function setOutputGroup(group) {
  $$('.output-group').forEach((item) => {
    item.classList.toggle('active', item.dataset.group === group);
  });
}

function setOutputHttpMode(mode) {
  $$('.output-subgroup').forEach((item) => {
    item.classList.toggle('active', item.dataset.mode === mode);
  });
}

function updateOutputAudioFixVisibility() {
  if (!elements.outputUdpAudioFixBlock) return;
  const isUdp = elements.outputType.value === 'udp';
  elements.outputUdpAudioFixBlock.classList.toggle('is-hidden', !isUdp);
  if (!isUdp) {
    elements.outputUdpAudioFixBlock.classList.remove('is-enabled');
    return;
  }
  const enabled = elements.outputUdpAudioFixEnabled && elements.outputUdpAudioFixEnabled.checked;
  elements.outputUdpAudioFixBlock.classList.toggle('is-enabled', enabled);
}

function openOutputModal(index) {
  const output = state.outputs[index];
  if (!output) return;
  state.outputEditingIndex = index;

  if (elements.outputPreset) elements.outputPreset.value = '';
  const uiType = getOutputUiType(output);
  const uiMode = getOutputUiMode(output);

  elements.outputType.value = uiType;
  elements.outputHttpMode.value = uiMode;
  setOutputGroup(uiType === 'rtp' ? 'udp' : uiType);
  setOutputHttpMode(uiMode);
  if (elements.outputBiss) {
    elements.outputBiss.value = output.biss || '';
  }

  elements.outputHttpHost.value = output.host || '0.0.0.0';
  elements.outputHttpPort.value = output.port || 8000;
  elements.outputHttpPath.value = output.path || '/stream';
  elements.outputHttpBuffer.value = output.buffer_size || 1024;
  elements.outputHttpBufferFill.value = output.buffer_fill || 256;
  elements.outputHttpKeep.checked = output.keep_active === true;
  if (elements.outputHttpSctp) {
    elements.outputHttpSctp.checked = output.sctp === true;
  }

  const defaults = getHlsDefaults(elements.streamId.value || output.id || 'stream');
  elements.outputHlsPath.value = output.path || defaults.path;
  elements.outputHlsBase.value = output.base_url || defaults.base_url;
  elements.outputHlsPlaylist.value = output.playlist || 'index.m3u8';
  elements.outputHlsPrefix.value = output.prefix || 'segment';
  elements.outputHlsTarget.value = output.target_duration || 6;
  elements.outputHlsWindow.value = output.window || 5;
  elements.outputHlsCleanup.value = output.cleanup || 10;
  elements.outputHlsWall.checked = output.use_wall !== false;
  if (elements.outputHlsNaming) {
    elements.outputHlsNaming.value = output.naming || getSettingString('hls_naming', 'sequence');
  }
  if (elements.outputHlsRound) {
    elements.outputHlsRound.checked = output.round_duration !== undefined
      ? output.round_duration === true
      : getSettingBool('hls_round_duration', false);
  }
  if (elements.outputHlsTsExtension) {
    elements.outputHlsTsExtension.value = output.ts_extension || getSettingString('hls_ts_extension', 'ts');
  }
  if (elements.outputHlsPassData) {
    elements.outputHlsPassData.checked = output.pass_data !== undefined
      ? output.pass_data === true
      : getSettingBool('hls_pass_data', true);
  }

  elements.outputUdpAddr.value = output.addr || '239.0.0.1';
  elements.outputUdpPort.value = output.port || 1234;
  elements.outputUdpTtl.value = output.ttl || 1;
  elements.outputUdpLocal.value = output.localaddr || '';
  elements.outputUdpSocket.value = output.socket_size || '';
  elements.outputUdpSync.value = output.sync || '';
  elements.outputUdpCbr.value = output.cbr || '';
  if (elements.outputUdpAudioFixEnabled) {
    const audioFix = normalizeOutputAudioFix(output.audio_fix);
    elements.outputUdpAudioFixEnabled.checked = audioFix.enabled;
    if (elements.outputUdpAudioFixForce) {
      elements.outputUdpAudioFixForce.checked = audioFix.force_on;
    }
    if (elements.outputUdpAudioFixMode) {
      elements.outputUdpAudioFixMode.value = audioFix.mode;
    }
    if (elements.outputUdpAudioFixBitrate) {
      elements.outputUdpAudioFixBitrate.value = audioFix.aac_bitrate_kbps;
    }
    if (elements.outputUdpAudioFixSampleRate) {
      elements.outputUdpAudioFixSampleRate.value = audioFix.aac_sample_rate;
    }
    if (elements.outputUdpAudioFixChannels) {
      elements.outputUdpAudioFixChannels.value = audioFix.aac_channels;
    }
    if (elements.outputUdpAudioFixProfile) {
      elements.outputUdpAudioFixProfile.value = audioFix.aac_profile || '';
    }
    if (elements.outputUdpAudioFixAsync) {
      elements.outputUdpAudioFixAsync.value = audioFix.aresample_async;
    }
    if (elements.outputUdpAudioFixSilence) {
      elements.outputUdpAudioFixSilence.checked = audioFix.silence_fallback;
    }
    elements.outputUdpAudioFixInterval.value = audioFix.probe_interval_sec;
    elements.outputUdpAudioFixDuration.value = audioFix.probe_duration_sec;
    elements.outputUdpAudioFixHold.value = audioFix.mismatch_hold_sec;
    elements.outputUdpAudioFixCooldown.value = audioFix.restart_cooldown_sec;
  }

  elements.outputSrtUrl.value = output.url || output.source_url || '';
  elements.outputSrtBridgePort.value = output.bridge_port || '';
  if (elements.outputSrtBridgeAddr) {
    elements.outputSrtBridgeAddr.value = output.bridge_addr || '127.0.0.1';
  }
  if (elements.outputSrtBridgeLocaladdr) {
    elements.outputSrtBridgeLocaladdr.value = output.bridge_localaddr || '';
  }
  if (elements.outputSrtBridgePktSize) {
    elements.outputSrtBridgePktSize.value = output.bridge_pkt_size || 1316;
  }
  if (elements.outputSrtBridgeSocket) {
    elements.outputSrtBridgeSocket.value = output.bridge_socket_size || '';
  }
  if (elements.outputSrtBridgeTtl) {
    elements.outputSrtBridgeTtl.value = output.bridge_ttl || '';
  }
  if (elements.outputSrtBridgeBin) {
    elements.outputSrtBridgeBin.value = output.bridge_bin || '';
  }
  if (elements.outputSrtBridgeLog) {
    elements.outputSrtBridgeLog.value = output.bridge_log_level || 'warning';
  }
  if (elements.outputSrtBridgeInputArgs) {
    const args = output.bridge_input_args;
    elements.outputSrtBridgeInputArgs.value = Array.isArray(args) ? argsToLines(args) : (args || '');
  }
  if (elements.outputSrtBridgeOutputArgs) {
    const args = output.bridge_output_args;
    elements.outputSrtBridgeOutputArgs.value = Array.isArray(args) ? argsToLines(args) : (args || '');
  }

  elements.outputNpHost.value = output.host || '';
  elements.outputNpPort.value = output.port || 80;
  elements.outputNpPath.value = output.path || '/push';
  elements.outputNpTimeout.value = output.timeout || 5;
  elements.outputNpBuffer.value = output.buffer_size || '';
  if (elements.outputNpBufferFill) {
    elements.outputNpBufferFill.value = output.buffer_fill || '';
  }
  if (elements.outputNpSctp) {
    elements.outputNpSctp.checked = output.sctp === true;
  }

  elements.outputFileName.value = output.filename || '/tmp/stream.ts';
  elements.outputFileBuffer.value = output.buffer_size || 32;
  elements.outputFileM2ts.checked = output.m2ts === true;
  elements.outputFileAio.checked = output.aio === true;
  elements.outputFileDirectio.checked = output.directio === true;

  updateOutputAudioFixVisibility();
  setOverlay(elements.outputOverlay, true);
}

function closeOutputModal() {
  state.outputEditingIndex = null;
  setOverlay(elements.outputOverlay, false);
}

function readOutputForm() {
  const type = elements.outputType.value;
  const biss = elements.outputBiss ? elements.outputBiss.value.trim() : '';
  const applyBiss = (output) => {
    if (biss) output.biss = biss;
    return output;
  };
  if (type === 'http') {
    const mode = elements.outputHttpMode.value;
    if (mode === 'http') {
      return applyBiss({
        format: 'http',
        host: elements.outputHttpHost.value.trim(),
        port: toNumber(elements.outputHttpPort.value) || 8000,
        path: elements.outputHttpPath.value.trim() || '/stream',
        buffer_size: toNumber(elements.outputHttpBuffer.value),
        buffer_fill: toNumber(elements.outputHttpBufferFill.value),
        keep_active: elements.outputHttpKeep.checked,
        sctp: elements.outputHttpSctp && elements.outputHttpSctp.checked,
      });
    }
    return applyBiss({
      format: 'hls',
      path: elements.outputHlsPath.value.trim(),
      base_url: elements.outputHlsBase.value.trim(),
      playlist: elements.outputHlsPlaylist.value.trim() || 'index.m3u8',
      prefix: elements.outputHlsPrefix.value.trim() || 'segment',
      target_duration: toNumber(elements.outputHlsTarget.value) || 6,
      window: toNumber(elements.outputHlsWindow.value) || 5,
      cleanup: toNumber(elements.outputHlsCleanup.value) || 10,
      use_wall: elements.outputHlsWall.checked,
      naming: elements.outputHlsNaming ? elements.outputHlsNaming.value : undefined,
      round_duration: elements.outputHlsRound ? elements.outputHlsRound.checked : undefined,
      ts_extension: elements.outputHlsTsExtension ? elements.outputHlsTsExtension.value.trim() : undefined,
      pass_data: elements.outputHlsPassData ? elements.outputHlsPassData.checked : undefined,
      auto: false,
    });
  }

  if (type === 'udp' || type === 'rtp') {
    const payload = applyBiss({
      format: type,
      addr: elements.outputUdpAddr.value.trim(),
      port: toNumber(elements.outputUdpPort.value),
      ttl: toNumber(elements.outputUdpTtl.value),
      localaddr: elements.outputUdpLocal.value.trim() || undefined,
      socket_size: toNumber(elements.outputUdpSocket.value),
      sync: toNumber(elements.outputUdpSync.value),
      cbr: toNumber(elements.outputUdpCbr.value),
    });
    if (type === 'udp' && elements.outputUdpAudioFixEnabled) {
      payload.audio_fix = {
        enabled: elements.outputUdpAudioFixEnabled.checked,
        force_on: elements.outputUdpAudioFixForce ? elements.outputUdpAudioFixForce.checked : false,
        mode: elements.outputUdpAudioFixMode ? elements.outputUdpAudioFixMode.value : OUTPUT_AUDIO_FIX_DEFAULTS.mode,
        target_audio_type: OUTPUT_AUDIO_FIX_DEFAULTS.target_audio_type,
        probe_interval_sec: toNumber(elements.outputUdpAudioFixInterval.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.probe_interval_sec,
        probe_duration_sec: toNumber(elements.outputUdpAudioFixDuration.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.probe_duration_sec,
        mismatch_hold_sec: toNumber(elements.outputUdpAudioFixHold.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.mismatch_hold_sec,
        restart_cooldown_sec: toNumber(elements.outputUdpAudioFixCooldown.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.restart_cooldown_sec,
        aac_bitrate_kbps: toNumber(elements.outputUdpAudioFixBitrate && elements.outputUdpAudioFixBitrate.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.aac_bitrate_kbps,
        aac_sample_rate: toNumber(elements.outputUdpAudioFixSampleRate && elements.outputUdpAudioFixSampleRate.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.aac_sample_rate,
        aac_channels: toNumber(elements.outputUdpAudioFixChannels && elements.outputUdpAudioFixChannels.value)
          || OUTPUT_AUDIO_FIX_DEFAULTS.aac_channels,
        aac_profile: elements.outputUdpAudioFixProfile
          ? (elements.outputUdpAudioFixProfile.value || '').trim()
          : OUTPUT_AUDIO_FIX_DEFAULTS.aac_profile,
        aresample_async: elements.outputUdpAudioFixAsync && toNumber(elements.outputUdpAudioFixAsync.value) !== undefined
          ? toNumber(elements.outputUdpAudioFixAsync.value)
          : OUTPUT_AUDIO_FIX_DEFAULTS.aresample_async,
        silence_fallback: elements.outputUdpAudioFixSilence ? elements.outputUdpAudioFixSilence.checked : false,
      };
    }
    return payload;
  }

  if (type === 'srt') {
    const output = applyBiss({
      format: 'srt',
      url: elements.outputSrtUrl.value.trim(),
      bridge_port: toNumber(elements.outputSrtBridgePort.value),
    });
    const bridgeAddr = elements.outputSrtBridgeAddr && elements.outputSrtBridgeAddr.value.trim();
    if (bridgeAddr) output.bridge_addr = bridgeAddr;
    const bridgeLocal = elements.outputSrtBridgeLocaladdr && elements.outputSrtBridgeLocaladdr.value.trim();
    if (bridgeLocal) output.bridge_localaddr = bridgeLocal;
    const bridgePkt = toNumber(elements.outputSrtBridgePktSize && elements.outputSrtBridgePktSize.value);
    if (bridgePkt !== undefined) output.bridge_pkt_size = bridgePkt;
    const bridgeSocket = toNumber(elements.outputSrtBridgeSocket && elements.outputSrtBridgeSocket.value);
    if (bridgeSocket !== undefined) output.bridge_socket_size = bridgeSocket;
    const bridgeTtl = toNumber(elements.outputSrtBridgeTtl && elements.outputSrtBridgeTtl.value);
    if (bridgeTtl !== undefined) output.bridge_ttl = bridgeTtl;
    const bridgeBin = elements.outputSrtBridgeBin && elements.outputSrtBridgeBin.value.trim();
    if (bridgeBin) output.bridge_bin = bridgeBin;
    const bridgeLog = elements.outputSrtBridgeLog && elements.outputSrtBridgeLog.value.trim();
    if (bridgeLog) output.bridge_log_level = bridgeLog;
    const bridgeInputArgs = elements.outputSrtBridgeInputArgs && linesToArgs(elements.outputSrtBridgeInputArgs.value);
    if (bridgeInputArgs && bridgeInputArgs.length) output.bridge_input_args = bridgeInputArgs;
    const bridgeOutputArgs = elements.outputSrtBridgeOutputArgs && linesToArgs(elements.outputSrtBridgeOutputArgs.value);
    if (bridgeOutputArgs && bridgeOutputArgs.length) output.bridge_output_args = bridgeOutputArgs;
    return output;
  }

  if (type === 'np') {
    return applyBiss({
      format: 'np',
      host: elements.outputNpHost.value.trim(),
      port: toNumber(elements.outputNpPort.value),
      path: elements.outputNpPath.value.trim(),
      timeout: toNumber(elements.outputNpTimeout.value),
      buffer_size: toNumber(elements.outputNpBuffer.value),
      buffer_fill: toNumber(elements.outputNpBufferFill && elements.outputNpBufferFill.value),
      sctp: elements.outputNpSctp && elements.outputNpSctp.checked,
    });
  }

  if (type === 'file') {
    return applyBiss({
      format: 'file',
      filename: elements.outputFileName.value.trim(),
      buffer_size: toNumber(elements.outputFileBuffer.value),
      m2ts: elements.outputFileM2ts.checked,
      aio: elements.outputFileAio.checked,
      directio: elements.outputFileDirectio.checked,
    });
  }

  return null;
}

function openTranscodeOutputModal(index) {
  const output = state.transcodeOutputs[index];
  if (!output) return;
  state.transcodeOutputEditingIndex = index;

  if (elements.transcodeOutputPreset) elements.transcodeOutputPreset.value = '';
  if (elements.transcodeOutputError) elements.transcodeOutputError.textContent = '';
  elements.transcodeOutputName.value = output.name || '';
  elements.transcodeOutputUrl.value = output.url || '';
  elements.transcodeOutputVf.value = output.vf || '';
  elements.transcodeOutputVcodec.value = output.vcodec || '';
  if (elements.transcodeOutputRepeatHeaders) {
    elements.transcodeOutputRepeatHeaders.checked = hasX264RepeatHeaders(output.v_args);
    updateRepeatHeadersToggle();
  }
  elements.transcodeOutputVArgs.value = argsToLines(output.v_args);
  elements.transcodeOutputAcodec.value = output.acodec || '';
  elements.transcodeOutputAArgs.value = argsToLines(output.a_args);
  elements.transcodeOutputFormatArgs.value = argsToLines(output.format_args);
  elements.transcodeOutputMetadata.value = argsToLines(output.metadata);

  setOverlay(elements.transcodeOutputOverlay, true);
}

function closeTranscodeOutputModal() {
  state.transcodeOutputEditingIndex = null;
  if (elements.transcodeOutputError) elements.transcodeOutputError.textContent = '';
  setOverlay(elements.transcodeOutputOverlay, false);
}

function readTranscodeOutputForm() {
  const name = elements.transcodeOutputName.value.trim();
  const url = elements.transcodeOutputUrl.value.trim();
  const vf = elements.transcodeOutputVf.value.trim();
  const vcodec = elements.transcodeOutputVcodec.value.trim();
  let vArgs = linesToArgs(elements.transcodeOutputVArgs.value);
  if (elements.transcodeOutputRepeatHeaders && isLibx264Codec(vcodec)) {
    vArgs = toggleX264RepeatHeaders(vArgs, elements.transcodeOutputRepeatHeaders.checked);
  }
  const acodec = elements.transcodeOutputAcodec.value.trim();
  const aArgs = linesToArgs(elements.transcodeOutputAArgs.value);
  const formatArgs = linesToArgs(elements.transcodeOutputFormatArgs.value);
  const metadata = linesToArgs(elements.transcodeOutputMetadata.value);

  const output = {};
  if (name) output.name = name;
  if (url) output.url = url;
  if (vf) output.vf = vf;
  if (vcodec) output.vcodec = vcodec;
  if (vArgs.length) output.v_args = vArgs;
  if (acodec) output.acodec = acodec;
  if (aArgs.length) output.a_args = aArgs;
  if (formatArgs.length) output.format_args = formatArgs;
  if (metadata.length) output.metadata = metadata;

  if (state.transcodeOutputEditingIndex !== null) {
    const existing = state.transcodeOutputs[state.transcodeOutputEditingIndex];
    if (existing && existing.watchdog) {
      output.watchdog = existing.watchdog;
    }
  }

  return output;
}

function openTranscodeMonitorModal(index) {
  const output = state.transcodeOutputs[index];
  if (!output) return;
  state.transcodeOutputMonitorIndex = index;
  if (elements.transcodeMonitorError) elements.transcodeMonitorError.textContent = '';

  const normalized = ensureTranscodeOutputWatchdog(output);
  state.transcodeOutputs[index] = normalized;
  const watchdog = normalized.watchdog || normalizeOutputWatchdog(null, TRANSCODE_WATCHDOG_DEFAULTS);

  if (elements.transcodeMonitorTitle) {
    const label = normalized.name ? ` — ${normalized.name}` : '';
    elements.transcodeMonitorTitle.textContent = `Output #${index + 1}${label}`;
  }
  if (elements.transcodeMonitorTarget) {
    const url = normalized.url || 'n/a';
    elements.transcodeMonitorTarget.textContent = `Monitoring output: ${url}`;
  }
  if (elements.transcodeMonitorProbeTarget) {
    const url = normalized.url || 'n/a';
    elements.transcodeMonitorProbeTarget.textContent = `Probe target: ${url}`;
  }

  if (elements.transcodeMonitorRestartDelay) elements.transcodeMonitorRestartDelay.value = watchdog.restart_delay_sec;
  if (elements.transcodeMonitorNoProgress) elements.transcodeMonitorNoProgress.value = watchdog.no_progress_timeout_sec;
  if (elements.transcodeMonitorMaxErrors) elements.transcodeMonitorMaxErrors.value = watchdog.max_error_lines_per_min;
  if (elements.transcodeMonitorDesyncMs) elements.transcodeMonitorDesyncMs.value = watchdog.desync_threshold_ms;
  if (elements.transcodeMonitorDesyncCount) elements.transcodeMonitorDesyncCount.value = watchdog.desync_fail_count;
  if (elements.transcodeMonitorMaxRestarts) elements.transcodeMonitorMaxRestarts.value = watchdog.max_restarts_per_10min;
  if (elements.transcodeMonitorEngine) elements.transcodeMonitorEngine.value = normalizeMonitorEngine(watchdog.monitor_engine);
  if (elements.transcodeMonitorProbeInterval) elements.transcodeMonitorProbeInterval.value = watchdog.probe_interval_sec;
  if (elements.transcodeMonitorProbeDuration) elements.transcodeMonitorProbeDuration.value = watchdog.probe_duration_sec;
  if (elements.transcodeMonitorProbeTimeout) elements.transcodeMonitorProbeTimeout.value = watchdog.probe_timeout_sec;
  if (elements.transcodeMonitorProbeFail) elements.transcodeMonitorProbeFail.value = watchdog.probe_fail_count;
  if (elements.transcodeMonitorLowEnabled) elements.transcodeMonitorLowEnabled.checked = watchdog.low_bitrate_enabled === true;
  if (elements.transcodeMonitorLowMin) elements.transcodeMonitorLowMin.value = watchdog.low_bitrate_min_kbps;
  if (elements.transcodeMonitorLowHold) elements.transcodeMonitorLowHold.value = watchdog.low_bitrate_hold_sec;
  if (elements.transcodeMonitorCooldown) elements.transcodeMonitorCooldown.value = watchdog.restart_cooldown_sec;

  setOverlay(elements.transcodeMonitorOverlay, true);
}

function closeTranscodeMonitorModal() {
  state.transcodeOutputMonitorIndex = null;
  if (elements.transcodeMonitorError) elements.transcodeMonitorError.textContent = '';
  setOverlay(elements.transcodeMonitorOverlay, false);
}

function readTranscodeMonitorForm() {
  const watchdog = normalizeOutputWatchdog({
    restart_delay_sec: toNumber(elements.transcodeMonitorRestartDelay && elements.transcodeMonitorRestartDelay.value),
    no_progress_timeout_sec: toNumber(elements.transcodeMonitorNoProgress && elements.transcodeMonitorNoProgress.value),
    max_error_lines_per_min: toNumber(elements.transcodeMonitorMaxErrors && elements.transcodeMonitorMaxErrors.value),
    desync_threshold_ms: toNumber(elements.transcodeMonitorDesyncMs && elements.transcodeMonitorDesyncMs.value),
    desync_fail_count: toNumber(elements.transcodeMonitorDesyncCount && elements.transcodeMonitorDesyncCount.value),
    max_restarts_per_10min: toNumber(elements.transcodeMonitorMaxRestarts && elements.transcodeMonitorMaxRestarts.value),
    probe_interval_sec: toNumber(elements.transcodeMonitorProbeInterval && elements.transcodeMonitorProbeInterval.value),
    probe_duration_sec: toNumber(elements.transcodeMonitorProbeDuration && elements.transcodeMonitorProbeDuration.value),
    probe_timeout_sec: toNumber(elements.transcodeMonitorProbeTimeout && elements.transcodeMonitorProbeTimeout.value),
    probe_fail_count: toNumber(elements.transcodeMonitorProbeFail && elements.transcodeMonitorProbeFail.value),
    monitor_engine: elements.transcodeMonitorEngine && elements.transcodeMonitorEngine.value,
    low_bitrate_enabled: elements.transcodeMonitorLowEnabled && elements.transcodeMonitorLowEnabled.checked,
    low_bitrate_min_kbps: toNumber(elements.transcodeMonitorLowMin && elements.transcodeMonitorLowMin.value),
    low_bitrate_hold_sec: toNumber(elements.transcodeMonitorLowHold && elements.transcodeMonitorLowHold.value),
    restart_cooldown_sec: toNumber(elements.transcodeMonitorCooldown && elements.transcodeMonitorCooldown.value),
  }, state.transcodeWatchdogDefaults || TRANSCODE_WATCHDOG_DEFAULTS);

  return watchdog;
}

function setInputGroup(group) {
  $$('.input-group').forEach((item) => {
    item.classList.toggle('active', item.dataset.group === group);
  });
}

function openInputModal(index) {
  const url = state.inputs[index] || '';
  const parsed = parseInputUrl(url);
  state.inputEditingIndex = index;

  if (elements.inputPreset) elements.inputPreset.value = '';
  const format = parsed.format || 'udp';
  elements.inputType.value = format;
  const group = (format === 'rtp') ? 'udp'
    : (format === 'hls' ? 'http'
      : (format === 'srt' || format === 'rtsp' ? 'bridge' : format));
  setInputGroup(group);

  const opts = parsed.options || {};
  const knownOptions = new Set([
    'pnr',
    'set_pnr',
    'set_tsid',
    'biss',
    'cam',
    'ecm_pid',
    'shift',
    'cas',
    'map',
    'filter',
    'filter~',
    'pass_sdt',
    'pass_eit',
    'no_reload',
    'no_analyze',
    'cc_limit',
    'bitrate_limit',
    'ua',
    'timeout',
    'buffer_size',
    'socket_size',
    'loop',
    'bridge_port',
  ]);
  const extras = {};
  Object.keys(opts).forEach((key) => {
    if (!knownOptions.has(key)) {
      extras[key] = opts[key];
    }
  });
  state.inputExtras[index] = extras;
  const asBool = (value) => value === true || value === 'true' || value === '1';

  elements.inputDvbId.value = parsed.dvbId || '';

  elements.inputUdpIface.value = parsed.iface || '';
  elements.inputUdpAddr.value = parsed.addr || '';
  elements.inputUdpPort.value = parsed.port || '';
  elements.inputUdpSocket.value = opts.socket_size || '';

  elements.inputHttpLogin.value = parsed.login || '';
  elements.inputHttpPass.value = parsed.password || '';
  elements.inputHttpHost.value = parsed.host || '';
  elements.inputHttpPort.value = parsed.port || '';
  elements.inputHttpPath.value = parsed.path || '/';
  elements.inputHttpUa.value = opts.ua || '';
  elements.inputHttpTimeout.value = opts.timeout || '';
  elements.inputHttpBuffer.value = opts.buffer_size || '';

  elements.inputBridgeUrl.value = parsed.url || '';
  elements.inputBridgePort.value = opts.bridge_port || '';

  elements.inputFileName.value = parsed.file || '';
  elements.inputFileLoop.checked = asBool(opts.loop);
  if (elements.inputStreamId) {
    elements.inputStreamId.value = parsed.streamId || '';
  }

  elements.inputPnr.value = opts.pnr || '';
  elements.inputSetPnr.value = opts.set_pnr || '';
  elements.inputSetTsid.value = opts.set_tsid || '';
  elements.inputBiss.value = opts.biss || '';
  const camValue = (opts.cam && opts.cam !== true && opts.cam !== 'true') ? String(opts.cam) : '';
  refreshInputCamOptions(camValue);
  elements.inputEcmPid.value = opts.ecm_pid || '';
  elements.inputShift.value = opts.shift || '';
  elements.inputMap.value = opts.map || '';
  elements.inputFilter.value = opts.filter || '';
  elements.inputFilterNot.value = opts['filter~'] || '';
  elements.inputCcLimit.value = opts.cc_limit || '';
  elements.inputBitrateLimit.value = opts.bitrate_limit || '';

  elements.inputCam.checked = asBool(opts.cam) || !!elements.inputCamId.value;
  elements.inputCas.checked = asBool(opts.cas);
  elements.inputPassSdt.checked = asBool(opts.pass_sdt);
  elements.inputPassEit.checked = asBool(opts.pass_eit);
  elements.inputNoReload.checked = asBool(opts.no_reload);
  elements.inputNoAnalyze.checked = asBool(opts.no_analyze);

  setOverlay(elements.inputOverlay, true);
}

function closeInputModal() {
  state.inputEditingIndex = null;
  setOverlay(elements.inputOverlay, false);
}

function readInputForm() {
  const format = elements.inputType.value;
  const options = {};

  const addNumber = (key, value) => {
    const num = toNumber(value);
    if (num !== undefined) options[key] = num;
  };

  const addString = (key, value) => {
    const str = (value || '').trim();
    if (str) options[key] = str;
  };

  addNumber('pnr', elements.inputPnr.value);
  addNumber('set_pnr', elements.inputSetPnr.value);
  addNumber('set_tsid', elements.inputSetTsid.value);
  addString('biss', elements.inputBiss.value);
  addNumber('ecm_pid', elements.inputEcmPid.value);
  addNumber('shift', elements.inputShift.value);
  addString('map', elements.inputMap.value);
  addString('filter', elements.inputFilter.value);
  addString('filter~', elements.inputFilterNot.value);
  addNumber('cc_limit', elements.inputCcLimit.value);
  addNumber('bitrate_limit', elements.inputBitrateLimit.value);

  if (elements.inputCam.checked) {
    const camId = elements.inputCamId.value.trim();
    options.cam = camId || true;
  } else if (elements.inputCamId.value.trim()) {
    options.cam = elements.inputCamId.value.trim();
  }

  if (elements.inputCas.checked) options.cas = true;
  if (elements.inputPassSdt.checked) options.pass_sdt = true;
  if (elements.inputPassEit.checked) options.pass_eit = true;
  if (elements.inputNoReload.checked) options.no_reload = true;
  if (elements.inputNoAnalyze.checked) options.no_analyze = true;

  const data = { format, options };

  if (format === 'dvb') {
    data.dvbId = elements.inputDvbId.value.trim();
    if (!data.dvbId) throw new Error('DVB adapter id is required');
  } else if (format === 'udp' || format === 'rtp') {
    data.iface = elements.inputUdpIface.value.trim();
    data.addr = elements.inputUdpAddr.value.trim();
    data.port = elements.inputUdpPort.value.trim();
    addNumber('socket_size', elements.inputUdpSocket.value);
    if (!data.addr) throw new Error('UDP address is required');
  } else if (format === 'http' || format === 'hls') {
    data.login = elements.inputHttpLogin.value.trim();
    data.password = elements.inputHttpPass.value;
    data.host = elements.inputHttpHost.value.trim();
    data.port = elements.inputHttpPort.value.trim();
    data.path = elements.inputHttpPath.value.trim() || '/';
    addString('ua', elements.inputHttpUa.value);
    addNumber('timeout', elements.inputHttpTimeout.value);
    addNumber('buffer_size', elements.inputHttpBuffer.value);
    if (!data.host) throw new Error('HTTP host is required');
  } else if (format === 'srt' || format === 'rtsp') {
    data.url = elements.inputBridgeUrl.value.trim();
    const bridgePort = toNumber(elements.inputBridgePort.value);
    if (bridgePort !== undefined) {
      options.bridge_port = bridgePort;
    }
    if (!data.url) throw new Error('URL is required');
    if (!options.bridge_port) throw new Error('Bridge port is required');
  } else if (format === 'file') {
    data.file = elements.inputFileName.value.trim();
    if (!data.file) throw new Error('Filename is required');
    if (elements.inputFileLoop.checked) options.loop = true;
  } else if (format === 'stream') {
    data.streamId = elements.inputStreamId ? elements.inputStreamId.value.trim() : '';
    if (!data.streamId) throw new Error('Stream ID is required');
  }

  const extras = state.inputExtras[state.inputEditingIndex] || {};
  Object.keys(extras).forEach((key) => {
    if (options[key] === undefined) {
      options[key] = extras[key];
    }
  });

  return buildInputUrl(data);
}

function setAdapterGroup(type) {
  const upper = (type || '').toUpperCase();
  const group = upper.startsWith('S') ? 'sat'
    : upper.startsWith('T') ? 'terrestrial'
    : upper.startsWith('C') ? 'cable'
    : upper === 'ATSC' ? 'atsc'
    : null;
  $$('.adapter-group').forEach((item) => {
    const groupName = item.dataset.group;
    const isActive = groupName === group || (groupName === 'not-sat' && group !== 'sat');
    item.classList.toggle('active', isActive);
  });
}

function setAdapterEditorActive(active) {
  if (!elements.adapterEditor) return;
  elements.adapterEditor.classList.toggle('active', active);
}

function adapterSummary(adapter) {
  const config = (adapter && adapter.config) || {};
  const parts = [];
  if (config.type) parts.push(String(config.type).toUpperCase());
  if (config.adapter !== undefined) parts.push(`Adapter ${config.adapter}`);
  if (config.device !== undefined) parts.push(`FE ${config.device}`);
  if (config.tp) parts.push(config.tp);
  if (!config.tp && config.frequency !== undefined) parts.push(`${config.frequency} MHz`);
  return parts.filter(Boolean).join(' · ');
}

function normalizeDvbKey(adapter, device) {
  const a = Number(adapter);
  const d = device === undefined ? 0 : Number(device);
  if (!Number.isFinite(a)) return null;
  const deviceNum = Number.isFinite(d) ? d : 0;
  return `${a}.${deviceNum}`;
}

function findDvbAdapter(adapter, device) {
  const key = normalizeDvbKey(adapter, device);
  if (!key) return null;
  return (state.dvbAdapters || []).find((item) => normalizeDvbKey(item.adapter, item.device) === key) || null;
}

function formatDvbStatus(item) {
  if (!item) return { label: 'MISSING', className: 'missing', hint: 'Adapter not detected' };
  if (item.error) return { label: 'ERROR', className: 'error', hint: item.error };
  if (item.busy) return { label: 'BUSY', className: 'busy', hint: 'Adapter is in use' };
  return { label: 'FREE', className: 'free', hint: 'Adapter is available' };
}

function normalizeAdapterValue(value) {
  if (value === undefined || value === null || value === '') return '';
  const num = Number(value);
  return Number.isFinite(num) ? String(num) : String(value).trim();
}

function getDvbAdapterMap() {
  const map = new Map();
  (state.dvbAdapters || []).forEach((item) => {
    if (!item || item.adapter === undefined || item.adapter === null) return;
    const adapterValue = normalizeAdapterValue(item.adapter);
    if (!adapterValue) return;
    if (!map.has(adapterValue)) map.set(adapterValue, []);
    map.get(adapterValue).push(item);
  });
  map.forEach((items) => {
    items.sort((a, b) => Number(a.device || 0) - Number(b.device || 0));
  });
  return map;
}

function renderAdapterIndexSelect(selectedAdapter) {
  if (!elements.adapterIndex) return '';
  const adapterValue = normalizeAdapterValue(selectedAdapter || elements.adapterIndex.value);
  const adapterMap = getDvbAdapterMap();
  const adapters = Array.from(adapterMap.keys()).sort((a, b) => Number(a) - Number(b));

  elements.adapterIndex.innerHTML = '';

  const hasOptions = adapters.length > 0;
  if (!state.dvbAdaptersLoaded || !hasOptions) {
    const option = document.createElement('option');
    option.value = adapterValue;
    option.textContent = adapterValue ? `adapter${adapterValue} (missing)` : 'No DVB adapters detected';
    elements.adapterIndex.appendChild(option);
    elements.adapterIndex.value = adapterValue;
    elements.adapterIndex.disabled = true;
    return adapterValue;
  }

  adapters.forEach((value) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = `adapter${value}`;
    elements.adapterIndex.appendChild(option);
  });

  let nextValue = adapterValue || adapters[0] || '';
  if (nextValue && !adapterMap.has(nextValue)) {
    const option = document.createElement('option');
    option.value = nextValue;
    option.textContent = `adapter${nextValue} (missing)`;
    elements.adapterIndex.appendChild(option);
  }
  elements.adapterIndex.value = nextValue;
  elements.adapterIndex.disabled = false;
  return nextValue;
}

function renderAdapterDeviceSelect(adapterValue, selectedDevice) {
  if (!elements.adapterDevice) return;
  const deviceValue = normalizeAdapterValue(selectedDevice || elements.adapterDevice.value);
  const adapterMap = getDvbAdapterMap();
  const items = adapterValue ? (adapterMap.get(String(adapterValue)) || []) : [];
  const devices = Array.from(new Set(items.map((item) => normalizeAdapterValue(item.device || 0))))
    .filter((value) => value !== '')
    .sort((a, b) => Number(a) - Number(b));

  elements.adapterDevice.innerHTML = '';

  if (!state.dvbAdaptersLoaded || devices.length === 0) {
    const option = document.createElement('option');
    option.value = deviceValue || '0';
    option.textContent = deviceValue ? `fe${deviceValue} (missing)` : 'fe0';
    elements.adapterDevice.appendChild(option);
    elements.adapterDevice.value = option.value;
    elements.adapterDevice.disabled = !state.dvbAdaptersLoaded;
    return;
  }

  devices.forEach((value) => {
    const option = document.createElement('option');
    option.value = value;
    option.textContent = `fe${value}`;
    elements.adapterDevice.appendChild(option);
  });

  let nextValue = deviceValue || devices[0] || '0';
  if (nextValue && !devices.includes(nextValue)) {
    const option = document.createElement('option');
    option.value = nextValue;
    option.textContent = `fe${nextValue} (missing)`;
    elements.adapterDevice.appendChild(option);
  }
  elements.adapterDevice.value = nextValue;
  elements.adapterDevice.disabled = false;
}

function renderAdapterHardwareSelects(selectedAdapter, selectedDevice) {
  const adapterValue = renderAdapterIndexSelect(selectedAdapter);
  renderAdapterDeviceSelect(adapterValue, selectedDevice);
}

function renderDvbDetectedSelect() {
  if (!elements.adapterDetected) return;
  elements.adapterDetected.innerHTML = '';
  const placeholder = document.createElement('option');
  placeholder.value = '';
  placeholder.textContent = 'Manual';
  elements.adapterDetected.appendChild(placeholder);

  if (!state.dvbAdaptersLoaded) {
    if (elements.adapterDetectedHint) {
      elements.adapterDetectedHint.textContent = 'DVB adapter list is unavailable.';
      elements.adapterDetectedHint.className = 'form-hint adapter-detected-hint missing';
    }
    if (elements.adapterDetectedBadge) {
      elements.adapterDetectedBadge.textContent = '';
      elements.adapterDetectedBadge.className = 'adapter-detected-badge';
    }
    updateAdapterBusyWarningFromFields();
    return;
  }

  const list = Array.isArray(state.dvbAdapters) ? state.dvbAdapters : [];
  const groups = {
    free: [],
    busy: [],
    error: [],
  };
  list.forEach((item) => {
    if (item && item.error) {
      groups.error.push(item);
    } else if (item && item.busy) {
      groups.busy.push(item);
    } else {
      groups.free.push(item);
    }
  });

  const renderGroup = (label, items) => {
    if (!items.length) return;
    items.sort((a, b) => {
      const aKey = normalizeDvbKey(a.adapter, a.device) || '';
      const bKey = normalizeDvbKey(b.adapter, b.device) || '';
      return aKey.localeCompare(bKey, undefined, { numeric: true });
    });
    const group = document.createElement('optgroup');
    group.label = label;
    items.forEach((item) => {
      const option = document.createElement('option');
      const key = normalizeDvbKey(item.adapter, item.device);
      const status = formatDvbStatus(item);
      const type = item.type || 'Unknown';
      const name = item.frontend ? ` · ${item.frontend}` : '';
      option.value = key || '';
      option.textContent = `${status.label} · adapter${item.adapter}.fe${item.device} · ${type}${name}`;
      option.dataset.status = status.className || '';
      group.appendChild(option);
    });
    elements.adapterDetected.appendChild(group);
  };

  renderGroup('FREE', groups.free);
  renderGroup('BUSY', groups.busy);
  renderGroup('ERROR', groups.error);

  renderAdapterHardwareSelects();
  if (!state.adapterEditing || !state.adapterEditing.adapter) {
    elements.adapterDetected.value = '';
    if (elements.adapterDetectedHint) {
      elements.adapterDetectedHint.textContent = 'Select a detected adapter to fill Adapter/Device/Type fields.';
      elements.adapterDetectedHint.className = 'form-hint';
    }
    if (elements.adapterDetectedBadge) {
      elements.adapterDetectedBadge.textContent = '';
      elements.adapterDetectedBadge.className = 'adapter-detected-badge';
    }
    updateAdapterBusyWarningFromFields();
    return;
  }
  const config = state.adapterEditing.adapter.config || {};
  const selectedKey = normalizeDvbKey(config.adapter, config.device);
  elements.adapterDetected.value = selectedKey || '';
  if (elements.adapterDetectedHint) {
    const item = findDvbAdapter(config.adapter, config.device);
    const status = formatDvbStatus(item);
    elements.adapterDetectedHint.textContent = status.hint;
    elements.adapterDetectedHint.className = `form-hint adapter-detected-hint ${status.className}`;
  }
  if (elements.adapterDetectedBadge) {
    const item = findDvbAdapter(config.adapter, config.device);
    const status = formatDvbStatus(item);
    elements.adapterDetectedBadge.textContent = item ? status.label : '';
    elements.adapterDetectedBadge.className = `adapter-detected-badge ${item ? status.className : ''}`.trim();
  }
  updateAdapterBusyWarningFromFields();
}

function updateAdapterBusyWarningFromFields() {
  if (!elements.adapterIndex || !elements.adapterDevice) return;
  if (!state.dvbAdaptersLoaded) {
    if (elements.adapterBusyWarning) elements.adapterBusyWarning.textContent = '';
    const fields = [elements.adapterIndex, elements.adapterDevice, elements.adapterType]
      .map((input) => input && input.closest('.field'))
      .filter(Boolean);
    fields.forEach((field) => field.classList.remove('warn'));
    if (elements.adapterDetectedHint) {
      elements.adapterDetectedHint.textContent = 'DVB adapter list is unavailable.';
      elements.adapterDetectedHint.className = 'form-hint adapter-detected-hint missing';
    }
    if (elements.adapterDetectedBadge) {
      elements.adapterDetectedBadge.textContent = '';
      elements.adapterDetectedBadge.className = 'adapter-detected-badge';
    }
    return;
  }
  const adapterValue = elements.adapterIndex.value;
  const deviceValue = elements.adapterDevice.value || 0;
  const item = findDvbAdapter(adapterValue, deviceValue);
  const isBusy = item && item.busy === true;
  const fields = [elements.adapterIndex, elements.adapterDevice, elements.adapterType]
    .map((input) => input && input.closest('.field'))
    .filter(Boolean);
  fields.forEach((field) => field.classList.toggle('warn', isBusy));
  if (elements.adapterBusyWarning) {
    if (isBusy) {
      elements.adapterBusyWarning.textContent = 'Selected adapter is busy. Choose a free adapter or release it.';
    } else {
      elements.adapterBusyWarning.textContent = '';
    }
  }
  if (elements.adapterDetected) {
    const key = normalizeDvbKey(adapterValue, deviceValue);
    const hasOption = key && elements.adapterDetected.querySelector(`option[value="${key}"]`);
    elements.adapterDetected.value = hasOption ? key : '';
    if (elements.adapterDetectedHint) {
      const status = formatDvbStatus(item);
      elements.adapterDetectedHint.textContent = status.hint;
      elements.adapterDetectedHint.className = `form-hint adapter-detected-hint ${status.className}`;
    }
    if (elements.adapterDetectedBadge) {
      const status = formatDvbStatus(item);
      elements.adapterDetectedBadge.textContent = item ? status.label : '';
      elements.adapterDetectedBadge.className = `adapter-detected-badge ${item ? status.className : ''}`.trim();
    }
  }
}

function getAdapterStatusEntry(adapterId, cfg) {
  if (!adapterId || !state.adapterStatus) return null;
  const direct = state.adapterStatus[adapterId];
  if (direct) return direct;
  let config = cfg || null;
  if (!config) {
    const adapter = state.adapterEditing && state.adapterEditing.adapter;
    config = adapter && adapter.config ? adapter.config : null;
  }
  const adapterNum = config && config.adapter !== undefined ? String(config.adapter) : null;
  const deviceNum = config && config.device !== undefined ? String(config.device) : null;
  if (!adapterNum) return null;
  const list = Object.values(state.adapterStatus);
  for (const entry of list) {
    if (!entry || entry.adapter === undefined) continue;
    if (String(entry.adapter) === adapterNum && String(entry.device || 0) === String(deviceNum || 0)) {
      return entry;
    }
  }
  return null;
}

function isAdapterLocked(adapterId, cfg) {
  const status = getAdapterStatusEntry(adapterId, cfg);
  if (!status || status.status === undefined || status.status === null) return false;
  return hasStatusBit(status.status, FE_HAS_LOCK);
}

function formatScanSignalLine(status) {
  if (!status) return 'No signal data.';
  const flags = formatStatusFlags(status.status);
  const ber = status.ber !== undefined ? status.ber : '-';
  const unc = status.unc !== undefined ? status.unc : '-';
  const signal = status.signal !== undefined ? formatPercent(status.signal) : '-';
  const snr = status.snr !== undefined ? formatPercent(status.snr) : '-';
  return `STATUS:${flags} BER:${ber} UNC:${unc} S:${signal} C/N:${snr}`;
}

function updateAdapterScanAvailability() {
  if (!elements.adapterScan) return;
  const adapter = state.adapterEditing && state.adapterEditing.adapter;
  const adapterId = adapter && adapter.id;
  const isNew = state.adapterEditing && state.adapterEditing.isNew;
  const status = adapterId ? getAdapterStatusEntry(adapterId, adapter && adapter.config) : null;
  const locked = adapterId ? isAdapterLocked(adapterId, adapter && adapter.config) : false;
  const hasSignal = status && (
    (Number(status.status) > 0)
    || (Number(status.signal) > 0)
    || (Number(status.snr) > 0)
  );
  let reason = '';
  let warning = '';
  if (!adapterId || isNew) {
    reason = 'Save adapter to enable scan.';
  } else if (!status) {
    warning = 'Adapter status unavailable; scan may fail.';
  } else if (!locked && !hasSignal) {
    warning = 'Signal not locked; scan may fail.';
  }
  elements.adapterScan.disabled = !!reason;
  elements.adapterScan.title = reason || warning || '';
}

function closeAdapterScanModal() {
  if (state.adapterScanPoll) {
    clearInterval(state.adapterScanPoll);
    state.adapterScanPoll = null;
  }
  state.adapterScanJobId = null;
  state.adapterScanResults = null;
  if (elements.adapterScanStatus) elements.adapterScanStatus.textContent = '';
  if (elements.adapterScanSignal) elements.adapterScanSignal.textContent = '';
  if (elements.adapterScanList) elements.adapterScanList.innerHTML = '';
  setOverlay(elements.adapterScanOverlay, false);
}

function renderAdapterScanResults(job) {
  if (!elements.adapterScanList) return;
  elements.adapterScanList.innerHTML = '';
  const channels = (job && job.channels) || [];
  if (!channels.length) {
    const empty = document.createElement('div');
    empty.className = 'scan-empty';
    empty.textContent = 'No channels found.';
    elements.adapterScanList.appendChild(empty);
    return;
  }
  channels.forEach((channel) => {
    const wrapper = document.createElement('div');
    wrapper.className = 'scan-channel';

    const header = document.createElement('label');
    header.className = 'scan-channel-header';
    const checkbox = document.createElement('input');
    checkbox.type = 'checkbox';
    checkbox.dataset.pnr = String(channel.pnr || '');
    checkbox.className = 'scan-channel-checkbox';
    const title = document.createElement('div');
    const name = channel.name || `PNR ${channel.pnr}`;
    const provider = channel.provider ? ` · ${channel.provider}` : '';
    title.textContent = `PNR:${channel.pnr} ${name}${provider}`;
    header.appendChild(checkbox);
    header.appendChild(title);
    wrapper.appendChild(header);

    if (channel.cas && channel.cas.length) {
      const casText = channel.cas
        .map((entry) => `0x${Number(entry.caid).toString(16)}${entry.pid ? `, PID:${entry.pid}` : ''}`)
        .join(', ');
      const cas = document.createElement('div');
      cas.className = 'scan-channel-meta';
      cas.innerHTML = `<strong>CAS:</strong> ${casText}`;
      wrapper.appendChild(cas);
    }

    const videos = channel.video || [];
    if (videos.length) {
      const vText = videos.map((v) => `VPID:${v.pid} ${v.type || ''}`.trim()).join(' · ');
      const vEl = document.createElement('div');
      vEl.className = 'scan-channel-meta';
      vEl.innerHTML = `<strong>${vText}</strong>`;
      wrapper.appendChild(vEl);
    }

    const audios = channel.audio || [];
    if (audios.length) {
      const aText = audios
        .map((a) => `APID:${a.pid}${a.lang ? ` ${a.lang}` : ''}`)
        .join(' · ');
      const aEl = document.createElement('div');
      aEl.className = 'scan-channel-meta';
      aEl.innerHTML = `<strong>${aText}</strong>`;
      wrapper.appendChild(aEl);
    }

    elements.adapterScanList.appendChild(wrapper);
  });
}

async function pollAdapterScan(jobId) {
  if (!jobId) return;
  try {
    const job = await apiJson(`/api/v1/dvb-scan/${jobId}`);
    state.adapterScanResults = job;
    if (elements.adapterScanStatus) {
      elements.adapterScanStatus.textContent = job.status === 'running'
        ? 'Scanning...'
        : (job.status === 'done' ? 'Scan complete.' : 'Scan failed.');
    }
    if (elements.adapterScanSignal) {
      elements.adapterScanSignal.textContent = formatScanSignalLine(job.signal);
    }
    if (job.status === 'done' || job.status === 'error') {
      if (state.adapterScanPoll) {
        clearInterval(state.adapterScanPoll);
        state.adapterScanPoll = null;
      }
      renderAdapterScanResults(job);
    }
  } catch (err) {
    if (elements.adapterScanStatus) {
      elements.adapterScanStatus.textContent = formatNetworkError(err) || err.message || 'Scan failed.';
    }
    if (state.adapterScanPoll) {
      clearInterval(state.adapterScanPoll);
      state.adapterScanPoll = null;
    }
  }
}

async function startAdapterScan(adapterId, opts) {
  if (!adapterId) return;
  const warning = opts && opts.warning ? `${opts.warning} ` : '';
  if (elements.adapterScanStatus) elements.adapterScanStatus.textContent = `${warning}Starting scan...`;
  if (elements.adapterScanSignal) {
    const status = getAdapterStatusEntry(adapterId);
    elements.adapterScanSignal.textContent = formatScanSignalLine(status);
  }
  if (elements.adapterScanList) elements.adapterScanList.innerHTML = '';
  const response = await apiJson('/api/v1/dvb-scan', {
    method: 'POST',
    body: JSON.stringify({ adapter_id: adapterId }),
  });
  state.adapterScanJobId = response.id;
  if (state.adapterScanPoll) {
    clearInterval(state.adapterScanPoll);
  }
  state.adapterScanPoll = setInterval(() => {
    pollAdapterScan(state.adapterScanJobId);
  }, 1000);
  await pollAdapterScan(state.adapterScanJobId);
}

function extractDvbPnr(input, adapterId) {
  if (!input) return null;
  if (typeof input === 'string') {
    if (!input.startsWith('dvb://')) return null;
    if (adapterId && !input.startsWith(`dvb://${adapterId}`)) return null;
    const match = input.match(/(?:[#?&])pnr=([^&]+)/i);
    return match ? match[1] : null;
  }
  if (typeof input === 'object') {
    const format = String(input.format || '').toLowerCase();
    if (format !== 'dvb') return null;
    const pnr = input.pnr !== undefined ? input.pnr : null;
    if (pnr !== null) return pnr;
    const addr = input.addr || input.url || '';
    if (typeof addr === 'string') {
      if (adapterId && !addr.startsWith(String(adapterId))) return null;
      const match = addr.match(/(?:[#?&])pnr=([^&]+)/i);
      return match ? match[1] : null;
    }
  }
  return null;
}

function collectExistingDvbPnrs(adapterId) {
  const pnrs = new Set();
  (state.streams || []).forEach((stream) => {
    const inputs = (stream.config && Array.isArray(stream.config.input)) ? stream.config.input : [];
    inputs.forEach((input) => {
      const pnr = extractDvbPnr(input, adapterId);
      if (pnr !== null && pnr !== undefined && pnr !== '') {
        pnrs.add(String(pnr));
      }
    });
  });
  return pnrs;
}

async function createStreamsFromScan(adapterId) {
  if (!adapterId) return;
  const list = Array.from(document.querySelectorAll('.scan-channel-checkbox'))
    .filter((item) => item.checked)
    .map((item) => item.dataset.pnr)
    .filter(Boolean);
  if (!list.length) {
    const message = 'Select at least one channel';
    setStatus(message);
    if (elements.adapterScanStatus) elements.adapterScanStatus.textContent = message;
    return;
  }
  const existingPnrs = collectExistingDvbPnrs(adapterId);
  const existingIds = new Set((state.streams || []).map((item) => item.id));
  const results = [];
  const failures = [];
  const skipped = [];
  const channels = (state.adapterScanResults && state.adapterScanResults.channels) || [];
  for (const pnr of list) {
    if (existingPnrs.has(String(pnr))) {
      skipped.push(String(pnr));
      continue;
    }
    const channel = channels.find((item) => String(item.pnr) === String(pnr));
    const name = channel && channel.name ? channel.name : `PNR ${pnr}`;
    let id = slugifyStreamId(name);
    if (!id || id === '') {
      id = `dvb_${adapterId}_${pnr}`;
    }
    let unique = id;
    let counter = 2;
    while (existingIds.has(unique)) {
      unique = `${id}_${counter}`;
      counter += 1;
    }
    existingIds.add(unique);
    const payload = {
      id: unique,
      enabled: true,
      config: {
        name,
        type: 'spts',
        input: [`dvb://${adapterId}#pnr=${pnr}`],
        output: [],
      },
    };
    try {
      await apiJson('/api/v1/streams', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      results.push(unique);
    } catch (err) {
      failures.push({
        pnr,
        message: err && err.message ? err.message : 'create failed',
      });
    }
  }
  try {
    await loadStreams();
  } catch (err) {
    const message = err && err.network
      ? 'Streams created, but refresh failed. Reload later.'
      : (err && err.message ? err.message : 'Streams created, but refresh failed');
    setStatus(message);
    if (elements.adapterScanStatus) elements.adapterScanStatus.textContent = message;
    closeAdapterScanModal();
    setView('streams');
    return;
  }
  const skippedLabel = skipped.length ? `, skipped ${skipped.length} existing (PNR: ${skipped.slice(0, 10).join(', ')}${skipped.length > 10 ? '…' : ''})` : '';
  let message = '';
  if (failures.length) {
    console.warn('Scan add failures', failures);
    message = `Created ${results.length} stream(s)${skippedLabel}, ${failures.length} failed`;
  } else if (results.length === 0 && skipped.length) {
    message = `All selected channels already exist (PNR: ${skipped.slice(0, 10).join(', ')}${skipped.length > 10 ? '…' : ''})`;
  } else {
    message = `Created ${results.length} stream(s)${skippedLabel}`;
  }
  if (elements.adapterScanStatus) elements.adapterScanStatus.textContent = message;
  closeAdapterScanModal();
  setView('dashboard');
  showDashboardNotice(message, 10000);
  setStatus(message, 'sticky');
  setTimeout(() => setStatus(''), 6000);
}

const FE_HAS_SIGNAL = 1;
const FE_HAS_CARRIER = 2;
const FE_HAS_VITERBI = 4;
const FE_HAS_SYNC = 8;
const FE_HAS_LOCK = 16;

function hasStatusBit(status, bit) {
  return (Number(status) & bit) === bit;
}

function toPercent(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) return 0;
  return Math.max(0, Math.min(100, Math.round((num * 100) / 0xFFFF)));
}

function formatRawSignal(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '-';
  return `${Math.round(num)} dBm`;
}

function formatRawSnr(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '-';
  return `${(num / 10).toFixed(1)} dB`;
}

function formatPercent(value) {
  return `${toPercent(value)}%`;
}

function formatStatusFlags(status) {
  if (!Number.isFinite(Number(status))) return '-----';
  const flags = [
    hasStatusBit(status, FE_HAS_SIGNAL) ? 'S' : '_',
    hasStatusBit(status, FE_HAS_CARRIER) ? 'C' : '_',
    hasStatusBit(status, FE_HAS_VITERBI) ? 'V' : '_',
    hasStatusBit(status, FE_HAS_SYNC) ? 'Y' : '_',
    hasStatusBit(status, FE_HAS_LOCK) ? 'L' : '_',
  ];
  return flags.join('');
}

function makeAdapterMeter(label, percent, valueText) {
  const meter = document.createElement('div');
  meter.className = 'adapter-meter';

  const title = document.createElement('div');
  title.className = 'adapter-meter-label';
  title.textContent = label;

  const track = document.createElement('div');
  track.className = 'adapter-meter-track';

  const fill = document.createElement('div');
  fill.className = 'adapter-meter-fill';
  fill.style.width = `${Math.max(0, Math.min(100, percent || 0))}%`;

  const value = document.createElement('div');
  value.className = 'adapter-meter-value';
  value.textContent = valueText;

  track.appendChild(fill);
  meter.appendChild(title);
  meter.appendChild(track);
  meter.appendChild(value);
  return meter;
}

function renderAdapterList() {
  if (!elements.adapterList) return;
  const adapters = state.adapters || [];
  const activeId = state.adapterEditing && state.adapterEditing.adapter ? state.adapterEditing.adapter.id : null;

  elements.adapterList.innerHTML = '';
  if (elements.adapterListEmpty) {
    elements.adapterListEmpty.style.display = adapters.length ? 'none' : 'block';
  }

  adapters.forEach((adapter) => {
    const config = adapter.config || {};
    const statusData = getAdapterStatusEntry(adapter.id, config) || {};
    const rawSignal = config.raw_signal === true;
    const signalPercent = rawSignal ? 0 : toPercent(statusData.signal);
    const snrPercent = rawSignal ? 0 : toPercent(statusData.snr);
    const hasStatus = statusData && statusData.updated_at;
    const statusFlags = formatStatusFlags(statusData.status);
    const isLocked = hasStatus && hasStatusBit(statusData.status, FE_HAS_LOCK);

    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'adapter-card';
    if (adapter.enabled === false) {
      card.classList.add('disabled');
    }
    if (adapter.id === activeId) {
      card.classList.add('active');
    }

    const title = document.createElement('div');
    title.className = 'adapter-card-title';
    title.textContent = config.name || adapter.id;

    const meta = document.createElement('div');
    meta.className = 'adapter-card-meta';
    meta.textContent = adapterSummary(adapter) || 'No config';

    const status = document.createElement('div');
    status.className = 'adapter-card-status';
    const dot = document.createElement('span');
    dot.className = `adapter-status-dot${adapter.enabled === false ? ' off' : ''}`;
    const label = document.createElement('span');
    label.textContent = adapter.enabled === false ? 'Disabled' : 'Enabled';
    status.appendChild(dot);
    status.appendChild(label);
    if (config.adapter !== undefined && state.dvbAdaptersLoaded) {
      const hw = findDvbAdapter(config.adapter, config.device);
      const hwStatus = formatDvbStatus(hw);
      const badge = document.createElement('span');
      badge.className = `adapter-badge ${hwStatus.className}`;
      badge.textContent = hwStatus.label;
      status.appendChild(badge);
    }

    const metrics = document.createElement('div');
    metrics.className = 'adapter-card-metrics';
    if (statusData && statusData.error) {
      const error = document.createElement('div');
      error.className = 'adapter-card-meta warn';
      error.textContent = statusData.error;
      metrics.appendChild(error);
    } else {
      metrics.appendChild(
        makeAdapterMeter(
          'S',
          signalPercent,
          rawSignal ? formatRawSignal(statusData.signal) : formatPercent(statusData.signal)
        )
      );
      metrics.appendChild(
        makeAdapterMeter(
          'Q',
          snrPercent,
          rawSignal ? formatRawSnr(statusData.snr) : formatPercent(statusData.snr)
        )
      );
    }

    const detail = document.createElement('div');
    detail.className = 'adapter-card-meta';
    const ber = statusData.ber !== undefined ? statusData.ber : '-';
    const unc = statusData.unc !== undefined ? statusData.unc : '-';
    if (statusData && statusData.error) {
      detail.textContent = statusData.error;
    } else if (hasStatus) {
      detail.textContent = `Status ${statusFlags} · ${isLocked ? 'LOCK' : 'NO LOCK'} · BER ${ber} · UNC ${unc}`;
    } else {
      detail.textContent = 'No signal data yet';
    }

    card.appendChild(title);
    card.appendChild(meta);
    card.appendChild(status);
    card.appendChild(metrics);
    card.appendChild(detail);
    card.addEventListener('click', () => openAdapterEditor(adapter, false));

    elements.adapterList.appendChild(card);
  });
}

function renderAdapterSelect(selectedId, isNew) {
  if (!elements.adapterSelect) return;
  elements.adapterSelect.innerHTML = '';
  const empty = document.createElement('option');
  empty.value = '';
  empty.textContent = 'New adapter';
  elements.adapterSelect.appendChild(empty);
  state.adapters.forEach((adapter) => {
    const option = document.createElement('option');
    option.value = adapter.id;
    option.textContent = adapter.id;
    elements.adapterSelect.appendChild(option);
  });
  elements.adapterSelect.value = isNew ? '' : (selectedId || '');
}

function openAdapterEditor(adapter, isNew) {
  const config = (adapter && adapter.config) || {};
  const id = adapter ? adapter.id : '';

  state.adapterEditing = { adapter, isNew };
  renderAdapterSelect(id, isNew);
  elements.adapterError.textContent = '';
  elements.adapterEnabled.checked = !adapter || adapter.enabled !== false;
  elements.adapterId.value = id || '';
  elements.adapterId.disabled = false;
  renderAdapterHardwareSelects(
    config.adapter !== undefined ? config.adapter : '',
    config.device !== undefined ? config.device : 0,
  );
  elements.adapterType.value = config.type || 'S2';
  elements.adapterModulation.value = config.modulation || 'AUTO';
  elements.adapterCaPmtDelay.value = config.ca_pmt_delay !== undefined ? config.ca_pmt_delay : '';
  elements.adapterBufferSize.value = config.buffer_size !== undefined ? config.buffer_size : '';
  elements.adapterBudget.checked = config.budget === true;
  elements.adapterRawSignal.checked = config.raw_signal === true;
  elements.adapterLogSignal.checked = config.log_signal === true;
  elements.adapterStreamId.value = config.stream_id !== undefined ? config.stream_id : '';

  const fallbackTp = (config.frequency && config.polarization && config.symbolrate)
    ? `${config.frequency}:${config.polarization}:${config.symbolrate}`
    : '';
  const fallbackLnb = (config.lof1 && config.lof2 && config.slof)
    ? `${config.lof1}:${config.lof2}:${config.slof}`
    : '';
  elements.adapterTp.value = config.tp || fallbackTp;
  elements.adapterLnb.value = config.lnb || fallbackLnb;
  elements.adapterLnbSharing.checked = config.lnb_sharing === true;
  elements.adapterDiseqc.value = config.diseqc !== undefined ? config.diseqc : '';
  elements.adapterTone.checked = config.tone === true;
  elements.adapterRolloff.value = config.rolloff || 'AUTO';
  elements.adapterUniScr.value = config.uni_scr !== undefined ? config.uni_scr : '';
  elements.adapterUniFrequency.value = config.uni_frequency !== undefined ? config.uni_frequency : '';

  elements.adapterTFrequency.value = config.frequency !== undefined ? config.frequency : '';
  elements.adapterBandwidth.value = config.bandwidth || 'AUTO';
  elements.adapterGuardinterval.value = config.guardinterval || 'AUTO';
  elements.adapterTransmitmode.value = config.transmitmode || 'AUTO';
  elements.adapterHierarchy.value = config.hierarchy || 'AUTO';

  elements.adapterCFrequency.value = config.frequency !== undefined ? config.frequency : '';
  elements.adapterCSymbolrate.value = config.symbolrate !== undefined ? config.symbolrate : '';

  elements.adapterAtscFrequency.value = config.frequency !== undefined ? config.frequency : '';

  setAdapterGroup(elements.adapterType.value);
  renderDvbDetectedSelect();
  updateAdapterBusyWarningFromFields();
  updateAdapterScanAvailability();
  if (elements.adapterDelete) {
    elements.adapterDelete.style.visibility = isNew ? 'hidden' : 'visible';
  }
  if (elements.adapterTitle) {
    elements.adapterTitle.textContent = isNew ? 'New adapter' : `Adapter: ${id}`;
  }
  setAdapterEditorActive(true);
  setTab('general', 'adapter-editor');
  renderAdapterList();
}

function closeAdapterEditor() {
  state.adapterEditing = null;
  if (elements.adapterTitle) {
    elements.adapterTitle.textContent = 'Adapter settings';
  }
  setAdapterEditorActive(false);
  renderAdapterList();
}

function readAdapterForm() {
  const id = elements.adapterId.value.trim();
  if (!id) throw new Error('Adapter id is required');
  const adapterIndex = toNumber(elements.adapterIndex.value);
  if (adapterIndex === undefined) throw new Error('Adapter number is required');

  const config = {
    id,
    adapter: adapterIndex,
    device: toNumber(elements.adapterDevice.value) || 0,
    type: elements.adapterType.value,
    ca_pmt_delay: toNumber(elements.adapterCaPmtDelay.value),
    buffer_size: toNumber(elements.adapterBufferSize.value),
    budget: elements.adapterBudget.checked || undefined,
    raw_signal: elements.adapterRawSignal.checked || undefined,
    log_signal: elements.adapterLogSignal.checked || undefined,
    stream_id: toNumber(elements.adapterStreamId.value),
  };

  const type = (config.type || '').toUpperCase();
  const modulation = elements.adapterModulation.value;
  if (type.startsWith('S')) {
    if (modulation && modulation.toUpperCase() !== 'AUTO') {
      config.modulation = modulation;
    }
  } else if (modulation) {
    config.modulation = modulation;
  }
  if (type.startsWith('S')) {
    config.tp = elements.adapterTp.value.trim();
    const lnbValue = elements.adapterLnb.value.trim();
    if (lnbValue) {
      if (!/^\d+:\d+:\d+$/.test(lnbValue)) {
        throw new Error('LNB must be in format LOF1:LOF2:SLOF (e.g. 9750:10600:11700)');
      }
      config.lnb = lnbValue;
    }
    config.lnb_sharing = elements.adapterLnbSharing.checked || undefined;
    config.diseqc = toNumber(elements.adapterDiseqc.value);
    config.tone = elements.adapterTone.checked || undefined;
    config.rolloff = elements.adapterRolloff.value;
    config.uni_scr = toNumber(elements.adapterUniScr.value);
    config.uni_frequency = toNumber(elements.adapterUniFrequency.value);
  } else if (type.startsWith('T')) {
    config.frequency = toNumber(elements.adapterTFrequency.value);
    config.bandwidth = elements.adapterBandwidth.value;
    config.guardinterval = elements.adapterGuardinterval.value;
    config.transmitmode = elements.adapterTransmitmode.value;
    config.hierarchy = elements.adapterHierarchy.value;
  } else if (type.startsWith('C')) {
    config.frequency = toNumber(elements.adapterCFrequency.value);
    config.symbolrate = toNumber(elements.adapterCSymbolrate.value);
  } else if (type === 'ATSC') {
    config.frequency = toNumber(elements.adapterAtscFrequency.value);
  }

  return { id, enabled: elements.adapterEnabled.checked, config };
}

async function updateStreamsForAdapterRename(oldId, newId) {
  if (!oldId || !newId || oldId === newId) return;
  const streams = await apiJson('/api/v1/streams');
  const list = Array.isArray(streams) ? streams : [];
  for (const stream of list) {
    const config = stream.config || {};
    const inputs = Array.isArray(config.input) ? config.input : [];
    let changed = false;
    const updatedInputs = inputs.map((input) => {
      if (typeof input === 'string') {
        const prefix = `dvb://${oldId}`;
        if (input.startsWith(prefix)) {
          changed = true;
          return `dvb://${newId}${input.slice(prefix.length)}`;
        }
        return input;
      }
      if (input && typeof input === 'object') {
        const format = String(input.format || '').toLowerCase();
        const dvbId = input.dvbId || input.dvb_id;
        if (format === 'dvb' && dvbId === oldId) {
          changed = true;
          const next = { ...input };
          if (next.dvbId !== undefined) next.dvbId = newId;
          if (next.dvb_id !== undefined) next.dvb_id = newId;
          return next;
        }
      }
      return input;
    });
    if (!changed) continue;
    const payload = {
      id: stream.id,
      enabled: stream.enabled !== false,
      config: { ...config, input: updatedInputs },
    };
    await apiJson(`/api/v1/streams/${stream.id}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }
}

async function loadAdapters() {
  try {
    const data = await apiJson('/api/v1/adapters');
    state.adapters = Array.isArray(data) ? data : [];
  } catch (err) {
    state.adapters = [];
  }
  renderAdapterList();
}

async function loadAdapterStatus() {
  try {
    const data = await apiJson('/api/v1/adapter-status');
    state.adapterStatus = data || {};
  } catch (err) {
    state.adapterStatus = {};
  }
  renderAdapterList();
  updateAdapterScanAvailability();
}

async function loadDvbAdapters() {
  try {
    const data = await apiJson('/api/v1/dvb-adapters');
    state.dvbAdapters = Array.isArray(data) ? data : [];
    state.dvbAdaptersLoaded = true;
  } catch (err) {
    state.dvbAdapters = [];
    state.dvbAdaptersLoaded = false;
  }
  renderAdapterList();
  renderDvbDetectedSelect();
}

function startAdapterPolling() {
  if (state.adapterTimer) {
    clearInterval(state.adapterTimer);
  }
  state.adapterTimer = setInterval(loadAdapterStatus, POLL_ADAPTER_MS);
  loadAdapterStatus();
}

function stopAdapterPolling() {
  if (state.adapterTimer) {
    clearInterval(state.adapterTimer);
    state.adapterTimer = null;
  }
}

function startDvbPolling() {
  if (state.currentView !== 'adapters') return;
  if (state.dvbTimer) {
    clearInterval(state.dvbTimer);
  }
  state.dvbTimer = setInterval(() => {
    if (state.currentView !== 'adapters' || document.hidden) return;
    loadDvbAdapters().catch(() => {});
  }, 3600 * 1000);
}

function stopDvbPolling() {
  if (state.dvbTimer) {
    clearInterval(state.dvbTimer);
    state.dvbTimer = null;
  }
}

async function saveAdapter() {
  const payload = readAdapterForm();
  const isNew = state.adapterEditing && state.adapterEditing.isNew;
  const originalId = state.adapterEditing && state.adapterEditing.adapter && state.adapterEditing.adapter.id;
  if (!isNew && originalId && payload.id !== originalId) {
    const confirmed = window.confirm(`Rename adapter ${originalId} to ${payload.id}?`);
    if (!confirmed) return;
    await apiJson('/api/v1/adapters', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    await apiJson(`/api/v1/adapters/${originalId}`, { method: 'DELETE' });
    await updateStreamsForAdapterRename(originalId, payload.id);
    await loadAdapters();
    await loadStreams();
    setStatus('Adapter renamed');
    const updated = state.adapters.find((item) => item.id === payload.id) || payload;
    openAdapterEditor(updated, false);
    return;
  }
  if (isNew) {
    await apiJson('/api/v1/adapters', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  } else {
    await apiJson(`/api/v1/adapters/${payload.id}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }
  await loadAdapters();
  setStatus('Adapter saved');
  const updated = state.adapters.find((item) => item.id === payload.id) || payload;
  openAdapterEditor(updated, false);
}

async function deleteAdapter(adapter) {
  const target = adapter || (state.adapterEditing && state.adapterEditing.adapter);
  if (!target || !target.id) return;
  const confirmed = window.confirm(`Delete adapter ${target.id}?`);
  if (!confirmed) return;
  await apiJson(`/api/v1/adapters/${target.id}`, { method: 'DELETE' });
  await loadAdapters();
  setStatus('Adapter deleted');
  closeAdapterEditor();
}

function clearSplitterEditor() {
  state.splitterEditing = null;
  state.splitterEditingNew = false;
  state.splitterDirty = false;
  state.splitterLinks = [];
  state.splitterAllow = [];
  if (elements.splitterTitle) {
    elements.splitterTitle.textContent = 'Splitter settings';
  }
  if (elements.splitterState) {
    elements.splitterState.textContent = 'Status: idle';
  }
  if (elements.splitterRuntime) {
    elements.splitterRuntime.textContent = 'Uptime: n/a • Restarts (10m): 0';
  }
  if (elements.splitterForm) {
    elements.splitterForm.reset();
  }
  if (elements.splitterLinkTable) {
    elements.splitterLinkTable.innerHTML = '';
  }
  if (elements.splitterAllowTable) {
    elements.splitterAllowTable.innerHTML = '';
  }
  if (elements.splitterLinkEmpty) {
    elements.splitterLinkEmpty.style.display = 'block';
  }
  if (elements.splitterAllowEmpty) {
    elements.splitterAllowEmpty.style.display = 'block';
  }
  if (elements.splitterError) {
    elements.splitterError.textContent = '';
  }
  if (elements.splitterPreset) {
    elements.splitterPreset.value = '';
  }
  updateSplitterActionState();
}

function openSplitterEditor(splitter, isNew) {
  if (!splitter) {
    clearSplitterEditor();
    return;
  }
  state.splitterEditing = splitter;
  state.splitterEditingNew = !!isNew;
  state.splitterDirty = false;
  if (elements.splitterError) {
    elements.splitterError.textContent = '';
  }
  if (elements.splitterPreset) {
    elements.splitterPreset.value = '';
  }
  if (isNew) {
    state.splitterLinks = [];
    state.splitterAllow = [];
  }

  elements.splitterTitle.textContent = isNew ? 'New splitter' : `Splitter: ${splitter.id}`;
  elements.splitterEnabled.checked = splitter.enable !== false;
  elements.splitterId.value = splitter.id || '';
  elements.splitterId.disabled = !isNew;
  elements.splitterName.value = splitter.name || '';
  elements.splitterPort.value = splitter.port || '';
  elements.splitterInInterface.value = splitter.in_interface || '';
  elements.splitterOutInterface.value = splitter.out_interface || '';
  elements.splitterLogtype.value = splitter.logtype || '';
  elements.splitterLogpath.value = splitter.logpath || '';
  elements.splitterConfigPath.value = splitter.config_path || '';
  elements.splitterUrlTemplate.textContent = `http://<server_ip>:${splitter.port || '<port>'}/path`;

  renderSplitterDetail();
}

function renderSplitterList() {
  const list = Array.isArray(state.splitters) ? state.splitters : [];
  elements.splitterList.innerHTML = '';
  if (list.length === 0) {
    elements.splitterListEmpty.style.display = 'block';
    const keepDraft = state.splitterEditing && (state.splitterEditingNew || state.splitterDirty);
    if (!keepDraft) {
      clearSplitterEditor();
    } else {
      updateSplitterActionState();
    }
    return;
  }
  elements.splitterListEmpty.style.display = 'none';

  list.forEach((splitter) => {
    const status = getSplitterStatus(splitter.id) || {};
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'splitter-card';
    if (state.splitterEditing && state.splitterEditing.id === splitter.id) {
      card.classList.add('active');
    }

    const left = document.createElement('div');
    left.className = 'buffer-card-main';
    const name = document.createElement('div');
    name.className = 'splitter-name';
    name.textContent = splitter.name || splitter.id;
    const meta = document.createElement('div');
    meta.className = 'splitter-meta';
    let okCount = 0;
    let totalCount = 0;
    if (status && Array.isArray(status.links)) {
      totalCount = status.links.length;
      status.links.forEach((link) => {
        if (link && link.state === 'OK') okCount += 1;
      });
    }
    const linksCount = splitter.links_count || totalCount || 0;
    const healthSummary = totalCount > 0 ? ` • OK ${okCount} • DOWN ${totalCount - okCount}` : '';
    const hasStatus = status && status.id;
    const uptimeValue = hasStatus && Number.isFinite(status.uptime_sec)
      ? formatUptime(status.uptime_sec)
      : 'n/a';
    const restartCount = hasStatus && Number.isFinite(status.restart_count_10min)
      ? status.restart_count_10min
      : 0;
    const runtimeSummary = hasStatus ? ` • Uptime ${uptimeValue} • Restarts ${restartCount}/10m` : '';
    meta.textContent = `Port ${splitter.port || 'n/a'} • Links ${linksCount}${healthSummary}${runtimeSummary}`;
    left.appendChild(name);
    left.appendChild(meta);

    const right = document.createElement('div');
    const stateLabel = document.createElement('div');
    stateLabel.className = 'splitter-state';
    const stateValue = status.state || (splitter.enable === false ? 'STOPPED' : 'UNKNOWN');
    stateLabel.textContent = stateValue;
    if (status.running) {
      stateLabel.classList.add('ok');
    } else if (stateValue === 'ERROR' || stateValue === 'DOWN') {
      stateLabel.classList.add('down');
    }
    right.appendChild(stateLabel);

    card.appendChild(left);
    card.appendChild(right);

    card.addEventListener('click', () => {
      loadSplitterDetail(splitter.id);
    });
    elements.splitterList.appendChild(card);
  });
}

function renderSplitterAllow() {
  const allow = Array.isArray(state.splitterAllow) ? state.splitterAllow : [];
  const table = elements.splitterAllowTable;
  table.innerHTML = '';

  if (!isSplitterSaved()) {
    elements.splitterAllowEmpty.style.display = 'block';
    return;
  }

  const header = document.createElement('div');
  header.className = 'table-row header';
  header.innerHTML = '<div>Type</div><div>Value</div><div></div>';
  table.appendChild(header);

  if (allow.length === 0) {
    elements.splitterAllowEmpty.style.display = 'block';
    const row = document.createElement('div');
    row.className = 'table-row';
    row.innerHTML = '<div>allow</div><div>0.0.0.0 (default)</div><div></div>';
    table.appendChild(row);
    return;
  }
  elements.splitterAllowEmpty.style.display = 'none';

  allow.forEach((rule) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.dataset.id = rule.id;
    row.innerHTML = `<div>${rule.kind}</div><div>${rule.value}</div>`;
    const actions = document.createElement('div');
    actions.className = 'splitter-actions';
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn ghost danger';
    remove.textContent = 'Delete';
    remove.dataset.action = 'allow-delete';
    remove.dataset.id = rule.id;
    actions.appendChild(remove);
    row.appendChild(actions);
    table.appendChild(row);
  });
}

function renderSplitterLinks() {
  const links = Array.isArray(state.splitterLinks) ? state.splitterLinks : [];
  const table = elements.splitterLinkTable;
  table.innerHTML = '';

  if (!isSplitterSaved()) {
    elements.splitterLinkEmpty.style.display = 'block';
    return;
  }

  const header = document.createElement('div');
  header.className = 'table-row header';
  header.innerHTML = '<div>Input URL</div><div>State</div><div>Output URL</div><div>Last OK</div><div>Last error</div><div></div>';
  table.appendChild(header);

  if (links.length === 0) {
    elements.splitterLinkEmpty.style.display = 'block';
    return;
  }
  elements.splitterLinkEmpty.style.display = 'none';

  const status = getSplitterStatus(state.splitterEditing && state.splitterEditing.id);
  const statusMap = {};
  if (status && Array.isArray(status.links)) {
    status.links.forEach((item) => {
      statusMap[item.link_id] = item;
    });
  }

  links.forEach((link) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.dataset.id = link.id;

    const linkStatus = statusMap[link.id] || {};
    const resourcePath = linkStatus.resource_path || getResourcePath(link.url);
    const outputUrl = linkStatus.output_url || buildSplitterOutputUrl(state.splitterEditing.port, resourcePath);
    const stateLabel = linkStatus.state || 'DOWN';
    const lastOk = formatTimestamp(linkStatus.last_ok_ts);
    const lastError = linkStatus.last_error || 'n/a';

    row.innerHTML = `<div>${link.url || ''}</div><div>${stateLabel}</div><div>${outputUrl}</div>` +
      `<div>${lastOk}</div><div>${lastError}</div>`;

    const actions = document.createElement('div');
    actions.className = 'splitter-actions';

    const copy = document.createElement('button');
    copy.type = 'button';
    copy.className = 'btn ghost';
    copy.textContent = 'Copy';
    copy.addEventListener('click', (event) => {
      event.stopPropagation();
      copyText(outputUrl);
    });

    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'btn ghost';
    edit.textContent = 'Edit';
    edit.addEventListener('click', (event) => {
      event.stopPropagation();
      openSplitterLinkModal(link);
    });

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn ghost danger';
    remove.textContent = 'Delete';
    remove.addEventListener('click', async (event) => {
      event.stopPropagation();
      await deleteSplitterLink(link);
    });

    actions.appendChild(copy);
    actions.appendChild(edit);
    actions.appendChild(remove);
    row.appendChild(actions);
    table.appendChild(row);
  });
}

function renderSplitterDetail() {
  if (!state.splitterEditing) {
    clearSplitterEditor();
    return;
  }
  const splitter = state.splitterEditing;
  elements.splitterEnabled.checked = splitter.enable !== false;
  elements.splitterId.value = splitter.id || '';
  elements.splitterId.disabled = !state.splitterEditingNew;
  elements.splitterName.value = splitter.name || '';
  elements.splitterPort.value = splitter.port || '';
  elements.splitterInInterface.value = splitter.in_interface || '';
  elements.splitterOutInterface.value = splitter.out_interface || '';
  elements.splitterLogtype.value = splitter.logtype || '';
  elements.splitterLogpath.value = splitter.logpath || '';
  elements.splitterConfigPath.value = splitter.config_path || '';
  elements.splitterUrlTemplate.textContent = `http://<server_ip>:${splitter.port || '<port>'}/path`;
  const status = getSplitterStatus(state.splitterEditing.id);
  if (status) {
    const stateText = status.running ? 'running' : 'stopped';
    const errorText = status.last_error ? ` • ${status.last_error}` : '';
    elements.splitterState.textContent = `Status: ${status.state || stateText}${errorText}`;
  } else {
    elements.splitterState.textContent = 'Status: unknown';
  }
  if (elements.splitterRuntime) {
    const uptimeValue = status && Number.isFinite(status.uptime_sec)
      ? formatUptime(status.uptime_sec)
      : 'n/a';
    const restartCount = status && Number.isFinite(status.restart_count_10min)
      ? status.restart_count_10min
      : 0;
    elements.splitterRuntime.textContent = `Uptime: ${uptimeValue} • Restarts (10m): ${restartCount}`;
  }
  renderSplitterAllow();
  renderSplitterLinks();
  updateSplitterActionState();
}

async function loadSplitters() {
  try {
    const [list, status] = await Promise.all([
      apiJson('/api/v1/splitters'),
      apiJson('/api/v1/splitter-status'),
    ]);
    state.splitters = Array.isArray(list) ? list : [];
    const statusMap = {};
    if (Array.isArray(status)) {
      status.forEach((item) => {
        if (item && item.id) {
          statusMap[item.id] = item;
        }
      });
    } else if (status && typeof status === 'object') {
      Object.keys(status).forEach((key) => {
        statusMap[key] = status[key];
      });
    }
    state.splitterStatus = statusMap;
  } catch (err) {
    state.splitters = [];
    state.splitterStatus = {};
  }

  renderSplitterList();

  const holdEditing = state.splitterEditing && (state.splitterEditingNew || state.splitterDirty);
  if (state.splitterEditing && state.splitterEditing.id && !holdEditing) {
    await loadSplitterDetail(state.splitterEditing.id, true);
  } else if (state.splitters.length > 0) {
    await loadSplitterDetail(state.splitters[0].id, true);
  }
}

async function loadSplitterDetail(id, silent) {
  if (!id) {
    clearSplitterEditor();
    return;
  }
  if (silent && (state.splitterEditingNew || state.splitterDirty)) {
    return;
  }
  try {
    const [row, links, allow, status] = await Promise.all([
      apiJson(`/api/v1/splitters/${id}`),
      apiJson(`/api/v1/splitters/${id}/links`),
      apiJson(`/api/v1/splitters/${id}/allow`),
      apiJson(`/api/v1/splitter-status/${id}`),
    ]);
    if (row) {
      state.splitterEditing = row;
      state.splitterEditingNew = false;
      state.splitterDirty = false;
    }
    state.splitterLinks = Array.isArray(links) ? links : [];
    state.splitterAllow = Array.isArray(allow) ? allow : [];
    if (status) {
      state.splitterStatus = { ...state.splitterStatus, [id]: status };
    }
    if (!silent) {
      openSplitterEditor(row, false);
    } else {
      renderSplitterDetail();
    }
  } catch (err) {
    if (!silent) {
      setStatus('Failed to load splitter details');
    }
  }
}

async function saveSplitter() {
  const id = elements.splitterId.value.trim();
  if (!id) throw new Error('Splitter id is required');
  const port = toNumber(elements.splitterPort.value);
  if (!port) throw new Error('Port is required');
  const payload = {
    id,
    name: elements.splitterName.value.trim(),
    enable: elements.splitterEnabled.checked,
    port,
    in_interface: elements.splitterInInterface.value.trim(),
    out_interface: elements.splitterOutInterface.value.trim(),
    logtype: elements.splitterLogtype.value.trim(),
    logpath: elements.splitterLogpath.value.trim(),
    config_path: elements.splitterConfigPath.value.trim(),
  };

  let saved = null;
  if (state.splitterEditingNew) {
    saved = await apiJson('/api/v1/splitters', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  } else {
    saved = await apiJson(`/api/v1/splitters/${encodeURIComponent(id)}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }
  state.splitterEditingNew = false;
  state.splitterDirty = false;
  if (saved && saved.id) {
    state.splitterEditing = { ...state.splitterEditing, ...payload, id: saved.id };
  } else {
    state.splitterEditing = { ...state.splitterEditing, ...payload };
  }
  renderSplitterDetail();
  await loadSplitters();
  setStatus('Splitter saved');
}

async function startSplitterAction(action) {
  if (!isSplitterSaved()) {
    setStatus('Save the instance first');
    return;
  }
  await apiJson(`/api/v1/splitters/${encodeURIComponent(state.splitterEditing.id)}/${action}`, {
    method: 'POST',
  });
  await loadSplitters();
  setStatus(`Splitter ${action} requested`);
}

async function openSplitterConfigModal() {
  if (!isSplitterSaved()) {
    setStatus('Save the instance first');
    return;
  }
  if (elements.splitterConfigPreview) {
    elements.splitterConfigPreview.textContent = 'Loading...';
  }
  if (elements.splitterConfigError) {
    elements.splitterConfigError.textContent = '';
  }
  if (elements.splitterConfigOverlay) {
    setOverlay(elements.splitterConfigOverlay, true);
  }
  try {
    const xml = await apiText(`/api/v1/splitters/${encodeURIComponent(state.splitterEditing.id)}/config`);
    if (elements.splitterConfigPreview) {
      elements.splitterConfigPreview.textContent = xml || '';
    }
  } catch (err) {
    if (elements.splitterConfigPreview) {
      elements.splitterConfigPreview.textContent = '';
    }
    if (elements.splitterConfigError) {
      elements.splitterConfigError.textContent = err.message || 'Failed to load config';
    }
  }
}

function closeSplitterConfigModal() {
  if (elements.splitterConfigOverlay) {
    setOverlay(elements.splitterConfigOverlay, false);
  }
}

function openSplitterLinkModal(link) {
  if (!isSplitterSaved()) {
    setStatus('Save the instance first');
    return;
  }
  state.splitterLinkEditing = link || null;
  elements.splitterLinkError.textContent = '';
  elements.splitterLinkEnabled.checked = !link || link.enable !== false;
  elements.splitterLinkUrl.value = (link && link.url) || '';
  elements.splitterLinkBandwidth.value = (link && link.bandwidth) || '';
  elements.splitterLinkBuffering.value = (link && link.buffering) || '';
  setOverlay(elements.splitterLinkOverlay, true);
}

function closeSplitterLinkModal() {
  state.splitterLinkEditing = null;
  setOverlay(elements.splitterLinkOverlay, false);
}

async function saveSplitterLink() {
  if (!isSplitterSaved()) {
    throw new Error('Save the instance first');
  }
  const payload = {
    enable: elements.splitterLinkEnabled.checked,
    url: elements.splitterLinkUrl.value.trim(),
    bandwidth: toNumber(elements.splitterLinkBandwidth.value),
    buffering: toNumber(elements.splitterLinkBuffering.value),
  };
  if (!payload.url) {
    throw new Error('Link URL is required');
  }
  const splitterId = encodeURIComponent(state.splitterEditing.id);
  if (state.splitterLinkEditing && state.splitterLinkEditing.id) {
    await apiJson(`/api/v1/splitters/${splitterId}/links/${encodeURIComponent(state.splitterLinkEditing.id)}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  } else {
    await apiJson(`/api/v1/splitters/${splitterId}/links`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }
  closeSplitterLinkModal();
  await loadSplitterDetail(state.splitterEditing.id, true);
  setStatus('Link saved');
}

async function deleteSplitterLink(link) {
  if (!state.splitterEditing || !state.splitterEditing.id || !link) return;
  const confirmed = window.confirm(`Delete link ${link.id}?`);
  if (!confirmed) return;
  await apiJson(`/api/v1/splitters/${encodeURIComponent(state.splitterEditing.id)}/links/${encodeURIComponent(link.id)}`, {
    method: 'DELETE',
  });
  await loadSplitterDetail(state.splitterEditing.id, true);
  setStatus('Link deleted');
}

function openSplitterAllowModal() {
  if (!isSplitterSaved()) {
    setStatus('Save the instance first');
    return;
  }
  state.splitterAllowEditing = null;
  elements.splitterAllowError.textContent = '';
  elements.splitterAllowKind.value = 'allow';
  elements.splitterAllowValue.value = '';
  setOverlay(elements.splitterAllowOverlay, true);
}

function closeSplitterAllowModal() {
  state.splitterAllowEditing = null;
  setOverlay(elements.splitterAllowOverlay, false);
}

async function saveSplitterAllow() {
  if (!isSplitterSaved()) {
    throw new Error('Save the instance first');
  }
  const payload = {
    kind: elements.splitterAllowKind.value,
    value: elements.splitterAllowValue.value.trim(),
  };
  if (!payload.value) {
    throw new Error('Allow value is required');
  }
  if (payload.kind === 'allowRange' && !isValidAllowRange(payload.value)) {
    throw new Error('allowRange must be CIDR or IP range');
  }
  await apiJson(`/api/v1/splitters/${encodeURIComponent(state.splitterEditing.id)}/allow`, {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  closeSplitterAllowModal();
  await loadSplitterDetail(state.splitterEditing.id, true);
  setStatus('Allow rule saved');
}

async function deleteSplitterAllow(ruleId) {
  if (!state.splitterEditing || !state.splitterEditing.id || !ruleId) return;
  const confirmed = window.confirm('Delete allow rule?');
  if (!confirmed) return;
  await apiJson(`/api/v1/splitters/${encodeURIComponent(state.splitterEditing.id)}/allow/${encodeURIComponent(ruleId)}`, {
    method: 'DELETE',
  });
  await loadSplitterDetail(state.splitterEditing.id, true);
  setStatus('Allow rule deleted');
}

function startSplitterPolling() {
  if (state.splitterTimer) {
    clearInterval(state.splitterTimer);
  }
  state.splitterTimer = setInterval(loadSplitters, POLL_SPLITTER_MS);
  loadSplitters();
}

function stopSplitterPolling() {
  if (state.splitterTimer) {
    clearInterval(state.splitterTimer);
    state.splitterTimer = null;
  }
}

function isSplitterSaved() {
  return !!(state.splitterEditing && state.splitterEditing.id && !state.splitterEditingNew);
}

function updateSplitterActionState() {
  const saved = isSplitterSaved();
  const hasEditor = !!state.splitterEditing;
  const disabled = !saved;
  const hint = saved ? '' : 'Save the instance first';
  if (elements.splitterPreset) {
    elements.splitterPreset.disabled = !hasEditor;
  }
  if (elements.splitterPresetApply) {
    elements.splitterPresetApply.disabled = !hasEditor;
  }
  const actionButtons = [
    elements.splitterStart,
    elements.splitterStop,
    elements.splitterRestart,
    elements.splitterApply,
    elements.splitterConfig,
    elements.splitterLinkNew,
    elements.splitterAllowNew,
  ];
  actionButtons.forEach((button) => {
    if (!button) return;
    button.disabled = !hasEditor || disabled;
    button.title = saved ? '' : hint;
  });
  if (elements.splitterLinkEmpty) {
    elements.splitterLinkEmpty.textContent = saved ? 'No links yet.' : 'Save the instance first.';
  }
  if (elements.splitterAllowEmpty) {
    elements.splitterAllowEmpty.textContent = saved ? 'No rules (defaults to allow 0.0.0.0).' : 'Save the instance first.';
  }
}

const SPLITTER_PRESETS = {
  basic: {
    port: 8090,
    logtype: '1',
    use_config_path: true,
  },
  file_log: {
    port: 8090,
    logtype: '2',
    use_config_path: true,
    logpath_template: '/var/log/hlssplitter/{id}.log',
  },
  syslog: {
    port: 8090,
    logtype: '4',
    use_config_path: true,
  },
};

function splitterTemplateId() {
  return elements.splitterId.value.trim() || 'splitter_main';
}

function applySplitterPreset(key) {
  const preset = SPLITTER_PRESETS[key];
  if (!preset) return;
  const idValue = splitterTemplateId();
  if (preset.port) elements.splitterPort.value = preset.port;
  if (preset.logtype !== undefined) elements.splitterLogtype.value = preset.logtype;
  if (preset.logpath_template) {
    elements.splitterLogpath.value = preset.logpath_template.replace('{id}', idValue);
  } else if (preset.logtype === '1' || preset.logtype === '4') {
    elements.splitterLogpath.value = '';
  }
  if (preset.use_config_path) {
    elements.splitterConfigPath.value = `./data/splitters/${idValue}.xml`;
  }
  if (elements.splitterName && !elements.splitterName.value.trim()) {
    elements.splitterName.value = `HLSSplitter ${idValue}`;
  }
  markSplitterDirty();
}

function syncSplitterEditingFromForm() {
  if (!state.splitterEditing) return;
  const port = toNumber(elements.splitterPort.value);
  const payload = {
    id: elements.splitterId.value.trim(),
    name: elements.splitterName.value.trim(),
    enable: elements.splitterEnabled.checked,
    port: port || '',
    in_interface: elements.splitterInInterface.value.trim(),
    out_interface: elements.splitterOutInterface.value.trim(),
    logtype: elements.splitterLogtype.value.trim(),
    logpath: elements.splitterLogpath.value.trim(),
    config_path: elements.splitterConfigPath.value.trim(),
  };
  state.splitterEditing = { ...state.splitterEditing, ...payload };
  if (elements.splitterUrlTemplate) {
    elements.splitterUrlTemplate.textContent = `http://<server_ip>:${payload.port || '<port>'}/path`;
  }
}

function markSplitterDirty() {
  if (!state.splitterEditing) return;
  state.splitterDirty = true;
  if (elements.splitterError) {
    elements.splitterError.textContent = '';
  }
  syncSplitterEditingFromForm();
}

function isBufferSaved() {
  return !!(state.bufferEditing && state.bufferEditing.id && !state.bufferEditingNew);
}

function updateBufferActionState() {
  const saved = isBufferSaved();
  const hasEditor = !!state.bufferEditing;
  if (elements.bufferPreset) {
    elements.bufferPreset.disabled = !hasEditor;
  }
  if (elements.bufferPresetApply) {
    elements.bufferPresetApply.disabled = !hasEditor;
  }
  if (elements.bufferInputNew) {
    elements.bufferInputNew.disabled = !saved;
    elements.bufferInputNew.title = saved ? '' : 'Save the resource first';
  }
  if (elements.bufferAllowNew) {
    elements.bufferAllowNew.disabled = !saved;
    elements.bufferAllowNew.title = saved ? '' : 'Save the resource first';
  }
  if (elements.bufferRestartReader) {
    elements.bufferRestartReader.disabled = !saved;
  }
  if (elements.bufferInputEmpty) {
    elements.bufferInputEmpty.textContent = saved ? 'No inputs yet.' : 'Save the resource first.';
  }
  if (elements.bufferAllowEmpty) {
    elements.bufferAllowEmpty.textContent = saved ? 'No rules (defaults to allow 0.0.0.0).' : 'Save the resource first.';
  }
}

function syncBufferEditingFromForm() {
  if (!state.bufferEditing) return;
  const payload = readBufferForm();
  state.bufferEditing = { ...state.bufferEditing, ...payload };
  if (elements.bufferOutputUrl) {
    elements.bufferOutputUrl.textContent = buildBufferOutputUrl(payload.path || '/');
  }
}

function markBufferDirty() {
  if (!state.bufferEditing) return;
  state.bufferDirty = true;
  syncBufferEditingFromForm();
}

function clearBufferEditor() {
  state.bufferEditing = null;
  state.bufferEditingNew = false;
  state.bufferDirty = false;
  state.bufferInputs = [];
  state.bufferAllow = [];
  if (elements.bufferTitle) {
    elements.bufferTitle.textContent = 'Buffer settings';
  }
  if (elements.bufferState) {
    elements.bufferState.textContent = 'Status: idle';
  }
  if (elements.bufferForm) {
    elements.bufferForm.reset();
  }
  if (elements.bufferPreset) {
    elements.bufferPreset.value = '';
  }
  if (elements.bufferInputTable) {
    elements.bufferInputTable.innerHTML = '';
  }
  if (elements.bufferAllowTable) {
    elements.bufferAllowTable.innerHTML = '';
  }
  if (elements.bufferDiagnostics) {
    elements.bufferDiagnostics.innerHTML = '';
  }
  if (elements.bufferInputEmpty) {
    elements.bufferInputEmpty.style.display = 'block';
  }
  if (elements.bufferAllowEmpty) {
    elements.bufferAllowEmpty.style.display = 'block';
  }
  updateBufferActionState();
}

function defaultBufferResource(id) {
  const baseId = id || `buffer_${Date.now().toString(36)}`;
  return {
    id: baseId,
    name: '',
    path: `/play/${baseId}`,
    enable: true,
    backup_type: 'passive',
    no_data_timeout_sec: 3,
    backup_start_delay_sec: 3,
    backup_return_delay_sec: 10,
    backup_probe_interval_sec: 30,
    buffering_sec: 8,
    bandwidth_kbps: 4000,
    client_start_offset_sec: 1,
    max_client_lag_ms: 3000,
    smart_start_enabled: true,
    smart_target_delay_ms: 1000,
    smart_lookback_ms: 5000,
    smart_require_pat_pmt: true,
    smart_require_keyframe: true,
    smart_require_pcr: false,
    smart_wait_ready_ms: 1500,
    smart_max_lead_ms: 2000,
    keyframe_detect_mode: 'auto',
    av_pts_align_enabled: true,
    av_pts_max_desync_ms: 500,
    paramset_required: true,
    start_debug_enabled: false,
    ts_resync_enabled: true,
    ts_drop_corrupt_enabled: true,
    ts_rewrite_cc_enabled: false,
    pacing_mode: 'none',
  };
}

const BUFFER_PRESETS = {
  live_backup: {
    label: 'Live + backup',
    values: {
      backup_type: 'passive',
      no_data_timeout_sec: 3,
      backup_start_delay_sec: 3,
      backup_return_delay_sec: 10,
      backup_probe_interval_sec: 30,
      buffering_sec: 8,
      bandwidth_kbps: 4000,
      client_start_offset_sec: 1,
      max_client_lag_ms: 3000,
      smart_start_enabled: true,
      smart_target_delay_ms: 1000,
      smart_lookback_ms: 5000,
      smart_wait_ready_ms: 1500,
      smart_max_lead_ms: 2000,
      smart_require_pat_pmt: true,
      smart_require_keyframe: true,
      smart_require_pcr: false,
      keyframe_detect_mode: 'auto',
      av_pts_align_enabled: true,
      av_pts_max_desync_ms: 500,
      paramset_required: true,
      start_debug_enabled: false,
      ts_resync_enabled: true,
      ts_drop_corrupt_enabled: true,
      ts_rewrite_cc_enabled: false,
      pacing_mode: 'pcr',
    },
  },
  multi_input: {
    label: 'Multi-input (active)',
    values: {
      backup_type: 'active',
      no_data_timeout_sec: 2,
      backup_start_delay_sec: 0,
      backup_return_delay_sec: 2,
      backup_probe_interval_sec: 10,
      buffering_sec: 6,
      bandwidth_kbps: 4000,
      client_start_offset_sec: 1,
      max_client_lag_ms: 2000,
      smart_start_enabled: true,
      smart_target_delay_ms: 800,
      smart_lookback_ms: 4000,
      smart_wait_ready_ms: 1200,
      smart_max_lead_ms: 1500,
      smart_require_pat_pmt: true,
      smart_require_keyframe: true,
      smart_require_pcr: false,
      keyframe_detect_mode: 'auto',
      av_pts_align_enabled: true,
      av_pts_max_desync_ms: 400,
      paramset_required: true,
      start_debug_enabled: false,
      ts_resync_enabled: true,
      ts_drop_corrupt_enabled: true,
      ts_rewrite_cc_enabled: false,
      pacing_mode: 'pcr',
    },
  },
  low_latency: {
    label: 'Low latency',
    values: {
      backup_type: 'passive',
      no_data_timeout_sec: 2,
      backup_start_delay_sec: 1,
      backup_return_delay_sec: 3,
      backup_probe_interval_sec: 10,
      buffering_sec: 2,
      bandwidth_kbps: 4000,
      client_start_offset_sec: 0,
      max_client_lag_ms: 800,
      smart_start_enabled: true,
      smart_target_delay_ms: 300,
      smart_lookback_ms: 1500,
      smart_wait_ready_ms: 500,
      smart_max_lead_ms: 800,
      smart_require_pat_pmt: true,
      smart_require_keyframe: true,
      smart_require_pcr: false,
      keyframe_detect_mode: 'idr_parse',
      av_pts_align_enabled: true,
      av_pts_max_desync_ms: 200,
      paramset_required: true,
      start_debug_enabled: false,
      ts_resync_enabled: true,
      ts_drop_corrupt_enabled: true,
      ts_rewrite_cc_enabled: false,
      pacing_mode: 'none',
    },
  },
};

function setPresetField(element, value) {
  if (!element) return;
  if (element.type === 'checkbox') {
    element.checked = !!value;
  } else {
    element.value = value;
  }
}

function applyBufferPresetValues(values) {
  if (!values) return;
  setPresetField(elements.bufferBackupType, values.backup_type);
  setPresetField(elements.bufferNoDataTimeout, values.no_data_timeout_sec);
  setPresetField(elements.bufferBackupStartDelay, values.backup_start_delay_sec);
  setPresetField(elements.bufferBackupReturnDelay, values.backup_return_delay_sec);
  setPresetField(elements.bufferBackupProbeInterval, values.backup_probe_interval_sec);
  setPresetField(elements.bufferBufferingSec, values.buffering_sec);
  setPresetField(elements.bufferBandwidthKbps, values.bandwidth_kbps);
  setPresetField(elements.bufferClientStartOffset, values.client_start_offset_sec);
  setPresetField(elements.bufferMaxClientLag, values.max_client_lag_ms);
  setPresetField(elements.bufferSmartEnabled, values.smart_start_enabled);
  setPresetField(elements.bufferSmartTargetDelay, values.smart_target_delay_ms);
  setPresetField(elements.bufferSmartLookback, values.smart_lookback_ms);
  setPresetField(elements.bufferSmartWaitReady, values.smart_wait_ready_ms);
  setPresetField(elements.bufferSmartMaxLead, values.smart_max_lead_ms);
  setPresetField(elements.bufferSmartRequirePatPmt, values.smart_require_pat_pmt);
  setPresetField(elements.bufferSmartRequireKeyframe, values.smart_require_keyframe);
  setPresetField(elements.bufferSmartRequirePcr, values.smart_require_pcr);
  setPresetField(elements.bufferKeyframeDetect, values.keyframe_detect_mode);
  setPresetField(elements.bufferAvAlignEnabled, values.av_pts_align_enabled);
  setPresetField(elements.bufferAvMaxDesync, values.av_pts_max_desync_ms);
  setPresetField(elements.bufferParamsetRequired, values.paramset_required);
  setPresetField(elements.bufferStartDebug, values.start_debug_enabled);
  setPresetField(elements.bufferTsResync, values.ts_resync_enabled);
  setPresetField(elements.bufferTsDrop, values.ts_drop_corrupt_enabled);
  setPresetField(elements.bufferTsRewrite, values.ts_rewrite_cc_enabled);
  setPresetField(elements.bufferPacingMode, values.pacing_mode);
}

function applyBufferPreset(key) {
  if (!state.bufferEditing) {
    setStatus('Create or select a buffer first');
    return;
  }
  const preset = BUFFER_PRESETS[key];
  if (!preset) {
    setStatus('Select a preset');
    return;
  }
  applyBufferPresetValues(preset.values);
  markBufferDirty();
  setStatus(`Preset applied: ${preset.label}`);
}

function openBufferEditor(buffer, isNew) {
  if (!buffer) {
    clearBufferEditor();
    return;
  }
  const defaults = defaultBufferResource(buffer.id);
  const merged = { ...defaults, ...buffer };
  state.bufferEditing = merged;
  state.bufferEditingNew = !!isNew;
  state.bufferDirty = false;
  if (isNew) {
    state.bufferInputs = [];
    state.bufferAllow = [];
  }

  elements.bufferTitle.textContent = isNew ? 'New buffer' : `Buffer: ${merged.id}`;
  elements.bufferEnabled.checked = merged.enable !== false;
  elements.bufferId.value = merged.id || '';
  elements.bufferId.disabled = !isNew;
  elements.bufferName.value = merged.name || '';
  elements.bufferPath.value = merged.path || '';
  elements.bufferBackupType.value = merged.backup_type || 'passive';
  elements.bufferNoDataTimeout.value = merged.no_data_timeout_sec ?? 3;
  elements.bufferBackupStartDelay.value = merged.backup_start_delay_sec ?? 3;
  elements.bufferBackupReturnDelay.value = merged.backup_return_delay_sec ?? 10;
  elements.bufferBackupProbeInterval.value = merged.backup_probe_interval_sec ?? 30;
  elements.bufferBufferingSec.value = merged.buffering_sec ?? 8;
  elements.bufferBandwidthKbps.value = merged.bandwidth_kbps ?? 4000;
  elements.bufferClientStartOffset.value = merged.client_start_offset_sec ?? 1;
  elements.bufferMaxClientLag.value = merged.max_client_lag_ms ?? 3000;
  elements.bufferSmartEnabled.checked = merged.smart_start_enabled !== false;
  elements.bufferSmartTargetDelay.value = merged.smart_target_delay_ms ?? 1000;
  elements.bufferSmartLookback.value = merged.smart_lookback_ms ?? 5000;
  elements.bufferSmartWaitReady.value = merged.smart_wait_ready_ms ?? 1500;
  elements.bufferSmartMaxLead.value = merged.smart_max_lead_ms ?? 2000;
  elements.bufferSmartRequirePatPmt.checked = merged.smart_require_pat_pmt !== false;
  elements.bufferSmartRequireKeyframe.checked = merged.smart_require_keyframe !== false;
  elements.bufferSmartRequirePcr.checked = merged.smart_require_pcr === true;
  elements.bufferKeyframeDetect.value = merged.keyframe_detect_mode || 'auto';
  elements.bufferAvAlignEnabled.checked = merged.av_pts_align_enabled !== false;
  elements.bufferAvMaxDesync.value = merged.av_pts_max_desync_ms ?? 500;
  elements.bufferParamsetRequired.checked = merged.paramset_required !== false;
  elements.bufferStartDebug.checked = merged.start_debug_enabled === true;
  elements.bufferTsResync.checked = merged.ts_resync_enabled !== false;
  elements.bufferTsDrop.checked = merged.ts_drop_corrupt_enabled !== false;
  elements.bufferTsRewrite.checked = merged.ts_rewrite_cc_enabled === true;
  elements.bufferPacingMode.value = merged.pacing_mode || 'none';
  if (elements.bufferPreset) {
    elements.bufferPreset.value = '';
  }

  const outputUrl = buildBufferOutputUrl(merged.path);
  if (elements.bufferOutputUrl) {
    elements.bufferOutputUrl.textContent = outputUrl;
  }

  renderBufferDetail();
}

function renderBufferList() {
  const list = Array.isArray(state.buffers) ? state.buffers : [];
  elements.bufferList.innerHTML = '';
  if (list.length === 0) {
    elements.bufferListEmpty.style.display = 'block';
    const keepDraft = state.bufferEditing && (state.bufferEditingNew || state.bufferDirty);
    if (!keepDraft) {
      clearBufferEditor();
    } else {
      updateBufferActionState();
    }
    return;
  }
  elements.bufferListEmpty.style.display = 'none';

  list.forEach((buffer) => {
    const status = getBufferStatus(buffer.id) || {};
    const card = document.createElement('button');
    card.type = 'button';
    card.className = 'buffer-card';
    if (state.bufferEditing && state.bufferEditing.id === buffer.id) {
      card.classList.add('active');
    }

    const left = document.createElement('div');
    const name = document.createElement('div');
    name.className = 'buffer-name';
    name.textContent = buffer.name || buffer.id;
    const meta = document.createElement('div');
    meta.className = 'buffer-meta';
    const clientCount = Number.isFinite(status.clients_connected) ? status.clients_connected : 0;
    const pathLabel = buffer.path || 'n/a';
    meta.textContent = `Path ${pathLabel} • Clients ${clientCount}`;
    left.appendChild(name);
    left.appendChild(meta);

    const right = document.createElement('div');
    const stateLabel = document.createElement('div');
    stateLabel.className = 'buffer-state';
    const stateValue = status.state || (buffer.enable === false ? 'STOPPED' : 'UNKNOWN');
    stateLabel.textContent = stateValue;
    if (stateValue === 'OK') {
      stateLabel.classList.add('ok');
    } else if (stateValue === 'DOWN') {
      stateLabel.classList.add('down');
    }
    right.appendChild(stateLabel);

    card.appendChild(left);
    card.appendChild(right);

    card.addEventListener('click', () => {
      loadBufferDetail(buffer.id);
    });
    elements.bufferList.appendChild(card);
  });
}

function renderBufferInputs() {
  const table = elements.bufferInputTable;
  table.innerHTML = '';
  const status = getBufferStatus(state.bufferEditing && state.bufferEditing.id);
  const inputs = (status && Array.isArray(status.inputs) && status.inputs.length)
    ? status.inputs
    : (Array.isArray(state.bufferInputs) ? state.bufferInputs : []);
  const activeIndex = status && Number.isFinite(status.active_input_index)
    ? status.active_input_index
    : null;

  const header = document.createElement('div');
  header.className = 'table-row header';
  header.innerHTML = '<div>Input URL</div><div>Priority</div><div>State</div><div>Last OK</div><div>Last error</div><div>Bytes</div><div></div>';
  table.appendChild(header);

  if (inputs.length === 0) {
    elements.bufferInputEmpty.style.display = 'block';
    return;
  }
  elements.bufferInputEmpty.style.display = 'none';

  inputs.forEach((input, index) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    if (Number.isFinite(activeIndex) && index === activeIndex) {
      row.classList.add('active');
    }
    const stateLabel = input.state || (input.enable === false ? 'DISABLED' : 'DOWN');
    const lastOk = formatTimestamp(input.last_ok_ts);
    const lastError = input.last_error || 'n/a';
    const bytes = formatBytes(input.bytes_in);
    row.innerHTML = `<div>${input.url || ''}</div><div>${input.priority ?? 0}</div>` +
      `<div>${stateLabel}</div><div>${lastOk}</div><div>${lastError}</div><div>${bytes}</div>`;

    const actions = document.createElement('div');
    actions.className = 'buffer-actions';

    const up = document.createElement('button');
    up.type = 'button';
    up.className = 'btn ghost';
    up.textContent = 'Up';
    up.disabled = index === 0;
    up.addEventListener('click', (event) => {
      event.stopPropagation();
      moveBufferInput(input, -1);
    });

    const down = document.createElement('button');
    down.type = 'button';
    down.className = 'btn ghost';
    down.textContent = 'Down';
    down.disabled = index >= inputs.length - 1;
    down.addEventListener('click', (event) => {
      event.stopPropagation();
      moveBufferInput(input, 1);
    });

    const edit = document.createElement('button');
    edit.type = 'button';
    edit.className = 'btn ghost';
    edit.textContent = 'Edit';
    edit.addEventListener('click', (event) => {
      event.stopPropagation();
      openBufferInputModal(input);
    });

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn ghost danger';
    remove.textContent = 'Delete';
    remove.addEventListener('click', async (event) => {
      event.stopPropagation();
      await deleteBufferInput(input);
    });

    actions.appendChild(up);
    actions.appendChild(down);
    actions.appendChild(edit);
    actions.appendChild(remove);
    row.appendChild(actions);
    table.appendChild(row);
  });
}

function renderBufferAllow() {
  const allow = Array.isArray(state.bufferAllow) ? state.bufferAllow : [];
  const table = elements.bufferAllowTable;
  table.innerHTML = '';
  const saved = isBufferSaved();

  const header = document.createElement('div');
  header.className = 'table-row header';
  header.innerHTML = '<div>Type</div><div>Value</div><div></div>';
  table.appendChild(header);

  if (allow.length === 0) {
    elements.bufferAllowEmpty.style.display = 'block';
    if (!saved) {
      return;
    }
    const row = document.createElement('div');
    row.className = 'table-row';
    row.innerHTML = '<div>allow</div><div>0.0.0.0 (default)</div><div></div>';
    table.appendChild(row);
    return;
  }
  elements.bufferAllowEmpty.style.display = 'none';

  allow.forEach((rule) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.dataset.id = rule.id;
    row.innerHTML = `<div>${rule.kind}</div><div>${rule.value}</div>`;
    const actions = document.createElement('div');
    actions.className = 'buffer-actions';
    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'btn ghost danger';
    remove.textContent = 'Delete';
    remove.addEventListener('click', () => {
      deleteBufferAllow(rule.id);
    });
    actions.appendChild(remove);
    row.appendChild(actions);
    table.appendChild(row);
  });
}

function renderBufferDiagnostics() {
  const container = elements.bufferDiagnostics;
  if (!container) return;
  container.innerHTML = '';

  const status = getBufferStatus(state.bufferEditing && state.bufferEditing.id);
  if (!status) {
    const empty = document.createElement('div');
    empty.className = 'muted';
    empty.textContent = 'No status available yet.';
    container.appendChild(empty);
    return;
  }

  const addDiag = (label, value) => {
    const card = document.createElement('div');
    card.className = 'buffer-diag';
    const lbl = document.createElement('div');
    lbl.className = 'buffer-diag-label';
    lbl.textContent = label;
    const val = document.createElement('div');
    val.textContent = value || 'n/a';
    card.appendChild(lbl);
    card.appendChild(val);
    container.appendChild(card);
  };

  const pids = status.pids || {};
  addDiag('PMT PID', pids.pmt_pid || 'n/a');
  addDiag('Video PID', pids.video_pid || 'n/a');
  addDiag('Audio PID', pids.audio_pid || 'n/a');
  addDiag('Codec', pids.video_codec || 'n/a');

  const bufferStats = status.buffer || {};
  addDiag('Buffer packets', bufferStats.capacity_packets || 'n/a');
  addDiag('Write index', bufferStats.write_index || 'n/a');
  addDiag('Last write', formatTimestamp(bufferStats.last_write_ts));

  const smart = status.smart || {};
  addDiag('Checkpoints', smart.checkpoints_count || 0);

  const flags = smart.ready_flags || {};
  const flagCard = document.createElement('div');
  flagCard.className = 'buffer-diag';
  const flagLabel = document.createElement('div');
  flagLabel.className = 'buffer-diag-label';
  flagLabel.textContent = 'Ready flags';
  const flagValue = document.createElement('div');
  ['pat_ok', 'pmt_ok', 'keyframe_ok', 'pcr_ok', 'paramset_ok'].forEach((key) => {
    const span = document.createElement('span');
    const ok = flags[key] === true;
    span.className = `buffer-flag ${ok ? 'ok' : 'down'}`;
    span.textContent = key.replace('_ok', '').toUpperCase();
    span.style.marginRight = '6px';
    flagValue.appendChild(span);
  });
  flagCard.appendChild(flagLabel);
  flagCard.appendChild(flagValue);
  container.appendChild(flagCard);

  if (status.last_start_debug) {
    const dbg = status.last_start_debug;
    const value = `${dbg.mode || 'n/a'} • desync ${dbg.desync_ms || 0} ms • score ${dbg.score || 0}`;
    addDiag('Last start', value);
  }
}

function renderBufferDetail() {
  if (!state.bufferEditing) {
    clearBufferEditor();
    return;
  }
  const buffer = state.bufferEditing;
  if (elements.bufferTitle) {
    elements.bufferTitle.textContent = state.bufferEditingNew
      ? 'New buffer'
      : (buffer.id ? `Buffer: ${buffer.id}` : 'Buffer settings');
  }
  elements.bufferEnabled.checked = buffer.enable !== false;
  elements.bufferId.value = buffer.id || '';
  elements.bufferId.disabled = !state.bufferEditingNew;
  elements.bufferName.value = buffer.name || '';
  elements.bufferPath.value = buffer.path || '';
  elements.bufferBackupType.value = buffer.backup_type || 'passive';
  elements.bufferNoDataTimeout.value = buffer.no_data_timeout_sec ?? 3;
  elements.bufferBackupStartDelay.value = buffer.backup_start_delay_sec ?? 3;
  elements.bufferBackupReturnDelay.value = buffer.backup_return_delay_sec ?? 10;
  elements.bufferBackupProbeInterval.value = buffer.backup_probe_interval_sec ?? 30;
  elements.bufferBufferingSec.value = buffer.buffering_sec ?? 8;
  elements.bufferBandwidthKbps.value = buffer.bandwidth_kbps ?? 4000;
  elements.bufferClientStartOffset.value = buffer.client_start_offset_sec ?? 1;
  elements.bufferMaxClientLag.value = buffer.max_client_lag_ms ?? 3000;
  elements.bufferSmartEnabled.checked = buffer.smart_start_enabled !== false;
  elements.bufferSmartTargetDelay.value = buffer.smart_target_delay_ms ?? 1000;
  elements.bufferSmartLookback.value = buffer.smart_lookback_ms ?? 5000;
  elements.bufferSmartWaitReady.value = buffer.smart_wait_ready_ms ?? 1500;
  elements.bufferSmartMaxLead.value = buffer.smart_max_lead_ms ?? 2000;
  elements.bufferSmartRequirePatPmt.checked = buffer.smart_require_pat_pmt !== false;
  elements.bufferSmartRequireKeyframe.checked = buffer.smart_require_keyframe !== false;
  elements.bufferSmartRequirePcr.checked = buffer.smart_require_pcr === true;
  elements.bufferKeyframeDetect.value = buffer.keyframe_detect_mode || 'auto';
  elements.bufferAvAlignEnabled.checked = buffer.av_pts_align_enabled !== false;
  elements.bufferAvMaxDesync.value = buffer.av_pts_max_desync_ms ?? 500;
  elements.bufferParamsetRequired.checked = buffer.paramset_required !== false;
  elements.bufferStartDebug.checked = buffer.start_debug_enabled === true;
  elements.bufferTsResync.checked = buffer.ts_resync_enabled !== false;
  elements.bufferTsDrop.checked = buffer.ts_drop_corrupt_enabled !== false;
  elements.bufferTsRewrite.checked = buffer.ts_rewrite_cc_enabled === true;
  elements.bufferPacingMode.value = buffer.pacing_mode || 'none';
  if (elements.bufferPreset) {
    elements.bufferPreset.value = '';
  }

  const status = getBufferStatus(buffer.id);
  if (status) {
    const activeLabel = Number.isFinite(status.active_input_index)
      ? ` • input ${status.active_input_index}`
      : '';
    const clientLabel = Number.isFinite(status.clients_connected)
      ? ` • clients ${status.clients_connected}`
      : '';
    const errorText = status.last_error ? ` • ${status.last_error}` : '';
    elements.bufferState.textContent = `Status: ${status.state || 'unknown'}${activeLabel}${clientLabel}${errorText}`;
    const outputUrl = status.output_url || buildBufferOutputUrl(buffer.path);
    elements.bufferOutputUrl.textContent = outputUrl;
  } else {
    elements.bufferState.textContent = 'Status: unknown';
    elements.bufferOutputUrl.textContent = buildBufferOutputUrl(buffer.path);
  }

  renderBufferInputs();
  renderBufferAllow();
  renderBufferDiagnostics();
  updateBufferActionState();
}

async function loadBuffers() {
  try {
    const [list, status] = await Promise.all([
      apiJson('/api/v1/buffers/resources'),
      apiJson('/api/v1/buffer-status'),
    ]);
    state.buffers = Array.isArray(list) ? list : [];
    const statusMap = {};
    if (Array.isArray(status)) {
      status.forEach((item) => {
        if (item && item.id) {
          statusMap[item.id] = item;
        }
      });
    } else if (status && typeof status === 'object') {
      Object.keys(status).forEach((key) => {
        statusMap[key] = status[key];
      });
    }
    state.bufferStatus = statusMap;
  } catch (err) {
    state.buffers = [];
    state.bufferStatus = {};
  }

  renderBufferList();

  const holdEditing = state.bufferEditing && (state.bufferEditingNew || state.bufferDirty);
  if (state.bufferEditing && state.bufferEditing.id && !holdEditing) {
    await loadBufferDetail(state.bufferEditing.id, true);
  } else if (!state.bufferEditing && state.buffers.length > 0) {
    await loadBufferDetail(state.buffers[0].id, true);
  }
}

async function loadBufferDetail(id, silent) {
  if (!id) {
    clearBufferEditor();
    return;
  }
  if (silent && (state.bufferEditingNew || state.bufferDirty)) {
    return;
  }
  try {
    const [row, inputs, allow, status] = await Promise.all([
      apiJson(`/api/v1/buffers/resources/${id}`),
      apiJson(`/api/v1/buffers/resources/${id}/inputs`),
      apiJson('/api/v1/buffers/allow'),
      apiJson(`/api/v1/buffer-status/${id}`),
    ]);
    if (row) {
      state.bufferEditing = row;
      state.bufferEditingNew = false;
      state.bufferDirty = false;
    }
    state.bufferInputs = Array.isArray(inputs) ? inputs : [];
    state.bufferAllow = Array.isArray(allow) ? allow : [];
    if (status) {
      state.bufferStatus = { ...state.bufferStatus, [id]: status };
    }
    if (!silent) {
      openBufferEditor(row, false);
    } else {
      renderBufferDetail();
    }
  } catch (err) {
    if (!silent) {
      setStatus('Failed to load buffer details');
    }
  }
}

function readBufferForm() {
  const id = elements.bufferId.value.trim();
  const rawPath = elements.bufferPath.value.trim();
  const path = normalizeBufferPath(rawPath);
  return {
    id,
    name: elements.bufferName.value.trim(),
    path: rawPath ? path : '',
    enable: elements.bufferEnabled.checked,
    backup_type: elements.bufferBackupType.value,
    no_data_timeout_sec: toNumber(elements.bufferNoDataTimeout.value) ?? 3,
    backup_start_delay_sec: toNumber(elements.bufferBackupStartDelay.value) ?? 3,
    backup_return_delay_sec: toNumber(elements.bufferBackupReturnDelay.value) ?? 10,
    backup_probe_interval_sec: toNumber(elements.bufferBackupProbeInterval.value) ?? 30,
    buffering_sec: toNumber(elements.bufferBufferingSec.value) ?? 8,
    bandwidth_kbps: toNumber(elements.bufferBandwidthKbps.value) ?? 4000,
    client_start_offset_sec: toNumber(elements.bufferClientStartOffset.value) ?? 1,
    max_client_lag_ms: toNumber(elements.bufferMaxClientLag.value) ?? 3000,
    smart_start_enabled: elements.bufferSmartEnabled.checked,
    smart_target_delay_ms: toNumber(elements.bufferSmartTargetDelay.value) ?? 1000,
    smart_lookback_ms: toNumber(elements.bufferSmartLookback.value) ?? 5000,
    smart_require_pat_pmt: elements.bufferSmartRequirePatPmt.checked,
    smart_require_keyframe: elements.bufferSmartRequireKeyframe.checked,
    smart_require_pcr: elements.bufferSmartRequirePcr.checked,
    smart_wait_ready_ms: toNumber(elements.bufferSmartWaitReady.value) ?? 1500,
    smart_max_lead_ms: toNumber(elements.bufferSmartMaxLead.value) ?? 2000,
    keyframe_detect_mode: elements.bufferKeyframeDetect.value,
    av_pts_align_enabled: elements.bufferAvAlignEnabled.checked,
    av_pts_max_desync_ms: toNumber(elements.bufferAvMaxDesync.value) ?? 500,
    paramset_required: elements.bufferParamsetRequired.checked,
    start_debug_enabled: elements.bufferStartDebug.checked,
    ts_resync_enabled: elements.bufferTsResync.checked,
    ts_drop_corrupt_enabled: elements.bufferTsDrop.checked,
    ts_rewrite_cc_enabled: elements.bufferTsRewrite.checked,
    pacing_mode: elements.bufferPacingMode.value,
  };
}

async function saveBuffer() {
  const payload = readBufferForm();
  if (!payload.id) {
    const autoId = `buffer_${Date.now().toString(36)}`;
    payload.id = autoId;
    elements.bufferId.value = autoId;
    if (!payload.path) {
      const autoPath = normalizeBufferPath(`/play/${autoId}`);
      payload.path = autoPath;
      elements.bufferPath.value = autoPath;
    }
  }
  if (!payload.path) throw new Error('Path is required');
  let saved;
  if (state.bufferEditingNew) {
    saved = await apiJson('/api/v1/buffers/resources', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  } else {
    saved = await apiJson(`/api/v1/buffers/resources/${encodeURIComponent(payload.id)}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  }
  state.bufferEditingNew = false;
  state.bufferDirty = false;
  if (saved && saved.id) {
    state.bufferEditing = { ...state.bufferEditing, ...saved };
  } else {
    state.bufferEditing = { ...state.bufferEditing, ...payload };
  }
  renderBufferDetail();
  await loadBuffers();
  setStatus('Buffer saved');
}

async function deleteBuffer() {
  const target = state.bufferEditing;
  if (!target || !target.id) return;
  const confirmed = window.confirm(`Delete buffer ${target.id}?`);
  if (!confirmed) return;
  await apiJson(`/api/v1/buffers/resources/${encodeURIComponent(target.id)}`, { method: 'DELETE' });
  await loadBuffers();
  setStatus('Buffer deleted');
  clearBufferEditor();
}

async function reloadBufferRuntime() {
  await apiJson('/api/v1/buffers/reload', { method: 'POST' });
  await loadBuffers();
  setStatus('Buffers reloaded');
}

async function restartBufferReader() {
  if (!state.bufferEditing || !state.bufferEditing.id) return;
  await apiJson(`/api/v1/buffers/${encodeURIComponent(state.bufferEditing.id)}/restart-reader`, {
    method: 'POST',
  });
  await loadBuffers();
  setStatus('Reader restart requested');
}

function openBufferInputModal(input) {
  if (!isBufferSaved()) {
    setStatus('Save the resource first');
    return;
  }
  state.bufferInputEditing = input || null;
  elements.bufferInputError.textContent = '';
  elements.bufferInputEnabled.checked = !input || input.enable !== false;
  elements.bufferInputUrl.value = (input && input.url) || '';
  elements.bufferInputPriority.value = input && Number.isFinite(input.priority) ? input.priority : 0;
  setOverlay(elements.bufferInputOverlay, true);
}

function closeBufferInputModal() {
  state.bufferInputEditing = null;
  setOverlay(elements.bufferInputOverlay, false);
}

async function saveBufferInput() {
  if (!isBufferSaved()) {
    throw new Error('Save the resource first');
  }
  const payload = {
    enable: elements.bufferInputEnabled.checked,
    url: elements.bufferInputUrl.value.trim(),
    priority: toNumber(elements.bufferInputPriority.value) ?? 0,
  };
  if (!payload.url) {
    throw new Error('Input URL is required');
  }
  const bufferId = encodeURIComponent(state.bufferEditing.id);
  if (state.bufferInputEditing && state.bufferInputEditing.id) {
    await apiJson(`/api/v1/buffers/resources/${bufferId}/inputs/${encodeURIComponent(state.bufferInputEditing.id)}`, {
      method: 'PUT',
      body: JSON.stringify(payload),
    });
  } else {
    await apiJson(`/api/v1/buffers/resources/${bufferId}/inputs`, {
      method: 'POST',
      body: JSON.stringify(payload),
    });
  }
  closeBufferInputModal();
  await loadBufferDetail(state.bufferEditing.id, true);
  setStatus('Input saved');
}

async function deleteBufferInput(input) {
  if (!state.bufferEditing || !state.bufferEditing.id || !input) return;
  const confirmed = window.confirm(`Delete input ${input.id}?`);
  if (!confirmed) return;
  await apiJson(`/api/v1/buffers/resources/${encodeURIComponent(state.bufferEditing.id)}/inputs/${encodeURIComponent(input.id)}`, {
    method: 'DELETE',
  });
  await loadBufferDetail(state.bufferEditing.id, true);
  setStatus('Input deleted');
}

async function moveBufferInput(input, direction) {
  if (!state.bufferEditing || !state.bufferEditing.id) return;
  const status = getBufferStatus(state.bufferEditing.id);
  const inputs = (status && Array.isArray(status.inputs) && status.inputs.length)
    ? status.inputs
    : (Array.isArray(state.bufferInputs) ? state.bufferInputs : []);
  const idx = inputs.findIndex((item) => item.id === input.id);
  if (idx < 0) return;
  const swapIdx = idx + direction;
  if (swapIdx < 0 || swapIdx >= inputs.length) return;
  const current = inputs[idx];
  const swap = inputs[swapIdx];
  const bufferId = encodeURIComponent(state.bufferEditing.id);
  const payloadCurrent = {
    enable: current.enable !== false,
    url: current.url || '',
    priority: swap.priority ?? 0,
  };
  const payloadSwap = {
    enable: swap.enable !== false,
    url: swap.url || '',
    priority: current.priority ?? 0,
  };
  await apiJson(`/api/v1/buffers/resources/${bufferId}/inputs/${encodeURIComponent(current.id)}`, {
    method: 'PUT',
    body: JSON.stringify(payloadCurrent),
  });
  await apiJson(`/api/v1/buffers/resources/${bufferId}/inputs/${encodeURIComponent(swap.id)}`, {
    method: 'PUT',
    body: JSON.stringify(payloadSwap),
  });
  await loadBufferDetail(state.bufferEditing.id, true);
}

function openBufferAllowModal() {
  if (!isBufferSaved()) {
    setStatus('Save the resource first');
    return;
  }
  state.bufferAllowEditing = null;
  elements.bufferAllowError.textContent = '';
  elements.bufferAllowKind.value = 'allow';
  elements.bufferAllowValue.value = '';
  setOverlay(elements.bufferAllowOverlay, true);
}

function closeBufferAllowModal() {
  state.bufferAllowEditing = null;
  setOverlay(elements.bufferAllowOverlay, false);
}

async function saveBufferAllow() {
  if (!isBufferSaved()) {
    throw new Error('Save the resource first');
  }
  const payload = {
    kind: elements.bufferAllowKind.value,
    value: elements.bufferAllowValue.value.trim(),
  };
  if (!payload.value) {
    throw new Error('Allow value is required');
  }
  await apiJson('/api/v1/buffers/allow', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  closeBufferAllowModal();
  await loadBufferDetail(state.bufferEditing.id, true);
  setStatus('Allow rule saved');
}

async function deleteBufferAllow(ruleId) {
  if (!ruleId) return;
  const confirmed = window.confirm('Delete allow rule?');
  if (!confirmed) return;
  await apiJson(`/api/v1/buffers/allow/${encodeURIComponent(ruleId)}`, {
    method: 'DELETE',
  });
  await loadBufferDetail(state.bufferEditing && state.bufferEditing.id, true);
  setStatus('Allow rule deleted');
}

function startBufferPolling() {
  if (state.bufferTimer) {
    clearInterval(state.bufferTimer);
  }
  state.bufferTimer = setInterval(loadBuffers, POLL_BUFFER_MS);
  loadBuffers();
}

function stopBufferPolling() {
  if (state.bufferTimer) {
    clearInterval(state.bufferTimer);
    state.bufferTimer = null;
  }
}

function validateOutput(output, index) {
  const label = `Output #${index + 1}`;
  const tabHint = ' (General tab)';
  if (!output) {
    return;
  }
  if (typeof output === 'string') {
    if (!output.trim()) return;
    return;
  }
  if (output._inline_invalid) {
    throw new Error(`${label}${tabHint}: invalid output URL`);
  }
  if (output.biss) {
    const parsed = parseBissKey(output.biss);
    if (parsed.error) {
      throw new Error(`${label}${tabHint}: ${parsed.error}`);
    }
    output.biss = parsed.value;
  }
  if (!output.format) {
    throw new Error(`${label}${tabHint}: format is required`);
  }
  if (output.format === 'hls') {
    if (!output.path) throw new Error(`${label}${tabHint}: HLS output directory is required`);
    return;
  }
  if (output.format === 'http') {
    if (!output.host || !output.port || !output.path) {
      throw new Error(`${label}${tabHint}: host, port and path are required`);
    }
    return;
  }
  if (output.format === 'udp' || output.format === 'rtp') {
    if (!output.addr || !output.port) {
      throw new Error(`${label}${tabHint}: address and port are required`);
    }
    return;
  }
  if (output.format === 'np') {
    if (!output.host || !output.port || !output.path) {
      throw new Error(`${label}${tabHint}: host, port and path are required`);
    }
    return;
  }
  if (output.format === 'srt') {
    if (!output.url && !(output.host || output.addr)) {
      throw new Error(`${label}${tabHint}: SRT URL or host is required`);
    }
    if (!output.bridge_port) {
      throw new Error(`${label}${tabHint}: bridge port is required`);
    }
    const hasBadArgs = (args) => Array.isArray(args) && args.some((arg) => /\s/.test(arg));
    if (hasBadArgs(output.bridge_input_args) || hasBadArgs(output.bridge_output_args)) {
      throw new Error(`${label}${tabHint}: SRT bridge args must be one argument per line (no spaces)`);
    }
    return;
  }
  if (output.format === 'file') {
    if (!output.filename) throw new Error(`${label}${tabHint}: filename is required`);
  }
}

function validateTranscodeOutput(output, index) {
  const label = `Transcode output #${index + 1}`;
  if (!output || !output.url) {
    throw new Error(`${label} (Transcode tab): URL is required`);
  }
}

function openEditor(stream, isNew) {
  const config = stream.config || {};

  elements.editorError.textContent = '';
  if (elements.streamTranscodePreset) {
    elements.streamTranscodePreset.value = '';
  }
  if (elements.streamTranscodeStatus) {
    elements.streamTranscodeStatus.textContent = '';
    elements.streamTranscodeStatus.classList.remove('is-error');
  }
  state.transcodeOutputs = [];
  state.transcodeOutputEditingIndex = null;
  state.transcodeOutputMonitorIndex = null;
  state.transcodeWatchdogDefaults = normalizeOutputWatchdog(null, TRANSCODE_WATCHDOG_DEFAULTS);
  updateStreamGroupOptions();
  elements.streamId.value = stream.id || '';
  elements.streamId.disabled = false;
  elements.streamName.value = config.name || '';
  state.streamIdAuto = isNew && !elements.streamId.value.trim();
  if (state.streamIdAuto && elements.streamName.value.trim()) {
    elements.streamId.value = slugifyStreamId(elements.streamName.value.trim());
  }
  elements.streamEnabled.checked = stream.enabled !== false;
  if (elements.streamType) {
    const typeValue = (config.type === 'transcode' || config.type === 'ffmpeg') ? 'transcode' : '';
    elements.streamType.value = typeValue;
    setTranscodeMode(typeValue === 'transcode');
  }
  elements.streamMpts.checked = config.mpts === true;
  updateMptsFields();
  elements.streamDesc.value = config.description || '';
  if (elements.streamGroup) {
    elements.streamGroup.value = config.group || config.category || '';
  }
  if (elements.streamServiceType) {
    elements.streamServiceType.value = config.service_type_id || '';
  }
  if (elements.streamServiceCodepage) {
    elements.streamServiceCodepage.value = config.codepage || '';
  }
  if (elements.streamServiceProvider) {
    elements.streamServiceProvider.value = config.service_provider || '';
  }
  if (elements.streamServiceName) {
    elements.streamServiceName.value = config.service_name || '';
  }
  if (elements.streamServiceHbbtv) {
    elements.streamServiceHbbtv.value = config.hbbtv_url || '';
  }
  if (elements.streamServiceCas) {
    elements.streamServiceCas.checked = config.cas === true;
  }
  const mptsConfig = config.mpts_config || {};
  const mptsGeneral = mptsConfig.general || {};
  const mptsNit = mptsConfig.nit || {};
  const mptsAdv = mptsConfig.advanced || {};
  if (elements.mptsCountry) {
    elements.mptsCountry.value = mptsGeneral.country || '';
  }
  if (elements.mptsUtcOffset) {
    elements.mptsUtcOffset.value = mptsGeneral.utc_offset || '';
  }
  const mptsDst = (mptsGeneral && typeof mptsGeneral.dst === 'object' && mptsGeneral.dst) ? mptsGeneral.dst : {};
  if (elements.mptsDstTimeOfChange) {
    elements.mptsDstTimeOfChange.value = mptsDst.time_of_change || '';
  }
  if (elements.mptsDstNextOffset) {
    elements.mptsDstNextOffset.value = (mptsDst.next_offset_minutes !== undefined && mptsDst.next_offset_minutes !== null)
      ? mptsDst.next_offset_minutes
      : '';
  }
  if (elements.mptsNetworkId) {
    elements.mptsNetworkId.value = mptsGeneral.network_id || '';
  }
  if (elements.mptsNetworkName) {
    elements.mptsNetworkName.value = mptsGeneral.network_name || '';
  }
  if (elements.mptsProviderName) {
    elements.mptsProviderName.value = mptsGeneral.provider_name || '';
  }
  if (elements.mptsCodepage) {
    elements.mptsCodepage.value = mptsGeneral.codepage || '';
  }
  if (elements.mptsTsid) {
    elements.mptsTsid.value = mptsGeneral.tsid || '';
  }
  if (elements.mptsOnid) {
    elements.mptsOnid.value = mptsGeneral.onid || '';
  }
  if (elements.mptsDelivery) {
    elements.mptsDelivery.value = mptsNit.delivery || '';
  }
  if (elements.mptsFrequency) {
    elements.mptsFrequency.value = mptsNit.frequency || '';
  }
  if (elements.mptsSymbolrate) {
    elements.mptsSymbolrate.value = mptsNit.symbolrate || '';
  }
  if (elements.mptsBandwidth) {
    elements.mptsBandwidth.value = mptsNit.bandwidth || '';
  }
  if (elements.mptsOrbitalPosition) {
    elements.mptsOrbitalPosition.value = mptsNit.orbital_position || '';
  }
  if (elements.mptsPolarization) {
    elements.mptsPolarization.value = mptsNit.polarization || '';
  }
  if (elements.mptsRolloff) {
    elements.mptsRolloff.value = mptsNit.rolloff || '';
  }
  if (elements.mptsFec) {
    elements.mptsFec.value = mptsNit.fec || '';
  }
  if (elements.mptsModulation) {
    elements.mptsModulation.value = mptsNit.modulation || '';
  }
  if (elements.mptsNetworkSearch) {
    elements.mptsNetworkSearch.value = mptsNit.network_search || '';
  }
  if (elements.mptsLcnTag) {
    elements.mptsLcnTag.value = mptsNit.lcn_descriptor_tag || '';
  }
  if (elements.mptsLcnTags) {
    if (Array.isArray(mptsNit.lcn_descriptor_tags)) {
      elements.mptsLcnTags.value = mptsNit.lcn_descriptor_tags.join(',');
    } else {
      elements.mptsLcnTags.value = mptsNit.lcn_descriptor_tags || '';
    }
  }
  if (elements.mptsLcnVersion) {
    elements.mptsLcnVersion.value = (mptsNit.lcn_version !== undefined && mptsNit.lcn_version !== null)
      ? mptsNit.lcn_version
      : '';
  }
  if (elements.mptsSiInterval) {
    elements.mptsSiInterval.value = mptsAdv.si_interval_ms || '';
  }
  if (elements.mptsTargetBitrate) {
    elements.mptsTargetBitrate.value = mptsAdv.target_bitrate || '';
  }
  // Auto-probe: восстановить настройки автосканирования сервисов.
  if (elements.mptsAutoProbe) {
    elements.mptsAutoProbe.checked = mptsAdv.auto_probe === true;
  }
  if (elements.mptsAutoProbeDuration) {
    const duration = mptsAdv.auto_probe_duration_sec || mptsAdv.auto_probe_duration;
    elements.mptsAutoProbeDuration.value = (duration !== undefined && duration !== null) ? duration : '';
  }
  if (elements.mptsPcrRestamp) {
    elements.mptsPcrRestamp.checked = mptsAdv.pcr_restamp === true;
  }
  if (elements.mptsPcrSmoothing) {
    elements.mptsPcrSmoothing.checked = mptsAdv.pcr_smoothing === true;
  }
  if (elements.mptsPcrSmoothAlpha) {
    elements.mptsPcrSmoothAlpha.value = mptsAdv.pcr_smooth_alpha || '';
  }
  if (elements.mptsPcrSmoothMax) {
    elements.mptsPcrSmoothMax.value = mptsAdv.pcr_smooth_max_offset_ms || '';
  }
  if (elements.mptsPatVersion) {
    elements.mptsPatVersion.value = mptsAdv.pat_version || '';
  }
  if (elements.mptsNitVersion) {
    elements.mptsNitVersion.value = mptsAdv.nit_version || '';
  }
  if (elements.mptsCatVersion) {
    elements.mptsCatVersion.value = mptsAdv.cat_version || '';
  }
  if (elements.mptsSdtVersion) {
    elements.mptsSdtVersion.value = mptsAdv.sdt_version || '';
  }
  if (elements.mptsDisableAutoremap) {
    elements.mptsDisableAutoremap.checked = mptsAdv.disable_auto_remap === true;
  }
  if (elements.mptsPassNit) {
    elements.mptsPassNit.checked = mptsAdv.pass_nit === true;
  }
  if (elements.mptsPassSdt) {
    elements.mptsPassSdt.checked = mptsAdv.pass_sdt === true;
  }
  if (elements.mptsPassEit) {
    elements.mptsPassEit.checked = mptsAdv.pass_eit === true;
  }
  if (elements.mptsPassCat) {
    elements.mptsPassCat.checked = mptsAdv.pass_cat === true;
  }
  if (elements.mptsPassTdt) {
    elements.mptsPassTdt.checked = mptsAdv.pass_tdt === true;
  }
  if (elements.mptsDisableTot) {
    elements.mptsDisableTot.checked = mptsAdv.disable_tot === true;
  }
  if (elements.mptsEitSource) {
    elements.mptsEitSource.value = mptsAdv.eit_source || '';
  }
  if (elements.mptsEitTableIds) {
    if (Array.isArray(mptsAdv.eit_table_ids)) {
      elements.mptsEitTableIds.value = mptsAdv.eit_table_ids.join(',');
    } else {
      elements.mptsEitTableIds.value = mptsAdv.eit_table_ids || '';
    }
  }
  if (elements.mptsCatSource) {
    elements.mptsCatSource.value = mptsAdv.cat_source || '';
  }
  if (elements.mptsStrictPnr) {
    elements.mptsStrictPnr.checked = mptsAdv.strict_pnr === true;
  }
  if (elements.mptsSptsOnly) {
    elements.mptsSptsOnly.checked = mptsAdv.spts_only !== false;
  }
  updateMptsAutoremapWarning();
  updateMptsPnrWarning();
  updateMptsInputWarning();
  updateMptsDeliveryWarning();
  const epgConfig = config.epg || {};
  if (elements.streamEpgId) {
    elements.streamEpgId.value = epgConfig.xmltv_id || '';
  }
  if (elements.streamEpgFormat) {
    elements.streamEpgFormat.value = epgConfig.format || '';
  }
  if (elements.streamEpgDestination) {
    elements.streamEpgDestination.value = epgConfig.destination || '';
  }
  if (elements.streamEpgCodepage) {
    elements.streamEpgCodepage.value = epgConfig.codepage || '';
  }
  if (elements.streamSetPnr) {
    elements.streamSetPnr.value = config.set_pnr || '';
  }
  if (elements.streamSetTsid) {
    elements.streamSetTsid.value = config.set_tsid || '';
  }
  if (elements.streamMap) {
    elements.streamMap.value = mapToString(config.map);
  }
  if (elements.streamFilter) {
    elements.streamFilter.value = mapToString(config.filter);
  }
  if (elements.streamFilterExclude) {
    elements.streamFilterExclude.value = mapToString(config['filter~']);
  }
  if (elements.streamTimeout) {
    elements.streamTimeout.value = config.timeout || '';
  }
  if (elements.streamHttpKeep) {
    elements.streamHttpKeep.value = config.http_keep_active || '';
  }
  if (elements.streamAuthEnabled) {
    if (config.auth_enabled === true) {
      elements.streamAuthEnabled.value = 'true';
    } else if (config.auth_enabled === false) {
      elements.streamAuthEnabled.value = 'false';
    } else {
      elements.streamAuthEnabled.value = '';
    }
  }
  if (elements.streamOnPlay) {
    elements.streamOnPlay.value = config.on_play || '';
  }
  if (elements.streamOnPublish) {
    elements.streamOnPublish.value = config.on_publish || '';
  }
  if (elements.streamSessionKeys) {
    elements.streamSessionKeys.value = config.session_keys || '';
  }
  if (elements.streamNoSdt) {
    elements.streamNoSdt.checked = config.no_sdt === true;
  }
  if (elements.streamNoEit) {
    elements.streamNoEit.checked = config.no_eit === true;
  }
  if (elements.streamPassSdt) {
    elements.streamPassSdt.checked = config.pass_sdt === true;
  }
  if (elements.streamPassEit) {
    elements.streamPassEit.checked = config.pass_eit === true;
  }
  if (elements.streamNoReload) {
    elements.streamNoReload.checked = config.no_reload === true;
  }
  if (elements.streamBackupType) {
    elements.streamBackupType.value = config.backup_type || '';
  }
  if (elements.streamBackupWarmMax) {
    elements.streamBackupWarmMax.value = config.backup_active_warm_max || '';
  }
  if (elements.streamBackupInitialDelay) {
    elements.streamBackupInitialDelay.value = config.backup_initial_delay || '';
  }
  if (elements.streamBackupStartDelay) {
    elements.streamBackupStartDelay.value = config.backup_start_delay || '';
  }
  if (elements.streamBackupReturnDelay) {
    elements.streamBackupReturnDelay.value = config.backup_return_delay || '';
  }
  if (elements.streamBackupStopInactiveSec) {
    elements.streamBackupStopInactiveSec.value = config.stop_if_all_inactive_sec ||
      config.backup_stop_if_all_inactive_sec || '';
  }
  if (elements.streamStableOkSec) {
    elements.streamStableOkSec.value = config.stable_ok_sec || '';
  }
  if (elements.streamNoDataTimeoutSec) {
    elements.streamNoDataTimeoutSec.value = config.no_data_timeout_sec || '';
  }
  if (elements.streamProbeIntervalSec) {
    elements.streamProbeIntervalSec.value = config.probe_interval_sec || '';
  }
  updateStreamBackupFields();

  if (elements.streamTranscodeEngine) {
    const tc = config.transcode || {};
    elements.streamTranscodeEngine.value = tc.engine || '';
    elements.streamTranscodeGpuDevice.value = tc.gpu_device || '';
    elements.streamTranscodeFfmpegPath.value = tc.ffmpeg_path || tc.ffmpeg_bin || '';
    elements.streamTranscodeLogFile.value = tc.log_file || '';
    if (elements.streamTranscodeLogMain) {
      const logToMain = tc.log_to_main;
      elements.streamTranscodeLogMain.checked = logToMain === true || logToMain === 'all' || logToMain === 'true';
    }
    elements.streamTranscodeGlobalArgs.value = argsToLines(tc.ffmpeg_global_args);
    elements.streamTranscodeDecoderArgs.value = argsToLines(tc.decoder_args);
    elements.streamTranscodeCommonArgs.value = argsToLines(tc.common_output_args || tc.common_input_args);
    state.transcodeOutputs = normalizeTranscodeOutputs(tc.outputs);
    state.transcodeOutputEditingIndex = null;
    state.transcodeWatchdogDefaults = normalizeOutputWatchdog(tc.watchdog, TRANSCODE_WATCHDOG_DEFAULTS);
    state.transcodeOutputs = state.transcodeOutputs.map(ensureTranscodeOutputWatchdog);
    if (elements.streamTranscodeInputProbeUdp) {
      elements.streamTranscodeInputProbeUdp.checked = tc.input_probe_udp === true;
    }
    if (elements.streamTranscodeInputProbeRestart) {
      elements.streamTranscodeInputProbeRestart.checked = tc.input_probe_restart === true;
    }
    if (elements.streamTranscodeProcessPerOutput) {
      elements.streamTranscodeProcessPerOutput.checked = tc.process_per_output === true;
    }
    if (elements.streamTranscodeSeamlessUdpProxy) {
      elements.streamTranscodeSeamlessUdpProxy.checked = tc.seamless_udp_proxy === true;
    }
    updateInputProbeRestartToggle();
    updateSeamlessProxyToggle();
  }

  state.inputs = normalizeInputs(config.input || []);
  renderInputList();

  state.mptsServices = normalizeMptsServices(config.mpts_services || []);
  if (state.mptsServices.length === 0 && config.mpts === true) {
    state.mptsServices = normalizeMptsServices(config.input || []);
  }
  renderMptsServiceList();

  state.mptsCa = normalizeMptsCa(mptsConfig.ca || []);
  renderMptsCaList();
  // В openEditor MPTS поля частично создаются динамически (список сервисов/CA),
  // поэтому повторно применяем disabled-состояние после render.
  updateMptsFields();

  state.outputs = normalizeOutputs(config.output || [], stream.id || '');
  renderOutputList();
  renderTranscodeOutputList();
  updateEditorTranscodeOutputStatus();

  elements.editorTitle.textContent = isNew ? 'New stream' : 'Edit stream';
  elements.btnDelete.style.visibility = isNew ? 'hidden' : 'visible';
  state.editing = { stream, isNew };
  setTab('general', 'stream-editor');
  setOverlay(elements.editorOverlay, true);
  updateEditorTranscodeStatus();
}

function closeEditor() {
  state.editing = null;
  state.transcodeOutputMonitorIndex = null;
  setOverlay(elements.editorOverlay, false);
}

function updateAutoHls() {
  if (!state.editing || !state.editing.isNew) return;
  const id = elements.streamId.value.trim() || 'stream';
  const defaults = getHlsDefaults(id);
  let changed = false;

  state.outputs.forEach((output) => {
    if (output.format === 'hls' && output.auto) {
      output.path = defaults.path;
      output.base_url = defaults.base_url;
      changed = true;
    }
  });

  if (changed) {
    renderOutputList();
  }
}

function syncStreamIdFromName() {
  if (!state.editing || !state.editing.isNew) return;
  if (!state.streamIdAuto) return;
  const name = elements.streamName.value.trim();
  const nextId = name ? slugifyStreamId(name) : '';
  if (elements.streamId.value !== nextId) {
    elements.streamId.value = nextId;
    updateAutoHls();
  }
}

function handleStreamIdInput() {
  if (!state.editing || !state.editing.isNew) {
    updateAutoHls();
    return;
  }
  const current = elements.streamId.value.trim();
  if (!current) {
    state.streamIdAuto = true;
    syncStreamIdFromName();
    return;
  }
  state.streamIdAuto = false;
  updateAutoHls();
}

function handleStreamNameInput() {
  syncStreamIdFromName();
}

function collectInputs() {
  const values = [];
  const items = elements.inputList.querySelectorAll('.list-input[data-role="input"]');
  state.inputs = [];
  items.forEach((input) => {
    const value = input.value.trim();
    state.inputs.push(value);
    if (value) values.push(value);
  });
  return values;
}

function readStreamForm() {
  const id = elements.streamId.value.trim();
  const name = elements.streamName.value.trim();
  const enabled = elements.streamEnabled.checked;
  const mptsEnabled = elements.streamMpts && elements.streamMpts.checked;
  let inputs = collectInputs();
  const description = elements.streamDesc.value.trim();
  const streamType = elements.streamType ? elements.streamType.value.trim() : '';
  const isTranscode = streamType === 'transcode' || streamType === 'ffmpeg';

  syncOutputInlineValues();

  if (!id) {
    throw new Error('Stream id is required (General tab)');
  }
  if (!name) {
    throw new Error('Stream name is required (General tab)');
  }
  let mptsServices = [];
  if (mptsEnabled) {
    mptsServices = collectMptsServices();
    if (!mptsServices.length) {
      throw new Error('At least one MPTS service input is required (MPTS tab)');
    }
    mptsServices.forEach((service, index) => {
      if (!service.input) {
        throw new Error(`MPTS service #${index + 1}: input URL is required`);
      }
      const parsed = parseInputUrl(service.input);
      if (!parsed || !parsed.format) {
        throw new Error(`MPTS service #${index + 1}: invalid input URL`);
      }
      const pnr = toNumber(service.pnr);
      if (pnr !== undefined && (pnr < 1 || pnr > 65535)) {
        throw new Error(`MPTS service #${index + 1}: PNR must be between 1 and 65535`);
      }
      const st = toNumber(service.service_type_id);
      if (st !== undefined && (st < 0 || st > 255)) {
        throw new Error(`MPTS service #${index + 1}: service type must be between 0 and 255`);
      }
      const lcn = toNumber(service.lcn);
      if (lcn !== undefined && (lcn < 1 || lcn > 1023)) {
        throw new Error(`MPTS service #${index + 1}: LCN must be between 1 and 1023`);
      }
    });
    inputs = mptsServices.map((service) => service.input);
  } else if (!inputs.length) {
    throw new Error('At least one input URL is required (General tab)');
  }

  let outputs = [];
  if (!isTranscode) {
    outputs = state.outputs.map((output, index) => {
      if (typeof output === 'string') {
        return output.trim();
      }
      if (!output) return '';
      if (!output.format && !output.type) {
        const inlineText = output._inline_value !== undefined ? String(output._inline_value || '').trim() : '';
        const fallback = inlineText || getOutputInlineValue(output, state.settings).trim();
        if (fallback) return fallback;
      }
      validateOutput(output, index);
      const clone = { ...output };
      delete clone.auto;
      delete clone._inline_value;
      delete clone._inline_invalid;
      return clone;
    }).filter((entry) => {
      if (!entry) return false;
      if (typeof entry === 'string') return entry.trim().length > 0;
      return true;
    });
  }

  const config = {
    id,
    name,
    input: inputs,
    description: description || undefined,
    mpts: elements.streamMpts.checked || undefined,
  };
  const group = (elements.streamGroup && elements.streamGroup.value || '').trim();
  if (group) {
    config.group = group;
  }
  if (outputs.length) {
    config.output = outputs;
  }
  if (isTranscode) {
    config.type = 'transcode';
  }

  const timeout = toNumber(elements.streamTimeout && elements.streamTimeout.value);
  if (timeout !== undefined) config.timeout = timeout;

  const httpKeep = toNumber(elements.streamHttpKeep && elements.streamHttpKeep.value);
  if (httpKeep !== undefined) config.http_keep_active = httpKeep;

  if (elements.streamAuthEnabled) {
    const authValue = elements.streamAuthEnabled.value;
    if (authValue === 'true') {
      config.auth_enabled = true;
    } else if (authValue === 'false') {
      config.auth_enabled = false;
    }
  }
  const onPlay = (elements.streamOnPlay && elements.streamOnPlay.value || '').trim();
  if (onPlay) config.on_play = onPlay;
  const onPublish = (elements.streamOnPublish && elements.streamOnPublish.value || '').trim();
  if (onPublish) config.on_publish = onPublish;
  const sessionKeys = (elements.streamSessionKeys && elements.streamSessionKeys.value || '').trim();
  if (sessionKeys) config.session_keys = sessionKeys;

  const setPnr = toNumber(elements.streamSetPnr && elements.streamSetPnr.value);
  if (setPnr !== undefined) config.set_pnr = setPnr;

  const setTsid = toNumber(elements.streamSetTsid && elements.streamSetTsid.value);
  if (setTsid !== undefined) config.set_tsid = setTsid;

  const mapValue = (elements.streamMap && elements.streamMap.value || '').trim();
  if (mapValue) config.map = mapValue;

  const filterValue = (elements.streamFilter && elements.streamFilter.value || '').trim();
  if (filterValue) {
    const parts = filterValue.split(',').map((part) => part.trim()).filter(Boolean);
    parts.forEach((part) => {
      const pid = Number(part);
      if (!Number.isFinite(pid) || Math.floor(pid) !== pid) {
        throw new Error(`Filter PID must be an integer: ${part} (Remap tab)`);
      }
      if (pid < 32 || pid > 8190) {
        throw new Error(`Filter PID must be between 32 and 8190: ${part} (Remap tab)`);
      }
    });
    config.filter = parts.join(',');
  }
  const filterExcludeValue = (elements.streamFilterExclude && elements.streamFilterExclude.value || '').trim();
  if (filterExcludeValue) {
    const parts = filterExcludeValue.split(',').map((part) => part.trim()).filter(Boolean);
    parts.forEach((part) => {
      const pid = Number(part);
      if (!Number.isFinite(pid) || Math.floor(pid) !== pid) {
        throw new Error(`Exclude PID must be an integer: ${part} (Remap tab)`);
      }
      if (pid < 32 || pid > 8190) {
        throw new Error(`Exclude PID must be between 32 and 8190: ${part} (Remap tab)`);
      }
    });
    config['filter~'] = parts.join(',');
  }

  const serviceType = toNumber(elements.streamServiceType && elements.streamServiceType.value);
  if (serviceType !== undefined) {
    if (serviceType < 0 || serviceType > 255) {
      throw new Error('Service type must be between 0 and 255 (Service tab)');
    }
    config.service_type_id = serviceType;
  }

  const codepage = (elements.streamServiceCodepage && elements.streamServiceCodepage.value || '').trim();
  if (codepage) config.codepage = codepage;

  const provider = (elements.streamServiceProvider && elements.streamServiceProvider.value || '').trim();
  if (provider) config.service_provider = provider;

  const serviceName = (elements.streamServiceName && elements.streamServiceName.value || '').trim();
  if (serviceName) config.service_name = serviceName;

  const hbbtvUrl = (elements.streamServiceHbbtv && elements.streamServiceHbbtv.value || '').trim();
  if (hbbtvUrl) config.hbbtv_url = hbbtvUrl;

  if (elements.streamServiceCas && elements.streamServiceCas.checked) {
    config.cas = true;
  }

  const mptsConfig = { general: {}, nit: {}, advanced: {} };
  const mptsGeneral = mptsConfig.general;
  const mptsNit = mptsConfig.nit;
  const mptsAdv = mptsConfig.advanced;

  const country = (elements.mptsCountry && elements.mptsCountry.value || '').trim();
  if (country) mptsGeneral.country = country;
  const utcOffset = toNumber(elements.mptsUtcOffset && elements.mptsUtcOffset.value);
  if (utcOffset !== undefined) mptsGeneral.utc_offset = utcOffset;
  const dstTimeOfChange = (elements.mptsDstTimeOfChange && elements.mptsDstTimeOfChange.value || '').trim();
  const dstNextOffset = toNumber(elements.mptsDstNextOffset && elements.mptsDstNextOffset.value);
  if (dstTimeOfChange || dstNextOffset !== undefined) {
    mptsGeneral.dst = {};
    if (dstTimeOfChange) mptsGeneral.dst.time_of_change = dstTimeOfChange;
    if (dstNextOffset !== undefined) mptsGeneral.dst.next_offset_minutes = dstNextOffset;
  }
  const networkId = toNumber(elements.mptsNetworkId && elements.mptsNetworkId.value);
  if (networkId !== undefined) mptsGeneral.network_id = networkId;
  const networkName = (elements.mptsNetworkName && elements.mptsNetworkName.value || '').trim();
  if (networkName) mptsGeneral.network_name = networkName;
  const providerName = (elements.mptsProviderName && elements.mptsProviderName.value || '').trim();
  if (providerName) mptsGeneral.provider_name = providerName;
  const mptsCodepage = (elements.mptsCodepage && elements.mptsCodepage.value || '').trim();
  if (mptsCodepage) mptsGeneral.codepage = mptsCodepage;
  const tsid = toNumber(elements.mptsTsid && elements.mptsTsid.value);
  if (tsid !== undefined) mptsGeneral.tsid = tsid;
  const onid = toNumber(elements.mptsOnid && elements.mptsOnid.value);
  if (onid !== undefined) mptsGeneral.onid = onid;

  const delivery = (elements.mptsDelivery && elements.mptsDelivery.value || '').trim();
  if (delivery) mptsNit.delivery = delivery;
  const frequency = toNumber(elements.mptsFrequency && elements.mptsFrequency.value);
  if (frequency !== undefined) mptsNit.frequency = frequency;
  const symbolrate = toNumber(elements.mptsSymbolrate && elements.mptsSymbolrate.value);
  if (symbolrate !== undefined) mptsNit.symbolrate = symbolrate;
  const bandwidth = toNumber(elements.mptsBandwidth && elements.mptsBandwidth.value);
  if (bandwidth !== undefined) mptsNit.bandwidth = bandwidth;
  const orbitalPosition = (elements.mptsOrbitalPosition && elements.mptsOrbitalPosition.value || '').trim();
  if (orbitalPosition) mptsNit.orbital_position = orbitalPosition;
  const polarization = (elements.mptsPolarization && elements.mptsPolarization.value || '').trim();
  if (polarization) mptsNit.polarization = polarization;
  const rolloff = (elements.mptsRolloff && elements.mptsRolloff.value || '').trim();
  if (rolloff) mptsNit.rolloff = rolloff;
  const fec = (elements.mptsFec && elements.mptsFec.value || '').trim();
  if (fec) mptsNit.fec = fec;
  const modulation = (elements.mptsModulation && elements.mptsModulation.value || '').trim();
  if (modulation) mptsNit.modulation = modulation;
  const networkSearch = (elements.mptsNetworkSearch && elements.mptsNetworkSearch.value || '').trim();
  if (networkSearch) mptsNit.network_search = networkSearch;
  const lcnTagRaw = (elements.mptsLcnTag && elements.mptsLcnTag.value || '').trim();
  if (lcnTagRaw) {
    const lcnTag = Number(lcnTagRaw);
    if (!Number.isFinite(lcnTag) || lcnTag < 1 || lcnTag > 255) {
      throw new Error('LCN descriptor tag must be between 1 and 255 (MPTS tab)');
    }
    mptsNit.lcn_descriptor_tag = lcnTag;
  }
  const lcnTagsRaw = (elements.mptsLcnTags && elements.mptsLcnTags.value || '').trim();
  if (lcnTagsRaw) {
    const parts = lcnTagsRaw.split(/[,\s]+/).filter(Boolean);
    const tags = parts.map((part) => Number(part));
    const invalid = tags.find((tag) => !Number.isFinite(tag) || tag < 1 || tag > 255);
    if (invalid !== undefined) {
      throw new Error('LCN descriptor tags must be between 1 and 255 (MPTS tab)');
    }
    mptsNit.lcn_descriptor_tags = tags;
  }
  const lcnVersion = toNumber(elements.mptsLcnVersion && elements.mptsLcnVersion.value);
  if (lcnVersion !== undefined) {
    if (lcnVersion < 0 || lcnVersion > 31) {
      throw new Error('LCN version must be between 0 and 31 (MPTS tab)');
    }
    mptsNit.lcn_version = lcnVersion;
  }

  const siInterval = toNumber(elements.mptsSiInterval && elements.mptsSiInterval.value);
  if (siInterval !== undefined) mptsAdv.si_interval_ms = siInterval;
  const targetBitrate = toNumber(elements.mptsTargetBitrate && elements.mptsTargetBitrate.value);
  if (targetBitrate !== undefined) mptsAdv.target_bitrate = targetBitrate;
  // Auto-probe: сохранить параметры автосканирования сервисов.
  if (elements.mptsAutoProbe && elements.mptsAutoProbe.checked) {
    mptsAdv.auto_probe = true;
  }
  const autoProbeDuration = toNumber(elements.mptsAutoProbeDuration && elements.mptsAutoProbeDuration.value);
  if (autoProbeDuration !== undefined) {
    if (autoProbeDuration < 1 || autoProbeDuration > 10) {
      throw new Error('Auto-probe duration must be between 1 and 10 sec (MPTS tab)');
    }
    mptsAdv.auto_probe_duration_sec = autoProbeDuration;
  }
  if (elements.mptsPcrRestamp && elements.mptsPcrRestamp.checked) {
    mptsAdv.pcr_restamp = true;
  }
  if (elements.mptsPcrSmoothing && elements.mptsPcrSmoothing.checked) {
    mptsAdv.pcr_smoothing = true;
  }
  const pcrAlpha = toNumber(elements.mptsPcrSmoothAlpha && elements.mptsPcrSmoothAlpha.value);
  if (pcrAlpha !== undefined) {
    if (pcrAlpha <= 0 || pcrAlpha > 100) {
      throw new Error('PCR smooth alpha must be in (0..1] or (1..100] (MPTS tab)');
    }
    mptsAdv.pcr_smooth_alpha = pcrAlpha;
  }
  const pcrMax = toNumber(elements.mptsPcrSmoothMax && elements.mptsPcrSmoothMax.value);
  if (pcrMax !== undefined) {
    if (pcrMax <= 0) {
      throw new Error('PCR smooth max offset must be > 0 (MPTS tab)');
    }
    mptsAdv.pcr_smooth_max_offset_ms = pcrMax;
  }
  const patVersion = toNumber(elements.mptsPatVersion && elements.mptsPatVersion.value);
  if (patVersion !== undefined) mptsAdv.pat_version = patVersion;
  const nitVersion = toNumber(elements.mptsNitVersion && elements.mptsNitVersion.value);
  if (nitVersion !== undefined) mptsAdv.nit_version = nitVersion;
  const catVersion = toNumber(elements.mptsCatVersion && elements.mptsCatVersion.value);
  if (catVersion !== undefined) mptsAdv.cat_version = catVersion;
  const sdtVersion = toNumber(elements.mptsSdtVersion && elements.mptsSdtVersion.value);
  if (sdtVersion !== undefined) mptsAdv.sdt_version = sdtVersion;
  if (elements.mptsDisableAutoremap && elements.mptsDisableAutoremap.checked) {
    mptsAdv.disable_auto_remap = true;
  }
  if (elements.mptsPassNit && elements.mptsPassNit.checked) {
    mptsAdv.pass_nit = true;
  }
  if (elements.mptsPassSdt && elements.mptsPassSdt.checked) {
    mptsAdv.pass_sdt = true;
  }
  if (elements.mptsPassEit && elements.mptsPassEit.checked) {
    mptsAdv.pass_eit = true;
  }
  if (elements.mptsPassCat && elements.mptsPassCat.checked) {
    mptsAdv.pass_cat = true;
  }
  if (elements.mptsPassTdt && elements.mptsPassTdt.checked) {
    mptsAdv.pass_tdt = true;
  }
  if (elements.mptsDisableTot && elements.mptsDisableTot.checked) {
    mptsAdv.disable_tot = true;
  }
  const eitSource = toNumber(elements.mptsEitSource && elements.mptsEitSource.value);
  if (eitSource !== undefined) {
    if (eitSource < 1) {
      throw new Error('EIT source must be >= 1 (MPTS tab)');
    }
    mptsAdv.eit_source = eitSource;
  }
  const eitTableIds = (elements.mptsEitTableIds && elements.mptsEitTableIds.value || '').trim();
  if (eitTableIds) {
    mptsAdv.eit_table_ids = eitTableIds;
  }
  const catSource = toNumber(elements.mptsCatSource && elements.mptsCatSource.value);
  if (catSource !== undefined) {
    if (catSource < 1) {
      throw new Error('CAT source must be >= 1 (MPTS tab)');
    }
    mptsAdv.cat_source = catSource;
  }
  if (elements.mptsStrictPnr && elements.mptsStrictPnr.checked) {
    mptsAdv.strict_pnr = true;
  }
  if (elements.mptsSptsOnly) {
    if (!elements.mptsSptsOnly.checked) {
      mptsAdv.spts_only = false;
    } else if (mptsEnabled) {
      mptsAdv.spts_only = true;
    }
  }

  if (mptsEnabled || hasAnyValue(mptsConfig)) {
    config.mpts_config = mptsConfig;
  }
  if (mptsEnabled || (mptsServices && mptsServices.length)) {
    const normalizedServices = mptsServices.map((service) => {
      const entry = { input: service.input };
      if (service.service_name) entry.service_name = service.service_name;
      if (service.service_provider) entry.service_provider = service.service_provider;
      const pnr = toNumber(service.pnr);
      if (pnr !== undefined) entry.pnr = pnr;
      const lcn = toNumber(service.lcn);
      if (lcn !== undefined) entry.lcn = lcn;
      const typeId = toNumber(service.service_type_id);
      if (typeId !== undefined) entry.service_type_id = typeId;
      if (service.scrambled === true) entry.scrambled = true;
      if (service.name) entry.name = service.name;
      return entry;
    });
    config.mpts_services = normalizedServices;
  }

  const epgId = (elements.streamEpgId && elements.streamEpgId.value || '').trim();
  const epgFormat = (elements.streamEpgFormat && elements.streamEpgFormat.value || '').trim();
  const epgDestination = (elements.streamEpgDestination && elements.streamEpgDestination.value || '').trim();
  const epgCodepage = (elements.streamEpgCodepage && elements.streamEpgCodepage.value || '').trim();
  if (epgId || epgFormat || epgDestination || epgCodepage) {
    if (!epgId) {
      throw new Error('EPG channel ID is required (EPG tab)');
    }
    config.epg = { xmltv_id: epgId };
    if (epgFormat) config.epg.format = epgFormat;
    if (epgDestination) config.epg.destination = epgDestination;
    if (epgCodepage) config.epg.codepage = epgCodepage;
  }

  if (elements.streamNoSdt && elements.streamNoSdt.checked) {
    config.no_sdt = true;
  }
  if (elements.streamNoEit && elements.streamNoEit.checked) {
    config.no_eit = true;
  }
  if (elements.streamPassSdt && elements.streamPassSdt.checked) {
    config.pass_sdt = true;
  }
  if (elements.streamPassEit && elements.streamPassEit.checked) {
    config.pass_eit = true;
  }
  if (elements.streamNoReload && elements.streamNoReload.checked) {
    config.no_reload = true;
  }

  if (elements.streamBackupType) {
    const backupType = elements.streamBackupType.value.trim();
    if (backupType) config.backup_type = backupType;
  }
  if (elements.streamBackupWarmMax) {
    const warmMax = toNumber(elements.streamBackupWarmMax.value);
    if (warmMax !== undefined) config.backup_active_warm_max = warmMax;
  }
  if (elements.streamBackupInitialDelay) {
    const initialDelay = toNumber(elements.streamBackupInitialDelay.value);
    if (initialDelay !== undefined) config.backup_initial_delay = initialDelay;
  }
  if (elements.streamBackupStartDelay) {
    const startDelay = toNumber(elements.streamBackupStartDelay.value);
    if (startDelay !== undefined) config.backup_start_delay = startDelay;
  }
  if (elements.streamBackupReturnDelay) {
    const returnDelay = toNumber(elements.streamBackupReturnDelay.value);
    if (returnDelay !== undefined) config.backup_return_delay = returnDelay;
  }
  if (elements.streamBackupStopInactiveSec) {
    const stopInactive = toNumber(elements.streamBackupStopInactiveSec.value);
    if (stopInactive !== undefined) config.stop_if_all_inactive_sec = stopInactive;
  }
  if (elements.streamStableOkSec) {
    const stableOk = toNumber(elements.streamStableOkSec.value);
    if (stableOk !== undefined) config.stable_ok_sec = stableOk;
  }
  if (elements.streamNoDataTimeoutSec) {
    const noDataTimeout = toNumber(elements.streamNoDataTimeoutSec.value);
    if (noDataTimeout !== undefined && noDataTimeout < 1) {
      throw new Error('No data timeout must be >= 1 second (Backup tab)');
    }
    if (noDataTimeout !== undefined) config.no_data_timeout_sec = noDataTimeout;
  }
  if (elements.streamProbeIntervalSec) {
    const probeInterval = toNumber(elements.streamProbeIntervalSec.value);
    if (probeInterval !== undefined) config.probe_interval_sec = probeInterval;
  }

  if (config.backup_type === 'active_stop_if_all_inactive' &&
    typeof config.stop_if_all_inactive_sec === 'number' &&
    config.stop_if_all_inactive_sec < 5) {
    throw new Error('Stop if all inactive must be >= 5 seconds (Backup tab)');
  }

  if (isTranscode) {
    const transcode = {};
    if (elements.streamTranscodeEngine) {
      const engine = elements.streamTranscodeEngine.value.trim();
      if (engine) transcode.engine = engine;
    }
    const gpuDevice = toNumber(elements.streamTranscodeGpuDevice && elements.streamTranscodeGpuDevice.value);
    if (gpuDevice !== undefined) transcode.gpu_device = gpuDevice;
    const ffmpegPath = (elements.streamTranscodeFfmpegPath && elements.streamTranscodeFfmpegPath.value || '').trim();
    if (ffmpegPath) transcode.ffmpeg_path = ffmpegPath;
    const logFile = (elements.streamTranscodeLogFile && elements.streamTranscodeLogFile.value || '').trim();
    if (logFile) transcode.log_file = logFile;
    if (elements.streamTranscodeLogMain && elements.streamTranscodeLogMain.checked) {
      transcode.log_to_main = true;
    }
    const inputProbeUdp = Boolean(elements.streamTranscodeInputProbeUdp && elements.streamTranscodeInputProbeUdp.checked);
    if (inputProbeUdp) {
      transcode.input_probe_udp = true;
    }
    if (elements.streamTranscodeInputProbeRestart && elements.streamTranscodeInputProbeRestart.checked) {
      transcode.input_probe_restart = true;
    }
    const perOutput = Boolean(elements.streamTranscodeProcessPerOutput && elements.streamTranscodeProcessPerOutput.checked);
    if (perOutput) {
      transcode.process_per_output = true;
    }
    if (perOutput && elements.streamTranscodeSeamlessUdpProxy && elements.streamTranscodeSeamlessUdpProxy.checked) {
      transcode.seamless_udp_proxy = true;
    }

    const globalArgs = linesToArgs(elements.streamTranscodeGlobalArgs && elements.streamTranscodeGlobalArgs.value);
    if (globalArgs.length) transcode.ffmpeg_global_args = globalArgs;
    const decoderArgs = linesToArgs(elements.streamTranscodeDecoderArgs && elements.streamTranscodeDecoderArgs.value);
    if (decoderArgs.length) transcode.decoder_args = decoderArgs;
    const commonArgs = linesToArgs(elements.streamTranscodeCommonArgs && elements.streamTranscodeCommonArgs.value);
    if (commonArgs.length) transcode.common_output_args = commonArgs;

    const baseWatchdog = state.transcodeWatchdogDefaults || normalizeOutputWatchdog(null, TRANSCODE_WATCHDOG_DEFAULTS);
    const tcOutputs = state.transcodeOutputs.map((output) => {
      const cleaned = {};
      const name = (output && output.name || '').trim();
      const url = (output && output.url || '').trim();
      const vf = (output && output.vf || '').trim();
      const vcodec = (output && output.vcodec || '').trim();
      const acodec = (output && output.acodec || '').trim();

      if (name) cleaned.name = name;
      if (url) cleaned.url = url;
      if (vf) cleaned.vf = vf;
      if (vcodec) cleaned.vcodec = vcodec;
      if (acodec) cleaned.acodec = acodec;

      const vArgs = cleanArgList(output && output.v_args);
      if (vArgs.length) cleaned.v_args = vArgs;
      const aArgs = cleanArgList(output && output.a_args);
      if (aArgs.length) cleaned.a_args = aArgs;
      const formatArgs = cleanArgList(output && output.format_args);
      if (formatArgs.length) cleaned.format_args = formatArgs;
      const metadata = cleanArgList(output && output.metadata);
      if (metadata.length) cleaned.metadata = metadata;

      const watchdog = normalizeOutputWatchdog(output && output.watchdog, baseWatchdog);
      cleaned.watchdog = watchdog;

      return cleaned;
    });
    tcOutputs.forEach(validateTranscodeOutput);
    if (!tcOutputs.length) {
      throw new Error('Transcode outputs are required (Transcode tab)');
    }
    transcode.outputs = tcOutputs;

    config.transcode = transcode;
  }

  return { id, enabled, config };
}

function updateTileInputs(tile, stats) {
  const container = tile.querySelector('[data-role="tile-inputs"]');
  if (!container) return;
  if (stats && stats.transcode_state) {
    container.innerHTML = '';
    return;
  }
  const inputs = Array.isArray(stats && stats.inputs) ? stats.inputs : [];
  const activeIndex = getActiveInputIndex(stats);
  renderTileInputs(container, inputs, activeIndex);
}

function updateTileMptsMeta(tile, stream, stats) {
  const meta = tile.querySelector('[data-role="tile-mpts-meta"]');
  if (!meta) return;
  const isMpts = stream && stream.config && stream.config.mpts === true;
  if (!isMpts) {
    meta.classList.add('is-hidden');
    meta.textContent = 'MPTS: -';
    return;
  }
  const mpts = stats && stats.mpts_stats;
  if (!mpts) {
    meta.classList.add('is-hidden');
    meta.textContent = 'MPTS: -';
    return;
  }
  const bitrate = formatBitrateBps(mpts.bitrate_bps);
  const nullPct = formatPercentOneDecimal(mpts.null_percent);
  const psi = Number.isFinite(Number(mpts.psi_interval_ms)) ? `${Math.round(mpts.psi_interval_ms)} ms` : '-';
  meta.textContent = `MPTS: ${bitrate} • null ${nullPct} • PSI ${psi}`;
  meta.classList.remove('is-hidden');
}

function updateTiles() {
  if (state.viewMode === 'table') {
    updateStreamTableRows();
    return;
  }
  if (state.viewMode === 'compact') {
    updateStreamCompactRows();
    return;
  }
  $$('.tile').forEach((tile) => {
    const id = tile.dataset.id;
    applyTileUiState(tile);
    const stream = state.streamIndex[id];
    const enabled = stream ? stream.enabled !== false : tile.dataset.enabled === '1';
    tile.dataset.enabled = enabled ? '1' : '0';
    const stats = state.stats[id] || {};
    const transcodeState = stats.transcode_state;
    const transcode = stats.transcode || {};
    const isRunning = transcodeState
      ? transcodeState === 'RUNNING'
      : stats.on_air === true;
    const onAir = enabled && isRunning;
    const rateEl = tile.querySelector('.tile-rate');
    const metaEl = tile.querySelector('.tile-meta');
    const inputs = Array.isArray(stats.inputs) ? stats.inputs : [];
    const activeIndex = getActiveInputIndex(stats);
    const activeLabel = getActiveInputLabel(inputs, activeIndex);
    const statusInfo = stream
      ? getStreamStatusInfo(stream, stats)
      : {
        label: enabled ? (onAir ? 'Online' : 'Offline') : 'Disabled',
        className: enabled ? (onAir ? 'ok' : 'warn') : 'disabled',
      };

    if (rateEl) {
      if (transcodeState) {
        rateEl.textContent = formatTranscodeBitrates(transcode);
      } else {
        rateEl.textContent = formatBitrate(stats.bitrate || 0);
      }
      rateEl.classList.toggle('warn', enabled && !onAir);
      rateEl.classList.toggle('disabled', !enabled);
    }
    if (metaEl) {
      if (!enabled) {
        metaEl.textContent = 'Disabled';
      } else if (transcodeState) {
        if (transcodeState === 'ERROR') {
          const alertMessage = formatTranscodeAlert(transcode.last_alert);
          const fallback = transcode.last_error || 'Transcode failed';
          metaEl.textContent = `Transcode error: ${alertMessage || fallback}`;
        } else if (transcodeState === 'STARTING') {
          metaEl.textContent = 'Pre-probe in progress...';
        } else if (transcodeState === 'RESTARTING') {
          const alertMessage = formatTranscodeAlert(transcode.last_alert);
          metaEl.textContent = alertMessage
            ? `Restarting: ${alertMessage}`
            : 'Transcode: RESTARTING';
        } else {
          let suffix = '';
          if (transcode.switch_warmup) {
            const warm = transcode.switch_warmup;
            if (warm.done && !warm.ok) {
              suffix = ' (warmup failed)';
            } else if (warm.ready) {
              const idr = warm.require_idr ? (warm.idr_seen ? ' IDR' : ' no-IDR') : '';
              const stable = warm.stable_ok ? ' stable' : ' unstable';
              suffix = ` (warmup ready${stable}${idr})`;
            } else {
              suffix = ' (warmup running)';
            }
          }
          metaEl.textContent = `Transcode: ${transcodeState}${suffix}`;
        }
      } else {
        metaEl.textContent = activeLabel ? `Active input: ${activeLabel}` : (onAir ? 'Active' : 'Inactive');
      }
    }

    const compactStatus = tile.querySelector('[data-role="tile-compact-status"]');
    if (compactStatus) {
      compactStatus.className = `tile-compact-status stream-status-badge ${statusInfo.className}`;
      const statusLabel = compactStatus.querySelector('[data-role="tile-compact-status-label"]');
      if (statusLabel) statusLabel.textContent = statusInfo.label;
    }
    const compactInput = tile.querySelector('[data-role="tile-compact-input"]');
    if (compactInput) {
      compactInput.textContent = activeLabel ? `Active input: ${activeLabel}` : 'Active input: -';
      const activeInput = Number.isFinite(activeIndex) ? inputs[activeIndex] : null;
      compactInput.title = activeInput && activeInput.url ? activeInput.url : '';
    }
    const compactSummary = tile.querySelector('[data-role="tile-compact-input-summary"]');
    if (compactSummary) {
      compactSummary.textContent = formatInputSummary(inputs, activeIndex);
    }

    updateTileInputs(tile, stats);
    updateTileMptsMeta(tile, stream, stats);
    tile.classList.toggle('ok', enabled && onAir);
    tile.classList.toggle('warn', enabled && !onAir);
    tile.classList.toggle('disabled', !enabled);
  });
  scheduleAutoFit(elements.dashboardStreams);
}

function formatTranscodeAlert(alert) {
  if (!alert || !alert.message) return '';
  if (alert.code === 'TRANSCODE_CONFIG_ERROR') {
    return `Config error: ${alert.message}`;
  }
  if (alert.code === 'TRANSCODE_GPU_UNAVAILABLE') {
    return `${alert.message}. Switch engine to CPU or install NVIDIA drivers.`;
  }
  if (alert.code === 'TRANSCODE_SPAWN_FAILED') {
    return `${alert.message}. Check ffmpeg path and permissions.`;
  }
  if (alert.code === 'TRANSCODE_UNSUPPORTED') {
    return `${alert.message}. This build does not support transcode.`;
  }
  if (alert.code === 'TRANSCODE_STALL') {
    return `${alert.message}. Check input URL and source availability.`;
  }
  if (alert.code === 'TRANSCODE_PROBE_FAILED') {
    return `${alert.message}. Check output URL and firewall rules.`;
  }
  if (alert.code === 'TRANSCODE_LOW_BITRATE') {
    return `${alert.message}. Output bitrate stayed below the threshold.`;
  }
  if (alert.code === 'TRANSCODE_EXIT') {
    return `${alert.message}. Check ffmpeg logs and output params.`;
  }
  if (alert.code === 'TRANSCODE_ERRORS_RATE') {
    return `${alert.message}. Source may be corrupted or unstable.`;
  }
  if (alert.code === 'TRANSCODE_AV_DESYNC') {
    return `${alert.message}. Try adjusting watchdog or source timestamps.`;
  }
  if (alert.code === 'TRANSCODE_RESTART_LIMIT') {
    return `${alert.message}. Reduce errors or increase restart limits.`;
  }
  if (alert.code === 'TRANSCODE_WARMUP_FAIL') {
    return `${alert.message}. Warmup failed; check input health and IDR availability.`;
  }
  if (alert.code === 'TRANSCODE_WARMUP_TIMEOUT') {
    return `${alert.message}. Warmup timed out; input may be stalled.`;
  }
  if (alert.code === 'TRANSCODE_WARMUP_STOP') {
    return `${alert.message}. Warmup stopped before completion.`;
  }
  if (alert.code === 'TRANSCODE_CUTOVER_START') {
    return `Cutover started: ${alert.message}`;
  }
  if (alert.code === 'TRANSCODE_CUTOVER_OK') {
    return `Cutover OK: ${alert.message}`;
  }
  if (alert.code === 'TRANSCODE_CUTOVER_FAIL') {
    return `Cutover failed: ${alert.message}`;
  }
  if (alert.code === 'TRANSCODE_PROXY_UNAVAILABLE') {
    return `${alert.message}. Missing udp_switch/udp_output modules.`;
  }
  if (alert.code === 'TRANSCODE_PROXY_FAILED') {
    return `Proxy failed: ${alert.message}`;
  }
  return alert.message;
}

function formatTranscodeRestartMeta(meta) {
  if (!meta || typeof meta !== 'object') return '';
  const parts = [];
  if (Number.isFinite(meta.output_index)) {
    parts.push(`output #${meta.output_index}`);
  }
  if (meta.reason) parts.push(meta.reason);
  if (meta.detail) parts.push(meta.detail);
  if (Number.isFinite(meta.desync_ms)) {
    parts.push(`desync ${Math.round(meta.desync_ms)}ms`);
  }
  if (Number.isFinite(meta.bitrate_kbps)) {
    parts.push(`${Math.round(meta.bitrate_kbps)} Kbit/s`);
  }
  if (meta.error_line) parts.push(meta.error_line);
  return parts.join(', ');
}

function formatTranscodeRestartSummary(transcode) {
  if (!transcode || !transcode.restart_reason_code) return '';
  const meta = formatTranscodeRestartMeta(transcode.restart_reason_meta);
  return meta
    ? `${transcode.restart_reason_code} (${meta})`
    : transcode.restart_reason_code;
}

function formatWarmupSummary(warmup) {
  if (!warmup) return '';
  const target = Number.isFinite(warmup.target) ? `#${warmup.target}` : '#?';
  const url = warmup.target_url ? ` (${shortInputLabel(warmup.target_url)})` : '';
  const state = warmup.done
    ? (warmup.ok ? 'OK' : 'FAILED')
    : (warmup.ready ? 'READY' : 'RUNNING');
  const parts = [`Warmup ${target}${url}: ${state}`];
  if (warmup.require_idr) {
    parts.push(warmup.idr_seen ? 'IDR:yes' : 'IDR:no');
  }
  if (warmup.stable_ok !== undefined) {
    parts.push(warmup.stable_ok ? 'Stable:yes' : 'Stable:no');
  }
  if (Number.isFinite(warmup.last_out_time_ms)) {
    parts.push(`out_time_ms:${Math.round(warmup.last_out_time_ms)}`);
  }
  if (Number.isFinite(warmup.min_out_time_ms)) {
    parts.push(`min_ms:${Math.round(warmup.min_out_time_ms)}`);
  }
  if (Number.isFinite(warmup.stable_sec)) {
    parts.push(`stable_sec:${Math.round(warmup.stable_sec)}`);
  }
  if (warmup.error) {
    parts.push(`err:${warmup.error}`);
  }
  return parts.join(' • ');
}

function formatWorkerCutoverHint(cutover) {
  if (!cutover || typeof cutover !== 'object') return '';
  const state = (cutover.state ? String(cutover.state) : '').toUpperCase();
  if (!state) return '';

  if (state === 'STARTED') {
    const started = cutover.started_at ? formatTimestamp(cutover.started_at) : '';
    return started ? `cutover started ${started}` : 'cutover started';
  }

  if (state === 'OK') {
    const parts = ['cutover OK'];
    const dur = Number(cutover.duration_sec);
    if (Number.isFinite(dur)) parts.push(`${dur.toFixed(1)}s`);
    const sub = [];
    const ready = Number(cutover.ready_sec);
    if (Number.isFinite(ready)) sub.push(`ready ${ready.toFixed(1)}s`);
    const stable = Number(cutover.stable_ok_sec);
    if (Number.isFinite(stable)) sub.push(`stable ${stable.toFixed(1)}s`);
    if (sub.length) parts.push(`(${sub.join(', ')})`);
    return parts.join(' ');
  }

  if (state === 'FAIL') {
    const parts = ['cutover FAIL'];
    if (cutover.error) parts.push(String(cutover.error));
    const dur = Number(cutover.duration_sec);
    if (Number.isFinite(dur)) parts.push(`${dur.toFixed(1)}s`);
    return parts.join(' ');
  }

  return `cutover ${state}`;
}

function updateEditorTranscodeStatus() {
  if (!elements.streamTranscodeStatus) return;
  if (elements.streamTranscodeInputUrl) {
    elements.streamTranscodeInputUrl.textContent = '';
  }
  if (elements.streamTranscodeWarmup) {
    elements.streamTranscodeWarmup.textContent = '';
    elements.streamTranscodeWarmup.classList.remove('is-error');
  }
  if (elements.streamTranscodeRestart) {
    elements.streamTranscodeRestart.textContent = '';
    elements.streamTranscodeRestart.classList.remove('is-error');
  }
  if (elements.streamTranscodeWorkers) {
    elements.streamTranscodeWorkers.textContent = '';
    elements.streamTranscodeWorkers.classList.remove('is-error');
  }
  if (elements.streamTranscodeStderr) {
    elements.streamTranscodeStderr.textContent = '';
    elements.streamTranscodeStderr.classList.remove('is-error');
  }
  if (!state.editing || !state.editing.stream) {
    elements.streamTranscodeStatus.textContent = '';
    elements.streamTranscodeStatus.classList.remove('is-error');
    return;
  }
  const stream = state.editing.stream;
  const stats = state.stats[stream.id] || {};
  const transcode = stats.transcode || {};
  const transcodeState = stats.transcode_state || transcode.state;
  if (elements.streamTranscodeInputUrl) {
    const inputUrl = transcode.ffmpeg_input_url || transcode.active_input_url || '';
    elements.streamTranscodeInputUrl.textContent = inputUrl
      ? `Transcode input: ${inputUrl}`
      : '';
  }
  const rateLabel = (transcode.input_bitrate_kbps || transcode.output_bitrate_kbps)
    ? formatTranscodeBitrates(transcode)
    : '';
  if (!transcodeState) {
    elements.streamTranscodeStatus.textContent = '';
    elements.streamTranscodeStatus.classList.remove('is-error');
    return;
  }
  const restartSummary = formatTranscodeRestartSummary(transcode);
  if (elements.streamTranscodeRestart && restartSummary) {
    const prefix = (transcodeState === 'ERROR' || transcodeState === 'RESTARTING')
      ? 'Restart reason'
      : 'Last restart';
    elements.streamTranscodeRestart.textContent = `${prefix}: ${restartSummary}`;
    if (transcodeState === 'ERROR' || transcodeState === 'RESTARTING') {
      elements.streamTranscodeRestart.classList.add('is-error');
    }
  }
  if (elements.streamTranscodeWarmup) {
    const warmupSummary = formatWarmupSummary(transcode && transcode.switch_warmup);
    if (warmupSummary) {
      elements.streamTranscodeWarmup.textContent = warmupSummary;
      if (transcodeState === 'ERROR') {
        elements.streamTranscodeWarmup.classList.add('is-error');
      }
    }
  }
  if (elements.streamTranscodeWorkers) {
    const workers = Array.isArray(transcode.workers) ? transcode.workers : [];
    if (workers.length) {
      const lines = [`Workers: ${workers.length}`];
      workers.forEach((worker) => {
        if (!worker) return;
        const index = Number.isFinite(worker.output_index) ? worker.output_index : '?';
        const state = worker.state || 'n/a';
        const parts = [`#${index} ${state}`];
        if (worker.pid) parts.push(`pid ${worker.pid}`);
        if (worker.restart_reason_code) parts.push(`restart ${worker.restart_reason_code}`);
        const cutoverHint = formatWorkerCutoverHint(worker.last_cutover);
        if (cutoverHint) parts.push(cutoverHint);
        if (worker.proxy_enabled) {
          const port = Number(worker.proxy_listen_port) || 0;
          parts.push(port ? `proxy 127.0.0.1:${port}` : 'proxy enabled');
          const src = worker.proxy_active_source || null;
          if (src && src.addr && src.port) {
            parts.push(`src ${src.addr}:${src.port}`);
          }
          if (Number.isFinite(worker.proxy_senders_count)) {
            parts.push(`senders ${worker.proxy_senders_count}`);
          }
        }
        lines.push(parts.join(' | '));
      });
      elements.streamTranscodeWorkers.textContent = lines.join('\n');
      if (transcodeState === 'ERROR') {
        elements.streamTranscodeWorkers.classList.add('is-error');
      }
    }
  }
  if (elements.streamTranscodeWarmup) {
    const warm = transcode && transcode.switch_warmup;
    if (warm) {
      const timeline = [
        warm.start_ts ? `start ${formatTimestamp(warm.start_ts)}` : null,
        warm.ready_ts ? `ready ${formatTimestamp(warm.ready_ts)}` : null,
        warm.last_progress_ts ? `last ${formatTimestamp(warm.last_progress_ts)}` : null,
        warm.deadline_ts ? `deadline ${formatTimestamp(warm.deadline_ts)}` : null,
      ].filter(Boolean);
      if (timeline.length) {
        elements.streamTranscodeWarmup.textContent += ` | ${timeline.join(' • ')}`;
      }
    }
  }
  if (elements.streamTranscodeStderr) {
    const tail = Array.isArray(transcode.stderr_tail) ? transcode.stderr_tail : [];
    if (tail.length) {
      const slice = tail.slice(-6);
      elements.streamTranscodeStderr.textContent = `FFmpeg stderr (tail):\n${slice.join('\n')}`;
      if (transcodeState === 'ERROR') {
        elements.streamTranscodeStderr.classList.add('is-error');
      }
    }
  }
  if (transcodeState === 'STARTING') {
    elements.streamTranscodeStatus.textContent = 'Pre-probe in progress...';
    elements.streamTranscodeStatus.classList.remove('is-error');
    return;
  }
  if (transcodeState === 'RUNNING') {
    const lastAlert = transcode && transcode.last_alert;
    const isCutover = lastAlert && typeof lastAlert.code === 'string' && lastAlert.code.startsWith('TRANSCODE_CUTOVER_');
    const cutoverHint = isCutover ? formatTranscodeAlert(lastAlert) : '';
    let text = rateLabel
      ? `Transcode active (${rateLabel})`
      : 'Transcode active';
    if (cutoverHint) {
      text += ` | ${cutoverHint}`;
    }
    elements.streamTranscodeStatus.textContent = text;
    elements.streamTranscodeStatus.classList.remove('is-error');
    return;
  }
  if (transcodeState === 'ERROR') {
    const alertMessage = formatTranscodeAlert(transcode.last_alert);
    const fallback = transcode.last_error || 'Transcode failed to start';
    elements.streamTranscodeStatus.textContent = `Transcode error: ${alertMessage || fallback}`;
    elements.streamTranscodeStatus.classList.add('is-error');
    return;
  }
  if (transcodeState === 'RESTARTING') {
    const alertMessage = formatTranscodeAlert(transcode.last_alert);
    elements.streamTranscodeStatus.textContent = alertMessage
      ? `Transcode restarting: ${alertMessage}`
      : 'Transcode restarting';
    elements.streamTranscodeStatus.classList.add('is-error');
    return;
  }
  elements.streamTranscodeStatus.textContent = `Transcode: ${transcodeState}`;
  elements.streamTranscodeStatus.classList.remove('is-error');
}

function updateEditorTranscodeOutputStatus() {
  if (!elements.transcodeOutputList) return;
  if (!state.editing || !state.editing.stream) return;
  const rows = elements.transcodeOutputList.querySelectorAll('.transcode-output-row');
  rows.forEach((row) => {
    const index = Number(row.dataset.index || 0);
    const output = state.transcodeOutputs[index];
    if (!output) return;
    const meta = row.querySelector('[data-role="transcode-output-monitor"]');
    if (meta) {
      meta.textContent = formatTranscodeOutputMonitorMeta(output, getTranscodeOutputStatus(index));
    }
  });
}

function updateEditorOutputStatus() {
  if (!state.editing || !state.editing.stream) return;
  const rows = elements.outputList.querySelectorAll('.output-row');
  rows.forEach((row) => {
    const index = Number(row.dataset.index || 0);
    const output = state.outputs[index];
    if (!output || String(output.format || '').toLowerCase() !== 'udp') return;
    const meta = row.querySelector('[data-role="output-audio-meta"]');
    if (!meta) return;
    const audioEl = meta.querySelector('[data-role="output-audio-type"]');
    const fixEl = meta.querySelector('[data-role="output-audio-fix"]');
    const info = getOutputAudioFixMeta(output, getEditingOutputStatus(index));
    if (audioEl) {
      audioEl.textContent = info.audioText;
      audioEl.className = `output-audio-status ${info.audioClass}`.trim();
    }
    if (fixEl) {
      fixEl.textContent = info.fixText;
      fixEl.className = `output-audio-status ${info.fixClass}`.trim();
    }
  });
}

function updateEditorMptsStatus() {
  if (!elements.mptsRuntime) return;
  if (!state.editing || !state.editing.stream) return;
  const enabled = elements.streamMpts && elements.streamMpts.checked;
  elements.mptsRuntime.classList.toggle('is-disabled', !enabled);
  const streamId = state.editing.stream.id;
  const stats = state.stats[streamId] || {};
  const mpts = stats.mpts_stats;

  if (!enabled) {
    // MPTS выключен — показываем заглушку.
    if (elements.mptsRuntimeBitrate) elements.mptsRuntimeBitrate.textContent = '-';
    if (elements.mptsRuntimeNull) elements.mptsRuntimeNull.textContent = '-';
    if (elements.mptsRuntimePsi) elements.mptsRuntimePsi.textContent = '-';
    if (elements.mptsRuntimeNote) elements.mptsRuntimeNote.textContent = 'Enable MPTS to see runtime stats.';
    return;
  }

  if (!mpts) {
    if (elements.mptsRuntimeBitrate) elements.mptsRuntimeBitrate.textContent = '-';
    if (elements.mptsRuntimeNull) elements.mptsRuntimeNull.textContent = '-';
    if (elements.mptsRuntimePsi) elements.mptsRuntimePsi.textContent = '-';
    if (elements.mptsRuntimeNote) elements.mptsRuntimeNote.textContent = 'No runtime stats yet (stream stopped or not running).';
    return;
  }

  if (elements.mptsRuntimeBitrate) elements.mptsRuntimeBitrate.textContent = formatBitrateBps(mpts.bitrate_bps);
  if (elements.mptsRuntimeNull) elements.mptsRuntimeNull.textContent = formatPercentOneDecimal(mpts.null_percent);
  if (elements.mptsRuntimePsi) {
    const psi = Number.isFinite(Number(mpts.psi_interval_ms)) ? `${Math.round(mpts.psi_interval_ms)} ms` : '-';
    elements.mptsRuntimePsi.textContent = psi;
  }
  if (elements.mptsRuntimeNote) elements.mptsRuntimeNote.textContent = 'Stats update on status polling.';
}

async function loadStreamStatus() {
  try {
    const data = await apiJson('/api/v1/stream-status');
    state.stats = data || {};
    updateTiles();
    updatePlayerMeta();
    updateEditorTranscodeStatus();
    updateEditorTranscodeOutputStatus();
    updateEditorOutputStatus();
    updateEditorMptsStatus();
  } catch (err) {
  }
}

function startStatusPolling() {
  if (state.statusTimer) {
    clearInterval(state.statusTimer);
  }
  state.statusTimer = setInterval(loadStreamStatus, POLL_STATUS_MS);
  loadStreamStatus();
}

function stopStatusPolling() {
  if (state.statusTimer) {
    clearInterval(state.statusTimer);
    state.statusTimer = null;
  }
}

function buildStreamModel(stream) {
  const stats = state.stats[stream.id] || {};
  const name = (stream.config && stream.config.name) || stream.id;
  const statusInfo = getStreamStatusInfo(stream, stats);
  const { activeInput, activeIndex } = getActiveInputStats(stats);
  const configInputs = normalizeOutputList(stream.config && stream.config.input);
  const fallbackInputUrl = configInputs.length ? String(configInputs[0]) : '';
  const inputUrl = (activeInput && activeInput.url) || fallbackInputUrl;
  const inputLabel = activeInput
    ? getInputLabel(activeInput, activeIndex || 0)
    : (inputUrl ? shortInputLabel(inputUrl) : 'n/a');
  let inputBitrateValue = stats.bitrate;
  if (activeInput) {
    const activeRate = Number.isFinite(activeInput.bitrate_kbps) ? activeInput.bitrate_kbps : activeInput.bitrate;
    if (Number.isFinite(activeRate)) {
      inputBitrateValue = activeRate;
    }
  }
  const inputBitrate = formatMaybeBitrate(inputBitrateValue);
  const inputUptime = (activeInput && Number.isFinite(activeInput.uptime_sec))
    ? formatUptime(activeInput.uptime_sec)
    : '-';

  const transcodeState = stats.transcode_state || '';
  const transcode = stats.transcode || {};
  const transcodeStatus = transcodeState ? transcodeState : 'DISABLED';
  const transcodeRates = transcodeState ? formatTranscodeBitrates(transcode) : 'In - / Out -';
  const transcodeError = transcodeState === 'ERROR'
    ? (formatTranscodeAlert(transcode.last_alert) || transcode.last_error || '')
    : '';

  const outputSummary = getOutputSummary(stream);
  const clients = Number.isFinite(stats.clients) ? stats.clients : null;
  const enabled = stream.enabled !== false;

  return {
    id: stream.id,
    name,
    statusInfo,
    inputUrl,
    inputLabel,
    inputBitrate,
    inputUptime,
    transcodeStatus,
    transcodeRates,
    transcodeError,
    outputSummary,
    clients,
    enabled,
    hasPreview: true,
  };
}

function buildStreamTableRow(stream) {
  const model = buildStreamModel(stream);
  const row = document.createElement('tr');
  row.className = 'stream-row';
  row.dataset.streamId = stream.id;

  const streamCell = createEl('td', 'col-stream');
  const streamWrap = createEl('div', 'stream-cell');
  const check = createEl('input');
  check.type = 'checkbox';
  check.dataset.action = 'select';
  const checkWrap = createEl('label', 'table-check');
  checkWrap.appendChild(check);

  const info = createEl('div', 'stream-info');
  const nameBtn = createEl('button', 'stream-cell-title text-link', model.name);
  nameBtn.dataset.action = 'edit';
  nameBtn.dataset.role = 'stream-name';
  const status = createEl('div', `stream-status-badge ${model.statusInfo.className}`);
  status.dataset.role = 'stream-status';
  const dot = createEl('span', 'stream-status-dot');
  const statusText = createEl('span', '', model.statusInfo.label);
  status.appendChild(dot);
  status.appendChild(statusText);
  const sub = createEl('div', 'stream-cell-sub');
  sub.appendChild(status);
  info.appendChild(nameBtn);
  info.appendChild(sub);

  streamWrap.appendChild(checkWrap);
  streamWrap.appendChild(info);
  streamCell.appendChild(streamWrap);

  const inputCell = createEl('td', 'col-input');
  const inputUrl = createEl('div', 'stream-input-url');
  inputUrl.dataset.role = 'stream-input-url';
  inputUrl.textContent = model.inputUrl || '-';
  if (model.inputUrl) inputUrl.title = model.inputUrl;
  const inputMeta = createEl('div', 'stream-cell-sub');
  inputMeta.dataset.role = 'stream-input-meta';
  inputMeta.textContent = `Active: ${model.inputLabel} • Uptime: ${model.inputUptime} • Bitrate: ${model.inputBitrate}`;
  inputCell.appendChild(inputUrl);
  inputCell.appendChild(inputMeta);

  const tcCell = createEl('td', 'col-transcode');
  const tcSummary = createEl('div', 'stream-transcode-summary');
  tcSummary.dataset.role = 'stream-transcode-summary';
  tcSummary.textContent = `Transcode: ${model.transcodeStatus}`;
  const tcMeta = createEl('div', 'stream-cell-sub');
  tcMeta.dataset.role = 'stream-transcode-meta';
  tcMeta.textContent = model.transcodeRates;
  if (model.transcodeError) {
    tcMeta.title = model.transcodeError;
  }
  tcCell.appendChild(tcSummary);
  tcCell.appendChild(tcMeta);

  const dvrCell = createEl('td', 'col-dvr');
  const dvrMeta = createEl('div', 'stream-cell-sub', 'Archive: disabled');
  dvrCell.appendChild(dvrMeta);

  const outputCell = createEl('td', 'col-output');
  const outputSummary = createEl('div', 'stream-output-summary');
  outputSummary.dataset.role = 'stream-output-summary';
  outputSummary.textContent = `Outputs: ${model.outputSummary}`;
  const outputMeta = createEl('div', 'stream-cell-sub');
  outputMeta.dataset.role = 'stream-output-meta';
  outputMeta.textContent = `Clients: ${model.clients !== null ? model.clients : '-'}`;

  const actions = createEl('div', 'stream-actions');
  const previewBtn = createEl('button', 'btn ghost', 'Play');
  previewBtn.dataset.action = 'play';
  const analyzeBtn = createEl('button', 'btn ghost', 'Analyze');
  analyzeBtn.dataset.action = 'analyze';
  const toggleBtn = createEl('button', 'btn ghost', model.enabled ? 'Disable' : 'Enable');
  toggleBtn.dataset.action = 'toggle';
  actions.appendChild(previewBtn);
  actions.appendChild(analyzeBtn);
  actions.appendChild(toggleBtn);

  outputCell.appendChild(outputSummary);
  outputCell.appendChild(outputMeta);
  outputCell.appendChild(actions);

  row.appendChild(streamCell);
  row.appendChild(inputCell);
  row.appendChild(tcCell);
  row.appendChild(dvrCell);
  row.appendChild(outputCell);

  return row;
}

function updateStreamTableRow(row, stream) {
  const model = buildStreamModel(stream);
  const nameBtn = row.querySelector('[data-role="stream-name"]');
  if (nameBtn) {
    nameBtn.textContent = model.name;
  }
  const status = row.querySelector('[data-role="stream-status"]');
  if (status) {
    status.className = `stream-status-badge ${model.statusInfo.className}`;
    const textNode = status.querySelector('span:last-child');
    if (textNode) textNode.textContent = model.statusInfo.label;
  }
  const inputUrl = row.querySelector('[data-role="stream-input-url"]');
  if (inputUrl) {
    inputUrl.textContent = model.inputUrl || '-';
    inputUrl.title = model.inputUrl || '';
  }
  const inputMeta = row.querySelector('[data-role="stream-input-meta"]');
  if (inputMeta) {
    inputMeta.textContent = `Active: ${model.inputLabel} • Uptime: ${model.inputUptime} • Bitrate: ${model.inputBitrate}`;
  }
  const tcSummary = row.querySelector('[data-role="stream-transcode-summary"]');
  if (tcSummary) {
    tcSummary.textContent = `Transcode: ${model.transcodeStatus}`;
  }
  const tcMeta = row.querySelector('[data-role="stream-transcode-meta"]');
  if (tcMeta) {
    tcMeta.textContent = model.transcodeRates;
    tcMeta.title = model.transcodeError || '';
  }
  const outputSummary = row.querySelector('[data-role="stream-output-summary"]');
  if (outputSummary) {
    outputSummary.textContent = `Outputs: ${model.outputSummary}`;
  }
  const outputMeta = row.querySelector('[data-role="stream-output-meta"]');
  if (outputMeta) {
    outputMeta.textContent = `Clients: ${model.clients !== null ? model.clients : '-'}`;
  }
  const previewBtn = row.querySelector('[data-action="play"]');
  if (previewBtn) {
    previewBtn.hidden = false;
  }
  const toggleBtn = row.querySelector('[data-action="toggle"]');
  if (toggleBtn) {
    toggleBtn.textContent = model.enabled ? 'Disable' : 'Enable';
  }
}

function renderStreamTable(list) {
  if (!elements.streamTableBody) return;
  elements.streamTableBody.innerHTML = '';
  state.streamTableRows = {};
  if (list.length === 0) {
    const row = document.createElement('tr');
    const cell = createEl('td', 'muted', 'No streams yet. Create the first one.');
    cell.colSpan = 5;
    row.appendChild(cell);
    elements.streamTableBody.appendChild(row);
    return;
  }
  list.forEach((stream) => {
    const row = buildStreamTableRow(stream);
    elements.streamTableBody.appendChild(row);
    state.streamTableRows[stream.id] = row;
  });
}

function updateStreamTableRows() {
  Object.keys(state.streamTableRows || {}).forEach((id) => {
    const stream = state.streamIndex[id];
    const row = state.streamTableRows[id];
    if (!stream || !row) return;
    updateStreamTableRow(row, stream);
  });
}

function buildStreamCompactRow(stream) {
  const model = buildStreamModel(stream);
  const row = createEl('div', 'stream-compact-row');
  row.dataset.streamId = stream.id;
  row.title = [
    model.name,
    `Status: ${model.statusInfo.label}`,
    `Input: ${model.inputUrl || '-'}`,
    `Input bitrate: ${model.inputBitrate}`,
    `Transcode: ${model.transcodeStatus}`,
    `Outputs: ${model.outputSummary}`,
  ].join('\n');

  const dot = createEl('span', `stream-status-dot ${model.statusInfo.className}`);
  const nameBtn = createEl('button', 'stream-compact-name', model.name);
  nameBtn.dataset.action = 'edit';
  const rate = createEl('div', 'stream-compact-rate', model.inputBitrate);
  const clients = createEl('div', 'stream-compact-clients', `Clients: ${model.clients !== null ? model.clients : '-'}`);
  const toggleBtn = createEl('button', 'btn ghost', model.enabled ? 'Disable' : 'Enable');
  toggleBtn.dataset.action = 'toggle';

  row.appendChild(dot);
  row.appendChild(nameBtn);
  row.appendChild(rate);
  row.appendChild(clients);
  row.appendChild(toggleBtn);
  return row;
}

function renderStreamCompact(list) {
  if (!elements.streamCompact) return;
  elements.streamCompact.innerHTML = '';
  state.streamCompactRows = {};
  if (list.length === 0) {
    const empty = createEl('div', 'panel', 'No streams yet. Create the first one.');
    elements.streamCompact.appendChild(empty);
    return;
  }
  list.forEach((stream) => {
    const row = buildStreamCompactRow(stream);
    elements.streamCompact.appendChild(row);
    state.streamCompactRows[stream.id] = row;
  });
}

function updateStreamCompactRows() {
  Object.keys(state.streamCompactRows || {}).forEach((id) => {
    const stream = state.streamIndex[id];
    const row = state.streamCompactRows[id];
    if (!stream || !row) return;
    const model = buildStreamModel(stream);
    const name = row.querySelector('.stream-compact-name');
    if (name) name.textContent = model.name;
    row.title = [
      model.name,
      `Status: ${model.statusInfo.label}`,
      `Input: ${model.inputUrl || '-'}`,
      `Input bitrate: ${model.inputBitrate}`,
      `Transcode: ${model.transcodeStatus}`,
      `Outputs: ${model.outputSummary}`,
    ].join('\n');
    const dot = row.querySelector('.stream-status-dot');
    if (dot) {
      dot.className = `stream-status-dot ${model.statusInfo.className}`;
    }
    const rate = row.querySelector('.stream-compact-rate');
    if (rate) rate.textContent = model.inputBitrate;
    const clients = row.querySelector('.stream-compact-clients');
    if (clients) clients.textContent = `Clients: ${model.clients !== null ? model.clients : '-'}`;
    const toggleBtn = row.querySelector('[data-action="toggle"]');
    if (toggleBtn) toggleBtn.textContent = model.enabled ? 'Disable' : 'Enable';
  });
}

function renderStreams() {
  if (autoFitObserver) {
    autoFitObserver.disconnect();
  }
  const filtered = state.streams.filter(isStreamVisible);

  rebuildStreamIndex(filtered);

  if (state.viewMode === 'table') {
    renderStreamTable(filtered);
    return;
  }
  if (state.viewMode === 'compact') {
    renderStreamCompact(filtered);
    return;
  }

  elements.dashboardStreams.innerHTML = '';
  if (filtered.length === 0) {
    const empty = createEl('div', 'panel', 'No streams yet. Create the first one.');
    empty.dataset.role = 'streams-empty';
    elements.dashboardStreams.appendChild(empty);
    return;
  }

  filtered.forEach((stream) => {
    const tile = buildStreamTile(stream);
    elements.dashboardStreams.appendChild(tile);
  });

  updateTiles();
}

function handleStreamAction(stream, actionName) {
  if (!stream || !actionName) return false;
  if (actionName === 'select') return true;
  if (actionName === 'edit') {
    openEditor(stream, false);
    return true;
  }
  if (actionName === 'play') {
    openPlayer(stream);
    return true;
  }
  if (actionName === 'analyze') {
    openAnalyze(stream);
    return true;
  }
  if (actionName === 'toggle') {
    toggleStream(stream).catch((err) => setStatus(err.message));
    return true;
  }
  if (actionName === 'delete') {
    deleteStream(stream).catch((err) => setStatus(err.message));
    return true;
  }
  return false;
}

function formatUptime(seconds) {
  const total = Math.max(0, Number(seconds) || 0);
  const hours = Math.floor(total / 3600);
  const mins = Math.floor(total / 60) % 60;
  return `${String(hours).padStart(2, '0')}:${String(mins).padStart(2, '0')}`;
}

function renderSessions() {
  const filterText = String(state.sessionFilterText || '').trim().toLowerCase();
  let sessions = state.sessions;
  if (filterText) {
    sessions = sessions.filter((session) => {
      const hay = [
        session.server,
        session.stream_name,
        session.stream_id,
        session.ip,
        session.login,
        session.user_agent,
      ].filter(Boolean).join(' ').toLowerCase();
      return hay.includes(filterText);
    });
  }

  const header = `
    <div class="table-row header">
      <div>Server</div>
      <div>Stream</div>
      <div>IP</div>
      <div>Login</div>
      <div>Uptime (hour:min)</div>
      <div>User-Agent</div>
      <div></div>
    </div>
  `;

  const fragment = document.createDocumentFragment();
  const headerRow = document.createElement('div');
  headerRow.className = 'table-row header';
  headerRow.innerHTML = `
    <div>Server</div>
    <div>Stream</div>
    <div>IP</div>
    <div>Login</div>
    <div>Uptime (hour:min)</div>
    <div>User-Agent</div>
    <div></div>
  `;
  fragment.appendChild(headerRow);
  const totalCount = state.sessions.length;
  const filteredCount = sessions.length;
  elements.sessionTotal.textContent = (filteredCount === totalCount)
    ? String(totalCount)
    : `${filteredCount}/${totalCount}`;

  if (filteredCount === 0) {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.innerHTML = filterText
      ? '<div class="muted">No sessions match the filter</div>'
      : '<div class="muted">No sessions yet</div>';
    fragment.appendChild(row);
    elements.sessionTable.innerHTML = '';
    elements.sessionTable.appendChild(fragment);
    return;
  }

  const renderRow = (session) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const uptime = formatUptime(Date.now() / 1000 - (session.started_at || 0));
    const cells = [
      session.server || '-',
      session.stream_name || session.stream_id || '-',
      session.ip || '-',
      session.login || '-',
      uptime,
      session.user_agent || '-',
    ];
    cells.forEach((value) => {
      const cell = document.createElement('div');
      cell.textContent = value;
      row.appendChild(cell);
    });
    const action = document.createElement('div');
    action.className = 'session-actions';

    const allowBtn = document.createElement('button');
    allowBtn.className = 'btn ghost tiny';
    allowBtn.dataset.action = 'allow-ip';
    allowBtn.dataset.ip = session.ip || '';
    allowBtn.textContent = 'Whitelist';
    allowBtn.disabled = !session.ip;

    const blockBtn = document.createElement('button');
    blockBtn.className = 'btn danger tiny';
    blockBtn.dataset.action = 'block-ip';
    blockBtn.dataset.ip = session.ip || '';
    blockBtn.textContent = 'Block';
    blockBtn.disabled = !session.ip;

    const button = document.createElement('button');
    button.className = 'icon-btn';
    button.dataset.action = 'disconnect';
    button.dataset.id = session.id;
    button.textContent = 'x';

    action.appendChild(allowBtn);
    action.appendChild(blockBtn);
    action.appendChild(button);
    row.appendChild(action);
    fragment.appendChild(row);
  };

  if (state.sessionGroupBy) {
    const groups = {};
    sessions.forEach((session) => {
      const label = session.stream_name || session.stream_id || 'Unknown stream';
      if (!groups[label]) {
        groups[label] = [];
      }
      groups[label].push(session);
    });
    Object.keys(groups).sort().forEach((label) => {
      const groupRow = document.createElement('div');
      groupRow.className = 'table-row group';
      groupRow.innerHTML = `<div>${label} (${groups[label].length})</div>`;
      fragment.appendChild(groupRow);
      groups[label].forEach(renderRow);
    });
  } else {
    sessions.forEach(renderRow);
  }
  elements.sessionTable.innerHTML = '';
  elements.sessionTable.appendChild(fragment);
}

function buildSessionQuery() {
  const params = [];
  const text = String(state.sessionFilterText || '').trim();
  if (text) {
    params.push(`text=${encodeURIComponent(text)}`);
  }
  const limit = toNumber(state.sessionLimit);
  if (limit) {
    params.push(`limit=${limit}`);
  }
  return params.length ? `?${params.join('&')}` : '';
}

function isActiveSession(session) {
  if (!session) return false;
  if (session.active === false) return false;
  if (session.ended_at || session.ended) return false;
  const status = session.status ? String(session.status).toLowerCase() : '';
  if (status && (status.includes('end') || status.includes('closed') || status.includes('inactive'))) {
    return false;
  }
  return true;
}

async function loadSessions() {
  try {
    const data = await apiJson(`/api/v1/sessions${buildSessionQuery()}`);
    const list = Array.isArray(data) ? data : [];
    state.sessions = list.filter(isActiveSession);
    renderSessions();
  } catch (err) {
    state.sessions = [];
    renderSessions();
  }
}

function startSessionPolling() {
  if (state.sessionPaused) {
    return;
  }
  if (state.sessionTimer) {
    clearInterval(state.sessionTimer);
  }
  state.sessionTimer = setInterval(loadSessions, POLL_SESSION_MS);
  loadSessions();
}

function stopSessionPolling() {
  if (state.sessionTimer) {
    clearInterval(state.sessionTimer);
    state.sessionTimer = null;
  }
}

function setSessionPaused(paused) {
  state.sessionPaused = paused;
  if (elements.sessionPause) {
    elements.sessionPause.textContent = paused ? 'Resume' : 'Pause';
  }
  if (paused) {
    stopSessionPolling();
  } else {
    startSessionPolling();
  }
}

function formatUserTime(ts) {
  if (!ts || Number(ts) <= 0) return '-';
  return formatLogTime(Number(ts));
}

function renderUsers() {
  if (!elements.usersTable) return;
  const header = `
    <div class="table-row header">
      <div>Login</div>
      <div>Role</div>
      <div>Status</div>
      <div>Created</div>
      <div>Last login IP</div>
      <div></div>
    </div>
  `;
  elements.usersTable.innerHTML = header;
  const users = state.users || [];
  if (elements.usersEmpty) {
    elements.usersEmpty.style.display = users.length ? 'none' : 'block';
  }
  if (!users.length) {
    return;
  }

  users.forEach((user) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    const cells = [
      user.username,
      user.is_admin ? 'Admin' : 'User',
      user.enabled ? 'Enabled' : 'Disabled',
      formatUserTime(user.created_at),
      user.last_login_ip || '-',
    ];
    cells.forEach((value) => {
      const cell = document.createElement('div');
      cell.textContent = value;
      row.appendChild(cell);
    });
    const actions = document.createElement('div');
    actions.className = 'user-actions';
    actions.innerHTML = `
      <button class="text-link" data-action="edit" data-user="${user.username}">Edit</button>
      <button class="text-link" data-action="reset" data-user="${user.username}">Reset</button>
      <button class="text-link" data-action="toggle" data-user="${user.username}">
        ${user.enabled ? 'Disable' : 'Enable'}
      </button>
    `;
    row.appendChild(actions);
    elements.usersTable.appendChild(row);
  });
}

async function loadUsers() {
  try {
    const data = await apiJson('/api/v1/users');
    state.users = Array.isArray(data) ? data : [];
    renderUsers();
  } catch (err) {
    state.users = [];
    renderUsers();
  }
}

function setUserOverlay(show) {
  if (!elements.userOverlay) return;
  setOverlay(elements.userOverlay, show);
}

function openUserEditor(user, mode) {
  state.userEditing = user;
  state.userMode = mode;
  elements.userError.textContent = '';
  elements.userTitle.textContent = mode === 'new'
    ? 'New user'
    : (mode === 'reset' ? `Reset password: ${user.username}` : `Edit user: ${user.username}`);

  elements.userUsername.value = user.username || '';
  elements.userPassword.value = '';
  elements.userAdmin.checked = !!user.is_admin;
  elements.userEnabled.checked = user.enabled !== false;
  elements.userComment.value = user.comment || '';

  const isNew = mode === 'new';
  const isReset = mode === 'reset';
  elements.userUsername.disabled = !isNew;
  elements.userFieldUsername.hidden = false;
  elements.userFieldAdmin.hidden = isReset;
  elements.userFieldEnabled.hidden = isReset;
  elements.userFieldComment.hidden = isReset;
  elements.userPassword.required = isNew || isReset;

  setUserOverlay(true);
}

async function saveUser() {
  const mode = state.userMode;
  const username = elements.userUsername.value.trim();
  const payload = {
    is_admin: elements.userAdmin.checked,
    enabled: elements.userEnabled.checked,
    comment: elements.userComment.value.trim(),
  };
  try {
    if (mode === 'new') {
      const password = elements.userPassword.value;
      await apiJson('/api/v1/users', {
        method: 'POST',
        body: JSON.stringify({
          username,
          password,
          is_admin: payload.is_admin,
          enabled: payload.enabled,
          comment: payload.comment,
        }),
      });
    } else if (mode === 'reset') {
      const password = elements.userPassword.value;
      await apiJson(`/api/v1/users/${encodeURIComponent(username)}/reset`, {
        method: 'POST',
        body: JSON.stringify({ password }),
      });
    } else {
      await apiJson(`/api/v1/users/${encodeURIComponent(username)}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
      if (elements.userPassword.value) {
        await apiJson(`/api/v1/users/${encodeURIComponent(username)}/reset`, {
          method: 'POST',
          body: JSON.stringify({ password: elements.userPassword.value }),
        });
      }
    }
    setUserOverlay(false);
    await loadUsers();
  } catch (err) {
    elements.userError.textContent = err.message;
  }
}

function closeUserEditor() {
  setUserOverlay(false);
}

function renderAccessLog() {
  const entries = state.accessLogEntries || [];
  const header = `
    <div class="table-row header">
      <div>Time</div>
      <div>Stream</div>
      <div>Protocol</div>
      <div>IP</div>
      <div>Event</div>
      <div>Info</div>
    </div>
  `;

  elements.accessTable.innerHTML = header;
  elements.accessTotal.textContent = String(entries.length);
  if (elements.accessCount) {
    elements.accessCount.textContent = String(entries.length);
  }

  if (!entries.length) {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.innerHTML = '<div class="muted">No access logs yet</div>';
    elements.accessTable.appendChild(row);
    return;
  }

  const fragment = document.createDocumentFragment();
  entries.forEach((entry) => {
    const row = document.createElement('div');
    row.className = 'table-row';
    row.title = entry.user_agent || '';
    const infoParts = [];
    if (entry.login) infoParts.push(`login: ${entry.login}`);
    if (entry.path) infoParts.push(entry.path);
    if (entry.reason) infoParts.push(entry.reason);
    const info = infoParts.join(' • ') || '-';
    const cells = [
      formatLogTime(entry.ts || 0),
      entry.stream_name || entry.stream_id || '-',
      (entry.protocol || '-').toUpperCase(),
      entry.ip || '-',
      (entry.event || '-').toUpperCase(),
      info,
    ];
    cells.forEach((value) => {
      const cell = document.createElement('div');
      cell.textContent = value;
      row.appendChild(cell);
    });
    fragment.appendChild(row);
  });
  elements.accessTable.appendChild(fragment);
}

function buildAccessLogQuery(since, limit) {
  const params = [`since=${since}`, `limit=${limit}`];
  const event = String(state.accessEventFilter || '').trim().toLowerCase();
  if (event && event !== 'all') {
    params.push(`event=${encodeURIComponent(event)}`);
  }
  const text = String(state.accessTextFilter || '').trim();
  if (text) {
    params.push(`text=${encodeURIComponent(text)}`);
  }
  return params.join('&');
}

function appendAccessLogEntries(entries) {
  if (!entries || entries.length === 0) {
    return;
  }
  state.accessLogEntries = state.accessLogEntries.concat(entries);
  const maxEntries = Math.max(50, Number(state.accessLimit) || 200);
  if (state.accessLogEntries.length > maxEntries) {
    state.accessLogEntries = state.accessLogEntries.slice(state.accessLogEntries.length - maxEntries);
  }
  renderAccessLog();
}

function renderAuditLog() {
  if (!elements.auditTable) return;
  const entries = state.auditEntries || [];
  const header = `
    <div class="table-row header">
      <div>Time</div>
      <div>Actor</div>
      <div>Action</div>
      <div>Target</div>
      <div>IP</div>
      <div>OK</div>
      <div>Message</div>
    </div>
  `;
  elements.auditTable.innerHTML = header;
  if (!entries.length) {
    const row = createEl('div', 'table-row');
    row.innerHTML = '<div class="muted">No audit entries yet</div>';
    elements.auditTable.appendChild(row);
    if (elements.auditCount) elements.auditCount.textContent = '0';
    if (elements.accessTotal) elements.accessTotal.textContent = '0';
    return;
  }
  const fragment = document.createDocumentFragment();
  entries.forEach((row) => {
    const tr = createEl('div', 'table-row');
    const ts = createEl('div', '', formatLogTime(row.ts || 0));
    const actor = createEl('div', '', row.actor_username || '-');
    const action = createEl('div', '', row.action || '-');
    const target = createEl('div', '', row.target_username || '-');
    const ip = createEl('div', '', row.ip || '-');
    const ok = createEl('div', '', row.ok ? 'yes' : 'no');
    const msg = createEl('div', '', row.message || '');
    const metaText = formatAuditMeta(row);
    if (metaText) {
      msg.appendChild(createEl('div', 'audit-meta muted', metaText));
    }
    tr.appendChild(ts);
    tr.appendChild(actor);
    tr.appendChild(action);
    tr.appendChild(target);
    tr.appendChild(ip);
    tr.appendChild(ok);
    tr.appendChild(msg);
    fragment.appendChild(tr);
  });
  elements.auditTable.appendChild(fragment);
  if (elements.auditCount) elements.auditCount.textContent = String(entries.length);
  if (elements.accessTotal) elements.accessTotal.textContent = String(entries.length);
}

function formatAuditMeta(row) {
  if (!row || !row.meta || typeof row.meta !== 'object') return '';
  const meta = row.meta;
  const parts = [];
  if (meta.plan_id) parts.push(`plan_id=${meta.plan_id}`);
  if (meta.mode) parts.push(`mode=${meta.mode}`);
  if (meta.diff_summary) {
    const summary = meta.diff_summary;
    if (summary && typeof summary === 'object') {
      const added = Number(summary.added || 0);
      const updated = Number(summary.updated || 0);
      const removed = Number(summary.removed || 0);
      parts.push(`diff +${added} ~${updated} -${removed}`);
    } else {
      parts.push(`diff=${String(summary).slice(0, 120)}`);
    }
  }
  if (meta.revision_id) parts.push(`rev=${meta.revision_id}`);
  return parts.join(' · ');
}

function buildAuditQuery(limit) {
  const params = [];
  const action = String(state.auditActionFilter || '').trim();
  const actor = String(state.auditActorFilter || '').trim();
  const ok = String(state.auditOkFilter || '').trim();
  if (action) params.push(`action=${encodeURIComponent(action)}`);
  if (actor) params.push(`actor=${encodeURIComponent(actor)}`);
  if (ok !== '') params.push(`ok=${encodeURIComponent(ok)}`);
  params.push(`limit=${encodeURIComponent(limit)}`);
  params.push('since=0');
  return params.join('&');
}

async function loadAuditLog(reset = true) {
  if (state.accessMode !== 'audit') {
    return;
  }
  try {
    const limit = Math.max(50, Math.min(500, Number(state.auditLimit) || 200));
    const data = await apiJson(`/api/v1/audit?${buildAuditQuery(limit)}`);
    state.auditEntries = Array.isArray(data) ? data : [];
    renderAuditLog();
  } catch (err) {
  }
}

async function loadAccessLog(reset = false) {
  if (state.accessMode !== 'access') {
    return;
  }
  try {
    const since = reset ? 0 : state.accessLogCursor;
    const limit = Math.max(50, Math.min(500, Number(state.accessLimit) || 200));
    const data = await apiJson(`/api/v1/access-log?${buildAccessLogQuery(since, limit)}`);
    const entries = data.entries || [];
    if (reset) {
      state.accessLogEntries = [];
      elements.accessTable.innerHTML = '';
    }
    appendAccessLogEntries(entries);
    if (entries.length) {
      state.accessLogCursor = entries[entries.length - 1].id;
    } else if (reset && data.next_id) {
      state.accessLogCursor = data.next_id - 1;
    }
    if (!entries.length && reset) {
      renderAccessLog();
    }
  } catch (err) {
  }
}

function startAccessLogPolling() {
  if (state.accessPaused) {
    return;
  }
  if (state.accessLogTimer) {
    clearInterval(state.accessLogTimer);
  }
  if (state.accessMode === 'audit') {
    state.accessLogTimer = setInterval(() => loadAuditLog(true), POLL_ACCESS_MS);
    loadAuditLog(true);
  } else {
    state.accessLogTimer = setInterval(() => loadAccessLog(false), POLL_ACCESS_MS);
    loadAccessLog(true);
  }
}

function stopAccessLogPolling() {
  if (state.accessLogTimer) {
    clearInterval(state.accessLogTimer);
    state.accessLogTimer = null;
  }
}

function startObservabilityPolling() {
  if (state.observabilityTimer) {
    clearInterval(state.observabilityTimer);
  }
  state.observabilityTimer = setInterval(() => {
    if (state.currentView === 'observability' && !document.hidden) {
      loadObservability(false);
    }
  }, POLL_OBSERVABILITY_MS);
}

function stopObservabilityPolling() {
  if (state.observabilityTimer) {
    clearInterval(state.observabilityTimer);
    state.observabilityTimer = null;
  }
}

function updateObservabilityStreamOptions() {
  if (!elements.observabilityStream) return;
  const current = elements.observabilityStream.value;
  elements.observabilityStream.innerHTML = '';
  const placeholder = createEl('option', '', 'Select stream');
  placeholder.value = '';
  elements.observabilityStream.appendChild(placeholder);
  const streams = Array.isArray(state.streams) ? state.streams.slice() : [];
  streams.sort((a, b) => String(a.id).localeCompare(String(b.id)));
  streams.forEach((stream) => {
    const option = createEl('option', '', `${stream.id} — ${stream.name || ''}`.trim());
    option.value = stream.id;
    elements.observabilityStream.appendChild(option);
  });
  if (current) {
    elements.observabilityStream.value = current;
  }
}

function updateObservabilityScopeFields() {
  if (!elements.observabilityScope || !elements.observabilityStreamField) return;
  const isStream = elements.observabilityScope.value === 'stream';
  elements.observabilityStreamField.hidden = !isStream;
}

function updateObservabilityOnDemandFields() {
  if (elements.settingsObservabilityOnDemand) {
    elements.settingsObservabilityOnDemand.checked = true;
    elements.settingsObservabilityOnDemand.disabled = true;
    const field = elements.settingsObservabilityOnDemand.closest ? elements.settingsObservabilityOnDemand.closest('.field') : null;
    if (field) field.hidden = true;
  }
  const onDemand = true;
  const toggleField = (input, hidden) => {
    if (!input) return;
    input.disabled = hidden;
    const field = input.closest ? input.closest('.field') : null;
    if (field) {
      field.hidden = hidden;
    }
  };
  if (elements.settingsObservabilityMetricsDays) {
    toggleField(elements.settingsObservabilityMetricsDays, onDemand);
  }
  if (elements.settingsObservabilityRollup) {
    toggleField(elements.settingsObservabilityRollup, onDemand);
  }
}

function getThemeColor(name, fallback) {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name);
  return value ? value.trim() : fallback;
}

function drawEmptyChart(canvas, message) {
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const rect = canvas.getBoundingClientRect();
  const ratio = window.devicePixelRatio || 1;
  canvas.width = rect.width * ratio;
  canvas.height = rect.height * ratio;
  ctx.scale(ratio, ratio);
  ctx.clearRect(0, 0, rect.width, rect.height);
  ctx.fillStyle = getThemeColor('--muted', '#8f98a3');
  ctx.font = '12px "IBM Plex Sans", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(message || 'No data', rect.width / 2, rect.height / 2);
}

function drawLineChart(canvas, series) {
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const rect = canvas.getBoundingClientRect();
  const ratio = window.devicePixelRatio || 1;
  canvas.width = rect.width * ratio;
  canvas.height = rect.height * ratio;
  ctx.scale(ratio, ratio);
  ctx.clearRect(0, 0, rect.width, rect.height);

  const allPoints = series.flatMap((item) => item.points || []);
  if (!allPoints.length) {
    drawEmptyChart(canvas, 'No data');
    return;
  }

  let minX = Infinity;
  let maxX = -Infinity;
  let minY = Infinity;
  let maxY = -Infinity;
  allPoints.forEach((pt) => {
    minX = Math.min(minX, pt.x);
    maxX = Math.max(maxX, pt.x);
    minY = Math.min(minY, pt.y);
    maxY = Math.max(maxY, pt.y);
  });
  if (minX === maxX) {
    minX -= 1;
    maxX += 1;
  }
  if (minY === maxY) {
    minY = minY === 0 ? -1 : minY * 0.9;
    maxY = maxY === 0 ? 1 : maxY * 1.1;
  }

  const padding = { left: 36, right: 8, top: 10, bottom: 18 };
  const width = rect.width - padding.left - padding.right;
  const height = rect.height - padding.top - padding.bottom;
  const xScale = (x) => padding.left + ((x - minX) / (maxX - minX)) * width;
  const yScale = (y) => rect.height - padding.bottom - ((y - minY) / (maxY - minY)) * height;

  ctx.strokeStyle = getThemeColor('--border', '#3d434e');
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padding.left, padding.top);
  ctx.lineTo(padding.left, rect.height - padding.bottom);
  ctx.lineTo(rect.width - padding.right, rect.height - padding.bottom);
  ctx.stroke();

  series.forEach((item) => {
    const points = item.points || [];
    if (!points.length) return;
    ctx.strokeStyle = item.color || getThemeColor('--accent', '#5aaae5');
    ctx.lineWidth = 2;
    ctx.beginPath();
    points.forEach((pt, idx) => {
      const x = xScale(pt.x);
      const y = yScale(pt.y);
      if (idx === 0) {
        ctx.moveTo(x, y);
      } else {
        ctx.lineTo(x, y);
      }
    });
    ctx.stroke();
  });
}

function drawBarChart(canvas, series) {
  if (!canvas) return;
  const ctx = canvas.getContext('2d');
  const rect = canvas.getBoundingClientRect();
  const ratio = window.devicePixelRatio || 1;
  canvas.width = rect.width * ratio;
  canvas.height = rect.height * ratio;
  ctx.scale(ratio, ratio);
  ctx.clearRect(0, 0, rect.width, rect.height);

  const allPoints = series.flatMap((item) => item.points || []);
  if (!allPoints.length) {
    drawEmptyChart(canvas, 'No data');
    return;
  }

  let minY = Infinity;
  let maxY = -Infinity;
  allPoints.forEach((pt) => {
    minY = Math.min(minY, pt.y);
    maxY = Math.max(maxY, pt.y);
  });
  if (minY === maxY) {
    minY = minY === 0 ? -1 : minY * 0.9;
    maxY = maxY === 0 ? 1 : maxY * 1.1;
  }

  const padding = { left: 36, right: 8, top: 10, bottom: 18 };
  const width = rect.width - padding.left - padding.right;
  const height = rect.height - padding.top - padding.bottom;
  const yScale = (y) => rect.height - padding.bottom - ((y - minY) / (maxY - minY)) * height;

  ctx.strokeStyle = getThemeColor('--border', '#3d434e');
  ctx.lineWidth = 1;
  ctx.beginPath();
  ctx.moveTo(padding.left, padding.top);
  ctx.lineTo(padding.left, rect.height - padding.bottom);
  ctx.lineTo(rect.width - padding.right, rect.height - padding.bottom);
  ctx.stroke();

  const maxPoints = Math.max(...series.map((item) => (item.points || []).length));
  if (!maxPoints) return;
  const groupCount = series.length || 1;
  const slotWidth = width / maxPoints;
  const barWidth = Math.max(2, (slotWidth * 0.7) / groupCount);

  series.forEach((item, sidx) => {
    const points = item.points || [];
    ctx.fillStyle = item.color || getThemeColor('--accent', '#5aaae5');
    points.forEach((pt, idx) => {
      const xBase = padding.left + idx * slotWidth + (slotWidth * 0.15);
      const x = xBase + sidx * barWidth;
      const y = yScale(pt.y);
      const h = (rect.height - padding.bottom) - y;
      ctx.fillRect(x, y, barWidth, h);
    });
  });
}

function renderAiCharts(charts) {
  if (!Array.isArray(charts) || !charts.length) return null;
  const palette = ['#5aaae5', '#7fd18c', '#f1b44c', '#d675d9'];
  const chartMode = getSettingString('ai_chart_mode', 'spec') || 'spec';
  const block = createEl('div', 'ai-chat-charts');
  charts.slice(0, 4).forEach((chart, idx) => {
    if (!chart || !Array.isArray(chart.series)) return;
    const card = createEl('div', 'ai-chat-chart');
    const title = createEl('div', 'ai-chart-title', chart.title || `Chart ${idx + 1}`);
    const canvas = document.createElement('canvas');
    canvas.className = 'ai-chart-canvas';
    card.appendChild(title);
    card.appendChild(canvas);
    block.appendChild(card);

    const series = chart.series.map((item, sidx) => {
      const values = Array.isArray(item.values) ? item.values : [];
      return {
        name: item.name || `Series ${sidx + 1}`,
        color: palette[sidx % palette.length],
        points: values.map((val, xIdx) => ({ x: xIdx, y: Number(val) || 0 })),
      };
    });
    if (String(chart.type || '').toLowerCase() === 'bar') {
      drawBarChart(canvas, series);
    } else {
      drawLineChart(canvas, series);
    }
    if (chartMode === 'image') {
      const img = document.createElement('img');
      img.className = 'ai-chart-image';
      img.alt = chart.title || 'Chart';
      try {
        img.src = canvas.toDataURL('image/png');
        canvas.replaceWith(img);
      } catch (err) {
        // fallback to canvas if toDataURL fails
      }
    }
  });
  return block;
}

function groupMetrics(items) {
  const map = {};
  (items || []).forEach((row) => {
    if (!row || row.metric_key == null || row.ts_bucket == null) return;
    const key = String(row.metric_key);
    if (!map[key]) map[key] = [];
    map[key].push({
      x: Number(row.ts_bucket) * 1000,
      y: Number(row.value) || 0,
    });
  });
  Object.keys(map).forEach((key) => {
    map[key].sort((a, b) => a.x - b.x);
  });
  return map;
}

function renderObservabilitySummary(summary, scope, streamId) {
  if (!elements.observabilitySummary) return;
  elements.observabilitySummary.innerHTML = '';
  const cards = [];
  const addCard = (label, value) => {
    const card = createEl('div', 'summary-card');
    card.innerHTML = `<div class="label">${label}</div><div class="value">${value}</div>`;
    cards.push(card);
  };

  if (scope === 'stream') {
    addCard('Stream', streamId || '—');
    addCard('Bitrate', formatBitrate(Number(summary.bitrate_kbps) || 0));
    addCard('On air', summary.on_air ? 'YES' : 'NO');
    addCard('Input switch', Number(summary.input_switch || 0));
  } else {
    addCard('Total bitrate', formatBitrate(Number(summary.total_bitrate_kbps) || 0));
    addCard('Streams on air', Number(summary.streams_on_air || 0));
    addCard('Streams down', Number(summary.streams_down || 0));
    addCard('Input switch', Number(summary.input_switch || 0));
    addCard('Alerts error', Number(summary.alerts_error || 0));
  }

  cards.forEach((card) => elements.observabilitySummary.appendChild(card));
}

function renderObservabilityCharts(items, scope) {
  const seriesMap = groupMetrics(items || []);
  const accent = getThemeColor('--accent', '#5aaae5');
  const warning = getThemeColor('--warning', '#f0b54d');
  const danger = getThemeColor('--danger', '#e06666');
  const success = getThemeColor('--success', '#5bc377');

  if (scope === 'stream') {
    drawLineChart(elements.observabilityChartBitrate, [
      { color: accent, points: seriesMap.bitrate_kbps || [] },
    ]);
    drawLineChart(elements.observabilityChartStreams, [
      { color: success, points: seriesMap.on_air || [] },
    ]);
    drawLineChart(elements.observabilityChartSwitches, [
      { color: warning, points: seriesMap.input_switch || [] },
    ]);
  } else {
    drawLineChart(elements.observabilityChartBitrate, [
      { color: accent, points: seriesMap.total_bitrate_kbps || [] },
    ]);
    drawLineChart(elements.observabilityChartStreams, [
      { color: success, points: seriesMap.streams_on_air || [] },
      { color: danger, points: seriesMap.streams_down || [] },
    ]);
    drawLineChart(elements.observabilityChartSwitches, [
      { color: warning, points: seriesMap.input_switch || [] },
      { color: danger, points: seriesMap.alerts_error || [] },
    ]);
  }
}

function renderObservabilityLogs(items) {
  if (!elements.observabilityLogs) return;
  elements.observabilityLogs.innerHTML = '';
  const list = Array.isArray(items) ? items : [];
  if (!list.length) {
    const empty = createEl('div', 'observability-log-empty', 'No recent errors.');
    elements.observabilityLogs.appendChild(empty);
    return;
  }
  list.forEach((row) => {
    const item = document.createElement('div');
    item.className = 'observability-log-item';
    const time = createEl('div', 'time', formatLogTime(row.ts || 0));
    const stream = createEl('div', 'stream', row.stream_id || '-');
    const message = createEl('div', 'message', row.message || row.component || '');
    item.appendChild(time);
    item.appendChild(stream);
    item.appendChild(message);
    elements.observabilityLogs.appendChild(item);
  });
}

function renderObservabilityAiSummary(payload) {
  if (!elements.observabilityAiSummary) return;
  elements.observabilityAiSummary.innerHTML = '';
  const note = payload && payload.note ? payload.note : '';
  const ai = payload && payload.ai ? payload.ai : null;
  if (!ai) {
    const empty = createEl('div', 'ai-summary-item', note || 'AI summary unavailable.');
    elements.observabilityAiSummary.appendChild(empty);
    return;
  }
  if (ai.summary) {
    const section = createEl('div', 'ai-summary-section');
    section.appendChild(createEl('div', 'ai-summary-label', 'Summary'));
    section.appendChild(createEl('div', 'ai-summary-item', ai.summary));
    elements.observabilityAiSummary.appendChild(section);
  }
  if (Array.isArray(ai.top_issues) && ai.top_issues.length) {
    const section = createEl('div', 'ai-summary-section');
    section.appendChild(createEl('div', 'ai-summary-label', 'Top issues'));
    ai.top_issues.forEach((item) => section.appendChild(createEl('div', 'ai-summary-item', item)));
    elements.observabilityAiSummary.appendChild(section);
  }
  if (Array.isArray(ai.suggestions) && ai.suggestions.length) {
    const section = createEl('div', 'ai-summary-section');
    section.appendChild(createEl('div', 'ai-summary-label', 'Suggestions'));
    ai.suggestions.forEach((item) => section.appendChild(createEl('div', 'ai-summary-item', item)));
    elements.observabilityAiSummary.appendChild(section);
  }
}


async function loadObservability(showStatus) {
  if (!elements.observabilityRange) return;
  const logsDays = getSettingNumber('ai_logs_retention_days', 0);
  const metricsDays = getSettingNumber('ai_metrics_retention_days', 0);
  const onDemand = getSettingBool('ai_metrics_on_demand', true);
  const enabled = logsDays > 0 || metricsDays > 0;
  if (elements.observabilityEmpty) {
    elements.observabilityEmpty.classList.toggle('active', !enabled);
  }
  if (elements.observabilityHint) {
    elements.observabilityHint.textContent = onDemand
      ? 'Metrics are calculated on request (logs + runtime snapshot).'
      : '';
  }
  if (!enabled) {
    renderObservabilitySummary({ total_bitrate_kbps: 0, streams_on_air: 0, streams_down: 0, input_switch: 0, alerts_error: 0 }, 'global');
    renderObservabilityCharts([], 'global');
    renderObservabilityLogs([]);
    renderObservabilityAiSummary({ note: 'AI summary unavailable.' });
    return;
  }

  const range = elements.observabilityRange.value || '24h';
  const scope = elements.observabilityScope.value || 'global';
  const streamId = elements.observabilityStream ? elements.observabilityStream.value : '';
  if (scope === 'stream' && !streamId) {
    renderObservabilitySummary({ bitrate_kbps: 0, on_air: 0, input_switch: 0 }, 'stream', '');
    renderObservabilityCharts([], 'stream');
    renderObservabilityLogs([]);
    return;
  }
  if (showStatus) {
    setStatus('Loading observability...');
  }

  try {
    const metricsUrl = new URL('/api/v1/ai/metrics', window.location.origin);
    metricsUrl.searchParams.set('range', range);
    metricsUrl.searchParams.set('scope', scope);
    if (scope === 'stream' && streamId) {
      metricsUrl.searchParams.set('id', streamId);
    }
    const metrics = await apiJson(metricsUrl.toString());
    const items = metrics && metrics.items ? metrics.items : [];

    const logsUrl = new URL('/api/v1/ai/logs', window.location.origin);
    logsUrl.searchParams.set('range', range);
    logsUrl.searchParams.set('level', 'ERROR');
    logsUrl.searchParams.set('limit', '20');
    if (scope === 'stream' && streamId) {
      logsUrl.searchParams.set('stream_id', streamId);
    }
    const logs = await apiJson(logsUrl.toString());
    const logItems = logs && logs.items ? logs.items : [];

    let summary = {};
    const latest = {};
    let lastBucket = 0;
    items.forEach((row) => {
      if (row.ts_bucket && row.ts_bucket > lastBucket) {
        lastBucket = row.ts_bucket;
      }
    });
    items.forEach((row) => {
      if (row.ts_bucket === lastBucket) {
        latest[row.metric_key] = row.value;
      }
    });
    if (scope === 'global') {
      summary = {
        total_bitrate_kbps: latest.total_bitrate_kbps || 0,
        streams_on_air: latest.streams_on_air || 0,
        streams_down: latest.streams_down || 0,
        streams_total: latest.streams_total || 0,
        input_switch: latest.input_switch || 0,
        alerts_error: latest.alerts_error || 0,
      };
    } else {
      summary = {
        bitrate_kbps: latest.bitrate_kbps || 0,
        on_air: Number(latest.on_air || 0) > 0,
        input_switch: latest.input_switch || 0,
      };
    }

    renderObservabilitySummary(summary, scope, streamId);
    renderObservabilityCharts(items, scope);
    renderObservabilityLogs(logItems);
  } catch (err) {
    const message = formatNetworkError(err) || 'Failed to load observability';
    setStatus(message);
  }
}

function syncPollingForView() {
  if (state.currentView === 'dashboard') {
    startStatusPolling();
  } else {
    stopStatusPolling();
  }
  if (state.currentView === 'sessions') {
    startSessionPolling();
  } else {
    stopSessionPolling();
  }
  if (state.currentView === 'log') {
    startLogPolling();
  } else {
    stopLogPolling();
  }
  if (state.currentView === 'access') {
    setAccessMode(state.accessMode || 'access');
  } else {
    stopAccessLogPolling();
  }
  if (state.currentView === 'adapters') {
    startAdapterPolling();
  } else {
    stopAdapterPolling();
  }
  if (state.currentView === 'buffers') {
    startBufferPolling();
  } else {
    stopBufferPolling();
  }
  if (state.currentView === 'splitters') {
    startSplitterPolling();
  } else {
    stopSplitterPolling();
  }
  if (state.currentView === 'observability') {
    startObservabilityPolling();
  } else {
    stopObservabilityPolling();
  }
}

function pauseAllPolling() {
  stopStatusPolling();
  stopAdapterPolling();
  stopDvbPolling();
  stopSplitterPolling();
  stopBufferPolling();
  stopSessionPolling();
  stopLogPolling();
  stopAccessLogPolling();
  stopServerStatusPolling();
  stopObservabilityPolling();
}

function resumeAllPolling() {
  if (document.hidden) return;
  syncPollingForView();
  if (state.currentView === 'adapters') {
    startDvbPolling();
  }
}

function setAccessPaused(paused) {
  state.accessPaused = paused;
  if (elements.accessPause) {
    elements.accessPause.textContent = paused ? 'Resume' : 'Pause';
  }
  if (paused) {
    stopAccessLogPolling();
  } else {
    startAccessLogPolling();
  }
}

function setAccessMode(mode) {
  const next = mode === 'audit' ? 'audit' : 'access';
  state.accessMode = next;
  if (elements.accessControls) {
    elements.accessControls.hidden = next !== 'access';
  }
  if (elements.auditControls) {
    elements.auditControls.hidden = next !== 'audit';
  }
  if (elements.accessTable) {
    elements.accessTable.hidden = next !== 'access';
  }
  if (elements.auditTable) {
    elements.auditTable.hidden = next !== 'audit';
  }
  startAccessLogPolling();
}

function logLevelClass(level) {
  const lvl = String(level || 'info').toLowerCase();
  if (lvl === 'error') return 'error';
  if (lvl === 'warning') return 'warn';
  if (lvl === 'debug') return 'debug';
  return 'info';
}

function formatLogTime(ts) {
  const date = new Date(ts * 1000);
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  const pad = (num) => String(num).padStart(2, '0');
  return `${months[date.getMonth()]} ${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function normalizeLogFilter(text) {
  return String(text || '').trim().toLowerCase();
}

function filterLogEntries(entries) {
  const level = state.logLevelFilter || 'all';
  const query = normalizeLogFilter(state.logTextFilter);
  if (level === 'all' && !query) return entries;
  return entries.filter((entry) => {
    if (level !== 'all' && String(entry.level || '').toLowerCase() !== level) {
      return false;
    }
    if (!query) return true;
    const message = `${entry.message || ''}`.toLowerCase();
    return message.includes(query);
  });
}

function renderLogs() {
  const entries = filterLogEntries(state.logEntries);
  elements.logOutput.textContent = '';
  if (!entries.length) {
    elements.logOutput.textContent = state.logEntries.length ? 'No logs match the filter.' : 'No logs yet.';
    if (elements.logCount) {
      const total = state.logEntries.length;
      elements.logCount.textContent = total ? `0/${total}` : '0';
    }
    return;
  }
  const fragment = document.createDocumentFragment();
  entries.forEach((entry) => {
    const line = document.createElement('div');
    line.className = `log-line ${logLevelClass(entry.level)}`;
    line.textContent = `${formatLogTime(entry.ts)} [${entry.level}] ${entry.message}`;
    fragment.appendChild(line);
  });
  elements.logOutput.appendChild(fragment);
  if (elements.logCount) {
    const total = state.logEntries.length;
    elements.logCount.textContent = entries.length === total ? String(total) : `${entries.length}/${total}`;
  }
  if (!state.logPaused) {
    elements.logOutput.scrollTop = elements.logOutput.scrollHeight;
  }
}

function buildLogQuery(since, limit) {
  const params = [`since=${since}`, `limit=${limit}`];
  const level = String(state.logLevelFilter || '').trim().toLowerCase();
  if (level && level !== 'all') {
    params.push(`level=${encodeURIComponent(level)}`);
  }
  const text = String(state.logTextFilter || '').trim();
  if (text) {
    params.push(`text=${encodeURIComponent(text)}`);
  }
  const stream = String(state.logStreamFilter || '').trim();
  if (stream) {
    params.push(`stream_id=${encodeURIComponent(stream)}`);
  }
  return params.join('&');
}

function appendLogEntries(entries) {
  if (!entries || entries.length === 0) {
    return;
  }
  state.logEntries = state.logEntries.concat(entries);
  const maxEntries = Math.max(50, Number(state.logLimit) || 500);
  if (state.logEntries.length > maxEntries) {
    state.logEntries = state.logEntries.slice(state.logEntries.length - maxEntries);
  }
  renderLogs();
}

async function loadLogs(reset = false) {
  try {
    const fetchLimit = Math.max(50, Math.min(500, Number(state.logLimit) || 200));
    const since = reset ? 0 : state.logCursor;
    const data = await apiJson(`/api/v1/logs?${buildLogQuery(since, fetchLimit)}`);
    const entries = data.entries || [];
    if (reset) {
      state.logEntries = [];
      elements.logOutput.textContent = '';
    }
    appendLogEntries(entries);
    if (entries.length) {
      state.logCursor = entries[entries.length - 1].id;
    } else if (reset && data.next_id) {
      state.logCursor = data.next_id - 1;
    }
    if (!entries.length && reset) {
      renderLogs();
    }
  } catch (err) {
  }
}

function startLogPolling() {
  if (state.logPaused) {
    return;
  }
  if (state.logTimer) {
    clearInterval(state.logTimer);
  }
  state.logTimer = setInterval(() => loadLogs(false), POLL_LOG_MS);
  loadLogs(true);
}

function stopLogPolling() {
  if (state.logTimer) {
    clearInterval(state.logTimer);
    state.logTimer = null;
  }
}

function setLogPaused(paused) {
  state.logPaused = paused;
  if (elements.logPause) {
    elements.logPause.textContent = paused ? 'Resume' : 'Pause';
  }
  if (paused) {
    stopLogPolling();
  } else {
    startLogPolling();
  }
}

function closeTileMenus(exceptTile) {
  $$('.tile').forEach((tile) => {
    if (tile !== exceptTile) {
      tile.removeAttribute('data-menu-open');
    }
  });
}

function getPlaylistUrl(stream) {
  const outputs = (stream.config && stream.config.output) || [];
  const hls = outputs.find((out) => out.format === 'hls');
  if (!hls || !hls.base_url) return null;
  const playlist = hls.playlist || 'index.m3u8';
  return joinPath(hls.base_url, playlist);
}

function getPlayBaseUrl() {
  const configuredPort = getSettingNumber('http_play_port', undefined);
  const fallbackPort = window.location.port ? Number(window.location.port) : undefined;
  // http_play_port=0 трактуем как "использовать основной HTTP порт".
  const port = (configuredPort && configuredPort > 0) ? configuredPort : fallbackPort;
  const noTls = getSettingBool('http_play_no_tls', false);
  const protocol = noTls ? 'http:' : window.location.protocol;
  const host = window.location.hostname || '127.0.0.1';
  const base = new URL(`${protocol}//${host}`);
  if (port) {
    base.port = String(port);
  }
  return base.toString().replace(/\/$/, '');
}

function getPlayUrl(stream) {
  if (!stream || !stream.id) return '';
  const base = getPlayBaseUrl();
  return `${base}/play/${encodeURIComponent(stream.id)}`;
}

function canPlayMpegTs() {
  if (!elements.playerVideo || !elements.playerVideo.canPlayType) return false;
  const result = elements.playerVideo.canPlayType('video/mp2t');
  return result === 'probably' || result === 'maybe';
}

let hlsJsPromise = null;

function canPlayHlsNatively() {
  if (!elements.playerVideo || !elements.playerVideo.canPlayType) return false;
  const result = elements.playerVideo.canPlayType('application/vnd.apple.mpegurl');
  return result === 'probably' || result === 'maybe';
}

function loadScriptOnce(src, marker) {
  return new Promise((resolve, reject) => {
    const selector = marker ? `script[data-marker="${marker}"]` : `script[src="${src}"]`;
    const existing = document.querySelector(selector);
    if (existing) {
      if (existing.dataset.loaded === '1') {
        resolve();
        return;
      }
      existing.addEventListener('load', () => resolve(), { once: true });
      existing.addEventListener('error', () => reject(new Error(`Failed to load ${src}`)), { once: true });
      return;
    }

    const script = document.createElement('script');
    script.src = src;
    script.async = true;
    if (marker) script.dataset.marker = marker;
    script.dataset.loaded = '0';
    script.addEventListener('load', () => {
      script.dataset.loaded = '1';
      resolve();
    }, { once: true });
    script.addEventListener('error', () => {
      reject(new Error(`Failed to load ${src}`));
    }, { once: true });
    document.head.appendChild(script);
  });
}

function ensureHlsJsLoaded() {
  if (window.Hls) return Promise.resolve();
  if (hlsJsPromise) return hlsJsPromise;
  // Загружаем локальный vendor только по требованию (не тянем CDN в проде).
  const src = `/vendor/hls.min.js?v=20260206d`;
  hlsJsPromise = loadScriptOnce(src, 'hlsjs').catch((err) => {
    hlsJsPromise = null;
    throw err;
  });
  return hlsJsPromise;
}

async function apiFetch(path, options = {}) {
  const headers = options.headers ? { ...options.headers } : {};
  if (state.token) {
    headers.Authorization = `Bearer ${state.token}`;
  }
  if (options.body && !headers['Content-Type']) {
    headers['Content-Type'] = 'application/json';
  }

  const retries = Number.isFinite(options.retry) ? options.retry : 1;
  let lastError = null;
  for (let attempt = 0; attempt <= retries; attempt += 1) {
    try {
      const response = await fetch(path, {
        credentials: 'same-origin',
        ...options,
        headers,
      });

      if (response.status === 401) {
        setOverlay(elements.loginOverlay, true);
      }

      return response;
    } catch (err) {
      lastError = err;
      if (attempt < retries) {
        await delay(250 * (attempt + 1));
      }
    }
  }

  const error = new Error('Network error: cannot reach server');
  error.network = true;
  error.cause = lastError;
  throw error;
}

function formatNetworkError(err) {
  if (!err) return '';
  if (err.network) return 'Server is unreachable or IP is not in allowlist.';
  const message = String(err.message || '');
  if (message.includes('Failed to fetch') || message.includes('Network error')) {
    return 'Server is unreachable or IP is not in allowlist.';
  }
  return '';
}

async function apiJson(path, options = {}) {
  const response = await apiFetch(path, options);
  const text = await response.text();
  let payload = {};
  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (err) {
      payload = {};
    }
  }
  if (!response.ok) {
    const message = payload.error || response.statusText || 'Request failed';
    const error = new Error(`HTTP ${response.status}: ${message}`);
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

async function apiText(path, options = {}) {
  const response = await apiFetch(path, options);
  const text = await response.text();
  if (!response.ok) {
    let message = response.statusText || 'Request failed';
    if (text) {
      try {
        const payload = JSON.parse(text);
        message = payload.error || message;
      } catch (err) {
      }
    }
    throw new Error(message);
  }
  return text;
}

function setImportStatus(message) {
  if (!elements.importResult) return;
  elements.importResult.textContent = message;
}

async function importConfigFile() {
  if (!elements.importFile) return;
  const file = elements.importFile.files && elements.importFile.files[0];
  if (!file) {
    setImportStatus('Select a JSON file first.');
    return;
  }

  let payload = null;
  try {
    const text = await file.text();
    payload = JSON.parse(text);
  } catch (err) {
    setImportStatus('Invalid JSON file.');
    return;
  }

  const mode = elements.importMode ? elements.importMode.value : 'merge';
  setImportStatus('Importing...');
  try {
    const result = await apiJson('/api/v1/import', {
      method: 'POST',
      body: JSON.stringify({ mode, config: payload }),
    });
    if (result && result.summary) {
      const s = result.summary;
      setImportStatus(
        `Imported. settings=${s.settings || 0}, users=${s.users || 0}, adapters=${s.adapters || 0}, streams=${s.streams || 0}, softcam=${s.softcam || 0}, splitters=${s.splitters || 0}, splitter_links=${s.splitter_links || 0}, splitter_allow=${s.splitter_allow || 0}`
      );
    } else {
      setImportStatus('Import complete.');
    }
    await refreshAll();
  } catch (err) {
    setImportStatus(`Import failed: ${err.message}`);
  }
}

function applySettingsToUI() {
  const setSelectValue = (select, value, fallback) => {
    if (!select) return;
    const target = String(value);
    if (select.querySelector(`option[value="${target}"]`)) {
      select.value = target;
    } else {
      select.value = String(fallback);
    }
  };
  if (elements.settingsShowSplitter) {
    elements.settingsShowSplitter.checked = getSettingBool('ui_splitter_enabled', false);
  }
  if (elements.settingsShowBuffer) {
    elements.settingsShowBuffer.checked = getSettingBool('ui_buffer_enabled', false);
  }
  if (elements.settingsShowAccess) {
    elements.settingsShowAccess.checked = getSettingBool('ui_access_enabled', true);
  }
  if (elements.settingsEpgInterval) {
    elements.settingsEpgInterval.value = getSettingNumber('epg_export_interval_sec', 0);
  }
  if (elements.settingsEventRequest) {
    elements.settingsEventRequest.value = getSettingString('event_request', '');
  }
  if (elements.settingsMonitorAnalyzeMax) {
    elements.settingsMonitorAnalyzeMax.value = getSettingNumber('monitor_analyze_max_concurrency', '');
  }
  if (elements.settingsPreviewMaxSessions) {
    elements.settingsPreviewMaxSessions.value = getSettingNumber('preview_max_sessions', 2);
  }
  if (elements.settingsPreviewIdleTimeout) {
    elements.settingsPreviewIdleTimeout.value = getSettingNumber('preview_idle_timeout_sec', 45);
  }
  if (elements.settingsPreviewTokenTtl) {
    elements.settingsPreviewTokenTtl.value = getSettingNumber('preview_token_ttl_sec', 180);
  }
  if (elements.settingsLogMaxEntries) {
    elements.settingsLogMaxEntries.value = getSettingNumber('log_max_entries', '');
  }
  if (elements.settingsLogRetentionSec) {
    elements.settingsLogRetentionSec.value = getSettingNumber('log_retention_sec', '');
  }
  if (elements.settingsAccessLogMaxEntries) {
    elements.settingsAccessLogMaxEntries.value = getSettingNumber('access_log_max_entries', '');
  }
  if (elements.settingsAccessLogRetentionSec) {
    elements.settingsAccessLogRetentionSec.value = getSettingNumber('access_log_retention_sec', '');
  }
  if (elements.settingsObservabilityEnabled) {
    const logsDays = getSettingNumber('ai_logs_retention_days', 0);
    const metricsDays = getSettingNumber('ai_metrics_retention_days', 0);
    const rollup = getSettingNumber('ai_rollup_interval_sec', 60);
    const onDemand = true;
    if (elements.settingsObservabilityOnDemand) {
      elements.settingsObservabilityOnDemand.checked = true;
      elements.settingsObservabilityOnDemand.disabled = true;
    }
    elements.settingsObservabilityEnabled.checked = (logsDays > 0) || (!onDemand && metricsDays > 0);
    setSelectValue(elements.settingsObservabilityLogsDays, logsDays > 0 ? logsDays : 7, 7);
    setSelectValue(elements.settingsObservabilityMetricsDays, metricsDays > 0 ? metricsDays : 30, 30);
    setSelectValue(elements.settingsObservabilityRollup, rollup || 60, 60);
    updateObservabilityOnDemandFields();
  }
  if (elements.settingsTelegramEnabled) {
    elements.settingsTelegramEnabled.checked = getSettingBool('telegram_enabled', false);
  }
  if (elements.settingsTelegramLevel) {
    elements.settingsTelegramLevel.value = getSettingString('telegram_level', 'OFF');
  }
  if (elements.settingsTelegramChatId) {
    elements.settingsTelegramChatId.value = getSettingString('telegram_chat_id', '');
  }
  if (elements.settingsTelegramToken) {
    elements.settingsTelegramToken.value = '';
  }
  if (elements.settingsTelegramTokenHint) {
    const tokenMasked = getSettingString('telegram_bot_token_masked', '');
    const tokenSet = getSettingBool('telegram_bot_token_set', false);
    elements.settingsTelegramTokenHint.textContent = tokenSet
      ? `Token set (${tokenMasked || 'masked'})`
      : 'Token not set';
  }
  if (elements.settingsTelegramBackupEnabled) {
    elements.settingsTelegramBackupEnabled.checked = getSettingBool('telegram_backup_enabled', false);
  }
  if (elements.settingsTelegramBackupSchedule) {
    elements.settingsTelegramBackupSchedule.value = getSettingString('telegram_backup_schedule', 'DAILY');
  }
  if (elements.settingsTelegramBackupTime) {
    elements.settingsTelegramBackupTime.value = getSettingString('telegram_backup_time', '03:00');
  }
  if (elements.settingsTelegramBackupWeekday) {
    elements.settingsTelegramBackupWeekday.value = String(getSettingNumber('telegram_backup_weekday', 1));
  }
  if (elements.settingsTelegramBackupMonthday) {
    elements.settingsTelegramBackupMonthday.value = getSettingNumber('telegram_backup_monthday', 1);
  }
  if (elements.settingsTelegramBackupSecrets) {
    elements.settingsTelegramBackupSecrets.checked = getSettingBool('telegram_backup_include_secrets', false);
  }
  if (elements.settingsTelegramSummaryEnabled) {
    elements.settingsTelegramSummaryEnabled.checked = getSettingBool('telegram_summary_enabled', false);
  }
  if (elements.settingsTelegramSummarySchedule) {
    elements.settingsTelegramSummarySchedule.value = getSettingString('telegram_summary_schedule', 'DAILY');
  }
  if (elements.settingsTelegramSummaryTime) {
    elements.settingsTelegramSummaryTime.value = getSettingString('telegram_summary_time', '08:00');
  }
  if (elements.settingsTelegramSummaryWeekday) {
    elements.settingsTelegramSummaryWeekday.value = String(getSettingNumber('telegram_summary_weekday', 1));
  }
  if (elements.settingsTelegramSummaryMonthday) {
    elements.settingsTelegramSummaryMonthday.value = getSettingNumber('telegram_summary_monthday', 1);
  }
  if (elements.settingsTelegramSummaryCharts) {
    elements.settingsTelegramSummaryCharts.checked = getSettingBool('telegram_summary_include_charts', true);
  }
  if (elements.settingsAiEnabled) {
    elements.settingsAiEnabled.checked = getSettingBool('ai_enabled', false);
  }
  if (elements.settingsAiApiKey) {
    elements.settingsAiApiKey.value = '';
  }
  if (elements.settingsAiApiKeyHint) {
    const masked = getSettingString('ai_api_key_masked', '');
    const set = getSettingBool('ai_api_key_set', false);
    elements.settingsAiApiKeyHint.textContent = set
      ? `Key set (${masked || 'masked'})`
      : 'Key not set';
  }
  if (elements.settingsAiApiBase) {
    elements.settingsAiApiBase.value = getSettingString('ai_api_base', '');
  }
  if (elements.settingsAiModel) {
    elements.settingsAiModel.value = getSettingString('ai_model', '');
  }
  if (elements.settingsAiModelHint) {
    elements.settingsAiModelHint.textContent = 'Default: gpt-5.2 (auto fallback to gpt-5-mini, gpt-4.1 if unavailable).';
  }
  if (elements.settingsAiChartMode) {
    elements.settingsAiChartMode.value = 'spec';
  }
  if (elements.settingsAiMaxTokens) {
    elements.settingsAiMaxTokens.value = getSettingNumber('ai_max_tokens', 512);
  }
  if (elements.settingsAiTemperature) {
    elements.settingsAiTemperature.value = getSettingNumber('ai_temperature', 0.2);
  }
  if (elements.settingsAiAllowedChats) {
    elements.settingsAiAllowedChats.value = getSettingString('ai_telegram_allowed_chat_ids', '');
  }
  if (elements.settingsAiStore) {
    elements.settingsAiStore.checked = getSettingBool('ai_store', false);
  }
  if (elements.settingsAiAllowApply) {
    elements.settingsAiAllowApply.checked = getSettingBool('ai_allow_apply', false);
  }
  if (elements.aiChatStatus) {
    const enabled = getSettingBool('ai_enabled', false);
    const model = getSettingString('ai_model', '');
    const effectiveModel = model || 'gpt-5.2';
    const keySet = getSettingBool('ai_api_key_set', false);
    if (!enabled) {
      elements.aiChatStatus.textContent = 'AstralAI disabled. Enable it in Settings → General.';
    } else if (!keySet) {
      elements.aiChatStatus.textContent = 'AstralAI not configured. Set API key.';
    } else {
      elements.aiChatStatus.textContent = `Model: ${effectiveModel} (auto fallback if unavailable).`;
    }
  }
  if (elements.settingsWatchdogEnabled) {
    elements.settingsWatchdogEnabled.checked = getSettingBool('resource_watchdog_enabled', true);
  }
  if (elements.settingsWatchdogCpu) {
    elements.settingsWatchdogCpu.value = getSettingNumber('resource_watchdog_cpu_pct', 95);
  }
  if (elements.settingsWatchdogRssMb) {
    elements.settingsWatchdogRssMb.value = getSettingNumber('resource_watchdog_rss_mb', 0);
  }
  if (elements.settingsWatchdogRssPct) {
    elements.settingsWatchdogRssPct.value = getSettingNumber('resource_watchdog_rss_pct', 80);
  }
  if (elements.settingsWatchdogInterval) {
    elements.settingsWatchdogInterval.value = getSettingNumber('resource_watchdog_interval_sec', 10);
  }
  if (elements.settingsWatchdogStrikes) {
    elements.settingsWatchdogStrikes.value = getSettingNumber('resource_watchdog_max_strikes', 6);
  }
  if (elements.settingsWatchdogUptime) {
    elements.settingsWatchdogUptime.value = getSettingNumber('resource_watchdog_min_uptime_sec', 180);
  }
  if (elements.settingsInfluxEnabled) {
    elements.settingsInfluxEnabled.checked = getSettingBool('influx_enabled', false);
  }
  if (elements.settingsInfluxUrl) {
    elements.settingsInfluxUrl.value = getSettingString('influx_url', '');
  }
  if (elements.settingsInfluxOrg) {
    elements.settingsInfluxOrg.value = getSettingString('influx_org', '');
  }
  if (elements.settingsInfluxBucket) {
    elements.settingsInfluxBucket.value = getSettingString('influx_bucket', '');
  }
  if (elements.settingsInfluxToken) {
    elements.settingsInfluxToken.value = getSettingString('influx_token', '');
  }
  if (elements.settingsInfluxInstance) {
    elements.settingsInfluxInstance.value = getSettingString('influx_instance', '');
  }
  if (elements.settingsInfluxMeasurement) {
    elements.settingsInfluxMeasurement.value = getSettingString('influx_measurement', 'astra_metrics');
  }
  if (elements.settingsInfluxInterval) {
    elements.settingsInfluxInterval.value = getSettingNumber('influx_interval_sec', 30);
  }
  if (elements.settingsFfmpegPath) {
    elements.settingsFfmpegPath.value = getSettingString('ffmpeg_path', '');
  }
  if (elements.settingsFfprobePath) {
    elements.settingsFfprobePath.value = getSettingString('ffprobe_path', '');
  }
  if (elements.settingsHttpsBridgeEnabled) {
    elements.settingsHttpsBridgeEnabled.checked = getSettingBool('https_bridge_enabled', false);
  }
  if (elements.settingsHttpCsrf) {
    elements.settingsHttpCsrf.checked = getSettingBool('http_csrf_enabled', true);
  }
  if (elements.settingsAuthSessionTtl) {
    elements.settingsAuthSessionTtl.value = getSettingNumber('auth_session_ttl_sec', 3600);
  }
  if (elements.settingsLoginRateLimit) {
    elements.settingsLoginRateLimit.value = getSettingNumber('rate_limit_login_per_min', 30);
  }
  if (elements.settingsLoginRateWindow) {
    elements.settingsLoginRateWindow.value = getSettingNumber('rate_limit_login_window_sec', 60);
  }
  if (elements.settingsDefaultNoDataTimeout) {
    elements.settingsDefaultNoDataTimeout.value = getSettingNumber('no_data_timeout_sec', '');
  }
  if (elements.settingsDefaultProbeInterval) {
    elements.settingsDefaultProbeInterval.value = getSettingNumber('probe_interval_sec', '');
  }
  if (elements.settingsDefaultStableOk) {
    elements.settingsDefaultStableOk.value = getSettingNumber('stable_ok_sec', '');
  }
  if (elements.settingsDefaultBackupInitial) {
    elements.settingsDefaultBackupInitial.value = getSettingNumber('backup_initial_delay_sec', '');
  }
  if (elements.settingsDefaultBackupStart) {
    elements.settingsDefaultBackupStart.value = getSettingNumber('backup_start_delay_sec', '');
  }
  if (elements.settingsDefaultBackupReturn) {
    elements.settingsDefaultBackupReturn.value = getSettingNumber('backup_return_delay_sec', '');
  }
  if (elements.settingsDefaultBackupStop) {
    elements.settingsDefaultBackupStop.value = getSettingNumber('backup_stop_if_all_inactive_sec', '');
  }
  if (elements.settingsDefaultBackupWarmMax) {
    elements.settingsDefaultBackupWarmMax.value = getSettingNumber('backup_active_warm_max', '');
  }
  if (elements.settingsDefaultHttpKeepActive) {
    elements.settingsDefaultHttpKeepActive.value = getSettingNumber('http_keep_active', '');
  }
  if (elements.casDefault) {
    elements.casDefault.checked = getSettingBool('cas_default', false);
  }
  if (elements.passwordMinLength) {
    elements.passwordMinLength.value = getSettingNumber('password_min_length', 8);
  }
  if (elements.passwordRequireLetter) {
    elements.passwordRequireLetter.checked = getSettingBool('password_require_letter', true);
  }
  if (elements.passwordRequireNumber) {
    elements.passwordRequireNumber.checked = getSettingBool('password_require_number', true);
  }
  if (elements.passwordRequireSymbol) {
    elements.passwordRequireSymbol.checked = getSettingBool('password_require_symbol', false);
  }
  if (elements.passwordRequireMixed) {
    elements.passwordRequireMixed.checked = getSettingBool('password_require_mixed_case', false);
  }
  if (elements.passwordDisallowUsername) {
    elements.passwordDisallowUsername.checked = getSettingBool('password_disallow_username', true);
  }

  if (elements.hlsDuration) {
    elements.hlsDuration.value = getSettingNumber('hls_duration', 6);
  }
  if (elements.hlsQuantity) {
    elements.hlsQuantity.value = getSettingNumber('hls_quantity', 5);
  }
  if (elements.hlsStorage) {
    elements.hlsStorage.value = getSettingString('hls_storage', 'disk');
  }
  const hlsStorageMode = elements.hlsStorage
    ? String(elements.hlsStorage.value || 'disk')
    : getSettingString('hls_storage', 'disk');
  if (elements.hlsOnDemand) {
    elements.hlsOnDemand.checked = getSettingBool('hls_on_demand', hlsStorageMode === 'memfd');
  }
  if (elements.hlsIdleTimeout) {
    elements.hlsIdleTimeout.value = getSettingNumber('hls_idle_timeout_sec', 30);
  }
  if (elements.hlsMaxBytesMb) {
    const bytes = getSettingNumber('hls_max_bytes_per_stream', 64 * 1024 * 1024);
    const mb = Math.max(0, Math.round((Number(bytes) || 0) / (1024 * 1024)));
    elements.hlsMaxBytesMb.value = String(mb);
  }
  if (elements.hlsMaxSegments) {
    elements.hlsMaxSegments.value = getSettingNumber('hls_max_segments', 12);
  }
  if (elements.hlsNaming) {
    elements.hlsNaming.value = getSettingString('hls_naming', 'sequence');
  }
  if (elements.hlsSessionTimeout) {
    elements.hlsSessionTimeout.value = getSettingNumber('hls_session_timeout', 60);
  }
  if (elements.hlsResourcePath) {
    elements.hlsResourcePath.value = getSettingString('hls_resource_path', 'absolute');
  }
  if (elements.hlsRoundDuration) {
    elements.hlsRoundDuration.checked = getSettingBool('hls_round_duration', false);
  }
  if (elements.hlsExpires) {
    elements.hlsExpires.checked = getSettingBool('hls_use_expires', false);
  }
  if (elements.hlsPassData) {
    elements.hlsPassData.checked = getSettingBool('hls_pass_data', true);
  }
  if (elements.hlsM3uHeaders) {
    elements.hlsM3uHeaders.checked = getSettingBool('hls_m3u_headers', true);
  }
  if (elements.hlsTsExtension) {
    elements.hlsTsExtension.value = getSettingString('hls_ts_extension', 'ts');
  }
  if (elements.hlsTsMime) {
    elements.hlsTsMime.value = getSettingString('hls_ts_mime', 'video/MP2T');
  }
  if (elements.hlsTsHeaders) {
    elements.hlsTsHeaders.checked = getSettingBool('hls_ts_headers', true);
  }
  updateHlsStorageUi();

  if (elements.httpPlayAllow) {
    elements.httpPlayAllow.checked = getSettingBool('http_play_allow', false);
  }
  if (elements.httpPlayHls) {
    elements.httpPlayHls.checked = getSettingBool('http_play_hls', false);
  }
  updateHttpPlayHlsStorageWarning();
  if (elements.httpPlayPort) {
    elements.httpPlayPort.value = getSettingNumber('http_play_port', getSettingNumber('http_port', 8000));
  }
  if (elements.httpPlayNoTls) {
    elements.httpPlayNoTls.checked = getSettingBool('http_play_no_tls', false);
  }
  if (elements.httpPlayLogos) {
    elements.httpPlayLogos.value = getSettingString('http_play_logos', '');
  }
  if (elements.httpPlayScreens) {
    elements.httpPlayScreens.value = getSettingString('http_play_screens', '');
  }
  if (elements.httpPlayPlaylistName) {
    elements.httpPlayPlaylistName.value = getSettingString('http_play_playlist_name', 'playlist.m3u8');
  }
  if (elements.httpPlayArrange) {
    elements.httpPlayArrange.value = getSettingString('http_play_arrange', 'tv');
  }
  if (elements.httpPlayBuffer) {
    elements.httpPlayBuffer.value = getSettingNumber('http_play_buffer_kb', 4000);
  }
  if (elements.httpPlayM3uHeader) {
    elements.httpPlayM3uHeader.value = getSettingString('http_play_m3u_header', '');
  }
  if (elements.httpPlayXspfTitle) {
    elements.httpPlayXspfTitle.value = getSettingString('http_play_xspf_title', '');
  }

  if (elements.bufferSettingEnabled) {
    elements.bufferSettingEnabled.checked = getSettingBool('buffer_enabled', false);
  }
  if (elements.bufferSettingHost) {
    elements.bufferSettingHost.value = getSettingString('buffer_listen_host', '0.0.0.0');
  }
  if (elements.bufferSettingPort) {
    elements.bufferSettingPort.value = getSettingNumber('buffer_listen_port', 8089);
  }
  if (elements.bufferSettingSourceInterface) {
    elements.bufferSettingSourceInterface.value = getSettingString('buffer_source_bind_interface', '');
  }
  if (elements.bufferSettingMaxClients) {
    elements.bufferSettingMaxClients.value = getSettingNumber('buffer_max_clients_total', 2000);
  }
  if (elements.bufferSettingClientTimeout) {
    elements.bufferSettingClientTimeout.value = getSettingNumber('buffer_client_read_timeout_sec', 20);
  }

  if (elements.httpAuthEnabled) {
    elements.httpAuthEnabled.checked = getSettingBool('http_auth_enabled', false);
  }
  if (elements.httpAuthUsers) {
    elements.httpAuthUsers.checked = getSettingBool('http_auth_users', true);
  }
  if (elements.httpAuthAllow) {
    elements.httpAuthAllow.value = getSettingString('http_auth_allow', '');
  }
  if (elements.httpAuthDeny) {
    elements.httpAuthDeny.value = getSettingString('http_auth_deny', '');
  }
  if (elements.httpAuthTokens) {
    elements.httpAuthTokens.value = getSettingString('http_auth_tokens', '');
  }
  if (elements.httpAuthRealm) {
    elements.httpAuthRealm.value = getSettingString('http_auth_realm', 'Astra');
  }
  if (elements.authOnPlayUrl) {
    elements.authOnPlayUrl.value = getSettingString('auth_on_play_url', '');
  }
  if (elements.authOnPublishUrl) {
    elements.authOnPublishUrl.value = getSettingString('auth_on_publish_url', '');
  }
  if (elements.authTimeoutMs) {
    elements.authTimeoutMs.value = getSettingNumber('auth_timeout_ms', 3000);
  }
  if (elements.authDefaultDuration) {
    elements.authDefaultDuration.value = getSettingNumber('auth_default_duration_sec', 180);
  }
  if (elements.authDenyCache) {
    elements.authDenyCache.value = getSettingNumber('auth_deny_cache_sec', 180);
  }
  if (elements.authHashAlgo) {
    elements.authHashAlgo.value = getSettingString('auth_hash_algo', 'sha1');
  }
  if (elements.authHlsRewrite) {
    elements.authHlsRewrite.checked = getSettingBool('auth_hls_rewrite_token', true);
  }
  if (elements.authAdminBypass) {
    elements.authAdminBypass.checked = getSettingBool('auth_admin_bypass_enabled', true);
  }
  if (elements.authAllowNoToken) {
    elements.authAllowNoToken.checked = getSettingBool('auth_allow_no_token', false);
  }
  if (elements.authOverlimitPolicy) {
    elements.authOverlimitPolicy.value = getSettingString('auth_overlimit_policy', 'deny_new');
  }

  if (elements.settingsShowEpg) {
    elements.settingsShowEpg.checked = getSettingNumber('epg_export_interval_sec', 0) > 0;
  }
  if (elements.settingsShowWebhook) {
    elements.settingsShowWebhook.checked = getSettingString('event_request', '') !== '';
  }
  if (elements.settingsShowLogLimits) {
    const logMax = getSettingNumber('log_max_entries', 0);
    const logRetention = getSettingNumber('log_retention_sec', 0);
    elements.settingsShowLogLimits.checked = logMax > 0 || logRetention > 0;
  }
  if (elements.settingsShowAccessLogLimits) {
    const accessMax = getSettingNumber('access_log_max_entries', 0);
    const accessRetention = getSettingNumber('access_log_retention_sec', 0);
    elements.settingsShowAccessLogLimits.checked = accessMax > 0 || accessRetention > 0;
  }
  if (elements.settingsShowTools) {
    const ffmpegPath = getSettingString('ffmpeg_path', '');
    const ffprobePath = getSettingString('ffprobe_path', '');
    elements.settingsShowTools.checked = !!(ffmpegPath || ffprobePath);
  }
  if (elements.settingsShowSecurityLimits) {
    const securityKeys = ['auth_session_ttl_sec', 'rate_limit_login_per_min', 'rate_limit_login_window_sec'];
    elements.settingsShowSecurityLimits.checked = securityKeys.some((key) => hasSettingValue(key));
  }
  if (elements.settingsShowStreamDefaults) {
    const defaultKeys = [
      'no_data_timeout_sec',
      'probe_interval_sec',
      'stable_ok_sec',
      'backup_initial_delay_sec',
      'backup_start_delay_sec',
      'backup_return_delay_sec',
      'backup_stop_if_all_inactive_sec',
      'backup_active_warm_max',
      'http_keep_active',
    ];
    elements.settingsShowStreamDefaults.checked = defaultKeys.some((key) => hasSettingValue(key));
  }
  if (elements.settingsShowAdvanced) {
    elements.settingsShowAdvanced.checked = getStoredBool(SETTINGS_ADVANCED_KEY, false);
  }

  updateTelegramBackupScheduleFields();
  updateTelegramSummaryScheduleFields();
  syncToggleTargets();

  renderGroups();
  renderSoftcams();
  renderServers();
  updateStreamGroupOptions();
  applyFeatureVisibility();

  if (state.generalRendered) {
    syncGeneralSettingsUi({ resetSnapshot: true });
  }
}

function collectGeneralSettings() {
  const epgInterval = toNumber(elements.settingsEpgInterval && elements.settingsEpgInterval.value);
  if (epgInterval !== undefined && epgInterval < 0) {
    throw new Error('EPG export interval must be >= 0');
  }
  const monitorMax = toNumber(elements.settingsMonitorAnalyzeMax && elements.settingsMonitorAnalyzeMax.value);
  if (monitorMax !== undefined && monitorMax < 1) {
    throw new Error('Analyze concurrency limit must be >= 1');
  }
  const previewMax = toNumber(elements.settingsPreviewMaxSessions && elements.settingsPreviewMaxSessions.value);
  if (previewMax !== undefined && previewMax < 1) {
    throw new Error('Preview max sessions must be >= 1');
  }
  const previewIdle = toNumber(elements.settingsPreviewIdleTimeout && elements.settingsPreviewIdleTimeout.value);
  if (previewIdle !== undefined && previewIdle < 10) {
    throw new Error('Preview idle timeout must be >= 10 sec');
  }
  const previewTtl = toNumber(elements.settingsPreviewTokenTtl && elements.settingsPreviewTokenTtl.value);
  if (previewTtl !== undefined && (previewTtl < 60 || previewTtl > 600)) {
    throw new Error('Preview token TTL must be between 60 and 600 sec');
  }
  const logMax = toNumber(elements.settingsLogMaxEntries && elements.settingsLogMaxEntries.value);
  if (logMax !== undefined && logMax < 0) {
    throw new Error('Log max entries must be >= 0');
  }
  const logRetention = toNumber(elements.settingsLogRetentionSec && elements.settingsLogRetentionSec.value);
  if (logRetention !== undefined && logRetention < 0) {
    throw new Error('Log retention must be >= 0');
  }
  const accessLogMax = toNumber(elements.settingsAccessLogMaxEntries && elements.settingsAccessLogMaxEntries.value);
  if (accessLogMax !== undefined && accessLogMax < 0) {
    throw new Error('Access log max entries must be >= 0');
  }
  const accessLogRetention = toNumber(elements.settingsAccessLogRetentionSec && elements.settingsAccessLogRetentionSec.value);
  if (accessLogRetention !== undefined && accessLogRetention < 0) {
    throw new Error('Access log retention must be >= 0');
  }
  const observabilityEnabled = elements.settingsObservabilityEnabled && elements.settingsObservabilityEnabled.checked;
  const observabilityLogsDays = toNumber(elements.settingsObservabilityLogsDays && elements.settingsObservabilityLogsDays.value);
  const observabilityMetricsDays = toNumber(elements.settingsObservabilityMetricsDays && elements.settingsObservabilityMetricsDays.value);
  const observabilityRollup = toNumber(elements.settingsObservabilityRollup && elements.settingsObservabilityRollup.value);
  const observabilityOnDemand = true;
  if (observabilityEnabled) {
    if (observabilityLogsDays !== undefined && observabilityLogsDays < 1) {
      throw new Error('Log retention days must be >= 1');
    }
    if (!observabilityOnDemand) {
      if (observabilityMetricsDays !== undefined && observabilityMetricsDays < 1) {
        throw new Error('Metrics retention days must be >= 1');
      }
    }
    if (observabilityRollup !== undefined && observabilityRollup < 30) {
      throw new Error('Rollup interval must be >= 30 sec');
    }
  }
  const telegramEnabled = elements.settingsTelegramEnabled && elements.settingsTelegramEnabled.checked;
  const telegramLevel = elements.settingsTelegramLevel && elements.settingsTelegramLevel.value;
  const telegramChatId = elements.settingsTelegramChatId && elements.settingsTelegramChatId.value.trim();
  const telegramToken = elements.settingsTelegramToken && elements.settingsTelegramToken.value.trim();
  const telegramTokenSet = getSettingBool('telegram_bot_token_set', false);
  const telegramBackupEnabled = elements.settingsTelegramBackupEnabled && elements.settingsTelegramBackupEnabled.checked;
  const telegramBackupSchedule = elements.settingsTelegramBackupSchedule && elements.settingsTelegramBackupSchedule.value;
  const telegramBackupTime = elements.settingsTelegramBackupTime && elements.settingsTelegramBackupTime.value;
  const telegramBackupWeekday = toNumber(elements.settingsTelegramBackupWeekday && elements.settingsTelegramBackupWeekday.value);
  const telegramBackupMonthday = toNumber(elements.settingsTelegramBackupMonthday && elements.settingsTelegramBackupMonthday.value);
  const telegramBackupSecrets = elements.settingsTelegramBackupSecrets && elements.settingsTelegramBackupSecrets.checked;
  const telegramSummaryEnabled = elements.settingsTelegramSummaryEnabled && elements.settingsTelegramSummaryEnabled.checked;
  const telegramSummarySchedule = elements.settingsTelegramSummarySchedule && elements.settingsTelegramSummarySchedule.value;
  const telegramSummaryTime = elements.settingsTelegramSummaryTime && elements.settingsTelegramSummaryTime.value;
  const telegramSummaryWeekday = toNumber(elements.settingsTelegramSummaryWeekday && elements.settingsTelegramSummaryWeekday.value);
  const telegramSummaryMonthday = toNumber(elements.settingsTelegramSummaryMonthday && elements.settingsTelegramSummaryMonthday.value);
  const telegramSummaryCharts = elements.settingsTelegramSummaryCharts && elements.settingsTelegramSummaryCharts.checked;
  if (telegramEnabled) {
    if (!telegramChatId) {
      throw new Error('Telegram chat ID is required when alerts are enabled');
    }
    if (!telegramToken && !telegramTokenSet) {
      throw new Error('Telegram bot token is required when alerts are enabled');
    }
  }
  if (telegramBackupEnabled) {
    if (!telegramChatId) {
      throw new Error('Telegram chat ID is required when backups are enabled');
    }
    if (!telegramToken && !telegramTokenSet) {
      throw new Error('Telegram bot token is required when backups are enabled');
    }
    if (!telegramBackupTime) {
      throw new Error('Backup time is required');
    }
    if (!/^\d{1,2}:\d{2}$/.test(telegramBackupTime)) {
      throw new Error('Backup time must be HH:MM');
    }
    const schedule = (telegramBackupSchedule || 'DAILY').toUpperCase();
    if (schedule === 'WEEKLY' && (telegramBackupWeekday === undefined || telegramBackupWeekday < 1 || telegramBackupWeekday > 7)) {
      throw new Error('Backup weekday must be 1-7');
    }
    if (schedule === 'MONTHLY' && (telegramBackupMonthday === undefined || telegramBackupMonthday < 1 || telegramBackupMonthday > 31)) {
      throw new Error('Backup month day must be 1-31');
    }
  }
  if (telegramSummaryEnabled) {
    if (!telegramChatId) {
      throw new Error('Telegram chat ID is required when summaries are enabled');
    }
    if (!telegramToken && !telegramTokenSet) {
      throw new Error('Telegram bot token is required when summaries are enabled');
    }
    if (!telegramSummaryTime) {
      throw new Error('Summary time is required');
    }
    if (!/^\d{1,2}:\d{2}$/.test(telegramSummaryTime)) {
      throw new Error('Summary time must be HH:MM');
    }
    const schedule = (telegramSummarySchedule || 'DAILY').toUpperCase();
    if (schedule === 'WEEKLY' && (telegramSummaryWeekday === undefined || telegramSummaryWeekday < 1 || telegramSummaryWeekday > 7)) {
      throw new Error('Summary weekday must be 1-7');
    }
    if (schedule === 'MONTHLY' && (telegramSummaryMonthday === undefined || telegramSummaryMonthday < 1 || telegramSummaryMonthday > 31)) {
      throw new Error('Summary month day must be 1-31');
    }
  }
  const aiEnabled = elements.settingsAiEnabled && elements.settingsAiEnabled.checked;
  const aiMaxTokens = toNumber(elements.settingsAiMaxTokens && elements.settingsAiMaxTokens.value);
  if (aiMaxTokens !== undefined && aiMaxTokens < 32) {
    throw new Error('AI max tokens must be >= 32');
  }
  const aiTemperature = toNumber(elements.settingsAiTemperature && elements.settingsAiTemperature.value);
  if (aiTemperature !== undefined && (aiTemperature < 0 || aiTemperature > 2)) {
    throw new Error('AI temperature must be between 0 and 2');
  }
  const influxEnabled = elements.settingsInfluxEnabled && elements.settingsInfluxEnabled.checked;
  const influxInterval = toNumber(elements.settingsInfluxInterval && elements.settingsInfluxInterval.value);
  if (influxInterval !== undefined && influxInterval < 5) {
    throw new Error('Influx interval must be >= 5');
  }
  const sessionTtl = toNumber(elements.settingsAuthSessionTtl && elements.settingsAuthSessionTtl.value);
  if (sessionTtl !== undefined && sessionTtl < 300) {
    throw new Error('Session TTL must be >= 300');
  }
  const loginRateLimit = toNumber(elements.settingsLoginRateLimit && elements.settingsLoginRateLimit.value);
  if (loginRateLimit !== undefined && loginRateLimit < 0) {
    throw new Error('Login rate limit must be >= 0');
  }
  const loginRateWindow = toNumber(elements.settingsLoginRateWindow && elements.settingsLoginRateWindow.value);
  if (loginRateWindow !== undefined && loginRateWindow < 1) {
    throw new Error('Login rate limit window must be >= 1');
  }
  const defaultNoDataTimeout = toNumber(elements.settingsDefaultNoDataTimeout && elements.settingsDefaultNoDataTimeout.value);
  if (defaultNoDataTimeout !== undefined && defaultNoDataTimeout < 1) {
    throw new Error('No data timeout must be >= 1');
  }
  const defaultProbeInterval = toNumber(elements.settingsDefaultProbeInterval && elements.settingsDefaultProbeInterval.value);
  if (defaultProbeInterval !== undefined && defaultProbeInterval < 0) {
    throw new Error('Probe interval must be >= 0');
  }
  const defaultStableOk = toNumber(elements.settingsDefaultStableOk && elements.settingsDefaultStableOk.value);
  if (defaultStableOk !== undefined && defaultStableOk < 0) {
    throw new Error('Stable OK window must be >= 0');
  }
  const defaultBackupInitial = toNumber(elements.settingsDefaultBackupInitial && elements.settingsDefaultBackupInitial.value);
  if (defaultBackupInitial !== undefined && defaultBackupInitial < 0) {
    throw new Error('Backup initial delay must be >= 0');
  }
  const defaultBackupStart = toNumber(elements.settingsDefaultBackupStart && elements.settingsDefaultBackupStart.value);
  if (defaultBackupStart !== undefined && defaultBackupStart < 0) {
    throw new Error('Backup start delay must be >= 0');
  }
  const defaultBackupReturn = toNumber(elements.settingsDefaultBackupReturn && elements.settingsDefaultBackupReturn.value);
  if (defaultBackupReturn !== undefined && defaultBackupReturn < 0) {
    throw new Error('Backup return delay must be >= 0');
  }
  const defaultBackupStop = toNumber(elements.settingsDefaultBackupStop && elements.settingsDefaultBackupStop.value);
  if (defaultBackupStop !== undefined && defaultBackupStop < 5) {
    throw new Error('Stop if all inactive must be >= 5');
  }
  const defaultBackupWarmMax = toNumber(elements.settingsDefaultBackupWarmMax && elements.settingsDefaultBackupWarmMax.value);
  if (defaultBackupWarmMax !== undefined && defaultBackupWarmMax < 0) {
    throw new Error('Active warm inputs max must be >= 0');
  }
  const defaultHttpKeepActive = toNumber(elements.settingsDefaultHttpKeepActive && elements.settingsDefaultHttpKeepActive.value);
  if (defaultHttpKeepActive !== undefined && defaultHttpKeepActive < -1) {
    throw new Error('HTTP keep active must be -1 or >= 0');
  }
  const watchdogEnabled = elements.settingsWatchdogEnabled && elements.settingsWatchdogEnabled.checked;
  const watchdogCpu = toNumber(elements.settingsWatchdogCpu && elements.settingsWatchdogCpu.value);
  if (watchdogCpu !== undefined && (watchdogCpu < 0 || watchdogCpu > 100)) {
    throw new Error('Watchdog CPU limit must be 0-100');
  }
  const watchdogRssMb = toNumber(elements.settingsWatchdogRssMb && elements.settingsWatchdogRssMb.value);
  if (watchdogRssMb !== undefined && watchdogRssMb < 0) {
    throw new Error('Watchdog RSS MB must be >= 0');
  }
  const watchdogRssPct = toNumber(elements.settingsWatchdogRssPct && elements.settingsWatchdogRssPct.value);
  if (watchdogRssPct !== undefined && (watchdogRssPct < 0 || watchdogRssPct > 100)) {
    throw new Error('Watchdog RSS % must be 0-100');
  }
  const watchdogInterval = toNumber(elements.settingsWatchdogInterval && elements.settingsWatchdogInterval.value);
  if (watchdogInterval !== undefined && watchdogInterval < 5) {
    throw new Error('Watchdog interval must be >= 5');
  }
  const watchdogStrikes = toNumber(elements.settingsWatchdogStrikes && elements.settingsWatchdogStrikes.value);
  if (watchdogStrikes !== undefined && watchdogStrikes < 1) {
    throw new Error('Watchdog max strikes must be >= 1');
  }
  const watchdogUptime = toNumber(elements.settingsWatchdogUptime && elements.settingsWatchdogUptime.value);
  if (watchdogUptime !== undefined && watchdogUptime < 0) {
    throw new Error('Watchdog min uptime must be >= 0');
  }
  const payload = {
    ui_splitter_enabled: elements.settingsShowSplitter ? elements.settingsShowSplitter.checked : false,
    ui_buffer_enabled: elements.settingsShowBuffer ? elements.settingsShowBuffer.checked : false,
    ui_access_enabled: elements.settingsShowAccess ? elements.settingsShowAccess.checked : true,
    epg_export_interval_sec: epgInterval || 0,
  };
  if (elements.settingsEventRequest) {
    payload.event_request = elements.settingsEventRequest.value.trim();
  }
  if (elements.settingsTelegramEnabled) payload.telegram_enabled = telegramEnabled;
  if (elements.settingsTelegramLevel) payload.telegram_level = telegramLevel || 'OFF';
  if (elements.settingsTelegramChatId) payload.telegram_chat_id = telegramChatId;
  if (telegramToken) payload.telegram_bot_token = telegramToken;
  if (elements.settingsTelegramBackupEnabled) payload.telegram_backup_enabled = telegramBackupEnabled;
  if (elements.settingsTelegramBackupSchedule) {
    payload.telegram_backup_schedule = telegramBackupSchedule || 'DAILY';
  }
  if (elements.settingsTelegramBackupTime) payload.telegram_backup_time = telegramBackupTime || '03:00';
  if (telegramBackupWeekday !== undefined) payload.telegram_backup_weekday = telegramBackupWeekday;
  if (telegramBackupMonthday !== undefined) payload.telegram_backup_monthday = telegramBackupMonthday;
  if (elements.settingsTelegramBackupSecrets) payload.telegram_backup_include_secrets = telegramBackupSecrets;
  if (elements.settingsTelegramSummaryEnabled) payload.telegram_summary_enabled = telegramSummaryEnabled;
  if (elements.settingsTelegramSummarySchedule) {
    payload.telegram_summary_schedule = telegramSummarySchedule || 'DAILY';
  }
  if (elements.settingsTelegramSummaryTime) payload.telegram_summary_time = telegramSummaryTime || '08:00';
  if (telegramSummaryWeekday !== undefined) payload.telegram_summary_weekday = telegramSummaryWeekday;
  if (telegramSummaryMonthday !== undefined) payload.telegram_summary_monthday = telegramSummaryMonthday;
  if (elements.settingsTelegramSummaryCharts) payload.telegram_summary_include_charts = telegramSummaryCharts;
  if (elements.settingsAiEnabled) payload.ai_enabled = aiEnabled;
  if (elements.settingsAiApiKey) {
    const key = elements.settingsAiApiKey.value.trim();
    if (key) payload.ai_api_key = key;
  }
  if (elements.settingsAiApiBase) {
    payload.ai_api_base = elements.settingsAiApiBase.value.trim();
  }
  if (elements.settingsAiModel) payload.ai_model = elements.settingsAiModel.value.trim();
  payload.ai_chart_mode = 'spec';
  if (aiMaxTokens !== undefined) payload.ai_max_tokens = aiMaxTokens;
  if (aiTemperature !== undefined) payload.ai_temperature = aiTemperature;
  if (elements.settingsAiAllowedChats) {
    payload.ai_telegram_allowed_chat_ids = elements.settingsAiAllowedChats.value.trim();
  }
  if (elements.settingsAiStore) payload.ai_store = elements.settingsAiStore.checked;
  if (elements.settingsAiAllowApply) payload.ai_allow_apply = elements.settingsAiAllowApply.checked;
  if (monitorMax !== undefined) payload.monitor_analyze_max_concurrency = monitorMax;
  if (previewMax !== undefined) payload.preview_max_sessions = previewMax;
  if (previewIdle !== undefined) payload.preview_idle_timeout_sec = previewIdle;
  if (previewTtl !== undefined) payload.preview_token_ttl_sec = previewTtl;
  if (logMax !== undefined) payload.log_max_entries = logMax;
  if (logRetention !== undefined) payload.log_retention_sec = logRetention;
  if (accessLogMax !== undefined) payload.access_log_max_entries = accessLogMax;
  if (accessLogRetention !== undefined) payload.access_log_retention_sec = accessLogRetention;
  if (elements.settingsObservabilityEnabled) {
    if (observabilityEnabled) {
      payload.ai_logs_retention_days = observabilityLogsDays || 7;
      payload.ai_metrics_retention_days = observabilityOnDemand ? 0 : (observabilityMetricsDays || 30);
      payload.ai_rollup_interval_sec = observabilityRollup || 60;
    } else {
      payload.ai_logs_retention_days = 0;
      payload.ai_metrics_retention_days = 0;
    }
  }
  if (elements.settingsObservabilityOnDemand) {
    payload.ai_metrics_on_demand = !!observabilityOnDemand;
  }
  if (elements.settingsInfluxEnabled) payload.influx_enabled = influxEnabled;
  if (elements.settingsInfluxUrl) payload.influx_url = elements.settingsInfluxUrl.value.trim();
  if (elements.settingsInfluxOrg) payload.influx_org = elements.settingsInfluxOrg.value.trim();
  if (elements.settingsInfluxBucket) payload.influx_bucket = elements.settingsInfluxBucket.value.trim();
  if (elements.settingsInfluxToken) payload.influx_token = elements.settingsInfluxToken.value.trim();
  if (elements.settingsInfluxInstance) payload.influx_instance = elements.settingsInfluxInstance.value.trim();
  if (elements.settingsInfluxMeasurement) payload.influx_measurement = elements.settingsInfluxMeasurement.value.trim();
  if (influxInterval !== undefined) payload.influx_interval_sec = influxInterval;
  if (elements.settingsFfmpegPath) payload.ffmpeg_path = elements.settingsFfmpegPath.value.trim();
  if (elements.settingsFfprobePath) payload.ffprobe_path = elements.settingsFfprobePath.value.trim();
  if (elements.settingsHttpsBridgeEnabled) {
    payload.https_bridge_enabled = elements.settingsHttpsBridgeEnabled.checked;
  }
  if (influxEnabled) {
    const influxUrl = elements.settingsInfluxUrl ? elements.settingsInfluxUrl.value.trim() : '';
    if (!influxUrl || !/^https?:\/\//i.test(influxUrl)) {
      throw new Error('Influx URL must start with http://');
    }
    if (elements.settingsInfluxOrg && !elements.settingsInfluxOrg.value.trim()) {
      throw new Error('Influx org is required when export is enabled');
    }
    if (elements.settingsInfluxBucket && !elements.settingsInfluxBucket.value.trim()) {
      throw new Error('Influx bucket is required when export is enabled');
    }
  }
  if (elements.settingsHttpCsrf) payload.http_csrf_enabled = elements.settingsHttpCsrf.checked;
  if (sessionTtl !== undefined) payload.auth_session_ttl_sec = sessionTtl;
  if (loginRateLimit !== undefined) payload.rate_limit_login_per_min = loginRateLimit;
  if (loginRateWindow !== undefined) payload.rate_limit_login_window_sec = loginRateWindow;
  if (defaultNoDataTimeout !== undefined) payload.no_data_timeout_sec = defaultNoDataTimeout;
  if (defaultProbeInterval !== undefined) payload.probe_interval_sec = defaultProbeInterval;
  if (defaultStableOk !== undefined) payload.stable_ok_sec = defaultStableOk;
  if (defaultBackupInitial !== undefined) payload.backup_initial_delay_sec = defaultBackupInitial;
  if (defaultBackupStart !== undefined) payload.backup_start_delay_sec = defaultBackupStart;
  if (defaultBackupReturn !== undefined) payload.backup_return_delay_sec = defaultBackupReturn;
  if (defaultBackupStop !== undefined) payload.backup_stop_if_all_inactive_sec = defaultBackupStop;
  if (defaultBackupWarmMax !== undefined) payload.backup_active_warm_max = defaultBackupWarmMax;
  if (defaultHttpKeepActive !== undefined) payload.http_keep_active = defaultHttpKeepActive;
  if (elements.settingsWatchdogEnabled) payload.resource_watchdog_enabled = watchdogEnabled;
  if (watchdogCpu !== undefined) payload.resource_watchdog_cpu_pct = watchdogCpu;
  if (watchdogRssMb !== undefined) payload.resource_watchdog_rss_mb = watchdogRssMb;
  if (watchdogRssPct !== undefined) payload.resource_watchdog_rss_pct = watchdogRssPct;
  if (watchdogInterval !== undefined) payload.resource_watchdog_interval_sec = watchdogInterval;
  if (watchdogStrikes !== undefined) payload.resource_watchdog_max_strikes = watchdogStrikes;
  if (watchdogUptime !== undefined) payload.resource_watchdog_min_uptime_sec = watchdogUptime;
  return payload;
}

function collectCasSettings() {
  if (!elements.casDefault) return {};
  return { cas_default: elements.casDefault.checked };
}

function collectPasswordPolicySettings() {
  const minLength = toNumber(elements.passwordMinLength && elements.passwordMinLength.value);
  if (minLength !== undefined && minLength < 0) {
    throw new Error('Password min length must be >= 0');
  }
  const payload = {};
  if (minLength !== undefined) payload.password_min_length = minLength;
  if (elements.passwordRequireLetter) payload.password_require_letter = elements.passwordRequireLetter.checked;
  if (elements.passwordRequireNumber) payload.password_require_number = elements.passwordRequireNumber.checked;
  if (elements.passwordRequireSymbol) payload.password_require_symbol = elements.passwordRequireSymbol.checked;
  if (elements.passwordRequireMixed) payload.password_require_mixed_case = elements.passwordRequireMixed.checked;
  if (elements.passwordDisallowUsername) payload.password_disallow_username = elements.passwordDisallowUsername.checked;
  return payload;
}

function collectHlsSettings() {
  const storage = elements.hlsStorage ? elements.hlsStorage.value : 'disk';
  const maxMb = toNumber(elements.hlsMaxBytesMb && elements.hlsMaxBytesMb.value);
  const maxBytes = (maxMb !== undefined ? Math.max(0, maxMb) : 64) * 1024 * 1024;
  return {
    hls_duration: toNumber(elements.hlsDuration.value) || 6,
    hls_quantity: toNumber(elements.hlsQuantity.value) || 5,
    hls_storage: storage,
    hls_on_demand: elements.hlsOnDemand ? elements.hlsOnDemand.checked : (storage === 'memfd'),
    hls_idle_timeout_sec: toNumber(elements.hlsIdleTimeout && elements.hlsIdleTimeout.value) || 30,
    hls_max_bytes_per_stream: Math.floor(maxBytes),
    hls_max_segments: toNumber(elements.hlsMaxSegments && elements.hlsMaxSegments.value) || 12,
    hls_naming: elements.hlsNaming.value,
    hls_session_timeout: toNumber(elements.hlsSessionTimeout.value) || 60,
    hls_resource_path: elements.hlsResourcePath.value,
    hls_round_duration: elements.hlsRoundDuration.checked,
    hls_use_expires: elements.hlsExpires.checked,
    hls_pass_data: elements.hlsPassData.checked,
    hls_m3u_headers: elements.hlsM3uHeaders.checked,
    hls_ts_extension: elements.hlsTsExtension.value.trim() || 'ts',
    hls_ts_mime: elements.hlsTsMime.value.trim() || 'video/MP2T',
    hls_ts_headers: elements.hlsTsHeaders.checked,
  };
}

function updateHttpPlayHlsStorageWarning() {
  if (!elements.httpPlayHlsStorageWarning || !elements.httpPlayHls || !elements.hlsStorage) {
    return;
  }
  const hlsEnabled = elements.httpPlayHls.checked;
  // В конфиге `hls_storage` может отсутствовать, но в UI select всегда имеет значение.
  const storage = String(elements.hlsStorage.value || 'disk');
  elements.httpPlayHlsStorageWarning.hidden = !(hlsEnabled && storage !== 'memfd');
}

function applyHlsMemfdPreset() {
  if (!elements.hlsStorage) return;
  elements.hlsStorage.value = 'memfd';
  if (elements.hlsOnDemand) {
    elements.hlsOnDemand.checked = true;
  }
  // Не перетираем ввод пользователя: проставляем дефолты только если поля пустые.
  if (elements.hlsIdleTimeout && !String(elements.hlsIdleTimeout.value || '').trim()) {
    elements.hlsIdleTimeout.value = '30';
  }
  if (elements.hlsMaxBytesMb && !String(elements.hlsMaxBytesMb.value || '').trim()) {
    elements.hlsMaxBytesMb.value = '64';
  }
  if (elements.hlsMaxSegments && !String(elements.hlsMaxSegments.value || '').trim()) {
    elements.hlsMaxSegments.value = '12';
  }
  updateHlsStorageUi();
}

function updateHlsStorageUi() {
  if (!elements.hlsStorage) return;
  const isMemfd = elements.hlsStorage.value === 'memfd';
  // Показываем memfd-only поля только когда выбран memfd.
  $$('.hls-memfd-only').forEach((el) => {
    el.hidden = !isMemfd;
  });
  updateHttpPlayHlsStorageWarning();
}

function collectHttpPlaySettings() {
  return {
    http_play_allow: elements.httpPlayAllow.checked,
    http_play_hls: elements.httpPlayHls.checked,
    http_play_port: toNumber(elements.httpPlayPort.value) || getSettingNumber('http_port', 8000),
    http_play_no_tls: elements.httpPlayNoTls.checked,
    http_play_logos: elements.httpPlayLogos.value.trim(),
    http_play_screens: elements.httpPlayScreens.value.trim(),
    http_play_playlist_name: elements.httpPlayPlaylistName.value.trim() || 'playlist.m3u8',
    http_play_arrange: elements.httpPlayArrange.value.trim() || 'tv',
    http_play_buffer_kb: toNumber(elements.httpPlayBuffer.value) || 4000,
    http_play_m3u_header: elements.httpPlayM3uHeader.value.trim(),
    http_play_xspf_title: elements.httpPlayXspfTitle.value.trim(),
  };
}

function collectBufferSettings() {
  return {
    buffer_enabled: elements.bufferSettingEnabled.checked,
    buffer_listen_host: elements.bufferSettingHost.value.trim() || '0.0.0.0',
    buffer_listen_port: toNumber(elements.bufferSettingPort.value) || 8089,
    buffer_source_bind_interface: elements.bufferSettingSourceInterface.value.trim(),
    buffer_max_clients_total: toNumber(elements.bufferSettingMaxClients.value) || 2000,
    buffer_client_read_timeout_sec: toNumber(elements.bufferSettingClientTimeout.value) || 20,
  };
}

function collectHttpAuthSettings() {
  return {
    http_auth_enabled: elements.httpAuthEnabled.checked,
    http_auth_users: elements.httpAuthUsers.checked,
    http_auth_allow: elements.httpAuthAllow.value.trim(),
    http_auth_deny: elements.httpAuthDeny.value.trim(),
    http_auth_tokens: elements.httpAuthTokens.value.trim(),
    http_auth_realm: elements.httpAuthRealm.value.trim() || 'Astra',
    auth_on_play_url: elements.authOnPlayUrl.value.trim(),
    auth_on_publish_url: elements.authOnPublishUrl.value.trim(),
    auth_timeout_ms: toNumber(elements.authTimeoutMs.value) || 3000,
    auth_default_duration_sec: toNumber(elements.authDefaultDuration.value) || 180,
    auth_deny_cache_sec: toNumber(elements.authDenyCache.value) || 180,
    auth_hash_algo: elements.authHashAlgo.value || 'sha1',
    auth_hls_rewrite_token: elements.authHlsRewrite.checked,
    auth_admin_bypass_enabled: elements.authAdminBypass.checked,
    auth_allow_no_token: elements.authAllowNoToken.checked,
    auth_overlimit_policy: elements.authOverlimitPolicy.value || 'deny_new',
  };
}

async function saveSettings(update, opts = {}) {
  await apiJson('/api/v1/settings', {
    method: 'PUT',
    body: JSON.stringify(update),
  });

  const shouldReload = opts.reload !== false;
  if (shouldReload) {
    await loadSettings();
  } else {
    // Не перерисовываем все поля (иначе можно потерять несохранённый ввод в форме).
    state.settings = state.settings || {};
    Object.keys(update || {}).forEach((key) => {
      state.settings[key] = update[key];
    });
  }

  if (!opts.silent) {
    setStatus(opts.status || 'Settings saved');
  }
}

let httpPlayToggleSaveTimer = null;

function scheduleHttpPlayToggleSave() {
  if (!elements.httpPlayAllow || !elements.httpPlayHls) return;
  updateHttpPlayHlsStorageWarning();
  if (httpPlayToggleSaveTimer) {
    clearTimeout(httpPlayToggleSaveTimer);
  }
  httpPlayToggleSaveTimer = setTimeout(() => {
    httpPlayToggleSaveTimer = null;
    const patch = {
      http_play_allow: elements.httpPlayAllow.checked,
      http_play_hls: elements.httpPlayHls.checked,
    };
    saveSettings(patch, {
      reload: false,
      status: 'HTTP Play access saved (restart to apply).',
    }).catch((err) => setStatus(err.message));
  }, 250);
}

async function requestRestart() {
  try {
    await apiJson('/api/v1/reload', { method: 'POST' });
    setStatus('Reloading...', 'sticky');
    setTimeout(() => {
      window.location.reload();
    }, 1500);
  } catch (err) {
    const message = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
    setStatus(message);
  }
}

async function loadSettings() {
  try {
    const data = await apiJson('/api/v1/settings');
    state.settings = data || {};
  } catch (err) {
    state.settings = {};
  }
  state.groups = normalizeGroups(state.settings.groups);
  state.servers = normalizeServers(state.settings.servers);
  state.softcams = normalizeSoftcams(state.settings.softcam);
  refreshInputCamOptions();

  applySettingsToUI();
}

function setConfigEditHint(message, isError) {
  if (!elements.configEditHint) return;
  elements.configEditHint.textContent = message || '';
  elements.configEditHint.classList.toggle('is-error', !!isError);
}

function getConfigExportUrl() {
  const params = [
    'include_users=1',
    'include_settings=1',
    'include_streams=1',
    'include_adapters=1',
    'include_softcam=1',
    'include_splitters=1',
  ];
  return `/api/v1/export?${params.join('&')}`;
}

async function loadFullConfig(force) {
  if (!elements.configEditor) return;
  if (state.configEditorDirty && !force) {
    const confirmed = window.confirm('Overwrite unsaved config changes?');
    if (!confirmed) return;
  }
  setConfigEditHint('Loading full config...', false);
  try {
    const data = await apiJson(getConfigExportUrl());
    const text = JSON.stringify(data || {}, null, 2);
    elements.configEditor.value = text ? `${text}\n` : '';
    state.configEditorDirty = false;
    state.configEditorLoaded = true;
    setConfigEditHint('Full config loaded from server.', false);
  } catch (err) {
    const message = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
    setConfigEditHint(message || 'Failed to load config', true);
    setStatus(message || 'Failed to load config');
  }
}

async function saveFullConfig() {
  if (!elements.configEditor) return;
  let payload = null;
  try {
    payload = JSON.parse(elements.configEditor.value || '{}');
  } catch (err) {
    setConfigEditHint('Invalid JSON: ' + (err.message || 'parse error'), true);
    setStatus('Invalid JSON config');
    return;
  }
  const mode = elements.configEditMode ? elements.configEditMode.value : 'replace';
  if (mode === 'replace') {
    const confirmed = window.confirm('Replace current config with this JSON?');
    if (!confirmed) return;
  }
  setConfigEditHint('Applying config...', false);
  try {
    const result = await apiJson('/api/v1/import', {
      method: 'POST',
      body: JSON.stringify({ mode, config: payload }),
    });
    const summary = result && result.summary ? result.summary : null;
    const summaryText = summary
      ? `settings=${summary.settings || 0}, users=${summary.users || 0}, adapters=${summary.adapters || 0}, streams=${summary.streams || 0}`
      : 'Config saved';
    state.configEditorDirty = false;
    setConfigEditHint(`Config applied (${mode}). ${summaryText}`, false);
    setStatus('Config saved and applied');
    await refreshAll();
    await loadConfigHistory();
    await loadFullConfig(true);
  } catch (err) {
    const message = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
    setConfigEditHint(message || 'Failed to apply config', true);
    setStatus(message || 'Failed to apply config');
  }
}

function renderConfigHistory() {
  if (!elements.configHistoryTable) return;
  elements.configHistoryTable.innerHTML = '';

  const header = document.createElement('div');
  header.className = 'table-row header';
  header.innerHTML = '<div>ID</div><div>Status</div><div>User</div><div>Comment</div><div>Created</div><div>Applied</div><div>Error</div><div></div>';
  elements.configHistoryTable.appendChild(header);

  if (!state.configRevisions.length) {
    const empty = document.createElement('div');
    empty.className = 'table-row';
    empty.innerHTML = '<div class="muted">No revisions yet</div>';
    elements.configHistoryTable.appendChild(empty);
    return;
  }

  const activeId = Number(state.settings.config_active_revision_id) || 0;
  const lkgId = Number(state.settings.config_lkg_revision_id) || 0;

  state.configRevisions.forEach((rev) => {
    const row = document.createElement('div');
    row.className = 'table-row';

    const status = formatRevisionStatus(rev.status, rev.id === activeId, rev.id === lkgId);

    const idCell = createEl('div', '', String(rev.id || ''));
    const statusCell = createEl('div', `revision-status ${status.className}`, status.label);
    const userCell = createEl('div', '', rev.created_by || '—');
    const commentCell = createEl('div', '', rev.comment || '—');
    const createdCell = createEl('div', '', formatTimestamp(rev.created_ts));
    const appliedCell = createEl('div', '', formatTimestamp(rev.applied_ts));
    const errorText = rev.error_text || '';
    const errorShort = errorText ? truncateText(errorText, 80) : '—';
    const errorCell = createEl('div', '', errorShort);
    if (errorText) {
      errorCell.title = errorText;
    }

    const actionCell = document.createElement('div');
    actionCell.className = 'revision-action';
    const restoreBtn = createEl('button', 'btn ghost', 'Restore');
    restoreBtn.type = 'button';
    restoreBtn.dataset.action = 'config-restore';
    restoreBtn.dataset.revisionId = String(rev.id || '');
    actionCell.appendChild(restoreBtn);
    if (errorText) {
      const detailsBtn = createEl('button', 'btn ghost', 'Details');
      detailsBtn.type = 'button';
      detailsBtn.dataset.action = 'config-error';
      detailsBtn.dataset.revisionId = String(rev.id || '');
      actionCell.appendChild(detailsBtn);
    }
    const deleteBtn = createEl('button', 'btn ghost', 'Delete');
    deleteBtn.type = 'button';
    deleteBtn.dataset.action = 'config-delete';
    deleteBtn.dataset.revisionId = String(rev.id || '');
    actionCell.appendChild(deleteBtn);

    row.appendChild(idCell);
    row.appendChild(statusCell);
    row.appendChild(userCell);
    row.appendChild(commentCell);
    row.appendChild(createdCell);
    row.appendChild(appliedCell);
    row.appendChild(errorCell);
    row.appendChild(actionCell);

    elements.configHistoryTable.appendChild(row);
  });

  if (elements.configActiveRevision) {
    elements.configActiveRevision.textContent = activeId ? String(activeId) : '—';
  }
  if (elements.configLkgRevision) {
    elements.configLkgRevision.textContent = lkgId ? String(lkgId) : '—';
  }
}

function setConfigErrorOverlay(show) {
  if (!elements.configErrorOverlay) return;
  setOverlay(elements.configErrorOverlay, show);
}

function openConfigErrorModal(revision) {
  if (!revision) return;
  const id = revision.id ? `#${revision.id}` : '';
  const status = formatRevisionStatus(revision.status, false, false);
  if (elements.configErrorTitle) {
    elements.configErrorTitle.textContent = `Config error ${id}`;
  }
  if (elements.configErrorMeta) {
    const user = revision.created_by || '—';
    const created = formatTimestamp(revision.created_ts);
    elements.configErrorMeta.textContent = `Status: ${status.label} · User: ${user} · Created: ${created}`;
  }
  if (elements.configErrorBody) {
    elements.configErrorBody.textContent = revision.error_text || '';
  }
  setConfigErrorOverlay(true);
}

async function deleteConfigRevision(revisionId) {
  const idValue = Number(revisionId);
  if (!Number.isFinite(idValue)) {
    setStatus('Invalid revision id');
    return;
  }
  const confirmed = window.confirm(`Delete config revision ${idValue}?`);
  if (!confirmed) return;
  try {
    await apiJson(`/api/v1/config/revisions/${idValue}`, { method: 'DELETE' });
    await loadConfigHistory();
    setStatus(`Deleted config revision ${idValue}`);
  } catch (err) {
    setStatus(err.message || 'Delete failed');
  }
}

async function deleteAllConfigRevisions() {
  const confirmed = window.confirm('Delete all saved config revisions? This cannot be undone.');
  if (!confirmed) return;
  try {
    await apiJson('/api/v1/config/revisions', { method: 'DELETE' });
    await loadConfigHistory();
    setStatus('Deleted all config revisions');
  } catch (err) {
    setStatus(err.message || 'Delete failed');
  }
}

async function loadConfigHistory() {
  if (!elements.configHistoryTable) return;
  try {
    const data = await apiJson('/api/v1/config/revisions');
    state.configRevisions = Array.isArray(data.revisions) ? data.revisions : [];
    state.settings.config_active_revision_id = data.active_revision_id;
    state.settings.config_lkg_revision_id = data.lkg_revision_id;
    renderConfigHistory();
  } catch (err) {
    state.configRevisions = [];
    renderConfigHistory();
    setStatus(err.message || 'Failed to load config history');
  }
}

async function loadLicense() {
  if (!elements.licenseText || state.licenseLoaded) return;
  if (elements.licenseMeta) elements.licenseMeta.textContent = 'Loading...';
  elements.licenseText.textContent = 'Loading...';
  try {
    const info = await apiJson('/api/v1/license');
    state.licenseLoaded = true;
    const name = info.name || 'License';
    const spdx = info.spdx ? ` (${info.spdx})` : '';
    const path = info.path ? `Source: ${info.path}` : '';
    if (elements.licenseMeta) {
      const meta = [name + spdx, path].filter(Boolean).join(' · ');
      elements.licenseMeta.textContent = meta || name;
    }
    elements.licenseText.textContent = info.text || '';
  } catch (err) {
    state.licenseLoaded = false;
    if (elements.licenseMeta) elements.licenseMeta.textContent = 'Failed to load license';
    elements.licenseText.textContent = err.message || 'Failed to load license';
  }
}

async function restoreConfigRevision(revisionId) {
  if (!revisionId) return;
  const confirmed = window.confirm(`Restore config revision ${revisionId}?`);
  if (!confirmed) return;
  try {
    await apiJson(`/api/v1/config/revisions/${revisionId}/restore`, { method: 'POST' });
    setStatus(`Config restored to revision ${revisionId}`);
    await loadConfigHistory();
    await loadSettings();
    await loadStreams();
  } catch (err) {
    const message = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
    setStatus(message || 'Failed to restore config');
  }
}

async function loadStreams() {
  const data = await apiJson('/api/v1/streams');
  state.streams = Array.isArray(data) ? data : [];
  renderStreams();
  updateObservabilityStreamOptions();
}

async function saveStream(event) {
  event.preventDefault();
  elements.editorError.textContent = '';
  setStreamEditorBusy(true, 'Saving...');

  try {
    const payload = readStreamForm();
    const isNew = state.editing && state.editing.isNew;
    const originalId = state.editing && state.editing.stream && state.editing.stream.id;
    if (!isNew && originalId && payload.id !== originalId) {
      const confirmed = window.confirm(`Rename stream ${originalId} to ${payload.id}?`);
      if (!confirmed) return;
      await apiJson('/api/v1/streams', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      await apiJson(`/api/v1/streams/${originalId}`, { method: 'DELETE' });
      setStatus('Stream renamed');
      closeEditor();
      await loadStreams();
      return;
    }
    if (isNew) {
      await apiJson('/api/v1/streams', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
    } else {
      await apiJson(`/api/v1/streams/${payload.id}`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      });
    }

    setStatus('Stream saved');
    closeEditor();
    if (isNew) {
      try {
        await loadStreams();
      } catch (err) {
        const message = err && err.network
          ? 'Stream saved, but the server is unreachable. Refresh later.'
          : (err && err.message ? err.message : 'Stream saved, but refresh failed');
        setStatus(message);
      }
      return;
    }
    const updated = {
      id: payload.id,
      enabled: payload.enabled,
      config: payload.config || {},
    };
    upsertStreamInState(updated);
    applyStreamUpdate(updated);
    scheduleStreamSync();
  } catch (err) {
    let message = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
    const networkMessage = formatNetworkError(err);
    if (networkMessage) {
      message = networkMessage;
    }
    elements.editorError.textContent = message || 'Failed to save stream';
  } finally {
    setStreamEditorBusy(false);
  }
}

async function toggleStream(stream) {
  const currentEnabled = stream && stream.enabled !== false;
  const nextEnabled = !currentEnabled;
  const payload = {
    enabled: nextEnabled,
  };
  await apiJson(`/api/v1/streams/${stream.id}`, {
    method: 'PUT',
    body: JSON.stringify(payload),
  });
  const updated = {
    id: stream.id,
    enabled: nextEnabled,
    config: stream.config || {},
  };
  upsertStreamInState(updated);
  applyStreamUpdate(updated);
  scheduleStreamSync();
}

async function deleteStream(stream) {
  const confirmed = window.confirm(`Delete stream ${stream.id}?`);
  if (!confirmed) return;
  await apiJson(`/api/v1/streams/${stream.id}`, { method: 'DELETE' });
  setStatus('Stream deleted');
  removeStreamFromState(stream.id);
  applyStreamRemoval(stream.id);
  scheduleStreamSync();
}

function getPlayerStream() {
  if (!state.playerStreamId) return null;
  return state.streamIndex[state.playerStreamId]
    || state.streams.find((item) => item && item.id === state.playerStreamId)
    || null;
}

function resolveAbsoluteUrl(url, base) {
  if (!url) return '';
  try {
    return new URL(url, base || window.location.origin).toString();
  } catch (err) {
    return String(url || '');
  }
}

function getPlayerShareUrls(stream) {
  const play = getPlayUrl(stream) || '';
  const hls = getPlaylistUrl(stream) || '';
  return {
    play,
    // HLS URL обычно доступен на основном HTTP порту (порт UI), поэтому резолвим от origin.
    hls: hls ? resolveAbsoluteUrl(hls, window.location.origin) : '',
  };
}

function getSelectedPlayerShareUrl(stream) {
  const target = stream || getPlayerStream();
  if (!target) return '';
  const urls = getPlayerShareUrls(target);
  if (state.playerShareKind === 'hls') {
    return urls.hls || urls.play || '';
  }
  return urls.play || urls.hls || '';
}

function getPlayerLink() {
  const link = getSelectedPlayerShareUrl() || state.playerUrl;
  if (!link) return '';
  return resolveAbsoluteUrl(link, window.location.origin);
}

function updatePlayerActions() {
  const hasUrl = !!getPlayerLink();
  if (elements.playerOpenTab) elements.playerOpenTab.disabled = !hasUrl;
  if (elements.playerCopyLink) elements.playerCopyLink.disabled = !hasUrl;
}

function updatePlayerShareUi(stream) {
  const target = stream || getPlayerStream();
  if (!target) return;
  const urls = getPlayerShareUrls(target);
  const hasHls = !!urls.hls;

  if (state.playerShareKind === 'hls' && !hasHls) {
    state.playerShareKind = 'play';
  }

  const selected = state.playerShareKind === 'hls'
    ? (urls.hls || urls.play || '')
    : (urls.play || urls.hls || '');

  state.playerShareUrl = selected;
  if (elements.playerUrl) {
    elements.playerUrl.textContent = state.playerShareUrl || '-';
    elements.playerUrl.title = state.playerShareUrl || '';
    if (elements.playerUrl.tagName === 'A') {
      elements.playerUrl.href = state.playerShareUrl || '#';
    }
  }

  if (elements.playerLinkPlay) {
    const active = state.playerShareKind !== 'hls';
    elements.playerLinkPlay.classList.toggle('active', active);
    elements.playerLinkPlay.setAttribute('aria-selected', active ? 'true' : 'false');
  }
  if (elements.playerLinkHls) {
    elements.playerLinkHls.disabled = !hasHls;
    const active = state.playerShareKind === 'hls';
    elements.playerLinkHls.classList.toggle('active', active);
    elements.playerLinkHls.setAttribute('aria-selected', active ? 'true' : 'false');
  }

  updatePlayerActions();
}

function updatePlayerMeta(stream) {
  const target = stream || getPlayerStream();
  if (!target) return;
  const name = (target.config && target.config.name) || target.id;
  if (elements.playerSub) elements.playerSub.textContent = name;
  const stats = state.stats[target.id] || {};
  const enabled = target.enabled !== false;
  const onAir = enabled && stats.on_air === true;
  if (elements.playerStatus) {
    elements.playerStatus.textContent = onAir ? 'ONLINE' : 'OFFLINE';
    elements.playerStatus.classList.toggle('ok', onAir);
    elements.playerStatus.classList.toggle('warn', !onAir);
    elements.playerStatus.title = enabled ? '' : 'Stream disabled';
  }
  if (elements.playerInput) {
    const inputs = Array.isArray(stats.inputs) ? stats.inputs : [];
    const activeIndex = getActiveInputIndex(stats);
    const label = getActiveInputLabel(inputs, activeIndex);
    const activeInput = inputs[Number.isFinite(activeIndex) ? activeIndex : -1];
    const url = activeInput && activeInput.url ? activeInput.url : '';
    elements.playerInput.textContent = label ? `Active input: ${label}` : 'Active input: -';
    elements.playerInput.title = url || '';
  }

  updatePlayerShareUi(target);
}

function setPlayerLoading(active, text) {
  if (!elements.playerLoading) return;
  elements.playerLoading.classList.toggle('active', active);
  elements.playerLoading.setAttribute('aria-hidden', active ? 'false' : 'true');
  const label = elements.playerLoading.querySelector('.player-loading-text');
  if (label) label.textContent = text || 'Подключение...';
}

function clearPlayerError() {
  if (!elements.playerError) return;
  elements.playerError.textContent = '';
  elements.playerError.classList.remove('active');
  elements.playerError.setAttribute('aria-hidden', 'true');
  if (elements.playerRetry) elements.playerRetry.hidden = true;
}

function setPlayerError(message) {
  if (!elements.playerError) return;
  if (state.playerStartTimer) {
    clearTimeout(state.playerStartTimer);
    state.playerStartTimer = null;
  }
  elements.playerError.textContent = message || 'Не удалось загрузить предпросмотр.';
  elements.playerError.classList.add('active');
  elements.playerError.setAttribute('aria-hidden', 'false');
  if (elements.playerRetry) elements.playerRetry.hidden = false;
  setPlayerLoading(false);
}

function resetPlayerMedia() {
  if (state.player) {
    state.player.destroy();
    state.player = null;
  }
  if (elements.playerVideo) {
    elements.playerVideo.pause();
    elements.playerVideo.removeAttribute('src');
    elements.playerVideo.load();
  }
  if (state.playerStartTimer) {
    clearTimeout(state.playerStartTimer);
    state.playerStartTimer = null;
  }
  setPlayerLoading(false);
  clearPlayerError();
}

function formatPreviewError(err) {
  const networkMessage = formatNetworkError(err);
  if (networkMessage) return networkMessage;
  const raw = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
  const text = String(raw || '');
  if (text.toLowerCase().includes('offline')) {
    return 'Поток оффлайн. Запустите источник и попробуйте снова.';
  }
  if (text.toLowerCase().includes('limit')) {
    return 'Слишком много предпросмотров. Закройте другой плеер.';
  }
  if (text.toLowerCase().includes('source')) {
    return 'Нет доступного источника для предпросмотра.';
  }
  return text || 'Не удалось запустить предпросмотр.';
}

function formatVideoError(err) {
  if (!err) return 'Ошибка воспроизведения.';
  if (err.code === 2) return 'Сетевая ошибка. Проверьте доступ к потоку.';
  if (err.code === 3) return 'Нет видео дорожки или формат не поддерживается.';
  if (err.code === 4) return 'Формат не поддерживается браузером.';
  return 'Ошибка воспроизведения.';
}

async function attachPlayerSource(url, opts = {}) {
  resetPlayerMedia();
  if (!url) {
    setPlayerError('Не удалось получить ссылку на предпросмотр.');
    return;
  }
  clearPlayerError();
  setPlayerLoading(true, 'Подключение...');
  state.playerStartTimer = setTimeout(() => {
    setPlayerError('Не удалось запустить предпросмотр. Попробуйте ещё раз.');
  }, 10000);

  if (opts.mode === 'mpegts') {
    elements.playerVideo.src = url;
    return;
  }

  if (canPlayHlsNatively()) {
    elements.playerVideo.src = url;
    return;
  }

  if (!window.Hls) {
    try {
      await ensureHlsJsLoaded();
    } catch (err) {
      setPlayerError('Не удалось загрузить HLS модуль. Проверьте доступ к UI (vendor/hls.min.js).');
      return;
    }
  }

  if (window.Hls && window.Hls.isSupported()) {
    const hls = new window.Hls({ lowLatencyMode: true });
    hls.on(window.Hls.Events.ERROR, (_event, data) => {
      if (data && data.fatal) {
        setPlayerError('Ошибка HLS-потока. Проверьте источник.');
        hls.destroy();
        state.player = null;
      }
    });
    hls.loadSource(url);
    hls.attachMedia(elements.playerVideo);
    state.player = hls;
  } else {
    setPlayerError('HLS playback not supported in this browser.');
  }
}

async function stopPlayerSession() {
  if (state.playerMode !== 'preview' || !state.playerStreamId) return;
  try {
    await apiJson(`/api/v1/streams/${state.playerStreamId}/preview/stop`, { method: 'POST' });
  } catch (err) {
  }
}

async function startPlayer(stream, opts = {}) {
  if (!stream || state.playerStarting) return;
  state.playerStarting = true;
  setPlayerLoading(true, 'Подключение...');
  clearPlayerError();

  let url = null;
  let mode = 'direct';
  let token = null;

  // В браузере гарантированно надёжнее HLS, чем попытка проигрывать MPEG-TS напрямую.
  // /play/* оставляем для "Open in new tab" / "Copy link" (VLC/плееры).
  url = opts.forceVideoOnly ? null : getPlaylistUrl(stream);

  if (!url) {
    try {
      const qs = opts.forceVideoOnly ? '?video_only=1' : '';
      const payload = await apiJson(`/api/v1/streams/${stream.id}/preview/start${qs}`, { method: 'POST' });
      url = payload.url;
      token = payload.token;
      mode = payload.mode || (payload.token ? 'preview' : 'direct');
    } catch (err) {
      setPlayerError(formatPreviewError(err));
      state.playerStarting = false;
      return;
    }
  }

  state.playerMode = (mode === 'preview') ? 'preview' : 'direct';
  state.playerToken = token;
  state.playerUrl = url || '';
  updatePlayerShareUi(stream);
  await attachPlayerSource(url, { mode: 'hls' });
  state.playerStarting = false;

  if (opts.openTab) {
    const link = getPlayerLink();
    if (link) window.open(link, '_blank', 'noopener');
  }
}

function openPlayer(stream) {
  if (!stream) return;
  if (state.playerMode === 'preview' && state.playerStreamId && state.playerStreamId !== stream.id) {
    apiJson(`/api/v1/streams/${state.playerStreamId}/preview/stop`, { method: 'POST' }).catch(() => {});
  }
  state.playerStreamId = stream.id;
  state.playerMode = null;
  state.playerUrl = '';
  state.playerShareUrl = '';
  state.playerShareKind = 'play';
  state.playerToken = null;
  state.playerTriedVideoOnly = false;
  updatePlayerMeta(stream);
  setOverlay(elements.playerOverlay, true);
  startPlayer(stream);
}

async function closePlayer() {
  await stopPlayerSession();
  resetPlayerMedia();
  setOverlay(elements.playerOverlay, false);
  state.playerStreamId = null;
  state.playerMode = null;
  state.playerUrl = '';
  state.playerShareUrl = '';
  state.playerShareKind = 'play';
  state.playerToken = null;
  state.playerTriedVideoOnly = false;
  updatePlayerActions();
}

function buildInputStatusRow(input, index, activeIndex) {
  const row = document.createElement('div');
  row.className = 'input-status-row';

  const state = getInputState(input, index, activeIndex);
  row.classList.add(`state-${state.toLowerCase()}`);
  if (Number.isFinite(activeIndex) && index === activeIndex) {
    row.classList.add('is-active');
  }

  const url = input.url || '';
  const label = getInputLabel(input, index);

  const head = document.createElement('div');
  head.className = 'input-status-head';

  const badge = document.createElement('span');
  badge.className = 'input-badge';
  badge.textContent = state;

  const title = document.createElement('span');
  title.className = 'input-label';
  title.textContent = label;
  if (url) {
    title.title = url;
  }

  const bitrateValue = Number.isFinite(input.bitrate_kbps) ? input.bitrate_kbps : input.bitrate;
  const bitrate = formatBitrate(Number(bitrateValue) || 0);
  const bitrateEl = document.createElement('span');
  bitrateEl.className = 'input-bitrate';
  bitrateEl.textContent = bitrate;

  head.appendChild(badge);
  head.appendChild(title);
  head.appendChild(bitrateEl);

  if (url) {
    const copyButton = document.createElement('button');
    copyButton.type = 'button';
    copyButton.className = 'input-copy';
    copyButton.textContent = 'Copy';
    copyButton.addEventListener('click', (event) => {
      event.stopPropagation();
      copyText(url);
    });
    head.appendChild(copyButton);
  }

  const meta = document.createElement('div');
  meta.className = 'input-status-meta';
  const lastOk = formatTimestamp(input.last_ok_ts);
  const lastError = input.last_error || 'n/a';
  const failCount = Number(input.fail_count) || 0;
  const incompatible = input.incompatible === true;
  const incompatReason = input.incompatible_reason || 'mismatch';
  const incompatText = incompatible ? ` | Incompatible: ${incompatReason}` : '';
  const kfOk = input.keyframe_ok_ts ? formatTimestamp(input.keyframe_ok_ts) : 'n/a';
  const kfMiss = Number(input.keyframe_miss_count) || 0;
  const kfText = input.keyframe_last_ts || input.keyframe_ok_ts
    ? ` | KF: ${kfOk} miss ${kfMiss}`
    : '';
  const sigErr = input.signature_error ? ` | Sig: ${input.signature_error}` : '';
  meta.textContent = `Fail: ${failCount} | Last OK: ${lastOk} | Error: ${lastError}${kfText}${sigErr}${incompatText}`;

  row.appendChild(head);
  row.appendChild(meta);
  return row;
}

function formatHexByte(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return 'n/a';
  return `0x${num.toString(16).toUpperCase().padStart(2, '0')}`;
}

function formatCrc32(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return 'n/a';
  return `0x${num.toString(16).toUpperCase().padStart(8, '0')}`;
}

function formatCasList(items) {
  if (!Array.isArray(items) || items.length === 0) return '';
  return items.map((entry) => {
    if (!entry) return '';
    const caid = Number.isFinite(entry.caid) ? `0x${Number(entry.caid).toString(16).toUpperCase().padStart(4, '0')}` : 'n/a';
    const pid = Number.isFinite(entry.pid) ? String(entry.pid) : 'n/a';
    return `caid=${caid} pid=${pid}`;
  }).filter(Boolean).join('; ');
}

function updateAnalyzeHeaderFromTotals(totals, onAir) {
  if (!totals) return;
  const cc = Number(totals.cc_errors) || 0;
  const pes = Number(totals.pes_errors) || 0;
  if (elements.analyzeRate) {
    elements.analyzeRate.textContent = formatMaybeBitrate(totals.bitrate);
    elements.analyzeRate.classList.toggle('warn', !onAir);
  }
  if (elements.analyzeCc) {
    elements.analyzeCc.textContent = `CC:${cc}`;
    elements.analyzeCc.classList.toggle('ok', cc === 0);
    elements.analyzeCc.classList.toggle('warn', cc > 0);
  }
  if (elements.analyzePes) {
    elements.analyzePes.textContent = `PES:${pes}`;
    elements.analyzePes.classList.toggle('ok', pes === 0);
    elements.analyzePes.classList.toggle('warn', pes > 0);
  }
}

function renderAnalyzeSections(sections) {
  elements.analyzeBody.innerHTML = '';
  const copyLines = [];
  const pushCopy = (text, indent = 0) => {
    if (!text) return;
    const prefix = indent > 0 ? ' '.repeat(indent) : '';
    copyLines.push(`${prefix}${text}`);
  };
  const addCopyItems = (items, indent = 2) => {
    if (!Array.isArray(items)) return;
    items.forEach((item) => {
      if (!item) return;
      if (item.nodeType) return;
      if (typeof item === 'string') {
        pushCopy(`- ${item}`, indent);
        return;
      }
      if (typeof item === 'object') {
        if (item.text) {
          pushCopy(`- ${item.text}`, indent);
        }
        const subs = item.sub || item.subs;
        if (subs) {
          const list = Array.isArray(subs) ? subs : [subs];
          list.forEach((subline) => {
            if (subline) pushCopy(String(subline), indent + 2);
          });
        }
      }
    });
  };
  sections.forEach((section) => {
    if (!section) return;
    const block = document.createElement('div');
    block.className = 'analyze-section';
    if (section.title) {
      const title = document.createElement('div');
      title.className = 'analyze-title';
      title.textContent = section.title;
      block.appendChild(title);
      pushCopy(section.title, 0);
    }
    if (section.meta) {
      const meta = document.createElement('div');
      meta.className = 'analyze-meta';
      meta.textContent = section.meta;
      block.appendChild(meta);
      pushCopy(section.meta, 2);
    }
    if (section.body && section.body.nodeType) {
      block.appendChild(section.body);
    }
    const items = Array.isArray(section.items) ? section.items : [];
    const listItems = [];
    const nodeItems = [];
    items.forEach((item) => {
      if (item && item.nodeType) {
        nodeItems.push(item);
      } else {
        listItems.push(item);
      }
    });
    if (listItems.length) {
      const list = document.createElement('ul');
      list.className = 'analyze-list';
      listItems.forEach((item) => {
        if (!item) return;
        const li = document.createElement('li');
        li.className = 'analyze-item';
        if (typeof item === 'string') {
          li.textContent = item;
        } else if (typeof item === 'object') {
          li.textContent = item.text || '';
          const subs = item.sub || item.subs;
          if (subs) {
            const subList = Array.isArray(subs) ? subs : [subs];
            subList.forEach((subline) => {
              if (!subline) return;
              const sub = document.createElement('div');
              sub.className = 'analyze-subline';
              sub.textContent = subline;
              li.appendChild(sub);
            });
          }
        }
        list.appendChild(li);
      });
      block.appendChild(list);
      addCopyItems(listItems, 2);
    }
    nodeItems.forEach((node) => {
      block.appendChild(node);
    });
    const subsections = Array.isArray(section.subsections) ? section.subsections : [];
    if (subsections.length) {
      const wrap = document.createElement('div');
      wrap.className = 'analyze-subsections';
      subsections.forEach((sub) => {
        if (!sub) return;
        const subBlock = document.createElement('div');
        subBlock.className = 'analyze-subsection';
        if (sub.title) {
          const subtitle = document.createElement('div');
          subtitle.className = 'analyze-subtitle';
          subtitle.textContent = sub.title;
          subBlock.appendChild(subtitle);
          pushCopy(sub.title, 2);
        }
        const subItems = Array.isArray(sub.items) ? sub.items : [];
        if (subItems.length) {
          const subList = document.createElement('ul');
          subList.className = 'analyze-list';
          subItems.forEach((item) => {
            if (!item) return;
            const li = document.createElement('li');
            li.className = 'analyze-item';
            if (typeof item === 'string') {
              li.textContent = item;
            } else if (typeof item === 'object') {
              li.textContent = item.text || '';
              const subs = item.sub || item.subs;
              if (subs) {
                const subLines = Array.isArray(subs) ? subs : [subs];
                subLines.forEach((subline) => {
                  if (!subline) return;
                  const subEl = document.createElement('div');
                  subEl.className = 'analyze-subline';
                  subEl.textContent = subline;
                  li.appendChild(subEl);
                });
              }
            }
            subList.appendChild(li);
          });
          subBlock.appendChild(subList);
          addCopyItems(subItems, 4);
        }
        wrap.appendChild(subBlock);
      });
      block.appendChild(wrap);
    }
    elements.analyzeBody.appendChild(block);
  });
  const copyText = copyLines.join('\n').trim();
  state.analyzeCopyText = copyText;
  if (elements.analyzeCopy) {
    elements.analyzeCopy.disabled = !copyText;
  }
}

function buildAnalyzeBaseSections(stream, stats) {
  const sections = [];
  const name = (stream.config && stream.config.name) || stream.id;
  sections.push({
    title: 'Stream',
    items: [
      `Name: ${name}`,
      `ID: ${stream.id}`,
    ],
  });

  const transcodeState = stats.transcode_state || (stats.transcode && stats.transcode.state);
  if (transcodeState) {
    const transcode = stats.transcode || {};
    const items = [
      `State: ${transcodeState}`,
      `Per-output: ${transcode.process_per_output ? 'Yes' : 'No'}`,
      `Seamless UDP proxy: ${transcode.seamless_udp_proxy ? 'Yes' : 'No'}`,
    ];
    const alertText = formatTranscodeAlert(transcode.last_alert);
    if (alertText) {
      items.push(`Last alert: ${alertText}`);
    }
    const workers = Array.isArray(transcode.workers) ? transcode.workers : [];
    if (workers.length) {
      workers.forEach((worker) => {
        if (!worker) return;
        const idx = Number.isFinite(worker.output_index) ? worker.output_index : '?';
        const state = worker.state || 'n/a';
        let line = `Worker #${idx}: ${state}`;
        if (worker.pid) line += ` pid=${worker.pid}`;
        if (worker.restart_reason_code) line += ` restart=${worker.restart_reason_code}`;
        if (worker.proxy_enabled) {
          const port = Number(worker.proxy_listen_port) || 0;
          line += port ? ` proxy=127.0.0.1:${port}` : ' proxy=on';
          const src = worker.proxy_active_source || null;
          if (src && src.addr && src.port) {
            line += ` src=${src.addr}:${src.port}`;
          }
          if (Number.isFinite(worker.proxy_senders_count)) {
            line += ` senders=${worker.proxy_senders_count}`;
          }
        }
        items.push(line);
      });
    }
    sections.push({ title: 'Transcode', items });
  }

  const updated = formatTimestamp(stats.updated_at);
  const activeIndex = getActiveInputIndex(stats);
  const inputs = Array.isArray(stats.inputs) ? stats.inputs : [];
  const inputItems = inputs.length
    ? inputs.map((input, index) => buildInputStatusRow(input, index, activeIndex))
    : ['No input stats yet.'];
  const activeInputLabel = getActiveInputLabel(inputs, activeIndex) || 'n/a';
  let lastSwitch = 'n/a';
  if (stats.last_switch) {
    const from = stats.last_switch.from;
    const to = stats.last_switch.to;
    const reason = stats.last_switch.reason || 'n/a';
    const ts = formatTimestamp(stats.last_switch.ts);
    lastSwitch = `${from} -> ${to} (${reason}) @ ${ts}`;
  }
  sections.push(
    {
      title: 'Input status',
      items: [
        `On air: ${stats.on_air ? 'Yes' : 'No'}`,
        `Scrambled: ${stats.scrambled ? 'Yes' : 'No'}`,
        `Active input: ${activeInputLabel}`,
        `Last update: ${updated}`,
        `Last switch: ${lastSwitch}`,
      ],
    },
    {
      title: 'Inputs',
      items: inputItems,
    }
  );
  return sections;
}

function buildAnalyzeProgramLines(programs) {
  if (!Array.isArray(programs) || programs.length === 0) {
    return ['No PSI/PMT data collected.'];
  }
  const lines = [];
  programs.forEach((program) => {
    if (!program) return;
    const name = program.name ? ` ${program.name}` : '';
    const provider = program.provider ? ` (${program.provider})` : '';
    lines.push(`PNR ${program.pnr || 'n/a'}${name}${provider}`);
    lines.push(`  PMT PID: ${program.pmt_pid || 'n/a'} | PCR PID: ${program.pcr || 'n/a'}`);
    const cas = formatCasList(program.cas);
    if (cas) lines.push(`  CAS: ${cas}`);
    const streams = Array.isArray(program.streams) ? program.streams : [];
    if (!streams.length) {
      lines.push('  Streams: n/a');
      return;
    }
    streams.forEach((stream) => {
      if (!stream) return;
      const typeName = stream.type_name || 'unknown';
      const typeId = formatHexByte(stream.type_id);
      const lang = stream.lang ? ` lang=${stream.lang}` : '';
      const streamCas = formatCasList(stream.cas);
      const casText = streamCas ? ` cas=${streamCas}` : '';
      lines.push(`  PID ${stream.pid || 'n/a'} • ${typeName} (${typeId})${lang}${casText}`);
    });
  });
  return lines;
}

function buildAnalyzePidLines(pids, programs) {
  if (!Array.isArray(pids) || pids.length === 0) {
    return ['No PID bitrate stats collected.'];
  }
  const meta = {};
  if (Array.isArray(programs)) {
    programs.forEach((program) => {
      const streams = Array.isArray(program && program.streams) ? program.streams : [];
      streams.forEach((stream) => {
        if (!stream || stream.pid == null) return;
        meta[stream.pid] = {
          type: stream.type_name,
          type_id: stream.type_id,
          lang: stream.lang,
          pnr: program.pnr,
          name: program.name,
        };
      });
    });
  }
  return pids.map((item) => {
    if (!item) return 'PID n/a';
    const details = meta[item.pid] || {};
    const typeName = details.type ? `${details.type} (${formatHexByte(details.type_id)})` : '';
    const lang = details.lang ? ` lang=${details.lang}` : '';
    const program = details.pnr ? ` PNR ${details.pnr}${details.name ? ` (${details.name})` : ''}` : '';
    const metaText = typeName ? ` • ${typeName}${lang}${program}` : (program ? ` •${program}` : '');
    const bitrate = formatMaybeBitrate(item.bitrate);
    const errors = `CC ${item.cc_error || 0} / PES ${item.pes_error || 0} / SCR ${item.sc_error || 0}`;
    return `PID ${item.pid} • ${bitrate}${metaText} • ${errors}`;
  });
}

function normalizeAnalyzePrograms(job) {
  const programs = job && job.programs;
  const list = [];
  if (Array.isArray(programs)) {
    programs.forEach((entry) => {
      if (entry) list.push(entry);
    });
  } else if (programs && typeof programs === 'object') {
    Object.keys(programs).forEach((key) => {
      const entry = programs[key];
      if (!entry) return;
      if (entry.pnr == null) {
        const pnr = Number(key);
        if (Number.isFinite(pnr)) entry.pnr = pnr;
      }
      list.push(entry);
    });
  }
  if (list.length === 0 && Array.isArray(job && job.program_list)) {
    job.program_list.forEach((entry) => {
      if (!entry) return;
      list.push({
        pnr: entry.pnr,
        pmt_pid: entry.pmt_pid,
        pcr: entry.pcr,
        streams: [],
      });
    });
  }
  list.forEach((entry) => {
    entry.pnr = Number.isFinite(Number(entry.pnr)) ? Number(entry.pnr) : entry.pnr;
    entry.pmt_pid = Number.isFinite(Number(entry.pmt_pid)) ? Number(entry.pmt_pid) : entry.pmt_pid;
    entry.pcr = Number.isFinite(Number(entry.pcr)) ? Number(entry.pcr) : entry.pcr;
    entry.streams = Array.isArray(entry.streams) ? entry.streams : [];
  });
  list.sort((a, b) => (Number(a.pnr) || 0) - (Number(b.pnr) || 0));
  return list;
}

function buildAnalyzeServiceMap(job) {
  const map = {};
  const channels = Array.isArray(job && job.channels) ? job.channels : [];
  channels.forEach((item) => {
    if (!item || item.pnr == null) return;
    map[item.pnr] = item;
  });
  const programs = Array.isArray(job && job.program_list) ? job.program_list : [];
  programs.forEach((item) => {
    if (!item || item.pnr == null) return;
    if (!map[item.pnr]) map[item.pnr] = item;
  });
  return map;
}

function getAnalyzeStreamLabel(stream) {
  const desc = stream && stream.descriptor ? String(stream.descriptor).toLowerCase() : '';
  if (desc.startsWith('0x59')) return 'SUB';
  if (desc.startsWith('0x56')) return 'TTX';
  const name = String(stream && stream.type_name ? stream.type_name : '');
  const lower = name.toLowerCase();
  if (lower.includes('video')) return 'VIDEO';
  if (lower.includes('audio')) return 'AUDIO';
  if (lower.includes('subtitle') || lower.includes('sub') || lower.includes('teletext')) return 'SUB';
  return 'PID';
}

function buildAnalyzePatSection(job, programs) {
  const tsid = job && job.pat_tsid != null ? job.pat_tsid : 'n/a';
  const crc = job && job.pat_crc32 != null ? formatCrc32(job.pat_crc32) : '';
  const meta = crc ? `CRC32: ${crc}` : '';
  if (!Array.isArray(programs) || programs.length === 0) {
    return {
      title: `PAT TSID:${tsid}`,
      meta,
      items: ['No PAT data collected.'],
    };
  }
  const items = programs.map((program) => {
    const pnr = program && program.pnr != null ? program.pnr : 'n/a';
    const pid = program && program.pmt_pid != null ? program.pmt_pid : 'n/a';
    return `PNR:${pnr} PID:${pid}`;
  });
  return {
    title: `PAT TSID:${tsid}`,
    meta,
    items,
  };
}

function buildAnalyzePmtSections(job, programs, serviceMap) {
  if (!Array.isArray(programs) || programs.length === 0) {
    return [{
      title: 'PMT',
      items: ['No PMT data collected.'],
    }];
  }
  return programs.map((program) => {
    const pnr = program && program.pnr != null ? program.pnr : 'n/a';
    const service = (serviceMap && serviceMap[pnr]) || {};
    const metaParts = [];
    if (service.name) metaParts.push(`Service: ${service.name}`);
    if (service.provider) metaParts.push(`Provider: ${service.provider}`);
    if (program.crc32 != null) metaParts.push(`CRC32: ${formatCrc32(program.crc32)}`);
    const items = [];
    const pcr = program && program.pcr != null ? program.pcr : 'n/a';
    items.push(`PCR PID:${pcr}`);
    const streams = Array.isArray(program && program.streams) ? program.streams : [];
    if (!streams.length) {
      items.push('Streams: n/a');
    } else {
      streams.forEach((stream) => {
        if (!stream) return;
        const label = getAnalyzeStreamLabel(stream);
        const pid = stream.pid != null ? stream.pid : 'n/a';
        const typeId = formatHexByte(stream.type_id);
        const typeName = stream.type_name ? ` ${stream.type_name}` : '';
        const line = `${label} PID:${pid} TYPE:${typeId}${typeName}`;
        const sub = [];
        if (stream.lang) sub.push(`Language: ${stream.lang}`);
        const cas = formatCasList(stream.cas);
        if (cas) sub.push(`CAS: ${cas}`);
        if (stream.descriptor) sub.push(`Descriptor: ${stream.descriptor}`);
        items.push(sub.length ? { text: line, sub } : line);
      });
    }
    return {
      title: `PMT PNR:${pnr}`,
      meta: metaParts.join(' · '),
      items,
    };
  });
}

function buildAnalyzeSdtSection(job, programs, serviceMap) {
  const tsid = job && job.sdt_tsid != null
    ? job.sdt_tsid
    : (job && job.pat_tsid != null ? job.pat_tsid : 'n/a');
  const crc = job && job.sdt_crc32 != null ? formatCrc32(job.sdt_crc32) : '';
  const meta = crc ? `CRC32: ${crc}` : '';
  if (!Array.isArray(programs) || programs.length === 0) {
    return {
      title: `SDT TSID:${tsid}`,
      meta,
      items: ['No SDT data collected.'],
    };
  }
  const items = programs.map((program) => {
    const pnr = program && program.pnr != null ? program.pnr : 'n/a';
    const service = (serviceMap && serviceMap[pnr]) || {};
    const subs = [
      `Provider: ${service.provider || 'n/a'}`,
      `Service: ${service.name || 'n/a'}`,
    ];
    return { text: `PNR:${pnr}`, sub: subs };
  });
  return {
    title: `SDT TSID:${tsid}`,
    meta,
    items,
  };
}

function buildAnalyzeJobSections(job) {
  if (!job) {
    return [{
      title: 'Analyze details',
      items: ['Analyze job not available.'],
    }];
  }
  if (job.error) {
    return [{
      title: 'Analyze details',
      items: [`Error: ${job.error}`],
    }];
  }
  const totals = job.totals || {};
  const summary = job.summary || {};
  const programs = normalizeAnalyzePrograms(job);
  const serviceMap = buildAnalyzeServiceMap(job);
  const programCount = summary.programs || programs.length || 'n/a';
  const channelCount = summary.channels || (Array.isArray(job.channels) ? job.channels.length : 'n/a');
  const sections = [{
    title: 'Analyze summary',
    items: [
      `Status: ${job.status || 'n/a'}`,
      `Duration: ${job.duration_sec || 'n/a'}s`,
      `Input URL: ${job.input_url || 'n/a'}`,
      `Bitrate: ${formatMaybeBitrate(totals.bitrate)}`,
      `CC errors: ${summary.cc_errors || totals.cc_errors || 0}`,
      `PES errors: ${summary.pes_errors || totals.pes_errors || 0}`,
      `Scrambled: ${totals.scrambled ? 'Yes' : 'No'}`,
      `Programs: ${programCount}`,
      `Channels: ${channelCount}`,
    ],
  }];

  sections.push(buildAnalyzePatSection(job, programs));
  buildAnalyzePmtSections(job, programs, serviceMap).forEach((section) => {
    sections.push(section);
  });
  sections.push(buildAnalyzeSdtSection(job, programs, serviceMap));
  if (Array.isArray(job.pids) && job.pids.length) {
    sections.push({
      title: 'PID details',
      items: buildAnalyzePidLines(job.pids || [], programs || []),
    });
  }
  return sections;
}

function clearAnalyzePoll() {
  if (state.analyzePoll) {
    clearTimeout(state.analyzePoll);
    state.analyzePoll = null;
  }
  state.analyzeJobId = null;
}

function formatAnalyzeError(err) {
  const networkMessage = formatNetworkError(err);
  if (networkMessage) return networkMessage;
  const raw = (err && err.payload && err.payload.error) ? err.payload.error : err.message;
  const text = String(raw || '');
  if (text.toLowerCase().includes('busy')) return 'Analyze is busy. Try again later.';
  if (text.toLowerCase().includes('input url')) return 'No input URL available for analyze.';
  if (text.toLowerCase().includes('transcode')) return 'Analyze is not available for transcode streams.';
  return text || 'Analyze failed to start.';
}

function pollAnalyzeJob(stream, stats, jobId, attempt) {
  const maxAttempts = 20;
  if (state.analyzeStreamId !== stream.id) return;
  apiJson(`/api/v1/streams/analyze/${jobId}`).then((job) => {
    if (state.analyzeStreamId !== stream.id) return;
    if (job.status === 'running' && attempt < maxAttempts) {
      const base = buildAnalyzeBaseSections(stream, stats);
      const sections = base.concat([{
        title: 'Analyze details',
        items: ['Analyzing...'],
      }]);
      renderAnalyzeSections(sections);
      state.analyzePoll = setTimeout(() => {
        pollAnalyzeJob(stream, stats, jobId, attempt + 1);
      }, 500);
      return;
    }
    updateAnalyzeHeaderFromTotals(job.totals, stats.on_air === true);
    const base = buildAnalyzeBaseSections(stream, stats);
    const sections = base.concat(buildAnalyzeJobSections(job));
    renderAnalyzeSections(sections);
  }).catch((err) => {
    if (state.analyzeStreamId !== stream.id) return;
    const base = buildAnalyzeBaseSections(stream, stats);
    const sections = base.concat([{
      title: 'Analyze details',
      items: [formatAnalyzeError(err)],
    }]);
    renderAnalyzeSections(sections);
  });
}

async function startAnalyzeDetails(stream, stats) {
  clearAnalyzePoll();
  state.analyzeStreamId = stream.id;
  const base = buildAnalyzeBaseSections(stream, stats);
  const sections = base.concat([{
    title: 'Analyze details',
    items: ['Starting analyze...'],
  }]);
  renderAnalyzeSections(sections);

  try {
    const payload = await apiJson(`/api/v1/streams/${stream.id}/analyze`, {
      method: 'POST',
      body: JSON.stringify({ duration_sec: 4 }),
    });
    state.analyzeJobId = payload.id;
    pollAnalyzeJob(stream, stats, payload.id, 0);
  } catch (err) {
    const failSections = base.concat([{
      title: 'Analyze details',
      items: [formatAnalyzeError(err)],
    }]);
    renderAnalyzeSections(failSections);
  }
}

function openAnalyze(stream) {
  const stats = state.stats[stream.id] || {};
  const ccErrors = Number(stats.cc_errors) || 0;
  const pesErrors = Number(stats.pes_errors) || 0;
  const onAir = stats.on_air === true;
  const transcode = stats.transcode;
  const transcodeState = stats.transcode_state || (transcode && transcode.state);
  const isTranscode = Boolean(transcodeState);

  clearAnalyzePoll();
  state.analyzeStreamId = null;
  state.analyzeCopyText = '';
  if (elements.analyzeCopy) {
    elements.analyzeCopy.disabled = true;
  }

  if (isTranscode) {
    const inputRate = formatMaybeBitrate(transcode && transcode.input_bitrate_kbps);
    const outputRate = formatMaybeBitrate(transcode && transcode.output_bitrate_kbps);
    elements.analyzeRate.textContent = `In ${inputRate} / Out ${outputRate}`;
    elements.analyzeCc.textContent = `State:${transcodeState || 'n/a'}`;
    elements.analyzePes.textContent = `Progress:${formatTranscodeProgress(transcode && transcode.last_progress)}`;
    const running = transcodeState === 'RUNNING';
    elements.analyzeRate.classList.toggle('warn', !running);
    elements.analyzeCc.classList.toggle('ok', running);
    elements.analyzeCc.classList.toggle('warn', !running);
    elements.analyzePes.classList.toggle('ok', running);
    elements.analyzePes.classList.toggle('warn', !running);
  } else {
    elements.analyzeRate.textContent = formatBitrate(stats.bitrate || 0);
    elements.analyzeCc.textContent = `CC:${ccErrors}`;
    elements.analyzePes.textContent = `PES:${pesErrors}`;
    elements.analyzeCc.classList.toggle('ok', ccErrors === 0);
    elements.analyzePes.classList.toggle('ok', pesErrors === 0);
    elements.analyzeCc.classList.toggle('warn', ccErrors > 0);
    elements.analyzePes.classList.toggle('warn', pesErrors > 0);
    elements.analyzeRate.classList.toggle('warn', !onAir);
  }

  if (isTranscode) {
    const sections = [];
    const updated = formatTimestamp(transcode && transcode.updated_at);
    const lastAlert = transcode && transcode.last_alert
      ? `${transcode.last_alert.code} @ ${formatTimestamp(transcode.last_alert.ts)}`
      : 'n/a';
    const lastError = transcode && transcode.last_error ? transcode.last_error : 'n/a';
    const desync = Number.isFinite(transcode && transcode.desync_ms_last)
      ? `${Math.round(transcode.desync_ms_last)} ms`
      : 'n/a';
    const inputRate = formatMaybeBitrate(transcode && transcode.input_bitrate_kbps);
    const outputRate = formatMaybeBitrate(transcode && transcode.output_bitrate_kbps);
    const inputOk = formatTimestamp(transcode && transcode.input_last_ok_ts);
    const outputOk = formatTimestamp(transcode && transcode.output_last_ok_ts);
    const inputErr = transcode && transcode.input_last_error ? transcode.input_last_error : 'n/a';
    const outputErr = transcode && transcode.output_last_error ? transcode.output_last_error : 'n/a';
    const restartCode = transcode && transcode.restart_reason_code ? transcode.restart_reason_code : 'n/a';
    const restartMeta = formatRestartMeta(transcode && transcode.restart_reason_meta);
    const exitCode = Number.isFinite(transcode && transcode.ffmpeg_exit_code)
      ? String(transcode.ffmpeg_exit_code)
      : 'n/a';
    const exitSignal = Number.isFinite(transcode && transcode.ffmpeg_exit_signal)
      ? String(transcode.ffmpeg_exit_signal)
      : 'n/a';
    const gpuInfo = formatGpuInfo(transcode);
    const gpuError = transcode && transcode.gpu_metrics_error ? transcode.gpu_metrics_error : 'n/a';
    const gpuOverload = transcode && transcode.gpu_overload_reason
      ? formatGpuOverloadReason(transcode.gpu_overload_reason)
      : 'n/a';
    const outputsStatus = Array.isArray(transcode && transcode.outputs_status)
      ? transcode.outputs_status
      : [];
    const mainOut = outputsStatus.find((entry) => entry.output_index === 1) || outputsStatus[0];
    const outputCc = Number.isFinite(transcode && transcode.output_cc_errors)
      ? String(transcode.output_cc_errors)
      : (mainOut && Number.isFinite(mainOut.cc_errors) ? String(mainOut.cc_errors) : 'n/a');
    const outputPes = Number.isFinite(transcode && transcode.output_pes_errors)
      ? String(transcode.output_pes_errors)
      : (mainOut && Number.isFinite(mainOut.pes_errors) ? String(mainOut.pes_errors) : 'n/a');
    const outputScrambled = (transcode && transcode.output_scrambled)
      ? 'Yes'
      : (mainOut && mainOut.scrambled_active ? 'Yes' : 'No');
    const outputScrambledCount = mainOut && Number.isFinite(mainOut.scrambled_errors)
      ? String(mainOut.scrambled_errors)
      : 'n/a';
    const formatPsiAge = (ts, timeout) => {
      if (!ts) return 'n/a';
      const age = Math.max(0, Math.floor(Date.now() / 1000) - ts);
      if (timeout && timeout > 0) {
        return age > timeout
          ? `late ${formatShortDuration(age)}`
          : 'ok';
      }
      return `${formatShortDuration(age)} ago`;
    };
    const outputPat = mainOut
      ? formatPsiAge(mainOut.psi_pat_ts, mainOut.pat_timeout_sec)
      : 'n/a';
    const outputPmt = mainOut
      ? formatPsiAge(mainOut.psi_pmt_ts, mainOut.pmt_timeout_sec)
      : 'n/a';
    const outputMin = Number.isFinite(transcode && transcode.output_bitrate_min_kbps)
      ? `${Math.round(transcode.output_bitrate_min_kbps)} Kbit/s`
      : 'n/a';
    const outputMax = Number.isFinite(transcode && transcode.output_bitrate_max_kbps)
      ? `${Math.round(transcode.output_bitrate_max_kbps)} Kbit/s`
      : 'n/a';
    const outputVariance = Number.isFinite(transcode && transcode.output_cbr_variance_pct)
      ? `${Math.round(transcode.output_cbr_variance_pct)}%`
      : 'n/a';
    const outputCbr = transcode && transcode.output_cbr_unstable ? 'Unstable' : 'OK';
    const switchPending = transcode && transcode.switch_pending
      ? `to #${transcode.switch_pending.target}` +
        `${transcode.switch_pending.target_url ? ` (${shortInputLabel(transcode.switch_pending.target_url)})` : ''}` +
        ` @ ${formatTimestamp(transcode.switch_pending.ready_at)}`
      : 'n/a';
    const switchPendingSince = transcode && transcode.switch_pending && transcode.switch_pending.created_at
      ? formatTimestamp(transcode.switch_pending.created_at)
      : 'n/a';
    const switchPendingTimeout = Number.isFinite(transcode && transcode.switch_pending_timeout_sec)
      ? `${transcode.switch_pending_timeout_sec}s`
      : 'n/a';
    const returnPending = transcode && transcode.return_pending
      ? `to #${transcode.return_pending.target}` +
        `${transcode.return_pending.target_url ? ` (${shortInputLabel(transcode.return_pending.target_url)})` : ''}` +
        ` @ ${formatTimestamp(transcode.return_pending.ready_at)}`
      : 'n/a';
    const switchGrace = transcode && transcode.switch_grace_until
      ? formatTimestamp(transcode.switch_grace_until)
      : 'n/a';
    const warmup = transcode && transcode.switch_warmup;
    let warmupStatus = warmup ? formatWarmupSummary(warmup) : 'n/a';
    if (warmup && warmup.start_ts) {
      warmupStatus += ` (start ${formatTimestamp(warmup.start_ts)})`;
    }
    const warmupDetails = warmup
      ? [
        `Target: ${Number.isFinite(warmup.target) ? `#${warmup.target}` : 'n/a'}`,
        `Ready: ${warmup.ready ? 'Yes' : 'No'}`,
        `Stable: ${warmup.stable_ok ? 'Yes' : 'No'}`,
        `Require IDR: ${warmup.require_idr ? 'Yes' : 'No'}`,
        `IDR seen: ${warmup.idr_seen ? 'Yes' : 'No'}`,
        `Last out_time_ms: ${Number.isFinite(warmup.last_out_time_ms) ? Math.round(warmup.last_out_time_ms) : 'n/a'}`,
        `Min out_time_ms: ${Number.isFinite(warmup.min_out_time_ms) ? Math.round(warmup.min_out_time_ms) : 'n/a'}`,
        `Stable sec: ${Number.isFinite(warmup.stable_sec) ? Math.round(warmup.stable_sec) : 'n/a'}`,
        `Ready at: ${warmup.ready_ts ? formatTimestamp(warmup.ready_ts) : 'n/a'}`,
        `Last progress: ${warmup.last_progress_ts ? formatTimestamp(warmup.last_progress_ts) : 'n/a'}`,
        `Error: ${warmup.error || 'n/a'}`,
      ]
      : null;
    const warmupTimeline = warmup
      ? [
        `Start: ${warmup.start_ts ? formatTimestamp(warmup.start_ts) : 'n/a'}`,
        `Ready: ${warmup.ready_ts ? formatTimestamp(warmup.ready_ts) : 'n/a'}`,
        `Last progress: ${warmup.last_progress_ts ? formatTimestamp(warmup.last_progress_ts) : 'n/a'}`,
        `Deadline: ${warmup.deadline_ts ? formatTimestamp(warmup.deadline_ts) : 'n/a'}`,
      ]
      : null;
    const outputs = Array.isArray(transcode && transcode.outputs) ? transcode.outputs : [];
    const outputItems = outputs.length
      ? outputs.map((out, index) => {
        const url = out && out.url ? out.url : out;
        const label = url ? shortInputLabel(url) : `Output ${index + 1}`;
        return `#${index + 1} ${label}`;
      })
      : ['No outputs configured.'];
    sections.push({
      title: 'Transcode',
      items: [
        `State: ${transcodeState || 'n/a'}`,
        `PID: ${(transcode && transcode.pid) || 'n/a'}`,
        `Restarts (10m): ${(transcode && transcode.restarts_10min) || 0}`,
        `Progress: ${formatTranscodeProgress(transcode && transcode.last_progress)}`,
        `Input bitrate: ${inputRate}`,
        `Output bitrate: ${outputRate}`,
        `Output bitrate range: ${outputMin} / ${outputMax} (variance ${outputVariance}, ${outputCbr})`,
        `Input last OK: ${inputOk}`,
        `Output last OK: ${outputOk}`,
        `Input last error: ${inputErr}`,
        `Output last error: ${outputErr}`,
        `Output CC errors: ${outputCc}`,
        `Output PES errors: ${outputPes}`,
        `Output scrambled: ${outputScrambled} (count ${outputScrambledCount})`,
        `Output PAT: ${outputPat}`,
        `Output PMT: ${outputPmt}`,
        `Switch pending: ${switchPending}`,
        `Switch pending since: ${switchPendingSince}`,
        `Switch pending timeout: ${switchPendingTimeout}`,
        `Return pending: ${returnPending}`,
        `Switch warmup: ${warmupStatus}`,
        `Switch grace until: ${switchGrace}`,
        `Last restart: ${restartCode}`,
        `Restart detail: ${restartMeta}`,
        `FFmpeg exit code: ${exitCode}`,
        `FFmpeg exit signal: ${exitSignal}`,
        `GPU: ${gpuInfo}`,
        `GPU metrics error: ${gpuError}`,
        `GPU overload reason: ${gpuOverload}`,
        `Last alert: ${lastAlert}`,
        `Last error: ${lastError}`,
        `Last desync: ${desync}`,
        `Last update: ${updated}`,
      ],
    });
    sections.push({
      title: 'Outputs',
      items: outputItems,
    });
    if (warmupTimeline) {
      sections.push({
        title: 'Warmup timeline',
        items: warmupTimeline,
      });
    }
    if (warmupDetails) {
      sections.push({
        title: 'Warmup details',
        items: warmupDetails,
      });
    }
    const inputs = Array.isArray(transcode && transcode.inputs_status) ? transcode.inputs_status : [];
    const activeInputIndex = Number.isFinite(transcode && transcode.active_input_index)
      ? transcode.active_input_index
      : null;
    const inputItems = inputs.length
      ? inputs.map((input, index) => buildInputStatusRow(input, index, activeInputIndex))
      : ['No input stats yet.'];
    sections.push({
      title: 'Inputs',
      items: inputItems,
    });
    const stderrTail = Array.isArray(transcode && transcode.stderr_tail) ? transcode.stderr_tail : [];
    if (stderrTail.length) {
      sections.push({
        title: 'Transcode stderr (tail)',
        items: stderrTail.slice(-12),
      });
    }
    renderAnalyzeSections(sections);
    elements.analyzeRestart.hidden = false;
    state.activeAnalyzeId = stream.id;
    setOverlay(elements.analyzeOverlay, true);
    return;
  }

  elements.analyzeRestart.hidden = true;
  state.activeAnalyzeId = null;
  setOverlay(elements.analyzeOverlay, true);
  startAnalyzeDetails(stream, stats);
}

function closeAnalyze() {
  state.activeAnalyzeId = null;
  clearAnalyzePoll();
  state.analyzeStreamId = null;
  state.analyzeCopyText = '';
  if (elements.analyzeCopy) {
    elements.analyzeCopy.disabled = true;
  }
  setOverlay(elements.analyzeOverlay, false);
}

async function restartAnalyzeTranscode() {
  if (!state.activeAnalyzeId) return;
  try {
    await apiJson(`/api/v1/transcode/${state.activeAnalyzeId}/restart`, { method: 'POST' });
  } catch (err) {
    setStatus(err.message);
  }
}

function setAiChatStatus(text) {
  if (elements.aiChatStatus) {
    elements.aiChatStatus.textContent = text || '';
  }
}

function buildAiChatContent(text, attachments) {
  const wrap = createEl('div', 'ai-chat-content');
  if (text) {
    wrap.appendChild(createEl('div', '', text));
  }
  if (Array.isArray(attachments) && attachments.length) {
    const holder = createEl('div', 'ai-chat-user-attachments');
    attachments.forEach((file) => {
      if (file && file.data_url && file.mime && file.mime.startsWith('image/')) {
        const img = document.createElement('img');
        img.src = file.data_url;
        img.alt = file.name || 'attachment';
        holder.appendChild(img);
      }
    });
    if (holder.children.length) {
      wrap.appendChild(holder);
    }
  }
  return wrap;
}

function appendAiChatMessage(role, content) {
  if (!elements.aiChatLog) return null;
  const msg = createEl('div', `ai-chat-msg ${role || 'assistant'}`);
  if (content && content.nodeType) {
    msg.appendChild(content);
  } else {
    msg.textContent = content || '';
  }
  elements.aiChatLog.appendChild(msg);
  elements.aiChatLog.scrollTop = elements.aiChatLog.scrollHeight;
  return msg;
}

function buildTypingNode() {
  const wrap = createEl('div', 'ai-chat-waiting');
  wrap.appendChild(createEl('div', 'ai-chat-waiting-photo'));
  const dots = createEl('div', 'ai-chat-typing');
  dots.appendChild(createEl('span'));
  dots.appendChild(createEl('span'));
  dots.appendChild(createEl('span'));
  wrap.appendChild(dots);
  return wrap;
}

function buildAiErrorNode(message, detail) {
  const wrap = createEl('div');
  wrap.appendChild(createEl('div', '', message || 'AI error'));
  const extra = (detail || '').trim();
  if (extra) {
    // Preserve newlines for debugging details without dumping raw JSON blobs.
    wrap.appendChild(createEl('div', 'form-hint form-hint-pre is-error', extra));
  }
  return wrap;
}

function formatAiJobMeta(job) {
  if (!job) return '';
  const parts = [];
  if (job.model) parts.push(`model=${job.model}`);
  const attempts = Number.isFinite(job.attempts) ? job.attempts : null;
  const max = Number.isFinite(job.max_attempts) ? job.max_attempts : null;
  if (attempts != null && max != null) parts.push(`attempt=${attempts}/${max}`);
  if (attempts != null && max == null) parts.push(`attempt=${attempts}`);
  if (job.error && typeof job.error === 'string' && job.error.trim()) parts.push(`last=${job.error.trim()}`);
  if (job.rate_limits && typeof job.rate_limits === 'object') {
    const rl = job.rate_limits;
    const rlParts = [];
    if (rl.requests_remaining != null) rlParts.push(`req_rem=${rl.requests_remaining}`);
    if (rl.tokens_remaining != null) rlParts.push(`tok_rem=${rl.tokens_remaining}`);
    if (rl.reset_seconds != null) rlParts.push(`reset=${rl.reset_seconds}s`);
    if (rlParts.length) parts.push(`rate(${rlParts.join(' ')})`);
  }
  return parts.join(' ');
}

function computeAiNextPollDelayMs(job) {
  if (!job || job.status !== 'retry') return 1500;
  const next = Number(job.next_try_ts);
  if (!Number.isFinite(next) || next <= 0) return 2500;
  const now = Math.floor(Date.now() / 1000);
  const remain = Math.max(0, next - now);
  // If the next retry is far away, avoid hammering /ai/jobs.
  if (remain >= 8) return 8000;
  if (remain >= 4) return 4000;
  return 2000;
}

function formatAiJobStatus(job) {
  if (!job) return 'AI...';
  const status = job.status || 'running';
  const attempts = Number.isFinite(job.attempts) ? job.attempts : null;
  const max = Number.isFinite(job.max_attempts) ? job.max_attempts : null;
  const attemptText = attempts != null && max != null ? ` (attempt ${attempts}/${max})` : '';
  if (status === 'retry') {
    const next = Number(job.next_try_ts);
    if (Number.isFinite(next) && next > 0) {
      const now = Math.floor(Date.now() / 1000);
      const remain = Math.max(0, next - now);
      const remainText = remain > 0 ? `, next in ${remain}s` : ', retrying...';
      const last = job.error ? ` ${job.error}` : '';
      return `AI retry${attemptText}${last}${remainText}`;
    }
    return `AI retry${attemptText}...`;
  }
  return `AI ${status}${attemptText}...`;
}

function getAiHelpHints() {
  const root = document.getElementById('help-bubbles');
  if (root) {
    const hints = [];
    root.querySelectorAll('.help-bubble').forEach((el) => {
      const text = (el.textContent || '').trim();
      if (text) hints.push(text);
    });
    if (hints.length) return hints;
  }
  return [
    'help',
    'refresh channel <id>',
    'show channel graphs (24h)',
    'show errors last 24h',
    'analyze stream <id>',
    'scan dvb adapter <n>',
    'list busy adapters',
    'check signal lock (femon)',
    'backup config now',
    'restart stream <id>',
  ];
}

function buildAiHelpNode() {
  const wrapper = createEl('div');
  wrapper.appendChild(createEl('div', 'form-note', 'Quick hints:'));
  const list = createEl('div', 'help-bubbles');
  getAiHelpHints().forEach((hint) => {
    list.appendChild(createEl('div', 'help-bubble', hint));
  });
  wrapper.appendChild(list);
  return wrapper;
}

function clearAiChatPolling() {
  if (state.aiChatPoll) {
    clearTimeout(state.aiChatPoll);
    state.aiChatPoll = null;
  }
  state.aiChatJobId = null;
  state.aiChatBusy = false;
  if (elements.aiChatSend) elements.aiChatSend.disabled = false;
  if (elements.aiChatStop) elements.aiChatStop.disabled = true;
}

function collectAiChatCliList() {
  const cli = [];
  if (elements.aiChatCliStream && elements.aiChatCliStream.checked) cli.push('stream');
  if (elements.aiChatCliDvbls && elements.aiChatCliDvbls.checked) cli.push('dvbls');
  if (elements.aiChatCliAnalyze && elements.aiChatCliAnalyze.checked) cli.push('analyze');
  if (elements.aiChatCliFemon && elements.aiChatCliFemon.checked) cli.push('femon');
  return cli;
}

function readAiChatFile(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error('Failed to read file'));
    reader.readAsDataURL(file);
  });
}

async function collectAiChatAttachments() {
  if (!elements.aiChatFiles || !elements.aiChatFiles.files) return [];
  const files = Array.from(elements.aiChatFiles.files);
  if (files.length === 0) return [];
  const maxFiles = 2;
  const maxBytes = 1500000;
  const out = [];
  for (let i = 0; i < files.length && out.length < maxFiles; i += 1) {
    const file = files[i];
    if (file.size > maxBytes) {
      setAiChatStatus(`Attachment too large: ${file.name}`);
      continue;
    }
    const dataUrl = await readAiChatFile(file);
    out.push({ data_url: dataUrl, mime: file.type, name: file.name });
  }
  return out;
}

function updateAiChatFilesLabel() {
  if (!elements.aiChatFiles || !elements.aiChatFilesLabel) return;
  const files = Array.from(elements.aiChatFiles.files || []);
  if (elements.aiChatFilePreviews) {
    elements.aiChatFilePreviews.innerHTML = '';
  }
  if (state.aiChatPreviewUrls && state.aiChatPreviewUrls.length) {
    state.aiChatPreviewUrls.forEach((url) => {
      try { URL.revokeObjectURL(url); } catch (err) {}
    });
    state.aiChatPreviewUrls = [];
  }
  if (files.length === 0) {
    elements.aiChatFilesLabel.textContent = 'No attachments';
    return;
  }
  elements.aiChatFilesLabel.textContent = files.map((file) => file.name).join(', ');
  if (!elements.aiChatFilePreviews) return;
  const maxFiles = 2;
  files.slice(0, maxFiles).forEach((file) => {
    const preview = createEl('div', 'ai-chat-file-preview');
    if (file.type && file.type.startsWith('image/')) {
      const img = document.createElement('img');
      const url = URL.createObjectURL(file);
      state.aiChatPreviewUrls.push(url);
      img.src = url;
      img.alt = file.name;
      preview.appendChild(img);
    }
    preview.appendChild(createEl('div', '', file.name));
    elements.aiChatFilePreviews.appendChild(preview);
  });
}

function buildAiChatPayload(prompt, attachments) {
  const payload = { prompt };
  if (elements.aiChatIncludeLogs) {
    payload.include_logs = elements.aiChatIncludeLogs.checked;
  }
  const cli = collectAiChatCliList();
  if (elements.aiChatStreamId && elements.aiChatStreamId.value.trim()) {
    payload.stream_id = elements.aiChatStreamId.value.trim();
    if (!cli.includes('stream')) cli.push('stream');
  }
  if (elements.aiChatAnalyzeUrl && elements.aiChatAnalyzeUrl.value.trim()) {
    payload.input_url = elements.aiChatAnalyzeUrl.value.trim();
    if (!cli.includes('analyze')) cli.push('analyze');
  }
  if (elements.aiChatFemonUrl && elements.aiChatFemonUrl.value.trim()) {
    payload.femon_url = elements.aiChatFemonUrl.value.trim();
    if (!cli.includes('femon')) cli.push('femon');
  }
  if (cli.length) {
    payload.include_cli = cli;
  }
  if (attachments && attachments.length) {
    payload.attachments = attachments;
  }
  return payload;
}

function renderAiPlanResult(job) {
  const wrapper = document.createElement('div');
  const plan = job && job.result && job.result.plan;
  if (!plan) {
    wrapper.appendChild(createEl('div', '', 'No plan data returned.'));
    return wrapper;
  }
  wrapper.appendChild(createEl('div', '', plan.summary || 'Plan ready.'));
  if (Array.isArray(plan.help_lines) && plan.help_lines.length) {
    const helpBlock = createEl('div', 'ai-help-lines');
    plan.help_lines.forEach((line) => {
      helpBlock.appendChild(createEl('div', '', `- ${line}`));
    });
    wrapper.appendChild(helpBlock);
  }
  if (Array.isArray(plan.charts) && plan.charts.length) {
    const charts = renderAiCharts(plan.charts);
    if (charts) wrapper.appendChild(charts);
  }
  if (Array.isArray(plan.warnings) && plan.warnings.length) {
    const warn = createEl('div', 'form-note', `Warnings: ${plan.warnings.join('; ')}`);
    wrapper.appendChild(warn);
  }
  if (Array.isArray(plan.ops) && plan.ops.length) {
    const list = document.createElement('div');
    plan.ops.forEach((op) => {
      const line = createEl(
        'div',
        '',
        `- ${op.op || 'op'} ${op.target || ''} ${op.field ? '(' + op.field + ')' : ''} ${op.value !== undefined ? '=' + op.value : ''}`
      );
      list.appendChild(line);
    });
    wrapper.appendChild(list);
  }
  const diff = job && job.result && job.result.diff;
  const diffError = job && job.result && job.result.diff_error;
  if (diffError) {
    wrapper.appendChild(createEl('div', 'form-note', `Diff preview failed: ${diffError}`));
  }
  if (diff && diff.sections) {
    const diffBlock = document.createElement('div');
    diffBlock.className = 'ai-summary-section';
    diffBlock.appendChild(createEl('div', 'ai-summary-label', 'Diff preview'));
    Object.keys(diff.sections).forEach((key) => {
      const section = diff.sections[key];
      if (!section) return;
      const added = Array.isArray(section.added) ? section.added.length : 0;
      const removed = Array.isArray(section.removed) ? section.removed.length : 0;
      const updated = Array.isArray(section.updated) ? section.updated.length : 0;
      const line = createEl('div', 'ai-summary-item', `${key}: +${added} ~${updated} -${removed}`);
      diffBlock.appendChild(line);
    });
    wrapper.appendChild(diffBlock);
  }
  const allowApply = getSettingBool('ai_allow_apply', false);
  if (allowApply && job && job.id) {
    const applyBtn = createEl('button', 'btn', 'Apply plan');
    applyBtn.type = 'button';
    applyBtn.addEventListener('click', async () => {
      applyBtn.disabled = true;
      try {
        await apiJson('/api/v1/ai/apply', {
          method: 'POST',
          body: JSON.stringify({
            plan_id: job.id,
            mode: 'merge',
            comment: 'ai chat apply',
          }),
        });
        appendAiChatMessage('system', 'Applied plan successfully.');
      } catch (err) {
        appendAiChatMessage('system', `Apply failed: ${formatNetworkError(err) || err.message}`);
      } finally {
        applyBtn.disabled = false;
      }
    });
    wrapper.appendChild(applyBtn);
  }
  return wrapper;
}

async function fetchAiJob(jobId) {
  const payload = await apiJson('/api/v1/ai/jobs');
  if (Array.isArray(payload)) {
    return payload.find((job) => job.id === jobId) || null;
  }
  if (payload && Array.isArray(payload.jobs)) {
    return payload.jobs.find((job) => job.id === jobId) || null;
  }
  return null;
}

function startAiChatPolling(jobId) {
  clearAiChatPolling();
  state.aiChatJobId = jobId;
  state.aiChatBusy = true;
  if (elements.aiChatSend) elements.aiChatSend.disabled = true;
  if (elements.aiChatStop) elements.aiChatStop.disabled = false;
  const startMs = Date.now();
  const deadlineMs = startMs + (10 * 60 * 1000);

  const scheduleNext = (delayMs) => {
    state.aiChatPoll = setTimeout(() => pollOnce(), delayMs);
  };

  const pollOnce = async () => {
    if (!state.aiChatJobId || state.aiChatJobId !== jobId) return;
    if (Date.now() > deadlineMs) {
      appendAiChatMessage('system', 'AI response timed out.');
      clearAiChatPolling();
      return;
    }
    try {
      const job = await fetchAiJob(jobId);
      if (!job) {
        scheduleNext(1500);
        return;
      }

      if (job.status === 'running' || job.status === 'queued' || job.status === 'retry') {
        setAiChatStatus(formatAiJobStatus(job));
        scheduleNext(computeAiNextPollDelayMs(job));
        return;
      }

      if (state.aiChatPendingEl) {
        state.aiChatPendingEl.remove();
        state.aiChatPendingEl = null;
      }

      if (job.status === 'done') {
        appendAiChatMessage('assistant', renderAiPlanResult(job));
        setAiChatStatus('');
      } else if (job.status === 'error') {
        const detail = job.error_detail && job.error_detail !== job.error ? job.error_detail : '';
        const metaLine = formatAiJobMeta(job);
        const extra = [detail, metaLine].filter(Boolean).join('\n');
        appendAiChatMessage('system', buildAiErrorNode(`AI error: ${job.error || 'unknown'}`, extra));
        setAiChatStatus('');
      }

      clearAiChatPolling();
    } catch (err) {
      const msg = `AI polling error: ${formatNetworkError(err) || err.message}`;
      appendAiChatMessage('system', buildAiErrorNode(msg));
      clearAiChatPolling();
    }
  };

  pollOnce();
}

async function sendAiChatMessage() {
  if (!elements.aiChatInput || state.aiChatBusy) return;
  const prompt = elements.aiChatInput.value.trim();
  if (!prompt) return;
  const normalized = prompt.toLowerCase();
  if (normalized === 'help' || normalized === '/help' || normalized === '?') {
    elements.aiChatInput.value = '';
    appendAiChatMessage('assistant', buildAiHelpNode());
    setAiChatStatus('');
    if (elements.aiChatFiles) {
      elements.aiChatFiles.value = '';
      updateAiChatFilesLabel();
    }
    return;
  }
  const attachments = await collectAiChatAttachments();
  elements.aiChatInput.value = '';
  appendAiChatMessage('user', buildAiChatContent(prompt, attachments));
  if (elements.aiChatFiles) {
    elements.aiChatFiles.value = '';
    updateAiChatFilesLabel();
  }
  const typingMsg = appendAiChatMessage('assistant', buildTypingNode());
  state.aiChatPendingEl = typingMsg;
  setAiChatStatus('Sending to AI...');
  try {
    const payload = buildAiChatPayload(prompt, attachments);
    payload.preview_diff = true;
    const job = await apiJson('/api/v1/ai/plan', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    if (!job || !job.id) {
      throw new Error('AI job failed');
    }
    startAiChatPolling(job.id);
  } catch (err) {
    if (state.aiChatPendingEl) {
      state.aiChatPendingEl.remove();
      state.aiChatPendingEl = null;
    }
    const msg = `AI request failed: ${formatNetworkError(err) || err.message}`;
    appendAiChatMessage('system', buildAiErrorNode(msg));
    setAiChatStatus('');
    clearAiChatPolling();
  }
}

async function submitLogin(event) {
  event.preventDefault();
  elements.loginError.textContent = '';

  try {
    const payload = {
      username: elements.loginUser.value.trim(),
      password: elements.loginPass.value,
    };

    const data = await apiJson('/api/v1/auth/login', {
      method: 'POST',
      body: JSON.stringify(payload),
    });

    if (data.token) {
      state.token = data.token;
      localStorage.setItem('astra_token', data.token);
    }

    setOverlay(elements.loginOverlay, false);
    await refreshAll();
  } catch (err) {
    elements.loginError.textContent = formatNetworkError(err) || err.message;
  }
}

async function logout() {
  try {
    await apiJson('/api/v1/auth/logout', { method: 'POST' });
  } catch (err) {
  }
  state.token = null;
  localStorage.removeItem('astra_token');
  pauseAllPolling();
  setOverlay(elements.loginOverlay, true);
}

async function refreshAll() {
  try {
    await loadSettings();
    await loadAdapters();
    await loadAdapterStatus();
    if (state.currentView === 'adapters') {
      await loadDvbAdapters();
      startDvbPolling();
    }
    await loadSplitters();
    await loadBuffers();
    await loadStreams();
    await loadUsers();
    await loadSessions();
    await loadAccessLog(true);
    if (state.currentView === 'observability') {
      await loadObservability(false);
    }
    setOverlay(elements.loginOverlay, false);
    resumeAllPolling();
  } catch (err) {
    setOverlay(elements.loginOverlay, true);
  }
}

function bindEvents() {
  elements.navLinks.forEach((item) => {
    item.addEventListener('click', (event) => {
      const view = item.dataset.view;
      if (view === 'settings') {
        setView('settings');
        toggleSettingsMenu();
      } else {
        setView(view);
      }
      event.stopPropagation();
    });
  });

  if (elements.settingsGeneralSearch) {
    const applySearch = debounce(() => {
      applySearchFilter(elements.settingsGeneralSearch.value);
    }, 150);
    elements.settingsGeneralSearch.addEventListener('input', () => {
      applySearch();
    });
  }
  if (elements.settingsGeneralMode) {
    elements.settingsGeneralMode.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-mode]');
      if (!button) return;
      setGeneralMode(button.dataset.mode);
    });
  }
  if (elements.settingsGeneralDensity) {
    elements.settingsGeneralDensity.addEventListener('change', () => {
      setGeneralDensity(elements.settingsGeneralDensity.checked);
    });
  }
  if (elements.settingsGeneralNav) {
    elements.settingsGeneralNav.addEventListener('click', (event) => {
      const button = event.target.closest('button[data-section]');
      if (!button) return;
      scrollToGeneralSection(button.dataset.section);
    });
  }
  if (elements.settingsGeneralNavSelect) {
    elements.settingsGeneralNavSelect.addEventListener('change', () => {
      scrollToGeneralSection(elements.settingsGeneralNavSelect.value);
    });
  }
  if (elements.settingsGeneralRoot) {
    elements.settingsGeneralRoot.addEventListener('input', handleGeneralInputChange);
    elements.settingsGeneralRoot.addEventListener('change', handleGeneralInputChange);
    elements.settingsGeneralRoot.addEventListener('click', (event) => {
      const toggleBtn = event.target.closest('[data-action="card-toggle"]');
      if (!toggleBtn) return;
      const cardId = toggleBtn.dataset.cardId;
      const cardState = state.generalCards.find((card) => card.id === cardId);
      if (cardState) {
        setCardOpen(cardState, cardState.bodyEl.hidden);
      }
    });
  }
  if (elements.settingsActionSave) {
    elements.settingsActionSave.addEventListener('click', async () => {
      try {
        await saveSettings(collectGeneralSettings());
      } catch (err) {
        setStatus(err.message);
      }
    });
  }
  if (elements.settingsActionCancel) {
    elements.settingsActionCancel.addEventListener('click', () => {
      applySettingsToUI();
      computeDirtyState({ resetSnapshot: true });
      setStatus('Изменения отменены');
    });
  }
  if (elements.settingsActionReset) {
    elements.settingsActionReset.addEventListener('click', async () => {
      try {
        await loadSettings();
        setStatus('Настройки перезагружены');
      } catch (err) {
        setStatus(err.message || 'Не удалось перезагрузить настройки');
      }
    });
  }
  if (elements.aiApplyConfirmClose) {
    elements.aiApplyConfirmClose.addEventListener('click', () => confirmAiApplyChange(false));
  }
  if (elements.aiApplyConfirmCancel) {
    elements.aiApplyConfirmCancel.addEventListener('click', () => confirmAiApplyChange(false));
  }
  if (elements.aiApplyConfirmOk) {
    elements.aiApplyConfirmOk.addEventListener('click', () => confirmAiApplyChange(true));
  }

  if (elements.observabilityRefresh) {
    elements.observabilityRefresh.addEventListener('click', () => {
      loadObservability(true);
    });
  }
  if (elements.observabilityRange) {
    elements.observabilityRange.addEventListener('change', () => {
      loadObservability(true);
    });
  }
  if (elements.observabilityScope) {
    elements.observabilityScope.addEventListener('change', () => {
      updateObservabilityScopeFields();
      loadObservability(true);
    });
  }
  if (elements.observabilityStream) {
    elements.observabilityStream.addEventListener('change', () => {
      loadObservability(true);
    });
  }
  if (elements.settingsObservabilityOnDemand) {
    elements.settingsObservabilityOnDemand.addEventListener('change', () => {
      updateObservabilityOnDemandFields();
    });
  }
  updateObservabilityScopeFields();

  elements.settingsItems.forEach((item) => {
    item.addEventListener('click', () => {
      setView('settings');
      setSettingsSection(item.dataset.section);
      closeSettingsMenu();
    });
  });

  if (elements.viewOptions.length) {
    elements.viewOptions.forEach((option) => {
      option.addEventListener('click', (event) => {
        const viewMode = option.dataset.viewMode;
        const themeMode = option.dataset.theme;
        const tilesMode = option.dataset.tilesMode;
        const viewToggle = option.dataset.viewToggle;
        if (viewMode) {
          setViewMode(viewMode);
        }
        if (themeMode) {
          setThemeMode(themeMode);
        }
        if (tilesMode) {
          const nextMode = (state.tilesUi && state.tilesUi.mode === 'compact')
            ? 'expanded'
            : 'compact';
          setTilesMode(nextMode);
        }
        if (viewToggle === 'disabled') {
          setShowDisabledStreams(!state.showDisabledStreams);
        }
        closeViewMenu();
        event.stopPropagation();
      });
    });
  }

  if (elements.btnView) {
    elements.btnView.addEventListener('click', (event) => {
      toggleViewMenu();
      event.stopPropagation();
    });
  }

  if (elements.importButton) {
    elements.importButton.addEventListener('click', (event) => {
      event.preventDefault();
      importConfigFile();
    });
  }

  if (elements.btnConfigRefresh) {
    elements.btnConfigRefresh.addEventListener('click', (event) => {
      event.preventDefault();
      loadConfigHistory();
    });
  }
  if (elements.btnConfigLoad) {
    elements.btnConfigLoad.addEventListener('click', (event) => {
      event.preventDefault();
      loadFullConfig(true);
    });
  }
  if (elements.btnConfigSave) {
    elements.btnConfigSave.addEventListener('click', (event) => {
      event.preventDefault();
      saveFullConfig();
    });
  }
  if (elements.configEditor) {
    elements.configEditor.addEventListener('input', () => {
      state.configEditorDirty = true;
      setConfigEditHint('Unsaved changes.', false);
    });
  }
  if (elements.configEditMode) {
    const storedMode = localStorage.getItem('astra_config_edit_mode');
    if (storedMode) {
      elements.configEditMode.value = storedMode;
    }
    elements.configEditMode.addEventListener('change', () => {
      localStorage.setItem('astra_config_edit_mode', elements.configEditMode.value);
    });
  }
  if (elements.btnConfigDeleteAll) {
    elements.btnConfigDeleteAll.addEventListener('click', (event) => {
      event.preventDefault();
      deleteAllConfigRevisions();
    });
  }

  if (elements.configHistoryTable) {
    elements.configHistoryTable.addEventListener('click', (event) => {
      const restoreTarget = event.target.closest('[data-action="config-restore"]');
      if (restoreTarget) {
        const revisionId = restoreTarget.dataset.revisionId;
        if (revisionId) {
          restoreConfigRevision(revisionId);
        }
        return;
      }
      const errorTarget = event.target.closest('[data-action="config-error"]');
      if (errorTarget) {
        const revisionId = Number(errorTarget.dataset.revisionId);
        const revision = state.configRevisions.find((rev) => Number(rev.id) === revisionId);
        if (revision) {
          openConfigErrorModal(revision);
        }
        return;
      }
      const deleteTarget = event.target.closest('[data-action="config-delete"]');
      if (deleteTarget) {
        const revisionId = deleteTarget.dataset.revisionId;
        if (revisionId) {
          deleteConfigRevision(revisionId);
        }
      }
    });
  }

  if (elements.configErrorClose) {
    elements.configErrorClose.addEventListener('click', () => setConfigErrorOverlay(false));
  }
  if (elements.configErrorDone) {
    elements.configErrorDone.addEventListener('click', () => setConfigErrorOverlay(false));
  }
  if (elements.configErrorCopy) {
    elements.configErrorCopy.addEventListener('click', () => {
      if (elements.configErrorBody) {
        copyText(elements.configErrorBody.textContent || '', 'Copied error text');
      }
    });
  }

  document.addEventListener('click', (event) => {
    if (!event.target.closest('#settings-menu') && !event.target.closest('#nav-settings')) {
      closeSettingsMenu();
    }
    if (!event.target.closest('#view-menu') && !event.target.closest('#btn-view')) {
      closeViewMenu();
    }

    if (!event.target.closest('.tile')) {
      closeTileMenus();
    }
  });

  elements.searchInput.addEventListener('input', (event) => {
    searchTerm = event.target.value;
    renderStreams();
  });

  elements.btnNewStream.addEventListener('click', () => {
    openEditor({ id: '', enabled: true, config: { input: [], output: [] } }, true);
  });

  elements.btnNewAdapter.addEventListener('click', () => {
    setView('adapters');
    openAdapterEditor({ id: '', enabled: true, config: {} }, true);
  });

  if (elements.splitterNew) {
    elements.splitterNew.addEventListener('click', () => {
      const baseId = `splitter_${Date.now().toString(36)}`;
      openSplitterEditor({
        id: baseId,
        name: '',
        enable: true,
        port: '',
        in_interface: '',
        out_interface: '',
        logtype: '',
        logpath: '',
        config_path: '',
      }, true);
    });
  }

  if (elements.splitterForm) {
    elements.splitterForm.addEventListener('input', markSplitterDirty);
    elements.splitterForm.addEventListener('change', markSplitterDirty);
    elements.splitterForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      if (elements.splitterError) {
        elements.splitterError.textContent = '';
      }
      try {
        await saveSplitter();
      } catch (err) {
        const message = err.message || 'Failed to save splitter';
        if (elements.splitterError) {
          elements.splitterError.textContent = message;
        }
        setStatus(message);
      }
    });
  }
  if (elements.splitterPresetApply && elements.splitterPreset) {
    elements.splitterPresetApply.addEventListener('click', () => {
      applySplitterPreset(elements.splitterPreset.value);
    });
  }

  if (elements.splitterStart) {
    elements.splitterStart.addEventListener('click', () => startSplitterAction('start'));
  }
  if (elements.splitterStop) {
    elements.splitterStop.addEventListener('click', () => startSplitterAction('stop'));
  }
  if (elements.splitterRestart) {
    elements.splitterRestart.addEventListener('click', () => startSplitterAction('restart'));
  }
  if (elements.splitterApply) {
    elements.splitterApply.addEventListener('click', () => startSplitterAction('apply-config'));
  }
  if (elements.splitterConfig) {
    elements.splitterConfig.addEventListener('click', openSplitterConfigModal);
  }

  if (elements.splitterLinkNew) {
    elements.splitterLinkNew.addEventListener('click', () => openSplitterLinkModal(null));
  }
  if (elements.splitterAllowNew) {
    elements.splitterAllowNew.addEventListener('click', () => openSplitterAllowModal());
  }
  if (elements.splitterLinkClose) {
    elements.splitterLinkClose.addEventListener('click', closeSplitterLinkModal);
  }
  if (elements.splitterLinkCancel) {
    elements.splitterLinkCancel.addEventListener('click', closeSplitterLinkModal);
  }
  if (elements.splitterAllowClose) {
    elements.splitterAllowClose.addEventListener('click', closeSplitterAllowModal);
  }
  if (elements.splitterAllowCancel) {
    elements.splitterAllowCancel.addEventListener('click', closeSplitterAllowModal);
  }
  if (elements.splitterConfigClose) {
    elements.splitterConfigClose.addEventListener('click', closeSplitterConfigModal);
  }
  if (elements.splitterConfigDismiss) {
    elements.splitterConfigDismiss.addEventListener('click', closeSplitterConfigModal);
  }
  if (elements.splitterConfigCopy) {
    elements.splitterConfigCopy.addEventListener('click', () => {
      const text = elements.splitterConfigPreview ? elements.splitterConfigPreview.textContent : '';
      if (!text) {
        setStatus('No config to copy');
        return;
      }
      copyText(text, 'Copied config');
    });
  }
  if (elements.splitterLinkForm) {
    elements.splitterLinkForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveSplitterLink();
      } catch (err) {
        elements.splitterLinkError.textContent = err.message || 'Failed to save link';
      }
    });
  }
  if (elements.splitterAllowForm) {
    elements.splitterAllowForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveSplitterAllow();
      } catch (err) {
        elements.splitterAllowError.textContent = err.message || 'Failed to save allow rule';
      }
    });
  }
  if (elements.splitterAllowTable) {
    elements.splitterAllowTable.addEventListener('click', (event) => {
      const target = event.target.closest('button');
      if (!target) return;
      if (target.dataset.action === 'allow-delete') {
        deleteSplitterAllow(target.dataset.id);
      }
    });
  }

  if (elements.bufferNew) {
    elements.bufferNew.addEventListener('click', () => {
      const draft = defaultBufferResource();
      openBufferEditor(draft, true);
    });
  }
  if (elements.bufferForm) {
    elements.bufferForm.addEventListener('input', markBufferDirty);
    elements.bufferForm.addEventListener('change', markBufferDirty);
    elements.bufferForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveBuffer();
      } catch (err) {
        setStatus(err.message || 'Failed to save buffer');
      }
    });
  }
  if (elements.bufferPresetApply && elements.bufferPreset) {
    elements.bufferPresetApply.addEventListener('click', () => {
      applyBufferPreset(elements.bufferPreset.value);
    });
  }
  if (elements.bufferDelete) {
    elements.bufferDelete.addEventListener('click', () => {
      deleteBuffer();
    });
  }
  if (elements.bufferReload) {
    elements.bufferReload.addEventListener('click', () => {
      reloadBufferRuntime();
    });
  }
  if (elements.bufferRestartReader) {
    elements.bufferRestartReader.addEventListener('click', () => {
      restartBufferReader();
    });
  }
  if (elements.bufferInputNew) {
    elements.bufferInputNew.addEventListener('click', () => openBufferInputModal(null));
  }
  if (elements.bufferInputClose) {
    elements.bufferInputClose.addEventListener('click', closeBufferInputModal);
  }
  if (elements.bufferInputCancel) {
    elements.bufferInputCancel.addEventListener('click', closeBufferInputModal);
  }
  if (elements.bufferInputForm) {
    elements.bufferInputForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveBufferInput();
      } catch (err) {
        elements.bufferInputError.textContent = err.message || 'Failed to save input';
      }
    });
  }
  if (elements.bufferAllowNew) {
    elements.bufferAllowNew.addEventListener('click', () => openBufferAllowModal());
  }
  if (elements.bufferAllowClose) {
    elements.bufferAllowClose.addEventListener('click', closeBufferAllowModal);
  }
  if (elements.bufferAllowCancel) {
    elements.bufferAllowCancel.addEventListener('click', closeBufferAllowModal);
  }
  if (elements.bufferAllowForm) {
    elements.bufferAllowForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveBufferAllow();
      } catch (err) {
        elements.bufferAllowError.textContent = err.message || 'Failed to save allow rule';
      }
    });
  }
  if (elements.bufferCopyUrl) {
    elements.bufferCopyUrl.addEventListener('click', () => {
      const url = elements.bufferOutputUrl.textContent || '';
      copyText(url);
    });
  }

  if (elements.groupNew) {
    elements.groupNew.addEventListener('click', () => openGroupModal(null));
  }
  if (elements.groupClose) {
    elements.groupClose.addEventListener('click', closeGroupModal);
  }
  if (elements.groupCancel) {
    elements.groupCancel.addEventListener('click', closeGroupModal);
  }
  if (elements.groupId) {
    elements.groupId.addEventListener('input', handleGroupIdInput);
  }
  if (elements.groupName) {
    elements.groupName.addEventListener('input', handleGroupNameInput);
  }
  if (elements.groupForm) {
    elements.groupForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveGroup();
      } catch (err) {
        if (elements.groupError) {
          elements.groupError.textContent = err.message || 'Failed to save group';
        }
      }
    });
  }
  if (elements.groupTable) {
    elements.groupTable.addEventListener('click', (event) => {
      const target = event.target.closest('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      const id = target.dataset.id;
      if (action === 'group-edit') {
        const group = (state.groups || []).find((g) => g && g.id === id);
        if (group) openGroupModal(group);
      }
      if (action === 'group-delete') {
        const confirmed = window.confirm(`Delete group ${id}? Streams using it will keep the old value.`);
        if (!confirmed) return;
        deleteGroup(id).catch((err) => setStatus(err.message || 'Delete failed'));
      }
    });
  }

  if (elements.softcamNew) {
    elements.softcamNew.addEventListener('click', () => openSoftcamModal(null));
  }
  if (elements.softcamClose) {
    elements.softcamClose.addEventListener('click', closeSoftcamModal);
  }
  if (elements.softcamCancel) {
    elements.softcamCancel.addEventListener('click', closeSoftcamModal);
  }
  if (elements.softcamId) {
    elements.softcamId.addEventListener('input', handleSoftcamIdInput);
  }
  if (elements.softcamName) {
    elements.softcamName.addEventListener('input', handleSoftcamNameInput);
  }
  if (elements.softcamForm) {
    elements.softcamForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveSoftcam();
      } catch (err) {
        if (elements.softcamError) {
          elements.softcamError.textContent = err.message || 'Failed to save softcam';
        }
      }
    });
  }
  if (elements.softcamTable) {
    elements.softcamTable.addEventListener('click', (event) => {
      const target = event.target.closest('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      const id = target.dataset.id;
      if (action === 'softcam-edit') {
        const softcam = (state.softcams || []).find((s) => s && s.id === id);
        if (softcam) openSoftcamModal(softcam);
      }
      if (action === 'softcam-delete') {
        const confirmed = window.confirm(`Delete softcam ${id}?`);
        if (!confirmed) return;
        deleteSoftcam(id).catch((err) => setStatus(err.message || 'Delete failed'));
      }
    });
  }

  if (elements.serverNew) {
    elements.serverNew.addEventListener('click', () => openServerModal(null));
  }
  if (elements.serverClose) {
    elements.serverClose.addEventListener('click', closeServerModal);
  }
  if (elements.serverCancel) {
    elements.serverCancel.addEventListener('click', closeServerModal);
  }
  if (elements.serverId) {
    elements.serverId.addEventListener('input', handleServerIdInput);
  }
  if (elements.serverName) {
    elements.serverName.addEventListener('input', handleServerNameInput);
  }
  if (elements.serverForm) {
    elements.serverForm.addEventListener('submit', async (event) => {
      event.preventDefault();
      try {
        await saveServer();
      } catch (err) {
        if (elements.serverError) {
          elements.serverError.textContent = err.message || 'Failed to save server';
        }
      }
    });
  }
  if (elements.serverTest) {
    elements.serverTest.addEventListener('click', async () => {
      try {
        if (state.serverEditing && state.serverEditing.id) {
          await testServer(state.serverEditing.id);
          return;
        }
        const payload = {
          host: elements.serverHost ? elements.serverHost.value.trim() : '',
          port: toNumber(elements.serverPort && elements.serverPort.value),
          login: elements.serverLogin ? elements.serverLogin.value.trim() : '',
          password: elements.serverPassword ? elements.serverPassword.value : '',
        };
        await testServer(null, payload);
      } catch (err) {
        setStatus(err.message || 'Server test failed');
      }
    });
  }
  if (elements.serverTable) {
    elements.serverTable.addEventListener('click', (event) => {
      const target = event.target.closest('[data-action]');
      if (!target) return;
      const action = target.dataset.action;
      const id = target.dataset.id;
      if (action === 'server-edit') {
        const server = (state.servers || []).find((s) => s && s.id === id);
        if (server) openServerModal(server);
      }
      if (action === 'server-open') {
        openServerUrl(id);
      }
      if (action === 'server-test') {
        testServer(id).catch((err) => setStatus(err.message || 'Server test failed'));
      }
      if (action === 'server-pull') {
        pullServerStreams(id).catch((err) => setStatus(err.message || 'Pull streams failed'));
      }
      if (action === 'server-import') {
        importServerConfig(id).catch((err) => setStatus(err.message || 'Import failed'));
      }
      if (action === 'server-delete') {
        const confirmed = window.confirm(`Delete server ${id}?`);
        if (!confirmed) return;
        deleteServer(id).catch((err) => setStatus(err.message || 'Delete failed'));
      }
    });
  }

  elements.btnLogout.addEventListener('click', logout);

  if (elements.btnSaveHls) {
    elements.btnSaveHls.addEventListener('click', async () => {
      try {
        await saveSettings(collectHlsSettings(), { status: 'HLS settings saved (restart to apply).' });
      } catch (err) {
        setStatus(err.message);
      }
    });
  }
  if (elements.btnApplyHls) {
    elements.btnApplyHls.addEventListener('click', async () => {
      try {
        await saveSettings(collectHlsSettings());
        requestRestart();
      } catch (err) {
        setStatus(err.message);
      }
    });
  }
  if (elements.hlsStorage) {
    elements.hlsStorage.addEventListener('change', updateHlsStorageUi);
  }
  if (elements.btnHlsSwitchMemfd) {
    elements.btnHlsSwitchMemfd.addEventListener('click', () => {
      applyHlsMemfdPreset();
      setSettingsSection('hls');
      setStatus('HLS: switched to Memfd preset (not saved). Use Save & Restart to apply.');
    });
  }

  if (elements.btnApplyCas) {
    elements.btnApplyCas.addEventListener('click', async () => {
      try {
        await saveSettings(collectCasSettings());
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.settingsTelegramTest) {
    elements.settingsTelegramTest.addEventListener('click', async () => {
      try {
        await apiJson('/api/v1/notifications/telegram/test', {
          method: 'POST',
          body: JSON.stringify({}),
        });
        setStatus('Telegram test message queued');
      } catch (err) {
        setStatus(err.message || 'Telegram test failed');
      }
    });
  }

  if (elements.settingsTelegramBackupNow) {
    elements.settingsTelegramBackupNow.addEventListener('click', async () => {
      try {
        await apiJson('/api/v1/notifications/telegram/backup', {
          method: 'POST',
          body: JSON.stringify({}),
        });
        setStatus('Telegram backup queued');
      } catch (err) {
        setStatus(err.message || 'Telegram backup failed');
      }
    });
  }
  if (elements.settingsTelegramSummaryNow) {
    elements.settingsTelegramSummaryNow.addEventListener('click', async () => {
      try {
        await apiJson('/api/v1/notifications/telegram/summary', {
          method: 'POST',
          body: JSON.stringify({}),
        });
        setStatus('Telegram summary queued');
      } catch (err) {
        setStatus(err.message || 'Telegram summary failed');
      }
    });
  }

  if (elements.settingsTelegramBackupSchedule) {
    elements.settingsTelegramBackupSchedule.addEventListener('change', updateTelegramBackupScheduleFields);
  }
  if (elements.settingsTelegramBackupEnabled) {
    elements.settingsTelegramBackupEnabled.addEventListener('change', updateTelegramBackupScheduleFields);
  }
  if (elements.settingsTelegramSummarySchedule) {
    elements.settingsTelegramSummarySchedule.addEventListener('change', updateTelegramSummaryScheduleFields);
  }
  if (elements.settingsTelegramSummaryEnabled) {
    elements.settingsTelegramSummaryEnabled.addEventListener('change', updateTelegramSummaryScheduleFields);
  }

  if (elements.httpPlayAllow) {
    elements.httpPlayAllow.addEventListener('change', scheduleHttpPlayToggleSave);
  }
  if (elements.httpPlayHls) {
    elements.httpPlayHls.addEventListener('change', scheduleHttpPlayToggleSave);
  }

  if (elements.btnSaveHttpPlay) {
    elements.btnSaveHttpPlay.addEventListener('click', async () => {
      try {
        await saveSettings(collectHttpPlaySettings(), { status: 'HTTP Play settings saved (restart to apply).' });
      } catch (err) {
        setStatus(err.message);
      }
    });
  }
  if (elements.btnApplyHttpPlay) {
    elements.btnApplyHttpPlay.addEventListener('click', async () => {
      try {
        await saveSettings(collectHttpPlaySettings());
        requestRestart();
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.btnApplyBuffer) {
    elements.btnApplyBuffer.addEventListener('click', async () => {
      try {
        await saveSettings(collectBufferSettings());
        setStatus('Buffer settings saved');
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.btnSaveHttpAuth) {
    elements.btnSaveHttpAuth.addEventListener('click', async () => {
      try {
        await saveSettings(collectHttpAuthSettings(), { status: 'HTTP auth settings saved (restart to apply).' });
      } catch (err) {
        setStatus(err.message);
      }
    });
  }
  if (elements.btnApplyHttpAuth) {
    elements.btnApplyHttpAuth.addEventListener('click', async () => {
      try {
        await saveSettings(collectHttpAuthSettings());
        requestRestart();
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.btnApplyPasswordPolicy) {
    elements.btnApplyPasswordPolicy.addEventListener('click', async () => {
      try {
        await saveSettings(collectPasswordPolicySettings());
        setStatus('Password policy saved');
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.btnRestart) {
    elements.btnRestart.addEventListener('click', () => {
      requestRestart();
    });
  }

  if (elements.btnUserNew) {
    elements.btnUserNew.addEventListener('click', () => {
      openUserEditor({ username: '', is_admin: false, enabled: true, comment: '' }, 'new');
    });
  }

  if (elements.userClose) {
    elements.userClose.addEventListener('click', closeUserEditor);
  }

  if (elements.userCancel) {
    elements.userCancel.addEventListener('click', closeUserEditor);
  }

  if (elements.userForm) {
    elements.userForm.addEventListener('submit', (event) => {
      event.preventDefault();
      saveUser();
    });
  }

  if (elements.usersTable) {
    elements.usersTable.addEventListener('click', (event) => {
      const action = event.target.closest('[data-action]');
      if (!action) return;
      const username = action.dataset.user;
      if (!username) return;
      const user = state.users.find((item) => item.username === username);
      if (!user) return;
      const mode = action.dataset.action;
      if (mode === 'edit') {
        openUserEditor(user, 'edit');
      } else if (mode === 'reset') {
        openUserEditor(user, 'reset');
      } else if (mode === 'toggle') {
        apiJson(`/api/v1/users/${encodeURIComponent(username)}`, {
          method: 'PUT',
          body: JSON.stringify({ enabled: !user.enabled }),
        })
          .then(loadUsers)
          .catch((err) => setStatus(err.message));
      }
    });
  }

  if (elements.aiChatSend) {
    elements.aiChatSend.addEventListener('click', () => {
      sendAiChatMessage();
    });
  }
  if (elements.aiChatStop) {
    elements.aiChatStop.addEventListener('click', () => {
      clearAiChatPolling();
      setAiChatStatus('Stopped.');
    });
    elements.aiChatStop.disabled = true;
  }
  if (elements.aiChatClear) {
    elements.aiChatClear.addEventListener('click', () => {
      if (elements.aiChatLog) {
        elements.aiChatLog.innerHTML = '';
      }
      setAiChatStatus('');
      if (elements.aiChatInput) elements.aiChatInput.value = '';
      if (elements.aiChatFiles) {
        elements.aiChatFiles.value = '';
        updateAiChatFilesLabel();
      }
    });
  }
  if (elements.aiChatInput) {
    elements.aiChatInput.addEventListener('keydown', (event) => {
      if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
        event.preventDefault();
        sendAiChatMessage();
      }
    });
  }
  if (elements.aiChatFiles) {
    elements.aiChatFiles.addEventListener('change', updateAiChatFilesLabel);
    updateAiChatFilesLabel();
  }

  elements.dashboardStreams.addEventListener('click', (event) => {
    const tile = event.target.closest('.tile');
    if (!tile) return;
    const stream = state.streams.find((s) => s.id === tile.dataset.id);
    if (!stream) return;

    const menuButton = event.target.closest('[data-action="menu"]');
    if (menuButton) {
      const isOpen = tile.getAttribute('data-menu-open') === 'true';
      closeTileMenus(tile);
      tile.setAttribute('data-menu-open', isOpen ? 'false' : 'true');
      return;
    }

    const toggleButton = event.target.closest('[data-action="tile-toggle"]');
    if (toggleButton) {
      const expanded = isTileExpanded(stream.id);
      setTileExpanded(stream.id, !expanded);
      return;
    }

    const action = event.target.closest('.menu-item');
    if (action) {
      handleStreamAction(stream, action.dataset.action);
      closeTileMenus();
      return;
    }

    const header = event.target.closest('.tile-header');
    if (header) {
      const expanded = isTileExpanded(stream.id);
      setTileExpanded(stream.id, !expanded);
      return;
    }

    openEditor(stream, false);
  });

  if (elements.streamTable) {
    elements.streamTable.addEventListener('click', (event) => {
      const row = event.target.closest('tr');
      if (!row) return;
      const stream = state.streams.find((item) => item.id === row.dataset.streamId);
      if (!stream) return;
      const action = event.target.closest('[data-action]');
      if (action && handleStreamAction(stream, action.dataset.action)) {
        return;
      }
    });
  }

  if (elements.streamCompact) {
    elements.streamCompact.addEventListener('click', (event) => {
      const row = event.target.closest('.stream-compact-row');
      if (!row) return;
      const stream = state.streams.find((item) => item.id === row.dataset.streamId);
      if (!stream) return;
      const action = event.target.closest('[data-action]');
      if (action && handleStreamAction(stream, action.dataset.action)) {
        return;
      }
      openEditor(stream, false);
    });
  }

  elements.editorClose.addEventListener('click', closeEditor);
  elements.editorCancel.addEventListener('click', closeEditor);
  if (elements.playerClose) {
    elements.playerClose.addEventListener('click', closePlayer);
  }
  if (elements.playerOpenTab) {
    elements.playerOpenTab.addEventListener('click', () => {
      const link = getPlayerLink();
      if (link) window.open(link, '_blank', 'noopener');
    });
  }
  if (elements.playerCopyLink) {
    elements.playerCopyLink.addEventListener('click', () => {
      const link = getPlayerLink();
      if (link) copyText(link);
    });
  }
  if (elements.playerLinkPlay) {
    elements.playerLinkPlay.addEventListener('click', () => {
      state.playerShareKind = 'play';
      updatePlayerShareUi();
    });
  }
  if (elements.playerLinkHls) {
    elements.playerLinkHls.addEventListener('click', () => {
      state.playerShareKind = 'hls';
      updatePlayerShareUi();
    });
  }
  if (elements.playerRetry) {
    elements.playerRetry.hidden = true;
    elements.playerRetry.addEventListener('click', async () => {
      const stream = getPlayerStream();
      if (!stream) return;
      await stopPlayerSession();
      state.playerTriedVideoOnly = false;
      startPlayer(stream);
    });
  }
  if (elements.playerVideo) {
    elements.playerVideo.addEventListener('playing', () => {
      setPlayerLoading(false);
      clearPlayerError();
      if (state.playerStartTimer) {
        clearTimeout(state.playerStartTimer);
        state.playerStartTimer = null;
      }
    });
    elements.playerVideo.addEventListener('waiting', () => {
      setPlayerLoading(true, 'Буферизация...');
    });
    elements.playerVideo.addEventListener('error', async () => {
      const mediaErr = elements.playerVideo.error;
      // Частый кейс: H.264 видео + MP2 аудио. Браузер не поддерживает MP2,
      // поэтому HLS падает как "format not supported". В предпросмотре
      // можно обойти это без транскодинга, отключив audio.
      if (mediaErr && mediaErr.code === 4) {
        const stream = getPlayerStream();
        if (stream && !state.playerTriedVideoOnly) {
          state.playerTriedVideoOnly = true;
          setPlayerLoading(true, 'Запуск без аудио...');
          clearPlayerError();
          await stopPlayerSession();
          startPlayer(stream, { forceVideoOnly: true });
          return;
        }
      }
      const message = formatVideoError(mediaErr);
      setPlayerError(message);
    });
  }
  elements.analyzeClose.addEventListener('click', closeAnalyze);
  elements.analyzeRestart.addEventListener('click', restartAnalyzeTranscode);
  if (elements.analyzeCopy) {
    elements.analyzeCopy.addEventListener('click', () => {
      if (state.analyzeCopyText) {
        copyText(state.analyzeCopyText);
      }
    });
  }
  if (elements.streamType) {
    elements.streamType.addEventListener('change', () => {
      const value = elements.streamType.value.trim();
      setTranscodeMode(value === 'transcode' || value === 'ffmpeg');
    });
  }
  if (elements.streamBackupType) {
    elements.streamBackupType.addEventListener('change', () => {
      updateStreamBackupFields();
    });
  }
  if (elements.streamTranscodePresetApply && elements.streamTranscodePreset) {
    elements.streamTranscodePresetApply.addEventListener('click', () => {
      applyStreamTranscodePreset(elements.streamTranscodePreset.value);
    });
    elements.streamTranscodePreset.addEventListener('change', () => {
      applyStreamTranscodePreset(elements.streamTranscodePreset.value);
    });
  }
  elements.streamForm.addEventListener('submit', saveStream);
  elements.loginForm.addEventListener('submit', submitLogin);

  elements.tabs.forEach((tab) => {
    tab.addEventListener('click', () => setTab(tab.dataset.tab, tab.dataset.tabScope));
  });
  initTabbars();

  elements.btnAddInput.addEventListener('click', () => {
    collectInputs();
    state.inputs.push('');
    renderInputList();
  });

  if (elements.btnAddMptsService) {
    elements.btnAddMptsService.addEventListener('click', () => {
      state.mptsServices = state.mptsServices || [];
      state.mptsServices.push({ input: '' });
      renderMptsServiceList();
    });
  }
  if (elements.btnMptsProbe) {
    elements.btnMptsProbe.addEventListener('click', () => {
      probeMptsServices();
    });
  }
  if (elements.btnMptsEnable && elements.streamMpts) {
    elements.btnMptsEnable.addEventListener('click', () => {
      elements.streamMpts.checked = true;
      updateMptsFields();
    });
  }
  if (elements.btnMptsManualToggle && elements.mptsManual) {
    const syncMptsManualToggle = () => {
      const collapsed = elements.mptsManual.classList.contains('is-collapsed');
      elements.btnMptsManualToggle.textContent = collapsed ? 'Show manual' : 'Hide manual';
      elements.btnMptsManualToggle.setAttribute('aria-expanded', collapsed ? 'false' : 'true');
    };
    syncMptsManualToggle();
    elements.btnMptsManualToggle.addEventListener('click', () => {
      elements.mptsManual.classList.toggle('is-collapsed');
      syncMptsManualToggle();
    });
  }
  if (elements.btnMptsEnableCallout) {
    elements.btnMptsEnableCallout.addEventListener('click', () => {
      if (elements.btnMptsEnable && !elements.btnMptsEnable.disabled) {
        elements.btnMptsEnable.click();
        return;
      }
      if (elements.streamMpts) {
        elements.streamMpts.checked = true;
        updateMptsFields();
      }
    });
  }
  if (elements.btnMptsConvertInputs) {
    elements.btnMptsConvertInputs.addEventListener('click', () => {
      convertInputsToMptsServices();
    });
  }
  if (elements.btnMptsAddStreams) {
    elements.btnMptsAddStreams.addEventListener('click', () => {
      openMptsStreamsModal();
    });
  }
  if (elements.mptsStreamsClose) {
    elements.mptsStreamsClose.addEventListener('click', closeMptsStreamsModal);
  }
  if (elements.mptsStreamsCancel) {
    elements.mptsStreamsCancel.addEventListener('click', closeMptsStreamsModal);
  }
  if (elements.mptsStreamsAdd) {
    elements.mptsStreamsAdd.addEventListener('click', addMptsServicesFromSelectedStreams);
  }
  if (elements.mptsStreamsSearch) {
    elements.mptsStreamsSearch.addEventListener('input', () => {
      const modal = state.mptsStreamsModal || { selected: new Set(), search: '' };
      modal.search = elements.mptsStreamsSearch.value || '';
      state.mptsStreamsModal = modal;
      renderMptsStreamsModal();
    });
  }
  if (elements.btnMptsBulkApply) {
    elements.btnMptsBulkApply.addEventListener('click', () => {
      applyMptsBulkActions();
    });
  }

  elements.inputList.addEventListener('click', (event) => {
    const action = event.target.closest('[data-action]');
    if (!action) return;
    const row = event.target.closest('.list-row');
    if (!row) return;
    const index = Number(row.dataset.index);
    if (action.dataset.action === 'input-options') {
      openInputModal(index);
      return;
    }
    if (action.dataset.action === 'input-remove') {
      state.inputs.splice(index, 1);
      renderInputList();
    }
  });

  if (elements.mptsServiceList) {
    elements.mptsServiceList.addEventListener('click', (event) => {
      const action = event.target.closest('[data-action]');
      if (!action) return;
      const row = event.target.closest('.list-row');
      if (!row) return;
      const index = Number(row.dataset.index);
      if (action.dataset.action === 'mpts-service-up') {
        if (index > 0) {
          const tmp = state.mptsServices[index - 1];
          state.mptsServices[index - 1] = state.mptsServices[index];
          state.mptsServices[index] = tmp;
          renderMptsServiceList();
        }
        return;
      }
      if (action.dataset.action === 'mpts-service-down') {
        if (index < state.mptsServices.length - 1) {
          const tmp = state.mptsServices[index + 1];
          state.mptsServices[index + 1] = state.mptsServices[index];
          state.mptsServices[index] = tmp;
          renderMptsServiceList();
        }
        return;
      }
      if (action.dataset.action === 'mpts-service-remove') {
        state.mptsServices.splice(index, 1);
        renderMptsServiceList();
      }
    });
  }

  [elements.mptsPassNit, elements.mptsPassSdt, elements.mptsPassEit, elements.mptsPassTdt].forEach((control) => {
    if (!control) return;
    control.addEventListener('change', updateMptsPassWarning);
  });
  [
    elements.mptsDelivery,
    elements.mptsFrequency,
    elements.mptsSymbolrate,
    elements.mptsBandwidth,
    elements.mptsOrbitalPosition,
    elements.mptsPolarization,
    elements.mptsRolloff,
    elements.mptsModulation,
  ].forEach((control) => {
    if (!control) return;
    control.addEventListener('change', updateMptsDeliveryWarning);
    control.addEventListener('input', updateMptsDeliveryWarning);
  });
  [elements.mptsLcnTag, elements.mptsLcnTags].forEach((control) => {
    if (!control) return;
    control.addEventListener('change', updateMptsLcnTagsWarning);
    control.addEventListener('input', updateMptsLcnTagsWarning);
  });
  [elements.mptsLcnVersion, elements.mptsNitVersion].forEach((control) => {
    if (!control) return;
    control.addEventListener('change', updateMptsLcnVersionWarning);
    control.addEventListener('input', updateMptsLcnVersionWarning);
  });
  if (elements.mptsAutoProbe) {
    elements.mptsAutoProbe.addEventListener('change', updateMptsFields);
  }

  bindMptsWarningHandlers();
  document.addEventListener('click', (event) => {
    if (!elements.streamMpts || elements.streamMpts.checked) return;
    const inEditor = elements.editorOverlay && elements.editorOverlay.classList.contains('active');
    if (!inEditor) return;
    const content = event.target.closest('[data-tab-content="mpts"][data-tab-scope="stream-editor"]');
    if (!content) return;
    const section = event.target.closest('.mpts-section');
    if (!section) return;
    focusMptsManual('Enable MPTS to unlock settings.');
  }, true);

  elements.btnAddOutput.addEventListener('click', () => {
    state.outputs.push(defaultHlsOutput(elements.streamId.value || 'stream'));
    renderOutputList();
    openOutputModal(state.outputs.length - 1);
  });

  elements.outputList.addEventListener('click', (event) => {
    const action = event.target.closest('[data-action]');
    if (!action) return;
    const row = event.target.closest('.list-row');
    if (!row) return;
    const index = Number(row.dataset.index);

    if (action.dataset.action === 'output-audio-fix') {
      toggleOutputAudioFix(index);
      return;
    }
    if (action.dataset.action === 'output-options') {
      openOutputModal(index);
    }
    if (action.dataset.action === 'output-remove') {
      state.outputs.splice(index, 1);
      renderOutputList();
    }
  });

  if (elements.btnAddTranscodeOutput) {
    elements.btnAddTranscodeOutput.addEventListener('click', () => {
      state.transcodeOutputs.push(ensureTranscodeOutputWatchdog({}));
      renderTranscodeOutputList();
      openTranscodeOutputModal(state.transcodeOutputs.length - 1);
    });
  }

  if (elements.transcodeOutputList) {
    elements.transcodeOutputList.addEventListener('click', (event) => {
      const action = event.target.closest('[data-action]');
      if (!action) return;
      const row = event.target.closest('.list-row');
      if (!row) return;
      const index = Number(row.dataset.index);

      if (action.dataset.action === 'transcode-output-options') {
        openTranscodeOutputModal(index);
      }
      if (action.dataset.action === 'transcode-output-monitor') {
        openTranscodeMonitorModal(index);
      }
      if (action.dataset.action === 'transcode-output-remove') {
        state.transcodeOutputs.splice(index, 1);
        renderTranscodeOutputList();
      }
    });
  }

  elements.btnDelete.addEventListener('click', async () => {
    if (!state.editing || state.editing.isNew) return;
    setStreamEditorBusy(true, 'Deleting...');
    try {
      await deleteStream(state.editing.stream);
      closeEditor();
    } catch (err) {
      setStatus(err.message);
    } finally {
      setStreamEditorBusy(false);
    }
  });

  elements.btnClone.addEventListener('click', () => {
    if (!state.editing) return;
    const clone = JSON.parse(JSON.stringify(state.editing.stream));
    const newId = `${clone.id || 'stream'}_copy`;
    clone.id = newId;
    if (clone.config) {
      clone.config.id = newId;
      clone.config.name = `${clone.config.name || newId} Copy`;
    }
    openEditor(clone, true);
  });

  elements.btnAnalyze.addEventListener('click', () => {
    if (!state.editing) return;
    openAnalyze(state.editing.stream);
  });

  elements.outputType.addEventListener('change', () => {
    const type = elements.outputType.value;
    setOutputGroup(type === 'rtp' ? 'udp' : type);
    updateOutputAudioFixVisibility();
  });
  if (elements.outputUdpAudioFixEnabled) {
    elements.outputUdpAudioFixEnabled.addEventListener('change', () => {
      updateOutputAudioFixVisibility();
    });
  }

  if (elements.outputPresetApply && elements.outputPreset) {
    elements.outputPresetApply.addEventListener('click', () => {
      applyOutputPreset(elements.outputPreset.value);
    });
    elements.outputPreset.addEventListener('change', () => {
      applyOutputPreset(elements.outputPreset.value);
    });
  }
  elements.outputHttpMode.addEventListener('change', () => {
    setOutputHttpMode(elements.outputHttpMode.value);
  });

  elements.outputForm.addEventListener('submit', (event) => {
    event.preventDefault();
    const output = readOutputForm();
    if (!output) return;
    if (state.outputEditingIndex !== null) {
      state.outputs[state.outputEditingIndex] = output;
    }
    renderOutputList();
    closeOutputModal();
  });

  elements.outputClose.addEventListener('click', closeOutputModal);
  elements.outputCancel.addEventListener('click', closeOutputModal);

  if (elements.transcodeOutputForm) {
    elements.transcodeOutputForm.addEventListener('submit', (event) => {
      event.preventDefault();
      const output = readTranscodeOutputForm();
      if (elements.transcodeOutputError) {
        elements.transcodeOutputError.textContent = '';
      }
      try {
        const idx = state.transcodeOutputEditingIndex !== null ? state.transcodeOutputEditingIndex : 0;
        validateTranscodeOutput(output, idx);
      } catch (err) {
        if (elements.transcodeOutputError) {
          elements.transcodeOutputError.textContent = err.message || 'Invalid output';
        }
        return;
      }
      if (state.transcodeOutputEditingIndex !== null) {
        state.transcodeOutputs[state.transcodeOutputEditingIndex] = ensureTranscodeOutputWatchdog(output);
      } else {
        state.transcodeOutputs.push(ensureTranscodeOutputWatchdog(output));
      }
      renderTranscodeOutputList();
      closeTranscodeOutputModal();
    });
  }

  if (elements.transcodeMonitorForm) {
    elements.transcodeMonitorForm.addEventListener('submit', (event) => {
      event.preventDefault();
      if (elements.transcodeMonitorError) {
        elements.transcodeMonitorError.textContent = '';
      }
      const idx = state.transcodeOutputMonitorIndex;
      if (idx === null || idx === undefined) {
        closeTranscodeMonitorModal();
        return;
      }
      const output = state.transcodeOutputs[idx];
      if (!output) {
        closeTranscodeMonitorModal();
        return;
      }
      if (!output.url) {
        if (elements.transcodeMonitorError) {
          elements.transcodeMonitorError.textContent = 'Output URL is required before configuring monitor.';
        }
        return;
      }
      output.watchdog = readTranscodeMonitorForm();
      state.transcodeOutputs[idx] = output;
      renderTranscodeOutputList();
      closeTranscodeMonitorModal();
    });
  }

  if (elements.transcodeOutputPreset) {
    elements.transcodeOutputPreset.addEventListener('change', (event) => {
      applyTranscodeOutputPreset(event.target.value);
    });
  }
  if (elements.transcodeOutputVcodec && elements.transcodeOutputRepeatHeaders) {
    elements.transcodeOutputVcodec.addEventListener('input', updateRepeatHeadersToggle);
  }
  if (elements.streamTranscodeInputProbeUdp && elements.streamTranscodeInputProbeRestart) {
    elements.streamTranscodeInputProbeUdp.addEventListener('change', updateInputProbeRestartToggle);
  }
  if (elements.streamTranscodeProcessPerOutput && elements.streamTranscodeSeamlessUdpProxy) {
    elements.streamTranscodeProcessPerOutput.addEventListener('change', updateSeamlessProxyToggle);
  }

  if (elements.transcodeOutputClose) {
    elements.transcodeOutputClose.addEventListener('click', closeTranscodeOutputModal);
  }

  if (elements.transcodeOutputCancel) {
    elements.transcodeOutputCancel.addEventListener('click', closeTranscodeOutputModal);
  }

  if (elements.transcodeMonitorClose) {
    elements.transcodeMonitorClose.addEventListener('click', closeTranscodeMonitorModal);
  }

  if (elements.transcodeMonitorCancel) {
    elements.transcodeMonitorCancel.addEventListener('click', closeTranscodeMonitorModal);
  }

  if (elements.inputType) {
    elements.inputType.addEventListener('change', () => {
      const type = elements.inputType.value;
      const group = (type === 'rtp') ? 'udp'
        : (type === 'hls' ? 'http'
          : (type === 'srt' || type === 'rtsp' ? 'bridge' : type));
      setInputGroup(group);
    });
  }
  if (elements.inputPresetApply && elements.inputPreset) {
    elements.inputPresetApply.addEventListener('click', () => {
      applyInputPreset(elements.inputPreset.value);
    });
    elements.inputPreset.addEventListener('change', () => {
      applyInputPreset(elements.inputPreset.value);
    });
  }

  if (elements.inputForm) {
    elements.inputForm.addEventListener('submit', (event) => {
      event.preventDefault();
      try {
        const url = readInputForm();
        if (state.inputEditingIndex !== null) {
          state.inputs[state.inputEditingIndex] = url;
        }
        renderInputList();
        closeInputModal();
      } catch (err) {
        setStatus(err.message);
      }
    });
  }

  if (elements.inputClose) {
    elements.inputClose.addEventListener('click', closeInputModal);
  }

  if (elements.inputCancel) {
    elements.inputCancel.addEventListener('click', closeInputModal);
  }

  if (elements.adapterType) {
    elements.adapterType.addEventListener('change', () => {
      setAdapterGroup(elements.adapterType.value);
    });
  }

  if (elements.adapterSelect) {
    elements.adapterSelect.addEventListener('change', (event) => {
      const id = event.target.value;
      if (!id) {
        openAdapterEditor({ id: '', enabled: true, config: {} }, true);
        return;
      }
      const adapter = state.adapters.find((item) => item.id === id);
      if (adapter) {
        openAdapterEditor(adapter, false);
      }
    });
  }

  if (elements.adapterDetected) {
    elements.adapterDetected.addEventListener('change', () => {
      const value = elements.adapterDetected.value;
      if (!value) {
        if (elements.adapterDetectedHint) {
          elements.adapterDetectedHint.textContent = 'Select a detected adapter to fill Adapter/Device/Type fields.';
          elements.adapterDetectedHint.className = 'form-hint';
        }
        if (elements.adapterDetectedBadge) {
          elements.adapterDetectedBadge.textContent = '';
          elements.adapterDetectedBadge.className = 'adapter-detected-badge';
        }
        return;
      }
      const [adapterStr, deviceStr] = value.split('.');
      const item = findDvbAdapter(adapterStr, deviceStr);
      if (!item) return;
      renderAdapterHardwareSelects(item.adapter, item.device || 0);
      if (item.type) {
        const current = elements.adapterType.value;
        if (!(current === 'S2' && item.type === 'S')) {
          elements.adapterType.value = item.type;
        }
        setAdapterGroup(elements.adapterType.value);
      }
      if (elements.adapterDetectedHint) {
        const status = formatDvbStatus(item);
        elements.adapterDetectedHint.textContent = status.hint;
        elements.adapterDetectedHint.className = `form-hint adapter-detected-hint ${status.className}`;
      }
      if (elements.adapterDetectedBadge) {
        const status = formatDvbStatus(item);
        elements.adapterDetectedBadge.textContent = status.label;
        elements.adapterDetectedBadge.className = `adapter-detected-badge ${status.className}`;
      }
      updateAdapterBusyWarningFromFields();
    });
  }

  if (elements.adapterDetectedRefresh) {
    elements.adapterDetectedRefresh.addEventListener('click', () => {
      loadDvbAdapters().catch(() => {});
    });
  }

  if (elements.adapterScan) {
    elements.adapterScan.addEventListener('click', async () => {
      const adapter = state.adapterEditing && state.adapterEditing.adapter;
      const adapterId = adapter && adapter.id;
      if (!adapterId) {
        setStatus('Save adapter to enable scan');
        return;
      }
      const status = getAdapterStatusEntry(adapterId, adapter && adapter.config);
      const locked = isAdapterLocked(adapterId, adapter && adapter.config);
      let warning = '';
      if (!status) {
        warning = 'Adapter status unavailable; scan may fail.';
      } else if (!locked) {
        warning = 'Signal not locked; scan may fail.';
      }
      if (elements.adapterScanSub) {
        elements.adapterScanSub.textContent = `Adapter: ${adapterId}`;
      }
      setOverlay(elements.adapterScanOverlay, true);
      try {
        await startAdapterScan(adapterId, warning ? { warning } : null);
      } catch (err) {
        if (elements.adapterScanStatus) {
          elements.adapterScanStatus.textContent = formatNetworkError(err) || err.message || 'Scan failed.';
        }
      }
    });
  }

  if (elements.adapterScanAdd) {
    elements.adapterScanAdd.addEventListener('click', () => {
      const adapter = state.adapterEditing && state.adapterEditing.adapter;
      const adapterId = adapter && adapter.id;
      createStreamsFromScan(adapterId).catch((err) => {
        setStatus(formatNetworkError(err) || err.message || 'Failed to create streams');
      });
    });
  }

  if (elements.adapterScanRefresh) {
    elements.adapterScanRefresh.addEventListener('click', () => {
      const adapter = state.adapterEditing && state.adapterEditing.adapter;
      const adapterId = adapter && adapter.id;
      if (!adapterId) return;
      startAdapterScan(adapterId).catch((err) => {
        if (elements.adapterScanStatus) {
          elements.adapterScanStatus.textContent = formatNetworkError(err) || err.message || 'Scan failed.';
        }
      });
    });
  }

  if (elements.adapterScanClose) {
    elements.adapterScanClose.addEventListener('click', closeAdapterScanModal);
  }

  if (elements.adapterScanCancel) {
    elements.adapterScanCancel.addEventListener('click', closeAdapterScanModal);
  }

  if (elements.adapterForm) {
    elements.adapterForm.addEventListener('submit', (event) => {
      event.preventDefault();
      elements.adapterError.textContent = '';
      saveAdapter().catch((err) => {
        elements.adapterError.textContent = formatNetworkError(err) || err.message;
      });
    });
  }

  if (elements.adapterIndex) {
    elements.adapterIndex.addEventListener('change', () => {
      renderAdapterDeviceSelect(elements.adapterIndex.value);
      updateAdapterBusyWarningFromFields();
    });
  }
  if (elements.adapterDevice) {
    elements.adapterDevice.addEventListener('change', updateAdapterBusyWarningFromFields);
  }

  if (elements.adapterCancel) {
    elements.adapterCancel.addEventListener('click', closeAdapterEditor);
  }

  if (elements.adapterClear) {
    elements.adapterClear.addEventListener('click', closeAdapterEditor);
  }

  if (elements.adapterNew) {
    elements.adapterNew.addEventListener('click', () => {
      openAdapterEditor({ id: '', enabled: true, config: {} }, true);
    });
  }

  if (elements.adapterDelete) {
    elements.adapterDelete.addEventListener('click', () => {
      deleteAdapter().catch((err) => setStatus(err.message));
    });
  }

  if (elements.streamId) {
    elements.streamId.addEventListener('input', handleStreamIdInput);
  }
  if (elements.streamName) {
    elements.streamName.addEventListener('input', handleStreamNameInput);
  }
  if (elements.streamMpts) {
    elements.streamMpts.addEventListener('change', updateMptsFields);
  }

  if (elements.logClear) {
    elements.logClear.addEventListener('click', () => {
      state.logEntries = [];
      renderLogs();
    });
  }

  if (elements.logPause) {
    elements.logPause.addEventListener('click', () => {
      setLogPaused(!state.logPaused);
    });
  }

  if (elements.logFilter) {
    const applyLogFilter = debounce(() => {
      state.logCursor = 0;
      if (state.logPaused) {
        renderLogs();
      } else {
        loadLogs(true);
      }
    }, 300);
    elements.logFilter.addEventListener('input', () => {
      state.logTextFilter = elements.logFilter.value;
      renderLogs();
      applyLogFilter();
    });
  }

  if (elements.logStream) {
    const applyStreamFilter = debounce(() => {
      state.logCursor = 0;
      if (state.logPaused) {
        renderLogs();
      } else {
        loadLogs(true);
      }
    }, 300);
    elements.logStream.addEventListener('input', () => {
      state.logStreamFilter = elements.logStream.value;
      renderLogs();
      applyStreamFilter();
    });
  }

  if (elements.logLevel) {
    elements.logLevel.addEventListener('change', () => {
      state.logLevelFilter = elements.logLevel.value;
      state.logCursor = 0;
      if (state.logPaused) {
        renderLogs();
      } else {
        loadLogs(true);
      }
    });
  }

  if (elements.logLimit) {
    elements.logLimit.value = String(state.logLimit || 500);
    elements.logLimit.addEventListener('change', () => {
      state.logLimit = toNumber(elements.logLimit.value) || 500;
      if (state.logEntries.length > state.logLimit) {
        state.logEntries = state.logEntries.slice(state.logEntries.length - state.logLimit);
      }
      state.logCursor = 0;
      if (state.logPaused) {
        renderLogs();
      } else {
        loadLogs(true);
      }
    });
  }

  if (elements.sessionFilter) {
    const applySessionFilter = debounce(() => {
      if (!state.sessionPaused) {
        loadSessions();
      }
    }, 300);
    elements.sessionFilter.addEventListener('input', () => {
      state.sessionFilterText = elements.sessionFilter.value;
      renderSessions();
      applySessionFilter();
    });
  }

  if (elements.sessionGroup) {
    elements.sessionGroup.addEventListener('change', () => {
      state.sessionGroupBy = elements.sessionGroup.checked;
      renderSessions();
    });
  }

  if (elements.sessionLimit) {
    elements.sessionLimit.value = String(state.sessionLimit || 200);
    elements.sessionLimit.addEventListener('change', () => {
      state.sessionLimit = toNumber(elements.sessionLimit.value) || 200;
      if (state.sessionPaused) {
        renderSessions();
      } else {
        loadSessions();
      }
    });
  }

  if (elements.accessEvent) {
    const applyAccessFilter = debounce(() => {
      state.accessLogCursor = 0;
      if (state.accessPaused) {
        renderAccessLog();
      } else {
        loadAccessLog(true);
      }
    }, 300);
    elements.accessEvent.addEventListener('change', () => {
      state.accessEventFilter = elements.accessEvent.value;
      applyAccessFilter();
    });
  }

  if (elements.accessFilter) {
    const applyAccessText = debounce(() => {
      state.accessLogCursor = 0;
      if (state.accessPaused) {
        renderAccessLog();
      } else {
        loadAccessLog(true);
      }
    }, 300);
    elements.accessFilter.addEventListener('input', () => {
      state.accessTextFilter = elements.accessFilter.value;
      applyAccessText();
    });
  }

  if (elements.accessLimit) {
    elements.accessLimit.value = String(state.accessLimit || 200);
    elements.accessLimit.addEventListener('change', () => {
      state.accessLimit = toNumber(elements.accessLimit.value) || 200;
      state.accessLogCursor = 0;
      if (state.accessLogEntries.length > state.accessLimit) {
        state.accessLogEntries = state.accessLogEntries.slice(state.accessLogEntries.length - state.accessLimit);
      }
      if (state.accessPaused) {
        renderAccessLog();
      } else {
        loadAccessLog(true);
      }
    });
  }

  if (elements.accessMode) {
    elements.accessMode.value = state.accessMode || 'access';
    elements.accessMode.addEventListener('change', () => {
      setAccessMode(elements.accessMode.value);
    });
  }

  if (elements.auditActionFilter) {
    elements.auditActionFilter.value = state.auditActionFilter || '';
    elements.auditActionFilter.addEventListener('input', debounce(() => {
      state.auditActionFilter = elements.auditActionFilter.value;
      loadAuditLog(true);
    }, 300));
  }
  if (elements.auditAiOnly) {
    elements.auditAiOnly.checked = state.auditActionFilter === 'ai_change';
    if (elements.auditActionFilter) {
      elements.auditActionFilter.disabled = elements.auditAiOnly.checked;
    }
  }
  if (elements.auditAiOnly) {
    elements.auditAiOnly.addEventListener('change', () => {
      if (elements.auditAiOnly.checked) {
        state.auditActionFilter = 'ai_change';
        if (elements.auditActionFilter) {
          elements.auditActionFilter.value = 'ai_change';
          elements.auditActionFilter.disabled = true;
        }
      } else {
        if (elements.auditActionFilter) {
          elements.auditActionFilter.disabled = false;
          elements.auditActionFilter.value = '';
        }
        state.auditActionFilter = '';
      }
      loadAuditLog(true);
    });
  }
  if (elements.auditActorFilter) {
    elements.auditActorFilter.addEventListener('input', debounce(() => {
      state.auditActorFilter = elements.auditActorFilter.value;
      loadAuditLog(true);
    }, 300));
  }
  if (elements.auditOkFilter) {
    elements.auditOkFilter.addEventListener('change', () => {
      state.auditOkFilter = elements.auditOkFilter.value;
      loadAuditLog(true);
    });
  }
  if (elements.auditLimit) {
    elements.auditLimit.value = String(state.auditLimit || 200);
    elements.auditLimit.addEventListener('change', () => {
      state.auditLimit = toNumber(elements.auditLimit.value) || 200;
      loadAuditLog(true);
    });
  }
  if (elements.auditRefresh) {
    elements.auditRefresh.addEventListener('click', () => {
      loadAuditLog(true);
    });
  }

  if (elements.sessionPause) {
    elements.sessionPause.addEventListener('click', () => {
      setSessionPaused(!state.sessionPaused);
    });
  }

  if (elements.sessionRefresh) {
    elements.sessionRefresh.addEventListener('click', () => {
      loadSessions();
    });
  }

  if (elements.accessPause) {
    elements.accessPause.addEventListener('click', () => {
      setAccessPaused(!state.accessPaused);
    });
  }

  if (elements.accessClear) {
    elements.accessClear.addEventListener('click', () => {
      state.accessLogEntries = [];
      renderAccessLog();
    });
  }

  elements.sessionTable.addEventListener('click', (event) => {
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const action = button.dataset.action;
    if (action === 'disconnect') {
      const id = button.dataset.id;
      apiJson(`/api/v1/sessions/${id}`, { method: 'DELETE' })
        .then(loadSessions)
        .catch((err) => setStatus(err.message));
      return;
    }
    if (action === 'allow-ip' || action === 'block-ip') {
      const ip = button.dataset.ip;
      if (!ip) return;
      const allowList = parseCommaList(getSettingString('http_auth_allow', ''));
      const denyList = parseCommaList(getSettingString('http_auth_deny', ''));
      let nextAllow = allowList.slice();
      let nextDeny = denyList.slice();
      if (action === 'allow-ip') {
        if (!nextAllow.includes(ip)) nextAllow.push(ip);
        nextDeny = nextDeny.filter((item) => item !== ip);
      } else {
        if (!nextDeny.includes(ip)) nextDeny.push(ip);
        nextAllow = nextAllow.filter((item) => item !== ip);
      }
      saveSettings({
        http_auth_allow: formatCommaList(nextAllow),
        http_auth_deny: formatCommaList(nextDeny),
      }).then(() => {
        setStatus(action === 'allow-ip' ? `IP ${ip} added to whitelist` : `IP ${ip} added to block list`);
      }).catch((err) => setStatus(err.message));
    }
  });

  document.addEventListener('keydown', (event) => {
    const tag = event.target.tagName.toLowerCase();
    if (tag === 'input' || tag === 'textarea') return;
    if (event.key.toLowerCase() === 'v' && event.shiftKey) {
      cycleViewMode();
      event.preventDefault();
      return;
    }
    if (event.key.toLowerCase() === 's') {
      elements.searchInput.focus();
      event.preventDefault();
    }
  });

  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      pauseAllPolling();
    } else {
      resumeAllPolling();
    }
  });

  window.addEventListener('beforeunload', (event) => {
    if (state.generalDirty || state.configEditorDirty) {
      event.preventDefault();
      event.returnValue = '';
    }
  });

  bindToggleTargets();
}

renderGeneralSettings();
bindEvents();
setViewMode(state.viewMode, { persist: false, render: false });
setThemeMode(state.themeMode, { persist: false });
setSettingsSection(state.settingsSection);
applyTilesUiState();
refreshAll();
