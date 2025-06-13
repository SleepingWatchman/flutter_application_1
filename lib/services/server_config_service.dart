import 'package:shared_preferences/shared_preferences.dart';

class ServerConfigService {
  static const _keyAddress = 'server_address';
  static const _keyPort = 'server_port';

  static Future<void> saveConfig(String address, String port) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAddress, address);
    await prefs.setString(_keyPort, port);
  }

  static Future<String> getAddress() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyAddress);
    return (value == null || value.isEmpty) ? 'localhost' : value;
  }

  static Future<String> getPort() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyPort);
    return (value == null || value.isEmpty) ? '8080' : value;
  }

  static Future<String> getBaseUrl() async {
    final address = await getAddress();
    final port = await getPort();
    return 'http://$address:$port';
  }
} 