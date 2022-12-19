import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';

const double ARROW_DEGREES = 0.5;
const double ARROW_LENGTH = 10;

class MyEdgeRenderer extends EdgeRenderer {
  var trianglePath = Path();
  Function getData;

  MyEdgeRenderer(this.getData);

  @override
  void render(Canvas canvas, Graph graph, Paint paint) {
    var trianglePaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    print("start paint len = ${graph.edges.length}");

    //Перебираем все связи
    graph.edges.forEach((edge) {

      var source = edge.source;
      var destination = edge.destination;

      var sourceOffset = source.position;

      var x1 = sourceOffset.dx;
      var y1 = sourceOffset.dy;

      var destinationOffset = destination.position;

      var x2 = destinationOffset.dx;
      var y2 = destinationOffset.dy;

      var startX = x1 + source.width / 2;
      var startY = y1 + source.height / 2;
      var stopX = x2 + destination.width / 2;
      var stopY = y2 + destination.height / 2;

      var clippedLine = clipLine(startX, startY, stopX, stopY, destination);

      Paint? edgeTrianglePaint;
      if (edge.paint != null) {
        edgeTrianglePaint = Paint()
          ..color = edge.paint?.color ?? paint.color
          ..style = PaintingStyle.fill;
      }

      var triangleCentroid = drawTriangle(
          canvas, edgeTrianglePaint ?? trianglePaint, clippedLine[0], clippedLine[1], clippedLine[2], clippedLine[3]);

      // canvas.drawLine(Offset(clippedLine[0], clippedLine[1]), Offset(triangleCentroid[0], triangleCentroid[1]),
      //     edge.paint ?? paint);

      Paint p = edge.paint ?? paint;

      var data = getData();

      String cur_imei = source.key?.value;
      if (data.containsKey("${cur_imei}_wireless")) {
        var wireless = data["${cur_imei}_wireless"];
        var w_data =
        wireless[wireless.keys
            .toList()
            .first]['results'].toList();
        for (var w_el in w_data) {
          if (!w_el.containsKey("mac")) {
            continue;
          }

          String mac_dst = w_el["mac"].toLowerCase();

          if (!data.containsKey("mac_${mac_dst}")) {
            continue;
          }

          String imei_dst = data["mac_${mac_dst}"];
          if (imei_dst!=edge.destination.key!.value) {
            continue;
          }

          String signal = w_el['signal'].toString();
          String noise = w_el['noise'].toString();
          double tx = double.parse(w_el['tx_rate'].toString())/1000.0;
          double rx = double.parse(w_el['rx_rate'].toString())/1000.0;
          double rtx = tx>rx?tx:rx;
          String rtx_rate = rtx.toStringAsFixed(0);

          print("paint: ${edge.source.key!.value} -> ${edge.destination.key!.value} rtx = ${rtx_rate}");


          //String tx_rate = (tx).toStringAsFixed(0);
          //String rx_rate = (double.parse(w_el['rx_rate'].toString())/1000.0).toStringAsFixed(0);

          double? sig = double.tryParse(signal);
          Color line_col = Colors.red;
          if (sig != null) {
            if (sig > -100) line_col = Colors.amber;
            if (sig > -90) line_col = Colors.yellow;
            if (sig > -80) line_col = Colors.green;
          }

          p = Paint()
            ..color = line_col
            ..strokeWidth = 2;

          canvas.drawLine(Offset(clippedLine[0], clippedLine[1]), Offset(triangleCentroid[0], triangleCentroid[1]),
              p);

          ///
          final textStyle = TextStyle(
            color: line_col,
            fontSize: 5,
            backgroundColor: Colors.white
          );
          final textSpan1 = TextSpan(
            text: '${rtx_rate} Mbt/s',
            style: textStyle,
          );
          final textPainter1 = TextPainter(
            text: textSpan1,
            textDirection: TextDirection.ltr,
          );
          textPainter1.layout(
            minWidth: 0,
            maxWidth: 200,
          );

          final offset = Offset((clippedLine[0]+clippedLine[2])/2,  (clippedLine[1]+clippedLine[3])/2);
          canvas.save();
          canvas.translate(offset.dx, offset.dy);
          var angle = (atan2(clippedLine[3] - clippedLine[1], clippedLine[2] - clippedLine[0]) + pi);
          canvas.rotate(angle);
          canvas.translate(-offset.dx, -offset.dy);

          final offset2 = Offset(offset.dx-textPainter1.width/2, offset.dy-textPainter1.height/2);
          RRect r = RRect.fromLTRBXY(offset.dx-textPainter1.width/2-2,  offset.dy-textPainter1.height/2-2, offset.dx+textPainter1.width/2+2, offset.dy+textPainter1.height/2+2,
              2, 2);
          canvas.drawRRect(r, Paint()..color=Colors.white..style=PaintingStyle.fill);
          canvas.drawRRect(r, Paint()..color=line_col..style=PaintingStyle.stroke..strokeWidth=1);
          textPainter1.paint(canvas, offset2);

          canvas.restore();

          // final textSpan2 = TextSpan(
          //   // text: 'tx:${tx_rate}Mbt/s  rx:${rx_rate}Mbt/s',
          //   text: 'tx:${tx_rate}Mbt/s',
          //   style: textStyle,
          // );
          // final textPainter2 = TextPainter(
          //   text: textSpan2,
          //   textDirection: TextDirection.ltr,
          // );
          // textPainter2.layout(
          //   minWidth: 0,
          //   maxWidth: 200,
          // );
          //
          // canvas.save();
          // canvas.translate(offset.dx, offset.dy);
          // canvas.rotate(angle);
          // canvas.translate(-offset.dx, -offset.dy);
          //
          // final offset3 = Offset(offset.dx-textPainter2.width/2, offset.dy+textPainter2.height);
          // textPainter2.paint(canvas, offset3);
          // canvas.restore();


          ///
        }
      }



      // canvas.drawLine(Offset(clippedLine[0], clippedLine[1]), Offset(triangleCentroid[0], triangleCentroid[1]),
      //     p);

    });
    print("end paint");
  }

