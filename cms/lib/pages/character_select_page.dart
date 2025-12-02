import 'package:cms/widgets/gradient_header.dart';
import 'package:flutter/material.dart';
import '../state/models.dart';
import 'photo_page.dart';

class CharacterSelectPage extends StatelessWidget {
  const CharacterSelectPage({super.key, required this.userName});
  static const String routeName = '/character';

  final String userName;

  @override
  Widget build(BuildContext context) {
    final characters = <_CharacterInfo>[
      const _CharacterInfo(
        'Gingerbread Man',
        'Color the sweet gingerbread',
        'assets/gingerbreadman.png',
        'assets/mask-gingerbreadman.png',
      ),
      const _CharacterInfo(
        'Nutcracker',
        'Color the royal nutcracker',
        'assets/nutcracker.png',
        'assets/mask-nutcracker.png',
      ),
      const _CharacterInfo(
        'Santa',
        'Decorate Santa for Christmas',
        'assets/santa.png',
        'assets/mask-santa.png',
      ),
      const _CharacterInfo(
        'Elf',
        'Bring the elf to life',
        'assets/elf.png',
        'assets/mask-elf.png',
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 32),
        ),
        backgroundColor: const Color(0xFF5522A3),
        title: const GradientHeader(
          text: 'Choose Your Character',
          fontSize: 28,
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFF5522A3),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Pick a character to start coloring',
                style: TextStyle(color: Colors.white70, fontSize: 18),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                shrinkWrap: false,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: characters.length,
                itemBuilder: (context, index) {
                  final info = characters[index];
                  return _CharacterCard(
                    title: info.title,
                    subtitle: info.subtitle,
                    imagePath: info.imagePath,
                    onTap: () {
                      final design = CharacterDesign(
                        userName: userName,
                        characterId: index,
                        characterName: info.title,
                        characterMask: info.characterMask,
                      );
                      Navigator.of(
                        context,
                      ).pushNamed(PhotoPage.routeName, arguments: design);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.title,
    required this.subtitle,
    required this.imagePath,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final String imagePath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.black,
                    child: Image.asset(imagePath, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 35,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.black54, fontSize: 18),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text(
                  'Start Coloring  →',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterInfo {
  const _CharacterInfo(
    this.title,
    this.subtitle,
    this.imagePath,
    this.characterMask,
  );
  final String title;
  final String subtitle;
  final String imagePath;
  final String characterMask;
}
