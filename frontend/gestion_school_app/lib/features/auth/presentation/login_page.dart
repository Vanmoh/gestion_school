import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';
import '../../../widgets/etablissement_identity.dart';
import '../../../widgets/fond_ecran_public.dart';
import '../../personnalisation/domain/personnalisation.dart';
import '../../personnalisation/presentation/personnalisation_controller.dart';
import '../domain/auth_user.dart';
import 'auth_controller.dart';
import 'widgets/login_brand_panel.dart';
import 'widgets/login_form_card.dart';
import 'widgets/login_mot_de_passe_dialog.dart';
import 'widgets/login_reglages_dialog.dart';

/// Deux colonnes a partir de cette largeur. Seuil inchange: c'est celui que
/// le test de mise en page eprouve depuis le debordement de 2026-08.
const double _kDeuxColonnes = 980;

/// Fenetre courte: le logo cede la place au texte plutot que l'inverse.
const double _kHauteurCourte = 700;

/// La carte ne s'etire pas: au-dela, une ligne de saisie devient penible a
/// suivre de l'oeil.
const double _kLargeurCarte = 460;

/// Largeur maximale de l'ensemble marque + carte.
///
/// Sans elle, sur un ecran de 1920 la marque restait collee au bord gauche et
/// un gouffre la separait de la carte, a droite: deux ilots aux extremites
/// d'un vide. Le contenu se centre desormais, comme au portail.
const double _kLargeurContenu = 1240;

