import 'package:flutter/cupertino.dart';
import 'package:image_editor/image_editor.dart';
import 'package:stickers/src/pages/edit_page.dart';

class DrawLayer extends StatelessWidget implements EditorLayer {
  final DrawingPainter painter = DrawingPainter();

  DrawOption get drawOption {
    DrawOption r = DrawOption();
    for (final stroke in painter.strokes) {
      if (stroke.points.isEmpty) continue;
      final linePaint = DrawPaint(paintingStyle: PaintingStyle.stroke, color: stroke.color, lineWeight: stroke.width);
      final fillPaint = DrawPaint(paintingStyle: PaintingStyle.fill, color: stroke.color, lineWeight: stroke.width);
      Offset last = stroke.points.first;
      for (final point in stroke.points) {
        r.addDrawPart(LineDrawPart(start: last, end: point, paint: linePaint));
        r.addDrawPart(
          OvalDrawPart(
              rect: Rect.fromLTWH(
                point.dx - (stroke.width ) / 2 ,
                point.dy - (stroke.width ) / 2 ,
                stroke.width ,
                stroke.width ,
              ),
              paint: fillPaint),
        );
        last = point;
      }
    }
    return r;
  }

  DrawLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: painter,
      ),
    );
  }
}

class Stroke {
  final Color color;
  final double width;
  List<Offset> points = [];

  Stroke(this.color, this.width);
}

class DrawingPainter extends CustomPainter {
  List<Stroke> strokes = [];
  double scaleFactor = 1;

  DrawingPainter();

  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint();
    paint.strokeCap = StrokeCap.round;
    for (final stroke in strokes) {
      paint.color = stroke.color;
      paint.strokeWidth = stroke.width * scaleFactor;
      if (stroke.points.isEmpty) continue;
      Offset last = stroke.points.first;
      for (final point in stroke.points) {
        canvas.drawLine(last * scaleFactor, point * scaleFactor, paint);
        last = point;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
