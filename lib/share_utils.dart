import 'package:flutter/material.dart';

/// share_plus on iOS treats every device as if it needs a popover anchor
/// (`popoverPresentationController` is non-nil even on iPhone, not just
/// iPad/Mac) — without `sharePositionOrigin` it silently returns a
/// PlatformException instead of opening the share sheet, and since none of
/// the call sites awaited/caught that error, tapping "share" did nothing at
/// all. Anchoring to the screen's own bounds is enough to satisfy it.
Rect? shareOriginFrom(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
