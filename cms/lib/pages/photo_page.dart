import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import '../state/models.dart';
import 'editor_page.dart';

class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, required this.design});
  static const String routeName = '/photo';

  final CharacterDesign design;

  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isCapturing = false;
  ui.Image? _maskImage;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _initializeCamera();
    _loadMask();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No cameras available')));
        }
        return;
      }

      // Use front camera if available
      final frontCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();

      if (mounted && _controller != null && _controller!.value.isInitialized) {
        setState(() {
          _isInitialized = true;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera failed to initialize')),
          );
        }
      }
    } catch (e) {
      debugPrint('Camera initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error initializing camera: $e')),
        );
      }
    }
  }

  Future<void> _loadMask() async {
    try {
      // Use the new mask with transparent background and white shape
      final maskPath =
          widget.design.characterMask; //'assets/mask-gingerbreadman.png';
      final byteData = await rootBundle.load(maskPath);
      final codec = await ui.instantiateImageCodec(
        byteData.buffer.asUint8List(),
      );
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _maskImage = frame.image;
        });
      }
    } catch (e) {
      // Mask loading failed, continue without mask
      debugPrint('Failed to load mask: $e');
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await _controller!.takePicture();
      final imageBytes = await image.readAsBytes();

      // Apply mask to the captured image
      final maskedBytes = await _applyMask(imageBytes);

      if (maskedBytes != null && mounted) {
        widget.design.faceImageBytes = maskedBytes;
        widget.design.facePosition = const Offset(0, 0);
        widget.design.faceScale = 1.0;

        Navigator.of(
          context,
        ).pushNamed(EditorPage.routeName, arguments: widget.design);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error capturing image: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<Uint8List?> _applyMask(Uint8List imageBytes) async {
    try {
      // Decode the captured image
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      final capturedImage = frame.image;

      if (_maskImage == null) {
        // No mask available, return original image
        return imageBytes;
      }

      // Calculate the size for mapping (this represents the camera preview size)
      final size = Size(
        capturedImage.width.toDouble(),
        capturedImage.height.toDouble(),
      );

      // Calculate mask position and size to match camera preview overlay
      // Use the same sizing logic as the overlay painter
      final maskAspect = _maskImage!.width / _maskImage!.height;

      // Use the same sizing logic as the overlay
      // Calculate based on the smaller screen dimension to ensure it's always big enough
      final smallerDimension =
          size.width < size.height ? size.width : size.height;

      // Use a fixed minimum size or a percentage, whichever is bigger
      // Made smaller as requested
      final minPixelSize =
          300.0; // Minimum 300 pixels for a face to fit (reduced from 350)
      final percentageSize =
          smallerDimension *
          0.60; // 60% of smaller dimension (reduced from 0.70)
      final targetSize =
          minPixelSize > percentageSize ? minPixelSize : percentageSize;

      // But don't exceed the screen size
      final maxSize = smallerDimension * 0.70; // 70% max (reduced from 0.80)
      var finalTargetSize = targetSize > maxSize ? maxSize : targetSize;

      // Make mask 10% smaller
      const double maskScale = 0.75;
      finalTargetSize = finalTargetSize * maskScale;

      double maskWidth, maskHeight;
      double offsetX, offsetY;

      // Calculate size to ensure it's big enough for a face
      // Use the target size and maintain aspect ratio
      // Some characters (Santa, Elf) need their masks to be less wide
      final characterId = widget.design.characterId;
      double widthAdjustment = 1.0; // Default no adjustment

      if (characterId == 2 || characterId == 3) {
        // Santa (2) and Elf (3) - make mask less wide
        widthAdjustment = 0.85; // Reduce width by 15%
      }

      if (maskAspect > 1.0) {
        // Mask is wider - use target size for width, but adjust for certain characters
        maskWidth = finalTargetSize * widthAdjustment;
        maskHeight = maskWidth / maskAspect;
      } else {
        // Mask is taller - use target size for height
        maskHeight = finalTargetSize;
        maskWidth = maskHeight * maskAspect * widthAdjustment;
      }

      // Ensure minimum size - also reduced by 10% to allow the mask to be smaller
      final minPixelSizeForCheck = 225.0; // Reduced by 10% from 250 (250 * 0.9)
      final minPercentageSize =
          smallerDimension * 0.45; // Reduced by 10% from 0.50 (0.50 * 0.9)
      final minSize =
          minPixelSizeForCheck > minPercentageSize
              ? minPixelSizeForCheck
              : minPercentageSize;

      if (maskWidth < minSize) {
        maskWidth = minSize;
        maskHeight = maskWidth / maskAspect;
      }
      if (maskHeight < minSize) {
        maskHeight = minSize;
        maskWidth = maskHeight * maskAspect;
      }

      // Add horizontal padding for Santa and Elf to make mask less wide
      if (characterId == 2 || characterId == 3) {
        // Reduce the mask width further by adding padding
        final paddingAmount =
            size.width * 0.08; // 8% padding on each side = 16% total reduction
        maskWidth = maskWidth - (paddingAmount * 2);
        // Recalculate height to maintain aspect ratio
        maskHeight = maskWidth / maskAspect;
      }

      // Center the mask
      offsetX = (size.width - maskWidth) / 2;
      offsetY = (size.height - maskHeight) / 2;

      // Create a new image that's just the mask size, not the full captured image
      // This ensures we only capture what's inside the mask
      final outputWidth = maskWidth.round();
      final outputHeight = maskHeight.round();

      // Create a new recorder for the cropped output
      final outputRecorder = ui.PictureRecorder();
      final outputCanvas = Canvas(outputRecorder);

      // Draw transparent background (no background - will be transparent)
      // Don't draw anything - the background will be transparent by default

      // Calculate the source rect from the captured image that corresponds to the mask area
      // The mask is centered on the screen, so we need to extract the corresponding area
      final previewSize = _controller?.value.previewSize;
      double capturedScaleX, capturedScaleY;

      if (previewSize != null) {
        // Map from preview size to captured image size
        // Account for potential rotation (camera images are often rotated)
        capturedScaleX = capturedImage.width / previewSize.height;
        capturedScaleY = capturedImage.height / previewSize.width;
      } else {
        // Fallback: use the size parameter (which should match preview)
        capturedScaleX = capturedImage.width / size.width;
        capturedScaleY = capturedImage.height / size.height;
      }

      // Calculate the source rect in the captured image that corresponds to the mask area
      final sourceX = offsetX * capturedScaleX;
      final sourceY = offsetY * capturedScaleY;
      final sourceWidth = maskWidth * capturedScaleX;
      final sourceHeight = maskHeight * capturedScaleY;

      final capturedSourceRect = Rect.fromLTWH(
        sourceX,
        sourceY,
        sourceWidth,
        sourceHeight,
      );

      // Destination rect is the full output image (mask size)
      final outputRect = Rect.fromLTWH(
        0,
        0,
        outputWidth.toDouble(),
        outputHeight.toDouble(),
      );
      final maskSourceRect = Rect.fromLTWH(
        0,
        0,
        _maskImage!.width.toDouble(),
        _maskImage!.height.toDouble(),
      );

      // Draw the cropped portion of the captured image
      outputCanvas.saveLayer(outputRect, Paint());
      outputCanvas.drawImageRect(
        capturedImage,
        capturedSourceRect,
        outputRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      // Apply mask using blend mode - white areas in mask keep image, transparent areas remove it
      final maskPaint = Paint()..blendMode = BlendMode.dstIn;

      outputCanvas.drawImageRect(
        _maskImage!,
        maskSourceRect,
        outputRect,
        maskPaint,
      );
      outputCanvas.restore();

      final outputPicture = outputRecorder.endRecording();
      final maskedImage = await outputPicture.toImage(
        outputWidth,
        outputHeight,
      );

      final byteData = await maskedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );

      if (byteData != null) {
        return byteData.buffer.asUint8List();
      }
    } catch (e) {
      debugPrint('Error applying mask: $e');
    }

    // Return original if mask application fails
    return imageBytes;
  }

  @override
  void dispose() {
    _controller?.dispose();
    // Restore orientation settings when leaving this page
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Your Photo'),
        backgroundColor: const Color(0xFF5522A3),
      ),
      backgroundColor: Colors.black,
      body:
          _isInitialized &&
                  _controller != null &&
                  _controller!.value.isInitialized
              ? Stack(
                fit: StackFit.expand,
                children: [
                  // Camera preview - must be first in stack
                  //Positioned.fill(child: CameraPreview(_controller!)),
                  Center(
                    child:
                        _controller == null
                            ? Container()
                            : FittedBox(
                              fit:
                                  BoxFit
                                      .cover, // or BoxFit.contain depending on what you want
                              child: SizedBox(
                                width: _controller!.value.previewSize!.height,
                                height: _controller!.value.previewSize!.width,
                                child: CameraPreview(_controller!),
                              ),
                            ),
                  ),
                  // Mask overlay - on top of camera preview (only if mask is loaded)
                  if (_maskImage != null)
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: true,
                        child: CustomPaint(
                          painter: _MaskOverlayPainter(
                            maskImage: _maskImage!,
                            characterId: widget.design.characterId,
                          ),
                        ),
                      ),
                    ),
                  // Instructions
                  Positioned(
                    top: 100,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Position your face inside the shape',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Capture button
                  Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child:
                          _isCapturing
                              ? const CircularProgressIndicator(
                                color: Colors.white,
                              )
                              : FloatingActionButton.extended(
                                onPressed: _captureImage,
                                backgroundColor: Colors.white,
                                icon: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.black,
                                ),
                                label: const Text(
                                  'Capture',
                                  style: TextStyle(color: Colors.black),
                                ),
                              ),
                    ),
                  ),
                ],
              )
              : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      _controller == null
                          ? 'Initializing camera...'
                          : 'Waiting for camera...',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
    );
  }
}

