import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gps_journey_details_view.dart';

/// Journey Phase 1G -- thin auth-gated wrapper (same shape as
/// `GpsJourneyHistoryScreen`): resolves the owner id and delegates to
/// [GpsJourneyDetailsBody], which holds all Details logic and is what tests
/// mount directly. The only Supabase use is the current user id.
class GpsJourneyDetailsScreen extends StatelessWidget {
  const GpsJourneyDetailsScreen({super.key, required this.routeId});

  final String routeId;

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Подорож')),
      body: userId == null
          ? const Center(child: Text('Потрібно увійти в акаунт.'))
          : GpsJourneyDetailsBody(ownerId: userId, routeId: routeId),
    );
  }
}
