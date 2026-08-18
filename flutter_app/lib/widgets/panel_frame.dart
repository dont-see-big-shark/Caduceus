import 'package:flutter/material.dart';

import '../design/components.dart';
import '../design/glass.dart';
import '../design/press.dart';
import '../design/theme.dart';
import '../design/tokens.dart';

/// Sizes a panel to the screen it is actually on.
///
/// Every panel in this app was written against a Mac window and asked for a
/// fixed 560–640 px of width. On an iPhone that is wider than the screen, so
/// the dialog overflowed its own bounds and the content was clipped on both
/// sides. Asking for a width is fine as an *upper* bound; it has to be a
/// preference, not a demand.
///
/// Height is treated the same way. A 420 px panel plus title, actions and the
/// keyboard does not fit a phone in landscape.
class PanelFrame extends StatelessWidget {
  /// Every overlay card in the app opens at the same size — the Settings
  /// card's 960×620. The content area is 960×560; the shared glass header
  /// brings the card to ~620. Panels used to each ask for their own width
  /// (560–720 px) and read as a family of different surfaces.
  static const standardWidth = 960.0;
  static const standardHeight = 560.0;

  const PanelFrame({
    required this.child,
    this.preferredWidth = standardWidth,
    this.preferredHeight = standardHeight,
    super.key,
  });

  final Widget child;
  final double preferredWidth;
  final double preferredHeight;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < Panel.phoneWidth) {
      return SizedBox(width: double.infinity, child: child);
    }
    final media = MediaQuery.of(context);
    // AlertDialog already insets itself; this is the room left inside that.
    final maxWidth = media.size.width - 80;
    final maxHeight =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.vertical -
        200;
    return SizedBox(
      width: preferredWidth.clamp(200.0, maxWidth <= 200 ? 200.0 : maxWidth),
      height: preferredHeight.clamp(
        160.0,
        maxHeight <= 160 ? 160.0 : maxHeight,
      ),
      child: child,
    );
  }
}

/// A panel, as the screen it is on wants it.
///
/// On a Mac these are dialogs in the middle of a window, which is right: there
/// is a pointer, the window is large, and a centred card is where the platform
/// puts a secondary task. On a phone the same card is a small rectangle
/// floating in the middle of a tall screen, unreachable by the thumb holding
/// the device and dismissable only by a button at its top corner.
///
/// So on a phone it becomes a sheet: it rises from the bottom, it is as wide
/// as the screen, and **it comes back down by being pulled** — 手势跟随, the
/// same gesture and the same thresholds the command palette uses, because two
/// sheets that dismiss differently is worse than either choice alone.
class Panel extends StatelessWidget {
  /// Deliberately [AlertDialog]'s own signature. Every panel in this app was
  /// written as one, and a shape-compatible replacement is a change of one
  /// word per file rather than a rewrite of seven layouts — which is the
  /// difference between a refactor that can be reviewed and one that cannot.
  const Panel({
    required this.title,
    required this.content,
    this.actions,
    this.embedded = false,
    this.headerCenter,
    super.key,
  });

  final Widget title;
  final Widget content;
  final List<Widget>? actions;

  /// Rendered in the middle of the header row — the design's title-bar
  /// search. The title sits left, this sits centred between it and the close
  /// ×. Panels without one keep the title expanding as before.
  final Widget? headerCenter;

  /// Renders inside a parent surface instead of as a dialog/sheet.
  ///
  /// The desktop right-hand panel rail (`panel_rail.dart`) hosts the same
  /// panel widgets the dialogs use; embedded drops the `AlertDialog` chrome
  /// (surface, inset, shadow) so a panel can sit inside a `GlassPanel` as one
  /// column — title, content, actions — without nesting dialogs.
  final bool embedded;

  /// Below this the pointer-and-window assumptions stop holding.
  static const phoneWidth = 720.0;

