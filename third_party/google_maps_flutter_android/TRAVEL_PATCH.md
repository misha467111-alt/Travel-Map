# Travel Map Android cluster presentation

Vendored from the installed google_maps_flutter_android 2.19.12 package.
Upstream LICENSE and AUTHORS are retained. The app uses a path override so the
change is reproducible without modifying the shared Pub cache.

The only upstream source change is in ClusterManagersController.java:
MarkerClusterRenderer.getDescriptorForCluster draws a 28 dp muted olive circle
with an exact count (999+ cap) and caches descriptors by count for this renderer.
No changes to clustering algorithms, thresholds, marker membership, camera
callbacks, or cluster tap behavior. The patch applies to standard Android markers;
iOS, web, and Android advanced markers retain their upstream renderer.

When updating the plugin, rebase this presentation override and verify the Android
build, visible cluster count and cluster tap on a physical device.
