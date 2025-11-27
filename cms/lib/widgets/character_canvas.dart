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

  @override
  State<CharacterCanvas> createState() => _CharacterCanvasState();
}

class _CharacterCanvasState extends State<CharacterCanvas> {
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

  @override
  void initState() {
    super.initState();
    _loadFaceImage();
    _loadFaceMask();
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
  bool _isPointCoveredByStroke(Offset point, Size canvasSize) {
    for (final stroke in widget.design.strokes) {
      if (stroke.points.isEmpty) continue;

      // Check if point is within stroke width distance of the stroke path
      final strokeWidth = stroke.strokeWidth;
      final threshold = strokeWidth / 2 + 1.0; // Add small buffer

      // Check distance to each segment of the stroke
      for (int i = 0; i < stroke.points.length - 1; i++) {
        final p1 = stroke.points[i];
        final p2 = stroke.points[i + 1];

        // Calculate distance from point to line segment
        final lineVec = p2 - p1;
        final pointVec = point - p1;
        final lineLength = lineVec.distance;

        if (lineLength < 0.1) {
          // Very short segment, check distance to point
          final dist = (point - p1).distance;
          if (dist <= threshold) return true;
        } else {
          // Project point onto line segment
          final t =
              (pointVec.dx * lineVec.dx + pointVec.dy * lineVec.dy) /
              (lineLength * lineLength);
          final clampedT = t.clamp(0.0, 1.0);
          final closestPoint =
              p1 + Offset(lineVec.dx * clampedT, lineVec.dy * clampedT);
          final dist = (point - closestPoint).distance;
          if (dist <= threshold) return true;
        }
      }

      // Also check distance to individual points (for single points or stroke caps)
      for (final strokePoint in stroke.points) {
        final dist = (point - strokePoint).distance;
        if (dist <= threshold) return true;
      }
    }

    return false;
  }

  /// Performs flood fill starting from the given position
  /// Fills all connected white areas with the given color
  /// Respects existing strokes as boundaries
  List<Offset> _performFloodFill(
    Offset startPos,
    Color fillColor,
    Size canvasSize,
  ) {
    if (!_canDrawAt(startPos, canvasSize)) {
      return []; // Can't fill if starting point is not on white
    }

    // Check if starting point is already covered by a stroke
    if (_isPointCoveredByStroke(startPos, canvasSize)) {
      return []; // Can't fill if starting point is on an existing stroke
    }

    final filledPoints = <Offset>[];
    final visited = <String>{}; // Track visited positions as "x,y" strings
    final queue = <Offset>[startPos];
    final step = 2.0; // Step size for sampling points

    // Convert canvas position to a key for visited tracking
    String posKey(Offset p) =>
        '${(p.dx / step).round()},${(p.dy / step).round()}';

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final key = posKey(current);

      if (visited.contains(key)) continue;
      if (!_canDrawAt(current, canvasSize)) continue; // Skip black areas
      if (_isPointCoveredByStroke(current, canvasSize))
        continue; // Skip areas covered by strokes (boundaries)

      visited.add(key);
      filledPoints.add(current);

      // Add neighboring points to queue (4-directional)
      final neighbors = [
        Offset(current.dx + step, current.dy), // Right
        Offset(current.dx - step, current.dy), // Left
        Offset(current.dx, current.dy + step), // Down
        Offset(current.dx, current.dy - step), // Up
      ];

      for (final neighbor in neighbors) {
        final neighborKey = posKey(neighbor);
        if (!visited.contains(neighborKey) &&
            neighbor.dx >= 0 &&
            neighbor.dy >= 0 &&
            neighbor.dx < canvasSize.width &&
            neighbor.dy < canvasSize.height) {
          queue.add(neighbor);
        }
      }
    }

    return filledPoints;
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

    for (final polygon in polygons) {
      if (polygon.isEmpty) {
        continue;
      }
      final firstPoint = polygon.first;
      path.moveTo(
        firstPoint.dx * canvasSize.width,
        firstPoint.dy * canvasSize.height,
      );

      for (int i = 1; i < polygon.length; i++) {
        final point = polygon[i];
        path.lineTo(point.dx * canvasSize.width, point.dy * canvasSize.height);
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
                setState(() {}); // Trigger rebuild after filtering
              }
            }
            _isDrawing = false;
          },
          onTapDown: (details) {
            final p = details.localPosition;

            // Handle fill tool - perform flood fill (priority)
            if (widget.onTap != null &&
                widget.fillColor != null &&
                _canDrawAt(p, size)) {
              // Save history before fill operation
              widget.onBeforeFill?.call();

              // Perform flood fill
              final fillPoints = _performFloodFill(p, widget.fillColor!, size);
              if (fillPoints.isNotEmpty) {
                // Create a fill stroke from the filled points
                widget.design.strokes.add(
                  DrawStroke(
                    points: fillPoints,
                    color: widget.fillColor!.value,
                    strokeWidth: 4.0, // Overlapping strokes for solid fill
                    isEraser: false,
                  ),
                );
                setState(() {}); // Trigger rebuild
                // Notify parent that fill completed so it can update UI (e.g., UNDO button)
                widget.onAfterFill?.call();
              }
              // Don't call onTap for fill - it's already handled
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

  @override
  void paint(Canvas canvas, Size size) {
    // Always draw black background first
    final bgPaint = Paint()..color = Colors.black;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

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

    // Draw existing strokes with clipping to white areas only
    for (final stroke in design.strokes) {
      final strokePaint =
          Paint()
            ..color = Color(stroke.color)
            ..strokeWidth = stroke.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;

      if (stroke.points.isNotEmpty) {
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
          path.moveTo(stroke.points[0].dx, stroke.points[0].dy);

          for (int i = 0; i < stroke.points.length - 1; i++) {
            final p0 = i > 0 ? stroke.points[i - 1] : stroke.points[i];
            final p1 = stroke.points[i];
            final p2 = stroke.points[i + 1];
            final p3 =
                i < stroke.points.length - 2
                    ? stroke.points[i + 2]
                    : stroke.points[i + 1];

            // Calculate control points for smooth Catmull-Rom spline
            // This creates smooth curves between points
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
      _drawFaceImage(canvas, size);
    }
  }

  /// Draws the face image clipped to the mask shape in the black face area
  /// The face image is already masked when captured, so we just need to position it correctly
  void _drawFaceImage(Canvas canvas, Size size) {
    // Face area position in the canvas (black space for face)
    // Different characters have different face positions
    double faceCenterX, faceCenterY, faceRadius;

    switch (design.characterId) {
      case 0: // Gingerbread man
        faceCenterX = size.width * 0.33;
        faceCenterY = size.height * 0.25;
        faceRadius = math.min(size.width, size.height) * 0.20;
        break;
      case 1: // Nutcracker
        faceCenterX = size.width * 0.31;
        faceCenterY = size.height * 0.14;
        faceRadius = math.min(size.width, size.height) * 0.17;
        break;
      case 2: // Santa
        faceCenterX = size.width * 0.37;
        faceCenterY = size.height * 0.27;
        faceRadius = math.min(size.width, size.height) * 0.25;
        break;

      case 3: // elf
        faceCenterX = size.width * 0.29;
        faceCenterY = size.height * 0.20;
        faceRadius = math.min(size.width, size.height) * 0.25;
        break;
      default:
        // Default to gingerbread man values
        faceCenterX = size.width * 0.5;
        faceCenterY = size.height * 0.25;
        faceRadius = math.min(size.width, size.height) * 0.10;
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
        oldDelegate.faceMaskImage != faceMaskImage;
  }
}
