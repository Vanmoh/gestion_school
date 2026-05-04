import 'dart:async';
import 'dart:ui';

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
    final maxWidth = isMobile ? media.width - 28 : 320.0;
    final topOffset = isDialogRoute ? (isMobile ? 14.0 : 18.0) : 10.0;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) {
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 16,
                topOffset,
                isMobile ? 14 : 16,
                0,
              ),
              child: Align(
                alignment: isMobile ? Alignment.topCenter : Alignment.topRight,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxWidth),
                  child: TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    tween: Tween<double>(begin: 0, end: 1),
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, -6 * (1 - value)),
                          child: child,
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSuccess
                                ? const Color(0xFF16653A).withValues(alpha: 0.94)
                                : backgroundColor.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSuccess
                                  ? const Color(0xFF5AC98A).withValues(alpha: 0.9)
                                  : colorScheme.outlineVariant.withValues(alpha: 0.9),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x22000000),
                                blurRadius: 8,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isError
                                        ? Icons.error_outline
                                        : (isSuccess
                                              ? Icons.check_rounded
                                              : Icons.info_outline),
                                    size: 12,
                                    color: accentColor,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    message,
                                    style: TextStyle(
                                      color: foregroundColor,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                      letterSpacing: 0.1,
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
