import '../home/college_guide_api.dart';

/// One choice list (college/collections/).
class ChoiceList {
  ChoiceList(this.id, this.name, this.choiceCount, [List<ChoiceItem>? choices])
    : choices = choices ?? [];

  final String id;
  final String? name;
  final int choiceCount;
  final List<ChoiceItem> choices;
}

/// One entry of a list's data.items.
class ChoiceItem {
  const ChoiceItem({
    required this.id,
    this.counselling,
    this.institute,
    this.state,
    this.course,
    this.beds = 0,
    this.quota,
    this.category,
    this.fee,
    this.year,
  });

  final String? id;
  final String? counselling;
  final String? institute;
  final String? state;
  final String? course;
  final int beds;
  final String? quota;
  final String? category;
  final String? fee;
  final String? year;
}

/// One quota for the picked counselling + institute + course.
class QuotaOption {
  const QuotaOption(this.name, this.categories);

  final String name;
  final List<String> categories;
}

/// The native ChoiceListRepository: lists, the add-choice drop-downs (cached
/// per selection), adding and removing choices.
class ChoiceListRepository {
  ChoiceListRepository(this.api);

  final CollegeGuideApiRepository api;

  final List<ChoiceList> _lists = [];
  final Map<String, List<String>> _optionCache = {};
  final Map<String, List<QuotaOption>> _quotaCache = {};

  /// The server's message (a string, or the first field of an object
  /// message, else description), or "[fallback] (error [code])".
  static String _message(Object error, String fallback) {
    if (error is CollegeGuideApiException) {
      final body = error.payload;
      if (body != null) {
        final message = body['message'];
        if (message is String && message.isNotEmpty) return message;
        if (message is Map) {
          for (final value in message.values) {
            if (value is String) return value;
            if (value is List && value.isNotEmpty) return '${value.first}';
          }
        }
        final description = body['description'];
        if (description is String && description.isNotEmpty) {
          return description;
        }
      }
      if (error.statusCode != null) {
        return '$fallback (error ${error.statusCode})';
      }
    }
    return '$fallback. Check your internet and try again.';
  }

  static String? _s(Object? v) => v == null ? null : '$v';

