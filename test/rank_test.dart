import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/gamification/domain/rank.dart';

void main() {
  test('rank thresholds are deterministic', () {
    expect(rankForXp(0), TravelRank.novice);
    expect(rankForXp(200), TravelRank.traveler);
    expect(rankForXp(700), TravelRank.pathfinder);
    expect(rankForXp(1500), TravelRank.explorer);
    expect(rankForXp(3000), TravelRank.legend);
  });

  test('negative XP is rejected', () {
    expect(() => rankForXp(-1), throwsArgumentError);
  });
}
