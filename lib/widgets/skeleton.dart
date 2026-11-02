import 'package:flutter/material.dart';

/// Shimmering placeholders shown instead of spinners while data loads.
/// Wrap a group of [Bone]s in one [Skeleton]: the shine sweeps over all of them together.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF1A2C22) : const Color(0xFFE9ECEF);
    final shine = dark ? const Color(0xFF243B2E) : const Color(0xFFF6F8FA);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) => ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            final t = _c.value * 2.6 - 0.8; // sweeps from left of the box to right of it
            return LinearGradient(
              begin: Alignment(-1.0 + t, -0.3),
              end: Alignment(0.0 + t, 0.3),
              colors: [base, shine, base],
              stops: const [0.15, 0.5, 0.85],
            ).createShader(rect);
          },
          child: child,
        ),
      ),
    );
  }
}

/// One grey rounded block (a line of text, a badge, a picture ...). Use inside a [Skeleton].
class Bone extends StatelessWidget {
  const Bone({super.key, this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

class _BoneCard extends StatelessWidget {
  const _BoneCard({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: padding, child: child));
}

/// A document / list row: title line, two detail lines and a badge.
class _RowBones extends StatelessWidget {
  const _RowBones({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _BoneCard(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Bone(height: 16, width: double.infinity)),
              const SizedBox(width: 40),
              Bone(width: compact ? 40 : 64, height: compact ? 18 : 22, radius: 999),
            ],
          ),
          SizedBox(height: compact ? 8 : 12),
          const Bone(width: 220, height: 12),
          if (!compact) ...const [
            SizedBox(height: 8),
            Bone(width: 150, height: 12),
          ],
        ],
      ),
    );
  }
}

/// Placeholder list (documents, master data, org tree ...).
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.compact = false, this.padding});

  final int count;
  final bool compact;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding ?? const EdgeInsets.all(16),
        itemCount: count,
        separatorBuilder: (_, __) => SizedBox(height: compact ? 8 : 12),
        itemBuilder: (_, __) => _RowBones(compact: compact),
      ),
    );
  }
}

/// A couple of placeholder rows for the end of a list that is loading its next page.
class SkeletonFooter extends StatelessWidget {
  const SkeletonFooter({super.key});

  @override
  Widget build(BuildContext context) =>
      const Skeleton(child: Padding(padding: EdgeInsets.symmetric(vertical: 4), child: _RowBones(compact: true)));
}

/// Plain bars inside a card (a few text lines).
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.lines = 3});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Bone(width: i.isEven ? double.infinity : 180, height: 13),
          ],
        ],
      ),
    );
  }
}

/// Home dashboard: two tiles, a row of small tiles, a chart and a list.
class SkeletonHome extends StatelessWidget {
  const SkeletonHome({super.key});

  Widget _tile() => const Expanded(
        child: _BoneCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Bone(width: 28, height: 28, radius: 10), SizedBox(height: 14), Bone(width: 50, height: 24), SizedBox(height: 8), Bone(width: 90, height: 11)],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [_tile(), const SizedBox(width: 10), _tile()]),
          const SizedBox(height: 10),
          Row(children: [_tile(), const SizedBox(width: 10), _tile()]),
          const SizedBox(height: 12),
          const _BoneCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Bone(width: 140, height: 16),
                SizedBox(height: 16),
                Bone(height: 150, radius: 12),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _RowBones(),
          const SizedBox(height: 12),
          const _RowBones(),
        ],
      ),
    );
  }
}

/// Document detail: a few cards with label / value pairs.
class SkeletonDetail extends StatelessWidget {
  const SkeletonDetail({super.key});

  Widget _card(int rows) => _BoneCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Bone(width: 130, height: 16),
            const SizedBox(height: 14),
            for (var i = 0; i < rows; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              const Bone(width: 80, height: 11),
              const SizedBox(height: 6),
              Bone(width: i.isEven ? 240 : 170, height: 14),
            ],
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [_card(4), const SizedBox(height: 12), _card(3), const SizedBox(height: 12), _card(2)],
      ),
    );
  }
}

/// A whole page-shaped block (PDF page or image while it downloads).
class SkeletonPage extends StatelessWidget {
  const SkeletonPage({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const Skeleton(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Center(
              child: AspectRatio(aspectRatio: 210 / 297, child: Bone(width: double.infinity, height: double.infinity, radius: 12)),
            ),
          ),
        ),
        if (label != null)
          Text(label!, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55), fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Shown while the saved sign-in is read: the shape of the app, no spinner.
class SkeletonSplash extends StatelessWidget {
  const SkeletonSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Skeleton(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Bone(width: 200, height: 24),
                SizedBox(height: 8),
                Bone(width: 260, height: 12),
                SizedBox(height: 24),
                Expanded(child: SingleChildScrollView(physics: NeverScrollableScrollPhysics(), child: _SplashBody())),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SplashBody extends StatelessWidget {
  const _SplashBody();

  @override
  Widget build(BuildContext context) => const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_RowBones(), SizedBox(height: 12), _RowBones(), SizedBox(height: 12), _RowBones(), SizedBox(height: 12), _RowBones()],
      );
}
