import 'package:notchpeek/core/platform/channels.dart';

/// Null-safe by the same rule as every other mapper: a malformed hover payload
/// reads as "the cursor is not here", which collapses the shell. Getting stuck
/// open is the failure that matters.
abstract final class HoverModel {
  static bool toEntity(Map<String, Object?> json) =>
      json[SystemEventKind.inside] as bool? ?? false;
}