  List<double> drawTriangle(Canvas canvas, Paint paint, double x1, double y1, double x2, double y2) {
    var angle = (atan2(y2 - y1, x2 - x1) + pi);
    var x3 = (x2 + ARROW_LENGTH * cos((angle - ARROW_DEGREES)));
    var y3 = (y2 + ARROW_LENGTH * sin((angle - ARROW_DEGREES)));
    var x4 = (x2 + ARROW_LENGTH * cos((angle + ARROW_DEGREES)));
    var y4 = (y2 + ARROW_LENGTH * sin((angle + ARROW_DEGREES)));
    trianglePath.moveTo(x2, y2); // Top;
    trianglePath.lineTo(x3, y3); // Bottom left
    trianglePath.lineTo(x4, y4); // Bottom right
    trianglePath.close();
    //canvas.drawPath(trianglePath, paint);

    // calculate centroid of the triangle
    var x = (x2 + x3 + x4) / 3;
    var y = (y2 + y3 + y4) / 3;
    var triangleCentroid = [x, y];
    trianglePath.reset();
    return triangleCentroid;
  }

  List<double> clipLine(double startX, double startY, double stopX, double stopY, Node destination) {
    var resultLine = List.filled(4, 0.0);
    resultLine[0] = startX;
    resultLine[1] = startY;

    var slope = (startY - stopY) / (startX - stopX);
    var halfHeight = destination.height / 2;
    var halfWidth = destination.width / 2;
    var halfSlopeWidth = slope * halfWidth;
    var halfSlopeHeight = halfHeight / slope;

    if (-halfHeight <= halfSlopeWidth && halfSlopeWidth <= halfHeight) {
      // line intersects with ...
      if (destination.x > startX) {
        // left edge
        resultLine[2] = stopX - halfWidth;
        resultLine[3] = stopY - halfSlopeWidth;
      } else if (destination.x < startX) {
        // right edge
        resultLine[2] = stopX + halfWidth;
        resultLine[3] = stopY + halfSlopeWidth;
      }
    }

    if (-halfWidth <= halfSlopeHeight && halfSlopeHeight <= halfWidth) {
      // line intersects with ...
      if (destination.y < startY) {
        // bottom edge
        resultLine[2] = stopX + halfSlopeHeight;
        resultLine[3] = stopY + halfHeight;
      } else if (destination.y > startY) {
        // top edge
        resultLine[2] = stopX - halfSlopeHeight;
        resultLine[3] = stopY - halfHeight;
      }
    }

    return resultLine;
  }
}
