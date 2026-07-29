import 'package:flutter/material.dart';

/// Tableau a defilement horizontal dont la premiere colonne reste visible.
///
/// `DataTable` fait disparaitre sa premiere colonne des qu'on fait defiler
/// horizontalement, ce qui rend une grille d'emploi du temps illisible: on ne
/// sait plus a quel creneau correspond la ligne affichee.
///
/// La colonne figee est rendue a l'interieur de chaque ligne, puis translatee
/// du decalage de defilement pour rester collee au bord gauche du viewport.
/// Elle partage donc la contrainte de hauteur de sa ligne: les hauteurs restent
/// alignees quel que soit le contenu des cellules, sans calcul de hauteur.
class FrozenColumnTable extends StatefulWidget {
  /// En-tete de la colonne figee.
  final Widget frozenHeader;

  /// En-tetes des colonnes defilantes.
  final List<Widget> headers;

  /// Cellule figee de chaque ligne (meme longueur que [rows]).
  final List<Widget> frozenCells;

  /// Cellules defilantes, indexees `[ligne][colonne]`.
  final List<List<Widget>> rows;

  final double frozenColumnWidth;
  final double columnWidth;
  final EdgeInsets cellPadding;
  final double minRowHeight;

  const FrozenColumnTable({
    super.key,
    required this.frozenHeader,
    required this.headers,
    required this.frozenCells,
    required this.rows,
    this.frozenColumnWidth = 104,
    this.columnWidth = 180,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.minRowHeight = 48,
  }) : assert(
         frozenCells.length == rows.length,
         'frozenCells et rows doivent decrire le meme nombre de lignes',
       );

  @override
  State<FrozenColumnTable> createState() => _FrozenColumnTableState();
}

class _FrozenColumnTableState extends State<FrozenColumnTable> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _offset => _controller.hasClients ? _controller.offset : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderColor = colorScheme.outlineVariant.withValues(alpha: 0.55);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRow(
                frozen: DefaultTextStyle.merge(
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  child: widget.frozenHeader,
                ),
                cells: widget.headers,
                background: colorScheme.surfaceContainerHighest,
                borderColor: borderColor,
                headerStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (var index = 0; index < widget.rows.length; index++)
                _buildRow(
                  frozen: widget.frozenCells[index],
                  cells: widget.rows[index],
                  // Couleurs opaques obligatoires: la colonne figee est peinte
                  // par-dessus les cellules qui defilent sous elle.
                  background: index.isEven
                      ? colorScheme.surface
                      : Color.alphaBlend(
                          colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.22,
                          ),
                          colorScheme.surface,
                        ),
                  borderColor: borderColor,
                  showTopBorder: true,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow({
    required Widget frozen,
    required List<Widget> cells,
    required Color background,
    required Color borderColor,
    TextStyle? headerStyle,
    bool showTopBorder = false,
  }) {
    final scrollableCells = <Widget>[
      for (final cell in cells)
        SizedBox(
          width: widget.columnWidth,
          child: Padding(
            padding: widget.cellPadding,
            child: Align(alignment: Alignment.centerLeft, child: cell),
          ),
        ),
    ];

    Widget content = Row(
      children: [
        // Reserve la place de la colonne figee, qui est peinte par-dessus.
        SizedBox(width: widget.frozenColumnWidth),
        ...scrollableCells,
      ],
    );

    if (headerStyle != null) {
      content = DefaultTextStyle.merge(style: headerStyle, child: content);
    }

    return Container(
      constraints: BoxConstraints(minHeight: widget.minRowHeight),
      decoration: BoxDecoration(
        color: background,
        border: showTopBorder
            ? Border(top: BorderSide(color: borderColor))
            : null,
      ),
      child: Stack(
        children: [
          content,
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.frozenColumnWidth,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final offset = _offset;
                return Transform.translate(
                  offset: Offset(offset, 0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: background,
                      border: Border(
                        right: BorderSide(color: borderColor),
                      ),
                      // Ombre portee uniquement quand la colonne flotte
                      // au-dessus du contenu defile.
                      boxShadow: offset > 0
                          ? const [
                              BoxShadow(
                                color: Color(0x1F000000),
                                blurRadius: 6,
                                offset: Offset(2, 0),
                              ),
                            ]
                          : const [],
                    ),
                    child: child,
                  ),
                );
              },
              child: Padding(
                padding: widget.cellPadding,
                child: Align(alignment: Alignment.centerLeft, child: frozen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
