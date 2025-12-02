import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import '../state/models.dart';
import 'character_shapes.dart';

class CharacterCanvas extends StatefulWidget {
  const CharacterCanvas({
    super.key,
    required this.design,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.faceDraggable = true,
    this.onTap,
    this.onTapPart,
    this.fillColor,
    this.onStickerTap,
    this.onBeforeFill,
    this.onAfterFill,
    this.onStrokeEnd,
  });

  final CharacterDesign design;
  final void Function(Offset localPos)? onPanStart;
  final void Function(Offset localPos)? onPanUpdate;
  final VoidCallback? onPanEnd;
  final bool faceDraggable;
  final void Function(Offset localPos)? onTap;
  final void Function(String partKey)? onTapPart;
  final Color? fillColor; // Color to use for flood fill
  final void Function(Sticker sticker)?
  onStickerTap; // Callback when sticker is tapped
  final VoidCallback?
  onBeforeFill; // Callback before fill operation (for undo history)
  final VoidCallback? onAfterFill; // Callback after fill operation completes
  final VoidCallback? onStrokeEnd; // Callback when stroke ends (for caching)

  @override
  State<CharacterCanvas> createState() => _CharacterCanvasState();
}

class _CharacterCanvasState extends State<CharacterCanvas> {
  bool _isFilling = false;
  // Paths used for hit-testing parts on the gingerbread template
  Path? _facePath;
  Path? _scarfPath;
  List<Path> _buttonPaths = <Path>[];
  Path? _braceletPath;

  // Paths for all drawable (white) areas of the character
  Path? _drawablePath;

  // Face image and mask for drawing
  ui.Image? _faceImage;
  ui.Image? _faceMaskImage;

  // Track if we're currently drawing (on white area)
  bool _isDrawing = false;

  // Store canvas size for filtering
  Size? _canvasSize;

  // Cache for fill stroke point keys for fast O(1) lookup
  final Map<DrawStroke, Set<int>> _fillStrokeKeysCache = {};

  // Cache for completed stroke paths to avoid rebuilding on every repaint
  final Map<DrawStroke, Path> _strokePathCache = {};
  final Map<DrawStroke, int> _strokePointCountCache = {};

