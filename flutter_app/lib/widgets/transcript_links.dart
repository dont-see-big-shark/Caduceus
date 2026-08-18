import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../haptics.dart';
import '../widgets/panel_frame.dart';

/// Opens a link from the transcript.
///
/// `MarkdownBody` renders links in link colours whether or not anything
/// handles a tap, so leaving this out was worse than rendering them as plain
/// text: it promised something the app did not do.
///
/// `file:` is the interesting case. Those paths belong to the machine running
/// the agent, not to this one, and the control plane has no method for reading
/// a file back — `file.attach`, `image.attach` and `pdf.attach` all push
/// *to* the server. So it cannot be downloaded, and pretending otherwise with
/// a spinner that fails would be worse than saying so. The path is offered for
/// copying instead, which is what someone needs to fetch it over ssh or ask
/// the agent for it.
Future<void> openTranscriptLink(
  BuildContext context,
  String? href, {
  String? title,
}) async {
  final raw = (href ?? '').trim();
  if (raw.isEmpty) return;
  final uri = Uri.tryParse(raw);
  if (uri == null) return;

  Haptics.tap();

  if (uri.scheme == 'file') {
    await _showServerPath(context, uri, title: title);
    return;
  }

  // Anything else goes to the platform: http and https to a browser, mailto
  // and tel to their handlers.
  try {
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (launched || !context.mounted) return;
  } catch (_) {
    if (!context.mounted) return;
  }
  _snack(context, 'Could not open $raw');
}

Future<void> _showServerPath(
  BuildContext context,
  Uri uri, {
  String? title,
}) async {
  // `file:///srv/x` → `/srv/x`. Keeping the scheme in the copied text would
  // make it useless to paste into scp or an editor.
  final path = uri.toFilePath();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => Panel(
      title: Text(title?.isNotEmpty == true ? title! : 'File on the server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This path is on the machine running the agent, not on this '
            'device, and the control plane has no way to send a file back. '
            'Copy the path to fetch it yourself, or ask the agent for its '
            'contents.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SelectableText(
            path,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: path));
            if (context.mounted) Navigator.of(context).pop();
          },
          child: const Text('Copy path'),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
