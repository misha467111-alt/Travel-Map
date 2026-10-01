import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'gps_journey_details_screen.dart';
import 'gps_journey_history_view.dart';

/// Journey Phase 1F -- thin auth-gated wrapper (same shape as
/// `GpsRecordingMapScreen`): resolves the owner id and delegates to
/// [GpsJourneyHistoryBody], which holds all History logic and is what tests
/// mount directly. This is the only History file that knows about Supabase,
/// and only for the current user id.
class GpsJourneyHistoryScreen extends StatelessWidget {
  const GpsJourneyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Історія подорожей')),
      body: userId == null
          ? const Center(child: Text('Потрібно увійти в акаунт.'))
          : GpsJourneyHistoryBody(
              ownerId: userId,
              onOpenJourney: (routeId) => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => GpsJourneyDetailsScreen(routeId: routeId),
                ),
              ),
            ),
    );
  }
}