  // Cached image of all completed strokes (for performance)
  ui.Image? _cachedStrokesImage;
  int _cachedStrokesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadFaceImage();
    _loadFaceMask();
  }

  @override
  void dispose() {
    _cachedStrokesImage?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(CharacterCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.design.characterId != widget.design.characterId) {
      _loadFaceMask();
    }
    if (oldWidget.design.faceImageBytes != widget.design.faceImageBytes) {
      _loadFaceImage();
    }
    // Clear caches when strokes change
    if (oldWidget.design.strokes.length != widget.design.strokes.length) {
      _fillStrokeKeysCache.clear();
      _strokePathCache.clear();
      _strokePointCountCache.clear();
      // Invalidate cached image when strokes change
      _cachedStrokesImage?.dispose();
      _cachedStrokesImage = null;
      _cachedStrokesCount = 0;
    }

    // Invalidate path cache for strokes that have changed
    for (final stroke in widget.design.strokes) {
      final cachedPointCount = _strokePointCountCache[stroke];
      if (cachedPointCount != null &&
          cachedPointCount != stroke.points.length) {
        _strokePathCache.remove(stroke);
        _strokePointCountCache.remove(stroke);
      }
    }
  }

  Future<void> _loadFaceImage() async {
    if (widget.design.faceImageBytes == null) {
      setState(() {
        _faceImage = null;
      });
      return;
    }

    try {
      final codec = await ui.instantiateImageCodec(
        widget.design.faceImageBytes!,
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _faceImage = frame.image;
        });
      }
    } catch (e) {
      debugPrint('Failed to load face image: $e');
      if (mounted) {
        setState(() {
          _faceImage = null;
        });
      }
    }
  }

  Future<void> _loadFaceMask() async {
    try {
      // Load the mask image for the current character using the characterMask property
      final maskPath = widget.design.characterMask;

      final byteData = await rootBundle.load(maskPath);
      final codec = await ui.instantiateImageCodec(
        byteData.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _faceMaskImage = frame.image;
        });
      }
    } catch (e) {
      debugPrint('Failed to load face mask: $e');
      if (mounted) {
        setState(() {
          _faceMaskImage = null;
        });
      }
    }
  }

  /// Determines if the supplied point lies on the drawable (white) region
  bool _canDrawAt(Offset position, Size canvasSize) {
    if (position.dx < 0 ||
        position.dy < 0 ||
        position.dx > canvasSize.width ||
        position.dy > canvasSize.height) {
      return false;
    }
    return _drawablePath?.contains(position) ?? false;
  }

  /// Checks if the stroke area (considering stroke width) is on white
  /// Samples multiple points around the stroke center to ensure no overlap
  bool _canDrawStrokeAt(Offset center, double strokeWidth, Size canvasSize) {
    final radius = strokeWidth / 2;

    // Check the center point
    if (!_canDrawAt(center, canvasSize)) {
      return false;
    }

    // Sample points around the circle to check if stroke area overlaps black
    // Check 8 points around the circle (every 45 degrees)
    for (int i = 0; i < 8; i++) {
      final angle = (i * 45) * math.pi / 180; // Convert to radians
      final checkPoint = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      if (!_canDrawAt(checkPoint, canvasSize)) {
        return false; // Stroke area overlaps black
      }
    }

    return true;
  }

  /// Checks if a point is covered by any existing stroke (acts as a boundary)
  /// If fillColor is provided, only blocks if the existing stroke has a different color
  bool _isPointCoveredByStroke(
    Offset point,
    Size canvasSize, [
    DrawStroke? excludeStroke,
    int? fillColor,
  ]) {
    final threshold =
        4.0 / 2 + 1.0; // Max stroke width threshold (fill uses 4.0)

    for (final stroke in widget.design.strokes) {
      if (stroke.points.isEmpty) continue;
      if (stroke == excludeStroke)
        continue; // Exclude the fill stroke from boundary check

      // Quick bounding box check - skip if point is far from stroke bounds
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;

      // Check if this is a fill stroke (strokeWidth 4.0 and many points)
      final isFillStroke =
          stroke.strokeWidth == 4.0 && stroke.points.length > 100;

      // For fill strokes, use more samples for accurate bounding box
      if (isFillStroke) {
        // Sample more points for accurate bounding box
        final sampleSize = 50;
        final step = (stroke.points.length / sampleSize).floor().clamp(
          1,
          stroke.points.length,
        );
        for (int i = 0; i < stroke.points.length; i += step) {
          final p = stroke.points[i];
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
      } else {
        // For small strokes, check all points
        for (final p in stroke.points) {
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
      }

      // Expand bounds by threshold
      minX -= threshold;
      maxX += threshold;
      minY -= threshold;
      maxY += threshold;

      // Skip if point is outside bounding box
      if (point.dx < minX ||
          point.dx > maxX ||
          point.dy < minY ||
          point.dy > maxY) {
        continue;
      }

      // Check if point is within stroke width distance of the stroke path
      final strokeWidth = stroke.strokeWidth;
      final strokeThreshold = strokeWidth / 2 + 1.0; // Add small buffer

      if (isFillStroke) {
        // For fill strokes, use cached key set for fast O(1) lookup
        // Build cache if not exists
        if (!_fillStrokeKeysCache.containsKey(stroke)) {
          final keySet = <int>{};
          final step = 2.0;
          final canvasArea = canvasSize.width * canvasSize.height;

          // Generate keys using same logic as fill algorithm
          int posKey(Offset p) {
            final x = (p.dx / step).round();
            final y = (p.dy / step).round();
            return (x * (canvasArea > 500000 ? 200000 : 100000) + y).toInt();
          }

          // Add all fill points to the set
          for (final fillPoint in stroke.points) {
            keySet.add(posKey(fillPoint));
          }
          _fillStrokeKeysCache[stroke] = keySet;
        }

        final fillKeys = _fillStrokeKeysCache[stroke]!;
        final step = 2.0;
        final canvasArea = canvasSize.width * canvasSize.height;

        // Generate key for query point using same logic
        int posKey(Offset p) {
          final x = (p.dx / step).round();
          final y = (p.dy / step).round();
          return (x * (canvasArea > 500000 ? 200000 : 100000) + y).toInt();
        }

        // Check if point key exists in fill stroke (exact match)
        final pointKey = posKey(point);
        bool pointInStroke = fillKeys.contains(pointKey);

        // Also check nearby points (within stroke width) to handle edge cases
        if (!pointInStroke) {
          final nearbyOffsets = [
            Offset(2, 0),
            Offset(-2, 0),
            Offset(0, 2),
            Offset(0, -2),
          ];
          for (final offset in nearbyOffsets) {
            final nearbyKey = posKey(point + offset);
            if (fillKeys.contains(nearbyKey)) {
              pointInStroke = true;
              break;
            }
          }
        }

        // If point is in this fill stroke, decide whether to block based on color
        if (pointInStroke) {
          // If fillColor is provided and colors are different, allow (will replace old fill)
          if (fillColor != null && stroke.color != fillColor) {
            continue; // Skip this stroke, allow the new fill to replace it
          }
          // Otherwise block (same color or no fillColor provided)
          return true;
        }
      } else {
        // For small strokes, check all segments and points
        for (int i = 0; i < stroke.points.length - 1; i++) {
          final p1 = stroke.points[i];
          final p2 = stroke.points[i + 1];

          final lineVec = p2 - p1;
          final pointVec = point - p1;
          final lineLength = lineVec.distance;

          if (lineLength < 0.1) {
            final dist = (point - p1).distance;
            if (dist <= strokeThreshold) return true;
          } else {
            final t =
                (pointVec.dx * lineVec.dx + pointVec.dy * lineVec.dy) /
                (lineLength * lineLength);
            final clampedT = t.clamp(0.0, 1.0);
            final closestPoint =
                p1 + Offset(lineVec.dx * clampedT, lineVec.dy * clampedT);
            final dist = (point - closestPoint).distance;
            if (dist <= strokeThreshold) return true;
          }
        }

        // Also check distance to individual points
        for (final strokePoint in stroke.points) {
          final dist = (point - strokePoint).distance;
          if (dist <= strokeThreshold) return true;
        }
      }
    }

    return false;
  }

  /// Performs flood fill asynchronously with progressive rendering for instant feedback.
  Future<void> _performFloodFillAsync(
    Offset startPos,
    Color fillColor,
    Size canvasSize,
  ) async {
    if (!_canDrawAt(startPos, canvasSize) ||
        _isPointCoveredByStroke(startPos, canvasSize, null, fillColor.value)) {
      widget.onAfterFill?.call();
      return;
    }

    // Create fill stroke but don't add to list yet (to avoid self-detection as boundary)
    final fillStroke = DrawStroke(
      points: [],
      color: fillColor.value,
      strokeWidth: 4.0,
      isEraser: false,
    );

    // Track if stroke was added for progressive rendering
    var strokeAdded = false;

    // Compute and add points progressively
    await _computeFloodFillPointsProgressive(
      startPos,
      canvasSize,
      fillStroke,
      fillColor: fillColor.value,
      onFirstChunk: () {
        // Add stroke to list on first chunk for progressive rendering
        if (!strokeAdded && fillStroke.points.isNotEmpty) {
          widget.design.strokes.add(fillStroke);
          strokeAdded = true;
        }
      },
    );

    if (!mounted) {
      widget.onAfterFill?.call();
      return;
    }

    // Ensure stroke is added if it has points (in case no chunks were processed)
    if (fillStroke.points.isNotEmpty && !strokeAdded) {
      widget.design.strokes.add(fillStroke);
    }

    if (mounted) {
      setState(() {});
    }
    widget.onAfterFill?.call();
  }

  /// Computes flood fill points progressively, updating the stroke as it goes.
  Future<void> _computeFloodFillPointsProgressive(
    Offset startPos,
    Size canvasSize,
    DrawStroke fillStroke, {
    int? fillColor,
    VoidCallback? onFirstChunk,
  }) async {
    // Adaptive step size based on canvas size
    final canvasArea = canvasSize.width * canvasSize.height;
    final step = 2.0; // Use 2.0 for all devices to ensure complete coverage
    final updateChunkSize =
        canvasArea > 500000 ? 200 : 150; // Points before UI update
    final maxPoints = canvasArea > 500000 ? 25000 : 15000;

    final visited = <int>{};
    final queue = <Offset>[startPos];
    var queueIndex = 0;
    var pointsAdded = 0;
    var lastUIUpdate = 0;

    int posKey(Offset p) {
      final x = (p.dx / step).round();
      final y = (p.dy / step).round();
      return (x * (canvasArea > 500000 ? 200000 : 100000) + y).toInt();
    }

    while (queueIndex < queue.length && fillStroke.points.length < maxPoints) {
      final current = queue[queueIndex++];
      final key = posKey(current);

      if (visited.contains(key)) continue;
      if (!_canDrawAt(current, canvasSize)) continue;
      if (_isPointCoveredByStroke(current, canvasSize, fillStroke, fillColor))
        continue;

      visited.add(key);
      fillStroke.points.add(current);
      pointsAdded++;

      final neighbors = [
        Offset(current.dx + step, current.dy),
        Offset(current.dx - step, current.dy),
        Offset(current.dx, current.dy + step),
        Offset(current.dx, current.dy - step),
      ];

      for (final neighbor in neighbors) {
        if (neighbor.dx >= 0 &&
            neighbor.dy >= 0 &&
            neighbor.dx < canvasSize.width &&
            neighbor.dy < canvasSize.height) {
          final neighborKey = posKey(neighbor);
          if (!visited.contains(neighborKey)) {
            queue.add(neighbor);
          }
        }
      }

      // Update UI progressively for instant visual feedback
      if (pointsAdded >= updateChunkSize) {
        pointsAdded = 0;
        // Call callback on first chunk to add stroke for progressive rendering
        if (onFirstChunk != null &&
            fillStroke.points.length >= updateChunkSize) {
          onFirstChunk();
        }
        if (mounted) {
          setState(() {});
        }
        await Future.delayed(Duration.zero);
        if (!mounted) {
          return;
        }
        lastUIUpdate = fillStroke.points.length;
      }
    }

    // Final UI update
    if (mounted && fillStroke.points.length > lastUIUpdate) {
      setState(() {});
    }
  }

  /// Caches all completed strokes as an image for performance
  /// This way we only need to draw the current stroke, not all strokes
  Future<void> _cacheCompletedStrokes(Size size) async {
    if (widget.design.strokes.isEmpty) {
      _cachedStrokesImage?.dispose();
      _cachedStrokesImage = null;
      _cachedStrokesCount = 0;
      return;
    }

    // Only cache if we have completed strokes
    final completedStrokesCount = widget.design.strokes.length;
    if (completedStrokesCount == _cachedStrokesCount) {
      return; // Already cached
    }

    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);

      // Draw all completed strokes
      final strokesToCache = widget.design.strokes;

      for (final stroke in strokesToCache) {
        final strokePaint =
            Paint()
              ..color = Color(stroke.color)
              ..strokeWidth = stroke.strokeWidth
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round
              ..blendMode = BlendMode.srcOver; // Use normal blend mode for eraser (white color restores base)

        if (stroke.points.isNotEmpty) {
          final path = Path();

          if (stroke.points.length == 1) {
            final point = stroke.points.first;
            path.moveTo(point.dx, point.dy);
            path.lineTo(point.dx + 0.1, point.dy + 0.1);
          } else if (stroke.points.length == 2) {
            path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
            path.lineTo(stroke.points[1].dx, stroke.points[1].dy);
          } else {
            path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
            for (int i = 0; i < stroke.points.length - 1; i++) {
              final p0 = i > 0 ? stroke.points[i - 1] : stroke.points[i];
              final p1 = stroke.points[i];
              final p2 = stroke.points[i + 1];
              final p3 =
                  i < stroke.points.length - 2
                      ? stroke.points[i + 2]
                      : stroke.points[i + 1];

              final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
              final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
              final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
              final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

              path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
            }
          }

          canvas.drawPath(path, strokePaint);
        }
      }

      final picture = recorder.endRecording();
      final oldImage = _cachedStrokesImage;
      _cachedStrokesImage = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      _cachedStrokesCount = completedStrokesCount;

      // Dispose old image
      oldImage?.dispose();

      if (mounted) {
        setState(() {}); // Trigger rebuild to show cached image
      }
    } catch (e) {
      debugPrint('Error caching strokes: $e');
    }
  }

  /// Filters stroke points to remove those that are on non-white areas
  /// Checks the stroke area (not just the point) to prevent edge overlaps
  void _filterStrokePoints(DrawStroke stroke, Size canvasSize) {
    if (stroke.points.isEmpty) return;

    // Create a new list with only points where the stroke area is on white
    final filteredPoints = <Offset>[];
    for (final point in stroke.points) {
      if (_canDrawStrokeAt(point, stroke.strokeWidth, canvasSize)) {
        filteredPoints.add(point);
      }
    }

    // Replace the points list with filtered points
    stroke.points.clear();
    stroke.points.addAll(filteredPoints);

    // If all points were removed, remove the stroke entirely
    if (stroke.points.isEmpty && widget.design.strokes.contains(stroke)) {
      widget.design.strokes.remove(stroke);
    }
  }

  /// Builds the drawable path for the character based on reference polygons
  void _buildDrawablePath(Size canvasSize) {
    final polygons = CharacterShapeLibrary.polygonsFor(
      widget.design.characterId,
    );
    final path = Path()..fillType = PathFillType.evenOdd;

    // Calculate scale factor for tablets - make character smaller on large screens
    final canvasArea = canvasSize.width * canvasSize.height;
    final scaleFactor = canvasArea > 500000 ? 1.0 : 1.0; // 75% size on tablets
    final scaledWidth = canvasSize.width * scaleFactor;
    final scaledHeight = canvasSize.height * scaleFactor;

    // Center the character in the canvas
    final offsetX = (canvasSize.width - scaledWidth) / 2;
    final offsetY = (canvasSize.height - scaledHeight) / 2;

    for (final polygon in polygons) {
      if (polygon.isEmpty) {
        continue;
      }
      final firstPoint = polygon.first;
      path.moveTo(
        firstPoint.dx * scaledWidth + offsetX,
        firstPoint.dy * scaledHeight + offsetY,
      );

      for (int i = 1; i < polygon.length; i++) {
        final point = polygon[i];
        path.lineTo(
          point.dx * scaledWidth + offsetX,
          point.dy * scaledHeight + offsetY,
        );
      }
      path.close();
    }

    _drawablePath = path;
    _facePath = null;
    _scarfPath = null;
    _buttonPaths = <Path>[];
    _braceletPath = null;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (size.width == 0 || size.height == 0) {
          return const SizedBox.shrink();
        }
        // Build drawable path for the character
        _buildDrawablePath(size);

        // Store canvas size for filtering
        _canvasSize = size;

        return GestureDetector(
          onPanStart: (d) {
            // Allow pan start only if the touched pixel is white.
            if (_canDrawAt(d.localPosition, size)) {
              _isDrawing = true;
              widget.onPanStart?.call(d.localPosition);
            } else {
              _isDrawing = false;
            }
          },
          onPanUpdate: (d) {
            final canDraw = _canDrawAt(d.localPosition, size);

            if (canDraw && _isDrawing) {
              // Continue drawing on white area
              widget.onPanUpdate?.call(d.localPosition);
            } else if (canDraw && !_isDrawing) {
              // Moved from black to white - start new stroke
              _isDrawing = true;
              widget.onPanStart?.call(d.localPosition);
            } else if (!canDraw && _isDrawing) {
              // Moved from white to black - end current stroke
              _isDrawing = false;
              widget.onPanEnd?.call();
            }
            // If !canDraw && !_isDrawing, do nothing (already on black)
          },
          onPanEnd: (_) {
            if (_isDrawing) {
              widget.onPanEnd?.call();
              // Filter the last stroke to remove points on non-white areas
              if (widget.design.strokes.isNotEmpty && _canvasSize != null) {
                final lastStroke = widget.design.strokes.last;
                _filterStrokePoints(lastStroke, _canvasSize!);
                // Cache completed strokes as image for performance
                _cacheCompletedStrokes(size);
                setState(() {}); // Trigger rebuild after filtering
              }
            }
            _isDrawing = false;
          },
          onTapDown: (details) {
            final p = details.localPosition;

            // Handle fill tool - perform flood fill (priority)
            if (!_isFilling &&
                widget.onTap != null &&
                widget.fillColor != null &&
                _canDrawAt(p, size)) {
              _isFilling = true;
              // Save history synchronously before fill to ensure clean undo
              widget.onBeforeFill?.call();
              // Start fill operation (history is already saved synchronously)
              _performFloodFillAsync(
                p,
                widget.fillColor!,
                size,
              ).whenComplete(() => _isFilling = false);
              return;
            }

            // Handle sticker placement - allow placing on top of existing stickers
            // Check this BEFORE checking for existing sticker taps
            if (widget.onTap != null && _canDrawAt(p, size)) {
              widget.onTap!.call(p);
              return;
            }

            // Check if tap is on an existing sticker (only if not placing new sticker)
            // This allows selecting existing stickers when not in placement mode
            if (widget.onStickerTap != null) {
              // Check stickers in reverse order (top to bottom)
              for (int i = widget.design.stickers.length - 1; i >= 0; i--) {
                final sticker = widget.design.stickers[i];
                final tp = TextPainter(
                  text: TextSpan(
                    text: sticker.label,
                    style: const TextStyle(fontSize: 48),
                  ),
                  textDirection: TextDirection.ltr,
                )..layout();

                // Calculate sticker bounds considering scale and rotation
                final scaledWidth = tp.width * sticker.scale;
                final scaledHeight = tp.height * sticker.scale;
                final stickerRect = Rect.fromCenter(
                  center: sticker.position,
                  width: scaledWidth,
                  height: scaledHeight,
                );

                // Simple bounding box check (rotation makes this approximate)
                if (stickerRect.contains(p)) {
                  widget.onStickerTap!.call(sticker);
                  return;
                }
              }
            }

            // Handle part tapping
            if (widget.onTapPart == null) return;
            if (_facePath?.contains(p) == true) {
              widget.onTapPart!.call('face');
              return;
            }
            if (_scarfPath?.contains(p) == true) {
              widget.onTapPart!.call('scarf');
              return;
            }
            for (final bp in _buttonPaths) {
              if (bp.contains(p)) {
                widget.onTapPart!.call('buttons');
                return;
              }
            }
            if (_braceletPath?.contains(p) == true) {
              widget.onTapPart!.call('bracelet');
              return;
            }
          },
          child: RepaintBoundary(
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: CustomPaint(
                painter: _CharacterPainter(
                  widget.design,
                  drawablePath: _drawablePath,
                  facePath: _facePath,
                  scarfPath: _scarfPath,
                  buttonPaths: _buttonPaths,
                  braceletPath: _braceletPath,
                  faceImage: _faceImage,
                  faceMaskImage: _faceMaskImage,
                  strokeVersion: widget.design.strokes.length,
                  lastStrokePointVersion:
                      widget.design.strokes.isNotEmpty
                          ? widget.design.strokes.last.points.length
                          : 0,
                  stickerVersion: widget.design.stickers.length,
                  strokePathCache: _strokePathCache,
                  strokePointCountCache: _strokePointCountCache,
                  cachedStrokesImage: _cachedStrokesImage,
                  cachedStrokesCount: _cachedStrokesCount,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CharacterPainter extends CustomPainter {
  _CharacterPainter(
    this.design, {
    this.drawablePath,
    this.facePath,
    this.scarfPath,
    required this.buttonPaths,
    this.braceletPath,
    this.faceImage,
    this.faceMaskImage,
    required this.strokeVersion,
    required this.lastStrokePointVersion,
    required this.stickerVersion,
    this.strokePathCache,
    this.strokePointCountCache,
    this.cachedStrokesImage,
    this.cachedStrokesCount = 0,
  });
  final CharacterDesign design;
  final Path? drawablePath;
  final Path? facePath;
  final Path? scarfPath;
  final List<Path> buttonPaths;
  final Path? braceletPath;
  final ui.Image? faceImage;
  final ui.Image? faceMaskImage;
  final int strokeVersion;
  final int lastStrokePointVersion;
  final int stickerVersion;
  final Map<DrawStroke, Path>? strokePathCache;
  final Map<DrawStroke, int>? strokePointCountCache;
  final ui.Image? cachedStrokesImage;
  final int cachedStrokesCount;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale factor for tablets - same as character path
    final canvasArea = size.width * size.height;
    final scaleFactor = canvasArea > 500000 ? 1.0 : 1.0; // 75% size on tablets
    final scaledWidth = size.width * scaleFactor;
    final scaledHeight = size.height * scaleFactor;
    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    // Draw black background - only in the scaled character area for tablets
    final bgPaint = Paint()..color = Colors.black;
    if (canvasArea > 500000) {
      // On tablets, draw black background only in the character area
      canvas.drawRect(
        Rect.fromLTWH(offsetX, offsetY, scaledWidth, scaledHeight),
        bgPaint,
      );
    } else {
      // On phones, draw full black background
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);
    }

    // Draw character shape in white (drawable areas)
    if (drawablePath != null && size.width > 0 && size.height > 0) {
      final characterPaint =
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.fill;
      canvas.drawPath(drawablePath!, characterPaint);
    }

    // Use drawable path as clipping path
    final clipPath = drawablePath;

    // Draw cached strokes image first (all completed strokes)
    // If cache exists, only draw strokes that aren't cached yet
    final strokesToDraw = <DrawStroke>[];

    if (cachedStrokesImage != null && cachedStrokesCount > 0) {
      // Draw cached image of completed strokes
      if (clipPath != null) {
        canvas.save();
        canvas.clipPath(clipPath);
        canvas.drawImage(cachedStrokesImage!, Offset.zero, Paint());
        canvas.restore();
      } else {
        canvas.drawImage(cachedStrokesImage!, Offset.zero, Paint());
      }

      // Only draw strokes that aren't in the cache (new strokes)
      if (design.strokes.length > cachedStrokesCount) {
        strokesToDraw.addAll(design.strokes.skip(cachedStrokesCount));
      }
    } else {
      // Cache not built yet - draw all strokes normally
      // This happens on first paint or after cache invalidation
      strokesToDraw.addAll(design.strokes);
    }

    for (final stroke in strokesToDraw) {
      final strokePaint =
          Paint()
            ..color = Color(stroke.color)
            ..strokeWidth = stroke.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = BlendMode.srcOver; // Use normal blend mode for eraser (white color restores base)

      if (stroke.points.isNotEmpty) {
        // Build path for current stroke being drawn
        final path = Path();

        if (stroke.points.length == 1) {
          // Single point - use a tiny line segment to prevent overlap
          final point = stroke.points.first;
          path.moveTo(point.dx, point.dy);
          path.lineTo(point.dx + 0.1, point.dy + 0.1);
        } else if (stroke.points.length == 2) {
          // Two points - simple line
          path.moveTo(stroke.points[0].dx, stroke.points[0].dy);
          path.lineTo(stroke.points[1].dx, stroke.points[1].dy);
        } else {
          // Multiple points - use smooth curves (Catmull-Rom spline)
          final points = stroke.points;
          path.moveTo(points[0].dx, points[0].dy);

          for (int i = 0; i < points.length - 1; i++) {
            final p0 = i > 0 ? points[i - 1] : points[i];
            final p1 = points[i];
            final p2 = points[i + 1];
            final p3 = i < points.length - 2 ? points[i + 2] : points[i + 1];

            // Calculate control points for smooth Catmull-Rom spline
            final cp1x = p1.dx + (p2.dx - p0.dx) / 6.0;
            final cp1y = p1.dy + (p2.dy - p0.dy) / 6.0;
            final cp2x = p2.dx - (p3.dx - p1.dx) / 6.0;
            final cp2y = p2.dy - (p3.dy - p1.dy) / 6.0;

            // Use cubic bezier for smooth curves
            path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
          }
        }

        // Clip to white areas before drawing
        if (clipPath != null) {
          canvas.save();
          canvas.clipPath(clipPath);
          canvas.drawPath(path, strokePaint);
          canvas.restore();
        } else {
          canvas.drawPath(path, strokePaint);
        }
      }
    }

    // Draw stickers as text labels with clipping to white areas
    // (reusing clipPath created above for strokes)
    for (final sticker in design.stickers) {
      final tp = TextPainter(
        text: TextSpan(
          text: sticker.label,
          style: const TextStyle(fontSize: 48),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Clip sticker to white areas only
      if (clipPath != null) {
        canvas.save();
        canvas.clipPath(clipPath);
        canvas.translate(sticker.position.dx, sticker.position.dy);
        canvas.scale(sticker.scale);
        canvas.rotate(sticker.rotation);
        tp.paint(canvas, Offset.zero);
        canvas.restore();
      } else {
        canvas.save();
        canvas.translate(sticker.position.dx, sticker.position.dy);
        canvas.scale(sticker.scale);
        canvas.rotate(sticker.rotation);
        tp.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }

    // Draw face image clipped to mask shape in the black face area
    if (faceImage != null && faceMaskImage != null) {
      _drawFaceImageInPainter(canvas, size);
    }
  }

  /// Draws the face image clipped to the mask shape in the black face area
  /// The face image is already masked when captured, so we just need to position it correctly
  void _drawFaceImageInPainter(Canvas canvas, Size size) {
    // Calculate scale factor for tablets - same as character path
    final canvasArea = size.width * size.height;
    final scaleFactor = canvasArea > 500000 ? 1.0 : 1.0; // 75% size on tablets
    final scaledWidth = size.width * scaleFactor;
    final scaledHeight = size.height * scaleFactor;
    final offsetX = (size.width - scaledWidth) / 2;
    final offsetY = (size.height - scaledHeight) / 2;

    // Face area position in the canvas (black space for face)
    // Different characters have different face positions
    // Apply scale and offset to match character scaling
    double faceCenterX, faceCenterY, faceRadius;

    switch (design.characterId) {
      case 0: // Gingerbread man
        faceCenterX = scaledWidth * 0.33 + offsetX;
        faceCenterY = scaledHeight * 0.25 + offsetY;
        faceRadius = math.min(scaledWidth, scaledHeight) * 0.20;
        break;
      case 1: // Nutcracker
        faceCenterX = scaledWidth * 0.31 + offsetX;
        faceCenterY = scaledHeight * 0.14 + offsetY;
        faceRadius = math.min(scaledWidth, scaledHeight) * 0.17;
        break;
      case 2: // Santa
        faceCenterX = scaledWidth * 0.37 + offsetX;
        faceCenterY = scaledHeight * 0.27 + offsetY;
        faceRadius = math.min(scaledWidth, scaledHeight) * 0.25;
        break;

      case 3: // elf
        faceCenterX = scaledWidth * 0.29 + offsetX;
        faceCenterY = scaledHeight * 0.20 + offsetY;
        faceRadius = math.min(scaledWidth, scaledHeight) * 0.25;
        break;
      default:
        // Default to gingerbread man values
        faceCenterX = scaledWidth * 0.5 + offsetX;
        faceCenterY = scaledHeight * 0.25 + offsetY;
        faceRadius = math.min(scaledWidth, scaledHeight) * 0.10;
    }

    // Calculate face size
    final canvasFaceSize = faceRadius * 2; // Diameter

    // Calculate face image size to fit the face area
    // The face image is already masked, so we just need to scale it to fit
    final maskAspect = faceMaskImage!.width / faceMaskImage!.height;

    // Use the mask aspect to determine the display size (since face should match mask shape)
    double faceWidth, faceHeight;

    if (maskAspect > 1.0) {
      // Mask is wider - use width as reference
      faceWidth = canvasFaceSize;
      faceHeight = faceWidth / maskAspect;
    } else {
      // Mask is taller - use height as reference
      faceHeight = canvasFaceSize;
      faceWidth = faceHeight * maskAspect;
    }

    // Center the face in the face area
    final faceRect = Rect.fromCenter(
      center: Offset(faceCenterX, faceCenterY),
      width: faceWidth,
      height: faceHeight,
    );

    // Draw the face image (already masked, so just draw it directly)
    // The image should have transparent background if captured correctly
    final faceSourceRect = Rect.fromLTWH(
      0,
      0,
      faceImage!.width.toDouble(),
      faceImage!.height.toDouble(),
    );

    final facePaint = Paint()..filterQuality = FilterQuality.high;

    // Draw the face image - it should have transparent background
    canvas.drawImageRect(faceImage!, faceSourceRect, faceRect, facePaint);
  }

  @override
  bool shouldRepaint(covariant _CharacterPainter oldDelegate) {
    return oldDelegate.strokeVersion != strokeVersion ||
        oldDelegate.lastStrokePointVersion != lastStrokePointVersion ||
        oldDelegate.stickerVersion != stickerVersion ||
        oldDelegate.design != design ||
        oldDelegate.facePath != facePath ||
        oldDelegate.scarfPath != scarfPath ||
        oldDelegate.braceletPath != braceletPath ||
        oldDelegate.faceImage != faceImage ||
        oldDelegate.faceMaskImage != faceMaskImage ||
        oldDelegate.cachedStrokesImage != cachedStrokesImage ||
        oldDelegate.cachedStrokesCount != cachedStrokesCount;
  }
}
