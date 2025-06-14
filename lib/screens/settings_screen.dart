import 'package:flutter/material.dart';
import '../services/server_config_service.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_collaborative_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _addressController = TextEditingController();
  final _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _addressController.text = await ServerConfigService.getAddress();
    _portController.text = await ServerConfigService.getPort();
    setState(() {});
  }

  Future<void> _saveConfig() async {
    await ServerConfigService.saveConfig(
      _addressController.text.trim(),
      _portController.text.trim(),
    );
    if (mounted) {
      final enhancedProvider = Provider.of<EnhancedCollaborativeProvider>(context, listen: false);
      await enhancedProvider.updateBaseUrl();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Настройки сервера сохранены')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки сервера')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Адрес сервера (например, 192.168.1.10 или localhost)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Порт сервера (например, 8080)',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _saveConfig,
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }
} 