import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/personnalisation.dart';
import 'personnalisation_controller.dart';

/// L'écran qui donne son identité à l'application.
///
/// Le nom, le logo, les coordonnées et les libellés des écrans publics
/// vivaient en dur dans le code : servir une autre école demandait de
/// recompiler. Tout se règle désormais ici, et le seul super admin y accède —
/// ces réglages engagent l'application entière, tous établissements
/// confondus.
class PersonnalisationPage extends ConsumerStatefulWidget {
  const PersonnalisationPage({super.key});

  /// Ouvre l'écran en fenêtre. Rendue depuis le bouton de la barre du haut.
  static Future<void> ouvrir(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(16),
        child: SizedBox(width: 760, child: PersonnalisationPage()),
      ),
    );
  }

  @override
  ConsumerState<PersonnalisationPage> createState() =>
      _PersonnalisationPageState();
}

class _PersonnalisationPageState extends ConsumerState<PersonnalisationPage> {
  final _formKey = GlobalKey<FormState>();

  final _nomApplication = TextEditingController();
  final _nomEcole = TextEditingController();
  final _sigle = TextEditingController();
  final _telephone = TextEditingController();
  final _email = TextEditingController();
  final _adresse = TextEditingController();
  final _titreConnexion = TextEditingController();
  final _sousTitreConnexion = TextEditingController();
  final _titrePortail = TextEditingController();
  final _sousTitrePortail = TextEditingController();
  final _messageAccueil = TextEditingController();
  final _piedDePage = TextEditingController();
  final _couleur = TextEditingController();

  /// Le logo choisi, pas encore envoyé. Nul tant qu'on n'en change pas :
  /// modifier un numéro de téléphone ne doit pas effacer l'image en place.
  Uint8List? _logoChoisi;

