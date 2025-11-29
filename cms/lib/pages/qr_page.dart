import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cms/state/models.dart';
import 'package:cms/widgets/my_loading.dart';
import 'package:cms/widgets/my_message.dart';
import 'package:flutter/material.dart';
import 'package:niimbot_label_printer/niimbot_label_printer.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/gradient_header.dart';

class QRPage extends StatefulWidget {
  const QRPage({super.key, required this.url, required this.characterDesign});
  static const String routeName = '/qr';

  final String url;
  final CharacterDesign characterDesign;

  @override
  State<QRPage> createState() => _QRPageState();
}

class _QRPageState extends State<QRPage> {
  // Password to access home - you can change this
  static const String _password = '8833';

  final NiimbotLabelPrinter _niimbotLabelPrinterPlugin = NiimbotLabelPrinter();

  // Label dimensions (in pixels, assuming 8 pixels per mm)
  int _labelWidth = 400; // Default: 50mm
  int _labelHeight = 240; // Default: 30mm

  @override
  void initState() {
    super.initState();
  }

  Future<void> _showPasswordDialog() async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? errorMessage;

        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Enter Password'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        border: const OutlineInputBorder(),
                        errorText: errorMessage,
                      ),
                      onSubmitted: (value) {
                        _validatePassword(
                          value,
                          passwordController,
                          setDialogState,
                          (msg) {
                            errorMessage = msg;
                          },
                        );
                      },
                      autofocus: true,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      _validatePassword(
                        passwordController.text,
                        passwordController,
                        setDialogState,
                        (msg) {
                          errorMessage = msg;
                        },
                      );
                    },
                    child: const Text('Submit'),
                  ),
                ],
              ),
        );
      },
    );
  }

  void _validatePassword(
    String enteredPassword,
    TextEditingController controller,
    StateSetter setDialogState,
    void Function(String?) setErrorMessage,
  ) {
    if (enteredPassword.isEmpty) {
      setDialogState(() {
        setErrorMessage('Password cannot be empty');
      });
      return;
    }

    if (enteredPassword == _password) {
      Navigator.pop(context); // Close password dialog
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      setDialogState(() {
        setErrorMessage('Incorrect password');
      });
      controller.clear();
      // Show error message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Incorrect password. Please try again.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showLabelSizeDialog() async {
    // Predefined label sizes (width x height in mm)
    final predefinedSizes = [
      {'label': '50 x 30', 'width': 50, 'height': 30},
      {'label': '60 x 30', 'width': 60, 'height': 30},
      {'label': '60 x 40', 'width': 60, 'height': 40},
      {'label': '40 x 30', 'width': 40, 'height': 30},
      {'label': '40 x 80', 'width': 40, 'height': 80},
      {'label': 'Custom', 'width': 0, 'height': 0}, // Custom option
    ];

    final widthController = TextEditingController(
      text: (_labelWidth ~/ 8).toString(),
    );
    final heightController = TextEditingController(
      text: (_labelHeight ~/ 8).toString(),
    );
    final pixelsPerMmController = TextEditingController(text: '8');
    String? selectedSize;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        String? errorMessage;

        return StatefulBuilder(
          builder:
              (context, setDialogState) => AlertDialog(
                title: const Text('Enter Paper Size'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Select a predefined size or enter custom dimensions:',
                        style: TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedSize,
                        decoration: const InputDecoration(
                          labelText: 'Predefined Sizes',
                          border: OutlineInputBorder(),
                        ),
                        items:
                            predefinedSizes.map((size) {
                              return DropdownMenuItem<String>(
                                value: size['label'] as String,
                                child: Text(size['label'] as String),
                              );
                            }).toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSize = value;
                            if (value != 'Custom') {
                              final selected = predefinedSizes.firstWhere(
                                (s) => s['label'] == value,
                              );
                              widthController.text =
                                  (selected['width'] as int).toString();
                              heightController.text =
                                  (selected['height'] as int).toString();
                              errorMessage = null;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: widthController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Width (mm)',
                          border: OutlineInputBorder(),
                          hintText: '50',
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSize = 'Custom';
                            errorMessage = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: heightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Height (mm)',
                          border: OutlineInputBorder(),
                          hintText: '30',
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            selectedSize = 'Custom';
                            errorMessage = null;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      // TextField(
                      //   controller: pixelsPerMmController,
                      //   keyboardType: TextInputType.number,
                      //   decoration: const InputDecoration(
                      //     labelText: 'Pixels per mm',
                      //     border: OutlineInputBorder(),
                      //     hintText: '8',
                      //     helperText: 'Usually 8 pixels per mm',
                      //   ),
                      // ),
                      if (errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () {
                      final width = int.tryParse(widthController.text);
                      final height = int.tryParse(heightController.text);
                      final pixelsPerMm = int.tryParse(
                        pixelsPerMmController.text,
                      );

                      if (width == null || width <= 0) {
                        setDialogState(() {
                          errorMessage = 'Please enter a valid width';
                        });
                        return;
                      }

                      if (height == null || height <= 0) {
                        setDialogState(() {
                          errorMessage = 'Please enter a valid height';
                        });
                        return;
                      }

                      if (pixelsPerMm == null || pixelsPerMm <= 0) {
                        setDialogState(() {
                          errorMessage = 'Please enter valid pixels per mm';
                        });
                        return;
                      }

                      Navigator.pop(context, true);
                    },
                    child: const Text('Continue'),
                  ),
                ],
              ),
        );
      },
    );

    if (result == true) {
      final width = int.tryParse(widthController.text);
      final height = int.tryParse(heightController.text);
      final pixelsPerMm = int.tryParse(pixelsPerMmController.text);

      if (width != null && height != null && pixelsPerMm != null) {
        setState(() {
          _labelWidth = width * pixelsPerMm;
          _labelHeight = height * pixelsPerMm;
        });
        // Proceed with printing
        await _printQRCode();
      }
    }
  }

  Future<void> _printQRCode() async {
    try {
      // Check if printer is connected
      final bool isConnected = await _niimbotLabelPrinterPlugin.isConnected();

      if (!isConnected) {
        MessageUtils.showErrorMessage(context, 'Printer not connected.');
        return;
      }

      // Show loading dialog
      LoadingDialog.show(context);

      double dpi = 203;
      double mmPerInch = 25.4;

      double paperWidthMm = (60).toDouble();
      double paperHeightMm = (40).toDouble();

      int calculateWidth = ((paperWidthMm / mmPerInch) * dpi).round();
      int calculateHeight = ((paperHeightMm / mmPerInch) * dpi).round();

      // Generate QR code image centered on label using user-provided dimensions
      ui.Image labelImage = await generateCenteredQRCodeImage(
        widget.url,
        characterDesign: widget.characterDesign,
        labelWidth: calculateWidth,
        labelHeight: calculateHeight,
      );

      //Make it more good looking
      labelImage = await convertToBlackAndWhite(labelImage);

      // Convert image to rawRgba format (required by Niimbot printer)
      ByteData? byteData = await labelImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );

      if (byteData == null) {
        LoadingDialog.hide(context);
        MessageUtils.showErrorMessage(context, 'Failed to process image data.');
        return;
      }

      List<int> bytesImage = byteData.buffer.asUint8List().toList();

      // Create print data for Niimbot printer
      Map<String, dynamic> datosImagen = {
        "bytes": bytesImage,
        "width": labelImage.width,
        "height": labelImage.height,
        "rotate": false,
        "invertColor": false,
        "density": 5, // Print density (1-5, higher = darker)
        "labelType": 1, // Label type
      };

      PrintData printData = PrintData.fromMap(datosImagen);

      // Send to printer with timeout
      await _niimbotLabelPrinterPlugin
          .send(printData)
          .timeout(const Duration(seconds: 10));

      // Verify connection after printing
      final bool checkConnection =
          await _niimbotLabelPrinterPlugin.isConnected();

      LoadingDialog.hide(context);

      if (!checkConnection) {
        MessageUtils.showErrorMessage(
          context,
          'Printer disconnected. Please reconnect.',
        );
      } else {
        MessageUtils.showSuccessMessage(
          context,
          'QR Code printed successfully!',
        );
      }
    } catch (e) {
      LoadingDialog.hide(context);
      MessageUtils.showErrorMessage(
        context,
        'Printing failed: ${e.toString()}',
      );
    }
  }

  Future<ui.Image> generateQRCodeImage(String qrData) async {
    final qrValidationResult = QrValidator.validate(
      data: qrData,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );

    if (qrValidationResult.status != QrValidationStatus.valid) {
      throw Exception('QR code generation failed');
    }

    final painter = QrPainter.withQr(
      qr: qrValidationResult.qrCode!,
      color: Colors.black,
      emptyColor: Colors.white,
      gapless: true,
    );

    // Generate QR code image - size optimized for label printer
    // 200x200 pixels works well for most label sizes
    return painter.toImage(200);
  }

  /// Generates a label image with QR code centered on it
  Future<ui.Image> generateCenteredQRCodeImage(
    String qrData, {
    required CharacterDesign characterDesign,
    required int labelWidth,
    required int labelHeight,
  }) async {
    // Generate the QR code image
    ui.Image qrImage = await generateQRCodeImage(qrData);

    // Create a canvas for the full label
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Fill background with white
    final backgroundPaint = Paint()..color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, labelWidth.toDouble(), labelHeight.toDouble()),
      backgroundPaint,
    );

    // Create text for character name and username above QR code
    final greetingText = characterDesign.characterName;
    final textStyle = const TextStyle(
      color: Colors.black,
      fontSize: 20,
      fontWeight: FontWeight.bold,
    );
    final textPainter = TextPainter(
      text: TextSpan(text: greetingText, style: textStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(maxWidth: labelWidth.toDouble());

    // Create text for username below QR code
    final userNameText = characterDesign.userName;
    final userNameTextStyle = const TextStyle(
      color: Colors.black,
      fontSize: 20,
      fontWeight: FontWeight.normal,
    );
    final userNameTextPainter = TextPainter(
      text: TextSpan(text: userNameText, style: userNameTextStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    userNameTextPainter.layout(maxWidth: labelWidth.toDouble());

    // Calculate spacing between elements (15 pixels)
    const spacing = 15.0;
    final qrSize = qrImage.width.toDouble();

    // Total height needed: top text + spacing + QR code + spacing + username
    final totalContentHeight =
        textPainter.height +
        spacing +
        qrSize +
        spacing +
        userNameTextPainter.height;

    // Calculate starting Y position to center everything vertically
    final startY = (labelHeight - totalContentHeight) / 2;

    // Calculate position for top text (centered horizontally)
    final textXOffset = (labelWidth - textPainter.width) / 2;
    final textYOffset = startY;

    // Draw the greeting text above QR code
    textPainter.paint(canvas, Offset(textXOffset, textYOffset));

    // Calculate position to center the QR code horizontally
    final xOffset = (labelWidth - qrSize) / 2;
    final qrYOffset = startY + textPainter.height + spacing;

    // Draw the QR code centered on the canvas
    canvas.drawImage(qrImage, Offset(xOffset, qrYOffset), Paint());

    // Calculate position for username text below QR code (centered horizontally)
    final userNameXOffset = (labelWidth - userNameTextPainter.width) / 2;
    final userNameYOffset = qrYOffset + qrSize + spacing;

    // Draw the username text below the QR code
    userNameTextPainter.paint(canvas, Offset(userNameXOffset, userNameYOffset));

    // Convert canvas to image
    final picture = recorder.endRecording();
    final labelImage = await picture.toImage(labelWidth, labelHeight);

    return labelImage;
  }

  Future<ui.Image> convertToBlackAndWhite(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final Uint8List pixels = byteData!.buffer.asUint8List();

    for (int i = 0; i < pixels.length; i += 4) {
      final r = pixels[i];
      final g = pixels[i + 1];
      final b = pixels[i + 2];

      final gray = (r + g + b) ~/ 3;
      final bw = gray < 160 ? 0 : 255;

      pixels[i] = bw; // R
      pixels[i + 1] = bw; // G
      pixels[i + 2] = bw; // B
      // Alpha remains unchanged
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      image.width,
      image.height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) => completer.complete(img),
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5522A3),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const GradientHeader(text: 'Your Design is Ready!', fontSize: 30),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Scan the QR code to view your creation',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: widget.url,
                            version: QrVersions.auto,
                            size: 280.0,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            widget.url,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _printQRCode,
                              icon: const Icon(Icons.print),
                              label: const Text('Print QR Code'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF5522A3),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _showPasswordDialog,
                              icon: const Icon(Icons.home),
                              label: const Text('Back to Home'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 32,
                                  vertical: 16,
                                ),
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF5522A3),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
