import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'academic_imports_page.dart';

Future<void> showAcademicImportsFloatingWindow(BuildContext context) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    builder: (dialogContext) {
      final media = MediaQuery.of(dialogContext).size;
      final width = math.min(media.width - 24, 1260.0);
      final height = math.min(media.height - 24, 860.0);

      return Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height,
          child: const AcademicImportsPage(),
        ),
      );
    },
  );
}

class AcademicImportsFloatingRoutePage extends StatelessWidget {
  const AcademicImportsFloatingRoutePage({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context).size;
    final width = math.min(media.width - 24, 1260.0);
    final height = math.min(media.height - 24, 860.0);

    return Scaffold(
      backgroundColor: Colors.black54,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: width,
              maxHeight: height,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: const AcademicImportsPage(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
