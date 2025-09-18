class ThreadSummary {
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

  ThreadSummary({
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

  factory ThreadSummary.fromJson(Map<String, dynamic> json) {
    return ThreadSummary(
      threadId: json['thread_id'] ?? 0,
      title: json['title'] ?? '',
      creator: json['creator'] ?? '',
      version: json['version'] ?? '',
      views: json['views'] ?? 0,
      likes: json['likes'] ?? 0,
      prefixes: List<int>.from(json['prefixes'] ?? []),
      tags: List<int>.from(json['tags'] ?? []),
      rating: (json['rating'] ?? 0.0).toDouble(),
      cover: json['cover'] ?? '',
      screens: List<String>.from(json['screens'] ?? []),
      date: json['date'] ?? '',
      watched: json['watched'] ?? false,
      ignored: json['ignored'] ?? false,
      isNew: json['new'] ?? false,
      timestamp: json['ts'] ?? 0,
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
  final List<ThreadSummary> threads;
  final Pagination pagination;
  final int count;

  ApiResponseData({required this.threads, required this.pagination, required this.count});

  factory ApiResponseData.fromJson(Map<String, dynamic> json) {
    return ApiResponseData(
      threads: (json['data'] as List? ?? []).map((item) => ThreadSummary.fromJson(item)).toList(),
      pagination: Pagination.fromJson(json['pagination'] ?? {}),
      count: json['count'] ?? 0,
    );
  }
}

class Pagination {
  final int page;
  final int total;

  Pagination({required this.page, required this.total});

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(page: json['page'] ?? 1, total: json['total'] ?? 0);
  }
}
