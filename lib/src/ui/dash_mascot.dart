import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models.dart';

/// Transparent frames rendered from the rigged Blender source, 6 × 4 at 12 fps.
class DashMascot extends StatefulWidget {
  const DashMascot({
    super.key,
    required this.size,
    this.clip = 'idle',
    this.skin = MascotSkin.hanbok,
    this.animate = false,
  });
  final double size;
  final String clip;
  final MascotSkin skin;
  final bool animate;
  @override
  State<DashMascot> createState() => _DashMascotState();
}

class _DashMascotState extends State<DashMascot>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _atlas;
  String? _loadedClip;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _update();
  }

  @override
  void didUpdateWidget(DashMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _update();
  }

  void _update() {
    final assetKey = '${widget.skin.name}/${widget.clip}';
    if (_loadedClip != assetKey) {
      if (_listener != null) _stream?.removeListener(_listener!);
      _loadedClip = assetKey;
      animation.value = 0;
      _stream = AssetImage('assets/dash/$assetKey.png')
          .resolve(createLocalImageConfiguration(context));
      _listener = ImageStreamListener((info, _) {
        if (!mounted || _loadedClip != assetKey) {
          info.dispose();
          return;
        }
        setState(() {
          _atlas?.dispose();
          _atlas = info;
        });
      });
      _stream!.addListener(_listener!);
    }
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      if (!animation.isAnimating) animation.repeat();
    } else {
      animation.stop();
      animation.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.clip == 'megaphone'
        ? '빨간 확성기와 소리 파동으로 반응하는 Flutter Dash'
        : widget.clip == 'sing'
        ? '마이크를 들고 노래하는 Flutter Dash'
        : '${widget.skin.label} 의상을 입은 Flutter Dash',
    image: true,
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, _) => _atlas == null
            ? Image.asset('assets/dash/${widget.skin.name}/poster.png')
            : CustomPaint(
                painter: _DashFrame(
                  _atlas!.image,
                  (animation.value * 24).floor().clamp(0, 23),
                ),
              ),
      ),
    ),
  );

  @override
  void dispose() {
    if (_listener != null) _stream?.removeListener(_listener!);
    _atlas?.dispose();
    animation.dispose();
    super.dispose();
  }
}

class _DashFrame extends CustomPainter {
  _DashFrame(this.image, this.frame);
  final ui.Image image;
  final int frame;
  @override
  void paint(Canvas canvas, Size size) {
    final tile = image.width / 6;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH((frame % 6) * tile, (frame ~/ 6) * tile, tile, tile),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_DashFrame old) =>
      old.image != image || old.frame != frame;
}
