import 'package:flutter/material.dart';

import 'models/course.dart';
import 'screens/ai_chat_screen.dart';
import 'screens/course_tab.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_tab.dart';
import 'screens/progress_tab.dart';
import 'services/progress_service.dart';
import 'theme.dart';

class KodikApp extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const KodikApp({super.key, required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'КодиК',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: RootScreen(course: course, progress: progress),
    );
  }
}

class RootScreen extends StatelessWidget {
  final Course course;
  final ProgressService progress;

  const RootScreen({super.key, required this.course, required this.progress});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: progress,
      builder: (context, _) {
        if (progress.userName.isEmpty) {
          return OnboardingScreen(progress: progress);
        }
        return HomeShell(course: course, progress: progress);
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  final Course course;
  final ProgressService progress;

  const HomeShell({
    super.key,
    required this.course,
    required this.progress,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _AiAssistantPlaceholder extends StatelessWidget {
  final Course course;
  final ProgressService progress;
  const _AiAssistantPlaceholder(this.course, this.progress);

  @override
  Widget build(BuildContext context) {
    int currentModule = 1;
    String currentTitle = 'Введение в Python';
    for (final m in course.modules) {
      if (!progress.isModuleComplete(m)) {
        currentModule = m.number;
        currentTitle = m.title;
        break;
      }
    }
    return AiChatScreen(
      currentModule: currentModule,
      currentModuleTitle: currentTitle,
    );
  }
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      CourseTab(course: widget.course, progress: widget.progress),
      ProgressTab(course: widget.course, progress: widget.progress),
      _AiAssistantPlaceholder(widget.course, widget.progress),
      ProfileTab(course: widget.course, progress: widget.progress),
    ];
    return Scaffold(
      body: IndexedStack(index: _tab, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.card,
        indicatorColor: AppColors.primary.withValues(alpha: 0.14),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Курс',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Прогресс',
          ),
          NavigationDestination(
            icon: Icon(Icons.smart_toy_outlined),
            selectedIcon: Icon(Icons.smart_toy),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Профиль',
          ),
        ],
      ),
    );
  }
}