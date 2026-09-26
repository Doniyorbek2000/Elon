// Renders the launcher icon master (1024×1024) from the vector BrandMark:
//   flutter test tool/icon/icon_test.dart --update-goldens
import 'package:bozor/core/design/app_theme.dart';
import 'package:bozor/core/widgets/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('launcher icon master', (tester) async {
    tester.view.physicalSize = const Size(1024, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const ColoredBox(
          color: Color(0xFFEFF4FF),
          child: Center(child: BrandMark(size: 640)),
        ),
      ),
    );
    await expectLater(find.byType(ColoredBox).first, matchesGoldenFile('out/icon_1024.png'));
  });
}