  @override
  Widget build(BuildContext context) {
    if (embedded) {
      final theme = Theme.of(context);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (MediaQuery.sizeOf(context).width >= phoneWidth)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 10, 6),
              child: DefaultTextStyle.merge(
                style: theme.textTheme.titleSmall!,
                child: title,
              ),
            ),
          Expanded(child: content),
          if (actions case final actions? when actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
        ],
      );
    }
    if (MediaQuery.sizeOf(context).width >= phoneWidth) {
      // Every overlay in this design is the same glass card — the shell the
      // settings overlay uses: a thick sheet of frosted glass, a serif header
      // with a close × at the far end, a hairline divider, the page below.
      // Panels used to arrive as flat `AlertDialog`s; that read as a second,
      // cheaper surface next to Settings. They now share Settings' card.
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(28),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: GlassPanel(
            level: Glass.thick,
            radius: BorderRadius.circular(
              20,
            ), // matches the ClipRRect so the hairline border follows the rounded corners
            // The card sizes to its content — the same fixed size every
            // overlay opens at. Without this, `crossAxisAlignment.stretch`
            // forces the column to the Dialog's full width and a 960-wide
            // panel would come out as a full-window card.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 10, 10),
                    child: Row(
                      children: [
                        if (headerCenter != null)
                          Flexible(
                            // A header with a centre search: the title takes
                            // its natural width, the search gets the middle.
                            child: DefaultTextStyle.merge(
                              style: serifDisplay(context, size: 16),
                              child: title,
                            ),
                          )
                        else
                          Expanded(
                            // The panel's own title row (label + any refresh
                            // button) inherits the serif display face,
                            // matching the settings header exactly.
                            child: DefaultTextStyle.merge(
                              style: serifDisplay(context, size: 16),
                              child: title,
                            ),
                          ),
                        if (headerCenter case final center?)
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: center,
                            ),
                          ),
                        HeaderCloseButton(),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: context.ink.hairline),
                  Flexible(child: content),
                  if (actions case final actions? when actions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final media = MediaQuery.of(context);
    // Room for the sheet: everything except the status bar and the keyboard,
    // less a strip of the conversation left showing so the sheet reads as
    // being *over* something rather than as a new screen.
    final maxHeight =
        media.size.height - media.padding.top - media.viewInsets.bottom - 64;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: PullToDismiss(
          child: SizedBox(
            width: double.infinity,
            height: maxHeight < 300 ? 300 : maxHeight,
            child: GlassPanel(
              level: Glass.thick,
              // The design's mobile sheet rounds the top edge at 24 pt.
              radius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const GrabHandle(),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: DefaultTextStyle.merge(
                              style:
                                  Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600) ??
                                  const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                              child: title,
                            ),
                          ),
                          const HeaderCloseButton(),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: context.ink.hairline),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        removeBottom: true,
                        child: content,
                      ),
                    ),
                    if (actions case final actions? when actions.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: actions,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows a [Panel] the way its shape implies it should arrive.
///
/// 底部面板从下推入 360ms. `showDialog` fades and scales from the middle of the
/// screen, which is right for a dialog and wrong for a sheet: a sheet that
/// materialises in place has no relationship to the edge it is anchored to,
/// and the pull-down that dismisses it then looks like a gesture invented for
/// the occasion rather than the reverse of how it came in.
///
/// On a wide window nothing changes — a centred card should not slide in from
/// anywhere, because it is not attached to an edge.
Future<T?> showPanel<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) {
  final phone = MediaQuery.sizeOf(context).width < Panel.phoneWidth;
  if (!phone) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  }
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(_SheetRoute<T>(builder: builder, dismissible: barrierDismissible));
}

/// A sheet that comes up from the edge it is anchored to.
///
/// A [PopupRoute] rather than `showGeneralDialog`, for one reason: it can have
/// a *reverse* duration. Disappearing is always half the speed of appearing in
/// this design — nobody should wait for a dismissal — and the general-dialog
/// helper only takes one number for both.
class _SheetRoute<T> extends PopupRoute<T> {
  _SheetRoute({required this.builder, required this.dismissible});

  final WidgetBuilder builder;
  final bool dismissible;

  @override
  Duration get transitionDuration => Motion.emphasized;

  @override
  Duration get reverseTransitionDuration => Motion.exit;

  @override
  bool get barrierDismissible => dismissible;

  @override
  Color get barrierColor => Colors.black54;

  @override
  String? get barrierLabel => 'Dismiss';

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: Motion.emphasizedCurve,
        reverseCurve: Motion.exitCurve,
      ),
    ),
    child: child,
  );
}
