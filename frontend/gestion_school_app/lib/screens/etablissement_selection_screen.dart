
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/etablissement_api.dart';
import '../core/network/api_client.dart';
import '../models/etablissement.dart';
import '../widgets/etablissement_selector.dart';

class RequireEtablissementSelection extends ConsumerStatefulWidget {
  final Widget child;
  const RequireEtablissementSelection({required this.child, Key? key}) : super(key: key);

  @override
  ConsumerState<RequireEtablissementSelection> createState() =>
      _RequireEtablissementSelectionState();
}

class _RequireEtablissementSelectionState
    extends ConsumerState<RequireEtablissementSelection> {
  bool _dialogOpen = false;
  bool _loadingEtablissements = false;
  bool _didTryLoad = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEtab();
    });
  }

  Future<void> _loadEtablissementsIfNeeded() async {
    final etabProvider = ref.read(etablissementProvider);
    if (_loadingEtablissements || _didTryLoad || etabProvider.etablissements.isNotEmpty) {
      return;
    }

    _didTryLoad = true;
    _loadingEtablissements = true;
    try {
      final response = await ref.read(dioProvider).get(EtablissementApi.etablissements);
      final data = (response.data as List<dynamic>)
          .map((e) => Etablissement.fromJson(e as Map<String, dynamic>))
          .toList();
      etabProvider.setEtablissements(data);
    } catch (_) {
      // Keep navigation usable even if API is temporarily unavailable.
    } finally {
      _loadingEtablissements = false;
    }
  }

  Future<void> _checkEtab() async {
    if (!mounted) {
      return;
    }

    await _loadEtablissementsIfNeeded();

    if (!mounted) {
      return;
    }

    final etabProvider = ref.read(etablissementProvider);
    if (_dialogOpen) {
      return;
    }

    if (etabProvider.selected == null && etabProvider.etablissements.isNotEmpty) {
      _dialogOpen = true;
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
      _dialogOpen = false;

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _checkEtab();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(etablissementProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkEtab();
    });
    return widget.child;
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
      }),
    );
  }
}
