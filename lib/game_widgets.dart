import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import './game_models.dart';

// ── Colours ───────────────────────────────────────────────────────────────────

class HuruufColors {
  static const teal = Color(0xFF4FC3BF);
  static const cardBg = Color(0xFFE8D5C4);
  static const cardBorder = Color(0xFF3D2B1F);
  static const gold = Color(0xFFD4A843);
  static const upvote = Color(0xFF2ECC71);
  static const downvote = Color(0xFFE74C3C);
  static const text = Color(0xFF1A0A00);
  static const cream = Color(0xFFFDF6EC);
}

// ── Text style helper ─────────────────────────────────────────────────────────

TextStyle arabicStyle({
  double fontSize = 16,
  Color color = Colors.white,
  FontWeight weight = FontWeight.w800,
}) =>
    GoogleFonts.amiri(
      fontSize: fontSize,
      fontWeight: weight,
      color: color,
    );

// ── VintageCard ───────────────────────────────────────────────────────────────

class VintageCard extends StatelessWidget {
  const VintageCard({
    super.key,
    required this.category,
    required this.letter,
    this.answer,
    this.answerController,
    this.readOnly = true,
    this.onAnswerChanged,
  });

  final TaskCategory category;
  final String letter;
  final String? answer;
  final TextEditingController? answerController;
  final bool readOnly;
  final ValueChanged<String>? onAnswerChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      constraints: const BoxConstraints(minHeight: 260),
      decoration: BoxDecoration(
        color: HuruufColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HuruufColors.cardBorder, width: 2.5),
        boxShadow: const [
          BoxShadow(
              color: Color(0x44000000),
              blurRadius: 12,
              offset: Offset(4, 6)),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _NoisePainter())),
          ..._corners(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TitleBand(category: category, letter: letter),
                const SizedBox(height: 10),
                _Illustration(category: category),
                const SizedBox(height: 10),
                readOnly
                    ? _StaticAnswer(answer: answer)
                    : _AnswerInput(
                        controller: answerController!,
                        onChanged: onAnswerChanged,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _corners() {
    const s = 24.0;
    return [
      Positioned(top: 4, left: 4, child: _Ornament(s)),
      Positioned(
          top: 4,
          right: 4,
          child: Transform.flip(flipX: true, child: _Ornament(s))),
      Positioned(
          bottom: 4,
          left: 4,
          child: Transform.flip(flipY: true, child: _Ornament(s))),
      Positioned(
          bottom: 4,
          right: 4,
          child:
              Transform.flip(flipX: true, flipY: true, child: _Ornament(s))),
    ];
  }
}

class _TitleBand extends StatelessWidget {
  const _TitleBand({required this.category, required this.letter});
  final TaskCategory category;
  final String letter;

  static const _names = <String, String>{
    'أ': 'الألف', 'ب': 'الباء', 'ت': 'التاء', 'ث': 'الثاء',
    'ج': 'الجيم', 'ح': 'الحاء', 'خ': 'الخاء', 'د': 'الدال',
    'ذ': 'الذال', 'ر': 'الراء', 'ز': 'الزاي', 'س': 'السين',
    'ش': 'الشين', 'ص': 'الصاد', 'ض': 'الضاد', 'ط': 'الطاء',
    'ظ': 'الظاء', 'ع': 'العين', 'غ': 'الغين', 'ف': 'الفاء',
    'ق': 'القاف', 'ك': 'الكاف', 'ل': 'اللام', 'م': 'الميم',
    'ن': 'النون', 'ه': 'الهاء', 'و': 'الواو', 'ي': 'الياء',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
        color: HuruufColors.cardBorder.withOpacity(0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '${category.arabicLabel} بحرف ${_names[letter] ?? letter}',
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: arabicStyle(
            fontSize: 14,
            color: HuruufColors.cream,
            weight: FontWeight.w900),
      ),
    );
  }
}

