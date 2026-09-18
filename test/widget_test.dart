import 'package:flutter_test/flutter_test.dart';
import 'package:kodik/data/course_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('курс содержит 9 модулей и 71 урок', () async {
    final course = await CourseRepository.loadFromAssets();
    expect(course.moduleCount, 9);
    expect(course.totalLessons, 71);
  });
}