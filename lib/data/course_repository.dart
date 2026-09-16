import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/course.dart';

class CourseRepository {
  static Future<Course> loadFromAssets() async {
    final raw = await rootBundle.loadString('assets/data/python_course.json');
    return parse(raw);
  }

  static Course parse(String rawJson) {
    final json = jsonDecode(rawJson) as Map<String, dynamic>;
    return Course.fromJson(json);
  }
}