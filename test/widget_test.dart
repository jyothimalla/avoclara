import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:avoclara/main.dart';
import 'package:avoclara/models/tracker_models.dart';
import 'package:avoclara/screens/tracker_home_page.dart';

void main() {
  Future<void> pumpTrackerHomePage(
    WidgetTester tester, {
    required UserType userType,
    String initialMotherName = 'Jyothi',
    String? initialChildName,
    String currentUserEmail = 'jyothi@example.com',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TrackerHomePage(
          initialMotherName: initialMotherName,
          currentUserEmail: currentUserEmail,
          initialUserType: userType,
          initialChildName: initialChildName,
          canChangePassword: true,
          onChangePassword: ({
            required String currentPassword,
            required String newPassword,
          }) async =>
              null,
          onLogout: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Shows auth screen when no session exists', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const HobbyTrackerApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsWidgets);
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('Activities page shows analysis sections', (WidgetTester tester) async {
    await pumpTrackerHomePage(tester, userType: UserType.student);

    await tester.tap(find.text('Activities'));
    await tester.pumpAndSettle();

    expect(find.text('Activity Analysis'), findsOneWidget);
    expect(find.text('Hobbies'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Checklist'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('Summary'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Summary'), findsOneWidget);
  });

  testWidgets('Profile page renders dynamic profile sections', (WidgetTester tester) async {
    await pumpTrackerHomePage(
      tester,
      userType: UserType.parent,
      initialMotherName: 'Jyothi',
      initialChildName: 'Aarav',
    );

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Profile Type'), findsOneWidget);
    expect(find.text('Parent'), findsWidgets);
    expect(find.text('Parent PIN'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Calendar Sync'), findsOneWidget);
  });

  testWidgets('Today search and filter work with added task', (WidgetTester tester) async {
    await pumpTrackerHomePage(tester, userType: UserType.individual);

    await tester.tap(find.text('To-Do List'));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Homework task');
    await tester.tap(find.text('Hobby').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Homework task');
    await tester.pumpAndSettle();

    expect(find.text('Search Today'), findsOneWidget);
    expect(find.text('Homework task'), findsWidgets);

    await tester.tap(find.text('Homework task').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pumpAndSettle();
    expect(find.text('Filter Today'), findsOneWidget);

    await tester.tap(find.text('Task').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Apply'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Clear Filters'), findsOneWidget);
  });

  testWidgets('Tracker items persist for the same user after rebuilding home', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await pumpTrackerHomePage(
      tester,
      userType: UserType.individual,
      currentUserEmail: 'persist@example.com',
    );

    await tester.tap(find.text('Checklist').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'School bag');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('School bag'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await pumpTrackerHomePage(
      tester,
      userType: UserType.individual,
      currentUserEmail: 'persist@example.com',
    );

    await tester.tap(find.text('Checklist').last);
    await tester.pumpAndSettle();

    expect(find.text('School bag'), findsOneWidget);
  });

  testWidgets('Checklist item stays in Checklist and does not appear in Hobbies', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await pumpTrackerHomePage(
      tester,
      userType: UserType.individual,
      currentUserEmail: 'checklist@example.com',
    );

    await tester.tap(find.text('Checklist').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Lunch box');
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch box'), findsOneWidget);

    await tester.tap(find.text('To-Do List'));
    await tester.pumpAndSettle();

    expect(find.text('Lunch box'), findsNothing);
  });
}
