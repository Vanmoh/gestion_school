import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/branding.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/etablissement_api.dart';
import '../../../core/network/api_client.dart';
import '../../../models/etablissement.dart';
import '../../../screens/etablissement_selection_screen.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _testingApiConnection = false;
  String _activeApiUrl = ApiConstants.baseUrl;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadActiveApiUrl();
    Future.microtask(
      () => ref.read(authControllerProvider.notifier).restoreSession(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    ref.listen(authControllerProvider, (previous, next) async {
      next.whenOrNull(
        data: (user) async {
          if (user != null && mounted) {
            // Récupérer les établissements de l'utilisateur
            final dio = ref.read(dioProvider);
            try {
              final response = await dio.get(EtablissementApi.etablissements);
              final List<dynamic> data = response.data as List<dynamic>;
              final etablissements = data.map((e) => Etablissement.fromJson(e as Map<String, dynamic>)).toList();
              final etabProvider = context.read<EtablissementProvider>();
              etabProvider.setEtablissements(etablissements);
              if (etablissements.length == 1) {
                etabProvider.selectEtablissement(etablissements.first);
                Navigator.of(context).pushReplacementNamed(user.homeRoute);
              } else if (etablissements.length > 1) {
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
                          Navigator.of(context).pushReplacementNamed(user.homeRoute);
                        },
                      ),
                    ),
                  ),
                );
              } else {
                _showMessage('Aucun établissement associé à ce compte.');
              }
            } catch (e) {
              _showMessage('Erreur lors de la récupération des établissements.');
            }
          }
        },
        error: (error, _) {
          _showMessage(_friendlyErrorMessage(error));
        },
      );
    });

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.surface,
                  scheme.surfaceContainerHighest.withValues(alpha: 0.42),
                ],
              ),
            ),
          ),
          Positioned(
            top: -80,
            left: -40,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.primary.withValues(alpha: 0.15),
              ),
            ),
          ),
          Positioned(
            bottom: -110,
            right: -70,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.tertiary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Text(
                  SchoolBranding.schoolName,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 12,
                    color: scheme.primary.withValues(alpha: 0.035),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      if (wide)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 32),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.bolt_rounded,
                                      color: scheme.primary,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      SchoolBranding.appName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.5,
                                          ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: 'Configurer URL API',
                                      onPressed: _openApiSettingsDialog,
                                      icon: const Icon(
                                        Icons.wifi_tethering_rounded,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Image.asset(
                                  'assets/images/logo_ecole.png',
                                  height: 190,
                                  fit: BoxFit.contain,
                                  alignment: Alignment.centerLeft,
                                  cacheWidth: 640,
                                  filterQuality: FilterQuality.medium,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Align(
                                      alignment: Alignment.centerLeft,
                                      child: Icon(
                                        Icons.account_balance_outlined,
                                        size: 52,
                                        color: scheme.primary,
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  '${SchoolBranding.schoolName}\n${SchoolBranding.schoolShort} (${SchoolBranding.level})',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Filières techniques et de gestion intégrées à une plateforme moderne.',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 18),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _featurePill(
                                      context,
                                      icon: Icons.verified_user_outlined,
                                      label: 'Connexion sécurisée',
                                    ),
                                    _featurePill(
                                      context,
                                      icon: Icons.sync_alt,
                                      label: 'Multi-plateforme',
                                    ),
                                    _featurePill(
                                      context,
                                      icon: Icons.analytics_outlined,
                                      label: 'Pilotage en temps réel',
                                    ),
                                    _featurePill(
                                      context,
                                      icon: Icons.call_outlined,
                                      label: 'Tél: ${SchoolBranding.phone}',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'STI: ${SchoolBranding.streamsSti.join(' • ')}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'STG: ${SchoolBranding.streamsStg.join(' • ')}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      Expanded(
                        child: Align(
                          alignment: Alignment.center,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 460),
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.94, end: 1),
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.easeOutCubic,
                              builder: (context, value, child) {
                                return Transform.scale(
                                  scale: value,
                                  child: child,
                                );
                              },
                              child: Card(
                                elevation: 10,
                                shadowColor: scheme.shadow.withValues(
                                  alpha: 0.24,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  side: BorderSide(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(26),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 40,
                                            decoration: BoxDecoration(
                                              color: scheme.primary.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.lock_person_outlined,
                                              color: scheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  SchoolBranding.appName,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                Text(
                                                  'Connexion sécurisée',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: scheme
                                                            .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Configurer URL API',
                                            onPressed: _openApiSettingsDialog,
                                            icon: const Icon(
                                              Icons.wifi_tethering_rounded,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      TextField(
                                        controller: _usernameController,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          labelText: 'Nom utilisateur',
                                          prefixIcon: const Icon(
                                            Icons.person_outline,
                                          ),
                                          filled: true,
                                          fillColor: scheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.28),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        onSubmitted: (_) =>
                                            _submitLogin(authState.isLoading),
                                        decoration: InputDecoration(
                                          labelText: 'Mot de passe',
                                          prefixIcon: const Icon(
                                            Icons.lock_outline,
                                          ),
                                          suffixIcon: IconButton(
                                            onPressed: () {
                                              setState(() {
                                                _obscurePassword =
                                                    !_obscurePassword;
                                              });
                                            },
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: scheme
                                              .surfaceContainerHighest
                                              .withValues(alpha: 0.28),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            borderSide: BorderSide.none,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 20),
                                      FilledButton.icon(
                                        onPressed: authState.isLoading
                                            ? null
                                            : () => _submitLogin(false),
                                        icon: authState.isLoading
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.login_rounded),
                                        label: Text(
                                          authState.isLoading
                                              ? 'Connexion en cours...'
                                              : 'Se connecter',
                                        ),
                                        style: FilledButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            50,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Accès réservé aux utilisateurs autorisés • ${SchoolBranding.schoolShort}',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'API: $_activeApiUrl',
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium
                                            ?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: _testingApiConnection
                                            ? null
                                            : _testApiConnection,
                                        icon: _testingApiConnection
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.wifi_find_rounded,
                                              ),
                                        label: const Text(
                                          'Tester connexion API',
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
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _submitLogin(bool loading) {
    if (loading) {
      return;
    }
    ref
        .read(authControllerProvider.notifier)
        .login(_usernameController.text.trim(), _passwordController.text);
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

    final messenger = ScaffoldMessenger.of(context);
    const successColor = Color(0xFF197A43);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: isSuccess ? successColor : null,
          content: Text(
            message,
            style: isSuccess ? const TextStyle(color: Colors.white) : null,
          ),
        ),
      );
  }

  Future<void> _testApiConnection() async {
    setState(() => _testingApiConnection = true);
    final dio = ref.read(dioProvider);

    try {
      final response = await dio.get(
        ApiConstants.login,
        options: Options(validateStatus: (_) => true),
      );

      final status = response.statusCode ?? 0;
      final reachable = status > 0;
      if (mounted) {
        _showMessage(
          reachable
              ? 'API joignable ($_activeApiUrl) • code $status'
              : 'API non joignable ($_activeApiUrl)',
          isSuccess: reachable,
        );
      }
    } on DioException catch (_) {
      if (mounted) {
        _showMessage('API non joignable: $_activeApiUrl');
      }
    } finally {
      if (mounted) {
        setState(() => _testingApiConnection = false);
      }
    }
  }

  Future<void> _openApiSettingsDialog() async {
    final tokenStorage = ref.read(tokenStorageProvider);
    final storedBaseUrl = await tokenStorage.apiBaseUrl();
    final controller = TextEditingController(
      text: storedBaseUrl ?? ApiConstants.baseUrl,
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Configuration API'),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    labelText: 'URL API',
                    hintText: 'http://IP_DU_PC:8000/api',
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Exemple: http://IP_DU_PC:8000/api',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () async {
                final normalized = _normalizeApiBaseUrl(controller.text);
                if (normalized == null) {
                  if (mounted) {
                    _showMessage(
                      'URL invalide. Exemple: http://IP_DU_PC:8000/api',
                    );
                  }
                  return;
                }

                await tokenStorage.saveApiBaseUrl(normalized);
                await _loadActiveApiUrl();

                if (mounted) {
                  Navigator.of(context).pop();
                  _showMessage(
                    'URL API enregistrée: $normalized',
                    isSuccess: true,
                  );
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        );
      },
    );

    controller.dispose();
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

  Widget _featurePill(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
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
        case DioExceptionType.unknown:
          return 'Erreur réseau inconnue. Vérifiez votre connexion puis réessayez.';
      }
    }

    return 'Connexion impossible. Veuillez réessayer.';
  }
}