  static String? _first(Map<String, dynamic> o, List<String> keys) {
    for (final key in keys) {
      final value = _s(o[key]);
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static int _firstInt(Map<String, dynamic> o, List<String> keys) {
    for (final key in keys) {
      final value = o[key];
      if (value is num) return value.toInt();
      if (value is String && int.tryParse(value) != null) {
        return int.parse(value);
      }
    }
    return 0;
  }

  static List<String> _strings(Object? value) => [
    if (value is List)
      for (final v in value)
        if (v != null && '$v'.trim().isNotEmpty) '$v',
  ];

  ChoiceList? _find(String id) {
    for (final list in _lists) {
      if (list.id == id) return list;
    }
    return null;
  }

  /// GET college/collections/
  Future<List<ChoiceList>> getLists() async {
    try {
      final json = await api.choiceRequest('GET', 'college/collections/');
      _lists
        ..clear()
        ..addAll([
          for (final c in (json['data'] as List? ?? const []))
            if (c is Map<String, dynamic>)
              ChoiceList(
                '${c['id']}',
                _s(c['name']),
                (c['total_items'] as num?)?.toInt() ?? 0,
              ),
        ]);
      return List.of(_lists);
    } catch (e) {
      throw _message(e, "Couldn't load your choice lists");
    }
  }

  /// Checked against the last fetched lists, before calling the server.
  bool nameExists(String name) => _lists.any(
    (l) => (l.name ?? '').toLowerCase() == name.trim().toLowerCase(),
  );

  /// POST college/collections/ {"name"}
  Future<ChoiceList> createList(String name) async {
    try {
      final json = await api.choiceRequest(
        'POST',
        'college/collections/',
        body: {'name': name.trim()},
      );
      final data = json['data'];
      if (data is! Map<String, dynamic>) throw const FormatException();
      final list = ChoiceList(
        '${data['id']}',
        _s(data['name']),
        (data['total_items'] as num?)?.toInt() ?? 0,
      );
      _lists.add(list);
      return list;
    } catch (e) {
      throw _message(e, "Couldn't create the list");
    }
  }

  Future<List<String>> _fetchStrings(
    String key,
    Map<String, String> query,
    String endpoint,
    String what,
  ) async {
    final cached = _optionCache[key];
    if (cached != null) return cached;
    try {
      final json = await api.choiceRequest('GET', endpoint, query: query);
      final data = json['data'];
      final results = _strings(data is Map ? data['results'] : null);
      _optionCache[key] = results;
      return results;
    } catch (e) {
      throw _message(e, "Couldn't load $what");
    }
  }

  /// GET college/counselling-list/
  Future<List<String>> counsellingOptions() => _fetchStrings(
    'counselling',
    const {},
    'college/counselling-list/',
    'counselling types',
  );

  /// GET college/choice/options/?counselling=
  Future<List<String>> instituteOptions(String counselling) => _fetchStrings(
    'institute|$counselling',
    {'counselling': counselling},
    'college/choice/options/',
    'institutes',
  );

  /// GET college/choice/options/?counselling=&institute=
  Future<List<String>> courseOptions(String counselling, String institute) =>
      _fetchStrings(
        'course|$counselling|$institute',
        {'counselling': counselling, 'institute': institute},
        'college/choice/options/',
        'courses',
      );

  /// GET college/choice/options/?counselling=&institute=&course=
  Future<List<QuotaOption>> quotaOptions(
    String counselling,
    String institute,
    String course,
  ) async {
    final key = '$counselling|$institute|$course';
    final cached = _quotaCache[key];
    if (cached != null) return cached;
    try {
      final json = await api.choiceRequest(
        'GET',
        'college/choice/options/',
        query: {
          'counselling': counselling,
          'institute': institute,
          'course': course,
        },
      );
      final data = json['data'];
      final quotas = <QuotaOption>[
        if (data is Map)
          for (final q in (data['quotas'] as List? ?? const []))
            if (q is Map && q['name'] != null)
              QuotaOption('${q['name']}', _strings(q['categories'])),
      ];
      _quotaCache[key] = quotas;
      return quotas;
    } catch (e) {
      throw _message(e, "Couldn't load quotas");
    }
  }

  /// POST college/choice/
  Future<void> addChoice({
    required String listId,
    required String counselling,
    required String institute,
    required String course,
    required String quota,
    required String category,
  }) async {
    try {
      await api.choiceRequest(
        'POST',
        'college/choice/',
        body: {
          'collection_id': listId,
          'counselling': counselling,
          'institute': institute,
          'course': course,
          'quota': quota,
          'category': category,
        },
      );
    } catch (e) {
      throw _message(e, "Couldn't add this choice");
    }
  }

  /// GET college/collections/{id}/ -> the list and all its choices.
  Future<ChoiceList> getChoices(String listId) async {
    try {
      final json = await api.choiceRequest(
        'GET',
        'college/collections/$listId/',
      );
      final data = json['data'];
      final info = data is Map<String, dynamic> ? data : <String, dynamic>{};
      final items = data is List ? data : (info['items'] as List? ?? const []);
      final choices = [
        for (final c in items)
          if (c is Map<String, dynamic>)
            ChoiceItem(
              id: _s(c['id']),
              counselling: _first(c, ['counselling', 'councelling_type']),
              institute: _first(c, ['institute', 'college_name']),
              state: _first(c, ['state']),
              course: _first(c, ['course', 'course_name']),
              beds: _firstInt(c, ['beds', 'seats', 'total_beds']),
              quota: _first(c, ['quota']),
              category: _first(c, ['category']),
              fee: _first(c, ['fee']),
              year: _first(c, ['year']),
            ),
      ];
      final cached = _find(listId);
      final name = _s(info['name']) ?? cached?.name;
      final list = ChoiceList(listId, name, choices.length, choices);
      if (cached != null) _lists[_lists.indexOf(cached)] = list;
      return list;
    } catch (e) {
      throw _message(e, "Couldn't load this list");
    }
  }

  /// DELETE college/collections/{id}/
  Future<void> deleteList(String listId) async {
    try {
      await api.choiceRequest('DELETE', 'college/collections/$listId/');
      _lists.removeWhere((l) => l.id == listId);
    } catch (e) {
      throw _message(e, "Couldn't delete this list");
    }
  }

  /// DELETE college/collections/{id}/items/{itemId}/
  Future<void> deleteChoice(String listId, String itemId) async {
    try {
      await api.choiceRequest(
        'DELETE',
        'college/collections/$listId/items/$itemId/',
      );
      _find(listId)?.choices.removeWhere((c) => c.id == itemId);
    } catch (e) {
      throw _message(e, "Couldn't remove this choice");
    }
  }
}
