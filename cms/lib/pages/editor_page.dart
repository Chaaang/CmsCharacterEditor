import 'package:cms/api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import '../state/models.dart';
import '../widgets/character_canvas.dart';
import '../widgets/gradient_header.dart';
import 'qr_page.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.design});
  static const String routeName = '/editor';

  final CharacterDesign design;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  ToolType _tool = ToolType.brush;
  Color _color = Colors.red;
  double _stroke = 6.0;
  DrawStroke? _currentStroke;
  String? _selectedSticker; // Track selected sticker for placement
  Sticker? _selectedPlacedSticker; // Track selected placed sticker for editing
  double _stickerSize = 1.0; // Default sticker size (1.0 = normal size)
  
  // Undo history
  final List<_DesignSnapshot> _history = [];
  static const int _maxHistorySize = 50;
  
  // Global key for capturing the canvas
  final GlobalKey _canvasKey = GlobalKey();
  
  // Upload state
  bool _isUploading = false;

  final List<String> _stickerPalette = [
    '🎅',
    '🕯️',
    '🎄',
    '🦌',
    '⛄',
    '🔔',
    '🎁',
    '🎈',
    '🧦',
    '❄️',
    '⭐',
    '🍬',
  ];

  void _startDraw(Offset p) {
    if (_tool == ToolType.brush || _tool == ToolType.eraser) {
      _saveToHistory(); // Save state before starting new stroke
      setState(() {
        _currentStroke = DrawStroke(
          points: [p],
          color: _tool == ToolType.eraser ? Colors.transparent.value : _color.value,
          strokeWidth: _stroke,
          isEraser: _tool == ToolType.eraser,
        );
        widget.design.strokes.add(_currentStroke!);
      });
    } else if (_tool == ToolType.fill) {
      // Fill uses part taps rather than pan
    }
  }

  void _updateDraw(Offset p) {
    if (_currentStroke != null) {
      setState(() {
        _currentStroke!.points.add(p);
      });
    }
  }

  void _endDraw() {
    setState(() {
      _currentStroke = null;
    });
  }

  void _selectSticker(String label) {
    setState(() {
      _selectedSticker = label;
      _selectedPlacedSticker = null; // Clear any selected placed sticker
      _tool = ToolType.move; // Switch to move tool when sticker is selected
    });
  }
  
  void _selectPlacedSticker(Sticker sticker) {
    setState(() {
      _selectedPlacedSticker = sticker;
      _selectedSticker = null; // Clear palette selection
      _tool = ToolType.move; // Ensure move tool is active
    });
  }
  
  
  void _handleFill(Offset position) {
    // Fill is handled by CharacterCanvas
    // History is saved via onBeforeFill callback
  }
  
  void _clearCanvas() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Canvas'),
        content: const Text('Are you sure you want to clear all drawings and stickers? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                widget.design.strokes.clear();
                widget.design.stickers.clear();
              });
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

    void _backToPhotoPage() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Editor'),
        content: const Text('Are you sure you want to exit Editor and go back to Photo Page? This will clear all drawings and stickers.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                widget.design.strokes.clear();
                widget.design.stickers.clear();
              });
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
  void _placeStickerAt(Offset position) {
    if (_selectedSticker != null) {
      _saveToHistory(); // Save state before placing sticker
      setState(() {
        // Calculate text size to center the sticker on tap position
        final textPainter = TextPainter(
          text: TextSpan(
            text: _selectedSticker!,
            style: const TextStyle(fontSize: 48),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        
        // Adjust position to center the sticker on the tap point
        final adjustedPosition = Offset(
          position.dx - textPainter.width / 2,
          position.dy - textPainter.height / 2,
        );
        
        widget.design.stickers.add(
          Sticker(
            label: _selectedSticker!,
            position: adjustedPosition,
            scale: _stickerSize, // Use the selected sticker size
          ),
        );
        _selectedSticker = null; // Clear selection after placing
        _tool = ToolType.brush; // Switch back to brush
      });
    }
  }

  // Save current state to history
  void _saveToHistory() {
    // Create a snapshot of current strokes and stickers
    final snapshot = _DesignSnapshot(
      strokes: widget.design.strokes.map((s) => DrawStroke(
        points: List.from(s.points),
        color: s.color,
        strokeWidth: s.strokeWidth,
        isEraser: s.isEraser,
      )).toList(),
      stickers: widget.design.stickers.map((s) => Sticker(
        label: s.label,
        position: s.position,
        scale: s.scale,
        rotation: s.rotation,
      )).toList(),
    );
    
    _history.add(snapshot);
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0); // Remove oldest
    }
  }
  
  // Undo last action
  void _undo() {
    if (_history.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to undo')),
      );
      return;
    }
    
    setState(() {
      final snapshot = _history.removeLast();
      widget.design.strokes.clear();
      widget.design.strokes.addAll(snapshot.strokes);
      widget.design.stickers.clear();
      widget.design.stickers.addAll(snapshot.stickers);
    });
  }
  
  // Upload/Save the canvas as image
  Future<void> _uploadCanvas() async {
    if (_isUploading) return; // Prevent multiple simultaneous uploads
    
    setState(() {
      _isUploading = true;
    });
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, // Prevent dismissing during upload
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text(
                'Uploading your design...',
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
    
    try {
      final renderObject = _canvasKey.currentContext?.findRenderObject();
      if (renderObject == null || !renderObject.attached) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Canvas not ready')),
          );
        }
        return;
      }
      
      final renderRepaintBoundary = renderObject as RenderRepaintBoundary;
      final image = await renderRepaintBoundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      
      if (byteData == null) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to capture image')),
          );
        }
        return;
      }

      final url = await Api.saveDesign(widget.design, byteData.buffer.asUint8List());
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        
        if (url != null && url.isNotEmpty) {
          // Navigate to QR page with the URL
          Navigator.of(context).pushNamed(
            QRPage.routeName,
            arguments: url,
          );
        } else {
          // If no URL returned, show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Upload successful but no URL received'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
            backgroundColor: const Color(0xFF5522A3),
      appBar: AppBar(
        leading: GestureDetector(
          onTap: () {
            _backToPhotoPage();
          },
          child: const Icon(Icons.arrow_back),
        ),
        backgroundColor: const Color(0xFF5522A3),
        title: GradientHeader(text: widget.design.characterName, fontSize: 24,),//Text(${widget.design.characterName}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear Canvas',
            onPressed: _clearCanvas,
            color: Colors.white,
          ),
          IconButton(
            icon: const Icon(Icons.color_lens),
            tooltip: 'Pick Color',
            color: Colors.white,
            onPressed: () async {
              final picked = await showDialog<Color>(
                context: context,
                builder: (context) {
                  Color temp = _color;
                  return AlertDialog(
                    title: const Text('Pick a color'),
                    content: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: temp,
                        onColorChanged: (c) => temp = c,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, temp),
                        child: const Text('Select'),
                      ),
                    ],
                  );
                },
              );
              if (picked != null) {
                setState(() => _color = picked);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _ToolBar(
            tool: _tool,
            color: _color,
            stroke: _stroke,
            onToolChanged: (t) => setState(() => _tool = t),
            onStrokeChanged: (v) => setState(() => _stroke = v),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                  child: RepaintBoundary(
                  key: _canvasKey,
                  child: CharacterCanvas(
                    design: widget.design,
                    onPanStart: _startDraw,
                    onPanUpdate: _updateDraw,
                    onPanEnd: _endDraw,
                    faceDraggable: false, // Don't show face image for now
                    onTap: _selectedSticker != null 
                        ? _placeStickerAt 
                        : (_tool == ToolType.fill ? _handleFill : null),
                    fillColor: _tool == ToolType.fill ? _color : null,
                    onBeforeFill: _tool == ToolType.fill ? _saveToHistory : null,
                    onAfterFill: _tool == ToolType.fill ? () => setState(() {}) : null,
                    onStickerTap: _tool == ToolType.move ? _selectPlacedSticker : null,
                    onTapPart: (partKey) {
                      // Part tapping for other tools
                    },
                  ),
                ),
              ),
            ),
          ),
          // UNDO and UPLOAD buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _history.isEmpty ? null : _undo,
                  icon: const Icon(Icons.undo),
                  label: const Text('Undo'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadCanvas,
                  icon: _isUploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.upload),
                  label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          // Sticker Size Selector
          Container(
            
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Sticker Size',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      _stickerSize.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text(
                      'Small',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    Expanded(
                      child: Slider(
                        value: _stickerSize,
                        min: 0.5,
                        max: 2.0,
                        divisions: 25,
                        activeColor: Colors.purple,
                        inactiveColor: Colors.pink.shade200,
                        onChanged: (value) {
                          setState(() {
                            _stickerSize = value;
                          });
                        },
                      ),
                    ),
                    const Text(
                      'Large',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 80,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final s = _stickerPalette[index];
                return GestureDetector(
                  onTap: () => _selectSticker(s),
                  child: Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _selectedSticker == s 
                          ? Colors.blue.shade200 
                          : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border: _selectedSticker == s
                          ? Border.all(color: Colors.blue, width: 2)
                          : null,
                    ),
                    child: Text(s, style: const TextStyle(fontSize: 32)),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _stickerPalette.length,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// Helper class to store design snapshots for undo
class _DesignSnapshot {
  _DesignSnapshot({
    required this.strokes,
    required this.stickers,
  });
  
  final List<DrawStroke> strokes;
  final List<Sticker> stickers;
}

class _ToolBar extends StatelessWidget {
  const _ToolBar({
    required this.tool,
    required this.color,
    required this.stroke,
    required this.onToolChanged,
    required this.onStrokeChanged,
  });

  final ToolType tool;
  final Color color;
  final double stroke;
  final ValueChanged<ToolType> onToolChanged;
  final ValueChanged<double> onStrokeChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _ToolButton(
            icon: Icons.brush,
            selected: tool == ToolType.brush,
            tooltip: 'Brush',
            onTap: () => onToolChanged(ToolType.brush),
          ),
          const SizedBox(width: 8),
          _ToolButton(
            icon: Icons.format_color_fill,
            selected: tool == ToolType.fill,
            tooltip: 'Fill',
            onTap: () => onToolChanged(ToolType.fill),
          ),
          // const SizedBox(width: 8),
          // _ToolButton(
          //   icon: Icons.auto_fix_off,
          //   selected: tool == ToolType.eraser,
          //   tooltip: 'Eraser',
          //   onTap: () => onToolChanged(ToolType.eraser),
          // ),
          const Spacer(),
          // Stroke Size Selector in Toolbar
          Container(
            width: 200,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Stroke Size',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      stroke.toStringAsFixed(0),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text(
                      'Small',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                    Expanded(
                      child: Slider(
                        value: stroke,
                        min: 1.0,
                        max: 24.0,
                        divisions: 23,
                        activeColor: Colors.purple,
                        inactiveColor: Colors.pink.shade200,
                        onChanged: onStrokeChanged,
                      ),
                    ),
                    const Text(
                      'Large',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.selected,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final bool selected;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: selected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? Colors.white : Colors.black12,
            ),
          ),
          child: Icon(
            size: 40,
            icon,
            color: selected ? Colors.white : null,
          ),
        ),
      ),
    );
  }
}
