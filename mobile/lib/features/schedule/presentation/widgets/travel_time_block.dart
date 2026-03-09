import 'package:flutter/material.dart';
import 'package:patterns_canvas/patterns_canvas.dart';

/// Widget rendering a hatched travel time block between consecutive bookings.
///
/// Visual design:
///   - Diagonal stripe pattern (DiagonalStripesLight from patterns_canvas)
///   - Light grey background with medium grey stripes
///   - Centered "Travel" label shown only when block is tall enough (≥ 30px)
///   - No user interaction — purely visual spacer
///
/// Used in [ContractorLane] to fill the gap between consecutive bookings where
/// a 'travel_buffer' [BlockedInterval] exists.
///
/// Leaf widget — no dependency on providers, ContractorLane, or CalendarDayView.
class TravelTimeBlock extends StatelessWidget {
  const TravelTimeBlock({
    required this.height,
    required this.width,
    super.key,
  });

  /// Height of the block in logical pixels (travelDurationMinutes × pixelsPerMinute).
  final double height;

  /// Width of the block (matches parent contractor lane width).
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          // Hatched diagonal stripe background using patterns_canvas.
          CustomPaint(
            size: Size(width, height),
            painter: _TravelStripesPainter(),
          ),
          // "Travel" label — only shown when block has enough vertical space.
          if (height >= 30)
            Center(
              child: Text(
                'Travel',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// [CustomPainter] that fills the canvas with a diagonal stripe pattern.
///
/// Uses [DiagonalStripesLight] from patterns_canvas for the hatched travel
/// block appearance — consistent with common dispatch calendar conventions.
class _TravelStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final pattern = DiagonalStripesLight(
      bgColor: const Color(0xFFF5F5F5), // grey.shade100
      fgColor: const Color(0xFFBDBDBD), // grey.shade400
    );
    pattern.paintOnWidget(canvas, size);
  }

  @override
  bool shouldRepaint(_TravelStripesPainter oldDelegate) => false;
}
