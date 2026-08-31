import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// La connexion temps réel du chat, partagée par toute l'application.
///
/// Il y en avait deux : la coquille de l'application en ouvrait une pour
/// compter les non-lus, et le panneau de discussion une seconde dès qu'on
/// l'ouvrait. Deux sockets par personne connectée, deux logiques de
/// reconnexion à maintenir en parallèle — et deux occasions de diverger au
/// premier ajustement.
///
/// Ce canal-ci est le seul propriétaire du socket. Il diffuse les événements
/// reçus à qui les écoute, et reste ouvert tant que quelqu'un écoute.
class CanalTempsReel {
  static const Duration _battement = Duration(seconds: 20);

  /// Comment ouvrir un socket. Injectable pour que le canal se teste sans
  /// serveur: la mecanique de reprise et de battement est precisement ce
  /// qu'on ne peut pas verifier a la main.
  final WebSocketChannel Function(Uri) _ouvrirSocket;

  /// Le battement, ajustable pour que les tests n'attendent pas vingt
  /// secondes a chaque verification.
  final Duration _cadenceBattement;

  CanalTempsReel({
    WebSocketChannel Function(Uri)? ouvrirSocket,
    Duration? cadenceBattement,
  })  : _ouvrirSocket = ouvrirSocket ?? WebSocketChannel.connect,
        _cadenceBattement = cadenceBattement ?? _battement;

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _abonnement;
  Timer? _reconnexion;
  Timer? _battementTimer;

  final _diffuseur = StreamController<Map<String, dynamic>>.broadcast();

  String? _base;
  String? _jeton;
  Uri Function(String base, String jeton)? _fabriqueUrl;
  int _tentative = 0;
  bool _attendPong = false;
  bool _connecte = false;
  bool _ferme = false;

  /// Les événements du serveur, tels qu'il les envoie. Flux de diffusion :
  /// la coquille et le panneau y sont abonnés en même temps.
  Stream<Map<String, dynamic>> get evenements => _diffuseur.stream;

  /// Vrai une fois la poignée de main aboutie, pas avant. `connect()` rend un
  /// canal paresseux dont l'échec n'arrive qu'ensuite : s'en remettre à lui
  /// ferait afficher « en ligne » sur un socket mort-né.
  bool get connecte => _connecte;

  /// Ouvre la connexion, ou la remplace si les identifiants ont changé.
  ///
  /// [fabriqueUrl] construit l'adresse à partir de la base d'API et du jeton :
  /// l'établissement courant et le chemin en dépendent, et le canal n'a pas à
  /// les connaître.
  Future<void> ouvrir(
    String base,
    String jeton, {
    required Uri Function(String base, String jeton) fabriqueUrl,
  }) async {
    if (_ferme) return;
    if (jeton.isEmpty) return;

    // Déjà branché sur les mêmes identifiants: ne pas rouvrir, ce serait
    // couper une connexion vivante pour la remplacer à l'identique.
    if (_connecte && _base == base && _jeton == jeton) return;

    _base = base;
    _jeton = jeton;
    _fabriqueUrl = fabriqueUrl;
    await _brancher();
  }

  Future<void> _brancher() async {
    final base = _base;
    final jeton = _jeton;
    final fabrique = _fabriqueUrl;
    if (base == null || jeton == null || fabrique == null) return;

    _reconnexion?.cancel();
    _reconnexion = null;
    await _abonnement?.cancel();
    await _socket?.sink.close();
    _connecte = false;

    try {
      final socket = _ouvrirSocket(fabrique(base, jeton));
      _socket = socket;
      _abonnement = socket.stream.listen(
        _recevoir,
        onError: (_) => _rompre(),
        onDone: _rompre,
      );

      await socket.ready;
    } catch (_) {
      _rompre();
      return;
    }

    if (_ferme) {
      await _socket?.sink.close();
      return;
    }

    _connecte = true;
    _tentative = 0;
    _attendPong = false;
    _demarrerBattement();
    _diffuseur.add(<String, dynamic>{'event': '_canal_ouvert'});
  }

  void _recevoir(dynamic charge) {
    try {
      final donnees = jsonDecode(charge.toString());
      if (donnees is! Map) return;
      final evenement = Map<String, dynamic>.from(donnees);
      if (evenement['event'] == 'pong') {
        _attendPong = false;
        return;
      }
      _diffuseur.add(evenement);
    } catch (_) {
      // Une charge illisible ne doit pas emporter le canal.
    }
  }

  void _rompre() {
    _connecte = false;
    _battementTimer?.cancel();
    if (_ferme) return;
    _diffuseur.add(<String, dynamic>{'event': '_canal_rompu'});
    _programmerLaReprise();
  }

  void _programmerLaReprise() {
    if (_ferme || _reconnexion != null) return;
    // Doublement jusqu'à trente secondes: retenter chaque seconde pendant une
    // coupure longue n'accélère rien et pilonne le serveur au moment où il
    // s'en remet.
    final secondes = (1 << _tentative.clamp(0, 5)).clamp(1, 30);
    _tentative += 1;
    _reconnexion = Timer(Duration(seconds: secondes), () {
      _reconnexion = null;
      unawaited(_brancher());
    });
  }

  void _demarrerBattement() {
    _battementTimer?.cancel();
    _battementTimer = Timer.periodic(_cadenceBattement, (_) {
      if (!_connecte) return;
      // Deux battements sans réponse: le socket paraît ouvert mais ne porte
      // plus rien. Le fermer soi-même déclenche la reprise.
      if (_attendPong) {
        _attendPong = false;
        unawaited(_socket?.sink.close());
        _rompre();
        return;
      }
      _attendPong = true;
      envoyer(<String, dynamic>{'action': 'ping'});
    });
  }

  /// Envoie une action au serveur. Sans effet si le canal est rompu : le
  /// message est perdu et l'appelant doit le savoir par [connecte].
  void envoyer(Map<String, dynamic> action) {
    if (!_connecte) return;
    try {
      _socket?.sink.add(jsonEncode(action));
    } catch (_) {
      _rompre();
    }
  }

  /// Ferme définitivement. Le canal ne se rouvre plus après cela.
  Future<void> fermer() async {
    _ferme = true;
    _connecte = false;
    _reconnexion?.cancel();
    _battementTimer?.cancel();
    await _abonnement?.cancel();
    await _socket?.sink.close();
    await _diffuseur.close();
  }
}
