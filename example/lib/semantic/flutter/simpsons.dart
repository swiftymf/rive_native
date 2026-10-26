import 'package:flutter/material.dart';

/// Simpsons-themed demo UI: logo, tab bar (PARENT / CHILD / ALL), and character cards.
/// Skeleton + data only; images are placeholders.
class SemanticDemoFlutterSimpsons extends StatefulWidget {
  const SemanticDemoFlutterSimpsons({super.key});

  @override
  State<SemanticDemoFlutterSimpsons> createState() =>
      _SemanticDemoFlutterSimpsonsState();
}

class _SimpsonCharacter {
  const _SimpsonCharacter({
    required this.name,
    required this.dob,
    required this.quote,
    required this.isParent,
  });

  final String name;
  final String dob;
  final String quote;
  final bool isParent;
}

class _SemanticDemoFlutterSimpsonsState
    extends State<SemanticDemoFlutterSimpsons> {
  static const List<_SimpsonCharacter> _characters = [
    _SimpsonCharacter(
      name: 'HOMER SIMPSON',
      dob: 'May 12th',
      quote: "D'oh!",
      isParent: true,
    ),
    _SimpsonCharacter(
      name: 'MARGE SIMPSON',
      dob: 'March 18th',
      quote: 'Oh, Homie!',
      isParent: true,
    ),
    _SimpsonCharacter(
      name: 'BART SIMPSON',
      dob: 'Unknown',
      quote: 'Eat my shorts!',
      isParent: false,
    ),
    _SimpsonCharacter(
      name: 'LISA SIMPSON',
      dob: 'Unknown',
      quote: 'BAAAAART!!',
      isParent: false,
    ),
    _SimpsonCharacter(
      name: 'MAGGIE SIMPSON',
      dob: '1988',
      quote: 'Daddy.',
      isParent: false,
    ),
  ];

  Widget _buildTabContent(List<_SimpsonCharacter> characters) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.amber.shade200,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: _CardsGrid(characters: characters),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: DefaultTabController(
          length: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        'THE',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'SIMPSONS',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade700,
                          shadows: [
                            Shadow(
                              color: Colors.black87,
                              offset: const Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Tab bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: TabBar(
                    indicator: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    dividerColor: Colors.transparent,
                    labelColor: Colors.black87,
                    unselectedLabelColor: Colors.brown.shade800,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    tabs: const [
                      Tab(text: 'PARENT'),
                      Tab(text: 'CHILD'),
                      Tab(text: 'ALL'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildTabContent(
                        _characters.where((c) => c.isParent).toList()),
                    _buildTabContent(
                        _characters.where((c) => !c.isParent).toList()),
                    _buildTabContent(List.from(_characters)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardsGrid extends StatelessWidget {
  const _CardsGrid({required this.characters});

  final List<_SimpsonCharacter> characters;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 16.0;
        const crossAxisCount = 2;
        final width = (constraints.maxWidth - spacing) / crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: characters
              .map((c) => SizedBox(
                    width: width,
                    child: _CharacterCard(character: c),
                  ))
              .toList(),
        );
      },
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({required this.character});

  final _SimpsonCharacter character;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Placeholder avatar
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person, color: Colors.blue.shade300, size: 32),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    character.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'DOB: ${character.dob}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Quote: "${character.quote}"',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
