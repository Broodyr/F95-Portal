import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/thread_page.dart';

/// One inline item on a "line" of the first post: a text run (possibly
/// bold), a link, or a placeholder for a spoiler block.
class _Item {
  final String text;
  final bool bold;
  final String? href;
  final int? spoilerIndex;

  const _Item.text(this.text, {required this.bold}) : href = null, spoilerIndex = null;
  const _Item.link(this.text, this.href) : bold = false, spoilerIndex = null;
  const _Item.spoiler(this.spoilerIndex) : text = '', bold = false, href = null;
}

/// Parses a thread page's first post into a tolerant block model.
/// Game threads have no enforced structure, so nothing here is required;
/// unrecognized content is simply skipped rather than failing the parse.
ThreadPage parseThreadPage(String htmlSource, {required int threadId}) {
  final document = html_parser.parse(htmlSource);
  final post = document.querySelector('article.message--post');
  final body = post?.querySelector('.message-body .bbWrapper') ?? post?.querySelector('.bbWrapper');
  if (body == null) {
    return ThreadPage(threadId: threadId);
  }

  // --- Pass 1: linearize the post into lines of inline items. -------------
  final spoilerElements = <Element>[];
  final lines = <List<_Item>>[];
  var current = <_Item>[];

  void newline() {
    if (current.isNotEmpty) {
      lines.add(current);
      current = <_Item>[];
    }
  }

  void walk(Node node, bool bold) {
    if (node is Element) {
      final tag = node.localName;
      if (node.classes.contains('bbCodeSpoiler')) {
        spoilerElements.add(node);
        newline();
        current.add(_Item.spoiler(spoilerElements.length - 1));
        newline();
        return;
      }
      if (tag == 'br') {
        newline();
        return;
      }
      if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
      if (tag == 'a') {
        final text = _collapse(node.text);
        // Lightbox/gallery anchors carry no usable label (or escaped markup
        // in saved pages); only short clean labels are download hosts.
        if (text.isNotEmpty && text.length <= 40 && !text.contains('<')) {
          current.add(_Item.link(text, node.attributes['href'] ?? ''));
        }
        return;
      }
      final bool isBlock = tag == 'div' || tag == 'p';
      if (isBlock) newline();
      final childBold = bold || tag == 'b' || tag == 'strong';
      for (final child in node.nodes) {
        walk(child, childBold);
      }
      if (isBlock) newline();
      return;
    }
    if (node is Text && node.text.trim().isNotEmpty) {
      current.add(_Item.text(node.text, bold: bold));
    }
  }

  walk(body, false);
  newline();

  // --- Pass 2: interpret the lines. ----------------------------------------
  final metaFields = <MetaField>[];
  final spoilers = <SpoilerSection>[];
  final extras = <DownloadGroup>[];
  final torrentLinks = <DownloadLink>[];
  final overviewBuffer = StringBuffer();

  final sets = <DownloadSet>[];
  var currentGroups = <DownloadGroup>[];
  String? currentSetTitle;

  void commitSet() {
    if (currentGroups.isNotEmpty) {
      sets.add(DownloadSet(title: currentSetTitle, groups: currentGroups));
      currentGroups = [];
    }
    currentSetTitle = null;
  }

  bool collectingOverview = false;
  bool inDownloads = false;
  bool inExtras = false;
  String? pendingLabel;

  void addGroup(String label, List<DownloadLink> links) {
    final group = DownloadGroup(label: label, links: links);
    if (inExtras || label.toLowerCase().startsWith('extra')) {
      extras.add(group);
    } else {
      currentGroups.add(group);
    }
    pendingLabel = null;
  }

  for (final line in lines) {
    // A line that is just a spoiler placeholder.
    _Item? spoilerItem;
    for (final item in line) {
      if (item.spoilerIndex != null) {
        spoilerItem = item;
        break;
      }
    }
    if (spoilerItem != null) {
      collectingOverview = false;
      final element = spoilerElements[spoilerItem.spoilerIndex!];
      // A bold header that gathered no download groups was actually this
      // spoiler's label ("Old Builds:" followed by a spoiler), not a set.
      String? consumedSetTitle;
      if (currentGroups.isEmpty && currentSetTitle != null) {
        consumedSetTitle = currentSetTitle;
        currentSetTitle = null;
      }
      final title = _spoilerTitle(element) ?? _usableLabel(pendingLabel) ?? _usableLabel(consumedSetTitle) ?? 'Spoiler';
      final rich = _spoilerRich(element);
      spoilers.add(SpoilerSection(title: title, content: _plainFromRich(rich), rich: rich));
      pendingLabel = null;
      continue;
    }

    final (label, hadColon, rest) = _splitLeadingBold(line);
    final links = [
      for (final item in rest)
        if (item.href != null) DownloadLink(host: item.text, url: item.href!),
    ];

    if (label.isNotEmpty) {
      if (label.toUpperCase().startsWith('DOWNLOAD')) {
        collectingOverview = false;
        inDownloads = true;
        pendingLabel = null;
        if (links.isNotEmpty) addGroup('Links', links);
        continue;
      }

      if (inDownloads) {
        if (label.toLowerCase() == 'extras' && links.isEmpty) {
          inExtras = true;
          pendingLabel = null;
          continue;
        }
        if (links.isNotEmpty) {
          addGroup(label, links);
        } else if (_isPlatform(label)) {
          // Platform label whose links continue on the next line.
          pendingLabel = label;
        } else {
          // A bold non-platform header inside downloads starts an alternate
          // set ("Incest Version (v0.15)").
          commitSet();
          currentSetTitle = _collapse('$label ${_plainText(rest)}');
          inExtras = false;
          pendingLabel = null;
        }
        continue;
      }

      if (label.toLowerCase() == 'overview') {
        collectingOverview = true;
        final restText = _plainText(rest);
        if (restText.isNotEmpty) overviewBuffer.writeln(restText);
        pendingLabel = null;
        continue;
      }

      // Bold without a colon mid-overview is emphasis, not a new label
      // (e.g. "<b>Overview:<br>Futaken Valley</b> is an action…").
      if (collectingOverview && !hadColon) {
        final text = _collapse('$label ${_plainText(rest)}');
        if (text.isNotEmpty) overviewBuffer.writeln(text);
        continue;
      }
      collectingOverview = false;

      if (hadColon) {
        final value = _metaValue(rest);
        if (value.isNotEmpty && label.length <= 25 && value.length <= 200) {
          metaFields.add(MetaField(label: label, value: value));
        }
      }
      pendingLabel = _usableLabel(label);
      continue;
    }

    // No leading bold.
    if (collectingOverview) {
      final text = _plainText(line);
      if (text.isNotEmpty) overviewBuffer.writeln(text);
      continue;
    }

    if (links.isEmpty) continue;

    if (inDownloads) {
      // Non-bold "Label:" prefixes also mark groups (animation/comic posts).
      final prefix = _textBeforeFirstLink(line);
      if (prefix.endsWith(':') && prefix.length <= 35) {
        addGroup(prefix.substring(0, prefix.length - 1).trim(), links);
      } else if (_isOnlySeparators(_nonLinkText(line))) {
        // A bare row of host links (asset posts have no platform labels).
        addGroup(pendingLabel ?? 'Links', links);
      }
      // Lines with prose around the links are credits, not downloads.
      continue;
    }

    // Outside the downloads section: torrents/magnets stand alone.
    for (final link in links) {
      if (link.host.toLowerCase() == 'torrent' ||
          link.url.toLowerCase().contains('.torrent') ||
          link.url.startsWith('magnet:')) {
        torrentLinks.add(link);
      }
    }
  }

  commitSet();
  if (torrentLinks.isNotEmpty) {
    sets.add(
      DownloadSet(
        title: null,
        groups: [DownloadGroup(label: 'Torrent', links: torrentLinks)],
      ),
    );
  }

  return ThreadPage(
    threadId: threadId,
    metaFields: metaFields,
    overview: overviewBuffer.toString().trim(),
    spoilers: spoilers,
    downloads: sets.isEmpty && extras.isEmpty ? null : DownloadsSection(sets: sets, extras: extras),
    attachments: _parseAttachments(post!),
    actions: _parseActions(document, post),
  );
}

