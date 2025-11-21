import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/gradient_header.dart';

class QRPage extends StatefulWidget {
  const QRPage({super.key, required this.url});
  static const String routeName = '/qr';

  final String url;

  @override
  State<QRPage> createState() => _QRPageState();
}

class _QRPageState extends State<QRPage> {
  // Password to access home - you can change this
  static const String _password = '8833';

  Future<void> _showPasswordDialog() async {
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        String? errorMessage;
        
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF5522A3),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const GradientHeader(
              text: 'Your Design is Ready!',
              fontSize: 30,
            ),
            const SizedBox(height: 8),
            const Center(
              child: Text(
                'Scan the QR code to view your creation',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
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

