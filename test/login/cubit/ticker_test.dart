import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileapp/login/cubit/cubit.dart';

void main() {
  group('Ticker', () {
    test('counts down once per second', () {
      fakeAsync((async) {
        final values = <int>[];
        const Ticker().tick(ticks: 3).listen(values.add);
        async.elapse(const Duration(milliseconds: 1500));
        expect(values, [2]);
        async.elapse(const Duration(seconds: 5));
        expect(values, [2, 1, 0]);
      });
    });
  });
}
