// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'Caduceus';

  @override
  String get settings => '設定';

  @override
  String get settingsItemModel => 'モデル';

  @override
  String get settingsItemChat => 'チャット';

  @override
  String get settingsItemWorkspace => 'ワークスペース';

  @override
  String get settingsItemSafety => '安全性';

  @override
  String get settingsItemMemory => 'メモリとコンテキスト';

  @override
  String get settingsItemAdvanced => '詳細設定';

  @override
  String get settingsItemNotifications => '通知';

  @override
  String get settingsItemBilling => '請求';

  @override
  String get settingsItemProviders => 'プロバイダー';

  @override
  String get settingsItemShortcuts => 'キーボードショートカット';

  @override
  String get settingsItemToolsKeys => 'ツールとキー';

  @override
  String get settingsItemPlugins => 'プラグイン';

  @override
  String get settingsItemArchived => 'アーカイブ済みチャット';

  @override
  String get settingsItemAbout => '情報';

  @override
  String get settingsGroupCore => 'コア';

  @override
  String get settingsGroupDevice => 'デバイス';

  @override
  String get settingsGroupAccount => 'アカウントと接続';

  @override
  String get settingsGroupSystem => 'システム';

  @override
  String get designSurfaceExample => 'サンプル · デザイン面';

  @override
  String get designSurfaceNoData =>
      'このページにはまだ実データのソースがありません。デザイン上のページであり、ゲートウェイに対応するインターフェースはまだありません。';

  @override
  String get composerFootCmd => '⌘K コマンド';

  @override
  String get composerFootHints => '↵ 送信 · ⇧↵ 改行 · Esc 閉じる';

  @override
  String get settingsSubtitle => 'Caduceus と Hermes サーバー';

  @override
  String get appearance => '外観';

  @override
  String get theme => 'テーマ';

  @override
  String get themeSystem => 'システム';

  @override
  String get themeLight => 'ライト';

  @override
  String get themeDark => 'ダーク';

  @override
  String get language => '言語';

  @override
  String get languageSystem => 'システムに従う';

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
  String get material => 'マテリアル';

  @override
  String get reduceVisualEffects => '視覚効果を減らす';

  @override
  String get whatItChanges => '変更内容';

  @override
  String get whatItChangesDesc =>
      'ガラスの代わりにソリッドパネルを使用し、オーロラ背景を無効にします。サイズやアニメーションはそのまま維持されます。';

  @override
  String get solid => 'ソリッド';

  @override
  String get glass => 'ガラス';

  @override
  String get session => 'セッション';

  @override
  String get modelAndSession => 'モデルとセッション';

  @override
  String get approvals => '承認';

  @override
  String get skills => 'スキル';

  @override
  String get voice => '音声';

  @override
  String get gateway => 'ゲートウェイ';

  @override
  String get device => 'デバイス';

  @override
  String get about => '情報';

  @override
  String get connection => '接続';

  @override
  String get connected => '接続済み';

  @override
  String get disconnected => '切断';

  @override
  String get pickGroupOnLeft => '左側からグループを選択';

  @override
  String get model => 'モデル';

  @override
  String get thisSession => '現在のセッション';

  @override
  String get changingIt => '変更方法';

  @override
  String get changingItDesc => 'ピッカーはコンポーザーの入力欄の横にあります。';

  @override
  String get workingDirectory => '作業ディレクトリ…';

  @override
  String get noSessionOpen => 'セッションが開いていません';

  @override
  String get dictation => '音声入力';

  @override
  String get running => '実行中';

  @override
  String get idle => '待機中';

  @override
  String get whereItRuns => '実行場所';

  @override
  String get onThisDevice => 'このデバイス上';

  @override
  String get address => 'アドレス';

  @override
  String get status => 'ステータス';

  @override
  String get version => 'バージョン';

  @override
  String get back => '戻る';

  @override
  String get connectNewBackend => '新しいバックエンドを接続';

  @override
  String get connectNewBackendSubtitle => '発見 · ペアリング · 診断';

  @override
  String get connectToHermesDesc =>
      'Hermesコントロールプレーンに接続します。SSHまたはTailscaleでトンネリングしてください。';

  @override
  String get addAnotherServer => 'サーバーを追加';

  @override
  String get sessionEndedWithError => 'セッションがエラーで終了しました';

  @override
  String get nameOptional => '名前 (任意)';

  @override
  String get serverUrl => 'サーバーURL';

  @override
  String get gatewayToken => 'ゲートウェイトークン';

  @override
  String get sessionToken => 'セッショントークン';

  @override
  String get openClawDeviceNote => 'OpenClawは承認されたデバイスのみ接続を許可します。';

  @override
  String get connect => '接続';

  @override
  String get forgetThisServer => 'このサーバーを削除';

  @override
  String get waitingToBeApproved => '承認待ち';

  @override
  String get openClawApprovalNote => 'トークンが受付されました。管理者による承認後、再接続してください。';

  @override
  String get copyDeviceId => 'デバイスIDをコピー';

  @override
  String get newSession => '新規セッション';

  @override
  String get searchSessions => 'セッションを検索';

  @override
  String get refresh => '更新';

  @override
  String get scheduledJobs => 'スケジュールタスク';

  @override
  String get projects => 'プロジェクト';

  @override
  String get backgroundProcesses => 'バックグラウンドプロセス…';

  @override
  String get agents => 'エージェント…';

  @override
  String get checkpoints => 'チェックポイント';

  @override
  String get learningJourney => '学習の記録';

  @override
  String get server => 'サーバー';

  @override
  String get noSessions => 'セッションがありません';

  @override
  String get noSessionsDesc => '新しいセッションを開始してください';

  @override
  String get reload => '再読み込み';

  @override
  String get cancel => 'キャンセル';

  @override
  String get close => '閉じる';

  @override
  String get save => '保存';

  @override
  String get stop => '停止';

  @override
  String get stopAll => 'すべて停止';

  @override
  String get delete => '削除';

  @override
  String get archive => 'アーカイブ';

  @override
  String get stopThisTitle => '停止しますか？';

  @override
  String get stopAllProcessesTitle => 'すべてのプロセスを停止しますか？';

  @override
  String get stopAllProcessesMessage => 'サーバー上のすべてのバックグラウンドプロセスを停止します。';

  @override
  String get nothingRunning => '実行中のプロセスはありません';

  @override
  String get hideOutput => '出力を非表示';

  @override
  String get showOutput => '出力を表示';

  @override
  String get delegation => 'タスク委任';

  @override
  String get noSubagentsRunning => '実行中のサブエージェントはありません';

  @override
  String get subagentsRunning => '個のサブエージェントが実行中';

  @override
  String get allowNewSubagents => '新しいサブエージェントを許可';

  @override
  String get spawningPaused => '生成停止中 — 既存のサブエージェントは継続します';

  @override
  String get agentMaySpawnChildren => 'エージェントは子エージェントを生成できます';

  @override
  String get savedSpawnTrees => '保存された生成ツリー';

  @override
  String get noneForThisSession => 'このセッションにはありません';

  @override
  String get recentActivity => 'アクティビティ';

  @override
  String get interruptThisSubagent => 'このサブエージェントを中断';

  @override
  String get restoreCheckpointTitle => 'チェックポイントを復元しますか？';

  @override
  String restoreCheckpointMessage(Object hash, Object timestamp) {
    return '$timestamp ($hash) の状態にファイルを復元します。';
  }

  @override
  String get noCheckpoints => 'チェックポイントがありません';

  @override
  String get selectCheckpointToSeeDiff => 'チェックポイントを選択して差分を確認';

  @override
  String get restoreThisCheckpoint => 'このチェックポイントを復元';

  @override
  String restored(Object hash) {
    return '$hash を復元しました';
  }

  @override
  String get newScheduledJob => '新規スケジュールタスク';

  @override
  String get jobName => '名前';

  @override
  String get schedule => 'スケジュール';

  @override
  String get scheduleHelper => 'cron式（例: 毎日09:00なら 0 9 * * *）';

  @override
  String get promptToRun => '実行プロンプト';

  @override
  String get create => '作成';

  @override
  String get noScheduledJobs => 'スケジュールタスクはありません';

  @override
  String get newJob => '新規ジョブ';

  @override
  String get thisEntryNoLongerAvailable => 'このエントリーは利用できません。';

  @override
  String get thisEntryHasNoContentYet => 'コンテンツがまだありません。';

  @override
  String get archiveSkillTitle => 'スキルをアーカイブしますか？';

  @override
  String get deleteMemoryTitle => '記憶を削除しますか？';

  @override
  String archiveSkillContent(Object label) {
    return '「$label」はサーバーにアーカイブされます。';
  }

  @override
  String deleteMemoryContent(Object label) {
    return '「$label」はエージェントの記憶から削除されます。';
  }

  @override
  String get install => 'インストール';

  @override
  String get noProjects => 'プロジェクトがありません';

  @override
  String get noSessionsInProject => 'セッションがありません';

  @override
  String get tools => 'ツール';

  @override
  String get commands => 'コマンド';

  @override
  String get config => '設定';

  @override
  String get plugins => 'プラグイン';

  @override
  String get thisServerReportsNothing => 'このサーバーはまだこのセッションに関する情報を報告していません。';

  @override
  String get readOnlyConfigNote => '読み取り専用: ここでの変更はサーバー全体に影響します。';

  @override
  String get maintenanceNote => 'メンテナンス — サーバー上の全セッションに影響します';

  @override
  String reloadTargetTitle(Object target) {
    return '$target を再読み込みしますか？';
  }

  @override
  String get reloadTargetMessage => 'サーバー上のすべてのセッションに影響します。';

  @override
  String get continueAction => '続行';

  @override
  String get typeAMessage => 'メッセージを入力...';

  @override
  String get send => '送信';

  @override
  String get stopTurn => '停止';

  @override
  String get thinking => '思考中...';

  @override
  String thinkingTime(Object seconds) {
    return '$seconds秒間思考';
  }

  @override
  String get copy => 'コピー';

  @override
  String get copied => 'コピーしました';

  @override
  String get retry => '再試行';

  @override
  String get edit => '編集';

  @override
  String get sessionActions => 'セッション操作';

  @override
  String get undoLastExchange => '直前のやり取りを取り消す';

  @override
  String get fileCheckpoints => 'ファイルチェックポイント…';

  @override
  String get journeyWhatItLearned => 'ジャーニー — 学習内容…';

  @override
  String get toolsetsSkillsPlugins => 'ツールセット、スキル、プラグイン…';

  @override
  String get findInConversation => '会話内を検索…';

  @override
  String get copyTranscript => '文字起こしをコピー';

  @override
  String get branchSession => 'ブランチ…';

  @override
  String get usageAndContext => '使用量とコンテキスト…';

  @override
  String get typeACommand => 'コマンドを入力…';

  @override
  String nothingMatches(Object query) {
    return '“$query” に一致する項目はありません';
  }

  @override
  String get actOnRunningTurn => '実行中のターンを操作';

  @override
  String get steerThisTurn => 'このターンを誘導';

  @override
  String get redirectThisTurn => 'このターンをリダイレクト';

  @override
  String get workingDirectoryTitle => '作業ディレクトリ';

  @override
  String get workingDirectoryDesc =>
      'エージェントが実行されているサーバー上のパス（このMac上ではありません）。添付ファイルと@-参照はこれを基準に解決されます。';

  @override
  String get set => '設定';

  @override
  String get nothingToUndo => '取り消すものがありません';

  @override
  String removedMessages(Object count) {
    return '$count 件のメッセージを削除しました';
  }

  @override
  String copiedCharacters(Object count) {
    return '$count 文字をコピーしました';
  }

  @override
  String get branchFailed => 'ブランチ作成に失敗しました';

  @override
  String branchedTo(Object id) {
    return '$id にブランチしました';
  }

  @override
  String get sessionUsage => 'セッション使用量';

  @override
  String get sessions => 'セッション';

  @override
  String get chat => 'チャット';

  @override
  String get panels => 'パネル';

  @override
  String get messaging => 'メッセージ';

  @override
  String get artifacts => 'アーティファクト';

  @override
  String get kanban => 'カンバン';

  @override
  String get photo => '写真';

  @override
  String get library => 'ライブラリ';

  @override
  String get file => 'ファイル';

  @override
  String get video => '動画';

  @override
  String get pasteFromClipboard => 'クリップボードから貼り付け';

  @override
  String get referencePathOnServer => 'サーバー上のパスを参照';

  @override
  String get queueForAfterThisTurn => 'このターンの終了後にキューに追加';

  @override
  String get attachSomething => 'ファイルを添付';

  @override
  String get rename => '名前を変更…';

  @override
  String get compressHistory => '履歴を圧縮';

  @override
  String get deleteSessionTitle => '削除…';

  @override
  String get renameSession => 'セッション名を変更';

  @override
  String get compressHistoryQuestion => '履歴を圧縮しますか？';

  @override
  String compressHistoryDesc(Object label) {
    return '“$label” の古いメッセージが要約されコンテキストが回収されます。この操作は取り消せません。';
  }

  @override
  String get deleteSessionQuestion => 'セッションを削除しますか？';

  @override
  String deleteSessionDesc(Object count, Object label) {
    return '“$label” とその $count 件のメッセージが永久に削除されます。';
  }

  @override
  String get holdToDelete => '長押しで削除';

  @override
  String get deleted => '削除済み';

  @override
  String get showSessions => 'セッションを表示';

  @override
  String get hideSessions => 'セッション非表示';

  @override
  String get appearanceSystem => '外観：システム';

  @override
  String get appearanceLight => '外観：ライト';

  @override
  String get appearanceDark => '外観：ダーク';

  @override
  String get modelForThisSession => 'このセッションのモデル';

  @override
  String get requeryProviders => 'プロバイダーを再クエリ';

  @override
  String get noModelList => 'このサーバーはモデルリストを提供していません。';

  @override
  String get noCredential => '資格情報なし';

  @override
  String get composerSuggestionResume => '前回のタスクを続ける';

  @override
  String get composerSuggestionStatus => '現在のセッションを確認';

  @override
  String get composerSuggestionRelease => 'リリースノートを書く';
}
