import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/enhanced_collaborative_provider.dart';

class ServerStatusIndicator extends StatelessWidget {
  const ServerStatusIndicator({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedCollaborativeProvider>(
      builder: (context, enhancedProvider, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: enhancedProvider.isServerAvailable
                ? Colors.green.withOpacity(0.15)
                : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enhancedProvider.isServerAvailable
                  ? Colors.green.withOpacity(0.4)
                  : Colors.red.withOpacity(0.4),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                enhancedProvider.isServerAvailable
                    ? Icons.cloud_done
                    : Icons.cloud_off,
                size: 12,
                color: enhancedProvider.isServerAvailable
                    ? Colors.green
                    : Colors.red,
              ),
              const SizedBox(width: 3),
              Text(
                enhancedProvider.isServerAvailable ? 'Онлайн' : 'Офлайн',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: enhancedProvider.isServerAvailable
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
} 