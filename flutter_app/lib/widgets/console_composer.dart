import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:agent_core/agent_core.dart';
import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';
import '../haptics.dart';
import 'package:flutter/services.dart';
import '../capture.dart';
import '../l10n/app_localizations.dart';
import '../workspace.dart';
import 'menu_card.dart';

/// Autocomplete item for slash commands (`/`) and server path references (`@`).
class CompletionItem {
  const CompletionItem({
    required this.insert,
    required this.label,
    required this.meta,
    this.replaceWord = false,
  });

  final String insert;
  final String label;
  final String meta;
  final bool replaceWord;
}

/// Composer input widget with debounced `@` path completion and attachment handling.
class ConsoleComposer extends StatefulWidget {
  const ConsoleComposer({
    required this.console,
    required this.workspace,
    required this.onSend,
    this.onPickModel,
    this.onStop,
    required this.onSteer,
    required this.onRedirect,
    this.completionsNotifier,
    required this.availableHeight,
    this.media,
    this.voice,
    super.key,
  });

  /// The camera and photo library. Injected so a test can answer "did the
  /// composer ask for a photo, and did the bytes reach the session" without a
  /// camera, and so the tiles that need hardware can be hidden where there is
  /// none.
  final MediaCapture? media;

  /// Dictation. Same reason.
  final VoiceInput? voice;

  /// The height the console actually has, from its `LayoutBuilder`.
  ///
  /// `MediaQuery.viewInsets` is zero in here — `Scaffold` subtracts the
  /// keyboard before building the body — so the old check saw a full-height
  /// screen and never went tight when it mattered.
  final double availableHeight;

  final SessionConsole console;
  final Workspace workspace;

  /// Sends [text], carrying whatever is on the chips with it.
  ///
  /// The attachments travel *with the message* rather than ahead of it: the
  /// composer holds bytes and the backend decides what to do with them, which
  /// is the only arrangement that works when two backends take a file two
  /// different ways.
  final Future<void> Function(String text, {List<Attachment> attachments})
  onSend;

  /// Opens the model picker. The model is shown beside the field rather than
  /// in a status line, so this is where it is changed from.
  final VoidCallback? onPickModel;

  /// Abandons the running turn. Send becomes stop while one is in flight.
  final VoidCallback? onStop;
  final Future<void> Function(String text) onSteer;
  final Future<void> Function(String text) onRedirect;
  final ValueNotifier<List<CompletionItem>>? completionsNotifier;

  @override
  State<ConsoleComposer> createState() => ConsoleComposerState();
}

/// One height for every control on the composer row, and the minimum touch
/// target iOS asks for.
const _actionBox = BoxConstraints(minWidth: 44, minHeight: 44);

class ConsoleComposerState extends State<ConsoleComposer> {
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  List<CompletionItem> _completions = const [];
  int _completionSeq = 0;
  Timer? _debounceTimer;

  SessionConsole get _c => widget.console;

  /// Clears the palette when the field loses focus.
  ///
  /// It only cleared on the *next keystroke*, so dismissing the keyboard or
  /// tapping the conversation left it open with no way to close it — you had
  /// to type something to make it go away.
  void _onFocusChanged() {
    if (!_inputFocus.hasFocus && _completions.isNotEmpty) {
      _setCompletions(const []);
    }
  }

  void _setCompletions(List<CompletionItem> items) {
    if (!mounted) return;
    setState(() => _completions = items);
    widget.completionsNotifier?.value = items;
  }

  /// Whether taking focus back is welcome.
  ///
  /// On a desktop, returning focus to the composer after every action is the
  /// right behaviour — the caret should be where you type next. On a phone it
  /// is the reason the keyboard "cannot be dismissed": you send, it reopens;
  /// you attach a file, it reopens; you tap away and the next action brings it
  /// straight back. On touch the keyboard is half the screen, and it belongs
  /// to the user, not to this widget.
  bool get _keyboardIsCheap {
    final platform = Theme.of(context).platform;
    return platform != TargetPlatform.iOS && platform != TargetPlatform.android;
  }

  void _returnFocus() {
    if (_keyboardIsCheap) _inputFocus.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onFocusChanged);
    // Deliberately not focused here. Opening a session on a phone used to
    // raise the keyboard before the transcript had been read at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _keyboardIsCheap) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onFocusChanged);
    _debounceTimer?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void requestFocus() => _inputFocus.requestFocus();

