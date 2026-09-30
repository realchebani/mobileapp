/// {@template ticker}
/// Counts down, one tick per second. Injectable to test countdowns.
/// {@endtemplate}
class Ticker {
  /// {@macro ticker}
  const new();

  /// Emits `ticks - 1`, `ticks - 2`, … `0`, one value per second.
  Stream<int> tick({required int ticks}) => Stream<int>.periodic(
    const Duration(seconds: 1),
    (count) => ticks - count - 1,
  ).take(ticks);
}
