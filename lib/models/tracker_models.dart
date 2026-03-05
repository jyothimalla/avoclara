import 'dart:typed_data';

import 'package:flutter/material.dart';

class LocalUserAccount {
  const LocalUserAccount({
    required this.name,
    required this.email,
    this.passwordHash,
    required this.provider,
    required this.createdAtIso,
    this.userType,
    this.childName,
  });

  final String name;
  final String email;
  final String? passwordHash;
  final String provider;
  final String createdAtIso;
  final String? userType;
  final String? childName;

  bool get usesPassword => provider == 'email';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'email': email,
    'passwordHash': passwordHash,
    'provider': provider,
    'createdAtIso': createdAtIso,
    'userType': userType,
    'childName': childName,
  };

  factory LocalUserAccount.fromJson(Map<String, dynamic> json) {
    return LocalUserAccount(
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      passwordHash: json['passwordHash'] as String?,
      provider: json['provider'] as String? ?? 'email',
      createdAtIso:
          json['createdAtIso'] as String? ?? DateTime.now().toIso8601String(),
      userType: json['userType'] as String?,
      childName: json['childName'] as String?,
    );
  }
}

enum TrackerSection {
  today,
  activities,
  hobbies,
  dailyTasks,
  todoList,
  checklist,
  weeklyPlanner,
  timer,
  profile,
  settings,
}

enum RepeatRule { none, daily, weekly, customDays }

enum ItemPriority { low, medium, high }

enum UserType { individual, student, parent, kid }

enum AppThemeChoice {
  blossom,
  ocean,
  sunshine,
  midnight,
  pearlLight,
  mintLight,
  skyLight,
}

class SectionVisualTheme {
  const SectionVisualTheme({
    required this.colors,
    required this.accent,
    required this.backgroundIcons,
  });

  final List<Color> colors;
  final Color accent;
  final List<IconData> backgroundIcons;
}

class TrackerItem {
  TrackerItem({
    required this.title,
    this.isDone = false,
    this.points = 0,
    this.repeatRule = RepeatRule.none,
    this.priority = ItemPriority.medium,
    this.isHighPriority = false,
    this.topPriorityNumber,
    List<int>? repeatWeekdays,
  }) : repeatWeekdays = repeatWeekdays ?? <int>[];

  final String title;
  bool isDone;
  final int points;
  final RepeatRule repeatRule;
  final List<int> repeatWeekdays;
  final ItemPriority priority;
  bool isHighPriority;
  int? topPriorityNumber;
}

class WeeklyActivity {
  WeeklyActivity({
    required this.title,
    required this.plannedDate,
    this.startHour,
    this.startMinute,
    this.endHour,
    this.endMinute,
    this.reminderMinutesBefore = 0,
    this.priority = ItemPriority.medium,
    this.isHighPriority = false,
    this.topPriorityNumber,
    this.isDone = false,
    this.googleEventId,
  });

  final String title;
  final DateTime plannedDate;
  final int? startHour;
  final int? startMinute;
  final int? endHour;
  final int? endMinute;
  final int reminderMinutesBefore;
  final ItemPriority priority;
  bool isHighPriority;
  int? topPriorityNumber;
  bool isDone;
  final String? googleEventId;
}

class ChildProfile {
  ChildProfile({
    required this.name,
    required this.items,
    required this.weeklyActivities,
    this.avatarIcon = Icons.face_rounded,
    this.avatarBytes,
  });

  String name;
  final Map<TrackerSection, List<TrackerItem>> items;
  final List<WeeklyActivity> weeklyActivities;
  IconData avatarIcon;
  Uint8List? avatarBytes;
}

class TodayActivityEntry {
  TodayActivityEntry({
    required this.title,
    required this.category,
    required this.icon,
    required this.color,
    required this.priority,
    required this.points,
    required this.isDone,
    required this.onToggleDone,
    required this.isHighPriority,
    required this.topPriorityNumber,
    required this.onTapPriority,
  });

  final String title;
  final String category;
  final IconData icon;
  final Color color;
  final ItemPriority priority;
  final int points;
  final bool isDone;
  final ValueChanged<bool> onToggleDone;
  final bool isHighPriority;
  final int? topPriorityNumber;
  final Future<void> Function() onTapPriority;
}

class TodaySearchResult {
  const TodaySearchResult({required this.entry, required this.date});

  final TodayActivityEntry entry;
  final DateTime date;
}

class HelpFaqItem {
  const HelpFaqItem({required this.question, required this.answer});

  final String question;
  final String answer;
}