/// Extracts the CSRF token plus the first post's bookmark endpoint, which
/// XenForo only renders for logged-in sessions.
ThreadActions? _parseActions(Document document, Element post) {
  final csrf = document.querySelector('html')?.attributes['data-csrf'];
  if (csrf == null || csrf.isEmpty) return null;

  for (final anchor in post.querySelectorAll('a')) {
    if (anchor.attributes['data-xf-click'] == 'bookmark-click') {
      return ThreadActions(
        csrfToken: csrf,
        bookmarkUrl: _absoluteUrl(anchor.attributes['href'] ?? ''),
        bookmarked: anchor.classes.contains('is-bookmarked'),
      );
    }
  }
  return null;
}

List<DownloadLink> _parseAttachments(Element post) {
  return [
    for (final anchor in post.querySelectorAll('.message-attachments .attachment-name a'))
      if (_collapse(anchor.text).isNotEmpty)
        DownloadLink(host: _collapse(anchor.text), url: _absoluteUrl(anchor.attributes['href'] ?? '')),
  ];
}

String _absoluteUrl(String url) {
  if (url.startsWith('//')) return 'https:$url';
  if (url.startsWith('/')) return 'https://f95zone.to$url';
  return url;
}

String _collapse(String text) => text.replaceAll('​', '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Whether a URL points directly at an image file (used to tell a lightbox
/// anchor wrapping a thumbnail from an ordinary hyperlink).
bool _isImageUrl(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return RegExp(r'\.(jpe?g|png|gif|webp|avif|bmp)$').hasMatch(path);
}

/// Splits a line into its leading bold label, whether the label was followed
/// by a colon (real labels are; bold emphasis is not), and the rest.
(String, bool, List<_Item>) _splitLeadingBold(List<_Item> line) {
  final labelBuffer = StringBuffer();
  int index = 0;
  while (index < line.length && line[index].bold && line[index].href == null) {
    labelBuffer.write('${line[index].text} ');
    index++;
  }
  var label = _collapse(labelBuffer.toString());
  bool hadColon = false;
  if (label.endsWith(':')) {
    hadColon = true;
    label = label.substring(0, label.length - 1).trim();
  } else if (index < line.length && line[index].href == null && line[index].text.trimLeft().startsWith(':')) {
    hadColon = true;
  }
  return (label, hadColon, line.sublist(index));
}

/// Meta values prefer plain text; falls back to the first link's label
/// ("Other Games: Link", "Developer: Bubbles and Sisters [- Subscribestar…]").
String _metaValue(List<_Item> rest) {
  final words = _plainText(rest.where((i) => i.href == null).toList())
      .split(' ')
      // Link separators ("Patreon - Itch - Steam") leave dangling dashes
      // once the link texts are dropped.
      .where((word) => word != '-' && word != '–')
      .toList();
  final text = words.join(' ').trim();
  if (text.isNotEmpty) return text;
  for (final item in rest) {
    if (item.href != null) return item.text;
  }
  return '';
}

String _plainText(List<_Item> items) {
  final joined = items.map((i) => i.text).join(' ');
  var text = _collapse(joined);
  while (text.startsWith(':') || text.startsWith('-')) {
    text = text.substring(1).trim();
  }
  return text;
}

String _textBeforeFirstLink(List<_Item> line) {
  final buffer = StringBuffer();
  for (final item in line) {
    if (item.href != null) break;
    buffer.write('${item.text} ');
  }
  return _collapse(buffer.toString());
}

String _nonLinkText(List<_Item> line) => _collapse(line.where((i) => i.href == null).map((i) => i.text).join(' '));

bool _isOnlySeparators(String text) => RegExp(r'^[\s\-–|/,·:]*$').hasMatch(text);

/// Labels usable as spoiler titles / download groups: short phrases, not the
/// bold sentences some posts use for emphasis.
String? _usableLabel(String? label) {
  if (label == null || label.isEmpty || label.length > 30) return null;
  return label;
}

bool _isPlatform(String label) {
  return RegExp(
    r'^(win|windows|pc|mac|os ?x|linux|android|ios|online|all|others?)\b',
    caseSensitive: false,
  ).hasMatch(label);
}

String? _spoilerTitle(Element spoiler) {
  final button = spoiler.querySelector('.bbCodeSpoiler-button');
  if (button == null) return null;
  var title = _collapse(button.text);
  if (title.toLowerCase().startsWith('spoiler')) {
    title = title.substring('spoiler'.length).trim();
    if (title.startsWith(':')) title = title.substring(1).trim();
  }
  return title.isEmpty ? null : title;
}

// --- Rich spoiler content ----------------------------------------------------

const int _spoilerTextCap = 8000;
const int _spoilerImageCap = 30;

List<RichPiece> _spoilerRich(Element spoiler) =>
    parseRichContent(spoiler.querySelector('.bbCodeSpoiler-content') ?? spoiler);

/// Walks [content] into inline [RichPiece]s (bold/italic/underline/strike,
/// bullets, links, non-smilie images), capped for pathological posts.
/// Shared by spoiler sections and the forum post-loop parser.
List<RichPiece> parseRichContent(Element content) {
  final pieces = <RichPiece>[];
  int textLength = 0;
  int imageCount = 0;
  bool capped = false;
  bool afterMaskedLink = false;

  void addNewline() {
    if (pieces.isNotEmpty && !pieces.last.newline) pieces.add(const RichPiece.newline());
  }

  void visit(
    Node node, {
    bool bold = false,
    bool italic = false,
    bool underline = false,
    bool strike = false,
    String? link,
  }) {
    if (capped) return;

    if (node is Element) {
      final tag = node.localName;
      if (node.classes.contains('messageHide')) {
        // Guest-masked link ("You must be registered to see the links"),
        // one div per link. Replace with a tappable sign-in prompt, and
        // collapse consecutive masks (host lists separated by dashes)
        // into a single prompt.
        if (!afterMaskedLink) {
          pieces.add(const RichPiece.text('Sign in', url: 'https://f95zone.to/login/'));
          pieces.add(const RichPiece.text(' to see links'));
          afterMaskedLink = true;
        }
        return;
      }
      if (node.classes.contains('bbCodeSpoiler-button')) return;
      if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
      if (tag == 'br') {
        addNewline();
        return;
      }
      if (tag == 'img') {
        if (node.classes.contains('smilie')) return;
        final rawSrc = node.attributes['src'] ?? '';
        final dataSrc = node.attributes['data-src'];
        // Inline thumbnail: the live `src` (an http `/thumb/` URL) when
        // usable, else the saved-page `data-src` (JS-populated full URL).
        final thumb = rawSrc.startsWith('http') ? rawSrc : (dataSrc ?? rawSrc);
        if (!thumb.startsWith('http') || imageCount >= _spoilerImageCap) return;
        // Full-size shown when tapped: the enclosing lightbox anchor when it
        // points at an image, else data-src, else the thumbnail with the
        // `/thumb/` segment dropped (f95 attachment thumbs live under it).
        final String full;
        if (link != null && _isImageUrl(link)) {
          full = link;
        } else if (dataSrc != null && dataSrc.startsWith('http')) {
          full = dataSrc;
        } else {
          full = thumb.replaceFirst('/thumb/', '/');
        }
        imageCount++;
        pieces.add(RichPiece.image(thumb, fullImageUrl: full == thumb ? null : full));
        return;
      }

      final childLink = tag == 'a' ? (node.attributes['href'] ?? link) : link;
      final childBold = bold || tag == 'b' || tag == 'strong';
      final childItalic = italic || tag == 'i' || tag == 'em';
      final childUnderline = underline || tag == 'u';
      final childStrike = strike || tag == 's' || tag == 'strike' || tag == 'del';

      final bool isBlock = tag == 'div' || tag == 'p' || tag == 'li' || tag == 'ul' || tag == 'ol';
      if (isBlock) addNewline();
      if (tag == 'li') {
        pieces.add(const RichPiece.text('• '));
        textLength += 2;
      }
      for (final child in node.nodes) {
        visit(
          child,
          bold: childBold,
          italic: childItalic,
          underline: childUnderline,
          strike: childStrike,
          link: childLink,
        );
      }
      if (isBlock) addNewline();
      return;
    }

    if (node is Text) {
      final raw = node.text.replaceAll('​', '');
      if (raw.trim().isEmpty) return;
      if (afterMaskedLink) {
        // Separator-only runs (" - ") between masked links vanish with
        // the masks they separated; real text ends the cluster.
        if (!raw.contains(RegExp(r'[a-zA-Z0-9]'))) return;
        afterMaskedLink = false;
      }
      var text = raw.replaceAll(RegExp(r'\s+'), ' ');
      if (textLength + text.length > _spoilerTextCap) {
        text = '${text.substring(0, (_spoilerTextCap - textLength).clamp(0, text.length))}…';
        capped = true;
      }
      textLength += text.length;
      pieces.add(
        RichPiece.text(
          text,
          bold: bold,
          italic: italic,
          underline: underline,
          strike: strike,
          url: link == null ? null : _absoluteUrl(link),
        ),
      );
    }
  }

  visit(content);

  while (pieces.isNotEmpty && pieces.last.newline) {
    pieces.removeLast();
  }
  return pieces;
}

String _plainFromRich(List<RichPiece> pieces) {
  final buffer = StringBuffer();
  for (final piece in pieces) {
    if (piece.newline) {
      buffer.write('\n');
    } else if (piece.imageUrl == null) {
      buffer.write(piece.text);
    }
  }
  final cleanedLines = [
    for (final line in buffer.toString().split('\n'))
      if (_collapse(line).isNotEmpty) _collapse(line),
  ];
  return cleanedLines.join('\n');
}
