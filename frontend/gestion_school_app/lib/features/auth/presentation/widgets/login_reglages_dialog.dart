/// Les reglages techniques, ranges hors du chemin.
///
/// L'URL de l'API, le test de connexion et le changement d'etablissement
/// s'empilaient sous le bouton « Se connecter ». Ils restent entierement
/// accessibles, mais cessent d'etre la premiere chose qu'on lit en arrivant.
library;

import 'package:flutter/material.dart';

import '../../../../models/etablissement.dart';
import '../../../../widgets/etablissement_identity.dart';

/// Ce que l'utilisateur a decide dans le panneau.
enum LoginReglagesAction { aucune, changerEtablissement }

/// Resultat d'un test de joignabilite.
typedef ResultatTestApi = ({bool joignable, int? code});

class LoginReglagesDialog extends StatefulWidget {
  final Etablissement etablissement;
  final String urlApi;

  /// Enregistre l'URL et rend celle qui est retenue, ou null si elle est
  /// invalide.
  final Future<String?> Function(String saisie) onEnregistrer;

  /// Le test rend son verdict au lieu de l'afficher lui-meme: sous un
  /// dialogue modal, une SnackBar s'affiche derriere le voile, et le
  /// resultat devenait invisible a l'instant precis ou on le demandait.
  final Future<ResultatTestApi> Function() onTester;

  const LoginReglagesDialog({
    super.key,
    required this.etablissement,
    required this.urlApi,
    required this.onEnregistrer,
    required this.onTester,
  });

  @override
  State<LoginReglagesDialog> createState() => _LoginReglagesDialogState();
}

class _LoginReglagesDialogState extends State<LoginReglagesDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.urlApi,
  );
  bool _testEnCours = false;
  String? _resultatTest;
  bool _testReussi = false;
  String? _erreurSaisie;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _tester() async {
    setState(() {
      _testEnCours = true;
      _resultatTest = null;
    });
    final resultat = await widget.onTester();
    if (!mounted) return;
    setState(() {
      _testEnCours = false;
      _testReussi = resultat.joignable;
      _resultatTest = resultat.joignable
          ? 'Serveur joignable (code ${resultat.code}).'
          : 'Serveur injoignable à cette adresse.';
    });
  }

  Future<void> _enregistrer() async {
    final retenue = await widget.onEnregistrer(_controller.text);
    if (!mounted) return;
    if (retenue == null) {
      setState(
        () => _erreurSaisie =
            'Adresse invalide. Exemple: http://192.168.1.10:8000/api',
      );
      return;
    }
    Navigator.of(context).pop(LoginReglagesAction.aucune);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      icon: const Icon(Icons.tune_rounded),
      title: const Text('Réglages techniques'),
      content: ConstrainedBox(
        // Remplace une largeur fixe de 540: sans effet sous 620 px de large,
        // et arbitraire au-dela.
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EtabSectionLabel('Serveur'),
              TextField(
                controller: _controller,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Adresse de l\'API',
                  hintText: 'http://IP_DU_PC:8000/api',
                  errorText: _erreurSaisie,
                ),
                onChanged: (_) {
                  if (_erreurSaisie != null) {
                    setState(() => _erreurSaisie = null);
                  }
                },
              ),
              const SizedBox(height: 10),
              // Pleine largeur plutot qu'un Row: le libelle et son icone
              // debordaient de 102 px sur un telephone de 360 px, le Row ne
              // contraignant pas son unique enfant.
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _testEnCours ? null : _tester,
                  icon: _testEnCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find_rounded),
                  label: const Text('Tester la connexion'),
                ),
              ),
              if (_resultatTest != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _testReussi
                          ? Icons.check_circle_outline
                          : Icons.error_outline,
                      size: 16,
                      color: _testReussi
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _resultatTest!,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
              const EtabSectionLabel('Établissement'),
              EtabContactLine(
                icon: Icons.apartment_rounded,
                value: etabDisplayName(widget.etablissement),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop(LoginReglagesAction.changerEtablissement),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Changer d\'établissement'),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(LoginReglagesAction.aucune),
          child: const Text('Fermer'),
        ),
        FilledButton(onPressed: _enregistrer, child: const Text('Enregistrer')),
      ],
    );
  }
}
