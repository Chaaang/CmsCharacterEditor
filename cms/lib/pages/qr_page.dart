import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cms/state/models.dart';
import 'package:cms/state/printer_state.dart';
import 'package:cms/widgets/my_loading.dart';
import 'package:cms/widgets/my_message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:niimbot_label_printer/niimbot_label_printer.dart';
import 'package:permission_handler/permission_handler.dart';
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

  List<BluetoothDevice> _devices = [];
  String macConnection = '';
  String deviceName = '';
  bool connecting = false;

  @override
  void initState() {
    super.initState();
    //_loadLastConnectedPrinter();
  }

  // Load the last connected printer from paired devices
  // Future<void> _loadLastConnectedPrinter() async {
  //   try {
  //     // Check if currently connected - if so, we can try to identify the device later
  //     final bool isConnected = await _niimbotLabelPrinterPlugin.isConnected();
  //     if (isConnected) {
  //       // Printer is already connected, we'll try to reconnect to any available device if it disconnects
  //     }
  //   } catch (e) {
  //     debugPrint('Error loading last connected printer: $e');
  //   }
  // }

  // Show printer selection dialog (similar to name_page.dart)
  // Future<bool> _showPrinterSelectionDialog() async {
  //   try {
  //     final bool permissionIsGranted =
  //         await _niimbotLabelPrinterPlugin.requestPermissionGrant();

  //     if (!permissionIsGranted) {
  //       MessageUtils.showErrorMessage(
  //         context,
  //         'Bluetooth permission is required to connect to printer.',
  //       );
  //       return false;
  //     }

  //     final bool isBluetoothEnabled =
  //         await _niimbotLabelPrinterPlugin.bluetoothIsEnabled();
  //     if (!isBluetoothEnabled) {
  //       MessageUtils.showErrorMessage(context, 'Please turn on your Bluetooth');
  //       return false;
  //     }

  //     // Fetch paired devices
  //     final List<BluetoothDevice> devices =
  //         await _niimbotLabelPrinterPlugin.getPairedDevices();

  //     if (devices.isEmpty) {
  //       MessageUtils.showErrorMessage(
  //         context,
  //         'No paired devices found. Please pair a printer first.',
  //       );
  //       return false;
  //     }

  //     // Check current connection
  //     bool isCurrentlyConnected =
  //         await _niimbotLabelPrinterPlugin.isConnected();
  //     String? currentMacAddress;

  //     // First check shared state from name_page
  //     if (PrinterState.connectedMacAddress != null) {
  //       currentMacAddress = PrinterState.connectedMacAddress;
  //       // Try to find the device in the list to update _lastConnectedPrinter
  //       try {
  //         final matchedDevice = devices.firstWhere(
  //           (d) => d.address == PrinterState.connectedMacAddress,
  //         );
  //         _lastConnectedPrinter = matchedDevice;
  //       } catch (e) {
  //         // Device not found in list, but we have the MAC address
  //       }
  //     } else if (isCurrentlyConnected && _lastConnectedPrinter != null) {
  //       currentMacAddress = _lastConnectedPrinter!.address;
  //     }

  //     // Show dialog
  //     final bool? connected = await showDialog<bool>(
  //       context: context,
  //       builder: (BuildContext context) {
  //         return AlertDialog(
  //           title: const Center(child: Text('Select Bluetooth Printer')),
  //           content: SizedBox(
  //             width: double.maxFinite,
  //             child: ListView.builder(
  //               shrinkWrap: true,
  //               itemCount: devices.length,
  //               itemBuilder: (BuildContext context, int index) {
  //                 BluetoothDevice device = devices[index];
  //                 final isSelected = device.address == currentMacAddress;
  //                 return ListTile(
  //                   selected: isSelected,
  //                   title: Text(
  //                     device.name.isNotEmpty ? device.name : 'Unnamed',
  //                   ),
  //                   subtitle: Text(device.address),
  //                   trailing:
  //                       isSelected
  //                           ? const Text(
  //                             'Disconnect',
  //                             style: TextStyle(color: Colors.red),
  //                           )
  //                           : const Text(
  //                             'Connect',
  //                             style: TextStyle(color: Colors.blue),
  //                           ),
  //                   onTap: () async {
  //                     if (isSelected) {
  //                       // Already connected - disconnect it
  //                       LoadingDialog.show(context);
  //                       await _niimbotLabelPrinterPlugin.disconnect();
  //                       LoadingDialog.hide(context);

  //                       setState(() {
  //                         _lastConnectedPrinter = null;
  //                       });

  //                       // Clear shared state
  //                       PrinterState.clearConnection();

  //                       Navigator.of(context).pop(false);
  //                       return;
  //                     }

  //                     // Try to connect
  //                     LoadingDialog.show(context);
  //                     bool result = await _niimbotLabelPrinterPlugin.connect(
  //                       device,
  //                     );
  //                     LoadingDialog.hide(context);

  //                     if (result) {
  //                       _lastConnectedPrinter =
  //                           device; // Store for future reference
  //                       // Update shared state
  //                       PrinterState.setConnected(device.address, device.name);
  //                       Navigator.of(context).pop(true);
  //                     } else {
  //                       MessageUtils.showErrorMessage(
  //                         context,
  //                         'Failed to connect to printer',
  //                       );
  //                       Navigator.of(context).pop(false);
  //                     }
  //                   },
  //                 );
  //               },
  //             ),
  //           ),
  //           actions: [
  //             TextButton(
  //               onPressed: () {
  //                 Navigator.of(context).pop(false);
  //               },
  //               child: const Text('Cancel'),
  //             ),
  //           ],
  //         );
  //       },
  //     );

  //     return connected ?? false;
  //   } catch (e) {
  //     MessageUtils.showErrorMessage(
  //       context,
  //       'Error showing printer selection: ${e.toString()}',
  //     );
  //     return false;
  //   }
  // }

  Future<bool> selectPrinter() async {
    final bool permissionIsGranted =
        await _niimbotLabelPrinterPlugin.requestPermissionGrant();

    if (!permissionIsGranted) {
      MessageUtils.showErrorMessage(
        context,
        'Bluetooth permission is required to connect to printer.',
      );
      return false;
    }

    final bool isBluetoothEnabled =
        await _niimbotLabelPrinterPlugin.bluetoothIsEnabled();
    if (!isBluetoothEnabled) {
      MessageUtils.showErrorMessage(context, 'Please Turn on your Bluetooth');
      return false;
    }

    // Fetch paired devices
    final List<BluetoothDevice> result =
        await _niimbotLabelPrinterPlugin.getPairedDevices();
    _devices = result;

    if (_devices.isEmpty) {
      MessageUtils.showErrorMessage(
        context,
        'No paired devices found. Please pair a printer first.',
      );
      return false;
    }

    // Show dialog and wait for result
    final bool? connected = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Center(child: Text('Select Bluetooth Printer')),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _devices.length,
              itemBuilder: (BuildContext context, int index) {
                BluetoothDevice device = _devices[index];
                return ListTile(
                  selected: device.address == macConnection,
                  title: Text(device.name.isNotEmpty ? device.name : 'Unnamed'),
                  subtitle: Text(device.address),
                  trailing:
                      macConnection != device.address
                          ? const Text(
                            'Connect',
                            style: TextStyle(color: Colors.blue),
                          )
                          : const Text(
                            'Disconnect',
                            style: TextStyle(color: Colors.blue),
                          ),
                  onTap: () async {
                    setState(() {
                      connecting = true;
                    });

                    // Check if already connected
                    if (macConnection == device.address) {
                      // If already connected, try to disconnect
                      await _niimbotLabelPrinterPlugin.disconnect();
                      setState(() {
                        macConnection =
                            ""; // Clear macConnection when disconnected
                        deviceName = 'Not Connected';
                        connecting = false;
                      });
                      // Clear connection from shared state
                      PrinterState.clearConnection();
                      Navigator.of(
                        context,
                      ).pop(false); // Return false (disconnected)
                      return;
                    }

                    // If not connected, try to connect
                    LoadingDialog.show(context);
                    bool result = await _niimbotLabelPrinterPlugin.connect(
                      device,
                    );
                    LoadingDialog.hide(context);

                    if (result) {
                      setState(() {
                        macConnection =
                            device.address; // Set macConnection on success
                        deviceName = device.name;
                        connecting = false;
                      });
                      // Store connection in shared state
                      PrinterState.setConnected(device.address, device.name);
                      Navigator.of(
                        context,
                      ).pop(true); // Return true (connected)
                    } else {
                      MessageUtils.showErrorMessage(
                        context,
                        'Error Connecting',
                      );
                      Navigator.of(
                        context,
                      ).pop(false); // Return false (connection failed)
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false); // Return false (cancelled)
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );

    return connected ?? false;
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

  Future<void> _printQRCode() async {
    if (kIsWeb) {
      MessageUtils.showErrorMessage(
        context,
        'Printer is not available on web.',
      );
      return;
    }

    try {
      // Check if printer is connected
      bool isConnected = await _niimbotLabelPrinterPlugin.isConnected();

      // If not connected, show printer selection dialog
      if (!isConnected) {
        final connected = await selectPrinter();
        if (!connected) {
          return; // User cancelled or connection failed
        }
        // Verify connection after selection
        isConnected = await _niimbotLabelPrinterPlugin.isConnected();
        if (!isConnected) {
          MessageUtils.showErrorMessage(
            context,
            'Failed to connect to printer. Please try again.',
          );
          return;
        }
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
      var result = await _niimbotLabelPrinterPlugin
          .send(printData)
          .timeout(const Duration(seconds: 10));

      if (result == false) {
        print('Printing failed.');
      } else {
        print('Printing successful.');
      }

      // Verify connection after printing
      bool checkConnection = await _niimbotLabelPrinterPlugin.isConnected();

      LoadingDialog.hide(context);

      if (!checkConnection) {
        // Printer disconnected, show printer selection dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Printer disconnected. Please reconnect to continue.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        final reconnected = await selectPrinter();

        if (reconnected) {
          MessageUtils.showSuccessMessage(
            context,
            'QR Code printed successfully! (Reconnected to printer)',
          );
        } else {
          MessageUtils.showErrorMessage(
            context,
            'QR Code printed but printer disconnected. Please reconnect to print again.',
          );
        }
      } else {
        MessageUtils.showSuccessMessage(
          context,
          'QR Code printed successfully!',
        );
      }
    } catch (e) {
      LoadingDialog.hide(context);

      // Check if error is due to disconnection, show printer selection dialog
      final bool isConnected = await _niimbotLabelPrinterPlugin.isConnected();
      if (!isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Printing failed. Printer disconnected. Please reconnect.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
        final reconnected = await selectPrinter();

        if (reconnected) {
          MessageUtils.showErrorMessage(
            context,
            'Printing failed but printer reconnected. Please try printing again.',
          );
        } else {
          MessageUtils.showErrorMessage(
            context,
            'Printing failed: ${e.toString()}. Please reconnect to printer.',
          );
        }
      } else {
        MessageUtils.showErrorMessage(
          context,
          'Printing failed: ${e.toString()}',
        );
      }
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

  Future<bool> _onWillPop() async {
    // Show exit confirmation dialog
    final shouldExit = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Exit?'),
            content: const Text('Are you sure you want to exit?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
    );

    return shouldExit ?? false;
  }

  Future<bool> requestNearbyDevicesPermission(BuildContext context) async {
    var scanStatus = await Permission.bluetoothScan.status;
    var connectStatus = await Permission.bluetoothConnect.status;

    // Already granted
    if (scanStatus.isGranted && connectStatus.isGranted) {
      return true;
    }

    // Permanently denied → go to settings
    if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // Show explanation dialog first
    bool proceed = await showPermissionExplanationDialog(context);
    if (!proceed) return false;

    // Request permissions
    scanStatus = await Permission.bluetoothScan.request();
    connectStatus = await Permission.bluetoothConnect.request();

    // Return true only if both granted
    return scanStatus.isGranted && connectStatus.isGranted;
  }

  Future<bool> showPermissionExplanationDialog(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text("Bluetooth Permission Needed"),
                content: const Text(
                  "This app needs Bluetooth access to connect and print to your device. "
                  "Please allow the permission when prompted.",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text("Continue"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final shouldExit = await _onWillPop();
          if (shouldExit && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF5522A3),
        appBar: AppBar(
          backgroundColor: const Color(0xFF5522A3),
          actions: [
            IconButton(
              onPressed: () async {
                bool granted = await requestNearbyDevicesPermission(context);
                if (granted) {
                  await selectPrinter();
                }
              },
              icon: const Icon(Icons.print_outlined, color: Colors.white),
            ),
          ],
        ),
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
      ),
    );
  }
}
