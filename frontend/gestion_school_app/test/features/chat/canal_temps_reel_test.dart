/// Le canal temps réel partagé du chat.
///
/// Il remplace deux connexions par une : la coquille de l'application en
/// ouvrait une pour compter les non-lus, le panneau une seconde à son
/// ouverture. Ce qu'on vérifie ici est précisément ce qu'on ne peut pas voir
/// à la main — la reprise après coupure, le battement, et le fait qu'un
/// abonné ne prive pas l'autre des événements.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestion_school_app/features/chat/data/canal_temps_reel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Un socket de laboratoire : on décide de ce qu'il reçoit et on relit ce
/// qu'on lui a fait envoyer.
class _FauxSocket implements WebSocketChannel {
  final _entrant = StreamController<dynamic>.broadcast();
  final _sortant = _FauxSink();
  final Completer<void> _pret = Completer<void>();

  _FauxSocket({bool pretDEmblee = true}) {
    if (pretDEmblee) _pret.complete();
  }

  /// Ce que le serveur envoie au client.
  void emettre(String charge) => _entrant.add(charge);

  /// Coupe la connexion, comme un serveur qui redémarre.
  void couper() => _entrant.close();

  void echouer() {
    // Le `catchError` evite une erreur non geree: on pose le refus avant que
    // le canal n'attende `ready`, et Dart signale sinon une exception que
    // personne n'ecoute encore.
    _pret.future.catchError((_) {});
    _pret.completeError(StateError('poignée de main refusée'));
  }

  List<String> get envoyes => _sortant.envoyes;

  @override
  Stream<dynamic> get stream => _entrant.stream;

  @override
  WebSocketSink get sink => _sortant;

  @override
  Future<void> get ready => _pret.future;

  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;

  // Le canal n'utilise que `stream`, `sink` et `ready`; le reste du contrat
  // de StreamChannel n'est la que pour satisfaire le type.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FauxSink implements WebSocketSink {
  final envoyes = <String>[];

  @override
  void add(dynamic data) => envoyes.add(data.toString());

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> get done => Future<void>.value();
}

Uri _url(String base, String jeton) => Uri.parse('ws://test/$jeton');

void main() {
  test('le canal s_ouvre et relaie ce que le serveur envoie', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    final recus = <Map<String, dynamic>>[];
    canal.evenements.listen(recus.add);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    expect(canal.connecte, isTrue);

    socket.emettre('{"event":"message","content":"bonjour"}');
    await Future<void>.delayed(Duration.zero);

    expect(recus.any((e) => e['event'] == 'message'), isTrue);
  });

  test('deux abonnes recoivent le meme evenement', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    // C'est tout l'objet de la fusion: la coquille compte les non-lus pendant
    // que le panneau affiche le fil, sur une seule connexion.
    final coquille = <Map<String, dynamic>>[];
    final panneau = <Map<String, dynamic>>[];
    canal.evenements.listen(coquille.add);
    canal.evenements.listen(panneau.add);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    socket.emettre('{"event":"message","id":7}');
    await Future<void>.delayed(Duration.zero);

    expect(coquille.any((e) => e['id'] == 7), isTrue);
    expect(panneau.any((e) => e['id'] == 7), isTrue);
  });

  test('une poignee de main refusee ne laisse pas le canal se croire ouvert', () async {
    final socket = _FauxSocket(pretDEmblee: false);
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    socket.echouer();
    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);

    // C'est le mensonge que la refonte visait: « connecté » affiché sur un
    // socket mort-né, pendant que plus rien n'arrive.
    expect(canal.connecte, isFalse);
  });

  test('une charge illisible n_emporte pas le canal', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    final recus = <Map<String, dynamic>>[];
    canal.evenements.listen(recus.add);
    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);

    socket.emettre('ceci n est pas du json');
    socket.emettre('{"event":"message"}');
    await Future<void>.delayed(Duration.zero);

    expect(canal.connecte, isTrue);
    expect(recus.any((e) => e['event'] == 'message'), isTrue);
  });

  test('une coupure se signale au lieu de passer inapercue', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    final recus = <Map<String, dynamic>>[];
    canal.evenements.listen(recus.add);
    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);

    socket.couper();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(canal.connecte, isFalse);
    expect(recus.any((e) => e['event'] == '_canal_rompu'), isTrue);
  });

  test('le battement interroge le serveur', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(
      ouvrirSocket: (_) => socket,
      cadenceBattement: const Duration(milliseconds: 20),
    );
    addTearDown(canal.fermer);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(socket.envoyes.any((m) => m.contains('ping')), isTrue);
  });

  test('deux battements sans reponse font conclure a la rupture', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(
      ouvrirSocket: (_) => socket,
      cadenceBattement: const Duration(milliseconds: 20),
    );
    addTearDown(canal.fermer);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    // Le faux socket ne répond jamais « pong »: le socket paraît ouvert mais
    // ne porte plus rien, ce qu'un simple `onDone` ne détecte pas.
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(canal.connecte, isFalse);
  });

  test('un pong ne remonte pas aux abonnes', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    final recus = <Map<String, dynamic>>[];
    canal.evenements.listen(recus.add);
    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);

    socket.emettre('{"event":"pong"}');
    await Future<void>.delayed(Duration.zero);

    expect(recus.any((e) => e['event'] == 'pong'), isFalse);
  });

  test('rouvrir sur les memes identifiants ne coupe pas la connexion', () async {
    var ouvertures = 0;
    final socket = _FauxSocket();
    final canal = CanalTempsReel(
      ouvrirSocket: (_) {
        ouvertures += 1;
        return socket;
      },
    );
    addTearDown(canal.fermer);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);

    expect(ouvertures, 1, reason: 'la seconde demande devait être ignorée');
  });

  test('un envoi sur canal rompu ne jette pas', () async {
    final socket = _FauxSocket();
    final canal = CanalTempsReel(ouvrirSocket: (_) => socket);
    addTearDown(canal.fermer);

    await canal.ouvrir('http://api', 'jeton', fabriqueUrl: _url);
    socket.couper();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(() => canal.envoyer({'action': 'typing'}), returnsNormally);
  });
}