class _Illustration extends StatelessWidget {
  const _Illustration({required this.category});
  final TaskCategory category;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 80,
        child: Center(
          child:
              Text(category.emoji, style: const TextStyle(fontSize: 56)),
        ),
      );
}

class _StaticAnswer extends StatelessWidget {
  const _StaticAnswer({this.answer});
  final String? answer;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: HuruufColors.cardBorder.withOpacity(0.4)),
        ),
        child: Text(
          answer ?? '—',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: arabicStyle(
              fontSize: 18,
              color: HuruufColors.text,
              weight: FontWeight.w900),
        ),
      );
}

class _AnswerInput extends StatelessWidget {
  const _AnswerInput({required this.controller, this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
        onChanged: onChanged,
        style: arabicStyle(
            fontSize: 18,
            color: HuruufColors.text,
            weight: FontWeight.w900),
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.white.withOpacity(0.6),
          hintText: 'اكتب إجابتك',
          hintTextDirection: TextDirection.rtl,
          hintStyle: arabicStyle(
              fontSize: 14,
              color: HuruufColors.text.withOpacity(0.4)),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: HuruufColors.cardBorder.withOpacity(0.4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(
                color: HuruufColors.cardBorder.withOpacity(0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide:
                const BorderSide(color: HuruufColors.gold, width: 2),
          ),
        ),
      );
}

class _Ornament extends StatelessWidget {
  const _Ornament(this.size);
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _OrnamentPainter()));
}

class _OrnamentPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = HuruufColors.cardBorder.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.drawCircle(Offset(cx, cy), size.width * 0.4, p);
    canvas.drawCircle(Offset(cx, cy), size.width * 0.2, p);
    canvas.drawLine(Offset(0, cy), Offset(size.width * 0.25, cy), p);
    canvas.drawLine(
        Offset(size.width * 0.75, cy), Offset(size.width, cy), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final p = Paint()
      ..color = Colors.black.withOpacity(0.03)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 300; i++) {
      canvas.drawCircle(
          Offset(rand.nextDouble() * size.width,
              rand.nextDouble() * size.height),
          0.5,
          p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── FaceDownCard ──────────────────────────────────────────────────────────────

class FaceDownCard extends StatelessWidget {
  const FaceDownCard({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: 90,
        height: 120,
        decoration: BoxDecoration(
          color: HuruufColors.cardBg.withOpacity(0.6),
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: HuruufColors.cardBorder, width: 2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(2, 4))
          ],
        ),
        child: Stack(children: [
          Positioned.fill(child: CustomPaint(painter: _NoisePainter())),
          Center(
              child: CustomPaint(
                  size: const Size(70, 100),
                  painter: _CardBackPainter())),
        ]),
      );
}

class _CardBackPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color.fromARGB(255, 61, 31, 31).withOpacity(0.2)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 4; i++) {
      final o = i * 7.0;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(o, o, size.width - o * 2,
                  size.height - o * 2),
              const Radius.circular(6)),
          p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

// ── SandWatchTimer ────────────────────────────────────────────────────────────

class SandWatchTimer extends StatefulWidget {
  const SandWatchTimer(
      {super.key, required this.secondsRemaining, this.totalSeconds = 30});
  final int secondsRemaining;
  final int totalSeconds;

  @override
  State<SandWatchTimer> createState() => _SandWatchTimerState();
}

class _SandWatchTimerState extends State<SandWatchTimer>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 1))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.secondsRemaining / widget.totalSeconds.clamp(1, 9999);
    final urgent = widget.secondsRemaining <= 10;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => CustomPaint(
            size: const Size(56, 84),
            painter: _HourglassPainter(
                progress: progress,
                urgent: urgent,
                anim: _ctrl.value),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.secondsRemaining.toString(),
          style: GoogleFonts.orbitron(
            fontSize: urgent ? 22 : 18,
            fontWeight: FontWeight.bold,
            color: urgent
                ? HuruufColors.downvote
                : HuruufColors.cardBorder,
          ),
        ),
        Text('ثانية',
            style: arabicStyle(
                fontSize: 11,
                color: HuruufColors.cardBorder.withOpacity(0.7),
                weight: FontWeight.w700)),
      ],
    );
  }
}

