/// Simple class to share printer connection state between pages
class PrinterState {
  static String? connectedMacAddress;
  static String? connectedPrinterName;

  static void setConnected(String macAddress, String printerName) {
    connectedMacAddress = macAddress;
    connectedPrinterName = printerName;
  }

  static void clearConnection() {
    connectedMacAddress = null;
    connectedPrinterName = null;
  }

  static bool isConnected(String? macAddress) {
    return macAddress != null &&
        connectedMacAddress != null &&
        macAddress == connectedMacAddress;
  }
}

