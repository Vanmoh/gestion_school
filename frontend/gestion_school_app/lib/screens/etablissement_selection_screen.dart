
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_selector.dart';

class RequireEtablissementSelection extends ConsumerWidget {
  final Widget child;
  const RequireEtablissementSelection({required this.child, Key? key}) : super(key: key);

  void _checkEtab(BuildContext context, WidgetRef ref) {
    final etabProvider = ref.read(etablissementProvider);
    if (etabProvider.selected == null && etabProvider.etablissements.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            child: SizedBox(
              height: 420,
              width: 340,
              child: EtablissementSelectionScreen(
                onSelected: (etab) {
                  etabProvider.selectEtablissement(etab);
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    _checkEtab(context, ref);
    return child;
  }
}

class EtablissementSelectionScreen extends ConsumerWidget {
  final void Function(Etablissement) onSelected;

  const EtablissementSelectionScreen({Key? key, required this.onSelected}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sélectionnez un établissement')),
      body: EtablissementSelector(onSelected: (etab) {
        onSelected(etab);
        Navigator.of(context).pop();
      }),
    );
  }
}
