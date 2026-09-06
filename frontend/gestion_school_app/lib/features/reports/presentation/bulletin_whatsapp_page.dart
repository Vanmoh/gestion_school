import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/permissions/module_permissions.dart';
import '../data/bulletin_whatsapp_repository.dart';
import '../domain/bulletin_whatsapp.dart';

/// L'envoi des bulletins d'une classe aux familles, par WhatsApp.
///
/// L'ecran est organise autour de ce qui bloque, pas de ce qui marche: sur
/// une classe de soixante eleves, l'interessant n'est pas la liste de ceux
/// qui peuvent recevoir leur bulletin, c'est de savoir lesquels ne le
/// peuvent pas et ce qu'il faut corriger pour cela.
///
/// L'envoi lui-meme est assiste et non automatique: l'application ouvre
/// WhatsApp avec le message pret, un humain appuie sur envoyer. Le serveur
/// ne peut donc pas constater le depart, il le tient de l'utilisateur -- ce
/// que l'ecran dit explicitement plutot que d'afficher un « envoye » qu'il
/// n'a pas verifie.
class BulletinWhatsAppPage extends ConsumerStatefulWidget {
  final int classroomId;
  final String classroomName;
  final int academicYearId;
  final String term;

  const BulletinWhatsAppPage({
    super.key,
    required this.classroomId,
    required this.classroomName,
    required this.academicYearId,
    required this.term,
  });

  @override
  ConsumerState<BulletinWhatsAppPage> createState() =>
      _BulletinWhatsAppPageState();
}

class _BulletinWhatsAppPageState extends ConsumerState<BulletinWhatsAppPage> {
  bool _loading = true;
  String _erreur = '';
  BulletinWhatsAppClasse? _classe;

  /// Les envois prepares pendant cette session, par eleve: c'est ce qui
  /// permet de proposer « confirmer l'envoi » sur la ligne qu'on vient
  /// d'ouvrir, sans recharger toute la classe.
  final Map<int, BulletinWhatsAppEnvoi> _prepares = {};

  /// Les eleves dont l'envoi est declare parti pendant cette session.
  final Set<int> _confirmes = {};

  int? _ligneOccupee;