class _HourglassPainter extends CustomPainter {
  _HourglassPainter(
      {required this.progress,
      required this.urgent,
      required this.anim});
  final double progress;
  final bool urgent;
  final double anim;

  @override
  void paint(Canvas canvas, Size size) {
    final color = urgent ? HuruufColors.downvote : HuruufColors.gold;
    final frame = Paint()
      ..color = HuruufColors.cardBorder
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final sand =
        Paint()..color = color.withOpacity(0.85)..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    canvas.drawLine(Offset(4, 6), Offset(w - 4, 6), frame);
    canvas.drawLine(Offset(4, h - 6), Offset(w - 4, h - 6), frame);

    canvas.drawPath(
      Path()
        ..moveTo(4, 6)
        ..lineTo(w - 4, 6)
        ..lineTo(cx + 4, h / 2 - 2)
        ..lineTo(w - 4, h - 6)
        ..lineTo(4, h - 6)
        ..lineTo(cx - 4, h / 2 + 2)
        ..close(),
      frame,
    );

    if (progress > 0) {
      final topH = (h / 2 - 14) * progress;
      canvas.drawPath(
        Path()
          ..moveTo(4, 6)
          ..lineTo(w - 4, 6)
          ..lineTo(cx + 4 * progress, 6 + topH)
          ..lineTo(cx - 4 * progress, 6 + topH)
          ..close(),
        sand,
      );
    }

    final filled = 1 - progress;
    if (filled > 0) {
      final botH = (h / 2 - 14) * filled;
      canvas.drawPath(
        Path()
          ..moveTo(4, h - 6)
          ..lineTo(w - 4, h - 6)
          ..lineTo(cx + 4 * filled, h - 6 - botH)
          ..lineTo(cx - 4 * filled, h - 6 - botH)
          ..close(),
        sand,
      );
    }

    if (progress > 0.05) {
      canvas.drawCircle(
        Offset(cx + math.sin(anim * math.pi * 6) * 1.5,
            h / 2 - 2 + anim * 12),
        1.5,
        Paint()..color = color.withOpacity(0.9),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HourglassPainter o) =>
      o.progress != progress || o.anim != anim;
}

// ── PhaseHeader ───────────────────────────────────────────────────────────────

class PhaseHeader extends StatelessWidget {
  const PhaseHeader(
      {super.key, required this.state, required this.roundNumber});
  final RoundState state;
  final int roundNumber;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 10),
        color: _color.withOpacity(0.9),
        child: Text(
          'الجولة $roundNumber — $_label',
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
          style: arabicStyle(
              fontSize: 18, color: Colors.white, weight: FontWeight.w900),
        ),
      );

  Color get _color {
    switch (state) {
      case RoundState.typing:
        return const Color(0xFF3498DB);
      case RoundState.voting:
        return const Color(0xFFE67E22);
      case RoundState.uniqueness:
        return const Color(0xFF9B59B6);
      case RoundState.results:
        return const Color(0xFF27AE60);
      default:
        return HuruufColors.teal;
    }
  }

  String get _label {
    switch (state) {
      case RoundState.typing:
        return 'اكتب إجابتك ✍️';
      case RoundState.voting:
        return 'صوّت على الإجابات 👍';
      case RoundState.uniqueness:
        return 'اختر الكلمات الفريدة ✨';
      case RoundState.results:
        return 'النتائج 🏆';
      default:
        return 'انتظر...';
    }
  }
}

// ── ScoreChip ─────────────────────────────────────────────────────────────────

class ScoreChip extends StatelessWidget {
  const ScoreChip({super.key, required this.score});
  final int score;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: HuruufColors.gold.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: HuruufColors.gold, width: 1.5),
        ),
        child: Text(
          '$score نقطة',
          textDirection: TextDirection.rtl,
          style: GoogleFonts.orbitron(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: HuruufColors.gold),
        ),
      );
}