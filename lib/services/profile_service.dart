import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/profile.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'profile_parser.dart';
import 'thread_page_service.dart';

/// Fetches and parses the signed-in member's profile: the member page (wall
/// inline), the lazily loaded postings and About tabs, and the wall's write
/// actions. No cache — the profile is the natural place to see fresh state.
class ProfileService {
  /// The member page for the current session's user; `/members/<id>/`
  /// redirects to the canonical slug URL.
  static Future<ProfilePage> fetchOwnProfile({http.Client? client, PackageInfoLoader? packageInfoLoader}) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return createMockProfilePage();
    }
    final userId = AuthService.instance.userId;
    if (userId == null) {
      throw ApiException('Sign in to view your profile.');
    }
    final url = 'https://f95zone.to/members/$userId/';
    return parseProfilePage(await _fetchHtml(url, client: client, packageInfoLoader: packageInfoLoader));
  }

  /// Any member's page by URL, for profiles opened from posts.
  static Future<ProfilePage> fetchProfile(
    String url, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return createMockProfilePage();
    }
    return parseProfilePage(await _fetchHtml(url, client: client, packageInfoLoader: packageInfoLoader));
  }

  /// The postings tab lazy-loads on the site; fetching its URL directly
  /// renders the member view with the pane filled in.
  static Future<List<ProfilePosting>> fetchPostings(
    String profileUrl, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return createMockPostings();
    }
    final html = await _fetchHtml(_join(profileUrl, 'recent-content'), client: client, packageInfoLoader: packageInfoLoader);
    return parseProfilePage(html).postings;
  }

  /// The About tab, same lazy-pane arrangement as postings.
  static Future<ProfileAbout> fetchAbout(
    String profileUrl, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) async {
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 300));
      return createMockProfileAbout();
    }
    return parseProfileAbout(
      await _fetchHtml(_join(profileUrl, 'about'), client: client, packageInfoLoader: packageInfoLoader),
    );
  }

  /// Posts a new wall message through the profile's post action.
  static Future<void> postWallMessage(
    String wallPostUrl,
    String csrfToken,
    String message, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(const Duration(milliseconds: 200));
    return ThreadPageService.postAction(
      wallPostUrl,
      csrfToken,
      fields: {'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  /// Comments on a wall post through its add-comment action.
  static Future<void> postComment(
    String commentUrl,
    String csrfToken,
    String message, {
    http.Client? client,
    PackageInfoLoader? packageInfoLoader,
  }) {
    if (kIsWeb) return Future.delayed(const Duration(milliseconds: 200));
    return ThreadPageService.postAction(
      commentUrl,
      csrfToken,
      fields: {'message': message},
      client: client,
      packageInfoLoader: packageInfoLoader,
    );
  }

  static String _join(String base, String suffix) => base.endsWith('/') ? '$base$suffix' : '$base/$suffix';

  static Future<String> _fetchHtml(String url, {http.Client? client, PackageInfoLoader? packageInfoLoader}) async {
    final http.Client httpClient = client ?? http.Client();
    final bool shouldCloseClient = client == null;

    try {
      final headers = {'User-Agent': await ApiService.resolveUserAgent(packageInfoLoader), 'Accept': 'text/html'};
      final cookies = AuthService.instance.cookieHeader;
      if (cookies != null) headers['Cookie'] = cookies;

      final response = await httpClient.get(Uri.parse(url), headers: headers);
      if (response.statusCode != 200) {
        throw ApiException('Failed to load profile page: ${response.statusCode}');
      }
      return response.body;
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Failed to load profile page: $e');
    } finally {
      if (shouldCloseClient) httpClient.close();
    }
  }

  // --- Mock data (web build + widget tests) --------------------------------

  static ProfilePage createMockProfilePage() {
    return const ProfilePage(
      username: 'Broodyr',
      memberTitle: 'Member',
      messages: '291',
      joined: 'Dec 11, 2017',
      lastSeen: 'Today at 4:55 PM',
      profileUrl: 'https://example.com/members/broodyr.1957582/',
      wallPosts: [
        ProfilePost(
          id: 142106,
          author: 'VoidWalker',
          authorUrl: 'https://example.com/members/voidwalker.101/',
          date: '2 days ago',
          body: 'Thanks for the ToxiCity mod update, the gallery unlock works great now!',
          comments: [
            ProfileComment(id: 1, author: 'ModAuthor', body: 'Glad it works — report anything odd in the thread.', date: 'Yesterday'),
            ProfileComment(
              id: 2,
              author: 'VoidWalker',
              authorUrl: 'https://example.com/members/voidwalker.101/',
              body: 'Will do!',
              date: 'Yesterday',
            ),
          ],
          commentUrl: 'https://example.com/profile-posts/142106/add-comment',
        ),
        ProfilePost(
          id: 138154,
          author: 'RenFan88',
          authorUrl: 'https://example.com/members/renfan88.202/',
          date: 'Jun 25, 2026',
          body: 'Any plans to mod Echoes ep. 4 when it drops?',
          commentUrl: 'https://example.com/profile-posts/138154/add-comment',
        ),
      ],
      csrfToken: 'mock-csrf',
      wallPostUrl: 'https://example.com/members/broodyr.1957582/post',
    );
  }

  static List<ProfilePosting> createMockPostings() {
    return const [
      ProfilePosting(
        title: 'Myth of Slayer Walkthrough [Ch 11]',
        prefixes: ['Mod', "Ren'Py"],
        url: 'https://example.com/threads/myth-of-slayer.276090/post-20908354',
        snippet: "No, I hadn't even heard of this app. I took a look and am already downloading it.",
        postInfo: 'Post #29',
        date: '21 minutes ago',
        forum: 'Mods',
      ),
      ProfilePosting(
        title: 'Red Lotus [v0.0.1] [apibytes]',
        prefixes: ['VN', "Ren'Py"],
        url: 'https://example.com/threads/red-lotus.304956/post-20874004',
        snippet: 'Red LOTUS WT — highlights the options in colors, cheat menu.',
        postInfo: 'Post #48',
        date: 'Friday at 5:26 AM',
        forum: 'Games',
      ),
      ProfilePosting(
        title: 'Echoes: The Lies We Tell Ourselves [Ep.3 Public]',
        prefixes: ['Mod'],
        url: 'https://example.com/threads/echoes-mod.301111/',
        snippet: 'The mod adds an in-game walkthrough, gallery unlocker, and cheat menu.',
        postInfo: 'Thread',
        replies: '1',
        date: 'Jun 2, 2026',
        forum: 'Mods',
      ),
    ];
  }

  static ProfileAbout createMockProfileAbout() {
    return const ProfileAbout(
      bio: 'Modding Ren\'Py games in my spare time.\nWalkthrough mods on request.',
      birthday: 'Jan 28',
      website: 'example.itch.io',
      location: 'The Netherlands',
    );
  }
}