/// Custom painter to draw the mask overlay on camera preview
/// Shows a semi-transparent overlay with a cutout where the face should be
class _MaskOverlayPainter extends CustomPainter {
  _MaskOverlayPainter({required this.maskImage, required this.characterId});

  final ui.Image maskImage;
  final int characterId;

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate scale to fit mask while maintaining aspect ratio
    // Make it bigger so a face can fit comfortably
    final maskAspect = maskImage.width / maskImage.height;

    // Make the mask size appropriate for a face to fit comfortably
    // The mask image might have transparent padding, so we need to scale it appropriately
    // Use a fixed minimum size in pixels to ensure it's always big enough for a face
    final smallerDimension =
        size.width < size.height ? size.width : size.height;

    // Use a fixed minimum size or a percentage, whichever is bigger
    // Made smaller as requested
    final minPixelSize =
        300.0; // Minimum 300 pixels for a face to fit (reduced from 350)
    final percentageSize =
        smallerDimension * 0.60; // 60% of smaller dimension (reduced from 0.70)
    final targetSize =
        minPixelSize > percentageSize ? minPixelSize : percentageSize;

    // But don't exceed the screen size
    final maxSize = smallerDimension * 0.70; // 70% max (reduced from 0.80)
    var finalTargetSize = targetSize > maxSize ? maxSize : targetSize;

