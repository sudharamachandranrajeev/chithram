import 'package:flutter/widgets.dart';

/// D-pad movement by geometry, for rails, grids and button rows alike.
///
/// Left / Right stay on the current row and go to the next tile. Up / Down go
/// to the nearest row in that direction and, in it, to the tile whose centre
/// is closest to the current one (so the column is kept). Returns false when
/// there is nowhere to go; the caller decides what that means (the focus
/// itself never moves to nothing).
bool moveFocus(FocusNode from, TraversalDirection direction) {
  final scope = from.nearestScope;
  if (scope == null || from.context == null) return false;
  final cur = from.rect;
  final all = scope.traversalDescendants.where((n) =>
      n != from &&
      n.canRequestFocus &&
      !n.skipTraversal &&
      n.context != null &&
      n.context!.mounted &&
      !n.rect.isEmpty);

  FocusNode? target;
  switch (direction) {
    case TraversalDirection.left:
    case TraversalDirection.right:
      final right = direction == TraversalDirection.right;
      double? best;
      for (final n in all) {
        final r = n.rect;
        if ((r.center.dy - cur.center.dy).abs() > cur.height / 2) continue;
        final dx = r.center.dx - cur.center.dx;
        if (right ? dx <= 1 : dx >= -1) continue;
        if (best == null || dx.abs() < best) {
          best = dx.abs();
          target = n;
        }
      }
    case TraversalDirection.up:
    case TraversalDirection.down:
      final down = direction == TraversalDirection.down;
      // The nearest row in this direction.
      double? rowY;
      for (final n in all) {
        final r = n.rect;
        final beyond = down ? r.top >= cur.bottom - cur.height * 0.25 : r.bottom <= cur.top + cur.height * 0.25;
        if (!beyond) continue;
        final d = (r.center.dy - cur.center.dy).abs();
        if (rowY == null || d < (rowY - cur.center.dy).abs()) rowY = r.center.dy;
      }
      if (rowY != null) {
        double? best;
        for (final n in all) {
          final r = n.rect;
          if ((r.center.dy - rowY).abs() > 12) continue;
          final beyond = down ? r.top >= cur.bottom - cur.height * 0.25 : r.bottom <= cur.top + cur.height * 0.25;
          if (!beyond) continue;
          final dx = (r.center.dx - cur.center.dx).abs();
          if (best == null || dx < best) {
            best = dx;
            target = n;
          }
        }
      }
  }
  if (target == null) return false;
  target.requestFocus();
  return true;
}