  /// L'image de fond choisie, pas encore envoyée.
  Uint8List? _fondChoisi;
  String? _nomDuFond;
  String? _nomDuLogo;

  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _remplirDepuis(ref.read(personnalisationProvider).valeur);
    // Un rechargement forcé à l'ouverture: l'identité peut avoir été changée
    // depuis un autre poste, et écraser ces valeurs-là sans les avoir vues
    // ferait perdre le travail de quelqu'un d'autre.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(personnalisationProvider).charger(forcer: true);
      if (mounted) {
        _remplirDepuis(ref.read(personnalisationProvider).valeur);
      }
    });
  }

  void _remplirDepuis(Personnalisation p) {
    _nomApplication.text = p.nomApplication;
    _nomEcole.text = p.nomEcole;
    _sigle.text = p.sigle;
    _telephone.text = p.telephone;
    _email.text = p.email;
    _adresse.text = p.adresse;
    _titreConnexion.text = p.titreConnexion;
    _sousTitreConnexion.text = p.sousTitreConnexion;
    _titrePortail.text = p.titrePortail;
    _sousTitrePortail.text = p.sousTitrePortail;
    _messageAccueil.text = p.messageAccueil;
    _piedDePage.text = p.piedDePage;
    _couleur.text = p.couleurPrincipale;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [
      _nomApplication,
      _nomEcole,
      _sigle,
      _telephone,
      _email,
      _adresse,
      _titreConnexion,
      _sousTitreConnexion,
      _titrePortail,
      _sousTitrePortail,
      _messageAccueil,
      _piedDePage,
      _couleur,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _choisirLeLogo() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (choix == null || choix.files.isEmpty) return;

    final fichier = choix.files.first;
    final octets = fichier.bytes;
    if (octets == null || octets.isEmpty) {
      _dire('Fichier illisible.');
      return;
    }
    // Deux mégaoctets: un logo est une image de quelques centaines de pixels,
    // au-delà c'est une photo qu'on chargerait à chaque écran de connexion.
    if (octets.length > 2 * 1024 * 1024) {
      _dire('Logo trop lourd : 2 Mo au maximum.');
      return;
    }

    setState(() {
      _logoChoisi = octets;
      _nomDuLogo = fichier.name;
    });
  }

  Future<void> _choisirLImageDeFond() async {
    final choix = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      withData: true,
    );
    if (choix == null || choix.files.isEmpty) return;

    final fichier = choix.files.first;
    final octets = fichier.bytes;
    if (octets == null || octets.isEmpty) {
      _dire('Fichier illisible.');
      return;
    }
    // Six mégaoctets, contre deux pour le logo: c'est une photo pleine page,
    // pas une vignette. Au-delà, chaque ouverture du portail la retélécharge
    // -- le serveur d'école répond `no-store` -- et l'écran met une seconde
    // de trop à s'habiller.
    if (octets.length > 6 * 1024 * 1024) {
      _dire('Image trop lourde : 6 Mo au maximum.');
      return;
    }

    setState(() {
      _fondChoisi = octets;
      _nomDuFond = fichier.name;
    });
  }

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enregistrement = true);
    try {
      await ref
          .read(personnalisationProvider)
          .enregistrer(
            <String, dynamic>{
              'nom_application': _nomApplication.text.trim(),
              'nom_ecole': _nomEcole.text.trim(),
              'sigle': _sigle.text.trim(),
              'telephone': _telephone.text.trim(),
              'email': _email.text.trim(),
              'adresse': _adresse.text.trim(),
              'titre_connexion': _titreConnexion.text.trim(),
              'sous_titre_connexion': _sousTitreConnexion.text.trim(),
              'titre_portail': _titrePortail.text.trim(),
              'sous_titre_portail': _sousTitrePortail.text.trim(),
              'message_accueil': _messageAccueil.text.trim(),
              'pied_de_page': _piedDePage.text.trim(),
              'couleur_principale': _couleur.text.trim(),
            },
            logo: _logoChoisi,
            nomDuLogo: _nomDuLogo,
            imageFond: _fondChoisi,
            nomDeLImageFond: _nomDuFond,
          );
      if (!mounted) return;
      setState(() {
        _logoChoisi = null;
        _nomDuLogo = null;
        _fondChoisi = null;
        _nomDuFond = null;
      });
      _dire('Personnalisation enregistrée.', succes: true);
    } on DioException catch (erreur) {
      if (!mounted) return;
      _dire(_detail(erreur));
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  /// Le motif du refus tel que le serveur le formule : « attendu une couleur
  /// au format #RRGGBB » vaut mieux qu'un code d'erreur.
  String _detail(DioException erreur) {
    final donnees = erreur.response?.data;
    if (donnees is Map) {
      if (donnees['detail'] != null) return donnees['detail'].toString();
      final premier = donnees.values.firstOrNull;
      if (premier is List && premier.isNotEmpty) {
        return premier.first.toString();
      }
      if (premier != null) return premier.toString();
    }
    return 'Enregistrement impossible.';
  }

  void _dire(String texte, {bool succes = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(texte),
          backgroundColor: succes
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.error,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final personnalisation = ref.watch(personnalisationProvider).valeur;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 6),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personnalisation',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Le nom, le logo et les libellés que voient vos '
                      'utilisateurs, sur tous les établissements.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Fermer',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _section(context, 'Identité'),
                  _logo(context, personnalisation),
                  const SizedBox(height: 18),
                  _imageDeFond(context, personnalisation),
                  const SizedBox(height: 12),
                  _paire(
                    _champ(
                      _nomApplication,
                      'Nom de l’application',
                      aide: 'Titre de l’onglet du navigateur.',
                      obligatoire: true,
                    ),
                    _champ(
                      _sigle,
                      'Sigle',
                      aide: 'Abrégé, quand la place manque.',
                    ),
                  ),
                  _champ(
                    _nomEcole,
                    'Nom de l’école',
                    aide: 'Affiché sur l’écran de connexion.',
                  ),

                  _section(context, 'Coordonnées'),
                  _paire(
                    _champ(_telephone, 'Téléphone'),
                    _champ(_email, 'E-mail'),
                  ),
                  _champ(_adresse, 'Adresse'),

                  _section(context, 'Écran de connexion'),
                  _champ(
                    _titreConnexion,
                    'Titre',
                    aide: 'Vide, l’écran garde sa formulation actuelle.',
                  ),
                  _champ(_sousTitreConnexion, 'Sous-titre'),

                  _section(context, 'Portail de choix d’établissement'),
                  _champ(
                    _titrePortail,
                    'Titre',
                    aide:
                        'Vide, l’écran garde « Choisissez votre établissement ».',
                  ),
                  _champ(_sousTitrePortail, 'Sous-titre'),
                  _champ(_messageAccueil, 'Message d’accueil', lignes: 2),

                  _section(context, 'Partout'),
                  _champ(_piedDePage, 'Pied de page', lignes: 2),
                  _couleurPrincipale(context),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _enregistrement
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('enregistrer-personnalisation'),
                onPressed: _enregistrement ? null : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(BuildContext context, String titre) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        titre,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _logo(BuildContext context, Personnalisation p) {
    final scheme = Theme.of(context).colorScheme;
    final apercuLogo = _logoChoisi;

    return Row(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
            color: scheme.surfaceContainerHighest,
          ),
          clipBehavior: Clip.antiAlias,
          child: apercuLogo != null
              ? Image.memory(apercuLogo, fit: BoxFit.contain)
              : (p.logoUrl.isNotEmpty
                    ? Image.network(
                        p.logoUrl,
                        fit: BoxFit.contain,
                        // Un logo introuvable ne doit pas casser l'écran de
                        // réglages: c'est justement là qu'on vient le corriger.
                        errorBuilder: (_, _, _) => Icon(
                          Icons.image_not_supported_outlined,
                          color: scheme.outline,
                        ),
                      )
                    : Icon(Icons.school_outlined, color: scheme.outline)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                key: const Key('choisir-logo'),
                onPressed: _enregistrement ? null : _choisirLeLogo,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(apercuLogo == null ? 'Choisir un logo' : 'Changer'),
              ),
              const SizedBox(height: 4),
              Text(
                apercuLogo == null
                    ? 'PNG ou JPEG, 2 Mo au maximum.'
                    : 'Nouveau logo prêt : ${_nomDuLogo ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// L'image de fond des écrans publics.
  ///
  /// Aperçu large et non carré comme celui du logo : c'est une photo qu'on
  /// juge à son cadrage, et un carré ne dirait rien de ce qu'on verra.
  Widget _imageDeFond(BuildContext context, Personnalisation p) {
    final scheme = Theme.of(context).colorScheme;
    final apercu = _fondChoisi;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 5,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
              color: scheme.surfaceContainerHighest,
            ),
            clipBehavior: Clip.antiAlias,
            child: apercu != null
                ? Image.memory(apercu, fit: BoxFit.cover)
                : (p.imageFondUrl.isNotEmpty
                      ? Image.network(
                          p.imageFondUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_not_supported_outlined,
                            color: scheme.outline,
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.photo_size_select_actual_outlined,
                            color: scheme.outline,
                          ),
                        )),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              key: const Key('choisir-image-fond'),
              onPressed: _enregistrement ? null : _choisirLImageDeFond,
              icon: const Icon(Icons.wallpaper_outlined, size: 18),
              label: Text(
                apercu == null ? 'Choisir une image de fond' : 'Changer',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                apercu == null
                    ? 'Portail et connexion, sous un voile sombre. Large '
                          'plutôt que haute, 1600 px au minimum, 6 Mo au plus.'
                    : 'Nouvelle image prête : ${_nomDuFond ?? ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _couleurPrincipale(BuildContext context) {
    final saisie = _couleur.text.trim();
    final apercu = Personnalisation(couleurPrincipale: saisie).couleur;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _champ(
            _couleur,
            'Couleur principale',
            aide: 'Format #RRGGBB. L’application reste en thème sombre.',
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: apercu,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _paire(Widget gauche, Widget droite) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        if (contraintes.maxWidth < 520) {
          return Column(children: [gauche, droite]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: gauche),
            const SizedBox(width: 12),
            Expanded(child: droite),
          ],
        );
      },
    );
  }

  Widget _champ(
    TextEditingController controleur,
    String etiquette, {
    String? aide,
    int lignes = 1,
    bool obligatoire = false,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controleur,
        maxLines: lignes,
        onChanged: onChanged,
        validator: obligatoire
            ? (valeur) => (valeur ?? '').trim().isEmpty
                  ? 'Ce champ ne peut pas rester vide.'
                  : null
            : null,
        decoration: InputDecoration(
          labelText: etiquette,
          helperText: aide,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
