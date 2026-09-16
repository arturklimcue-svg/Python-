# КодиК — Python-разработчик

Интерактивный курс программирования на Python (Flutter, Android).

## Возможности
- 9 модулей, у каждого финальный мини-проект/практика
- ~140 упражнений в первом модуле (теория + задачи: выбор ответа, заполнение пропусков, правда/ложь)
- Геймификация: XP, уровни, монеты, стрик, достижения
- Сертификат при 100% курса (сохранение/шеринг PNG)
- Сброс прогресса

## Как собрать APK
CI собирает APK автоматически через GitHub Actions (ubuntu, x64):

```bash
flutter pub get
flutter create --platforms android --org com.arturklimcue --project-name kodik .
flutter analyze
flutter test
flutter build apk --release
```

Или откройте репозиторий и скачайте APK из раздела **Releases** (или **Actions → последний билд → Artifact**).

## Структура проекта
```
assets/data/python_course.json  – контент курса (модули, уроки, упражнения)
lib/
  models/                       – модели данных (Course, Lesson, Exercise, Task)
  data/                         – загрузчик JSON из assets
  services/                     – прогресс, хранение (SharedPreferences), сертификат
  screens/                      – экраны: онбординг, курс, уроки, прогресс, профиль, сертификат
  widgets/                      – код-блок с подсветкой, виджеты упражнений
  app.dart, main.dart           – точка входа
test/                           – юнит-тесты моделей и прогресса
.github/workflows/build-apk.yml – GitHub Actions (сборка, тест, релиз APK)
```

## Как добавить новые модули
Редактируйте `assets/data/python_course.json`:
- Структура: `Course → modules[] → lessons[] → exercises[]`
- Тип упражнения: `theory` (только текст) или `theory_task` (текст + задание)
- Типы заданий: `single`, `multi`, `tf`, `fill`, `code_output`

## Технологии
- **Flutter 3.47+**, Dart
- **SharedPreferences** для хранения прогресса
- **share_plus** для шеринга сертификата
- **RepaintBoundary** для захвата PNG сертификата