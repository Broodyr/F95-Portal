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
      if (tag == 'script' || tag == 'style') return;
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
  final platforms = <DownloadGroup>[];
  final extras = <DownloadGroup>[];
  final overviewBuffer = StringBuffer();

  bool collectingOverview = false;
  bool inDownloads = false;
  bool inExtras = false;
  String? pendingLabel;

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
      final title = _spoilerTitle(element) ?? _usableLabel(pendingLabel) ?? 'Spoiler';
      spoilers.add(SpoilerSection(title: title, content: _spoilerContent(element)));
      pendingLabel = null;
      continue;
    }

    final (label, hadColon, rest) = _splitLeadingBold(line);
    final links = [for (final item in rest) if (item.href != null) DownloadLink(host: item.text, url: item.href!)];

    if (label.isNotEmpty) {
      if (label.toUpperCase().startsWith('DOWNLOAD')) {
        collectingOverview = false;
        inDownloads = true;
        pendingLabel = null;
        if (links.isNotEmpty) platforms.add(DownloadGroup(label: 'Links', links: links));
        continue;
      }

      if (inDownloads) {
        if (label.toLowerCase() == 'extras' && links.isEmpty) {
          inExtras = true;
          pendingLabel = null;
          continue;
        }
        if (links.isNotEmpty) {
          final group = DownloadGroup(label: label, links: links);
          (!inExtras && _isPlatform(label) ? platforms : extras).add(group);
          pendingLabel = null;
        } else {
          pendingLabel = label;
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
    } else if (inDownloads && links.isNotEmpty && pendingLabel != null) {
      // Anchors-only lines attach to the preceding bold label; unlabeled
      // link lines are credits/prose, not downloads.
      final group = DownloadGroup(label: pendingLabel, links: links);
      (!inExtras && _isPlatform(group.label) ? platforms : extras).add(group);
      pendingLabel = null;
    }
  }

  return ThreadPage(
    threadId: threadId,
    metaFields: metaFields,
    overview: overviewBuffer.toString().trim(),
    spoilers: spoilers,
    downloads: platforms.isEmpty && extras.isEmpty ? null : DownloadsSection(platforms: platforms, extras: extras),
  );
}

String _collapse(String text) => text.replaceAll('​', '').replaceAll(RegExp(r'\s+'), ' ').trim();

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

/// Meta values prefer plain text; falls back to link labels ("Other Games: Link").
String _metaValue(List<_Item> rest) {
  final words = _plainText(rest.where((i) => i.href == null).toList())
      .split(' ')
      // Link separators ("Patreon - Itch - Steam") leave dangling dashes
      // once the link texts are dropped.
      .where((word) => word != '-' && word != '–')
      .toList();
  final text = words.join(' ').trim();
  if (text.isNotEmpty) return text;
  return _collapse(rest.where((i) => i.href != null).map((i) => i.text).join(', '));
}

String _plainText(List<_Item> items) {
  final joined = items.map((i) => i.text).join(' ');
  var text = _collapse(joined);
  while (text.startsWith(':') || text.startsWith('-')) {
    text = text.substring(1).trim();
  }
  return text;
}

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

String _spoilerContent(Element spoiler) {
  final content = spoiler.querySelector('.bbCodeSpoiler-content') ?? spoiler;
  final buffer = StringBuffer();

  void visit(Node node) {
    if (node is Element) {
      if (node.localName == 'br') {
        buffer.write('\n');
        return;
      }
      if (node.classes.contains('bbCodeSpoiler-button')) return;
      final bool isBlock = node.localName == 'div' || node.localName == 'p' || node.localName == 'li';
      if (isBlock && buffer.isNotEmpty) buffer.write('\n');
      node.nodes.forEach(visit);
      return;
    }
    if (node is Text) buffer.write(node.text);
  }

  visit(content);

  final cleanedLines = [
    for (final line in buffer.toString().split('\n'))
      if (_collapse(line).isNotEmpty) _collapse(line),
  ];
  final text = cleanedLines.join('\n');
  // Changelogs can run to tens of thousands of characters; cap what the
  // modal will ever need to render.
  return text.length <= 8000 ? text : '${text.substring(0, 8000)}…';
}