  String get text => _input.text.trim();

  void clearInput() => _input.clear();

  List<CompletionItem> get completions => _completions;

  Future<void> _handleSend() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    // Before the await, so the press is acknowledged even when the send is
    // slow. A phone has no hover or cursor change to say a tap registered,
    // which is why people tap twice.
    Haptics.tap();
    _input.clear();
    final attachments = [for (final a in _attachments) a.file];
    // The chips describe what is riding along with *this* message. Once it is
    // gone they describe nothing, and leaving them up implies the next message
    // carries the same file too.
    setState(_attachments.clear);
    _setCompletions(const []);
    await widget.onSend(text, attachments: attachments);
    _returnFocus();
  }

  Future<void> _handleSteer() async {
    Haptics.tap();
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await widget.onSteer(text);
    _returnFocus();
  }

  Future<void> _handleRedirect() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await widget.onRedirect(text);
    _returnFocus();
  }

  /// Whether the field was empty at the last rebuild.
  ///
  /// The primary button is send when there is something to send and stop when
  /// there is not, so the composer has to rebuild when that flips. It listens
  /// to the console, which knows nothing about typing.
  bool _wasEmpty = true;

  void _onInputChanged(String value) {
    final empty = value.trim().isEmpty;
    if (empty != _wasEmpty) {
      _wasEmpty = empty;
      if (mounted) setState(() {});
    }
    final text = value.trimLeft();
    if (text.startsWith('/') && !text.contains(' ')) {
      _debounceTimer?.cancel();
      // The catalog is fetched once and cached, but the first `/` in a session
      // arrives before it: the completions were computed from whatever
      // `commands` held at that instant — nothing — and nothing recomputed
      // them when the reply landed. The palette simply never appeared.
      if (widget.workspace.commands.isEmpty) {
        widget.workspace.loadCommands().then((_) {
          if (mounted && _input.text.trimLeft().startsWith('/')) {
            _onInputChanged(_input.text);
          }
        });
      }
      final query = text.substring(1);
      _setCompletions(
        widget.workspace.commands
            .where((c) => query.isEmpty || c.matches(query))
            .take(8)
            .map(
              (c) => CompletionItem(
                insert: '${c.name} ',
                label: c.name,
                meta: c.description,
              ),
            )
            .toList(),
      );
      return;
    }

    final word = _wordAtCursor(value);
    if (word != null && word.startsWith('@')) {
      // Debounce @ path autocomplete by 150 ms to eliminate RPC flooding
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 150), () {
        _completePath(word);
      });
      return;
    }

    _debounceTimer?.cancel();
    if (_completions.isNotEmpty) _setCompletions(const []);
  }

  String? _wordAtCursor(String value) {
    final caret = _input.selection.baseOffset;
    final end = caret < 0 || caret > value.length ? value.length : caret;
    // Nothing before the caret is not a word — and `lastIndexOf(…, -1)` is a
    // RangeError, not an empty result. Deleting the last character of the
    // composer is enough to reach it, which makes this the most ordinary
    // crash in the app: type anything, then erase it.
    if (end <= 0) return null;
    final start = value.lastIndexOf(RegExp(r'\s'), end - 1) + 1;
    if (start >= end) return null;
    return value.substring(start, end);
  }

  Future<void> _completePath(String word) async {
    final seq = ++_completionSeq;
    final items = await widget.workspace.completePath(_c.persistedId, word);
    if (!mounted || seq != _completionSeq) return;
    _setCompletions(
      items
          .take(8)
          .map(
            (i) => CompletionItem(
              insert: i.text,
              label: i.display,
              meta: i.meta,
              replaceWord: true,
            ),
          )
          .toList(),
    );
  }

  void applyCompletion(CompletionItem completion) {
    if (completion.replaceWord) {
      final value = _input.text;
      final caret = _input.selection.baseOffset;
      final end = caret < 0 || caret > value.length ? value.length : caret;
      final start = value.lastIndexOf(RegExp(r'\s'), end - 1) + 1;
      final trailing = completion.insert.endsWith('/') ? '' : ' ';
      _input.text = value.replaceRange(
        start,
        end,
        '${completion.insert}$trailing',
      );
      _input.selection = TextSelection.collapsed(
        offset: start + completion.insert.length + trailing.length,
      );
      _setCompletions(const []);
      _inputFocus.requestFocus();
      if (trailing.isEmpty) _onInputChanged(_input.text);
      return;
    }
    _input.text = completion.insert;
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _setCompletions(const []);
    _returnFocus();
  }

  /// What is riding along with the next message.
  ///
  /// The design draws these as chips under the field, which is the only way to
  /// see what you have attached — the previous behaviour appended a `@ref` to
  /// the text for a file and showed a snackbar for an image, so an image you
  /// attached left no trace at all once the snackbar faded.
  final List<_Attachment> _attachments = [];

  /// The attach button's position, for the desktop popup menu that opens
  /// from it.
  final _attachKey = GlobalKey();

  late final MediaCapture _media = widget.media ?? PlatformMediaCapture();
  late final VoiceInput _voice = widget.voice ?? PlatformVoiceInput();

  /// The ＋ sheet: where an attachment can come from.
  ///
  /// The prototype draws four tiles — 拍照 · 图库 · 文件 · 录像 — rather than a
  /// list, and the shape is the point: four things you pick between belong
  /// side by side, where the choice is one glance rather than four reads.
  ///
  /// Camera and video are hidden where `image_picker` has no camera to open
  /// (macOS, and anything headless): a tile that opens nothing is worse than
  /// a tile that is not there. The clipboard and a server-side path are kept
  /// underneath as rows, because they are not captures — a `@ref` resolved
  /// against the session's cwd has nothing to do with this device at all.
  bool get _canAttach =>
      widget.workspace.supports(Capability.fileAttach) ||
      widget.workspace.supports(Capability.imageAttach);

  List<(String, String, IconData)> get _tiles {
    final l10n = AppLocalizations.of(context);
    return [
      if (_media.hasCamera)
        ('camera', l10n?.photo ?? 'Photo', Icons.camera_alt_outlined),
      ('library', l10n?.library ?? 'Library', Icons.grid_on_outlined),
      ('file', l10n?.file ?? 'File', Icons.description_outlined),
      if (_media.hasCamera)
        ('video', l10n?.video ?? 'Video', Icons.videocam_outlined),
    ];
  }

  List<(String, String, IconData)> get _rows {
    final l10n = AppLocalizations.of(context);
    return [
      (
        'clipboard',
        l10n?.pasteFromClipboard ?? 'Paste from the clipboard',
        Icons.content_paste,
      ),
      (
        'server',
        l10n?.referencePathOnServer ?? 'Reference a path on the server',
        Icons.dns_outlined,
      ),
    ];
  }

  Future<void> _openAttachMenu() async {
    Haptics.select();
    // Both platforms use the design's `attach-pop`: a glass card anchored to
    // the button, opening above it — not a phone-only bottom sheet.
    final choice = await showMenuAnchor<String>(
      context,
      anchor: _attachKey,
      offset: const Offset(0, -8),
      menu: _attachMenuCard(_tiles, _rows),
    );
    if (choice != null && mounted) _handleAttachChoice(choice);
  }

  void _handleAttachChoice(String choice) {
    switch (choice) {
      case 'file':
        _attach();
      case 'library':
        _capture(_media.fromLibrary);
      case 'camera':
        _capture(_media.photo);
      case 'video':
        _capture(_media.video);
      case 'clipboard':
        _pasteClipboard();
      case 'server':
        _referenceServerPath();
    }
  }

  Widget _attachMenuCard(
    List<(String, String, IconData)> tiles,
    List<(String, String, IconData)> rows,
  ) {
    // The design's `attach-pop`: a compact glass card anchored to the
    // attach button, not a centred dialog.
    return MenuCard(
      width: 232,
      items: [
        for (final tile in tiles)
          MenuItem(
            label: tile.$2,
            icon: tile.$3,
            onTap: () => Navigator.of(context).pop(tile.$1),
          ),
        const MenuItem(label: '', divider: true),
        for (final source in rows)
          MenuItem(
            label: source.$2,
            icon: source.$3,
            onTap: () => Navigator.of(context).pop(source.$1),
          ),
      ],
    );
  }

  /// Runs one of the capture sources and attaches whatever comes back.
  ///
  /// A refusal at the system prompt and a user backing out of the camera are
  /// indistinguishable here, and should be: neither is an error, and neither
  /// deserves a message. What does deserve one is the platform throwing —
  /// a missing permission string terminates the app on iOS, but on macOS and
  /// in a simulator it surfaces as an exception, and silence there would look
  /// exactly like a button that does nothing.
  Future<void> _capture(Future<Captured?> Function() source) async {
    try {
      final shot = await source();
      if (shot == null || !mounted) return;
      await _attachBytes(
        name: shot.name,
        bytes: shot.bytes,
        mimeType: shot.mimeType,
      );
    } on Exception catch (e) {
      if (mounted) _say('Could not attach that: $e');
    }
  }

  /// What the microphone is doing right now.
  Dictation _dictation = Dictation.idle;

  /// What was in the field before dictation started.
  ///
  /// Partial results arrive as the *whole* phrase so far, not as deltas, so
  /// each one replaces the last — appending them would spell the sentence out
  /// cumulatively. Anything already typed has to be preserved around that.
  String _beforeDictation = '';

  Future<void> _toggleDictation() async {
    if (_dictation == Dictation.listening) {
      await _voice.stop();
      if (mounted) setState(() => _dictation = Dictation.idle);
      Haptics.tap();
      return;
    }
    Haptics.select();
    _beforeDictation = _input.text.trimRight();
    final started = await _voice.start(
      onResult: (text, finished) {
        if (!mounted) return;
        final joiner = _beforeDictation.isEmpty ? '' : ' ';
        _input.text = '$_beforeDictation$joiner$text';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
        if (finished) setState(() => _dictation = Dictation.idle);
      },
    );
    if (!mounted) return;
    setState(
      () => _dictation = started ? Dictation.listening : Dictation.unavailable,
    );
    if (!started) {
      _say('Dictation is not available — check microphone and speech access');
    }
  }

  /// Pastes clipboard text into the field rather than sending it as a file.
  ///
  /// A pasted snippet is almost always something to *talk about*, and text in
  /// the prompt is cheaper and more useful to the model than an attachment it
  /// has to open.
  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) _say('The clipboard has no text in it');
      return;
    }
    final prefix = _input.text.isEmpty || _input.text.endsWith('\n')
        ? ''
        : '\n';
    _input.text = '${_input.text}$prefix$text';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _returnFocus();
  }

  /// Starts an `@` reference and opens completion against the session's cwd.
  void _referenceServerPath() {
    final prefix = _input.text.isEmpty || _input.text.endsWith(' ') ? '' : ' ';
    _input.text = '${_input.text}$prefix@';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _inputFocus.requestFocus();
    _onInputChanged(_input.text);
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _attach({bool imagesOnly = false}) async {
    final file = await openFile(
      acceptedTypeGroups: imagesOnly
          ? const [
              XTypeGroup(
                label: 'Images',
                extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
              ),
            ]
          : const [],
    );
    if (file == null) return;
    await _attachBytes(
      name: file.name,
      bytes: await file.readAsBytes(),
      mimeType: file.mimeType,
    );
  }

  /// Attaches bytes that are already in hand, whatever produced them.
  ///
  /// The file picker, the camera and the video recorder all end up here: what
  /// the session is given is a name and some bytes, and where they came from
  /// stops mattering the moment they exist. Keeping one path also keeps one
  /// answer to the question the two branches below disagree on — whether the
  /// attachment can still be taken back.
  Future<void> _attachBytes({
    required String name,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';
    const imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
    final isImage = imageExtensions.contains(extension);
    setState(() {
      _attachments.add(
        _Attachment(
          icon: isImage ? Icons.image_outlined : Icons.description_outlined,
          file: Attachment(
            name: name,
            bytes: bytes,
            // The picker knows the type on some platforms and not others; the
            // extension is the fallback, and an unknown type is a byte stream
            // rather than a guess.
            mimeType: mimeType ?? _mimeFor(extension),
          ),
        ),
      );
    });
    Haptics.tap();
  }

  static String _mimeFor(String extension) => switch (extension) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'txt' || 'md' => 'text/plain',
    'json' => 'application/json',
    'pdf' => 'application/pdf',
    _ => 'application/octet-stream',
  };

  void _removeAttachment(_Attachment a) =>
      setState(() => _attachments.remove(a));

  /// The input field itself — shared by the phone's single-row composer and
  /// the desktop's stacked field + toolbar, so the two cannot drift.
  Widget _field({required bool tight, required bool veryTight}) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _handleSend,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _setCompletions(const []),
      },
      child: TextField(
        controller: _input,
        focusNode: _inputFocus,
        onChanged: _onInputChanged,
        minLines: 1,
        maxLines: veryTight ? 1 : (tight ? 2 : 6),
        style: Theme.of(context).textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: _c.streaming
              ? (AppLocalizations.of(context)?.queueForAfterThisTurn ??
                    'Queue for after this turn')
              : (AppLocalizations.of(context)?.typeAMessage ??
                    'Message, or / for a command'),
          hintStyle: TextStyle(color: context.ink.faint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
        // PC 端 Enter 发送、⇧↵ 换行 — the design's composer-foot:
        // ↵ 发送 · ⇧↵ 换行. A `send` action makes plain Enter run
        // onSubmitted and keeps Shift+Enter inserting the newline.
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _handleSend(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final room = widget.availableHeight;
        final tight = room < 420;
        // Landscape with a keyboard up leaves under 200 points for the whole
        // console. Two lines of field fit at the default text size and
        // overflow by 11 at ×1.3 — so the *scaled* line height decides, not
        // the raw number of points.
        final lineHeight = media.textScaler.scale(14) * 1.7;
        final veryTight = room - 44 - lineHeight * 2 < 90;
        final dark = Theme.of(context).brightness == Brightness.dark;
        // A phone has no room for a tools band *and* a card — the design's
        // `composer-tools` row (model chip) floats above the glass card, so
        // the card's own toolbar does not repeat it.
        final isPhone = MediaQuery.sizeOf(context).width < 720;
        return SizedBox(
          // Full width: the composer card must span the whole console column
          // so its send button sits against the console's right edge — as the
          // design's `.composer-wrap` does. In a centered column the card
          // shrank to its content and send floated ~350 pt off the edge.
          width: double.infinity,
          child: Padding(
            key: const ValueKey('composer'),
            padding: isPhone
                ? const EdgeInsets.fromLTRB(12, 10, 12, 20)
                : const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A prompt the server accepted but has not started. It is in no
                // transcript and no event stream until the current turn drains,
                // so without this it looks like the message was never sent.
                if (_c.queuedPrompt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.schedule_send,
                          size: 14,
                          color: Palette.brass,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Queued for after this turn: ${_c.queuedPrompt}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),

                // One rounded card holding the field and its controls, the
                // shape every phone chat app has converged on. The previous row
                // put a bordered field between two loose buttons whose 48 pt
                // boxes never lined up with the field's ~40 pt — the
                // misalignment reported from the phone. Here the field has no
                // border of its own and the controls sit on their own line, so
                // there is nothing left to misalign.
                // Glass, and lit around the edge while a turn generates.
                // 边缘流光 replaces a "generating…" label outright: the composer
                // is already where the eye is, and a travelling edge says
                // *working* without spending a line of text or a translation.
                RimLight(
                  active: _c.streaming,
                  radius: const BorderRadius.all(Radius.circular(22)),
                  child: GlassPanel(
                    radius: const BorderRadius.all(Radius.circular(22)),
                    tint: dark ? null : Colors.white.withValues(alpha: .95),
                    // Tight in landscape: 393 points of height with a keyboard
                    // over most of it leaves the card a few points, and the
                    // stacked layout overflowed by 5. The controls fold onto the
                    // field's line when there is no room to stack them.
                    padding: EdgeInsets.fromLTRB(
                      14,
                      tight ? 0 : 4,
                      8,
                      tight ? 0 : 6,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_attachments.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 2),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final a in _attachments)
                                  _AttachmentChip(
                                    attachment: a,
                                    onRemove: () => _removeAttachment(a),
                                  ),
                              ],
                            ),
                          ),
                        // The phone's Claude-style composer: the field on
                        // top, and the same toolbar band as the desktop
                        // underneath — model switch left, send right. It keeps
                        // one control vocabulary across both surfaces rather
                        // than teaching the phone a second one.
                        if (isPhone && !tight)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _field(tight: tight, veryTight: veryTight),
                              const _InsetRule(),
                              Row(
                                children: [
                                  if (_c.model.isNotEmpty)
                                    Flexible(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ModelChip(
                                          model: _c.model,
                                          onTap: widget.onPickModel,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  if (_canAttach)
                                    _GlyphButton(
                                      key: _attachKey,
                                      glyph: Icons.add_rounded,
                                      tooltip:
                                          AppLocalizations.of(
                                            context,
                                          )?.attachSomething ??
                                          'Attach something',
                                      onTap: _openAttachMenu,
                                    ),
                                  _SendButton(
                                    stopping:
                                        _c.streaming &&
                                        _input.text.trim().isEmpty,
                                    queueing: _c.streaming,
                                    onSend: _handleSend,
                                    onStop: widget.onStop,
                                  ),
                                ],
                              ),
                            ],
                          )
                        else if (isPhone)
                          // A keyboard-up landscape leaves the card a few
                          // points tall; the controls fold onto the field's
                          // line so the whole card still fits.
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              if (_canAttach)
                                _GlyphButton(
                                  key: _attachKey,
                                  glyph: Icons.add_rounded,
                                  tooltip:
                                      AppLocalizations.of(
                                        context,
                                      )?.attachSomething ??
                                      'Attach something',
                                  onTap: _openAttachMenu,
                                ),
                              Expanded(
                                child: _field(
                                  tight: tight,
                                  veryTight: veryTight,
                                ),
                              ),
                              _SendButton(
                                stopping:
                                    _c.streaming && _input.text.trim().isEmpty,
                                queueing: _c.streaming,
                                onSend: _handleSend,
                                onStop: widget.onStop,
                              ),
                            ],
                          )
                        else ...[
                          _field(tight: tight, veryTight: veryTight),
                          const _InsetRule(),
                          LayoutBuilder(
                            builder: (context, box) {
                              // A squeezed desktop console can be ~140 pt wide
                              // (min window minus an expanded rail and the panel
                              // column). The toolbar sheds secondary controls
                              // before it overflows: attach and the model chip
                              // go first, then dictation, and send always stays.
                              final veryNarrow = box.maxWidth < 260;
                              final sendOnly = box.maxWidth < 120;
                              return Row(
                                children: [
                                  if (_canAttach && !veryNarrow)
                                    _GlyphButton(
                                      key: _attachKey,
                                      glyph: Icons.add_rounded,
                                      tooltip:
                                          AppLocalizations.of(
                                            context,
                                          )?.attachSomething ??
                                          'Attach something',
                                      onTap: _openAttachMenu,
                                    ),
                                  if (_c.model.isNotEmpty && !sendOnly)
                                    Expanded(
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: ModelChip(
                                          model: _c.model,
                                          onTap: widget.onPickModel,
                                        ),
                                      ),
                                    ),
                                  if (_c.streaming && !veryNarrow)
                                    _QuietFor(console: _c),
                                  if (_c.streaming && !veryNarrow)
                                    _AltRouteMenu(
                                      onSteer: _handleSteer,
                                      onRedirect: _handleRedirect,
                                    ),
                                  if (!_c.streaming && !sendOnly)
                                    _MicButton(
                                      state: _dictation,
                                      onTap: _toggleDictation,
                                    ),
                                  _SendButton(
                                    stopping:
                                        _c.streaming &&
                                        _input.text.trim().isEmpty,
                                    queueing: _c.streaming,
                                    onSend: _handleSend,
                                    onStop: widget.onStop,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Something riding along with the next message.
@immutable
/// Something picked, waiting to ride along with the next message.
///
/// Held rather than uploaded. It used to go to the server the moment it was
/// picked, which meant the *composer* had to know how a given backend takes a
/// file — and on one that does not take them the way Hermes does, the pick
/// simply failed. It also meant an attachment could not be taken back, because
/// by the time the chip appeared the server already had it.
class _Attachment {
  const _Attachment({required this.icon, required this.file});

  final IconData icon;
  final Attachment file;

  String get name => file.name;
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.attachment, required this.onRemove});

  final _Attachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => GlassPanel.pill(
    level: Glass.thin,
    padding: EdgeInsets.only(left: 10, right: onRemove == null ? 12 : 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(attachment.icon, size: 13, color: context.ink.tertiary),
        const SizedBox(width: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Text(
              attachment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, size: 11, opacity: InkLevel.secondary),
            ),
          ),
        ),
        if (onRemove != null)
          Pressable(
            onTap: onRemove,
            haptic: false,
            semanticLabel: 'Remove ${attachment.name}',
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: context.ink.faint,
              ),
            ),
          ),
      ],
    ),
  );
}

