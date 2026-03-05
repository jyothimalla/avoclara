import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:image_picker/image_picker.dart';

import '../models/tracker_models.dart';

const String _kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);
const String _kGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

class TrackerHomePage extends StatefulWidget {
  const TrackerHomePage({
    super.key,
    required this.initialMotherName,
    required this.currentUserEmail,
    required this.initialUserType,
    this.initialChildName,
    required this.canChangePassword,
    required this.onChangePassword,
    required this.onLogout,
  });

  final String initialMotherName;
  final String currentUserEmail;
  final UserType initialUserType;
  final String? initialChildName;
  final bool canChangePassword;
  final Future<String?> Function({
    required String currentPassword,
    required String newPassword,
  })
  onChangePassword;
  final Future<void> Function() onLogout;

  @override
  State<TrackerHomePage> createState() => _TrackerHomePageState();
}

class _TrackerHomePageState extends State<TrackerHomePage>
    with WidgetsBindingObserver {
  static const List<String> _weekDays = <String>[
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _monthNames = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  static const List<IconData> _avatarChoices = <IconData>[
    Icons.face_rounded,
    Icons.pets_rounded,
    Icons.emoji_emotions_rounded,
    Icons.auto_awesome_rounded,
    Icons.sports_esports_rounded,
    Icons.school_rounded,
  ];
  static const List<String> _weekDaysSunFirst = <String>[
    'Sun',
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
  ];
  static const List<String> _todayFilterCategories = <String>[
    'Hobby',
    'Task',
    'To-Do',
    'Checklist',
    'Weekly',
  ];
  static const List<ItemPriority> _todayFilterPriorities = <ItemPriority>[
    ItemPriority.high,
    ItemPriority.medium,
    ItemPriority.low,
  ];

  TrackerSection _currentSection = TrackerSection.today;
  DateTime _selectedPlannerDate = _dateOnly(DateTime.now());
  late final UserType _userType = widget.initialUserType;
  AppThemeChoice _themeChoice = AppThemeChoice.pearlLight;
  String _motherName = 'Jyothi';
  String? _parentPin;
  int _selectedChildIndex = 0;
  final Set<String> _todayCategoryFilters = <String>{};
  final Set<ItemPriority> _todayPriorityFilters = <ItemPriority>{};
  final ImagePicker _imagePicker = ImagePicker();

  late List<ChildProfile> _children;

  Map<TrackerSection, List<TrackerItem>> get _items =>
      _children[_selectedChildIndex].items;
  List<WeeklyActivity> get _weeklyActivities =>
      _children[_selectedChildIndex].weeklyActivities;
  String get _activeChildName => _children[_selectedChildIndex].name;
  List<TrackerItem> get _hobbyItems =>
      _items[TrackerSection.hobbies] ?? <TrackerItem>[];
  List<TrackerItem> get _taskItems =>
      _items[TrackerSection.dailyTasks] ?? <TrackerItem>[];
  List<TrackerItem> get _checklistItems =>
      _items[TrackerSection.checklist] ?? <TrackerItem>[];
  int get _earnedPointsTotal =>
      (<TrackerSection>[TrackerSection.todoList, TrackerSection.checklist])
          .expand(
            (TrackerSection section) => _items[section] ?? <TrackerItem>[],
          )
          .where((TrackerItem item) => item.isDone)
          .fold<int>(0, (int sum, TrackerItem item) => sum + item.points);

  bool get _isParentUser => _userType == UserType.parent;
  String get _userTypeLabel {
    switch (_userType) {
      case UserType.individual:
        return 'Individual';
      case UserType.student:
        return 'Student';
      case UserType.parent:
        return 'Parent';
      case UserType.kid:
        return 'Kid';
    }
  }

  String get _profileOwnerName =>
      _userType == UserType.parent ? _motherName : _activeChildName;

  Map<TrackerSection, List<TrackerItem>> _emptyItemsMap() {
    return <TrackerSection, List<TrackerItem>>{
      TrackerSection.hobbies: <TrackerItem>[],
      TrackerSection.dailyTasks: <TrackerItem>[],
      TrackerSection.todoList: <TrackerItem>[],
      TrackerSection.checklist: <TrackerItem>[],
    };
  }

  ChildProfile _createProfile(String name) {
    return ChildProfile(
      name: name,
      items: _emptyItemsMap(),
      weeklyActivities: <WeeklyActivity>[],
      avatarIcon: Icons.face_rounded,
    );
  }

  static const int _defaultTimerSeconds = 0;
  static const int _reminderGraceMinutes = 20;
  Timer? _countdownTimer;
  Timer? _reminderTimer;
  int _timerSecondsRemaining = _defaultTimerSeconds;
  bool _isTimerRunning = false;
  final Map<String, int> _timerUsageSecondsByDate = <String, int>{};
  final Set<String> _shownReminderKeys = <String>{};
  final Set<String> _googleImportKeys = <String>{};
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;
  gcal.CalendarApi? _calendarApi;
  bool _isGoogleConnected = false;
  bool _isSyncingCalendar = false;
  DateTime? _lastGoogleSyncAt;

  @override
  void initState() {
    super.initState();
    if (widget.initialMotherName.trim().isNotEmpty) {
      _motherName = widget.initialMotherName.trim();
    }
    final String primaryName = widget.initialMotherName.trim().isEmpty
        ? 'My Profile'
        : widget.initialMotherName.trim();
    _children = <ChildProfile>[
      _createProfile(
        _isParentUser
            ? ((widget.initialChildName?.trim().isNotEmpty ?? false)
                  ? widget.initialChildName!.trim()
                  : 'Child 1')
            : primaryName,
      ),
    ];
    WidgetsBinding.instance.addObserver(this);
    _reminderTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkTaskReminders();
    });
    _checkTaskReminders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _reminderTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTaskReminders();
    }
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool _sameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _reminderKey(WeeklyActivity activity) {
    final String y = activity.plannedDate.year.toString().padLeft(4, '0');
    final String m = activity.plannedDate.month.toString().padLeft(2, '0');
    final String d = activity.plannedDate.day.toString().padLeft(2, '0');
    final String hh = (activity.startHour ?? 0).toString().padLeft(2, '0');
    final String mm = (activity.startMinute ?? 0).toString().padLeft(2, '0');
    return '${identityHashCode(activity)}-$y$m$d-$hh$mm';
  }

  String _dateStorageKey(DateTime value) {
    final String y = value.year.toString().padLeft(4, '0');
    final String m = value.month.toString().padLeft(2, '0');
    final String d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int get _todayTimerUsageSeconds =>
      _timerUsageSecondsByDate[_dateStorageKey(_dateOnly(DateTime.now()))] ?? 0;

  String _formatTimerUsage(int seconds) {
    final int hours = seconds ~/ 3600;
    final int minutes = (seconds % 3600) ~/ 60;
    if (hours <= 0) {
      return '$minutes min';
    }
    if (minutes <= 0) {
      return '$hours hr';
    }
    return '$hours hr $minutes min';
  }

  DateTime? _activityStartDateTime(WeeklyActivity activity) {
    if (activity.startHour == null || activity.startMinute == null) {
      return null;
    }
    return DateTime(
      activity.plannedDate.year,
      activity.plannedDate.month,
      activity.plannedDate.day,
      activity.startHour!,
      activity.startMinute!,
    );
  }

  void _checkTaskReminders() {
    if (!mounted) {
      return;
    }
    final DateTime now = DateTime.now();
    for (final WeeklyActivity activity in _weeklyActivities) {
      if (activity.isDone) {
        continue;
      }
      final DateTime? startDateTime = _activityStartDateTime(activity);
      if (startDateTime == null) {
        continue;
      }
      final DateTime reminderAt = startDateTime.subtract(
        Duration(minutes: activity.reminderMinutesBefore),
      );
      final int diffMinutes = now.difference(reminderAt).inMinutes;
      if (diffMinutes < 0 || diffMinutes > _reminderGraceMinutes) {
        continue;
      }
      final String key = _reminderKey(activity);
      if (_shownReminderKeys.contains(key)) {
        continue;
      }
      _shownReminderKeys.add(key);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            activity.reminderMinutesBefore == 0
                ? 'Reminder: ${activity.title} starts now'
                : 'Reminder: ${activity.title} starts in ${activity.reminderMinutesBefore} min',
          ),
          backgroundColor: const Color(0xFFE83E76),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _addItem() async {
    final bool usePoints = _currentSection == TrackerSection.checklist;
    final TextEditingController titleController = TextEditingController();
    final TextEditingController pointsController = TextEditingController(
      text: '10',
    );
    TrackerSection targetSection = TrackerSection.hobbies;
    bool isRecurringTask = false;
    RepeatRule selectedRepeatRule = RepeatRule.none;
    final Set<int> selectedRepeatDays = <int>{DateTime.now().weekday};
    ItemPriority selectedPriority = ItemPriority.medium;
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text('Add ${_sectionLabel(_currentSection)} item'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Enter item name',
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_currentSection == TrackerSection.activities ||
                        _currentSection == TrackerSection.todoList) ...[
                      DropdownButtonFormField<TrackerSection>(
                        initialValue: targetSection,
                        decoration: const InputDecoration(labelText: 'Type'),
                        items: const [
                          DropdownMenuItem(
                            value: TrackerSection.hobbies,
                            child: Text('Hobby'),
                          ),
                          DropdownMenuItem(
                            value: TrackerSection.dailyTasks,
                            child: Text('Task'),
                          ),
                        ],
                        onChanged: (TrackerSection? value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            targetSection = value;
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recurring task?'),
                      value: isRecurringTask,
                      activeThumbColor: const Color(0xFFE83E76),
                      onChanged: (bool value) {
                        setDialogState(() {
                          isRecurringTask = value;
                          selectedRepeatRule = isRecurringTask
                              ? RepeatRule.daily
                              : RepeatRule.none;
                        });
                      },
                    ),
                    if (isRecurringTask)
                      DropdownButtonFormField<RepeatRule>(
                        initialValue: selectedRepeatRule,
                        decoration: const InputDecoration(labelText: 'Repeat'),
                        items: const [
                          DropdownMenuItem(
                            value: RepeatRule.daily,
                            child: Text('Daily'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.weekly,
                            child: Text('Weekly'),
                          ),
                          DropdownMenuItem(
                            value: RepeatRule.customDays,
                            child: Text('Few days'),
                          ),
                        ],
                        onChanged: (RepeatRule? value) {
                          if (value == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedRepeatRule = value;
                            if (selectedRepeatRule == RepeatRule.weekly &&
                                selectedRepeatDays.length > 1) {
                              final int day = selectedRepeatDays.first;
                              selectedRepeatDays
                                ..clear()
                                ..add(day);
                            }
                          });
                        },
                      ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<ItemPriority>(
                      initialValue: selectedPriority,
                      decoration: const InputDecoration(labelText: 'Priority'),
                      items: const [
                        DropdownMenuItem(
                          value: ItemPriority.high,
                          child: Text('High'),
                        ),
                        DropdownMenuItem(
                          value: ItemPriority.medium,
                          child: Text('Medium'),
                        ),
                        DropdownMenuItem(
                          value: ItemPriority.low,
                          child: Text('Low'),
                        ),
                      ],
                      onChanged: (ItemPriority? value) {
                        if (value == null) {
                          return;
                        }
                        setDialogState(() {
                          selectedPriority = value;
                        });
                      },
                    ),
                    if (isRecurringTask &&
                        (selectedRepeatRule == RepeatRule.weekly ||
                            selectedRepeatRule == RepeatRule.customDays)) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        children: List<Widget>.generate(_weekDays.length, (
                          int index,
                        ) {
                          final int weekday = index + 1;
                          final bool selected = selectedRepeatDays.contains(
                            weekday,
                          );
                          return FilterChip(
                            selected: selected,
                            label: Text(_weekDays[index]),
                            onSelected: (bool isSelected) {
                              setDialogState(() {
                                if (selectedRepeatRule == RepeatRule.weekly) {
                                  selectedRepeatDays
                                    ..clear()
                                    ..add(weekday);
                                  return;
                                }
                                if (isSelected) {
                                  selectedRepeatDays.add(weekday);
                                } else {
                                  selectedRepeatDays.remove(weekday);
                                }
                              });
                            },
                          );
                        }),
                      ),
                    ],
                    if (usePoints) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: pointsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Points',
                          hintText: '10',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final List<int> repeatDays = selectedRepeatDays.toList()
                      ..sort();
                    Navigator.of(context).pop(<String, dynamic>{
                      'title': titleController.text.trim(),
                      'points':
                          int.tryParse(pointsController.text.trim()) ?? 10,
                      'repeatRule': isRecurringTask
                          ? selectedRepeatRule
                          : RepeatRule.none,
                      'repeatDays': repeatDays,
                      'priority': selectedPriority,
                      'targetSection': targetSection,
                    });
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && (result['title'] as String).isNotEmpty) {
      final int safePoints = usePoints
          ? ((result['points'] as int?) ?? 10).clamp(1, 999)
          : 0;
      final RepeatRule repeatRule =
          result['repeatRule'] as RepeatRule? ?? RepeatRule.none;
      final ItemPriority priority =
          result['priority'] as ItemPriority? ?? ItemPriority.medium;
      final TrackerSection target =
          result['targetSection'] as TrackerSection? ?? _currentSection;
      List<int> repeatDays =
          (result['repeatDays'] as List<dynamic>? ?? <dynamic>[]).cast<int>();
      if (repeatRule == RepeatRule.weekly && repeatDays.isEmpty) {
        repeatDays = <int>[DateTime.now().weekday];
      }
      if (repeatRule == RepeatRule.customDays && repeatDays.isEmpty) {
        repeatDays = <int>[DateTime.now().weekday];
      }
      setState(() {
        _items[target]!.add(
          TrackerItem(
            title: result['title'] as String,
            points: safePoints,
            repeatRule: repeatRule,
            repeatWeekdays: repeatDays,
            priority: priority,
          ),
        );
      });
    }
  }

  Future<void> _addWeeklyActivity() async {
    final TextEditingController titleController = TextEditingController();
    TimeOfDay? selectedStartTime;
    TimeOfDay? selectedEndTime;
    ItemPriority selectedPriority = ItemPriority.medium;
    int reminderBeforeMinutes = 0;
    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Add Activity for Selected Date'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Example: English reading',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedStartTime == null
                              ? 'Start: Not set'
                              : 'Start: ${selectedStartTime!.hour.toString().padLeft(2, '0')}:${selectedStartTime!.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: selectedStartTime ?? TimeOfDay.now(),
                          );
                          if (picked == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedStartTime = picked;
                          });
                        },
                        icon: const Icon(Icons.access_time),
                        label: const Text('Set Start'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selectedEndTime == null
                              ? 'End: Not set'
                              : 'End: ${selectedEndTime!.hour.toString().padLeft(2, '0')}:${selectedEndTime!.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime:
                                selectedEndTime ??
                                selectedStartTime ??
                                TimeOfDay.now(),
                          );
                          if (picked == null) {
                            return;
                          }
                          setDialogState(() {
                            selectedEndTime = picked;
                          });
                        },
                        icon: const Icon(Icons.access_time_filled),
                        label: const Text('Set End'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<ItemPriority>(
                    initialValue: selectedPriority,
                    decoration: const InputDecoration(labelText: 'Priority'),
                    items: const [
                      DropdownMenuItem(
                        value: ItemPriority.high,
                        child: Text('High'),
                      ),
                      DropdownMenuItem(
                        value: ItemPriority.medium,
                        child: Text('Medium'),
                      ),
                      DropdownMenuItem(
                        value: ItemPriority.low,
                        child: Text('Low'),
                      ),
                    ],
                    onChanged: (ItemPriority? value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        selectedPriority = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: reminderBeforeMinutes,
                    decoration: const InputDecoration(labelText: 'Remind me'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('At start time')),
                      DropdownMenuItem(value: 5, child: Text('5 min before')),
                      DropdownMenuItem(value: 10, child: Text('10 min before')),
                      DropdownMenuItem(value: 15, child: Text('15 min before')),
                    ],
                    onChanged: (int? value) {
                      if (value == null) {
                        return;
                      }
                      setDialogState(() {
                        reminderBeforeMinutes = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pop(<String, dynamic>{
                      'title': titleController.text.trim(),
                      'start': selectedStartTime,
                      'end': selectedEndTime,
                      'priority': selectedPriority,
                      'reminderBeforeMinutes': reminderBeforeMinutes,
                    });
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && (result['title'] as String).isNotEmpty) {
      final TimeOfDay? start = result['start'] as TimeOfDay?;
      final TimeOfDay? end = result['end'] as TimeOfDay?;
      final ItemPriority priority =
          result['priority'] as ItemPriority? ?? ItemPriority.medium;
      final int reminderBeforeMinutes =
          (result['reminderBeforeMinutes'] as int? ?? 0).clamp(0, 120);
      setState(() {
        _weeklyActivities.add(
          WeeklyActivity(
            title: result['title'] as String,
            plannedDate: _selectedPlannerDate,
            startHour: start?.hour,
            startMinute: start?.minute,
            endHour: end?.hour,
            endMinute: end?.minute,
            priority: priority,
            reminderMinutesBefore: reminderBeforeMinutes,
          ),
        );
      });
    }
  }

  Future<void> _pickPlannerDate() async {
    final DateTime? picked = await _openCalendarSheet();
    if (picked != null) {
      setState(() {
        _selectedPlannerDate = _dateOnly(picked);
      });
    }
  }

  DateTime? _googleEventStart(gcal.Event event) {
    if (event.start == null) {
      return null;
    }
    return event.start!.dateTime ?? event.start!.date;
  }

  String _googleEventImportKey(gcal.Event event) {
    final DateTime? start = _googleEventStart(event);
    final String date = start == null
        ? 'unknown'
        : '${start.year}-${start.month}-${start.day}-${start.hour}-${start.minute}';
    return '${event.id ?? event.summary ?? 'event'}-$date';
  }

  Future<void> _connectGoogleCalendar() async {
    try {
      if (!_googleInitialized) {
        if (kIsWeb && _kGoogleWebClientId.trim().isEmpty) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google Calendar on web needs GOOGLE_WEB_CLIENT_ID. '
                'Run with --dart-define=GOOGLE_WEB_CLIENT_ID=your_client_id',
              ),
              backgroundColor: Color(0xFFE83E76),
              duration: Duration(seconds: 6),
            ),
          );
          return;
        }
        await _googleSignIn.initialize(
          clientId: kIsWeb ? _kGoogleWebClientId.trim() : null,
          serverClientId: _kGoogleServerClientId.trim().isEmpty
              ? null
              : _kGoogleServerClientId.trim(),
        );
        _googleInitialized = true;
      }
      await _googleSignIn.authenticate();
      final GoogleSignInClientAuthorization authz = await _googleSignIn
          .authorizationClient
          .authorizeScopes(<String>[gcal.CalendarApi.calendarScope]);
      final dynamic client = authz.authClient(
        scopes: <String>[gcal.CalendarApi.calendarScope],
      );
      setState(() {
        _calendarApi = gcal.CalendarApi(client);
        _isGoogleConnected = true;
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google Calendar connected'),
          backgroundColor: Color(0xFF3ECF8E),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google sign-in failed: $error'),
          backgroundColor: const Color(0xFFE83E76),
        ),
      );
    }
  }

  Future<void> _disconnectGoogleCalendar() async {
    await _googleSignIn.signOut();
    setState(() {
      _calendarApi = null;
      _isGoogleConnected = false;
    });
  }

  Future<void> _importGoogleCalendarEvents() async {
    if (_calendarApi == null) {
      await _connectGoogleCalendar();
    }
    if (_calendarApi == null) {
      return;
    }
    setState(() {
      _isSyncingCalendar = true;
    });
    try {
      final DateTime startWindow = _dateOnly(DateTime.now());
      final DateTime endWindow = startWindow.add(const Duration(days: 30));
      final gcal.Events events = await _calendarApi!.events.list(
        'primary',
        singleEvents: true,
        orderBy: 'startTime',
        timeMin: startWindow.toUtc(),
        timeMax: endWindow.toUtc(),
      );
      int added = 0;
      for (final gcal.Event event in events.items ?? <gcal.Event>[]) {
        final DateTime? start = _googleEventStart(event);
        if (start == null) {
          continue;
        }
        final String key = _googleEventImportKey(event);
        if (_googleImportKeys.contains(key)) {
          continue;
        }
        _googleImportKeys.add(key);
        final DateTime plannedDate = _dateOnly(start.toLocal());
        final DateTime? end = (event.end?.dateTime ?? event.end?.date)
            ?.toLocal();
        _weeklyActivities.add(
          WeeklyActivity(
            title: event.summary?.trim().isNotEmpty == true
                ? event.summary!.trim()
                : 'Google event',
            plannedDate: plannedDate,
            startHour: start.hour,
            startMinute: start.minute,
            endHour: end?.hour,
            endMinute: end?.minute,
            priority: ItemPriority.medium,
            googleEventId: event.id,
          ),
        );
        added++;
      }
      setState(() {
        _lastGoogleSyncAt = DateTime.now();
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $added event(s) from Google Calendar'),
          backgroundColor: const Color(0xFF3ECF8E),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calendar import failed: $error'),
            backgroundColor: const Color(0xFFE83E76),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingCalendar = false;
        });
      }
    }
  }

  Future<void> _exportSelectedDateToGoogleCalendar() async {
    if (_calendarApi == null) {
      await _connectGoogleCalendar();
    }
    if (_calendarApi == null) {
      return;
    }
    setState(() {
      _isSyncingCalendar = true;
    });
    try {
      final List<WeeklyActivity> selectedDateActivities = _weeklyActivities
          .where(
            (WeeklyActivity a) =>
                _sameDate(a.plannedDate, _selectedPlannerDate),
          )
          .toList();
      int exported = 0;
      for (final WeeklyActivity activity in selectedDateActivities) {
        if (activity.googleEventId != null) {
          continue;
        }
        final DateTime start = DateTime(
          activity.plannedDate.year,
          activity.plannedDate.month,
          activity.plannedDate.day,
          activity.startHour ?? 9,
          activity.startMinute ?? 0,
        );
        final DateTime end = DateTime(
          activity.plannedDate.year,
          activity.plannedDate.month,
          activity.plannedDate.day,
          activity.endHour ?? ((activity.startHour ?? 9) + 1),
          activity.endMinute ?? (activity.startMinute ?? 0),
        );
        final gcal.Event event = gcal.Event()
          ..summary = activity.title
          ..start = (gcal.EventDateTime()..dateTime = start.toUtc())
          ..end = (gcal.EventDateTime()..dateTime = end.toUtc());
        await _calendarApi!.events.insert(event, 'primary');
        exported++;
      }
      setState(() {
        _lastGoogleSyncAt = DateTime.now();
      });
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported $exported event(s) to Google Calendar'),
          backgroundColor: const Color(0xFF3ECF8E),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Calendar export failed: $error'),
            backgroundColor: const Color(0xFFE83E76),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingCalendar = false;
        });
      }
    }
  }

  String _sectionLabel(TrackerSection section) {
    switch (section) {
      case TrackerSection.today:
        return 'Today';
      case TrackerSection.activities:
        return 'Activities';
      case TrackerSection.hobbies:
        return 'Hobbies';
      case TrackerSection.dailyTasks:
        return 'Daily Tasks';
      case TrackerSection.todoList:
        return 'To-Do List';
      case TrackerSection.checklist:
        return 'Checklist';
      case TrackerSection.weeklyPlanner:
        return 'Weekly Planner';
      case TrackerSection.timer:
        return 'Timer';
      case TrackerSection.profile:
        return 'Profile';
      case TrackerSection.settings:
        return 'Settings';
    }
  }

  IconData _sectionIcon(TrackerSection section) {
    switch (section) {
      case TrackerSection.today:
        return Icons.today;
      case TrackerSection.activities:
        return Icons.widgets_rounded;
      case TrackerSection.hobbies:
        return Icons.palette_outlined;
      case TrackerSection.dailyTasks:
        return Icons.today_outlined;
      case TrackerSection.todoList:
        return Icons.task_alt_outlined;
      case TrackerSection.checklist:
        return Icons.checklist_outlined;
      case TrackerSection.weeklyPlanner:
        return Icons.calendar_view_week_rounded;
      case TrackerSection.timer:
        return Icons.timer_outlined;
      case TrackerSection.profile:
        return Icons.person_outline;
      case TrackerSection.settings:
        return Icons.settings_outlined;
    }
  }

  SectionVisualTheme _sectionVisual(TrackerSection section) {
    switch (section) {
      case TrackerSection.today:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFFE83E76),
            ocean: const Color(0xFF3BA7FF),
            sunshine: const Color(0xFFFFB347),
            midnight: const Color(0xFF9D7CFF),
            pearlLight: const Color(0xFFE45B93),
            mintLight: const Color(0xFF17B979),
            skyLight: const Color(0xFF4E8DFF),
          ),
          backgroundIcons: <IconData>[
            Icons.today,
            Icons.event_note,
            Icons.calendar_month,
          ],
        );
      case TrackerSection.activities:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFF57CC99),
            ocean: const Color(0xFF4CC9F0),
            sunshine: const Color(0xFFFFC857),
            midnight: const Color(0xFF7DD3FC),
            pearlLight: const Color(0xFF3AAE7A),
            mintLight: const Color(0xFF12A8C8),
            skyLight: const Color(0xFF5A84F6),
          ),
          backgroundIcons: const <IconData>[
            Icons.palette_outlined,
            Icons.task_alt_rounded,
            Icons.extension_rounded,
          ],
        );
      case TrackerSection.hobbies:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFF3ECF8E),
            ocean: const Color(0xFF4DD0E1),
            sunshine: const Color(0xFFFFD166),
            midnight: const Color(0xFF7CE7B8),
            pearlLight: const Color(0xFF29B36E),
            mintLight: const Color(0xFF179C81),
            skyLight: const Color(0xFF2D9ACD),
          ),
          backgroundIcons: <IconData>[
            Icons.pets_rounded,
            Icons.cruelty_free_rounded,
            Icons.emoji_nature_rounded,
          ],
        );
      case TrackerSection.dailyTasks:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFF4CC9F0),
            ocean: const Color(0xFF5FB0FF),
            sunshine: const Color(0xFFFFC857),
            midnight: const Color(0xFF8AB4FF),
            pearlLight: const Color(0xFF4A7DFF),
            mintLight: const Color(0xFF20B7A3),
            skyLight: const Color(0xFF4C86F9),
          ),
          backgroundIcons: <IconData>[
            Icons.sunny,
            Icons.wb_twilight_rounded,
            Icons.nights_stay_rounded,
          ],
        );
      case TrackerSection.todoList:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFFFF9F43),
            ocean: const Color(0xFF66C7F4),
            sunshine: const Color(0xFFFF9F1C),
            midnight: const Color(0xFFFFB86C),
            pearlLight: const Color(0xFFF28B1D),
            mintLight: const Color(0xFF7BAF25),
            skyLight: const Color(0xFFED8B4B),
          ),
          backgroundIcons: <IconData>[
            Icons.functions_rounded,
            Icons.calculate_rounded,
            Icons.percent_rounded,
          ],
        );
      case TrackerSection.checklist:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFFA78BFA),
            ocean: const Color(0xFF7C9DFF),
            sunshine: const Color(0xFFF7B267),
            midnight: const Color(0xFFB8A1FF),
            pearlLight: const Color(0xFF8B6CF2),
            mintLight: const Color(0xFF53B67B),
            skyLight: const Color(0xFF6F84F5),
          ),
          backgroundIcons: <IconData>[
            Icons.check_circle_rounded,
            Icons.rule_rounded,
            Icons.fact_check_rounded,
          ],
        );
      case TrackerSection.weeklyPlanner:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFFE83E76),
            ocean: const Color(0xFF4D96FF),
            sunshine: const Color(0xFFFF8C42),
            midnight: const Color(0xFF9A7BFF),
            pearlLight: const Color(0xFFE45B93),
            mintLight: const Color(0xFF24B5A0),
            skyLight: const Color(0xFF598AF7),
          ),
          backgroundIcons: <IconData>[
            Icons.school_rounded,
            Icons.menu_book_rounded,
            Icons.edit_calendar_rounded,
          ],
        );
      case TrackerSection.timer:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFFF4B400),
            ocean: const Color(0xFF00C2FF),
            sunshine: const Color(0xFFFFD23F),
            midnight: const Color(0xFF93D7FF),
            pearlLight: const Color(0xFFE6A400),
            mintLight: const Color(0xFF1BA8C7),
            skyLight: const Color(0xFF6489FF),
          ),
          backgroundIcons: <IconData>[
            Icons.timer,
            Icons.hourglass_bottom_rounded,
            Icons.alarm,
          ],
        );
      case TrackerSection.profile:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFF5FB0FF),
            ocean: const Color(0xFF4DD0E1),
            sunshine: const Color(0xFFFFC857),
            midnight: const Color(0xFF8DB4FF),
            pearlLight: const Color(0xFF7E74E8),
            mintLight: const Color(0xFF24A88E),
            skyLight: const Color(0xFF5C87F2),
          ),
          backgroundIcons: <IconData>[
            Icons.person,
            Icons.badge_outlined,
            Icons.manage_accounts_outlined,
          ],
        );
      case TrackerSection.settings:
        return SectionVisualTheme(
          colors: _themeBackgroundColors(),
          accent: _themeAccent(
            blossom: const Color(0xFF5FB0FF),
            ocean: const Color(0xFF4DD0E1),
            sunshine: const Color(0xFFFFC857),
            midnight: const Color(0xFF8DB4FF),
            pearlLight: const Color(0xFF7E74E8),
            mintLight: const Color(0xFF24A88E),
            skyLight: const Color(0xFF5C87F2),
          ),
          backgroundIcons: <IconData>[
            Icons.settings_outlined,
            Icons.tune_rounded,
            Icons.lock_outline,
          ],
        );
    }
  }

  List<DateTime> _continuousDates() {
    return List<DateTime>.generate(
      90,
      (int index) =>
          _dateOnly(_selectedPlannerDate.add(Duration(days: index - 7))),
    );
  }

  String _formatDateLabel(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.day}, ${date.year}';
  }

  Color _themeAccent({
    required Color blossom,
    required Color ocean,
    required Color sunshine,
    required Color midnight,
    required Color pearlLight,
    required Color mintLight,
    required Color skyLight,
  }) {
    switch (_themeChoice) {
      case AppThemeChoice.blossom:
        return blossom;
      case AppThemeChoice.ocean:
        return ocean;
      case AppThemeChoice.sunshine:
        return sunshine;
      case AppThemeChoice.midnight:
        return midnight;
      case AppThemeChoice.pearlLight:
        return pearlLight;
      case AppThemeChoice.mintLight:
        return mintLight;
      case AppThemeChoice.skyLight:
        return skyLight;
    }
  }

  List<Color> _themeBackgroundColors() {
    switch (_themeChoice) {
      case AppThemeChoice.blossom:
        return const <Color>[Color(0xFF140B13), Color(0xFF24111F)];
      case AppThemeChoice.ocean:
        return const <Color>[Color(0xFF08141F), Color(0xFF102536)];
      case AppThemeChoice.sunshine:
        return const <Color>[Color(0xFF1A1208), Color(0xFF2B1E0F)];
      case AppThemeChoice.midnight:
        return const <Color>[Color(0xFF090A16), Color(0xFF161B2F)];
      case AppThemeChoice.pearlLight:
        return const <Color>[Color(0xFFFDFBFF), Color(0xFFF1EDF7)];
      case AppThemeChoice.mintLight:
        return const <Color>[Color(0xFFF4FFF9), Color(0xFFEAFBF3)];
      case AppThemeChoice.skyLight:
        return const <Color>[Color(0xFFF8FBFF), Color(0xFFEAF2FF)];
    }
  }

  Color _themeSurfaceColor() {
    switch (_themeChoice) {
      case AppThemeChoice.blossom:
        return const Color(0xFF1A111B);
      case AppThemeChoice.ocean:
        return const Color(0xFF12202D);
      case AppThemeChoice.sunshine:
        return const Color(0xFF23170D);
      case AppThemeChoice.midnight:
        return const Color(0xFF12162A);
      case AppThemeChoice.pearlLight:
        return const Color(0xFFFFFFFF);
      case AppThemeChoice.mintLight:
        return const Color(0xFFFFFFFF);
      case AppThemeChoice.skyLight:
        return const Color(0xFFFFFFFF);
    }
  }

  Color _themeNavColor() {
    switch (_themeChoice) {
      case AppThemeChoice.blossom:
        return const Color(0xFF16181D);
      case AppThemeChoice.ocean:
        return const Color(0xFF101A24);
      case AppThemeChoice.sunshine:
        return const Color(0xFF1D160F);
      case AppThemeChoice.midnight:
        return const Color(0xFF101426);
      case AppThemeChoice.pearlLight:
        return const Color(0xFFE8DDEA);
      case AppThemeChoice.mintLight:
        return const Color(0xFFDDEDE5);
      case AppThemeChoice.skyLight:
        return const Color(0xFFDCE6F3);
    }
  }

  bool get _isLightTheme =>
      _themeChoice == AppThemeChoice.pearlLight ||
      _themeChoice == AppThemeChoice.mintLight ||
      _themeChoice == AppThemeChoice.skyLight;

  Color _primaryTextColor() {
    return _isLightTheme ? const Color(0xFF1F2937) : Colors.white;
  }

  Color _secondaryTextColor() {
    return _isLightTheme ? const Color(0xFF475569) : Colors.white70;
  }

  Color _mutedTextColor() {
    return _isLightTheme ? const Color(0xFF64748B) : Colors.white54;
  }

  Color _dividerColor() {
    return _isLightTheme ? const Color(0xFFD9DEE7) : const Color(0xFF2A2F39);
  }

  Color _chipSurfaceColor() {
    return _isLightTheme ? const Color(0xFFF0F4F8) : const Color(0xFF1B2029);
  }

  String _themeLabel(AppThemeChoice theme) {
    switch (theme) {
      case AppThemeChoice.blossom:
        return 'Blossom';
      case AppThemeChoice.ocean:
        return 'Ocean';
      case AppThemeChoice.sunshine:
        return 'Sunshine';
      case AppThemeChoice.midnight:
        return 'Midnight';
      case AppThemeChoice.pearlLight:
        return 'Pearl Light';
      case AppThemeChoice.mintLight:
        return 'Mint Light';
      case AppThemeChoice.skyLight:
        return 'Sky Light';
    }
  }

  String _headerWithUser(String pageTitle) {
    if (_isParentUser) {
      return '$pageTitle • $_motherName • $_activeChildName';
    }
    return '$pageTitle • $_profileOwnerName';
  }

  String _formatSyncTime(DateTime value) {
    final String month = _monthNames[value.month - 1];
    final String day = value.day.toString().padLeft(2, '0');
    final String hour = value.hour.toString().padLeft(2, '0');
    final String minute = value.minute.toString().padLeft(2, '0');
    return '$month $day, ${value.year} $hour:$minute';
  }

  Widget _buildHomeWelcomeStrip(SectionVisualTheme visual) {
    final bool isParent = _isParentUser;
    final String title =
        'Welcome, ${isParent ? _motherName : _profileOwnerName}';
    final String subtitle = isParent
        ? 'Managing today for $_activeChildName'
        : 'Planning for your $_userTypeLabel profile';
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _themeSurfaceColor(),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: visual.accent.withValues(alpha: 0.30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isLightTheme ? 0.05 : 0.20),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: visual.accent.withValues(alpha: 0.18),
            backgroundImage: _children[_selectedChildIndex].avatarBytes != null
                ? MemoryImage(_children[_selectedChildIndex].avatarBytes!)
                : null,
            child: _children[_selectedChildIndex].avatarBytes == null
                ? Icon(
                    _children[_selectedChildIndex].avatarIcon,
                    color: visual.accent,
                    size: 20,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: _primaryTextColor(),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: _secondaryTextColor(),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: visual.accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _userTypeLabel,
              style: TextStyle(
                color: visual.accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _googleCalendarHelpText() {
    if (_isGoogleConnected) {
      return _lastGoogleSyncAt == null
          ? 'Connected. Import or export events now.'
          : 'Connected. Last sync: ${_formatSyncTime(_lastGoogleSyncAt!)}';
    }
    if (kIsWeb) {
      return 'Needs Google web client setup. Run with GOOGLE_WEB_CLIENT_ID and enable Calendar API.';
    }
    return 'Needs Google Sign-In and Calendar API OAuth setup for this app before sync will work.';
  }

  Future<String?> _promptTextValue({
    required String title,
    required String initial,
    String hint = '',
  }) async {
    final TextEditingController controller = TextEditingController(
      text: initial,
    );
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptPinValue({
    required String title,
    required String hint,
  }) async {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            decoration: InputDecoration(hintText: hint, counterText: ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _setupParentPin() async {
    final String? firstPin = await _promptPinValue(
      title: 'Set Parent PIN',
      hint: 'Create 4-6 digit PIN',
    );
    if (firstPin == null) {
      return false;
    }
    final bool validFirstPin = RegExp(r'^\d{4,6}$').hasMatch(firstPin);
    if (!validFirstPin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN must be 4 to 6 digits'),
            backgroundColor: Color(0xFFE83E76),
          ),
        );
      }
      return false;
    }

    final String? confirmPin = await _promptPinValue(
      title: 'Confirm Parent PIN',
      hint: 'Re-enter PIN',
    );
    if (confirmPin == null) {
      return false;
    }
    if (confirmPin != firstPin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN does not match'),
            backgroundColor: Color(0xFFE83E76),
          ),
        );
      }
      return false;
    }

    setState(() {
      _parentPin = firstPin;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parent PIN set successfully'),
          backgroundColor: Color(0xFF3ECF8E),
        ),
      );
    }
    return true;
  }

  Future<bool> _verifyParentPin() async {
    if ((_parentPin ?? '').isEmpty) {
      return false;
    }
    final String? enteredPin = await _promptPinValue(
      title: 'Enter Parent PIN',
      hint: 'Enter PIN',
    );
    if (enteredPin == null) {
      return false;
    }
    if (enteredPin != _parentPin) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect PIN'),
            backgroundColor: Color(0xFFE83E76),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _pickProfilePhoto() async {
    final XFile? file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (file == null) {
      return;
    }
    final Uint8List bytes = await file.readAsBytes();
    setState(() {
      _children[_selectedChildIndex].avatarBytes = bytes;
    });
  }

  Future<void> _showAvatarPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF12151C),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose profile photo',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _avatarChoices.map((IconData icon) {
                    final bool selected =
                        _children[_selectedChildIndex].avatarBytes == null &&
                        _children[_selectedChildIndex].avatarIcon == icon;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _children[_selectedChildIndex].avatarBytes = null;
                          _children[_selectedChildIndex].avatarIcon = icon;
                        });
                        Navigator.of(context).pop();
                      },
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: selected
                            ? _sectionVisual(TrackerSection.profile).accent
                            : _chipSurfaceColor(),
                        child: Icon(
                          icon,
                          color: selected ? Colors.white : _primaryTextColor(),
                          size: 28,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () async {
                          Navigator.of(context).pop();
                          await _pickProfilePhoto();
                        },
                        icon: const Icon(Icons.upload_rounded),
                        label: const Text('Upload Photo'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () {
                          setState(() {
                            _children[_selectedChildIndex].avatarBytes = null;
                            _children[_selectedChildIndex].avatarIcon =
                                Icons.face_rounded;
                          });
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.restart_alt_rounded),
                        label: const Text('Reset'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatActivityTime(WeeklyActivity activity) {
    if (activity.startHour == null ||
        activity.startMinute == null ||
        activity.endHour == null ||
        activity.endMinute == null) {
      return 'Time not set';
    }
    String formatSingle(int hour, int minute) {
      final String period = hour >= 12 ? 'PM' : 'AM';
      final int hour12 = hour % 12 == 0 ? 12 : hour % 12;
      final String mm = minute.toString().padLeft(2, '0');
      return '$hour12:$mm $period';
    }

    return '${formatSingle(activity.startHour!, activity.startMinute!)} - '
        '${formatSingle(activity.endHour!, activity.endMinute!)}';
  }

  bool _itemOccursOnDate(TrackerItem item, DateTime date) {
    switch (item.repeatRule) {
      case RepeatRule.none:
        return true;
      case RepeatRule.daily:
        return true;
      case RepeatRule.weekly:
      case RepeatRule.customDays:
        return item.repeatWeekdays.contains(date.weekday);
    }
  }

  Future<int?> _promptTopPriorityNumber({int? initialValue}) async {
    final TextEditingController controller = TextEditingController(
      text: initialValue?.toString() ?? '',
    );
    final int? value = await showDialog<int>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Top Priority Number'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Enter rank number',
              hintText: '1',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(int.tryParse(controller.text.trim()));
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (value == null) {
      return null;
    }
    return value.clamp(1, 999);
  }

  Future<void> _toggleItemTopPriority(TrackerItem item) async {
    if (item.isHighPriority) {
      setState(() {
        item.isHighPriority = false;
        item.topPriorityNumber = null;
      });
      return;
    }
    final int? rank = await _promptTopPriorityNumber(
      initialValue: item.topPriorityNumber,
    );
    if (rank == null) {
      return;
    }
    setState(() {
      item.isHighPriority = true;
      item.topPriorityNumber = rank;
    });
  }

  Future<void> _toggleWeeklyTopPriority(WeeklyActivity activity) async {
    if (activity.isHighPriority) {
      setState(() {
        activity.isHighPriority = false;
        activity.topPriorityNumber = null;
      });
      return;
    }
    final int? rank = await _promptTopPriorityNumber(
      initialValue: activity.topPriorityNumber,
    );
    if (rank == null) {
      return;
    }
    setState(() {
      activity.isHighPriority = true;
      activity.topPriorityNumber = rank;
    });
  }

  Widget _buildTopPriorityDot({
    required bool selected,
    required int? rank,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFFE83E76) : Colors.transparent,
          border: Border.all(color: const Color(0xFFE83E76), width: 2),
        ),
        child: selected
            ? Center(
                child: Text(
                  '${rank ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Color _checkboxBaseColor() {
    return _isLightTheme ? Colors.black : Colors.white;
  }

  BorderSide _checkboxSide() {
    return BorderSide(color: _checkboxBaseColor(), width: 1.6);
  }

  Color _checkboxCheckColor() {
    return _isLightTheme ? Colors.white : Colors.black;
  }

  WidgetStateProperty<Color?> _checkboxFill() {
    return WidgetStateProperty.resolveWith<Color?>((Set<WidgetState> states) {
      if (states.contains(WidgetState.selected)) {
        return _checkboxBaseColor();
      }
      return Colors.transparent;
    });
  }

  void _showPointsEarnedMessage({required String title, required int points}) {
    if (!mounted || points <= 0) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You earned $points points for completing $title'),
        backgroundColor: const Color(0xFF3ECF8E),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleTrackerItemDone(TrackerItem item, bool value) {
    final bool wasDone = item.isDone;
    setState(() {
      item.isDone = value;
    });
    if (!wasDone && value && item.points > 0) {
      _showPointsEarnedMessage(title: item.title, points: item.points);
    }
  }

  List<HelpFaqItem> _faqItems() {
    return const <HelpFaqItem>[
      HelpFaqItem(
        question: 'How do I add a new hobby or task?',
        answer:
            'Open To-Do List, tap the + button, then choose whether the item is a hobby or a task before saving.',
      ),
      HelpFaqItem(
        question: 'How do recurring items work?',
        answer:
            'When you create an item, turn on Recurring task and choose daily, weekly, or selected days. It will appear automatically on matching dates.',
      ),
      HelpFaqItem(
        question: 'Where can I see what is completed?',
        answer:
            'On Today, To-Do List, and Checklist, completed items move into the Completed section below the active list.',
      ),
      HelpFaqItem(
        question: 'How are points earned?',
        answer:
            'Points are awarded when point-based items are completed. The earned total appears on the Profile page.',
      ),
      HelpFaqItem(
        question: 'How do filters work?',
        answer:
            'Use the filter button on Today to show only hobbies, tasks, to-do items, checklist items, or weekly plans.',
      ),
      HelpFaqItem(
        question: 'How does the timer work?',
        answer:
            'Use the Timer page when you want to study, read, or focus for a set block like 30 minutes. Set the time, press Start, and the app will track how much timer time you used today.',
      ),
      HelpFaqItem(
        question: 'How do profile types work?',
        answer:
            'During setup, choose whether the app is for an individual, student, parent, or kid. Parent-only controls appear only for parent accounts.',
      ),
    ];
  }

  String _nextTaskAnswer() {
    final List<TodayActivityEntry> pendingEntries = _todayEntriesFor(
      _selectedPlannerDate,
    ).where((TodayActivityEntry entry) => !entry.isDone).toList();
    final List<WeeklyActivity> pendingTimedActivities =
        _weeklyActivities
            .where(
              (WeeklyActivity activity) =>
                  _sameDate(activity.plannedDate, _selectedPlannerDate) &&
                  !activity.isDone &&
                  activity.startHour != null &&
                  activity.startMinute != null,
            )
            .toList()
          ..sort((WeeklyActivity a, WeeklyActivity b) {
            final DateTime aTime =
                _activityStartDateTime(a) ?? _selectedPlannerDate;
            final DateTime bTime =
                _activityStartDateTime(b) ?? _selectedPlannerDate;
            return aTime.compareTo(bTime);
          });

    if (pendingTimedActivities.isNotEmpty) {
      final WeeklyActivity next = pendingTimedActivities.first;
      return 'Your next scheduled task is ${next.title} at ${_formatActivityTime(next)}.';
    }
    if (pendingEntries.isNotEmpty) {
      final TodayActivityEntry next = pendingEntries.first;
      return 'Your next pending item is ${next.title} under ${next.category}.';
    }
    return 'There is no pending task on ${_formatDateLabel(_selectedPlannerDate)}.';
  }

  String _highPriorityTodayAnswer(String query) {
    final List<TodayActivityEntry> entries = _todayEntriesFor(
      _selectedPlannerDate,
    );
    final bool onlyTasks = query.contains('task');
    final bool onlyChecklist = query.contains('checklist');
    final bool onlyHobbies = query.contains('hobb');
    final Iterable<TodayActivityEntry> filtered = entries.where((
      TodayActivityEntry entry,
    ) {
      if (entry.priority != ItemPriority.high && !entry.isHighPriority) {
        return false;
      }
      if (onlyTasks) {
        return entry.category == 'Task' ||
            entry.category == 'To-Do' ||
            entry.category == 'Weekly';
      }
      if (onlyChecklist) {
        return entry.category == 'Checklist';
      }
      if (onlyHobbies) {
        return entry.category == 'Hobby';
      }
      return true;
    });
    final List<TodayActivityEntry> matches = filtered.toList();
    if (matches.isEmpty) {
      if (onlyTasks) {
        return 'There are no high priority tasks on ${_formatDateLabel(_selectedPlannerDate)}.';
      }
      if (onlyChecklist) {
        return 'There are no high priority checklist items on ${_formatDateLabel(_selectedPlannerDate)}.';
      }
      if (onlyHobbies) {
        return 'There are no high priority hobbies on ${_formatDateLabel(_selectedPlannerDate)}.';
      }
      return 'There are no high priority items on ${_formatDateLabel(_selectedPlannerDate)}.';
    }
    final String names = matches
        .take(3)
        .map((TodayActivityEntry entry) => entry.title)
        .join(', ');
    final String suffix = matches.length > 3 ? ', and more' : '';
    if (onlyTasks) {
      return 'Yes. High priority tasks today are $names$suffix.';
    }
    if (onlyChecklist) {
      return 'Yes. High priority checklist items today are $names$suffix.';
    }
    if (onlyHobbies) {
      return 'Yes. High priority hobbies today are $names$suffix.';
    }
    return 'Yes. High priority items today are $names$suffix.';
  }

  String _completionStatusAnswer(String query) {
    final List<TodayActivityEntry> entries = _todayEntriesFor(
      _selectedPlannerDate,
    );
    final int completed = entries
        .where((TodayActivityEntry entry) => entry.isDone)
        .length;
    final int pending = entries.length - completed;
    if (query.contains('complete') || query.contains('completed')) {
      return 'You completed $completed item(s) and still have $pending pending on ${_formatDateLabel(_selectedPlannerDate)}.';
    }
    return 'There are $pending pending item(s) and $completed completed item(s) on ${_formatDateLabel(_selectedPlannerDate)}.';
  }

  String _assistantReply(String message) {
    final String query = message.trim().toLowerCase();
    if (query.isEmpty) {
      return 'Ask about your next task, recurring items, points, filters, or parent mode.';
    }
    if (query.contains('next')) {
      return _nextTaskAnswer();
    }
    if (query.contains('high priority') ||
        query.contains('top priority') ||
        query.contains('priority today')) {
      return _highPriorityTodayAnswer(query);
    }
    if (query.contains('pending') ||
        query.contains('completed') ||
        query.contains('complete today')) {
      return _completionStatusAnswer(query);
    }
    if (query.contains('recurring') || query.contains('repeat')) {
      return 'Create an item from To-Do List, switch on Recurring task, then choose daily, weekly, or selected days.';
    }
    if (query.contains('point')) {
      return 'Points are added when point-based items are completed. You can review the total in Profile.';
    }
    if (query.contains('timer') ||
        query.contains('study') ||
        query.contains('read for')) {
      return 'Use the Timer page when you want to study or read for a set block like 30 minutes. Start the timer there, and Activities will show how much timer time you used today.';
    }
    if (query.contains('filter') ||
        query.contains('task') ||
        query.contains('checklist') ||
        query.contains('hobby')) {
      return 'Use the filter icon on Today to show only hobbies, tasks, checklist items, to-do items, or weekly plans.';
    }
    if (query.contains('parent') ||
        query.contains('pin') ||
        query.contains('kid') ||
        query.contains('profile type')) {
      return _isParentUser
          ? 'This account is set up as Parent, so parent PIN and child profile controls are available in Profile.'
          : 'This account is set up as $_userTypeLabel, so only personal profile controls are shown.';
    }
    if (query.contains('calendar') || query.contains('date')) {
      return 'Use the top date strip or the calendar icon to move to another day and review or add activities there.';
    }
    return 'I can help with next task, recurring items, filters, points, parent mode, and calendar navigation.';
  }

  Future<void> _openHelpCenter() async {
    final TextEditingController chatController = TextEditingController();
    String assistantMessage = _nextTaskAnswer();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _themeSurfaceColor(),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: _sectionVisual(
                              TrackerSection.today,
                            ).accent.withValues(alpha: 0.16),
                            child: Icon(
                              Icons.support_agent_rounded,
                              color: _sectionVisual(
                                TrackerSection.today,
                              ).accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Help & Assistant',
                              style: TextStyle(
                                color: _primaryTextColor(),
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'FAQs',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ..._faqItems().map((HelpFaqItem item) {
                        return ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: const EdgeInsets.only(bottom: 12),
                          iconColor: _secondaryTextColor(),
                          collapsedIconColor: _secondaryTextColor(),
                          title: Text(
                            item.question,
                            style: TextStyle(
                              color: _primaryTextColor(),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                item.answer,
                                style: TextStyle(
                                  color: _secondaryTextColor(),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        );
                      }),
                      const SizedBox(height: 12),
                      Text(
                        'Mini Assistant',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _chipSurfaceColor(),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _dividerColor()),
                        ),
                        child: Text(
                          assistantMessage,
                          style: TextStyle(
                            color: _primaryTextColor(),
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                              'What is my next task?',
                              'Are there any high priority tasks today?',
                              'How does the timer work?',
                              'How do recurring tasks work?',
                              'How do points work?',
                            ].map((String prompt) {
                              return ActionChip(
                                label: Text(prompt),
                                onPressed: () {
                                  setSheetState(() {
                                    assistantMessage = _assistantReply(prompt);
                                  });
                                },
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: chatController,
                        style: TextStyle(color: _primaryTextColor()),
                        decoration: InputDecoration(
                          hintText: 'Ask about next task, points, filters...',
                          hintStyle: TextStyle(color: _mutedTextColor()),
                          filled: true,
                          fillColor: _chipSurfaceColor(),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: _dividerColor()),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(color: _dividerColor()),
                          ),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setSheetState(() {
                                assistantMessage = _assistantReply(
                                  chatController.text,
                                );
                              });
                            },
                            icon: Icon(
                              Icons.send_rounded,
                              color: _sectionVisual(
                                TrackerSection.today,
                              ).accent,
                            ),
                          ),
                        ),
                        onSubmitted: (String value) {
                          setSheetState(() {
                            assistantMessage = _assistantReply(value);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    chatController.dispose();
  }

  List<TodayActivityEntry> _applyTodayCategoryFilters(
    List<TodayActivityEntry> entries,
  ) {
    return entries.where((TodayActivityEntry entry) {
      final bool categoryMatch =
          _todayCategoryFilters.isEmpty ||
          _todayCategoryFilters.contains(entry.category);
      final bool priorityMatch =
          _todayPriorityFilters.isEmpty ||
          _todayPriorityFilters.contains(entry.priority);
      return categoryMatch && priorityMatch;
    }).toList();
  }

  Future<void> _openTodayFilterSheet() async {
    final Set<String> draftFilters = Set<String>.from(_todayCategoryFilters);
    final Set<ItemPriority> draftPriorities = Set<ItemPriority>.from(
      _todayPriorityFilters,
    );
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _themeSurfaceColor(),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filter Today',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Show only the activity types and priorities you want to see.',
                        style: TextStyle(
                          color: _secondaryTextColor(),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _todayFilterCategories.map((String category) {
                          final bool selected = draftFilters.contains(category);
                          return FilterChip(
                            label: Text(category),
                            selected: selected,
                            labelStyle: TextStyle(
                              color: _primaryTextColor(),
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            backgroundColor: _chipSurfaceColor(),
                            selectedColor: _sectionVisual(
                              TrackerSection.today,
                            ).accent.withValues(alpha: 0.20),
                            side: BorderSide(
                              color: selected
                                  ? _sectionVisual(TrackerSection.today).accent
                                  : _dividerColor(),
                            ),
                            onSelected: (bool value) {
                              setSheetState(() {
                                if (value) {
                                  draftFilters.add(category);
                                } else {
                                  draftFilters.remove(category);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Priority',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _todayFilterPriorities.map((
                          ItemPriority priority,
                        ) {
                          final bool selected = draftPriorities.contains(
                            priority,
                          );
                          final Color priorityColor = _priorityColor(priority);
                          return FilterChip(
                            label: Text('${_priorityLabel(priority)} Priority'),
                            selected: selected,
                            labelStyle: TextStyle(
                              color: selected
                                  ? priorityColor
                                  : _primaryTextColor(),
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                            backgroundColor: _chipSurfaceColor(),
                            selectedColor: priorityColor.withValues(
                              alpha: 0.16,
                            ),
                            side: BorderSide(
                              color: selected ? priorityColor : _dividerColor(),
                            ),
                            onSelected: (bool value) {
                              setSheetState(() {
                                if (value) {
                                  draftPriorities.add(priority);
                                } else {
                                  draftPriorities.remove(priority);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                draftFilters.clear();
                                draftPriorities.clear();
                              });
                            },
                            child: const Text('Clear'),
                          ),
                          const Spacer(),
                          FilledButton(
                            onPressed: () {
                              setState(() {
                                _todayCategoryFilters
                                  ..clear()
                                  ..addAll(draftFilters);
                                _todayPriorityFilters
                                  ..clear()
                                  ..addAll(draftPriorities);
                              });
                              Navigator.of(context).pop();
                            },
                            child: const Text('Apply'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<TodaySearchResult> _searchTodayResults(String query) {
    final String normalizedQuery = query.trim().toLowerCase();
    final Iterable<DateTime> dates = _continuousDates();
    final List<TodaySearchResult> matches = <TodaySearchResult>[];
    for (final DateTime date in dates) {
      final List<TodayActivityEntry> entries = _applyTodayCategoryFilters(
        _todayEntriesFor(date),
      );
      for (final TodayActivityEntry entry in entries) {
        if (normalizedQuery.isEmpty) {
          matches.add(TodaySearchResult(entry: entry, date: date));
          continue;
        }
        final String priority = entry.priority.name.toLowerCase();
        final String dateLabel = _formatDateLabel(date).toLowerCase();
        final String weekdayLabel = _weekDays[date.weekday - 1].toLowerCase();
        final bool matched =
            entry.title.toLowerCase().contains(normalizedQuery) ||
            entry.category.toLowerCase().contains(normalizedQuery) ||
            priority.contains(normalizedQuery) ||
            dateLabel.contains(normalizedQuery) ||
            weekdayLabel.contains(normalizedQuery) ||
            (entry.points > 0 && '${entry.points}'.contains(normalizedQuery));
        if (matched) {
          matches.add(TodaySearchResult(entry: entry, date: date));
        }
      }
    }
    return matches;
  }

  Future<void> _openTodaySearch() async {
    final TextEditingController controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _themeSurfaceColor(),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final List<TodaySearchResult> filtered = _searchTodayResults(
              controller.text,
            );

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search Today',
                      style: TextStyle(
                        color: _primaryTextColor(),
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      onChanged: (_) => setSheetState(() {}),
                      style: TextStyle(color: _primaryTextColor()),
                      decoration: InputDecoration(
                        hintText: 'Search tasks, hobbies, checklist...',
                        hintStyle: TextStyle(color: _mutedTextColor()),
                        prefixIcon: Icon(
                          Icons.search,
                          color: _secondaryTextColor(),
                        ),
                        filled: true,
                        fillColor: _chipSurfaceColor(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: _dividerColor()),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: _dividerColor()),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'No matching activities found',
                          style: TextStyle(color: _secondaryTextColor()),
                        ),
                      )
                    else
                      SizedBox(
                        height: 280,
                        child: ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              Divider(color: _dividerColor(), height: 1),
                          itemBuilder: (BuildContext context, int index) {
                            final TodaySearchResult result = filtered[index];
                            final TodayActivityEntry entry = result.entry;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              onTap: () {
                                setState(() {
                                  _selectedPlannerDate = result.date;
                                });
                                Navigator.of(context).pop();
                              },
                              leading: CircleAvatar(
                                backgroundColor: entry.color.withValues(
                                  alpha: 0.16,
                                ),
                                child: Icon(entry.icon, color: entry.color),
                              ),
                              title: Text(
                                entry.title,
                                style: TextStyle(
                                  color: _primaryTextColor(),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${entry.category} • ${_formatDateLabel(result.date)}',
                                style: TextStyle(color: _secondaryTextColor()),
                              ),
                              trailing: entry.points > 0
                                  ? Text(
                                      '${entry.points} pts',
                                      style: TextStyle(
                                        color: entry.color,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<TodayActivityEntry> _todayEntriesFor(DateTime date) {
    final List<TodayActivityEntry> entries = <TodayActivityEntry>[];

    void addFromSection(
      TrackerSection section,
      String category,
      IconData icon,
      Color color,
    ) {
      final List<TrackerItem> list = _items[section] ?? <TrackerItem>[];
      for (final TrackerItem item in list) {
        if (!_itemOccursOnDate(item, date)) {
          continue;
        }
        entries.add(
          TodayActivityEntry(
            title: item.title,
            category: category,
            icon: icon,
            color: color,
            priority: item.priority,
            points: item.points,
            isDone: item.isDone,
            onToggleDone: (bool value) {
              _toggleTrackerItemDone(item, value);
            },
            isHighPriority: item.isHighPriority,
            topPriorityNumber: item.topPriorityNumber,
            onTapPriority: () => _toggleItemTopPriority(item),
          ),
        );
      }
    }

    addFromSection(
      TrackerSection.hobbies,
      'Hobby',
      Icons.palette,
      const Color(0xFF3ECF8E),
    );
    addFromSection(
      TrackerSection.dailyTasks,
      'Task',
      Icons.task_alt,
      const Color(0xFF4CC9F0),
    );
    addFromSection(
      TrackerSection.todoList,
      'To-Do',
      Icons.check_circle,
      const Color(0xFFFF9F43),
    );
    addFromSection(
      TrackerSection.checklist,
      'Checklist',
      Icons.checklist,
      const Color(0xFFA78BFA),
    );

    for (final WeeklyActivity activity in _weeklyActivities) {
      if (!_sameDate(activity.plannedDate, date)) {
        continue;
      }
      entries.add(
        TodayActivityEntry(
          title: activity.title,
          category: 'Weekly',
          icon: Icons.calendar_today,
          color: const Color(0xFFE83E76),
          priority: activity.priority,
          points: 0,
          isDone: activity.isDone,
          onToggleDone: (bool value) {
            setState(() {
              activity.isDone = value;
            });
          },
          isHighPriority: activity.isHighPriority,
          topPriorityNumber: activity.topPriorityNumber,
          onTapPriority: () => _toggleWeeklyTopPriority(activity),
        ),
      );
    }

    return entries;
  }

  void _moveWeeklyActivityWithinDate(WeeklyActivity activity, int direction) {
    final List<int> sameDateIndexes = <int>[];
    for (int i = 0; i < _weeklyActivities.length; i++) {
      if (_sameDate(_weeklyActivities[i].plannedDate, _selectedPlannerDate)) {
        sameDateIndexes.add(i);
      }
    }
    final int currentGlobalIndex = _weeklyActivities.indexOf(activity);
    final int currentLocalIndex = sameDateIndexes.indexOf(currentGlobalIndex);
    if (currentLocalIndex < 0) {
      return;
    }
    final int targetLocalIndex = currentLocalIndex + direction;
    if (targetLocalIndex < 0 || targetLocalIndex >= sameDateIndexes.length) {
      return;
    }
    final int targetGlobalIndex = sameDateIndexes[targetLocalIndex];
    setState(() {
      final WeeklyActivity moving = _weeklyActivities.removeAt(
        currentGlobalIndex,
      );
      final int insertIndex = currentGlobalIndex < targetGlobalIndex
          ? targetGlobalIndex - 1
          : targetGlobalIndex;
      _weeklyActivities.insert(insertIndex, moving);
    });
  }

  DateTime _monthStart(DateTime date) => DateTime(date.year, date.month, 1);

  int _daysInMonth(DateTime monthDate) {
    return DateTime(monthDate.year, monthDate.month + 1, 0).day;
  }

  Future<DateTime?> _openCalendarSheet() async {
    DateTime displayMonth = _monthStart(_selectedPlannerDate);
    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final int firstWeekday = DateTime(
              displayMonth.year,
              displayMonth.month,
              1,
            ).weekday; // Mon=1..Sun=7
            final int startOffset = firstWeekday % 7; // Sun=0..Sat=6
            final int daysThisMonth = _daysInMonth(displayMonth);
            final DateTime prevMonth = DateTime(
              displayMonth.year,
              displayMonth.month - 1,
              1,
            );
            final int daysPrevMonth = _daysInMonth(prevMonth);

            return SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F1218),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            setSheetState(() {
                              displayMonth = DateTime(
                                displayMonth.year,
                                displayMonth.month - 1,
                                1,
                              );
                            });
                          },
                          icon: const Icon(
                            Icons.chevron_left,
                            color: Color(0xFFE83E76),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                _monthNames[displayMonth.month - 1],
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${displayMonth.year}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setSheetState(() {
                              displayMonth = DateTime(
                                displayMonth.year,
                                displayMonth.month + 1,
                                1,
                              );
                            });
                          },
                          icon: const Icon(
                            Icons.chevron_right,
                            color: Color(0xFFE83E76),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: _weekDaysSunFirst
                          .map(
                            (String day) => Expanded(
                              child: Center(
                                child: Text(
                                  day,
                                  style: TextStyle(
                                    color: day == 'Sun' || day == 'Sat'
                                        ? const Color(0xFFE83E76)
                                        : Colors.white70,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 42,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                            childAspectRatio: 1,
                          ),
                      itemBuilder: (BuildContext context, int index) {
                        late final DateTime date;
                        late final bool inCurrentMonth;
                        if (index < startOffset) {
                          final int day =
                              daysPrevMonth - startOffset + index + 1;
                          date = DateTime(prevMonth.year, prevMonth.month, day);
                          inCurrentMonth = false;
                        } else if (index < startOffset + daysThisMonth) {
                          final int day = index - startOffset + 1;
                          date = DateTime(
                            displayMonth.year,
                            displayMonth.month,
                            day,
                          );
                          inCurrentMonth = true;
                        } else {
                          final int day =
                              index - (startOffset + daysThisMonth) + 1;
                          final DateTime nextMonth = DateTime(
                            displayMonth.year,
                            displayMonth.month + 1,
                            1,
                          );
                          date = DateTime(nextMonth.year, nextMonth.month, day);
                          inCurrentMonth = false;
                        }

                        final bool selected = _sameDate(
                          date,
                          _selectedPlannerDate,
                        );
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(date),
                          child: Container(
                            decoration: BoxDecoration(
                              color: selected
                                  ? const Color(0xFFE83E76)
                                  : const Color(0xFF1B2029),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : (inCurrentMonth
                                            ? Colors.white70
                                            : Colors.white30),
                                  fontSize: 16,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'CLOSE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.of(
                              context,
                            ).pop(_dateOnly(DateTime.now())),
                            child: const Text(
                              'TODAY',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _repeatLabel(TrackerItem item) {
    switch (item.repeatRule) {
      case RepeatRule.none:
        return 'One-time';
      case RepeatRule.daily:
        return 'Daily';
      case RepeatRule.weekly:
        if (item.repeatWeekdays.isEmpty) {
          return 'Weekly';
        }
        return 'Weekly • ${_weekDays[item.repeatWeekdays.first - 1]}';
      case RepeatRule.customDays:
        if (item.repeatWeekdays.isEmpty) {
          return 'Few days';
        }
        final List<String> labels = item.repeatWeekdays
            .map((int weekday) => _weekDays[weekday - 1])
            .toList();
        return 'Few days • ${labels.join(', ')}';
    }
  }

  String _priorityLabel(ItemPriority priority) {
    switch (priority) {
      case ItemPriority.high:
        return 'High';
      case ItemPriority.medium:
        return 'Medium';
      case ItemPriority.low:
        return 'Low';
    }
  }

  FontWeight _priorityFontWeight(ItemPriority priority) {
    switch (priority) {
      case ItemPriority.high:
        return FontWeight.w800;
      case ItemPriority.medium:
        return FontWeight.w600;
      case ItemPriority.low:
        return FontWeight.w500;
    }
  }

  Color _priorityColor(ItemPriority priority) {
    switch (priority) {
      case ItemPriority.high:
        return const Color(0xFFFF5D73);
      case ItemPriority.medium:
        return const Color(0xFFFFB84D);
      case ItemPriority.low:
        return const Color(0xFF7FDBA9);
    }
  }

  void _startTimer() {
    if (_isTimerRunning || _timerSecondsRemaining <= 0) {
      return;
    }
    setState(() {
      _isTimerRunning = true;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      final String todayKey = _dateStorageKey(_dateOnly(DateTime.now()));
      if (_timerSecondsRemaining <= 1) {
        timer.cancel();
        setState(() {
          _timerSecondsRemaining = 0;
          _isTimerRunning = false;
          _timerUsageSecondsByDate[todayKey] =
              (_timerUsageSecondsByDate[todayKey] ?? 0) + 1;
        });
      } else {
        setState(() {
          _timerSecondsRemaining--;
          _timerUsageSecondsByDate[todayKey] =
              (_timerUsageSecondsByDate[todayKey] ?? 0) + 1;
        });
      }
    });
  }

  Future<void> _handleTimerPrimaryAction() async {
    if (_isTimerRunning) {
      _pauseTimer();
      return;
    }
    if (_timerSecondsRemaining <= 0) {
      await _setTimerDuration();
    }
    if (_timerSecondsRemaining > 0) {
      _startTimer();
    }
  }

  void _pauseTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _isTimerRunning = false;
    });
  }

  void _resetTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _timerSecondsRemaining = 0;
      _isTimerRunning = false;
    });
  }

  Future<void> _setTimerDuration() async {
    final TextEditingController minutesController = TextEditingController(
      text: (_timerSecondsRemaining ~/ 60).toString(),
    );
    final TextEditingController secondsController = TextEditingController(
      text: (_timerSecondsRemaining % 60).toString(),
    );

    final Map<String, int>? value = await showDialog<Map<String, int>>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Set Timer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minutesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: secondsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Seconds'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(<String, int>{
                  'minutes': int.tryParse(minutesController.text.trim()) ?? 0,
                  'seconds': int.tryParse(secondsController.text.trim()) ?? 0,
                });
              },
              child: const Text('Set'),
            ),
          ],
        );
      },
    );

    if (value == null) {
      return;
    }
    final int minutes = value['minutes']!.clamp(0, 999);
    final int seconds = value['seconds']!.clamp(0, 59);
    _countdownTimer?.cancel();
    setState(() {
      _isTimerRunning = false;
      _timerSecondsRemaining = (minutes * 60) + seconds;
    });
  }

  String _formatTime(int seconds) {
    final int minutesPart = seconds ~/ 60;
    final int secondsPart = seconds % 60;
    final String mm = minutesPart.toString().padLeft(2, '0');
    final String ss = secondsPart.toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  void _moveItemWithinCompletionGroup(
    List<TrackerItem> allItems,
    TrackerItem item,
    int direction,
    bool isDoneGroup,
  ) {
    final List<int> sameGroupIndexes = <int>[];
    for (int i = 0; i < allItems.length; i++) {
      if (allItems[i].isDone == isDoneGroup) {
        sameGroupIndexes.add(i);
      }
    }
    final int currentGlobalIndex = allItems.indexOf(item);
    final int currentLocalIndex = sameGroupIndexes.indexOf(currentGlobalIndex);
    if (currentLocalIndex < 0) {
      return;
    }
    final int targetLocalIndex = currentLocalIndex + direction;
    if (targetLocalIndex < 0 || targetLocalIndex >= sameGroupIndexes.length) {
      return;
    }
    final int targetGlobalIndex = sameGroupIndexes[targetLocalIndex];
    setState(() {
      final TrackerItem moving = allItems.removeAt(currentGlobalIndex);
      final int insertIndex = currentGlobalIndex < targetGlobalIndex
          ? targetGlobalIndex - 1
          : targetGlobalIndex;
      allItems.insert(insertIndex, moving);
    });
  }

  Widget _buildTaskCard({
    required TrackerItem item,
    required List<TrackerItem> allItems,
    required int groupIndex,
    required int groupLength,
    required bool showPoints,
    required bool isCompletedGroup,
    required Color accent,
  }) {
    return Card(
      color: _themeSurfaceColor(),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _priorityColor(item.priority).withValues(alpha: 0.24),
        ),
      ),
      child: CheckboxListTile(
        value: item.isDone,
        fillColor: _checkboxFill(),
        checkColor: _checkboxCheckColor(),
        side: _checkboxSide(),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      color: item.isHighPriority
                          ? const Color(0xFFFF879E)
                          : _priorityColor(item.priority),
                      fontWeight: item.isHighPriority
                          ? FontWeight.w800
                          : _priorityFontWeight(item.priority),
                      decoration: item.isDone
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _priorityColor(
                        item.priority,
                      ).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_priorityLabel(item.priority)} Priority',
                      style: TextStyle(
                        color: _priorityColor(item.priority),
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (showPoints)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${item.points} pts',
                  style: TextStyle(
                    color: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          _repeatLabel(item),
          style: TextStyle(color: _secondaryTextColor()),
        ),
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (bool? value) {
          _toggleTrackerItemDone(item, value ?? false);
        },
        secondary: SizedBox(
          width: 156,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildTopPriorityDot(
                selected: item.isHighPriority,
                rank: item.topPriorityNumber,
                onTap: () async => _toggleItemTopPriority(item),
              ),
              const SizedBox(width: 10),
              if (groupIndex > 0)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.keyboard_arrow_up,
                    color: _primaryTextColor(),
                  ),
                  tooltip: 'Move up',
                  onPressed: () => _moveItemWithinCompletionGroup(
                    allItems,
                    item,
                    -1,
                    isCompletedGroup,
                  ),
                ),
              if (groupIndex < groupLength - 1)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    color: _primaryTextColor(),
                  ),
                  tooltip: 'Move down',
                  onPressed: () => _moveItemWithinCompletionGroup(
                    allItems,
                    item,
                    1,
                    isCompletedGroup,
                  ),
                ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline, color: _primaryTextColor()),
                tooltip: 'Delete',
                onPressed: () {
                  setState(() {
                    allItems.remove(item);
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRegularSection(
    List<TrackerItem> currentItems,
    Color accent, {
    bool embedded = false,
  }) {
    final bool showPoints =
        _currentSection == TrackerSection.todoList ||
        _currentSection == TrackerSection.checklist;
    final List<TrackerItem> pendingItems = currentItems
        .where((TrackerItem item) => !item.isDone)
        .toList();
    final List<TrackerItem> completedItems = currentItems
        .where((TrackerItem item) => item.isDone)
        .toList();
    return currentItems.isEmpty
        ? const Center(
            child: Text(
              'No items yet. Add one to get started.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        : ListView(
            padding: embedded
                ? EdgeInsets.zero
                : const EdgeInsets.only(bottom: 90),
            shrinkWrap: embedded,
            physics: embedded
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            children: [
              ...List<Widget>.generate(pendingItems.length, (int index) {
                final TrackerItem item = pendingItems[index];
                return _buildTaskCard(
                  item: item,
                  allItems: currentItems,
                  groupIndex: index,
                  groupLength: pendingItems.length,
                  showPoints: showPoints,
                  isCompletedGroup: false,
                  accent: accent,
                );
              }),
              if (completedItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 18,
                        color: Color(0xFF7FDBA9),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Completed Tasks (${completedItems.length})',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                ...List<Widget>.generate(completedItems.length, (int index) {
                  final TrackerItem item = completedItems[index];
                  return _buildTaskCard(
                    item: item,
                    allItems: currentItems,
                    groupIndex: index,
                    groupLength: completedItems.length,
                    showPoints: showPoints,
                    isCompletedGroup: true,
                    accent: accent,
                  );
                }),
              ],
            ],
          );
  }

  Widget _buildActivitiesOverviewCard({
    required String label,
    required IconData icon,
    required Color color,
    required int total,
    required int completed,
    required int remaining,
    String? helper,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _themeSurfaceColor(),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '$completed achieved',
            style: TextStyle(
              color: _primaryTextColor(),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$remaining left out of $total',
            style: TextStyle(color: _secondaryTextColor(), fontSize: 12),
          ),
          if ((helper ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              helper!,
              style: TextStyle(color: _mutedTextColor(), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActivitiesScaffold() {
    final SectionVisualTheme visualTheme = _sectionVisual(
      TrackerSection.activities,
    );
    final int hobbyTotal = _hobbyItems.length;
    final int hobbyCompleted = _hobbyItems
        .where((TrackerItem x) => x.isDone)
        .length;
    final int hobbyRemaining = hobbyTotal - hobbyCompleted;
    final int taskTotal = _taskItems.length;
    final int taskCompleted = _taskItems
        .where((TrackerItem x) => x.isDone)
        .length;
    final int taskRemaining = taskTotal - taskCompleted;
    final int checklistTotal = _checklistItems.length;
    final int checklistCompleted = _checklistItems
        .where((TrackerItem x) => x.isDone)
        .length;
    final int checklistRemaining = checklistTotal - checklistCompleted;
    final int totalActivities = hobbyTotal + taskTotal + checklistTotal;
    final int totalCompleted =
        hobbyCompleted + taskCompleted + checklistCompleted;
    final int totalRemaining = totalActivities - totalCompleted;
    final int completionRate = totalActivities == 0
        ? 0
        : ((totalCompleted / totalActivities) * 100).round();
    final String todayTimerUsage = _formatTimerUsage(_todayTimerUsageSeconds);

    return Scaffold(
      backgroundColor: visualTheme.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _primaryTextColor(),
        elevation: 0,
        title: Text(_headerWithUser(_sectionLabel(TrackerSection.activities))),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: visualTheme.colors,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List<Widget>.generate(40, (int index) {
                    final IconData icon =
                        visualTheme.backgroundIcons[index %
                            visualTheme.backgroundIcons.length];
                    return Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        icon,
                        size: 26 + ((index % 4) * 4),
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    );
                  }),
                ),
              ),
            ),
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _themeSurfaceColor(),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: visualTheme.accent.withValues(alpha: 0.24),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Activity Analysis',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        totalActivities == 0
                            ? 'No hobbies, tasks, or checklist items added yet.'
                            : 'You achieved $totalCompleted activities and $totalRemaining are left.',
                        style: TextStyle(
                          color: _secondaryTextColor(),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _buildProgressChip(
                              label: 'Achieved',
                              value: '$totalCompleted',
                              color: const Color(0xFF3ECF8E),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildProgressChip(
                              label: 'Left',
                              value: '$totalRemaining',
                              color: const Color(0xFFFFB703),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildProgressChip(
                              label: 'Success',
                              value: '$completionRate%',
                              color: visualTheme.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Today you used the timer for $todayTimerUsage.',
                        style: TextStyle(
                          color: _secondaryTextColor(),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _buildActivitiesOverviewCard(
                        label: 'Hobbies',
                        icon: Icons.palette_outlined,
                        color: const Color(0xFF3ECF8E),
                        total: hobbyTotal,
                        completed: hobbyCompleted,
                        remaining: hobbyRemaining,
                        helper: hobbyTotal == 0
                            ? 'Add hobbies from To-Do List'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActivitiesOverviewCard(
                        label: 'Tasks',
                        icon: Icons.task_alt_rounded,
                        color: const Color(0xFF4CC9F0),
                        total: taskTotal,
                        completed: taskCompleted,
                        remaining: taskRemaining,
                        helper: taskTotal == 0
                            ? 'Add tasks from To-Do List'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _buildActivitiesOverviewCard(
                  label: 'Timer Today',
                  icon: Icons.timer_outlined,
                  color: visualTheme.accent,
                  total: 1,
                  completed: _todayTimerUsageSeconds > 0 ? 1 : 0,
                  remaining: 0,
                  helper: 'Used for $todayTimerUsage today',
                ),
                const SizedBox(height: 18),
                _buildActivitiesOverviewCard(
                  label: 'Checklist',
                  icon: Icons.checklist_rounded,
                  color: const Color(0xFFA78BFA),
                  total: checklistTotal,
                  completed: checklistCompleted,
                  remaining: checklistRemaining,
                  helper: checklistTotal == 0
                      ? 'Add checklist items from Checklist'
                      : null,
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _themeSurfaceColor(),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Summary',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        hobbyRemaining == 0 &&
                                taskRemaining == 0 &&
                                checklistRemaining == 0 &&
                                totalActivities > 0
                            ? 'Everything planned in hobbies, tasks, and checklist is completed.'
                            : 'Use the To-Do List tab for hobbies/tasks and Checklist tab for checklist items, then track progress during the day.',
                        style: TextStyle(
                          color: _secondaryTextColor(),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visualTheme.accent.withValues(alpha: 0.28),
      ),
    );
  }

  Widget _buildProgressChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: _secondaryTextColor(),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodoScaffold() {
    final SectionVisualTheme visualTheme = _sectionVisual(
      TrackerSection.todoList,
    );
    return Scaffold(
      backgroundColor: visualTheme.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _primaryTextColor(),
        elevation: 0,
        title: Text(_headerWithUser(_sectionLabel(TrackerSection.todoList))),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: visualTheme.colors,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 100),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _themeSurfaceColor(),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: visualTheme.accent.withValues(alpha: 0.22),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Combined Activities',
                    style: TextStyle(
                      color: _primaryTextColor(),
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add and manage hobbies and tasks here. When you create a new item, choose whether it is a hobby or a task.',
                    style: TextStyle(color: _secondaryTextColor(), height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Hobbies',
              style: TextStyle(
                color: _primaryTextColor(),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            _buildRegularSection(
              _hobbyItems,
              const Color(0xFF3ECF8E),
              embedded: true,
            ),
            const SizedBox(height: 18),
            Text(
              'Tasks',
              style: TextStyle(
                color: _primaryTextColor(),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            _buildRegularSection(
              _taskItems,
              const Color(0xFF4CC9F0),
              embedded: true,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: visualTheme.accent,
        foregroundColor: Colors.white,
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visualTheme.accent.withValues(alpha: 0.28),
      ),
    );
  }

  Widget _buildBottomNavBar({
    required Color background,
    required Color indicator,
  }) {
    final List<TrackerSection> visibleSections = <TrackerSection>[
      TrackerSection.today,
      TrackerSection.todoList,
      TrackerSection.checklist,
      TrackerSection.activities,
      TrackerSection.timer,
      TrackerSection.profile,
    ];
    final int selectedIndex = visibleSections.contains(_currentSection)
        ? visibleSections.indexOf(_currentSection)
        : 0;

    return NavigationBar(
      backgroundColor: background,
      indicatorColor: indicator,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((
        Set<WidgetState> states,
      ) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: _primaryTextColor(),
            fontWeight: FontWeight.w600,
          );
        }
        return TextStyle(color: _secondaryTextColor());
      }),
      selectedIndex: selectedIndex,
      destinations: visibleSections
          .map(
            (TrackerSection section) => NavigationDestination(
              icon: Icon(_sectionIcon(section), color: _secondaryTextColor()),
              selectedIcon: Icon(
                _sectionIcon(section),
                color: _primaryTextColor(),
              ),
              label: _sectionLabel(section),
            ),
          )
          .toList(),
      onDestinationSelected: (int index) {
        setState(() {
          _currentSection = visibleSections[index];
        });
      },
    );
  }

  void _openSectionFromDrawer(TrackerSection section) {
    Navigator.of(context).pop();
    setState(() {
      _currentSection = section;
    });
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    final Color accent = _sectionVisual(TrackerSection.today).accent;
    return ListTile(
      leading: Icon(icon, color: selected ? accent : _secondaryTextColor()),
      title: Text(
        label,
        style: TextStyle(
          color: _primaryTextColor(),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
      tileColor: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onTap: onTap,
    );
  }

  Widget _buildAppDrawer() {
    return Drawer(
      backgroundColor: _themeSurfaceColor(),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _profileOwnerName,
                      style: TextStyle(
                        color: _primaryTextColor(),
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isParentUser
                          ? 'Parent mode for $_motherName'
                          : '$_userTypeLabel profile',
                      style: TextStyle(color: _secondaryTextColor()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildDrawerItem(
                icon: Icons.today,
                label: 'Today',
                selected: _currentSection == TrackerSection.today,
                onTap: () => _openSectionFromDrawer(TrackerSection.today),
              ),
              _buildDrawerItem(
                icon: Icons.analytics_outlined,
                label: 'Activities',
                selected: _currentSection == TrackerSection.activities,
                onTap: () => _openSectionFromDrawer(TrackerSection.activities),
              ),
              _buildDrawerItem(
                icon: Icons.palette_outlined,
                label: 'Hobbies',
                selected: _currentSection == TrackerSection.todoList,
                onTap: () => _openSectionFromDrawer(TrackerSection.todoList),
              ),
              _buildDrawerItem(
                icon: Icons.task_alt_outlined,
                label: 'Tasks',
                selected: _currentSection == TrackerSection.todoList,
                onTap: () => _openSectionFromDrawer(TrackerSection.todoList),
              ),
              _buildDrawerItem(
                icon: Icons.checklist_outlined,
                label: 'Checklist',
                selected: _currentSection == TrackerSection.checklist,
                onTap: () => _openSectionFromDrawer(TrackerSection.checklist),
              ),
              _buildDrawerItem(
                icon: Icons.timer_outlined,
                label: 'Timer',
                selected: _currentSection == TrackerSection.timer,
                onTap: () => _openSectionFromDrawer(TrackerSection.timer),
              ),
              const Divider(height: 24),
              _buildDrawerItem(
                icon: Icons.person_outline,
                label: 'Profile',
                selected: _currentSection == TrackerSection.profile,
                onTap: () => _openSectionFromDrawer(TrackerSection.profile),
              ),
              _buildDrawerItem(
                icon: Icons.settings_outlined,
                label: 'Settings',
                selected: _currentSection == TrackerSection.settings,
                onTap: () => _openSectionFromDrawer(TrackerSection.settings),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  _isParentUser
                      ? 'Use Profile for theme, parent PIN, family, and sync settings.'
                      : 'Use Profile for theme, personal details, and sync settings.',
                  style: TextStyle(color: _mutedTextColor(), height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyPlannerView() {
    final List<DateTime> weekDates = _continuousDates();
    final List<WeeklyActivity> selectedDateActivities = _weeklyActivities.where(
      (WeeklyActivity activity) {
        return _sameDate(activity.plannedDate, _selectedPlannerDate);
      },
    ).toList();

    return Column(
      children: [
        const SizedBox(height: 4),
        SizedBox(
          height: 102,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            scrollDirection: Axis.horizontal,
            itemCount: weekDates.length,
            separatorBuilder: (BuildContext context, int index) =>
                const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int index) {
              final DateTime chipDate = weekDates[index];
              final bool selected = _sameDate(chipDate, _selectedPlannerDate);
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedPlannerDate = chipDate;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 72,
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFFE83E76)
                        : const Color(0xFF1A1E24),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekDays[chipDate.weekday - 1],
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _monthNames[chipDate.month - 1],
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.white60,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${chipDate.day}',
                        style: TextStyle(
                          color: selected ? Colors.white : _primaryTextColor(),
                          fontSize: 36,
                          height: 0.92,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: selectedDateActivities.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        color: Color(0xFFFF87AF),
                        size: 74,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No activities scheduled',
                        style: TextStyle(
                          color: _primaryTextColor(),
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Add something to plan your day',
                        style: TextStyle(
                          color: _secondaryTextColor(),
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                  itemCount: selectedDateActivities.length,
                  itemBuilder: (BuildContext context, int index) {
                    final WeeklyActivity activity =
                        selectedDateActivities[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: _themeSurfaceColor(),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _priorityColor(
                            activity.priority,
                          ).withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8D5BFF),
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        activity.title,
                                        style: TextStyle(
                                          color: activity.isHighPriority
                                              ? const Color(0xFFFF879E)
                                              : _priorityColor(
                                                  activity.priority,
                                                ),
                                          fontSize: 20,
                                          fontWeight: activity.isHighPriority
                                              ? FontWeight.w800
                                              : _priorityFontWeight(
                                                  activity.priority,
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _buildTopPriorityDot(
                                      selected: activity.isHighPriority,
                                      rank: activity.topPriorityNumber,
                                      onTap: () async =>
                                          _toggleWeeklyTopPriority(activity),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${_monthNames[activity.plannedDate.month - 1]} ${activity.plannedDate.day}',
                                  style: TextStyle(
                                    color: _secondaryTextColor(),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatActivityTime(activity),
                                  style: const TextStyle(
                                    color: Color(0xFFFF87AF),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _priorityColor(
                                      activity.priority,
                                    ).withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_priorityLabel(activity.priority)} Priority',
                                    style: TextStyle(
                                      color: _priorityColor(activity.priority),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Checkbox(
                            value: activity.isDone,
                            fillColor: _checkboxFill(),
                            checkColor: _checkboxCheckColor(),
                            side: _checkboxSide(),
                            onChanged: (bool? value) {
                              setState(() {
                                activity.isDone = value ?? false;
                              });
                            },
                          ),
                          SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (index > 0)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.keyboard_arrow_up,
                                      color: _primaryTextColor(),
                                    ),
                                    tooltip: 'Move up',
                                    onPressed: () =>
                                        _moveWeeklyActivityWithinDate(
                                          activity,
                                          -1,
                                        ),
                                  ),
                                if (index < selectedDateActivities.length - 1)
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(
                                      minWidth: 30,
                                      minHeight: 30,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      Icons.keyboard_arrow_down,
                                      color: _primaryTextColor(),
                                    ),
                                    tooltip: 'Move down',
                                    onPressed: () =>
                                        _moveWeeklyActivityWithinDate(
                                          activity,
                                          1,
                                        ),
                                  ),
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 30,
                                    minHeight: 30,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: _primaryTextColor(),
                                  ),
                                  tooltip: 'Remove activity',
                                  onPressed: () {
                                    setState(() {
                                      _weeklyActivities.remove(activity);
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTodayScaffold() {
    final List<DateTime> weekDates = _continuousDates();
    final List<TodayActivityEntry> entries = _applyTodayCategoryFilters(
      _todayEntriesFor(_selectedPlannerDate),
    );
    final List<TodayActivityEntry> pendingEntries = entries
        .where((TodayActivityEntry entry) => !entry.isDone)
        .toList();
    final List<TodayActivityEntry> completedEntries = entries
        .where((TodayActivityEntry entry) => entry.isDone)
        .toList();
    final SectionVisualTheme visual = _sectionVisual(TrackerSection.today);

    return Scaffold(
      backgroundColor: visual.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: visual.colors.first,
        elevation: 0,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: Icon(Icons.menu, color: visual.accent),
            );
          },
        ),
        title: Text(
          'Today',
          style: TextStyle(
            color: _primaryTextColor(),
            fontWeight: FontWeight.w700,
            fontSize: 34,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openTodaySearch,
            icon: Icon(Icons.search, color: _secondaryTextColor()),
          ),
          IconButton(
            onPressed: _openTodayFilterSheet,
            icon: Icon(
              _todayCategoryFilters.isEmpty && _todayPriorityFilters.isEmpty
                  ? Icons.tune
                  : Icons.filter_alt_rounded,
              color:
                  _todayCategoryFilters.isEmpty && _todayPriorityFilters.isEmpty
                  ? _secondaryTextColor()
                  : visual.accent,
            ),
          ),
          IconButton(
            onPressed: _pickPlannerDate,
            icon: Icon(
              Icons.calendar_month_outlined,
              color: _secondaryTextColor(),
            ),
          ),
          IconButton(
            onPressed: _openHelpCenter,
            icon: Icon(Icons.help_outline, color: _secondaryTextColor()),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHomeWelcomeStrip(visual),
          if (_todayCategoryFilters.isNotEmpty ||
              _todayPriorityFilters.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                scrollDirection: Axis.horizontal,
                itemCount:
                    _todayCategoryFilters.length +
                    _todayPriorityFilters.length +
                    1,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 8),
                itemBuilder: (BuildContext context, int index) {
                  if (index ==
                      _todayCategoryFilters.length +
                          _todayPriorityFilters.length) {
                    return ActionChip(
                      label: const Text('Clear Filters'),
                      backgroundColor: _chipSurfaceColor(),
                      side: BorderSide(color: _dividerColor()),
                      onPressed: () {
                        setState(() {
                          _todayCategoryFilters.clear();
                          _todayPriorityFilters.clear();
                        });
                      },
                    );
                  }
                  if (index < _todayCategoryFilters.length) {
                    final String category = _todayCategoryFilters.elementAt(
                      index,
                    );
                    return Chip(
                      label: Text(category),
                      backgroundColor: visual.accent.withValues(alpha: 0.18),
                      side: BorderSide(
                        color: visual.accent.withValues(alpha: 0.28),
                      ),
                      labelStyle: TextStyle(
                        color: _primaryTextColor(),
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }
                  final ItemPriority priority = _todayPriorityFilters.elementAt(
                    index - _todayCategoryFilters.length,
                  );
                  final Color priorityColor = _priorityColor(priority);
                  return Chip(
                    label: Text('${_priorityLabel(priority)} Priority'),
                    backgroundColor: priorityColor.withValues(alpha: 0.14),
                    side: BorderSide(
                      color: priorityColor.withValues(alpha: 0.28),
                    ),
                    labelStyle: TextStyle(
                      color: priorityColor,
                      fontWeight: FontWeight.w700,
                    ),
                  );
                },
              ),
            ),
          if (_todayCategoryFilters.isNotEmpty ||
              _todayPriorityFilters.isNotEmpty)
            const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: weekDates.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(width: 8),
              itemBuilder: (BuildContext context, int index) {
                final DateTime chipDate = weekDates[index];
                final bool selected = _sameDate(chipDate, _selectedPlannerDate);
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedPlannerDate = chipDate;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 72,
                    decoration: BoxDecoration(
                      color: selected ? visual.accent : _themeSurfaceColor(),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _weekDays[chipDate.weekday - 1],
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : _secondaryTextColor(),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _monthNames[chipDate.month - 1],
                          style: TextStyle(
                            color: selected ? Colors.white : _mutedTextColor(),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${chipDate.day}',
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : _primaryTextColor(),
                            fontSize: 28,
                            height: 0.92,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'No activities scheduled',
                      style: TextStyle(
                        color: _secondaryTextColor(),
                        fontSize: 20,
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 100),
                    children: [
                      ...List<Widget>.generate(pendingEntries.length, (
                        int index,
                      ) {
                        final TodayActivityEntry entry = pendingEntries[index];
                        return Column(
                          children: [
                            _buildTodayEntryTile(entry),
                            Divider(color: _dividerColor(), height: 1),
                          ],
                        );
                      }),
                      if (completedEntries.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 18,
                              color: Color(0xFF7FDBA9),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Completed (${completedEntries.length})',
                              style: TextStyle(
                                color: _secondaryTextColor(),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...List<Widget>.generate(completedEntries.length, (
                          int index,
                        ) {
                          final TodayActivityEntry entry =
                              completedEntries[index];
                          return Column(
                            children: [
                              _buildTodayEntryTile(entry),
                              Divider(color: _dividerColor(), height: 1),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: visual.accent,
        foregroundColor: Colors.white,
        onPressed: _addWeeklyActivity,
        child: const Icon(Icons.add, size: 34),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visual.accent.withValues(alpha: 0.28),
      ),
    );
  }

  Widget _buildTodayEntryTile(TodayActivityEntry entry) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: entry.color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(entry.icon, color: Colors.white),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              entry.title,
              style: TextStyle(
                color: entry.isHighPriority
                    ? const Color(0xFFFF879E)
                    : _priorityColor(entry.priority),
                fontSize: 20,
                fontWeight: entry.isHighPriority
                    ? FontWeight.w800
                    : _priorityFontWeight(entry.priority),
                decoration: entry.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _buildTopPriorityDot(
            selected: entry.isHighPriority,
            rank: entry.topPriorityNumber,
            onTap: () async => entry.onTapPriority(),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              entry.category,
              style: TextStyle(color: entry.color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _priorityColor(entry.priority).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _priorityLabel(entry.priority),
              style: TextStyle(
                color: _priorityColor(entry.priority),
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ),
          if (entry.points > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: entry.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: entry.color.withValues(alpha: 0.24)),
              ),
              child: Text(
                '${entry.points} pts',
                style: TextStyle(
                  color: entry.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: Checkbox(
        value: entry.isDone,
        fillColor: _checkboxFill(),
        checkColor: _checkboxCheckColor(),
        side: _checkboxSide(),
        onChanged: (bool? value) => entry.onToggleDone(value ?? false),
      ),
    );
  }

  Widget _buildProfileSection({
    required String title,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: padding,
      decoration: BoxDecoration(
        color: _themeSurfaceColor(),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _dividerColor()),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isLightTheme ? 0.04 : 0.16),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: _secondaryTextColor(),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildProfileInfoTile({
    required String label,
    required String value,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _dividerColor())),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _secondaryTextColor())),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: _primaryTextColor(),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing],
        ],
      ),
    );
  }

  // Kept temporarily because Today still reuses the same scheduled-item data model.
  // ignore: unused_element
  Widget _buildWeeklyPlannerScaffold() {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C10),
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0C10),
        elevation: 0,
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu, color: Color(0xFFE83E76)),
            );
          },
        ),
        title: Text(
          _headerWithUser(_formatDateLabel(_selectedPlannerDate)),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search, color: Colors.white70),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.tune, color: Colors.white70),
          ),
          IconButton(
            onPressed: _pickPlannerDate,
            icon: const Icon(
              Icons.calendar_month_outlined,
              color: Colors.white70,
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.help_outline, color: Colors.white70),
          ),
        ],
        toolbarHeight: 68,
      ),
      body: _buildWeeklyPlannerView(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFE83E76),
        foregroundColor: Colors.white,
        onPressed: _addWeeklyActivity,
        child: const Icon(Icons.add, size: 34),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: const Color(0xFF16181D),
        indicator: const Color(0xFF3C202D),
      ),
    );
  }

  Widget _buildTimerScaffold() {
    final SectionVisualTheme visual = _sectionVisual(TrackerSection.timer);
    return Scaffold(
      backgroundColor: visual.colors.first,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: visual.colors,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Text(
                _headerWithUser('Focus Timer'),
                style: TextStyle(
                  color: _primaryTextColor(),
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isLightTheme
                      ? Colors.black.withValues(alpha: 0.04)
                      : Colors.white.withValues(alpha: 0.1),
                  border: Border.all(
                    color: _isLightTheme ? Colors.black12 : Colors.white24,
                    width: 3,
                  ),
                ),
                child: Center(
                  child: Text(
                    _formatTime(_timerSecondsRemaining),
                    style: TextStyle(
                      color: _primaryTextColor(),
                      fontSize: 52,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _handleTimerPrimaryAction,
                    icon: Icon(
                      _isTimerRunning ? Icons.pause : Icons.play_arrow,
                    ),
                    label: Text(_isTimerRunning ? 'Pause' : 'Start'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _resetTimer,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Reset'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _primaryTextColor(),
                      side: BorderSide(color: _mutedTextColor()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: _setTimerDuration,
                icon: const Icon(Icons.tune),
                label: const Text('Set Time'),
              ),
              const SizedBox(height: 8),
              Text(
                _timerSecondsRemaining <= 0
                    ? 'Tap Start to set a time and begin'
                    : 'Tap Start to begin the timer',
                style: TextStyle(color: _secondaryTextColor(), fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visual.accent.withValues(alpha: 0.28),
      ),
    );
  }

  Widget _buildProfileScaffold() {
    final SectionVisualTheme visual = _sectionVisual(TrackerSection.profile);
    return Scaffold(
      backgroundColor: visual.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: visual.colors.first,
        foregroundColor: _primaryTextColor(),
        title: Text(_headerWithUser('Profile')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileSection(
              title: 'Profile',
              child: Column(
                children: [
                  Row(
                    children: [
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 42,
                            backgroundColor: visual.accent.withValues(
                              alpha: 0.20,
                            ),
                            backgroundImage:
                                _children[_selectedChildIndex].avatarBytes !=
                                    null
                                ? MemoryImage(
                                    _children[_selectedChildIndex].avatarBytes!,
                                  )
                                : null,
                            child:
                                _children[_selectedChildIndex].avatarBytes ==
                                    null
                                ? Icon(
                                    _children[_selectedChildIndex].avatarIcon,
                                    color: visual.accent,
                                    size: 38,
                                  )
                                : null,
                          ),
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: IconButton.filled(
                              onPressed: _showAvatarPicker,
                              style: IconButton.styleFrom(
                                backgroundColor: visual.accent,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(34, 34),
                                padding: EdgeInsets.zero,
                              ),
                              icon: const Icon(Icons.edit, size: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _profileOwnerName,
                              style: TextStyle(
                                color: _primaryTextColor(),
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isParentUser
                                  ? 'Parent view for $_motherName'
                                  : '$_userTypeLabel profile',
                              style: TextStyle(color: _secondaryTextColor()),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.currentUserEmail,
                              style: TextStyle(color: _mutedTextColor()),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: _showAvatarPicker,
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  label: const Text('Manage Photo'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () async {
                                    await widget.onLogout();
                                  },
                                  icon: const Icon(Icons.logout_rounded),
                                  label: const Text('Logout'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _buildProfileInfoTile(
                    label: 'Profile Type',
                    value: _userTypeLabel,
                  ),
                ],
              ),
            ),
            _buildProfileSection(
              title: 'Quick Info',
              child: Column(
                children: [
                  if (_isParentUser)
                    _buildProfileInfoTile(
                      label: 'Parent PIN',
                      value: _parentPin == null ? 'Not set' : 'Set',
                      trailing: FilledButton.tonal(
                        onPressed: () async {
                          if ((_parentPin ?? '').isNotEmpty) {
                            final bool ok = await _verifyParentPin();
                            if (!ok) {
                              return;
                            }
                          }
                          await _setupParentPin();
                        },
                        child: Text(
                          _parentPin == null ? 'Set PIN' : 'Change PIN',
                        ),
                      ),
                    ),
                  _buildProfileInfoTile(
                    label: 'Earned Points',
                    value: '$_earnedPointsTotal points',
                  ),
                  _buildProfileInfoTile(
                    label: _isParentUser ? 'Parent Name' : 'Profile Name',
                    value: _profileOwnerName,
                    trailing: IconButton(
                      icon: Icon(Icons.edit, color: _secondaryTextColor()),
                      onPressed: () async {
                        final String? value = await _promptTextValue(
                          title: _isParentUser
                              ? 'Edit Parent Name'
                              : 'Edit Profile Name',
                          initial: _profileOwnerName,
                          hint: _isParentUser
                              ? 'Enter parent name'
                              : 'Enter profile name',
                        );
                        if (value == null || value.isEmpty) {
                          return;
                        }
                        setState(() {
                          if (_isParentUser) {
                            _motherName = value;
                          } else {
                            _children[_selectedChildIndex].name = value;
                          }
                        });
                      },
                    ),
                  ),
                  if (_isParentUser)
                    Container(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Active Child',
                                  style: TextStyle(
                                    color: _secondaryTextColor(),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _activeChildName,
                                  style: TextStyle(
                                    color: _primaryTextColor(),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (_isParentUser)
              _buildProfileSection(
                title: 'Family',
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          'Child Profile',
                          style: TextStyle(color: _secondaryTextColor()),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _selectedChildIndex,
                            dropdownColor: _themeSurfaceColor(),
                            style: TextStyle(color: _primaryTextColor()),
                            items: List<DropdownMenuItem<int>>.generate(
                              _children.length,
                              (int idx) => DropdownMenuItem<int>(
                                value: idx,
                                child: Text(_children[idx].name),
                              ),
                            ),
                            onChanged: (int? index) {
                              if (index == null) {
                                return;
                              }
                              setState(() {
                                _selectedChildIndex = index;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () async {
                              final String? name = await _promptTextValue(
                                title: 'Add Child Profile',
                                initial: '',
                                hint: 'Child name',
                              );
                              if (name == null || name.isEmpty) {
                                return;
                              }
                              setState(() {
                                _children.add(_createProfile(name));
                                _selectedChildIndex = _children.length - 1;
                              });
                            },
                            child: const Text('Add Child'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () async {
                              final String? name = await _promptTextValue(
                                title: 'Rename Child Profile',
                                initial: _activeChildName,
                                hint: 'Child name',
                              );
                              if (name == null || name.isEmpty) {
                                return;
                              }
                              setState(() {
                                _children[_selectedChildIndex].name = name;
                              });
                            },
                            child: const Text('Rename Child'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            _buildProfileSection(
              title: 'Calendar Sync',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isGoogleConnected ? Icons.cloud_done : Icons.cloud_off,
                        color: _isGoogleConnected
                            ? const Color(0xFF3ECF8E)
                            : _mutedTextColor(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Google Calendar',
                          style: TextStyle(
                            color: _primaryTextColor(),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_isSyncingCalendar)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _googleCalendarHelpText(),
                    style: TextStyle(color: _secondaryTextColor(), height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _isGoogleConnected
                            ? _disconnectGoogleCalendar
                            : _connectGoogleCalendar,
                        icon: Icon(
                          _isGoogleConnected ? Icons.link_off : Icons.link,
                        ),
                        label: Text(
                          _isGoogleConnected ? 'Disconnect' : 'Connect',
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _isSyncingCalendar
                            ? null
                            : _importGoogleCalendarEvents,
                        icon: const Icon(Icons.download),
                        label: const Text('Import to App'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _isSyncingCalendar
                            ? null
                            : _exportSelectedDateToGoogleCalendar,
                        icon: const Icon(Icons.upload),
                        label: const Text('Export Selected Date'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visual.accent.withValues(alpha: 0.28),
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    final TextEditingController currentController = TextEditingController();
    final TextEditingController newController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    String? inlineError;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: Icon(Icons.lock_outline),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New Password',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        inlineError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (newController.text.length < 6) {
                            setDialogState(() {
                              inlineError =
                                  'New password must be at least 6 characters';
                            });
                            return;
                          }
                          if (newController.text != confirmController.text) {
                            setDialogState(() {
                              inlineError = 'Passwords do not match';
                            });
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            inlineError = null;
                          });
                          final String? result = await widget.onChangePassword(
                            currentPassword: currentController.text,
                            newPassword: newController.text,
                          );
                          if (!context.mounted || !dialogContext.mounted) {
                            return;
                          }
                          if (result == null) {
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Password updated successfully'),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            saving = false;
                            inlineError = result;
                          });
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
  }

  Widget _buildSettingsScaffold() {
    final SectionVisualTheme visual = _sectionVisual(TrackerSection.settings);
    return Scaffold(
      backgroundColor: visual.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: visual.colors.first,
        foregroundColor: _primaryTextColor(),
        title: Text(_headerWithUser('Settings')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileSection(
              title: 'Theme',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _themeLabel(_themeChoice),
                    style: TextStyle(
                      color: _primaryTextColor(),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AppThemeChoice.values.map((AppThemeChoice theme) {
                      final bool selected = _themeChoice == theme;
                      final Color accent = selected
                          ? visual.accent
                          : _mutedTextColor();
                      return ChoiceChip(
                        label: Text(_themeLabel(theme)),
                        selected: selected,
                        labelStyle: TextStyle(
                          color: _primaryTextColor(),
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                        backgroundColor: _chipSurfaceColor(),
                        selectedColor: accent.withValues(alpha: 0.35),
                        side: BorderSide(
                          color: selected ? accent : _dividerColor(),
                        ),
                        onSelected: (bool value) {
                          if (!value) {
                            return;
                          }
                          setState(() {
                            _themeChoice = theme;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            _buildProfileSection(
              title: 'Security',
              child: Column(
                children: [
                  _buildProfileInfoTile(
                    label: 'Password',
                    value: widget.canChangePassword
                        ? 'Change your account password'
                        : 'Unavailable for Google sign-in accounts',
                    trailing: FilledButton.tonal(
                      onPressed: widget.canChangePassword
                          ? _openChangePasswordDialog
                          : null,
                      child: const Text('Change'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visual.accent.withValues(alpha: 0.28),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentSection == TrackerSection.today) {
      return _buildTodayScaffold();
    }
    if (_currentSection == TrackerSection.activities) {
      return _buildActivitiesScaffold();
    }
    if (_currentSection == TrackerSection.todoList) {
      return _buildTodoScaffold();
    }
    if (_currentSection == TrackerSection.weeklyPlanner) {
      return _buildTodayScaffold();
    }
    if (_currentSection == TrackerSection.timer) {
      return _buildTimerScaffold();
    }
    if (_currentSection == TrackerSection.profile) {
      return _buildProfileScaffold();
    }
    if (_currentSection == TrackerSection.settings) {
      return _buildSettingsScaffold();
    }

    final SectionVisualTheme visualTheme = _sectionVisual(_currentSection);
    final List<TrackerItem> currentItems =
        _items[_currentSection] ?? <TrackerItem>[];
    final int completedCount = currentItems
        .where((TrackerItem x) => x.isDone)
        .length;
    final bool pointsSection =
        _currentSection == TrackerSection.todoList ||
        _currentSection == TrackerSection.checklist;
    final int completedPoints = currentItems
        .where((TrackerItem x) => x.isDone)
        .fold<int>(0, (int sum, TrackerItem x) => sum + x.points);

    return Scaffold(
      backgroundColor: visualTheme.colors.first,
      drawer: _buildAppDrawer(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(_headerWithUser(_sectionLabel(_currentSection))),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: visualTheme.colors,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: List<Widget>.generate(40, (int index) {
                    final IconData icon =
                        visualTheme.backgroundIcons[index %
                            visualTheme.backgroundIcons.length];
                    return Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        icon,
                        size: 26 + ((index % 4) * 4),
                        color: Colors.white.withValues(alpha: 0.13),
                      ),
                    );
                  }),
                ),
              ),
            ),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Card(
                    color: const Color(0xFF161A22),
                    child: ListTile(
                      leading: Icon(
                        _sectionIcon(_currentSection),
                        color: visualTheme.accent,
                      ),
                      title: Text(
                        '${currentItems.length} item(s)',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        pointsSection
                            ? '$completedCount completed • $completedPoints points'
                            : '$completedCount completed',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _buildRegularSection(currentItems, visualTheme.accent),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: visualTheme.accent,
        foregroundColor: Colors.white,
        onPressed: _addItem,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      bottomNavigationBar: _buildBottomNavBar(
        background: _themeNavColor(),
        indicator: visualTheme.accent.withValues(alpha: 0.28),
      ),
    );
  }
}
