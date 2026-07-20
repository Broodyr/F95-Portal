import 'package:html/parser.dart' as html_parser;

/// Content the site won't serve this viewer, and won't on a second ask: a
/// profile whose owner limited it, a forum or thread that isn't there.
///
/// Separate from [ApiException] for one reason — a screen showing this should
/// not offer Retry. A 403 earns the same 403; a 404 stays missing. Reserved
/// for those two: a 500 or a timeout carries no such promise and stays an
/// ordinary, retryable failure.
class ContentUnavailableException implements Exception {
  final String message;

  /// Which of the two it was. Most screens don't care — they only drop
  /// Retry — but the one showing a member can tell "they shut you out" from
  /// "they aren't there" and say so.
  final int? statusCode;

  ContentUnavailableException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// True for the statuses whose meaning won't change between two identical
/// requests. Anything else — server errors, rate limits, timeouts — is worth
/// another try.
bool isPermanentStatus(int statusCode) => statusCode == 403 || statusCode == 404;

/// The site's own wording for a request it refused, or couldn't fulfil.
///
/// XenForo answers 403 and 404 with an ordinary page rather than a bare
/// status, and states the reason in a `.blockMessage`: "This member limits
/// who may view their full profile", "The requested forum could not be
/// found". Surfacing that beats surfacing the status code.
///
/// Scoped to a direct child of the page content, which is load-bearing —
/// every page on the site carries half a dozen `.blockMessage` nodes in its
/// header (the no-JS notice, the out-of-date browser warning), and a profile
/// that loaded fine has one per lazy tab pane holding "Loading…". Those all
/// sit deeper, or outside, so the selector steps over them.
///
/// Null when the markup says nothing useful, so callers fall back to the
/// status code rather than showing an empty error.
String? parseSiteErrorMessage(String htmlSource) {
  final block = html_parser.parse(htmlSource).querySelector('.p-body-pageContent > .blockMessage');
  final message = block?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  return message.isEmpty ? null : message;
}
