import 'dart:ui' show Offset;
import 'dart:typed_data';

enum ToolType { brush, eraser, fill, move }

class DrawStroke {
  DrawStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
  });

  final List<Offset> points;
  final int color;
  final double strokeWidth;
  final bool isEraser;
}

class Sticker {
  Sticker({
    required this.label,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
  });

  final String label;
  Offset position;
  double scale;
  double rotation;
}

class CharacterDesign {
  CharacterDesign({
    required this.userName,
    required this.characterId,
    required this.characterName,
    required this.characterMask,
    this.faceImageBytes,
    this.facePosition = const Offset(0, 0),
    this.faceScale = 1.0,
    this.primaryColor = 0xFF9C27B0,
    Map<String, int>? partColors,
  });

  final String characterMask;
  final String userName;
  final int characterId;
  final String characterName;

  Uint8List? faceImageBytes;
  Offset facePosition;
  double faceScale;

  int primaryColor;

  final List<DrawStroke> strokes = <DrawStroke>[];
  final List<Sticker> stickers = <Sticker>[];

  // Paintable parts for templates (e.g., gingerbread)
  // Keys used: 'face', 'scarf', 'buttons', 'bracelet'
  final Map<String, int> partColors = <String, int>{
    'face': 0xFFFFFFFF,
    'scarf': 0xFFFFFFFF,
    'buttons': 0xFFFFFFFF,
    'bracelet': 0xFFFFFFFF,
  };

  void setPartColor(String partKey, int colorValue) {
    partColors[partKey] = colorValue;
  }

  int getPartColor(String partKey) {
    return partColors[partKey] ?? 0xFFFFFFFF;
  }

  String getCharacterImagePath() {
    switch (characterId) {
      case 0:
        return 'assets/gingerbreadman2.png';
      case 1:
        return 'assets/nutcracker2.png';
      case 2:
        return 'assets/santa2.png';
      case 3:
        return 'assets/elf2.png';
      default:
        return 'assets/gingerbreadman.png';
    }
  }
}


