import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

import 'package:flutter_application_1/main.dart';

/// Real database I/O does not complete inside testWidgets' fake clock,
/// so we let real time pass with runAsync and then pump the UI.
Future<void> pumpDb(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() {
    // Use the FFI SQLite implementation when running tests on desktop.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('shows the app title and empty state', (tester) async {
    await tester.runAsync(() => MovieDatabase.instance.deleteAllMovies());

    await tester.pumpWidget(const MovieApp(initialDarkMode: false));
    await pumpDb(tester);

    expect(find.text('Pocket Notes: Movies'), findsOneWidget);
    expect(find.text('No movies yet. Add your first movie!'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('shows an error when saving without a title', (tester) async {
    await tester.runAsync(() => MovieDatabase.instance.deleteAllMovies());

    await tester.pumpWidget(const MovieApp(initialDarkMode: false));
    await pumpDb(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Add Movie'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Please enter a movie title.'), findsOneWidget);
  });

  testWidgets('adds a movie and shows it in the list', (tester) async {
    await tester.runAsync(() => MovieDatabase.instance.deleteAllMovies());

    await tester.pumpWidget(const MovieApp(initialDarkMode: false));
    await pumpDb(tester);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'Inception');
    await tester.tap(find.text('Save'));
    await pumpDb(tester);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Rating: 10/10'), findsOneWidget);
  });

  testWidgets('8+ filter chip toggles', (tester) async {
    await tester.runAsync(() => MovieDatabase.instance.deleteAllMovies());

    await tester.pumpWidget(const MovieApp(initialDarkMode: false));
    await pumpDb(tester);

    await tester.tap(find.text('8+ Rating Only'));
    await tester.pump();

    expect(find.text('No movies rated 8 or above.'), findsOneWidget);
  });
}
