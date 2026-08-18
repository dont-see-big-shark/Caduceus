// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Caduceus';

  @override
  String get settings => '设置';

  @override
  String get settingsItemModel => 'Model';

  @override
  String get settingsItemChat => 'Chat';

  @override
  String get settingsItemWorkspace => 'Workspace';

  @override
  String get settingsItemSafety => 'Safety';

  @override
  String get settingsItemMemory => 'Memory & Context';

  @override
  String get settingsItemAdvanced => 'Advanced';

  @override
  String get settingsItemNotifications => 'Notifications';

  @override
  String get settingsItemBilling => 'Billing';

  @override
  String get settingsItemProviders => 'Providers';

  @override
  String get settingsItemShortcuts => 'Keyboard Shortcuts';

  @override
  String get settingsItemToolsKeys => 'Tools & Keys';

  @override
  String get settingsItemPlugins => 'Plugins';

  @override
  String get settingsItemArchived => 'Archived Chats';

  @override
  String get settingsItemAbout => 'About';

  @override
  String get settingsGroupCore => '核心';

  @override
  String get settingsGroupDevice => '设备';

  @override
  String get settingsGroupAccount => '账户与连接';

  @override
  String get settingsGroupSystem => '系统';

  @override
  String get designSurfaceExample => '示例 · 设计面';

  @override
  String get designSurfaceNoData =>
      '该页面暂无真实数据源 — 这是设计中的页面，网关尚无对应接口。以示例标注呈现，不提供虚构控件。';

  @override
  String get composerFootCmd => '⌘K 命令面板';

  @override
  String get composerFootHints => '↵ 发送 · ⇧↵ 换行 · Esc 关闭';

  @override
  String get settingsSubtitle => 'Caduceus 与 Hermes 服务端';

  @override
  String get appearance => '外观';

  @override
  String get theme => '主题';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get themeLight => '浅色';

  @override
  String get themeDark => '深色';

  @override
  String get language => '语言';

  @override
  String get languageSystem => '跟随系统';

  @override
  String get languageEn => 'English';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageZhTW => '繁體中文';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEs => 'Español';

  @override
  String get material => '视觉效果';

  @override
  String get reduceVisualEffects => '减少视觉效果';

  @override
  String get whatItChanges => '变更内容';

  @override
  String get whatItChangesDesc => '实色面板代替玻璃效果，关闭极光背景。所有尺寸、圆角、时长与曲线保持原样。';

  @override
  String get solid => '实色';

  @override
  String get glass => '玻璃';

  @override
  String get session => '会话';

  @override
  String get modelAndSession => '模型与会话';

  @override
  String get approvals => '审批';

  @override
  String get skills => '技能';

  @override
  String get voice => '语音';

  @override
  String get gateway => '网关';

  @override
  String get device => '设备';

  @override
  String get about => '关于';

  @override
  String get connection => '连接';

  @override
  String get connected => '已连接';

  @override
  String get disconnected => '未连接';

  @override
  String get pickGroupOnLeft => '请在左侧选择项目';

  @override
  String get model => '模型';

  @override
  String get thisSession => '当前会话';

  @override
  String get changingIt => '修改模型';

  @override
  String get changingItDesc => '模型选择器位于输入框旁。此处不再重复提供。';

  @override
  String get workingDirectory => '工作目录…';

  @override
  String get noSessionOpen => '未打开会话';

  @override
  String get dictation => '听写';

  @override
  String get running => '正在运行';

  @override
  String get idle => '空闲';

  @override
  String get whereItRuns => '运行位置';

  @override
  String get onThisDevice => '在此设备上';

  @override
  String get address => '地址';

  @override
  String get status => '状态';

  @override
  String get version => '版本';

  @override
  String get back => '返回';

  @override
  String get connectNewBackend => '连接新后端';

  @override
  String get connectNewBackendSubtitle => '发现 · 配对 · 诊断';

  @override
  String get connectToHermesDesc =>
      '连接到 Hermes 控制平面。通过 SSH 或 Tailscale 端口转发以绑定至本地环回端口 — 随后仅需会话 Token。';

  @override
  String get addAnotherServer => '添加其他服务器';

  @override
  String get sessionEndedWithError => '会话因错误终止';

  @override
  String get nameOptional => '名称 (可选)';

  @override
  String get serverUrl => '服务器 URL';

  @override
  String get gatewayToken => '网关 Token';

  @override
  String get sessionToken => '会话 Token';

  @override
  String get openClawDeviceNote =>
      'OpenClaw 仅在管理员批准新设备后允许连接。本应用每个服务器保存一个密钥，仅需批准一次。';

  @override
  String get connect => '连接';

  @override
  String get forgetThisServer => '遗忘此服务器';

  @override
  String get waitingToBeApproved => '等待批准';

  @override
  String get openClawApprovalNote => '网关已接受 Token 与握手。需管理员批准设备后重新连接。';

  @override
  String get copyDeviceId => '复制设备 ID';

  @override
  String get newSession => '新建会话';

  @override
  String get searchSessions => '搜索会话';

  @override
  String get refresh => '刷新';

  @override
  String get scheduledJobs => '计划任务';

  @override
  String get projects => '项目';

  @override
  String get backgroundProcesses => '后台进程…';

  @override
  String get agents => '智能体…';

  @override
  String get checkpoints => '检查点';

  @override
  String get learningJourney => '学习历程';

  @override
  String get server => '服务器';

  @override
  String get noSessions => '暂无会话';

  @override
  String get noSessionsDesc => '新建会话以开始使用';

  @override
  String get reload => '重新加载';

  @override
  String get cancel => '取消';

  @override
  String get close => '关闭';

  @override
  String get save => '保存';

  @override
  String get stop => '停止';

  @override
  String get stopAll => '全部停止';

  @override
  String get delete => '删除';

  @override
  String get archive => '归档';

  @override
  String get stopThisTitle => '停止此进程？';

  @override
  String get stopAllProcessesTitle => '停止所有进程？';

  @override
  String get stopAllProcessesMessage => '服务器上的所有后台进程将被杀死，包括其他会话启动且未在此列出的进程。';

  @override
  String get nothingRunning => '无运行中进程';

  @override
  String get hideOutput => '隐藏输出';

  @override
  String get showOutput => '显示输出';

  @override
  String get delegation => '任务委派';

  @override
  String get noSubagentsRunning => '无运行中的子智能体';

  @override
  String get subagentsRunning => '个子智能体运行中';

  @override
  String get allowNewSubagents => '允许新子智能体';

  @override
  String get spawningPaused => '衍生已暂停 — 已运行的子智能体将继续执行';

  @override
  String get agentMaySpawnChildren => '智能体可衍生子智能体';

  @override
  String get savedSpawnTrees => '已保存的衍生树';

  @override
  String get noneForThisSession => '当前会话暂无';

  @override
  String get recentActivity => '近期活动';

  @override
  String get interruptThisSubagent => '中断此子智能体';

  @override
  String get restoreCheckpointTitle => '还原检查点？';

  @override
  String restoreCheckpointMessage(Object hash, Object timestamp) {
    return '服务器上的文件将被重写为 $timestamp ($hash) 的状态。在此之后的修改将丢失。';
  }

  @override
  String get noCheckpoints => '暂无检查点 — 智能体在此会话中未修改文件，或检查点功能未开启。';

  @override
  String get selectCheckpointToSeeDiff => '选择检查点以查看差异';

  @override
  String get restoreThisCheckpoint => '还原此检查点';

  @override
  String restored(Object hash) {
    return '已还原 $hash';
  }

  @override
  String get newScheduledJob => '新建计划任务';

  @override
  String get jobName => '名称';

  @override
  String get schedule => '定时计划';

  @override
  String get scheduleHelper => 'cron 表达式，例如 0 9 * * * 表示每天 09:00';

  @override
  String get promptToRun => '运行提示词';

  @override
  String get create => '创建';

  @override
  String get noScheduledJobs => '暂无计划任务';

  @override
  String get newJob => '新任务';

  @override
  String get thisEntryNoLongerAvailable => '此条目已不可用。';

  @override
  String get thisEntryHasNoContentYet => '此条目尚无内容。';

  @override
  String get archiveSkillTitle => '归档技能？';

  @override
  String get deleteMemoryTitle => '删除记忆？';

  @override
  String archiveSkillContent(Object label) {
    return '“$label” 将在服务器上归档，后续可恢复。';
  }

  @override
  String deleteMemoryContent(Object label) {
    return '“$label” 将从智能体的记忆中移除，此操作不可撤销。';
  }

  @override
  String get install => '安装';

  @override
  String get noProjects => '暂无项目 — 此服务器上的会话未进行分组';

  @override
  String get noSessionsInProject => '暂无会话';

  @override
  String get tools => '工具';

  @override
  String get commands => '命令';

  @override
  String get config => '配置';

  @override
  String get plugins => '插件';

  @override
  String get thisServerReportsNothing => '该服务器暂未报告此会话的任何用量数据。';

  @override
  String get readOnlyConfigNote => '只读：在此开启或关闭将更改整台服务器的配置，而非仅当前会话。';

  @override
  String get maintenanceNote => '维护 — 将影响此服务器上的所有会话';

  @override
  String reloadTargetTitle(Object target) {
    return '重新加载 $target？';
  }

  @override
  String get reloadTargetMessage => '此操作将更改服务器上的所有会话，而非仅当前会话。';

  @override
  String get continueAction => '继续';

  @override
  String get typeAMessage => '输入消息...';

  @override
  String get send => '发送';

  @override
  String get stopTurn => '停止';

  @override
  String get thinking => '思考中...';

  @override
  String thinkingTime(Object seconds) {
    return '思考用时 $seconds 秒';
  }

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制';

  @override
  String get retry => '重试';

  @override
  String get edit => '编辑';

  @override
  String get sessionActions => '会话操作';

  @override
  String get undoLastExchange => '撤销上次对话';

  @override
  String get fileCheckpoints => '文件检查点…';

  @override
  String get journeyWhatItLearned => '学习历程 — 已学内容…';

  @override
  String get toolsetsSkillsPlugins => '工具箱、技能、插件…';

  @override
  String get findInConversation => '在会话中查找…';

  @override
  String get copyTranscript => '复制对话记录';

  @override
  String get branchSession => '分支会话…';

  @override
  String get usageAndContext => '用量与上下文…';

  @override
  String get typeACommand => '输入命令…';

  @override
  String nothingMatches(Object query) {
    return '无匹配项 “$query”';
  }

  @override
  String get actOnRunningTurn => '干预运行中的轮次';

  @override
  String get steerThisTurn => '引导此轮';

  @override
  String get redirectThisTurn => '重定向此轮';

  @override
  String get workingDirectoryTitle => '工作目录';

  @override
  String get workingDirectoryDesc => '智能体所在服务器上的路径（非本机路径）。附件与 @-引用将基于此路径解析。';

  @override
  String get set => '设置';

  @override
  String get nothingToUndo => '没有可撤销的内容';

  @override
  String removedMessages(Object count) {
    return '已移除 $count 条消息';
  }

  @override
  String copiedCharacters(Object count) {
    return '已复制 $count 个字符';
  }

  @override
  String get branchFailed => '创建分支失败';

  @override
  String branchedTo(Object id) {
    return '已分支至 $id';
  }

  @override
  String get sessionUsage => '会话用量';

  @override
  String get sessions => '会话';

  @override
  String get chat => '会话';

  @override
  String get panels => '面板';

  @override
  String get messaging => 'Messaging';

  @override
  String get artifacts => 'Artifacts';

  @override
  String get kanban => 'Kanban';

  @override
  String get photo => '照片';

  @override
  String get library => '图库';

  @override
  String get file => '文件';

  @override
  String get video => '视频';

  @override
  String get pasteFromClipboard => '从剪贴板粘贴';

  @override
  String get referencePathOnServer => '引用服务器路径';

  @override
  String get queueForAfterThisTurn => '排队等待本轮结束';

  @override
  String get attachSomething => '添加附件';

  @override
  String get rename => '重命名…';

  @override
  String get compressHistory => '压缩历史记录';

  @override
  String get deleteSessionTitle => '删除…';

  @override
  String get renameSession => '重命名会话';

  @override
  String get compressHistoryQuestion => '压缩历史记录？';

  @override
  String compressHistoryDesc(Object label) {
    return '“$label” 中的较早消息将被总结归纳以回收上下文。此操作无法撤销。';
  }

  @override
  String get deleteSessionQuestion => '删除会话？';

  @override
  String deleteSessionDesc(Object count, Object label) {
    return '“$label” 及其 $count 条消息将被永久删除。';
  }

  @override
  String get holdToDelete => '按住以删除';

  @override
  String get deleted => '已删除';

  @override
  String get showSessions => '显示会话列表';

  @override
  String get hideSessions => '隐藏会话列表';

  @override
  String get appearanceSystem => '外观：跟随系统';

  @override
  String get appearanceLight => '外观：浅色';

  @override
  String get appearanceDark => '外观：深色';

  @override
  String get modelForThisSession => '此会话的模型';

  @override
  String get requeryProviders => '重新查询提供商';

  @override
  String get noModelList => '此服务器未提供模型列表。';

  @override
  String get noCredential => '无凭据';

  @override
  String get composerSuggestionResume => '继续上次的任务';

  @override
  String get composerSuggestionStatus => '检查当前会话状态';

  @override
  String get composerSuggestionRelease => '写一条发布说明';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get appTitle => 'Caduceus';

  @override
  String get settings => '設定';

  @override
  String get settingsItemModel => 'Model';

  @override
  String get settingsItemChat => 'Chat';

  @override
  String get settingsItemWorkspace => 'Workspace';

  @override
  String get settingsItemSafety => 'Safety';

  @override
  String get settingsItemMemory => 'Memory & Context';

  @override
  String get settingsItemAdvanced => 'Advanced';

  @override
  String get settingsItemNotifications => 'Notifications';

  @override
  String get settingsItemBilling => 'Billing';

  @override
  String get settingsItemProviders => 'Providers';

  @override
  String get settingsItemShortcuts => 'Keyboard Shortcuts';

  @override
  String get settingsItemToolsKeys => 'Tools & Keys';

  @override
  String get settingsItemPlugins => 'Plugins';

  @override
  String get settingsItemArchived => 'Archived Chats';

  @override
  String get settingsItemAbout => 'About';

  @override
  String get settingsGroupCore => '核心';

  @override
  String get settingsGroupDevice => '裝置';

  @override
  String get settingsGroupAccount => '帳戶與連線';

  @override
  String get settingsGroupSystem => '系統';

  @override
  String get designSurfaceExample => '示例 · 設計面';

  @override
  String get designSurfaceNoData =>
      '此頁面暫無真實資料來源 — 這是設計中的頁面，閘道尚無對應介面。以範例標註呈現，不提供虛構控制項。';

  @override
  String get composerFootCmd => '⌘K 指令面板';

  @override
  String get composerFootHints => '↵ 傳送 · ⇧↵ 換行 · Esc 關閉';

  @override
  String get settingsSubtitle => 'Caduceus 與 Hermes 伺服端';

  @override
  String get appearance => '外觀';

  @override
  String get theme => '主題';

  @override
  String get themeSystem => '跟隨系統';

  @override
  String get themeLight => '淺色';

  @override
  String get themeDark => '深色';

  @override
  String get language => '語言';

  @override
  String get languageSystem => '跟隨系統';

  @override
  String get languageEn => 'English';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageZhTW => '繁體中文';

  @override
  String get languageJa => '日本語';

  @override
  String get languageEs => 'Español';

  @override
  String get material => '視覺效果';

  @override
  String get reduceVisualEffects => '減少視覺效果';

  @override
  String get whatItChanges => '變更內容';

  @override
  String get whatItChangesDesc => '實色面板代替玻璃效果，關閉極光背景。所有尺寸、圓角、時長與曲線保持原樣。';

  @override
  String get solid => '實色';

  @override
  String get glass => '玻璃';

  @override
  String get session => '會話';

  @override
  String get modelAndSession => '模型與會話';

  @override
  String get approvals => '審批';

  @override
  String get skills => '技能';

  @override
  String get voice => '語音';

  @override
  String get gateway => '網關';

  @override
  String get device => '設備';

  @override
  String get about => '關於';

  @override
  String get connection => '連接';

  @override
  String get connected => '已連接';

  @override
  String get disconnected => '未連接';

  @override
  String get pickGroupOnLeft => '請在左側選擇項目';

  @override
  String get model => '模型';

  @override
  String get thisSession => '當前會話';

  @override
  String get changingIt => '修改模型';

  @override
  String get changingItDesc => '模型選擇器位於輸入框旁。此處不再重複提供。';

  @override
  String get workingDirectory => '工作目錄…';

  @override
  String get noSessionOpen => '未打開會話';

  @override
  String get dictation => '聽寫';

  @override
  String get running => '正在運行';

  @override
  String get idle => '空閒';

  @override
  String get whereItRuns => '運行位置';

  @override
  String get onThisDevice => '在此設備上';

  @override
  String get address => '地址';

  @override
  String get status => '狀態';

  @override
  String get version => '版本';

  @override
  String get back => '返回';

  @override
  String get connectNewBackend => '連接新後端';

  @override
  String get connectNewBackendSubtitle => '發現 · 配對 · 診斷';

  @override
  String get connectToHermesDesc =>
      '連接到 Hermes 控制平面。通過 SSH 或 Tailscale 端口轉發以綁定至本地環回端口 — 隨後僅需會話 Token。';

  @override
  String get addAnotherServer => '新增其他伺服器';

  @override
  String get sessionEndedWithError => '會話因錯誤終止';

  @override
  String get nameOptional => '名稱 (可選)';

  @override
  String get serverUrl => '伺服器 URL';

  @override
  String get gatewayToken => '網關 Token';

  @override
  String get sessionToken => '會話 Token';

  @override
  String get openClawDeviceNote =>
      'OpenClaw 僅在管理員批准新裝置後允許連接。本應用每個伺服器儲存一個密鑰，僅需批准一次。';

  @override
  String get connect => '連接';

  @override
  String get forgetThisServer => '移除此伺服器';

  @override
  String get waitingToBeApproved => '等待批准';

  @override
  String get openClawApprovalNote => '網關已接受 Token 與握手。需管理員批准裝置後重新連接。';

  @override
  String get copyDeviceId => '複製裝置 ID';

  @override
  String get newSession => '新建會話';

  @override
  String get searchSessions => '搜尋會話';

  @override
  String get refresh => '重新整理';

  @override
  String get scheduledJobs => '排程任務';

  @override
  String get projects => '專案';

  @override
  String get backgroundProcesses => '背景程序…';

  @override
  String get agents => '智能體…';

  @override
  String get checkpoints => '檢查點';

  @override
  String get learningJourney => '學習歷程';

  @override
  String get server => '伺服器';

  @override
  String get noSessions => '暫無會話';

  @override
  String get noSessionsDesc => '新建會話以開始使用';

  @override
  String get reload => '重新載入';

  @override
  String get cancel => '取消';

  @override
  String get close => '關閉';

  @override
  String get save => '儲存';

  @override
  String get stop => '停止';

  @override
  String get stopAll => '全部停止';

  @override
  String get delete => '刪除';

  @override
  String get archive => '封存';

  @override
  String get stopThisTitle => '停止此程序？';

  @override
  String get stopAllProcessesTitle => '停止所有程序？';

  @override
  String get stopAllProcessesMessage => '伺服器上的所有背景程序將被刪除，包括其他會話啟動且未在此列出的程序。';

  @override
  String get nothingRunning => '無執行中程序';

  @override
  String get hideOutput => '隱藏輸出';

  @override
  String get showOutput => '顯示輸出';

  @override
  String get delegation => '任務委派';

  @override
  String get noSubagentsRunning => '無執行中的子智慧體';

  @override
  String get subagentsRunning => '個子智慧體執行中';

  @override
  String get allowNewSubagents => '允許新子智慧體';

  @override
  String get spawningPaused => '衍生已暫停 — 已執行的子智慧體將繼續執行';

  @override
  String get agentMaySpawnChildren => '智慧體可衍生子智慧體';

  @override
  String get savedSpawnTrees => '已儲存的衍生樹';

  @override
  String get noneForThisSession => '當前會話暫無';

  @override
  String get recentActivity => '近期活動';

  @override
  String get interruptThisSubagent => '中斷此子智慧體';

  @override
  String get restoreCheckpointTitle => '還原檢查點？';

  @override
  String restoreCheckpointMessage(Object hash, Object timestamp) {
    return '伺服器上的檔案將被重寫為 $timestamp ($hash) 的狀態。在此之後的修改將遺失。';
  }

  @override
  String get noCheckpoints => '暫無檢查點 — 智慧體在此會話中未修改檔案，或檢查點功能未開啟。';

  @override
  String get selectCheckpointToSeeDiff => '選擇檢查點以檢視差異';

  @override
  String get restoreThisCheckpoint => '還原此檢查點';

  @override
  String restored(Object hash) {
    return '已還原 $hash';
  }

  @override
  String get newScheduledJob => '新建排程任務';

  @override
  String get jobName => '名稱';

  @override
  String get schedule => '定時計劃';

  @override
  String get scheduleHelper => 'cron 表達式，例如 0 9 * * * 表示每天 09:00';

  @override
  String get promptToRun => '執行提示詞';

  @override
  String get create => '建立';

  @override
  String get noScheduledJobs => '暫無排程任務';

  @override
  String get newJob => '新任務';

  @override
  String get thisEntryNoLongerAvailable => '此條目已不可用。';

  @override
  String get thisEntryHasNoContentYet => '此條目尚無內容。';

  @override
  String get archiveSkillTitle => '封存技能？';

  @override
  String get deleteMemoryTitle => '刪除記憶？';

  @override
  String archiveSkillContent(Object label) {
    return '「$label」將在伺服器上封存，後續可還原。';
  }

  @override
  String deleteMemoryContent(Object label) {
    return '「$label」將從智慧體的記憶中移除，此操作不可復原。';
  }

  @override
  String get install => '安裝';

  @override
  String get noProjects => '暫無專案 — 此伺服器上的會話未進行分組';

  @override
  String get noSessionsInProject => '暫無會話';

  @override
  String get tools => '工具';

  @override
  String get commands => '指令';

  @override
  String get config => '設定';

  @override
  String get plugins => '外掛';

  @override
  String get thisServerReportsNothing => '該伺服器暫未報告此會話的任何用量數據。';

  @override
  String get readOnlyConfigNote => '唯讀：在此開啟或關閉將變更整台伺服器的設定，而非僅當前會話。';

  @override
  String get maintenanceNote => '維護 — 將影響此伺服器上的所有會話';

  @override
  String reloadTargetTitle(Object target) {
    return '重新載入 $target？';
  }

  @override
  String get reloadTargetMessage => '此操作將變更伺服器上的所有會話，而非僅當前會話。';

  @override
  String get continueAction => '繼續';

  @override
  String get typeAMessage => '輸入訊息...';

  @override
  String get send => '傳送';

  @override
  String get stopTurn => '停止';

  @override
  String get thinking => '思考中...';

  @override
  String thinkingTime(Object seconds) {
    return '思考用時 $seconds 秒';
  }

  @override
  String get copy => '複製';

  @override
  String get copied => '已複製';

  @override
  String get retry => '重試';

  @override
  String get edit => '編輯';

  @override
  String get sessionActions => '會話操作';

  @override
  String get undoLastExchange => '撤銷上次對話';

  @override
  String get fileCheckpoints => '檔案檢查點…';

  @override
  String get journeyWhatItLearned => '學習歷程 — 已學內容…';

  @override
  String get toolsetsSkillsPlugins => '工具箱、技能、外掛…';

  @override
  String get findInConversation => '在會話中搜尋…';

  @override
  String get copyTranscript => '複製對話記錄';

  @override
  String get branchSession => '分支會話…';

  @override
  String get usageAndContext => '用量與上下文…';

  @override
  String get typeACommand => '輸入命令…';

  @override
  String nothingMatches(Object query) {
    return '無符合項目 “$query”';
  }

  @override
  String get actOnRunningTurn => '干預運行中的輪次';

  @override
  String get steerThisTurn => '引導此輪';

  @override
  String get redirectThisTurn => '重定向此輪';

  @override
  String get workingDirectoryTitle => '工作目錄';

  @override
  String get workingDirectoryDesc => '智能體所在伺服器上的路徑（非本機路徑）。附件與 @-引用將基於此路徑解析。';

  @override
  String get set => '設定';

  @override
  String get nothingToUndo => '沒有可撤銷的內容';

  @override
  String removedMessages(Object count) {
    return '已移除 $count 則訊息';
  }

  @override
  String copiedCharacters(Object count) {
    return '已複製 $count 個字元';
  }

  @override
  String get branchFailed => '建立分支失敗';

  @override
  String branchedTo(Object id) {
    return '已分支至 $id';
  }

  @override
  String get sessionUsage => '會話用量';

  @override
  String get sessions => '會話';

  @override
  String get chat => '對話';

  @override
  String get panels => '面板';

  @override
  String get messaging => 'Messaging';

  @override
  String get artifacts => 'Artifacts';

  @override
  String get kanban => 'Kanban';

  @override
  String get photo => '相片';

  @override
  String get library => '圖庫';

  @override
  String get file => '檔案';

  @override
  String get video => '影片';

  @override
  String get pasteFromClipboard => '從剪貼簿貼上';

  @override
  String get referencePathOnServer => '引用伺服器路徑';

  @override
  String get queueForAfterThisTurn => '排隊等待本輪結束';

  @override
  String get attachSomething => '新增附件';

  @override
  String get rename => '重新命名…';

  @override
  String get compressHistory => '壓縮歷史記錄';

  @override
  String get deleteSessionTitle => '刪除…';

  @override
  String get renameSession => '重新命名會話';

  @override
  String get compressHistoryQuestion => '壓縮歷史記錄？';

  @override
  String compressHistoryDesc(Object label) {
    return '“$label” 中的較早訊息將被總結歸納以回收上下文。此操作無法撤銷。';
  }

  @override
  String get deleteSessionQuestion => '刪除會話？';

  @override
  String deleteSessionDesc(Object count, Object label) {
    return '“$label” 及其 $count 則訊息將被永久刪除。';
  }

  @override
  String get holdToDelete => '按住以刪除';

  @override
  String get deleted => '已刪除';

  @override
  String get showSessions => '顯示會話列表';

  @override
  String get hideSessions => '隱藏會話列表';

  @override
  String get appearanceSystem => '外觀：隨系統';

  @override
  String get appearanceLight => '外觀：淺色';

  @override
  String get appearanceDark => '外觀：深色';

  @override
  String get modelForThisSession => '此會話的模型';

  @override
  String get requeryProviders => '重新查詢提供者';

  @override
  String get noModelList => '此伺服器未提供模型列表。';

  @override
  String get noCredential => '無憑證';

  @override
  String get composerSuggestionResume => '繼續上次的任務';

  @override
  String get composerSuggestionStatus => '檢查目前工作階段狀態';

  @override
  String get composerSuggestionRelease => '寫一則發行說明';
}
