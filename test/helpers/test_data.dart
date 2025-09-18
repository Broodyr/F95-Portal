import 'package:f95_portal/models/game_thread.dart';

GameThread createGameThread({
  int threadId = 1,
  String title = 'Test Game',
  String creator = 'Test Creator',
  String version = 'v0.1',
  int views = 1000,
  int likes = 100,
  List<int>? prefixes,
  List<int>? tags,
  double rating = 4.5,
  String cover = '',
  List<String>? screens,
  String date = '1 day',
  bool watched = false,
  bool ignored = false,
  bool isNew = false,
  int timestamp = 0,
}) {
  return GameThread(
    threadId: threadId,
    title: title,
    creator: creator,
    version: version,
    views: views,
    likes: likes,
    prefixes: prefixes ?? const [3],
    tags: tags ?? const [191],
    rating: rating,
    cover: cover,
    screens: screens ?? const [],
    date: date,
    watched: watched,
    ignored: ignored,
    isNew: isNew,
    timestamp: timestamp,
  );
}

ApiResponse createApiResponse({List<GameThread>? games, int page = 1, int total = 1, int count = 1}) {
  final gameList = games ?? [createGameThread()];
  return ApiResponse(
    status: 'ok',
    data: ApiResponseData(
      games: gameList,
      pagination: Pagination(page: page, total: total),
      count: count,
    ),
  );
}
