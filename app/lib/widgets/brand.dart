import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/relic_theme.dart';
import '../theme/tokens.dart';
import 'relic_mark.dart';

/// The full Relic logo: the gold shard + the "Relic" wordmark, matching the
/// site nav. The lockup is proportional to the mark — the wordmark is set at
/// the mark's own height in Stack Sans Headline *regular*, tracked −2%, one
/// third of a mark-height away. Use this on brand surfaces instead of a giant
/// bare icon.
class RelicWordmark extends StatelessWidget {
  /// Height of the mark, and the wordmark's font size.
  final double markSize;

  /// Ink for the wordmark. Null takes the palette's primary text, so the
  /// lockup reads correctly in both themes instead of defaulting to light-mode
  /// ink on a dark ground.
  final Color? color;
  const RelicWordmark({
    super.key,
    this.markSize = 26,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = RelicTheme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        RelicIcon(size: markSize),
        SizedBox(width: markSize * 0.33),
        Text(
          'Relic',
          style: RelicTheme.headline(
            size: markSize,
            weight: FontWeight.w400,
            color: color ?? c.text,
            height: 1,
            letterSpacing: markSize * -0.02,
          ),
        ),
      ],
    );
  }
}
