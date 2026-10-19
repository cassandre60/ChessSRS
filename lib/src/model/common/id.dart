import 'package:deep_pick/deep_pick.dart';

extension type const StringId(String value) {
  StringId.fromJson(dynamic json) : this(json as String);
  String toJson() => value;

  int get length => value.length;
  bool startsWith(String prefix) => value.startsWith(prefix);
}

extension type const IntId(int value) {}

final _gameOrChallengeIdRegex = RegExp(r'''^[\w-]{8}$''');

extension type const GameAnyId._(String value) implements StringId {
  GameAnyId(this.value) : assert(value.length == 8 || value.length == 12);
  GameId get gameId => GameId(value.substring(0, 8));
  bool get isFullId => value.length == 12;
  GameFullId? get gameFullId => isFullId ? GameFullId(value) : null;

  GameAnyId.fromJson(dynamic json) : this(json as String);
}

extension type const GameId._(String value) implements StringId, GameAnyId {
  const GameId(this.value) : assert(value.length == 8);

  bool get isValid => _gameOrChallengeIdRegex.hasMatch(value);

  GameId.fromJson(dynamic json) : this(json as String);
}

extension type const GameFullId._(String value) implements StringId, GameAnyId {
  const GameFullId(this.value) : assert(value.length == 12);

  GameFullId.fromJson(dynamic json) : this(json as String);
}

extension type const PuzzleId(String value) implements StringId {
  PuzzleId.fromJson(dynamic json) : this(json as String);
}

extension type const UserId(String value) implements StringId {
  UserId.fromUserName(String userName) : this(userName.toLowerCase());
  UserId.fromJson(dynamic json) : this(json as String);
}

extension type const ChallengeId(String value) implements StringId {
  ChallengeId.fromJson(dynamic json) : this(json as String);

  bool get isValid => _gameOrChallengeIdRegex.hasMatch(value);
}

extension type const BroadcastTournamentId(String value) implements StringId {}

extension type const BroadcastRoundId(String value) implements StringId {}

extension type const BroadcastGameId(String value) implements StringId {}

extension type const StudyId(String value) implements StringId {
  StudyId.fromJson(dynamic json) : this(json as String);
}

extension type const TournamentId(String value) implements StringId {
  TournamentId.fromJson(dynamic json) : this(json as String);
}

extension type const TeamId(String value) implements StringId {
  TeamId.fromJson(dynamic json) : this(json as String);
}

extension type const StudyChapterId(String value) implements StringId {
  StudyChapterId.fromJson(dynamic json) : this(json as String);
}

extension type const FideId(int value) implements IntId {}

extension IDPick on Pick {
  StringId asStringIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return StringId(value);
    }
    throw PickException.fromPick(this, "can't be casted to StringId");
  }

  UserId asUserIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return UserId(value);
    }
    throw PickException.fromPick(this, "can't be casted to UserId");
  }

  UserId? asUserIdOrNull() {
    if (value == null) return null;
    try {
      return asUserIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  GameId asGameIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return GameId(value);
    }
    throw PickException.fromPick(this, "can't be casted to GameId");
  }

  GameFullId asGameFullIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return GameFullId(value);
    }
    throw PickException.fromPick(this, "can't be casted to GameId");
  }

  GameFullId? asGameFullIdOrNull() {
    if (value == null) return null;
    try {
      return asGameFullIdOrThrow();
    } catch (_) {
      return null;
    }
  }

  PuzzleId asPuzzleIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return PuzzleId(value);
    }
    throw PickException.fromPick(this, "can't be casted to PuzzleId");
  }

  ChallengeId asChallengeIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return ChallengeId(value);
    }
    throw PickException.fromPick(this, "can't be casted to ChallengeId");
  }

  BroadcastTournamentId asBroadcastTournamentIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return BroadcastTournamentId(value);
    }
    throw PickException.fromPick(this, "can't be casted to BroadcastTournamentId");
  }

  BroadcastRoundId asBroadcastRoundIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return BroadcastRoundId(value);
    }
    throw PickException.fromPick(this, "can't be casted to BroadcastRoundId");
  }

  BroadcastGameId asBroadcastGameIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return BroadcastGameId(value);
    }
    throw PickException.fromPick(this, "can't be casted to BroadcastGameId");
  }

  TeamId asTeamIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return TeamId(value);
    }
    throw PickException.fromPick(this, "can't be casted to TeamId");
  }

  StudyId asStudyIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return StudyId(value);
    }
    throw PickException.fromPick(this, "can't be casted to StudyId");
  }

  FideId asFideIdOrThrow() {
    final value = required().value;
    if (value is int && value != 0) {
      return FideId(value);
    }
    throw PickException.fromPick(this, "can't be casted to FideId");
  }

  TournamentId asTournamentIdOrThrow() {
    final value = required().value;
    if (value is String) {
      return TournamentId(value);
    }
    throw PickException.fromPick(this, "can't be casted to TournamentId");
  }

  TournamentId? asTournamentIdOrNull() {
    if (value == null) return null;
    try {
      return asTournamentIdOrThrow();
    } catch (_) {
      return null;
    }
  }
}
