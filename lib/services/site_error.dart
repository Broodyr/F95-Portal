import 'package:html/parser.dart' as html_parser;

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
