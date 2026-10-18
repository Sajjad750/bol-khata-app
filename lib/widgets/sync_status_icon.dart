import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/database_providers.dart';
import '../theme/khata_colors.dart';

/// Small cloud icon: green when fully synced, grey outline when pending.
class SyncStatusIcon extends ConsumerWidget {
  const SyncStatusIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Ensure background sync is running while UI is shown.
    ref.watch(syncServiceProvider);

    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final pending = pendingAsync.asData?.value ?? 0;
    final fullySynced = pending == 0;

    return Tooltip(
      message: fullySynced ? 'All entries synced' : '$pending waiting to sync',
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Icon(
          fullySynced ? Icons.cloud_done : Icons.cloud_outlined,
          color: fullySynced ? KhataColors.primaryGreen : Colors.grey.shade500,
          size: 22,
        ),
      ),
    );
  }
}
