/// JSON numbers decode as double whenever the source emits a decimal point,
/// so every numeric field must accept any [num]. The reverse also happens:
/// nominally-string fields occasionally ship as raw numbers (e.g. thread
/// 200660 has "version": 1.3), so string fields must accept anything.
int _asInt(dynamic value, [int fallback = 0]) => value is num ? value.toInt() : fallback;

double _asDouble(dynamic value, [double fallback = 0.0]) => value is num ? value.toDouble() : fallback;

String _asString(dynamic value, [String fallback = '']) => value == null ? fallback : value.toString();

List<int> _asIntList(dynamic value) => [
  for (final item in value as List? ?? const [])
    if (item is num) item.toInt(),
];

class BrowseThread {
  final int threadId;
  final String title;
  final String creator;
  final String version;
  final int views;
  final int likes;
  final List<int> prefixes;
  final List<int> tags;
  final double rating;
  final String cover;
  final List<String> screens;
  final String date;
  final bool watched;
  final bool ignored;
  final bool isNew;
  final int timestamp;

  BrowseThread({
    required this.threadId,
    required this.title,
    required this.creator,
    required this.version,
    required this.views,
    required this.likes,
    required this.prefixes,
    required this.tags,
    required this.rating,
    required this.cover,
    required this.screens,
    required this.date,
    required this.watched,
    required this.ignored,
    required this.isNew,
    required this.timestamp,
  });

  factory BrowseThread.fromJson(Map<String, dynamic> json) {
    return BrowseThread(
      threadId: _asInt(json['thread_id']),
      title: _asString(json['title']),
      creator: _asString(json['creator']),
      version: _asString(json['version']),
      views: _asInt(json['views']),
      likes: _asInt(json['likes']),
      prefixes: _asIntList(json['prefixes']),
      tags: _asIntList(json['tags']),
      rating: _asDouble(json['rating']),
      cover: _asString(json['cover']),
      screens: [for (final screen in json['screens'] as List? ?? const []) screen.toString()],
      date: _asString(json['date']),
      watched: json['watched'] ?? false,
      ignored: json['ignored'] ?? false,
      isNew: json['new'] ?? false,
      timestamp: _asInt(json['ts']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'thread_id': threadId,
      'title': title,
      'creator': creator,
      'version': version,
      'views': views,
      'likes': likes,
      'prefixes': prefixes,
      'tags': tags,
      'rating': rating,
      'cover': cover,
      'screens': screens,
      'date': date,
      'watched': watched,
      'ignored': ignored,
      'new': isNew,
      'ts': timestamp,
    };
  }

  bool get isCompleted => prefixes.contains(18);
  bool get isAbandoned => prefixes.contains(22);
  bool get isOnhold => prefixes.contains(20);
}

class ApiResponse {
  final String status;
  final ApiResponseData data;

  ApiResponse({required this.status, required this.data});

  factory ApiResponse.fromJson(Map<String, dynamic> json) {
    return ApiResponse(status: json['status'] ?? '', data: ApiResponseData.fromJson(json['msg'] ?? {}));
  }
}

class ApiResponseData {
  final List<BrowseThread> threads;
  final Pagination pagination;
  final int count;

  ApiResponseData({required this.threads, required this.pagination, required this.count});

  factory ApiResponseData.fromJson(Map<String, dynamic> json) {
    return ApiResponseData(
      threads: (json['data'] as List? ?? []).map((item) => BrowseThread.fromJson(item)).toList(),
      pagination: Pagination.fromJson(json['pagination'] ?? {}),
      count: _asInt(json['count']),
    );
  }
}

class Pagination {
  final int page;
  final int total;

  Pagination({required this.page, required this.total});

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(page: _asInt(json['page'], 1), total: _asInt(json['total']));
  }
}