    // Make mask 10% smaller
    const double maskScale = 0.75;
    finalTargetSize = finalTargetSize * maskScale;

    double maskWidth, maskHeight;
    double offsetX, offsetY;

    // Calculate size to ensure it's big enough for a face
    // Use the target size and maintain aspect ratio
    // Some characters (Santa, Elf) need their masks to be less wide
    double widthAdjustment = 1.0; // Default no adjustment

    if (characterId == 2 || characterId == 3) {
      // Santa (2) and Elf (3) - make mask less wide
      widthAdjustment = 0.75; // Reduce width by 15%
    }

    if (maskAspect > 1.0) {
      // Mask is wider - use target size for width, but adjust for certain characters
      maskWidth = finalTargetSize * widthAdjustment;
      maskHeight = maskWidth / maskAspect;
    } else {
      // Mask is taller - use target size for height
      maskHeight = finalTargetSize;
      maskWidth = maskHeight * maskAspect * widthAdjustment;
    }

    // Ensure minimum size - also reduced by 10% to allow the mask to be smaller
    final minPixelSizeForCheck = 225.0; // Reduced by 10% from 250 (250 * 0.9)
    final minPercentageSize =
        smallerDimension * 0.45; // Reduced by 10% from 0.50 (0.50 * 0.9)
    final minSize =
        minPixelSizeForCheck > minPercentageSize
            ? minPixelSizeForCheck
            : minPercentageSize;

    if (maskWidth < minSize) {
      maskWidth = minSize;
      maskHeight = maskWidth / maskAspect;
    }
    if (maskHeight < minSize) {
      maskHeight = minSize;
      maskWidth = maskHeight * maskAspect;
    }

