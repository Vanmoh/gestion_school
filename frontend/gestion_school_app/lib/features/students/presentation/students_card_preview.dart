part of 'students_page.dart';

/// L'aperçu de la carte d'élève avant impression.
///
/// Deux cent soixante lignes de dessin, qui ne servent qu'à l'impression et
/// n'ont rien à voir avec la gestion des dossiers.
///
/// Le mécanisme `part` déplace le code sans le découpler: l'extension voit les
/// champs de la page comme avant.
extension _ApercuDeLaCarte on _StudentsPageState {
  Widget _studentDesignCardPreview(Student student, {bool compact = false}) {
    final classLabel = student.classroomName.trim().isEmpty
        ? 'Non attribuée'
        : student.classroomName;
    final firstName = student.firstName.trim().isEmpty
        ? '-'
        : student.firstName;
    final lastName = student.lastName.trim().isEmpty ? '-' : student.lastName;
    final yearLabel = _activeAcademicYearLabel();
    final birthLabel = student.birthDate == null
        ? '-'
        : '${student.birthDate!.day.toString().padLeft(2, '0')}/${student.birthDate!.month.toString().padLeft(2, '0')}/${student.birthDate!.year.toString().padLeft(4, '0')}';
    final cardNumber = student.id > 0
        ? student.id.toString().padLeft(5, '0')
        : '00000';
    final padding = compact ? 6.5 : 8.0;
    final photoWidth = compact ? 57.0 : 75.0;
    final phoneLine = 'Tel : 78 78 59 13 / 66 74 22 32';
    final signatureWidth = compact ? 74.0 : 98.0;
    final signatureHeight = compact ? 30.0 : 39.0;
    final stampSize = compact ? 42.0 : 52.0;
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF2C303B),
      fontSize: compact ? 6.4 : 7.6,
      fontWeight: FontWeight.w800,
    );
    final valueStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: const Color(0xFF19488A),
      fontSize: compact ? 6.5 : 7.7,
      fontWeight: FontWeight.w800,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF5C6675), width: 1.0),
        color: const Color(0xFFF6F8FC),
      ),
      clipBehavior: Clip.antiAlias,
      child: AspectRatio(
        aspectRatio: _StudentsPageState._studentCardTemplateAspectRatio,
        child: Container(
          margin: EdgeInsets.all(compact ? 3.5 : 4.8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF9EA8BA), width: 0.9),
          ),
          child: Padding(
            padding: EdgeInsets.all(padding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LYCEE TECHNIQUE OUMAR BAH',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF144688),
                    fontSize: compact ? 8.8 : 11.3,
                    letterSpacing: 0.1,
                  ),
                ),
                Text(
                  'LTOB (1er ETAGE)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF2C303B),
                    fontSize: compact ? 7.6 : 9.4,
                  ),
                ),
                Text(
                  phoneLine,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB13B43),
                    fontSize: compact ? 6.0 : 7.2,
                  ),
                ),
                SizedBox(height: compact ? 4.0 : 5.2),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(vertical: compact ? 2.6 : 3.4),
                  color: const Color(0xFF1B5CA6),
                  child: Text(
                    'CARTE SCOLAIRE',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.35,
                      fontSize: compact ? 8.2 : 10.4,
                    ),
                  ),
                ),
                SizedBox(height: compact ? 4.0 : 5.4),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: photoWidth,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: const Color(0xFF326AAF),
                            width: 1.1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(1.2),
                          child: _studentCardPhoto(student),
                        ),
                      ),
                      SizedBox(width: compact ? 6.5 : 8.8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _studentCardInfoRow(
                              'Nom',
                              lastName,
                              compact: compact,
                            ),
                            _studentCardInfoRow(
                              'Prenom',
                              firstName,
                              compact: compact,
                            ),
                            _studentCardInfoRow(
                              'Classe',
                              classLabel,
                              compact: compact,
                            ),
                            _studentCardInfoRow(
                              'Année Scolaire',
                              yearLabel,
                              compact: compact,
                            ),
                            _studentCardInfoRow(
                              'Matricule',
                              student.matricule,
                              compact: compact,
                            ),
                            SizedBox(height: compact ? 2.0 : 2.8),
                            _studentCardInfoRow(
                              'Ne(e) le',
                              birthLabel,
                              compact: compact,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 3.6 : 4.8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: SizedBox(
                        width: compact ? 116 : 156,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'No de Carte : ',
                                    style: labelStyle,
                                  ),
                                  TextSpan(text: cardNumber, style: valueStyle),
                                ],
                              ),
                            ),
                            SizedBox(height: compact ? 1.2 : 1.6),
                            Container(
                              height: 1,
                              color: const Color(0xFFAAC0DE),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: signatureWidth,
                              height: signatureHeight,
                              child: Image.asset(
                                _StudentsPageState._studentCardSignatureAsset,
                                fit: BoxFit.contain,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Color(0xFF3A5F93),
                                          width: 1.1,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Text(
                              'Le Principal',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: compact ? 6.0 : 7.0,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF2C303B),
                                  ),
                            ),
                          ],
                        ),
                        SizedBox(width: compact ? 5.5 : 7.0),
                        SizedBox(
                          width: stampSize,
                          height: stampSize,
                          child: Image.asset(
                            _StudentsPageState._studentCardStampAsset,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFF1F5C9E),
                                    width: 1.2,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'Cachet',
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        fontSize: compact ? 5.0 : 5.8,
                                        color: const Color(0xFF1F5C9E),
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
