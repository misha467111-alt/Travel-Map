# Screen 1 physical QA — 2026-09-08

SCREEN 1 FINAL VISUAL PASS: NO. Stop at Screen 1.

Existing changes were inspected and preserved. Previously unverified changes confirmed: opaque category strip (48 dp), circular toolbar buttons (34 dp).

Changes in this pass:
- Manual My Location now uses the same 10.5 overview zoom as initial GPS. Physical QA confirmed the previous manual zoom 15 returned zero locations.
- Production POI markers are attached to the existing cluster manager. GPS remains outside clustering. Existing widget test now checks this association.
- Normal map land/road/water colors moved closer to the muted master reference.

Validation:
- Before physical QA: flutter analyze PASS; flutter test 124/124 PASS.
- Final: flutter analyze PASS; flutter test 124/124 PASS.
- Samsung R58M34G0J7W / SM-A505FM detected and final build installed without clearing app data.
- Normal map, real production markers, pink GPS marker and Google attribution visible.
- Final GPS viewport: zoom 10.5, southwest 50.12405898635782,30.279660411179066; northeast 50.52480157226137,30.65254881978035; 26 locations, 27 input markers including GPS.
- Pan viewport returned 35 locations; manual My Location restored the final 26-location viewport at zoom 10.5.
- Clusters 4 and 8 visibly rendered. Cluster tap changed zoom from 10.5 to 12.5 and returned 8 locations.
- Earlier pan/hold screenshots have identical SHA256 hashes; no observed snap-back. Later GPS updates are covered by the one-shot policy tests, not a physical GPS stream: the current provider uses getCurrentPosition.
- Bounded viewport RPC retained; no fetch-all introduced; no extra client approved-status filtering in this path.

Direct comparison against qa/master/master_reference_board.png and qa/master/master_reference_screen1_crop.png:
- Compact header geometry: PASS.
- Category strip: circular and opaque, but icon artwork/order and edge presentation still differ from master: FAIL for full visual match.
- Right toolbar: compact circles, but icon artwork/order differs: FAIL for full visual match.
- Bottom navigation: fits, selected Map is gold; icon artwork/label styling still differs: FAIL for full visual match.
- Map viewport: FAIL for full visual match. Actual GPS centers Khotiv rather than the reference Kyiv composition; map labels and native blue numbered clusters are substantially larger than reference markers.
- Google attribution: PASS. No unintended UI overflow/clipping observed; the horizontal category list shows part of its next scrollable item.
- Search remains intentionally absent.

Final screenshot: qa/current/screen1_reference_final_v2.png (physical Samsung, Normal map).
Evidence: screen1_v2_viewport_evidence.log, screen1_v2_analyze_final.log, screen1_v2_tests_final.log.

AI/OpenAI executed: NO. Production data changed: NO. No other screens started.
