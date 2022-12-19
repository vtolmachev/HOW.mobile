import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:graphview/GraphView.dart';

class MyAlgo extends FruchtermanReingoldAlgorithm {

  MyAlgo() {
    super.repulsionPercentage = 0.3;
    super.graphWidth = 300;
    super.graphHeight = 300;
  }
  @override
  void init(Graph? graph) {
    if (graph!.nodes.length==0) return;

    double dimension = sqrt(graph!.nodes.length);
    int dim = dimension.toInt();
    if (dim < dimension) {
      dim++;
    }

    double dx = (graphWidth/dim);
    double dy = (graphHeight/dim);
    int x_counter = 0;

    double x = dx/2;
    double y = dy/2;


    graph!.nodes.forEach((node) {
      displacement[node] = Offset.zero;
      node.position = Offset(x,y);
      x+=dx;
      x_counter++;
      if (x_counter==dim) {
        x_counter=0;
        x = dx/2;
        y+= dy;
      }
    });
  }
}