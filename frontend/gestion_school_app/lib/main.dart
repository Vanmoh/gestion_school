import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'app.dart';
import 'models/etablissement.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EtablissementProvider()),
      ],
      child: const GestionSchoolApp(),
    ),
  );
}