    // Add horizontal padding for Santa and Elf to make mask less wide
    if (characterId == 2 || characterId == 3) {
      // Reduce the mask width further by adding padding
      final paddingAmount =
          size.width * 0.08; // 8% padding on each side = 16% total reduction
      maskWidth = maskWidth - (paddingAmount * 2);
      // Recalculate height to maintain aspect ratio
      maskHeight = maskWidth / maskAspect;
    }

    // Center the mask
    offsetX = (size.width - maskWidth) / 2;
    offsetY = (size.height - maskHeight) / 2;

    // Draw semi-transparent overlay everywhere (darker areas outside mask)
    final overlayPaint = Paint()..color = Colors.black.withOpacity(0.5);

    // Create a cutout using the mask - white areas in mask = transparent (show camera)
    // The mask has transparent background and white shape where face should be
    // We want to create a "hole" where the white shape is, so the camera shows through
    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, size.height), Paint());

    // Draw the overlay in the layer
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), overlayPaint);

    // Use the mask to cut out the face area (create a transparent hole)
    // The mask has white shape on transparent background
    // We want to cut out where the mask is white (non-transparent)
    final maskRect = Rect.fromLTWH(offsetX, offsetY, maskWidth, maskHeight);
    final maskSourceRect = Rect.fromLTWH(
      0,
      0,
      maskImage.width.toDouble(),
      maskImage.height.toDouble(),
    );

    // Use dstOut to cut out the white areas of the mask (where face should be)
    // This creates a transparent window where the mask is white, showing the camera
    // The mask's alpha channel will determine what gets cut out
    final maskPaint = Paint()..blendMode = BlendMode.dstOut;

    canvas.drawImageRect(maskImage, maskSourceRect, maskRect, maskPaint);
    canvas.restore();

    // Draw only a white outline/border of the mask shape as a guide
    // We'll create a stroke effect by drawing the mask edges
    final maskRectForOutline = Rect.fromLTWH(
      offsetX,
      offsetY,
      maskWidth,
      maskHeight,
    );
    final maskSourceRectForOutline = Rect.fromLTWH(
      0,
      0,
      maskImage.width.toDouble(),
      maskImage.height.toDouble(),
    );

    // Draw the mask shape as a white outline guide
    // Technique: draw the full mask in white, then cut out a slightly smaller version
    // This leaves only the border/outline visible
    canvas.saveLayer(
      Rect.fromLTWH(offsetX - 3, offsetY - 3, maskWidth + 6, maskHeight + 6),
      Paint(),
    );

    // Draw the mask shape in white (full size)
    final whiteMaskPaint =
        Paint()
          ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn);
    canvas.drawImageRect(
      maskImage,
      maskSourceRectForOutline,
      maskRectForOutline,
      whiteMaskPaint,
    );

    // Now use dstOut to create an inner cutout, leaving only the border
    // Calculate a slightly smaller rect for the inner cutout (creates the outline effect)
    final strokeWidth = 3.0;
    final scaleFactor = 1.0 - (strokeWidth * 2 / maskWidth);
    final innerWidth = maskWidth * scaleFactor;
    final innerHeight = maskHeight * scaleFactor;
    final innerOffsetX = offsetX + (maskWidth - innerWidth) / 2;
    final innerOffsetY = offsetY + (maskHeight - innerHeight) / 2;

    final innerRect = Rect.fromLTWH(
      innerOffsetX,
      innerOffsetY,
      innerWidth,
      innerHeight,
    );
    final innerMaskSourceRect = Rect.fromLTWH(
      (maskImage.width.toDouble() - maskImage.width.toDouble() * scaleFactor) /
          2,
      (maskImage.height.toDouble() -
              maskImage.height.toDouble() * scaleFactor) /
          2,
      maskImage.width.toDouble() * scaleFactor,
      maskImage.height.toDouble() * scaleFactor,
    );

    final innerMaskPaint = Paint()..blendMode = BlendMode.dstOut;
    canvas.drawImageRect(
      maskImage,
      innerMaskSourceRect,
      innerRect,
      innerMaskPaint,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskOverlayPainter oldDelegate) =>
      oldDelegate.maskImage != maskImage ||
      oldDelegate.characterId != characterId;
}
