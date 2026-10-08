import 'package:flutter/cupertino.dart';
import 'package:stickers/src/pages/edit_page.dart';

class DrawLayer extends StatelessWidget implements EditorLayer {
  final DrawingPainter painter = DrawingPainter();

  static DrawLayer fromJson(Map<String, dynamic> json) {
    final layer = DrawLayer();
    layer.painter.strokes = (json["strokes"] as List).map((stroke) => Stroke.fromJson(stroke)).toList();
    return layer;
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

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "draw",
      "strokes": painter.strokes.map((e) => e.toJson()).toList(),
    };
  }
}

class Stroke {
  final Color color;
  final double width;
  List<Offset> points = [];

  Stroke(this.color, this.width);

  static Stroke fromJson(Map<String, dynamic> json) {
    Stroke s = Stroke(
      Color(json["color"] as int),
      (json["width"] as num).toDouble(),
    );
    s.points = (json["points"] as List)
        .map((p) => Offset((p["x"] as num).toDouble(), (p["y"] as num).toDouble()))
        .toList();
    return s;
  }

  Map<String, dynamic> toJson() {
    return {
      "color": color.toARGB32(),
      "width": width,
      "points": points
          .map((point) => {
                "x": point.dx,
                "y": point.dy,
              })
          .toList(),
    };
  }
}

class DrawingPainter extends CustomPainter {
  List<Stroke> strokes = [];
  double scaleFactor = 1;

  final _RepaintNotifier _repaint;

  DrawingPainter() : this._(_RepaintNotifier());

  DrawingPainter._(this._repaint) : super(repaint: _repaint);

  /// Must be called after [strokes] change, as the layer widget isn't rebuilt.
  void repaint() => _repaint.notify();

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

class _RepaintNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
