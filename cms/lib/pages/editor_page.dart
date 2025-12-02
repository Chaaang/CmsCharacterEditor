import 'package:cms/api/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:async';
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
  double _stickerSize = 1.0; // Default sticker size (1.0 = normal size)

  // Undo history
  final List<_DesignSnapshot> _history = [];
  static const int _maxHistorySize = 50;

  // Global key for capturing the canvas
  final GlobalKey _canvasKey = GlobalKey();

  // Upload state
  bool _isUploading = false;

  // Bump this to force rebuilding the CharacterCanvas (clears internal caches)
  int _canvasVersion = 0;

  // Performance optimization: throttle setState during drawing
  int _pointsSinceLastUpdate = 0;
  static const int _updateThreshold = 3; // Update every 3 points

  // Timer state
  Timer? _timer;
  int _remainingSeconds = 600; // 10 minutes in seconds
  static const int _initialTimerSeconds = 600; // 10 minutes
  static const int _extendedTimerSeconds = 300; // 5 minutes
  static const String _password = '8833'; // Same password as QR page

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() {
          _remainingSeconds--;
        });
      } else {
        _timer?.cancel();
        _showPasswordDialog();
      }
    });
  }

  void _resetTimer({bool extend = false}) {
    _remainingSeconds = extend ? _extendedTimerSeconds : _initialTimerSeconds;
    _startTimer();
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _showPasswordDialog() async {
    final passwordController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? errorMessage;

        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Time\'s Up!'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Please enter password to continue:'),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        errorText: errorMessage,
                      ),
                      onSubmitted: (value) {
                        if (value == _password) {
                          Navigator.pop(context, true);
                        } else {
                          setDialogState(() {
                            errorMessage = 'Incorrect password';
                          });
                          passwordController.clear();
                        }
                      },
                      autofocus: true,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Skip & Print QR'),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (passwordController.text == _password) {
                        Navigator.pop(context, true);
                      } else {
                        setDialogState(() {
                          errorMessage = 'Incorrect password';
                        });
                        passwordController.clear();
                      }
                    },
                    child: const Text('Submit'),
                  ),
                ],
              ),
        );
      },
    );

    if (result == true) {
      // Password correct - reset timer to 5 minutes
      _resetTimer(extend: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Timer extended by 5 minutes'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // User skipped or cancelled - proceed to upload and print QR
      await _proceedToQR();
    }
  }

  Future<void> _proceedToQR() async {
    // Upload the canvas first, then navigate to QR page
    await _performUpload();
  }

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

  final List<Color> _colors = [
    Colors.black,
    Color(0xFF724236),
    Color(0xFF548F46),
    Color(0xFF4442FB),
    Color(0xFFEA7600),
    Color(0xFFFF2A08),
    Color(0xFF8850C7),
  ];

  // Activate eraser tool
  void _activateEraser() {
    setState(() {
      _tool = ToolType.eraser;
    });
  }

  void _startDraw(Offset p) {
    if (_tool == ToolType.brush || _tool == ToolType.eraser) {
      _saveToHistory(); // Save state before starting new stroke
      setState(() {
        _currentStroke = DrawStroke(
          points: [p],
          color: _tool == ToolType.eraser ? Colors.white.value : _color.value,
          strokeWidth: _stroke,
          isEraser: _tool == ToolType.eraser,
        );
        widget.design.strokes.add(_currentStroke!);
      });
    }
  }

  void _updateDraw(Offset p) {
    if (_currentStroke != null) {
      _currentStroke!.points.add(p);
      _pointsSinceLastUpdate++;

      // Throttle updates: only call setState every N points for better performance
      if (_pointsSinceLastUpdate >= _updateThreshold) {
        _pointsSinceLastUpdate = 0;
        setState(() {
          // State is already updated, just trigger rebuild
        });
      }
    }
  }

  void _endDraw() {
    // Always update on end to ensure final state is rendered
    _pointsSinceLastUpdate = 0;
    setState(() {
      _currentStroke = null;
    });
  }

  void _selectSticker(String label) {
    setState(() {
      _selectedSticker = label;
      _tool = ToolType.move; // Switch to move tool when sticker is selected
    });
  }

  void _selectPlacedSticker(Sticker sticker) {
    setState(() {
      _selectedSticker = null; // Clear palette selection
      _tool = ToolType.move; // Ensure move tool is active
    });
  }

  // Convert sticker size value (1.0-2.0) to display value (1-10)
  int _getStickerDisplayValue(double value) {
    // Map: 1.0->1, 1.1->2, 1.2->3, ..., 1.9->10, 2.0->10
    final displayValue = ((value - 1.0) * 10).round() + 1;
    return displayValue.clamp(1, 10);
  }

  void _clearCanvas() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear Canvas'),
            content: const Text(
              'Are you sure you want to clear all drawings and stickers? This cannot be undone.',
            ),
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
                    // Force CharacterCanvas to rebuild with a new State
                    _canvasVersion++;
                  });

                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Clear'),
              ),
            ],
          ),
    );
  }

  void _backToPhotoPage() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit Editor'),
            content: const Text(
              'Are you sure you want to exit Editor and go back to Photo Page? This will clear all drawings and stickers.',
            ),
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
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  // Save current state to history (async to avoid blocking UI)
  void _saveToHistory() {
    // Defer the expensive copy operation to avoid blocking the UI thread
    Future.microtask(() {
      if (!mounted) return;

      // Create a snapshot of current strokes and stickers
      final snapshot = _DesignSnapshot(
        strokes:
            widget.design.strokes
                .map(
                  (s) => DrawStroke(
                    points: List.from(s.points),
                    color: s.color,
                    strokeWidth: s.strokeWidth,
                    isEraser: s.isEraser,
                  ),
                )
                .toList(),
        stickers:
            widget.design.stickers
                .map(
                  (s) => Sticker(
                    label: s.label,
                    position: s.position,
                    scale: s.scale,
                    rotation: s.rotation,
                  ),
                )
                .toList(),
      );

      _history.add(snapshot);
      if (_history.length > _maxHistorySize) {
        _history.removeAt(0); // Remove oldest
      }
    });
  }

  // Upload/Save the canvas as image
  Future<void> _uploadCanvas() async {
    // Show confirmation dialog first
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Confirm Upload'),
            content: const Text(
              'Are you sure? Once uploaded, no further changes can be made.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Continue'),
              ),
            ],
          ),
    );

    if (confirmed != true) {
      return; // User cancelled
    }

    // Proceed with upload
    await _performUpload();
  }

  Future<void> _performUpload() async {
    if (_isUploading) return; // Prevent multiple simultaneous uploads

    setState(() {
      _isUploading = true;
    });

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => PopScope(
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Canvas not ready')));
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

      final url = await Api.saveDesign(
        widget.design,
        byteData.buffer.asUint8List(),
      );

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        if (url != null && url.isNotEmpty) {
          // Navigate to QR page with the URL
          //Navigator.of(context).pushNamed(QRPage.routeName, arguments: url);

          Navigator.push(
            context,
            MaterialPageRoute(
              builder:
                  (context) => QRPage(url: url, characterDesign: widget.design),
            ),
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
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GradientHeader(text: widget.design.characterName, fontSize: 24),
            const SizedBox(width: 16),
            // Timer display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:
                    _remainingSeconds <= 60
                        ? Colors.red
                        : _remainingSeconds <= 300
                        ? Colors.orange
                        : Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _formatTime(_remainingSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.upload),
              tooltip: 'Upload',
              onPressed: _uploadCanvas,
              color: Colors.white,
            ),
          ],
        ),
        //Text(${widget.design.characterName}'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            tooltip: 'Clear Canvas',
            onPressed: _clearCanvas,
            color: Colors.white,
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
            onEraserTap: _activateEraser,
            colors: _colors,
            onColorChanged: (c) => setState(() => _color = c),
            onColorPickerTap: () async {
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
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // On tablets, use transparent background since CharacterCanvas draws its own
                  final canvasArea =
                      constraints.maxWidth * constraints.maxHeight;
                  final isTablet = canvasArea > 500000;

                  return DecoratedBox(
                    decoration: BoxDecoration(
                      color: isTablet ? Colors.transparent : Colors.black,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isTablet ? Colors.transparent : Colors.black12,
                      ),
                    ),
                    child: RepaintBoundary(
                      key: _canvasKey,
                      child: CharacterCanvas(
                        key: ValueKey(_canvasVersion),
                        design: widget.design,
                        onPanStart: _startDraw,
                        onPanUpdate: _updateDraw,
                        onPanEnd: _endDraw,
                        faceDraggable: false, // Don't show face image for now
                        onTap:
                            _selectedSticker != null ? _placeStickerAt : null,
                        onStickerTap:
                            _tool == ToolType.move
                                ? _selectPlacedSticker
                                : null,
                        onTapPart: (partKey) {
                          // Part tapping for other tools
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          //Stroke Size and Sticker Size Selectors
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              children: [
                // Stroke Size Selector
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Brush Size',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _stroke.toStringAsFixed(0),
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text(
                            'Small',
                            style: TextStyle(fontSize: 21, color: Colors.grey),
                          ),
                          Expanded(
                            child: Slider(
                              value: _stroke,
                              min: 1.0,
                              max: 24.0,
                              divisions: 23,
                              activeColor: Colors.purple,
                              inactiveColor: Colors.pink.shade200,
                              onChanged: (value) {
                                setState(() {
                                  _stroke = value;
                                });
                              },
                            ),
                          ),
                          const Text(
                            'Large',
                            style: TextStyle(fontSize: 21, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Vertical divider
                Container(
                  width: 1,
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.grey.shade300,
                ),
                // Sticker Size Selector
                Expanded(
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
                            _getStickerDisplayValue(_stickerSize).toString(),
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text(
                            '1',
                            style: TextStyle(fontSize: 21, color: Colors.grey),
                          ),
                          Expanded(
                            child: Slider(
                              value: _stickerSize,
                              min: 1.0,
                              max: 2.0,
                              divisions: 10,
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
                            '10',
                            style: TextStyle(fontSize: 21, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                      color:
                          _selectedSticker == s
                              ? Colors.blue.shade200
                              : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          _selectedSticker == s
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
  _DesignSnapshot({required this.strokes, required this.stickers});

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
    required this.onEraserTap,
    required this.colors,
    required this.onColorChanged,
    required this.onColorPickerTap,
  });

  final ToolType tool;
  final Color color;
  final double stroke;
  final ValueChanged<ToolType> onToolChanged;
  final ValueChanged<double> onStrokeChanged;
  final VoidCallback onEraserTap;
  final List<Color> colors;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onColorPickerTap;

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
            icon: Icons.auto_fix_off,
            selected: tool == ToolType.eraser,
            tooltip: 'Eraser',
            onTap: onEraserTap,
          ),
          const Spacer(),
          // Color Picker Button
          Tooltip(
            message: 'Pick Color',
            child: InkResponse(
              onTap: onColorPickerTap,
              radius: 24,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Icon(
                  size: 40,
                  Icons.color_lens,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          SizedBox(width: 8),
          // Color Palette
          Row(
            children:
                colors.map((c) {
                  final isSelected = color.value == c.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => onColorChanged(c),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black26,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow:
                              isSelected
                                  ? [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.5),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                  : null,
                        ),
                      ),
                    ),
                  );
                }).toList(),
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
            color:
                selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                    : null,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? Colors.white : Colors.black12),
          ),
          child: Icon(size: 40, icon, color: selected ? Colors.white : null),
        ),
      ),
    );
  }
}
