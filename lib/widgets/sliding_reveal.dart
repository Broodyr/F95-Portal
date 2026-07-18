import 'package:flutter/material.dart';

import '../constants.dart';

/// Clip-and-slide reveal for collapsible content: search-sheet sections,
/// the suggestion dropdown, and spoiler cards. When [visible] flips off,
/// the outgoing child stays mounted just long enough to slide shut, then
/// is dropped from the tree so hidden content can't be found or hit.
///
/// [child] may be null while hidden — the last non-null child is retained
/// for the slide-shut. That suits callers whose visibility is derived
/// (focus/text state) and who have nothing to build once hidden.
class SlidingReveal extends StatefulWidget {
  final bool visible;
  final Widget? child;

  const SlidingReveal({super.key, required this.visible, this.child});

  @override
  State<SlidingReveal> createState() => _SlidingRevealState();
}

class _SlidingRevealState extends State<SlidingReveal> {
  Widget? _lastChild;

  /// True while sliding shut: the child is kept mounted until [AnimatedAlign]
  /// reports the collapse finished.
  bool _settling = false;

  @override
  void didUpdateWidget(SlidingReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) _settling = !widget.visible;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.visible && widget.child != null) _lastChild = widget.child;
    return ClipRect(
      child: AnimatedAlign(
        duration: Motion.duration,
        curve: Motion.curve,
        alignment: Alignment.topLeft,
        heightFactor: widget.visible ? 1 : 0,
        onEnd: () {
          if (widget.visible) return;
          setState(() {
            _settling = false;
            _lastChild = null;
          });
        },
        child: widget.visible || _settling ? _lastChild : null,
      ),
    );
  }
}
