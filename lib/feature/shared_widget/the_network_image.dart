import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Standard network image with a shimmer placeholder.
class TheNetworkImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const TheNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Decode at display size: a full 1600x1200 photo costs ~7MB of memory.
      // Constrain one side only so the aspect ratio (and BoxFit) is kept.
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final w = width?.isFinite == true ? width! : constraints.maxWidth;
      final h = height?.isFinite == true ? height! : constraints.maxHeight;
      final decodeByWidth = w.isFinite && (!h.isFinite || w > h);
      return ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: CachedNetworkImage(
          imageUrl: url,
          width: width,
          height: height,
          fit: fit,
          memCacheWidth: decodeByWidth ? (w * dpr).round() : null,
          memCacheHeight:
              !decodeByWidth && h.isFinite ? (h * dpr).round() : null,
          placeholder: (context, _) => Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Container(width: width, height: height, color: Colors.white),
          ),
          errorWidget: (context, _, __) => Container(
            width: width,
            height: height,
            color: Colors.grey.shade200,
            child: const Icon(Icons.image_not_supported_outlined),
          ),
        ),
      );
    });
  }
}