  BulletinWhatsAppRepository get _repo =>
      BulletinWhatsAppRepository(ref.read(dioProvider));

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _loading = true;
      _erreur = '';
    });
    try {
      final classe = await _repo.etatClasse(
        classroomId: widget.classroomId,
        academicYearId: widget.academicYearId,
        term: widget.term,
      );
      if (!mounted) return;
      setState(() {
        _classe = classe;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _erreur = messageDErreur(
          error,
          parDefaut: 'Impossible de charger la classe.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _envoyer(BulletinWhatsAppEtat eleve, {bool forcer = false}) async {
    setState(() => _ligneOccupee = eleve.studentId);
    try {
      final envoi = await _repo.preparerEleve(
        studentId: eleve.studentId,
        academicYearId: widget.academicYearId,
        term: widget.term,
        forcer: forcer,
      );
      if (!mounted) return;
      setState(() => _prepares[eleve.studentId] = envoi);

      final ouvert = await launchUrl(
        Uri.parse(envoi.whatsappUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      if (!ouvert) {
        // Le lien reste affiche dans la fiche de l'envoi: WhatsApp absent de
        // la machine ne doit pas faire perdre le message deja prepare.
        _message(
          'WhatsApp n\'a pas pu être ouvert. Utilisez « Voir le message » '
          'pour copier le lien.',
        );
      }
    } catch (error) {
      if (!mounted) return;
      final dejaEnvoye =
          codeHttp(error) == BulletinWhatsAppRepository.codeDejaEnvoye;
      if (dejaEnvoye && !forcer) {
        final confirme = await _confirmerRenvoi(eleve, messageDErreur(error));
        if (confirme == true && mounted) {
          await _envoyer(eleve, forcer: true);
        }
        return;
      }
      _message(messageDErreur(error));
    } finally {
      if (mounted) setState(() => _ligneOccupee = null);
    }
  }

  Future<bool?> _confirmerRenvoi(BulletinWhatsAppEtat eleve, String detail) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulletin déjà envoyé'),
        content: Text(
          '$detail\n\n'
          'Envoyer à nouveau le bulletin de ${eleve.studentName} '
          'à ${eleve.parentName.isEmpty ? 'son parent' : eleve.parentName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Envoyer à nouveau'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmerDepart(BulletinWhatsAppEnvoi envoi, {bool echec = false}) async {
    setState(() => _ligneOccupee = envoi.studentId);
    try {
      await _repo.marquerEnvoye(
        envoi.deliveryId,
        motifEchec: echec ? 'Message non envoyé depuis WhatsApp' : '',
      );
      if (!mounted) return;
      setState(() {
        if (echec) {
          _prepares.remove(envoi.studentId);
        } else {
          _confirmes.add(envoi.studentId);
        }
      });
      _message(echec ? 'Échec enregistré.' : 'Envoi enregistré.');
    } catch (error) {
      if (!mounted) return;
      _message(messageDErreur(error, parDefaut: 'Enregistrement impossible.'));
    } finally {
      if (mounted) setState(() => _ligneOccupee = null);
    }
  }

  Future<void> _corrigerContact(BulletinWhatsAppEtat eleve) async {
    final parentId = eleve.parentId;
    if (parentId == null) {
      _message(
        'Rattachez d\'abord un parent à cet élève depuis le module Élèves.',
      );
      return;
    }

    final saisie = await showDialog<_ContactSaisi>(
      context: context,
      builder: (_) => _DialogueContactParent(
        titre: eleve.parentName.isEmpty
            ? 'Contact du parent'
            : 'Contact de ${eleve.parentName}',
        numeroInitial: eleve.phone,
        consentementInitial: eleve.parentConsent,
      ),
    );

    if (saisie == null || !mounted) return;

    try {
      await _repo.enregistrerContactParent(
        parentId: parentId,
        numero: saisie.numero,
        consentement: saisie.consentement,
      );
      if (!mounted) return;
      await _charger();
    } catch (error) {
      if (!mounted) return;
      _message(_motifDeSaisie(error));
    }
  }

  /// Le refus du serveur sur le numero, sorti de la reponse de validation.
  ///
  /// DRF renvoie les erreurs de champ sous la clef du champ et non sous
  /// « detail »: sans cette lecture, l'ecran affichait « Envoi impossible »
  /// la ou le serveur expliquait precisement ce qui clochait dans la saisie.
  String _motifDeSaisie(Object error) {
    final data = donneesDErreur(error);
    if (data is Map) {
      final champ = data['whatsapp_phone'];
      if (champ is List && champ.isNotEmpty) return champ.first.toString();
      if (champ != null) return champ.toString();
    }
    return messageDErreur(error, parDefaut: 'Enregistrement impossible.');
  }

  void _voirLeMessage(BulletinWhatsAppEnvoi envoi) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Message pour ${envoi.studentName}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(envoi.message),
              const SizedBox(height: 12),
              Text(
                'Destinataire : ${envoi.phone}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(texte)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final permissions = ref.watch(currentPermissionsProvider);
    final peutCorriger = permissions.canWrite('students');

    return Scaffold(
      appBar: AppBar(
        title: Text('Bulletins par WhatsApp — ${widget.classroomName}'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loading ? null : _charger,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (_loading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_erreur.isNotEmpty) {
            return _EtatVide(
              icone: Icons.error_outline,
              titre: 'Chargement impossible',
              detail: _erreur,
              action: FilledButton(
                onPressed: _charger,
                child: const Text('Réessayer'),
              ),
            );
          }

          final classe = _classe;
          if (classe == null || classe.eleves.isEmpty) {
            return const _EtatVide(
              icone: Icons.groups_outlined,
              titre: 'Aucun élève',
              detail: 'Cette classe ne compte aucun élève inscrit.',
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Bandeau(
                classe: classe,
                envoyesDansLaSession: _confirmes.length,
                term: widget.term,
              ),
              const SizedBox(height: 16),
              ...classe.eleves.map(
                (eleve) => _LigneEleve(
                  eleve: eleve,
                  envoi: _prepares[eleve.studentId],
                  confirme: _confirmes.contains(eleve.studentId),
                  occupe: _ligneOccupee == eleve.studentId,
                  peutCorriger: peutCorriger,
                  surEnvoi: () => _envoyer(eleve),
                  surCorrection: () => _corrigerContact(eleve),
                  surConfirmation: (echec) {
                    final envoi = _prepares[eleve.studentId];
                    if (envoi != null) _confirmerDepart(envoi, echec: echec);
                  },
                  surApercu: () {
                    final envoi = _prepares[eleve.studentId];
                    if (envoi != null) _voirLeMessage(envoi);
                  },
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'L\'application ouvre WhatsApp avec le message prêt ; c\'est '
                'vous qui appuyez sur envoyer. Le suivi enregistre donc ce '
                'que vous confirmez, pas un accusé de réception du téléphone.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Ce que le formulaire de contact rapporte, une fois valide.
class _ContactSaisi {
  final String numero;
  final bool consentement;

  const _ContactSaisi({required this.numero, required this.consentement});
}

/// Saisie du numero WhatsApp d'un parent et de son accord.
///
/// Un widget a part et non un `StatefulBuilder` dans la page: le champ de
/// texte a besoin d'un controleur dont la duree de vie soit celle du
/// formulaire. Libere par la page, il l'etait pendant que le dialogue se
/// fermait encore, et Flutter refusait alors de reconstruire le champ.
class _DialogueContactParent extends StatefulWidget {
  final String titre;
  final String numeroInitial;
  final bool consentementInitial;

  const _DialogueContactParent({
    required this.titre,
    required this.numeroInitial,
    required this.consentementInitial,
  });

  @override
  State<_DialogueContactParent> createState() => _DialogueContactParentState();
}

class _DialogueContactParentState extends State<_DialogueContactParent> {
  late final TextEditingController _numero;
  late bool _consentement;

  @override
  void initState() {
    super.initState();
    _numero = TextEditingController(text: widget.numeroInitial);
    _consentement = widget.consentementInitial;
  }

  @override
  void dispose() {
    _numero.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      // Largeur bornee et contenu defilant: la case de consentement porte
      // deux lignes de texte, et sans contrainte la colonne debordait de
      // l'ecran au lieu de s'y ajuster.
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _numero,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Numéro WhatsApp',
                  helperText: 'Un seul numéro, par exemple 76 12 34 56',
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _consentement,
                onChanged: (valeur) {
                  setState(() => _consentement = valeur ?? false);
                },
                title: const Text(
                  'Le parent accepte de recevoir les bulletins par WhatsApp',
                ),
                subtitle: const Text(
                  'À cocher seulement si la famille a donné son accord.',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _ContactSaisi(
              numero: _numero.text,
              consentement: _consentement,
            ),
          ),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _Bandeau extends StatelessWidget {
  final BulletinWhatsAppClasse classe;
  final int envoyesDansLaSession;
  final String term;

  const _Bandeau({
    required this.classe,
    required this.envoyesDansLaSession,
    required this.term,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${classe.classroomName} — $term ${classe.academicYear}',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pastille(
                libelle: '${classe.readyCount} joignable(s)',
                couleur: theme.colorScheme.primary,
              ),
              if (classe.blockedCount > 0)
                _Pastille(
                  libelle: '${classe.blockedCount} à corriger',
                  couleur: theme.colorScheme.error,
                ),
              if (envoyesDansLaSession > 0)
                _Pastille(
                  libelle: '$envoyesDansLaSession envoi(s) confirmé(s)',
                  couleur: theme.colorScheme.tertiary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pastille extends StatelessWidget {
  final String libelle;
  final Color couleur;

  const _Pastille({required this.libelle, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        libelle,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(color: couleur),
      ),
    );
  }
}

class _LigneEleve extends StatelessWidget {
  final BulletinWhatsAppEtat eleve;
  final BulletinWhatsAppEnvoi? envoi;
  final bool confirme;
  final bool occupe;
  final bool peutCorriger;
  final VoidCallback surEnvoi;
  final VoidCallback surCorrection;
  final void Function(bool echec) surConfirmation;
  final VoidCallback surApercu;

  const _LigneEleve({
    required this.eleve,
    required this.envoi,
    required this.confirme,
    required this.occupe,
    required this.peutCorriger,
    required this.surEnvoi,
    required this.surCorrection,
    required this.surConfirmation,
    required this.surApercu,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prepare = envoi != null && !confirme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eleve.studentName.isEmpty
                            ? eleve.matricule
                            : eleve.studentName,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _sousTitre(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (occupe)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  _statut(theme),
              ],
            ),
            if (!eleve.canSend) ...[
              const SizedBox(height: 8),
              Text(
                eleve.blockedReason,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (eleve.canSend && !prepare && !confirme)
                  FilledButton.icon(
                    onPressed: occupe ? null : surEnvoi,
                    icon: const Icon(Icons.send, size: 18),
                    label: Text(
                      eleve.alreadySent ? 'Envoyer à nouveau' : 'Envoyer',
                    ),
                  ),
                // Un envoi confirme reste rejouable, en retrait: « je n'ai
                // rien recu » est la premiere chose que dit une famille, et
                // obliger a recharger toute la classe pour y repondre faisait
                // perdre la trace de la ou on en etait.
                if (confirme)
                  TextButton.icon(
                    onPressed: occupe ? null : surEnvoi,
                    icon: const Icon(Icons.replay, size: 18),
                    label: const Text('Envoyer à nouveau'),
                  ),
                if (prepare) ...[
                  FilledButton.icon(
                    onPressed: occupe ? null : () => surConfirmation(false),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Message envoyé'),
                  ),
                  TextButton(
                    onPressed: occupe ? null : () => surConfirmation(true),
                    child: const Text('Je n\'ai pas pu envoyer'),
                  ),
                  TextButton(
                    onPressed: occupe ? null : surApercu,
                    child: const Text('Voir le message'),
                  ),
                ],
                if (!eleve.canSend && peutCorriger && eleve.parentId != null)
                  TextButton.icon(
                    onPressed: occupe ? null : surCorrection,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Corriger le contact'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sousTitre() {
    final morceaux = <String>[];
    if (eleve.parentName.isNotEmpty) morceaux.add(eleve.parentName);
    if (eleve.phone.isNotEmpty) morceaux.add(eleve.phone);
    if (morceaux.isEmpty) return 'Aucun contact enregistré';
    return morceaux.join(' · ');
  }

  Widget _statut(ThemeData theme) {
    if (confirme) {
      return Icon(Icons.check_circle, color: theme.colorScheme.primary);
    }
    if (eleve.alreadySent) {
      final date = eleve.lastSentAt;
      return Tooltip(
        message: date == null
            ? 'Bulletin déjà envoyé'
            : 'Envoyé le ${date.day.toString().padLeft(2, '0')}/'
                  '${date.month.toString().padLeft(2, '0')}/${date.year}',
        child: Icon(
          Icons.mark_email_read_outlined,
          color: theme.colorScheme.tertiary,
        ),
      );
    }
    if (!eleve.canSend) {
      return Icon(Icons.block, color: theme.colorScheme.error);
    }
    return Icon(
      Icons.schedule_send_outlined,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _EtatVide extends StatelessWidget {
  final IconData icone;
  final String titre;
  final String detail;
  final Widget? action;

  const _EtatVide({
    required this.icone,
    required this.titre,
    required this.detail,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(titre, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
