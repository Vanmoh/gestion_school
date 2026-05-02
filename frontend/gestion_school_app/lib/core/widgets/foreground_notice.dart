import 'dart:async';

import 'package:flutter/material.dart';

class ForegroundNotice {
  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(
    BuildContext context,
    String message, {
    bool isSuccess = false,
    bool isError = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _activeTimer?.cancel();
    _activeTimer = null;
    _activeEntry?.remove();
    _activeEntry = null;

    final colorScheme = Theme.of(context).colorScheme;
    final accentColor = isError
        ? colorScheme.error
        : (isSuccess ? const Color(0xFF197A43) : colorScheme.primary);
    final backgroundColor = isSuccess
      ? const Color(0xFF197A43)
      : colorScheme.surfaceContainerHigh;
    final foregroundColor = isSuccess ? Colors.white : colorScheme.onSurface;

    final media = MediaQuery.of(context).size;
    final route = ModalRoute.of(context);
    final isDialogRoute = route is PopupRoute;
    final isMobile = media.width < 700;
    final maxWidth = isMobile ? media.width - 24 : 380.0;
    final topOffset = isDialogRoute ? (isMobile ? 16.0 : 24.0) : 12.0;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 12 : 16,
                topOffset,
                isMobile ? 12 : 16,
                0,
              ),
              child: Align(
                alignment: isMobile ? Alignment.topCenter : Alignment.topRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, -10 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSuccess
                              ? const Color(0xFF4CB979)
                              : colorScheme.outlineVariant,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x30000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              width: 5,
                              decoration: BoxDecoration(
                                color: accentColor,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(12),
                                  bottomLeft: Radius.circular(12),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isError
                                        ? Icons.error_outline
                                        : (isSuccess
                                              ? Icons.check_circle_outline
                                              : Icons.info_outline),
                                    size: 17,
                                    color: accentColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      message,
                                      style: TextStyle(
                                        color: foregroundColor,
                                        fontWeight: FontWeight.w600,
                                        height: 1.25,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    _activeEntry = entry;
    overlay.insert(entry);

    _activeTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        entry.remove();
        _activeEntry = null;
      }
      _activeTimer = null;
    });
  }
}
