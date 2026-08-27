enum TravelRank { novice, traveler, pathfinder, explorer, legend }

TravelRank rankForXp(int xp) => switch (xp) {
      < 0 => throw ArgumentError.value(xp, 'xp', 'must be non-negative'),
      < 200 => TravelRank.novice,
      < 700 => TravelRank.traveler,
      < 1500 => TravelRank.pathfinder,
      < 3000 => TravelRank.explorer,
      _ => TravelRank.legend,
    };

extension TravelRankLabel on TravelRank {
  String get labelUk => switch (this) {
        TravelRank.novice => 'Новачок',
        TravelRank.traveler => 'Мандрівник',
        TravelRank.pathfinder => 'Слідопит',
        TravelRank.explorer => 'Дослідник',
        TravelRank.legend => 'Легенда',
      };
}