/// The composer's primary control, and the one that changes meaning.
///
/// 按钮旋转 45° 并缩到 0.9 变成"停止" — send and stop are the *same* button
/// rotating into its other state, not two buttons swapping places. That is
/// what makes it legible: the thing under your thumb never moves, and the
/// rotation tells you it now does the opposite.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.stopping,
    required this.queueing,
    required this.onSend,
    required this.onStop,
  });

  final bool stopping;

  /// A turn is running but there is text: sending queues it behind the turn.
  final bool queueing;
  final VoidCallback onSend;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: stopping
          ? 'Stop this turn'
          : queueing
          ? 'Queue for after this turn'
          : 'Send',
      child: Pressable(
        onTap: stopping ? onStop : onSend,
        semanticLabel: stopping ? 'Stop this turn' : 'Send',
        child: ConstrainedBox(
          constraints: _actionBox,
          child: Center(
            child: AnimatedRotation(
              turns: stopping ? .125 : 0,
              duration: Motion.standard,
              curve: Motion.standardCurve,
              child: AnimatedScale(
                scale: stopping ? .9 : 1,
                duration: Motion.standard,
                curve: Motion.standardCurve,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: brassSheen,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Palette.brass.withValues(alpha: .3),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    // Un-rotated inside the rotating disc: the *disc* turns,
                    // the glyph stays upright, which is why the square reads
                    // as a stop sign and not a tilted arrow.
                    child: AnimatedRotation(
                      turns: stopping ? -.125 : 0,
                      duration: Motion.standard,
                      curve: Motion.standardCurve,
                      child: Icon(
                        stopping
                            ? Icons.stop_rounded
                            : Icons.arrow_upward_rounded,
                        size: 18,
                        color: Palette.slate,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare glyph with a full touch target — attach, and anything like it.
class _GlyphButton extends StatelessWidget {
  const _GlyphButton({
    required this.glyph,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final IconData glyph;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Pressable(
      onTap: onTap,
      semanticLabel: tooltip,
      child: ConstrainedBox(
        constraints: _actionBox,
        child: Center(
          child: ComposerChip(
            child: Icon(glyph, size: 18, color: context.ink.secondary),
          ),
        ),
      ),
    ),
  );
}

/// The model, in mono, because it is a machine identifier.
/// Which model is answering, and — where one can be chosen — the way to it.
class ModelChip extends StatelessWidget {
  const ModelChip({required this.model, required this.onTap, super.key});

  final String model;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    haptic: false,
    semanticLabel: 'Model: $model',
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: context.ink.base.withValues(alpha: .05),
        border: Border.all(color: context.ink.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              model,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(context, size: 11, opacity: InkLevel.secondary),
            ),
          ),
          // The chevron is the promise that something opens. Which model is
          // answering is worth showing on a backend that cannot change it —
          // the promise is not, and a control that looks pressable and is not
          // is the same broken promise as one that fails when pressed.
          if (onTap != null) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 13,
              color: context.ink.faint,
            ),
          ],
        ],
      ),
    ),
  );
}

/// Completion dropdown overlay widget for slash commands and path suggestions.
class CompletionOverlay extends StatelessWidget {
  const CompletionOverlay({
    required this.completions,
    required this.maxHeight,
    required this.onSelect,
    super.key,
  });

  final List<CompletionItem> completions;
  final double maxHeight;
  final ValueChanged<CompletionItem> onSelect;

  @override
  Widget build(BuildContext context) {
    // The thickest glass in the system — this floats furthest from the page,
    // and thickness is how this design says "in front of".
    return Padding(
      key: const ValueKey('completions'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: GlassPanel(
        level: Glass.thick,
        radius: Radii.largeAll,
        child: Material(
          type: MaterialType.transparency,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            // Scoped: this list rebuilds on every keystroke as the query
            // narrows. Re-animating the remaining rows each time reads as
            // flicker, not as choreography.
            child: StaggerScope(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: completions.length,
                itemBuilder: (context, i) {
                  final c = completions[i];
                  return Staggered(
                    index: i,
                    from: const Offset(0, 6),
                    child: InkWell(
                      onTap: () => onSelect(c),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Text(
                              c.label,
                              style: mono(
                                context,
                                size: 13,
                                opacity: InkLevel.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                c.meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.ink.faint,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// How long the running turn has been quiet.
///
/// Silent below [_after]: a turn that is streaming normally produces a frame
/// every few hundred milliseconds, and a counter resetting to zero over and
/// over is noise sitting next to the send button. What the number is *for* is
/// the other case — nothing has arrived for a while, and the UI would
/// otherwise look identical whether the agent is thinking hard or the
/// connection has died.
class _QuietFor extends StatelessWidget {
  const _QuietFor({required this.console});

  final SessionConsole console;

  /// Below this it is not yet news.
  static const _after = Duration(seconds: 3);

  @override
  Widget build(BuildContext context) {
    final quiet = console.sinceActivity;
    if (quiet < _after) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        label: 'Quiet for ${quiet.inSeconds} seconds',
        child: ExcludeSemantics(
          child: Text(
            'quiet ${quiet.inSeconds}s',
            style: mono(context, size: 11, opacity: InkLevel.tertiary),
          ),
        ),
      ),
    );
  }
}

/// One of the ＋ sheet's four tiles.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.state, required this.onTap});

  final Dictation state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final listening = state == Dictation.listening;
    return Tooltip(
      message: listening ? 'Stop dictating' : 'Dictate',
      child: Pressable(
        onTap: onTap,
        haptic: false,
        semanticLabel: listening ? 'Stop dictating' : 'Dictate a message',
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: ComposerChip(
              // Listening is the one state that must be unmistakable: a
              // microphone that is open and looks shut is the worst failure
              // this control has, so that state leaves the chip's palette
              // entirely rather than shading within it.
              fill: listening ? Palette.coral.withValues(alpha: .9) : null,
              child: Icon(
                listening ? Icons.stop_rounded : Icons.mic_none_rounded,
                size: 17,
                color: listening ? Colors.white : context.ink.secondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round backing every small composer control sits on.
///
/// The ＋ had no backing at all — a bare glyph floating on the field — while
/// the microphone had a fill and no edge and the send button had both. Three
/// controls in one row, none of them the same object. What makes brass read
/// as the primary here is that it is the *only* one that is filled and lit;
/// that contrast only exists if its neighbours are a consistent, quieter
/// thing rather than three different quieter things.
class ComposerChip extends StatelessWidget {
  const ComposerChip({required this.child, this.fill, super.key});

  final Widget child;

  /// Overrides the resting fill, for a state that has to leave the palette.
  final Color? fill;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: Motion.standard,
    curve: Motion.standardCurve,
    width: 34,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: fill ?? context.ink.base.withValues(alpha: .07),
      border: Border.all(
        color: fill == null ? context.ink.hairline : Colors.transparent,
      ),
    ),
    child: child,
  );
}

/// A hairline that reads as light on an edge rather than as a drawn line.
///
/// Two rows of one pixel: a white one at the boundary and a dark one directly
/// under it. That pair is what a lit edge on a physical panel looks like, and
/// it is why this does not read as a table border — a single grey rule at 12%
/// is a divider, the same rule with a shadow beneath it is a *surface*.

class _InsetRule extends StatelessWidget {
  const _InsetRule();

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: dark ? .10 : .5),
          ),
          Container(
            height: 1,
            color: Colors.black.withValues(alpha: dark ? .16 : .04),
          ),
        ],
      ),
    );
  }
}

/// The alt-route menu for a running turn — the same glass-card menu as
/// everywhere else.
class _AltRouteMenu extends StatelessWidget {
  const _AltRouteMenu({required this.onSteer, required this.onRedirect});

  final VoidCallback onSteer;
  final VoidCallback onRedirect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final menu = MenuController();
    return Tooltip(
      message: l10n?.actOnRunningTurn ?? 'Act on the running turn',
      child: MenuAnchor(
        controller: menu,
        style: anchoredMenuStyle,
        alignmentOffset: const Offset(-120, 6),
        menuChildren: [
          MenuCard(
            items: [
              MenuItem(
                label: l10n?.steerThisTurn ?? 'Steer this turn',
                onTap: () {
                  menu.close();
                  Haptics.select();
                  onSteer();
                },
              ),
              MenuItem(
                label: l10n?.redirectThisTurn ?? 'Redirect this turn',
                onTap: () {
                  menu.close();
                  Haptics.select();
                  onRedirect();
                },
              ),
            ],
          ),
        ],
        child: Pressable(
          onTap: () {
            Haptics.select();
            menu.open();
          },
          child: Icon(Icons.alt_route, size: 18, color: context.ink.tertiary),
        ),
      ),
    );
  }
}
