import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:innertube/innertube.dart' show StoryboardFrame, StoryboardLevel;

/// Loads one sprite sheet. Tests swap it.
typedef SheetProvider = ImageProvider Function(Uri url, int decodeWidth);

ImageProvider networkSheet(Uri url, int decodeWidth) => ResizeImage(
  NetworkImage(url.toString()),
  width: decodeWidth,
  allowUpscaling: false,
);

/// The frame's rectangle inside a sheet image of [image] pixels (which may
/// have been decoded smaller than the sheet's native size).
Rect storyboardSource(
  StoryboardLevel level,
  StoryboardFrame frame,
  Size image,
) {
  final fw = image.width / level.cols;
  final fh = image.height / level.rows;
  return Rect.fromLTWH(frame.col * fw, frame.row * fh, fw, fh);
}

/// Width to decode a sheet at when its frames show [displayWidth] logical
/// pixels wide at [pixelRatio]: never above native size.
int sheetDecodeWidth(
  StoryboardLevel level,
  double displayWidth,
  double pixelRatio,
) {
  final scale = math.min(1.0, displayWidth * pixelRatio / level.width);
  return math.max(1, (level.cols * level.width * scale).round());
}

/// The preview frame for [time]: one crop of a sprite sheet, decoded at
/// display size. Keeps the last frame on screen while the next sheet loads.
class StoryboardThumb extends StatefulWidget {
  const StoryboardThumb({
    super.key,
    required this.level,
    required this.time,
    required this.width,
    this.provider = networkSheet,
  });

  final StoryboardLevel level;
  final Duration time;
  final double width;
  final SheetProvider provider;

  @override
  State<StoryboardThumb> createState() => _StoryboardThumbState();
}

class _StoryboardThumbState extends State<StoryboardThumb> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  StoryboardFrame? _shown;
  Uri? _loading;
  Uri? _infoUrl;

  double get _height => widget.width * widget.level.height / widget.level.width;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(StoryboardThumb old) {
    super.didUpdateWidget(old);
    _resolve();
  }

  void _resolve() {
    final frame = widget.level.frameAt(widget.time);
    if (_loading == frame.url) {
      // Same sheet, another frame: no new load, just move the crop.
      if (_infoUrl == frame.url) _shown = frame;
      return;
    }
    _loading = frame.url;
    _detach();
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final provider = widget.provider(
      frame.url,
      sheetDecodeWidth(widget.level, widget.width, ratio),
    );
    final stream = provider.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      if (!mounted || _loading != frame.url) {
        info.dispose();
        return;
      }
      setState(() {
        _info?.dispose();
        _info = info.clone();
        _shown = frame;
        _infoUrl = frame.url;
      });
      info.dispose();
    }, onError: (_, _) {});
    _stream = stream..addListener(listener);
    _listener = listener;
  }

  void _detach() {
    final l = _listener;
    if (l != null) _stream?.removeListener(l);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    _info?.dispose();
    _info = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final frame = _shown;
    return SizedBox(
      width: widget.width,
      height: _height,
      child: info == null || frame == null
          ? const ColoredBox(color: Color(0xFF000000))
          : RepaintBoundary(
              child: CustomPaint(
                painter: _FramePainter(widget.level, frame, info.image),
              ),
            ),
    );
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.level, this.frame, this.image);

  final StoryboardLevel level;
  final StoryboardFrame frame;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final src = storyboardSource(
      level,
      frame,
      Size(image.width.toDouble(), image.height.toDouble()),
    );
    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_FramePainter old) =>
      old.image != image ||
      old.frame.col != frame.col ||
      old.frame.row != frame.row;
}
