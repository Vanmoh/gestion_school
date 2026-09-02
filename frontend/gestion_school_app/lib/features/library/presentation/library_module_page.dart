import 'package:flutter/material.dart';

import 'library_documents_page.dart';
import 'library_page.dart';

/// Les deux bibliotheques sous une seule entree: le papier et le PDF.
///
/// Une seule cle de droits (`library`) les gouverne, contrairement aux
/// emargements dont les deux onglets ont des matrices incompatibles: qui
/// tient le fonds papier tient le fonds numerique, et l'élève qui lit l'un
/// lit l'autre. Deux cles auraient invente une distinction que personne n'a
/// demandee.
class LibraryModulePage extends StatefulWidget {
  const LibraryModulePage({super.key});

  @override
  State<LibraryModulePage> createState() => _LibraryModulePageState();
}

class _LibraryModulePageState extends State<LibraryModulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: TabBar(
            controller: _controller,
            tabs: const [
              Tab(icon: Icon(Icons.picture_as_pdf_outlined), text: 'Documents'),
              Tab(icon: Icon(Icons.menu_book_outlined), text: 'Ouvrages'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _controller,
            children: const [LibraryDocumentsPage(), LibraryPage()],
          ),
        ),
      ],
    );
  }
}