/// Ou poser le message produit par [_LoginPageState._friendlyErrorMessage].
enum _ChampEnErreur { identifiant, motDePasse, aucun }

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _obscurePassword = true;
  bool _wrongScopeDialogOpen = false;
  String _activeApiUrl = ApiConstants.baseUrl;

  /// Messages du serveur, ranges sous le champ qu'ils concernent.
  String? _erreurIdentifiant;
  String? _erreurMotDePasse;
  String? _erreurGenerale;
  bool _erreurReseau = false;

  /// Fondu de sortie, joue juste avant de quitter l'ecran.
  ///
  /// La bascule vers le tableau de bord etait seche: la page disparaissait
  /// d'un coup, sur une machine d'ecole qui met parfois une seconde a dessiner
  /// l'ecran suivant. Un fondu court adoucit la couture sans faire attendre.
  bool _sortie = false;

  /// Position du curseur, pour que l'eclairage du fond le suive.
  ///
  /// Nulle tant que la souris n'a pas bouge -- et pour toujours au doigt, ou
  /// il n'y a pas de curseur a suivre.
  Alignment? _curseur;

  @override
  void initState() {
    super.initState();
    _loadActiveApiUrl();
    Future.microtask(() => ref.read(etablissementProvider).hydrate());
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).restoreSession(),
    );
    // `app.dart` place ce chargement sur les deux ecrans qui portent la marque
    // -- le portail et la connexion -- mais la connexion ne l'avait jamais
    // fait: le telephone et le courriel de l'ecole y etaient donc vides, ce
    // que le panneau « mot de passe oublie » ne peut plus se permettre.
    Future.microtask(() => ref.read(personnalisationProvider).charger());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final etablissementState = ref.watch(etablissementProvider);
    final selectedEtablissement = etablissementState.selected;

    // L'identite reglee par l'ecole remplace les constantes qui vivaient dans
    // le code: le nom, le logo et le telephone y etaient figes a la
    // compilation, et servir une autre ecole demandait de recompiler.
    final marque = ref.watch(personnalisationProvider).valeur;

    ref.listen(authControllerProvider, (previous, next) async {
      next.whenOrNull(
        data: (user) async {
          if (user != null && mounted) {
            final selectedEtablissementId = selectedEtablissement?.id;
            final userEtablissementId = user.etablissementId;
            final wrongScopedLogin =
                user.role != 'super_admin' &&
                selectedEtablissementId != null &&
                userEtablissementId != null &&
                selectedEtablissementId != userEtablissementId;

            if (wrongScopedLogin) {
              // On ne propose pas d'enregistrer un identifiant qu'on vient de
              // refuser.
              TextInput.finishAutofillContext(shouldSave: false);
              await ref.read(authControllerProvider.notifier).logout();
              if (!mounted) {
                return;
              }
              _passwordController.clear();
              if (_wrongScopeDialogOpen) {
                return;
              }
              _wrongScopeDialogOpen = true;
              try {
                await _showWrongScopedLoginDialog(user);
              } finally {
                _wrongScopeDialogOpen = false;
              }
              return;
            }
            // Sans cet appel, le groupe de remplissage reste ouvert et ni le
            // navigateur ni Android ne proposent jamais d'enregistrer le mot
            // de passe: le gestionnaire attend la fin du formulaire, pas la
            // navigation.
            TextInput.finishAutofillContext();
            // Le navigateur est saisi avant l'attente: s'en servir apres
            // reviendrait a traverser le contexte d'un ecran peut-etre demonte.
            final navigateur = Navigator.of(context);
            final immobile = etabReduceMotion(context);
            setState(() => _sortie = true);
            if (!immobile) {
              await Future<void>.delayed(const Duration(milliseconds: 220));
            }
            if (!mounted) return;
            navigateur.pushReplacementNamed(user.homeRoute);
          }
        },
        error: (error, _) => _reporterErreur(error),
      );
    });

    if (!etablissementState.hydrated) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (selectedEtablissement == null) {
      return _EcranSansEtablissement();
    }

    return Scaffold(
      body: AnimatedOpacity(
        opacity: _sortie ? 0 : 1,
        duration: etabReduceMotion(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: MouseRegion(
          onHover: (evenement) {
            final taille = MediaQuery.sizeOf(context);
            if (taille.isEmpty) return;
            setState(() {
              _curseur = Alignment(
                (evenement.position.dx / taille.width) * 2 - 1,
                (evenement.position.dy / taille.height) * 2 - 1,
              );
            });
          },
          onExit: (_) => setState(() => _curseur = null),
          child: Stack(
            children: [
              // Le fond prolonge celui du portail -- memes halos, teintes par
              // l'etablissement -- et y ajoute la profondeur qui manquait sur un
              // grand ecran. Il fige son mouvement quand le systeme demande moins
              // d'animations.
              Positioned.fill(
                child: FondEcranPublic(
                  tints: etabRamp(selectedEtablissement),
                  // La photo de l'ecole d'abord, celle de la plateforme ensuite:
                  // on est ici chez un etablissement precis, et sa facade parle
                  // mieux que l'image commune.
                  photoUrl:
                      (selectedEtablissement.coverUrlForDisplay ?? '')
                          .isNotEmpty
                      ? selectedEtablissement.coverUrlForDisplay
                      : marque.imageFondUrl,
                  // Sur grand ecran la photo tient la moitie gauche, celle de la
                  // marque, et laisse la carte sur le fond sombre: du texte de
                  // saisie pose sur une photo se lit mal, meme voilee.
                  largeurPhoto:
                      MediaQuery.sizeOf(context).width >= _kDeuxColonnes
                      ? 0.62
                      : 1,
                  curseur: _curseur,
                  ancrageLueur:
                      MediaQuery.sizeOf(context).width >= _kDeuxColonnes
                      ? const Alignment(0.55, 0)
                      : Alignment.center,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final deuxColonnes =
                              constraints.maxWidth >= _kDeuxColonnes;
                          final dense = constraints.maxHeight < _kHauteurCourte;

                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              deuxColonnes ? 40 : 24,
                              24,
                              deuxColonnes ? 40 : 24,
                              12,
                            ),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: _kLargeurContenu,
                                ),
                                child: deuxColonnes
                                    ? _deuxColonnes(
                                        etablissement: selectedEtablissement,
                                        marque: marque,
                                        authState: authState,
                                        dense: dense,
                                      )
                                    : _uneColonne(
                                        etablissement: selectedEtablissement,
                                        marque: marque,
                                        authState: authState,
                                      ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const EtabSecureFooter(),
                  ],
                ),
              ),
              // Sur grand ecran le bouton vit dans le coin; en colonne unique il
              // rejoint l'en-tete de marque, sans quoi il chevaucherait la carte
              // sur un telephone etroit.
              if (MediaQuery.sizeOf(context).width >= _kDeuxColonnes)
                Positioned(
                  top: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: _boutonReglages(selectedEtablissement),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deuxColonnes({
    required Etablissement etablissement,
    required Personnalisation marque,
    required AsyncValue<AuthUser?> authState,
    required bool dense,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `Expanded` pour la marque et largeur fixe pour la carte: deux
        // `Expanded` donnaient 50/50, et la carte plafonnee a 460 laissait un
        // vide fantome a sa droite.
        Expanded(
          child: _CentreDefilant(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            child: LoginBrandPanel(
              etablissement: etablissement,
              logoDeMarque: marque.logoUrl,
              titre: marque.titreConnexion,
              sousTitre: marque.sousTitreConnexion,
              contact: _contactCourt(etablissement, marque),
              dense: dense,
            ),
          ),
        ),
        const SizedBox(width: 40),
        SizedBox(
          width: _kLargeurCarte,
          child: _CentreDefilant(
            child: _carte(
              etablissement,
              marque,
              authState,
              autofocus: true,
              avecIdentite: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _uneColonne({
    required Etablissement etablissement,
    required Personnalisation marque,
    required AsyncValue<AuthUser?> authState,
  }) {
    return _CentreDefilant(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _kLargeurCarte),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LoginBrandHeader(
              etablissement: etablissement,
              action: _boutonReglages(etablissement),
            ),
            const SizedBox(height: 18),
            _carte(
              etablissement,
              marque,
              authState,
              autofocus: false,
              // L'en-tete de marque, juste au-dessus, porte deja l'identite.
              avecIdentite: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _carte(
    Etablissement etablissement,
    Personnalisation marque,
    AsyncValue<AuthUser?> authState, {
    required bool autofocus,
    required bool avecIdentite,
  }) {
    // Une entree en opacite et en echelle, jamais en taille: le test de mise
    // en page echantillonne l'ecran a 100 ms, donc en pleine animation. Une
    // hauteur animee y serait mesuree a mi-course et pourrait deborder.
    final immobile = etabReduceMotion(context);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: immobile ? Duration.zero : const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, valeur, child) {
        return Opacity(
          opacity: valeur.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 14 * (1 - valeur)),
            child: child,
          ),
        );
      },
      child: LoginFormCard(
        formKey: _formKey,
        etablissement: etablissement,
        identifiantController: _usernameController,
        motDePasseController: _passwordController,
        identifiantFocus: _usernameFocus,
        motDePasseFocus: _passwordFocus,
        motDePasseMasque: _obscurePassword,
        onBasculerVisibilite: () =>
            setState(() => _obscurePassword = !_obscurePassword),
        enCours: authState.isLoading,
        onSoumettre: () => _submitLogin(authState.isLoading),
        onMotDePasseOublie: () =>
            _ouvrirMotDePasseOublie(etablissement, marque),
        erreurIdentifiant: () => _erreurIdentifiant,
        erreurMotDePasse: () => _erreurMotDePasse,
        erreurGenerale: _erreurGenerale,
        erreurReseau: _erreurReseau,
        urlApi: _activeApiUrl,
        onOuvrirReglages: () => _ouvrirReglages(etablissement),
        autofocus: autofocus,
        avecIdentite: avecIdentite,
        onIdentifiantModifie: (_) {
          if (_erreurIdentifiant != null) {
            setState(() => _erreurIdentifiant = null);
          }
        },
        onMotDePasseModifie: (_) {
          if (_erreurMotDePasse != null) {
            setState(() => _erreurMotDePasse = null);
          }
        },
      ),
    );
  }

  Widget _boutonReglages(Etablissement etablissement) {
    return IconButton(
      tooltip: 'Réglages techniques',
      onPressed: () => _ouvrirReglages(etablissement),
      icon: const Icon(Icons.tune_rounded),
    );
  }

  /// Le telephone de l'ecole, pret a etre affiche en pastille.
  String? _contactCourt(Etablissement etablissement, Personnalisation marque) {
    final numero = _telephoneRetenu(etablissement, marque);
    return numero == null ? null : 'Tél: $numero';
  }

  /// L'etablissement d'abord, la personnalisation ensuite. Rien apres.
  ///
  /// Pas de repli sur le numero livre avec l'application: c'est celui de
  /// l'ecole d'origine, et l'afficher a une autre enverrait ses parents
  /// appeler un etablissement qui ne les connait pas. Mieux vaut avouer qu'on
  /// ne connait pas le contact.
  String? _telephoneRetenu(
    Etablissement etablissement,
    Personnalisation marque,
  ) {
    final propre = (etablissement.phone ?? '').trim();
    if (propre.isNotEmpty) return propre;
    return marque.telephone.trim().isEmpty ? null : marque.telephone.trim();
  }

  String? _emailRetenu(Etablissement etablissement, Personnalisation marque) {
    final propre = (etablissement.email ?? '').trim();
    if (propre.isNotEmpty) return propre;
    return marque.email.trim().isEmpty ? null : marque.email.trim();
  }

  Future<void> _ouvrirMotDePasseOublie(
    Etablissement etablissement,
    Personnalisation marque,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => LoginMotDePasseOublieDialog(
        etablissement: etablissement,
        telephone: _telephoneRetenu(etablissement, marque),
        email: _emailRetenu(etablissement, marque),
      ),
    );
  }

  Future<void> _ouvrirReglages(Etablissement etablissement) async {
    final tokenStorage = ref.read(tokenStorageProvider);

    final action = await showDialog<LoginReglagesAction>(
      context: context,
      builder: (_) => LoginReglagesDialog(
        etablissement: etablissement,
        urlApi: _activeApiUrl,
        onEnregistrer: (saisie) async {
          final normalisee = _normalizeApiBaseUrl(saisie);
          if (normalisee == null) return null;
          await tokenStorage.saveApiBaseUrl(normalisee);
          await _loadActiveApiUrl();
          return normalisee;
        },
        onTester: _testApiConnection,
      ),
    );

    if (!mounted) return;
    // Depiler le dialogue avant de naviguer: l'inverse laisse une route
    // orpheline au-dessus du nouvel ecran.
    if (action == LoginReglagesAction.changerEtablissement) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  void _submitLogin(bool loading) {
    if (loading) {
      return;
    }
    FocusScope.of(context).unfocus();

    // Les messages du serveur sont effaces AVANT la validation. Sans cela, les
    // validators les retournent encore: un utilisateur qui reessaie sans rien
    // retaper -- le serveur etait tombe, il est revenu -- verrait la
    // validation echouer et aucune requete ne partirait. Le formulaire
    // resterait bloque par un message qui ne decrit plus rien.
    setState(() {
      _erreurIdentifiant = null;
      _erreurMotDePasse = null;
      _erreurGenerale = null;
      _erreurReseau = false;
    });

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    ref
        .read(authControllerProvider.notifier)
        .login(_usernameController.text.trim(), _passwordController.text);
  }

  /// Ou poser le message d'erreur.
  ///
  /// 400 et 401 ne distinguent pas le nom du mot de passe -- le serveur repond
  /// la meme chose dans les deux cas. Repeter la phrase sous les deux champs
  /// serait du bruit: on la pose sous le mot de passe, le seul des deux qu'on
  /// retape en pratique. Un refus de compte, une panne serveur ou un delai
  /// depasse ne concernent aucun champ: ils vont dans le bandeau.
  _ChampEnErreur _champConcerne(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;
      if (status == 400 || status == 401) {
        return _ChampEnErreur.motDePasse;
      }
    }
    return _ChampEnErreur.aucun;
  }

  void _reporterErreur(Object error) {
    if (!mounted) return;
    final message = _friendlyErrorMessage(error);
    final champ = _champConcerne(error);

    setState(() {
      switch (champ) {
        case _ChampEnErreur.motDePasse:
          _erreurMotDePasse = message;
        case _ChampEnErreur.identifiant:
          _erreurIdentifiant = message;
        case _ChampEnErreur.aucun:
          _erreurGenerale = message;
      }
      _erreurReseau =
          error is DioException &&
          error.type == DioExceptionType.connectionError;
    });

    // Rejoue les validators pour que le champ montre le message a l'instant,
    // sans attendre une frappe.
    _formKey.currentState?.validate();
    if (champ == _ChampEnErreur.motDePasse) {
      _passwordController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _passwordController.text.length,
      );
      _passwordFocus.requestFocus();
    }
  }

  String _userEtablissementLabel(AuthUser user) {
    final name = user.etablissementName.trim();
    if (name.isNotEmpty) {
      return name;
    }
    final id = user.etablissementId;
    if (id != null) {
      return 'Établissement #$id';
    }
    return 'l\'établissement associé à ce compte';
  }

  Future<void> _showWrongScopedLoginDialog(AuthUser user) async {
    if (!mounted) {
      return;
    }

    final targetLabel = _userEtablissementLabel(user);
    final scheme = Theme.of(context).colorScheme;
    final targetId = user.etablissementId;

    Future<void> chooseTargetEtablissement(BuildContext dialogContext) async {
      final provider = ref.read(etablissementProvider);
      if (targetId == null) {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        _showMessage(
          'Impossible d\'identifier automatiquement l\'établissement du compte.',
        );
        return;
      }

      Etablissement? target;
      for (final item in provider.etablissements) {
        if (item.id == targetId) {
          target = item;
          break;
        }
      }
      if (target == null) {
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
        return;
      }

      await provider.selectEtablissement(target);
      if (dialogContext.mounted) {
        Navigator.of(dialogContext).pop();
      }
      _showMessage(
        'Établissement "$targetLabel" sélectionné. Reconnectez-vous pour continuer.',
        isSuccess: true,
      );
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  // Les deux couleurs posees ici etaient claires et ecrites en
                  // dur (un beige et un brun): sur le theme sombre elles
                  // formaient une tache, et elles ignoraient l'accent de
                  // l'ecole.
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.account_balance_rounded,
                  color: scheme.onErrorContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Établissement incorrect',
                  style: Theme.of(
                    dialogContext,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ce compte est rattaché à cet établissement :',
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  targetLabel,
                  style: Theme.of(dialogContext).textTheme.titleMedium
                      ?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Sélectionnez le bon établissement avant de vous reconnecter.',
                style: Theme.of(dialogContext).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Fermer'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
              icon: const Icon(Icons.swap_horiz_rounded),
              label: const Text('Changer d\'établissement'),
            ),
            FilledButton.icon(
              onPressed: () => chooseTargetEtablissement(dialogContext),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Choisir cet établissement'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadActiveApiUrl() async {
    final tokenStorage = ref.read(tokenStorageProvider);
    final storedBaseUrl = await tokenStorage.apiBaseUrl();
    if (!mounted) {
      return;
    }
    setState(() {
      _activeApiUrl = (storedBaseUrl != null && storedBaseUrl.isNotEmpty)
          ? storedBaseUrl
          : ApiConstants.baseUrl;
    });
  }

  void _showMessage(String message, {bool isSuccess = false}) {
    if (!mounted) return;

    final scheme = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? scheme.tertiaryContainer : null,
          content: Text(
            message,
            style: isSuccess
                ? TextStyle(color: scheme.onTertiaryContainer)
                : null,
          ),
        ),
      );
  }

  /// Le test rend son verdict au lieu de l'afficher: il est demande depuis un
  /// dialogue modal, sous lequel une SnackBar passerait derriere le voile.
  Future<ResultatTestApi> _testApiConnection() async {
    final dio = ref.read(dioProvider);
    try {
      final response = await dio.get(
        ApiConstants.login,
        options: Options(validateStatus: (_) => true),
      );
      final status = response.statusCode ?? 0;
      return (joignable: status > 0, code: status > 0 ? status : null);
    } on DioException catch (_) {
      return (joignable: false, code: null);
    }
  }

  String? _normalizeApiBaseUrl(String input) {
    var value = input.trim();
    if (value.isEmpty) {
      return null;
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }

    final uri = Uri.tryParse(value);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    var path = uri.path;
    if (path.isEmpty || path == '/') {
      path = '/api';
    }

    if (!path.endsWith('/api')) {
      path = path.endsWith('/') ? '${path}api' : '$path/api';
    }

    final authority = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    return '${uri.scheme}://$authority$path';
  }

  String _friendlyErrorMessage(Object error) {
    if (error is DioException) {
      final status = error.response?.statusCode;

      if (status == 400 || status == 401) {
        return 'Identifiants invalides. Vérifiez le nom utilisateur et le mot de passe.';
      }
      if (status == 403) {
        return 'Accès refusé. Votre compte n\'est pas autorisé à se connecter.';
      }
      if (status != null && status >= 500) {
        return 'Erreur serveur. Réessayez dans quelques instants.';
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Délai dépassé. Vérifiez votre connexion réseau.';
        case DioExceptionType.connectionError:
          return 'Serveur inaccessible. Vérifiez le backend et l\'URL API actuelle: $_activeApiUrl';
        case DioExceptionType.cancel:
          return 'Requête annulée.';
        case DioExceptionType.badCertificate:
          return 'Certificat serveur invalide.';
        case DioExceptionType.badResponse:
          return 'Réponse invalide du serveur.';
        default:
          return 'Erreur réseau inconnue. Vérifiez votre connexion puis réessayez.';
      }
    }

    return 'Connexion impossible. Veuillez réessayer.';
  }
}

/// Aucun etablissement choisi: la connexion n'a rien a afficher.
class _EcranSansEtablissement extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.school_outlined, size: 52),
                    const SizedBox(height: 16),
                    const Text(
                      'Choisissez d\'abord un établissement',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'La connexion s\'ouvre avec les informations de l\'établissement sélectionné.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pushNamedAndRemoveUntil('/', (route) => false);
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Choisir un établissement'),
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

/// Centre [child] verticalement tant que la hauteur le permet, puis le rend
/// defilant des qu'il depasse.
///
/// Les deux colonnes vivaient dans un Row sans defilement: sur une fenetre
/// courte, le bloc de gauche debordait de quelques pixels au lieu de pouvoir
/// etre parcouru. C'est ce widget, et lui seul, qui rend tenable une fenetre
/// de 520 px de haut.
class _CentreDefilant extends StatelessWidget {
  final Widget child;
  final CrossAxisAlignment crossAxisAlignment;

  const _CentreDefilant({
    required this.child,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: crossAxisAlignment,
              children: [child],
            ),
          ),
        );
      },
    );
  }
}
