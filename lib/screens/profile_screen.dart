import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/backup_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, BackupProvider>(
      builder: (context, auth, backup, child) {
        if (auth.isLoading || backup.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // ... existing profile UI ...
            if (auth.isAuthenticated) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await backup.uploadBackup();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Backup uploaded successfully')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error uploading backup: $e')),
                      );
                    }
                  }
                },
                child: const Text('Upload Backup'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await backup.downloadBackup();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Backup downloaded successfully')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error downloading backup: $e')),
                      );
                    }
                  }
                },
                child: const Text('Download Backup'),
              ),
            ],
          ],
        );
      },
    );
  }
} 