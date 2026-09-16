class ChatMessage {
  final String role;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class AiAgent {
  final List<ChatMessage> messages = [];
  final int currentModule;
  final String currentModuleTitle;

  AiAgent({required this.currentModule, required this.currentModuleTitle});

  Future<void> sendMessage(String text) async {
    messages.add(ChatMessage(role: 'user', text: text));
    final response = _generateResponse(text);
    messages.add(ChatMessage(role: 'ai', text: response));
  }

  String _generateResponse(String text) {
    final lower = text.toLowerCase();

    if (_matches(lower, ['привет', 'здравствуй', 'хай', 'hello'])) {
      return 'Привет! 😊 Я помогу тебе с изучением Python. '
          'Задавай вопросы по теме урока или попроси объяснить что-то подробнее!';
    }

    if (_matches(lower, ['переменн', 'тип', 'str', 'int', 'float', 'print'])) {
      return 'В Python переменные создаются автоматически при присваивании значения.\n\n'
          'Основные типы данных:\n'
          '- `int` — целые числа\n'
          '- `float` — дробные числа\n'
          '- `str` — строки\n'
          '- `bool` — логический тип\n\n'
          '```python\nname = "Алиса"       # str\n'
          'age = 15              # int\n'
          'height = 1.65         # float\n'
          'print(name, age)\n```';
    }

    if (_matches(lower, ['if', 'услови', 'elif', 'тернарн'])) {
      return 'Условные операторы позволяют программе принимать решения.\n\n'
          '```python\ngrade = 5\n'
          'if grade >= 4:\n'
          '    print("Хорошо!")\n'
          'elif grade == 3:\n'
          '    print("Удовлетворительно")\n'
          'else:\n'
          '    print("Нужно подтянуть")\n```\n\n'
          'Тернарный оператор: `result = "да" if age >= 18 else "нет"`';
    }

    if (_matches(lower, ['while', 'for', 'цикл', 'повтор'])) {
      return 'Циклы используются для повторения действий.\n\n'
          '`for` — перебирает элементы:\n'
          '```python\nfor i in range(5):\n'
          '    print(i)  # 0, 1, 2, 3, 4\n```\n\n'
          '`while` — выполняет блок пока условие истинно:\n'
          '```python\nwhile count > 0:\n'
          '    print(count)\n'
          '    count -= 1\n```';
    }

    if (_matches(lower, ['список', 'list', 'append', 'индекс'])) {
      return 'Списки — упорядоченные коллекции элементов.\n\n'
          '```python\nfruits = ["яблоко", "банан", "вишня"]\n'
          'fruits.append("груша")      # добавить элемент\n'
          'print(fruits[0])            # яблоко (индексация с 0)\n'
          'print(len(fruits))          # длина списка\n'
          'for fruit in fruits:\n'
          '    print(fruit)\n```';
    }

    if (_matches(lower, ['функци', 'def', 'return', 'параметр'])) {
      return 'Функции позволяют переиспользовать код.\n\n'
          '```python\ndef greet(name, age=10):\n'
          '    """Приветствие"""\n'
          '    return f"Привет, {name}! Тебе {age} лет."\n\n'
          'print(greet("Маша"))\n'
          'print(greet("Петя", 12))\n```\n\n'
          '`return` возвращает значение, `def` определяет функцию.';
    }

    if (_matches(lower, ['словар', 'dict', 'ключ'])) {
      return 'Словари хранят пары «ключ — значение».\n\n'
          '```python\nstudent = {\n'
          '    "имя": "Дима",\n'
          '    "оценка": 5,\n'
          '    "предметы": ["математика", "физика"]\n'
          '}\n\n'
          'print(student["имя"])          # Дима\n'
          'student["класс"] = "10Б"       # добавить ключ\n'
          'for key, value in student.items():\n'
          '    print(key, value)\n```';
    }

    if (_matches(lower, ['класс', 'объект', 'наследован', 'метод', 'self'])) {
      return 'ООП позволяет моделировать реальные сущности через классы.\n\n'
          '```python\nclass Animal:\n'
          '    def __init__(self, name):\n'
          '        self.name = name\n\n'
          '    def speak(self):\n'
          '        return f"{self.name} издаёт звук"\n\n'
          'class Dog(Animal):            # наследование\n'
          '    def speak(self):\n'
          '        return f"{self.name} лает"\n\n'
          'rex = Dog("Рекс")\n'
          'print(rex.speak())  # Рекс лает\n```';
    }

    if (_matches(lower, ['api', 'запрос', 'json', 'http'])) {
      return 'API позволяют приложению обмениваться данными с сервером.\n\n'
          '```python\nimport requests\n\n'
          'response = requests.get("https://api.example.com/data")\n'
          'data = response.json()   # парсим JSON\n\n'
          'for item in data["results"]:\n'
          '    print(item["name"])\n```\n\n'
          'JSON — формат данных вида `{ "ключ": "значение" }`.';
    }

    if (_matches(lower, ['помощь', 'помоги', 'объясни', 'что такое'])) {
      return 'Сейчас мы изучаем тему «$currentModuleTitle» (модуль $currentModule).\n\n'
          'Ты можешь спросить:\n'
          '- Объясни конкретную тему (например, «что такое функции»)\n'
          '- Как работает определённая конструкция\n'
          '- Пример кода по теме урока\n\n'
          'Задавай вопрос, и я постараюсь помочь! 💡';
    }

    if (_matches(lower, ['проверь', 'код', 'ошибк'])) {
      return 'Вот типичные ошибки, на которые стоит обратить внимание:\n\n'
          '1. **IndentationError** — проверь отступы (4 пробела)\n'
          '2. **NameError** — переменная не определена\n'
          '3. **TypeError** — несовместимые типы (например, `str + int`)\n'
          '4. **IndexError** — выход за границы списка\n'
          '5. **KeyError** — ключ не найден в словаре\n\n'
          'Пришли свой код, и я помогу найти проблему!';
    }

    return 'Я пока не знаю, как ответить на этот вопрос 😅\n\n'
        'Попробуй спросить о:\n'
        '- Переменных и типах данных\n'
        '- Условиях (if/else)\n'
        '- Циклах (for/while)\n'
        '- Списках и словарях\n'
        '- Функциях\n'
        '- ООП (классах)\n'
        '- API и запросах';
  }

  bool _matches(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }
}
