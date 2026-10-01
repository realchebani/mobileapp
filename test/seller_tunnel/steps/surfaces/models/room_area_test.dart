import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/seller_tunnel/steps/surfaces/models/room_area.dart';

void main() {
  group(RoomArea, () {
    test('parse accepts a comma or a dot', () {
      expect(RoomArea.parse(' 12,5 '), 12.5);
      expect(RoomArea.parse('12.25'), 12.25);
      expect(RoomArea.parse('7'), 7);
      expect(RoomArea.parse(''), isNull);
      expect(RoomArea.parse('12,'), isNull);
      expect(RoomArea.parse('a'), isNull);
    });

    test('round keeps 2 decimals', () {
      expect(RoomArea.round(12.345), 12.35);
      expect(RoomArea.round(0.1 + 0.2), 0.3);
    });

    test('format shows 1 decimal, 2 when needed', () {
      expect(RoomArea.format(6), '6,0');
      expect(RoomArea.format(38.5), '38,5');
      expect(RoomArea.format(12.25), '12,25');
      expect(RoomArea.format(1150), '1 150,0');
    });

    test('input is the value as typed', () {
      expect(RoomArea.input(12), '12');
      expect(RoomArea.input(12.5), '12,5');
      expect(RoomArea.input(12.25), '12,25');
      expect(RoomArea.input(0.5), '0,5');
    });

    test('short drops the decimals of a whole value', () {
      expect(RoomArea.short(115), '115');
      expect(RoomArea.short(115.5), '115,5');
    });
  });
}
