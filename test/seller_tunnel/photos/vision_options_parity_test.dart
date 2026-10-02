import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_options.dart';
import 'package:property_repository/property_repository.dart';

/// EPIC-15: the options the vision AI may propose (Edge Functions
/// vision-room and plan-reader) are those of the V5c form.
void main() {
  final fixture = jsonDecode(
    File('supabase/functions/tests/fixtures/vision_options.json')
        .readAsStringSync(),
  ) as Map<String, dynamic>;

  test('room kinds are the V5c room suggestions', () {
    expect(fixture['room_kinds'], [
      for (final s in RoomSuggestion.values) s.name,
    ]);
  });

  test('floor coverings, glazings and levels are the stored values', () {
    expect(fixture['floor_coverings'], [
      for (final c in FloorCovering.values) c.value,
    ]);
    expect(fixture['glazings'], [for (final g in Glazing.values) g.value]);
    expect(fixture['levels'], [for (final l in RoomLevel.values) l.value]);
  });
}
