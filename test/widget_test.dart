import 'package:flutter_test/flutter_test.dart';

import 'package:kindred_app/main.dart';

void main() {
  test('level thresholds are ordered', () {
    expect(helperThreshold, lessThan(championThreshold));
    expect(championThreshold, lessThan(legendThreshold));
    expect(pointsPerAct, greaterThan(0));
  });

  test('banner palette is available', () {
    expect(bannerColors.length, greaterThanOrEqualTo(4));
  });
}
