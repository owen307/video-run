import 'package:alpaca_video/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('console shows Video Run, the mock bank, and follow cues', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const VideoRunApp());
    await tester.pumpAndSettle();

    expect(find.text('Video Run'), findsWidgets);
    expect(find.text('MOCK'), findsWidgets);
    expect(find.text('CUT'), findsOneWidget);
    expect(find.text('Follow cues'), findsOneWidget);
    expect(find.text('Send link'), findsOneWidget);
    expect(find.text('CAM1'), findsWidgets);
    expect(find.text('Walk-in'), findsOneWidget);

    expect(
      find.descendant(of: find.byKey(const Key('program-tally')), matching: find.text('CAM1')),
      findsOneWidget,
    );
    await tester.tap(find.text('CUT'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('program-tally')), matching: find.text('CAM2')),
      findsOneWidget,
    );
    expect(find.textContaining('send off'), findsWidgets);

    await tester.tap(find.byKey(const Key('open-about')));
    await tester.pumpAndSettle();
    final title = tester.widget<Text>(find.byKey(const Key('about-title')));
    expect(title.data, 'Video Run');
  });
}
