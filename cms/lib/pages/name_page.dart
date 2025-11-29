import 'package:cms/widgets/gradient_header.dart';
import 'package:cms/widgets/my_loading.dart';
import 'package:cms/widgets/my_message.dart';
import 'package:flutter/material.dart';
import 'package:niimbot_label_printer/niimbot_label_printer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'character_select_page.dart';

class NamePage extends StatefulWidget {
  const NamePage({super.key});

  @override
  State<NamePage> createState() => _NamePageState();
}

class _NamePageState extends State<NamePage> {
  final TextEditingController _controller = TextEditingController();
  final NiimbotLabelPrinter _niimbotLabelPrinterPlugin = NiimbotLabelPrinter();
  List<BluetoothDevice> _devices = [];
  String macConnection = '';
  String deviceName = '';
  bool connecting = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // @override
  // initState() {
  //   super.initState();
  //   //requestNearbyDevicesPermission();
  // }

  // Future<bool> requestNearbyDevicesPermission() async {
  //   var scanStatus = await Permission.bluetoothScan.status;
  //   var connectStatus = await Permission.bluetoothConnect.status;

  //   // If permission is already granted, return true
  //   if (scanStatus.isGranted && connectStatus.isGranted) {
  //     print("Permission already granted");
  //     return true;
  //   }

  //   // If permission is denied but not permanently, request again
  //   if (scanStatus.isDenied || connectStatus.isDenied) {
  //     scanStatus = await Permission.bluetoothScan.request();
  //     connectStatus = await Permission.bluetoothConnect.request();
  //   }

  //   // If granted after request, return true
  //   if (scanStatus.isGranted && connectStatus.isGranted) {
  //     print("Nearby devices permission granted");
  //     return true;
  //   }

  //   // If permanently denied, show a dialog directing the user to settings
  //   if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
  //     openAppSettings(); // Open device settings so the user can enable it manually
  //     return false;
  //   }

  //   print("Permission denied");
  //   return false;
  // }

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

  Future<void> selectPrinter() async {
    final bool permissionIsGranted =
        await _niimbotLabelPrinterPlugin.requestPermissionGrant();

    if (permissionIsGranted) {
      final bool isBluetoothEnabled =
          await _niimbotLabelPrinterPlugin.bluetoothIsEnabled();
      if (isBluetoothEnabled) {
        // Fetch paired devices
        final List<BluetoothDevice> result =
            await _niimbotLabelPrinterPlugin.getPairedDevices();
        _devices = result;
        // Show dialog
        showDialog(
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
                      title: Text(
                        device.name.isNotEmpty ? device.name : 'Unnamed',
                      ),
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
                        } else {
                          // If not connected, try to connect
                          LoadingDialog.show(context);
                          bool result = await _niimbotLabelPrinterPlugin
                              .connect(device);

                          if (result) {
                            setState(() {
                              macConnection =
                                  device
                                      .address; // Set macConnection on success
                              deviceName = device.name;
                              connecting = false;
                              LoadingDialog.hide;
                              Navigator.of(context).pop(); // Close the dialog
                            });
                          } else {
                            MessageUtils.showErrorMessage(
                              context,
                              'Error Connecting',
                            );
                            LoadingDialog.hide;
                            Navigator.of(context).pop(); // Close the dialog
                          }
                        }

                        Navigator.of(context).pop(); // Close the dialog
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // Close the dialog
                  },
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      } else {
        MessageUtils.showErrorMessage(context, 'Please Turn on your Bluetooth');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5522A3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF5522A3),
        actions: [
          IconButton(
            onPressed: () async {
              bool granted = await requestNearbyDevicesPermission(context);
              if (granted) {
                await selectPrinter();
              } else {
                print("Permission denied");
              }
            },
            icon: const Icon(Icons.print_outlined, color: Colors.white),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GradientHeader(text: 'Christmas', fontSize: 45),
                GradientHeader(text: 'Coloring', fontSize: 45),
                const Center(
                  child: Text(
                    'Create your festive masterpiece',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  style: TextStyle(color: Colors.white),
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: 'What is your name?',
                    border: OutlineInputBorder(),
                    labelStyle: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () {
                    final name = _controller.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter your name')),
                      );
                      return;
                    }
                    Navigator.of(context)
                        .pushNamed(
                          CharacterSelectPage.routeName,
                          arguments: name,
                        )
                        .then((_) {
                          _controller.clear();
                        });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(25),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 110, 20, 246),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Text(
                        'Start Creating →',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
