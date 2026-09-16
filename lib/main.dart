import 'package:flutter/material.dart';

import 'app.dart';
import 'data/course_repository.dart';
import 'services/progress_service.dart';
import 'services/storage_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final course = await CourseRepository.loadFromAssets();
  final progress = ProgressService(PrefsStorage());
  await progress.load();
  await progress.touchStreak(DateTime.now());

  runApp(KodikApp(course: course, progress: progress));
}