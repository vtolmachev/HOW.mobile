import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';
import 'package:flutter_guid/flutter_guid.dart';
import 'package:graphview/GraphView.dart';
import 'package:how_connector/algo.dart';
import 'package:how_connector/renderer.dart';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

import 'package:http/http.dart' as http;

//WEB
//import 'package:flutter/foundation.dart' show kIsWeb;
//import 'package:mqtt_client/mqtt_browser_client.dart';
//WEB

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HOW Connector',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Настройка роутеров'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  //"https://how.hpn.kz/info/?imei=868186041755552"
  String _barcode = "IMEI:868186041755099";//"IMEI:868186041755438";
  String _selected = "";
  bool _internet_is_connected = false;
  bool _mqtt_is_connected = false;
  bool _is_subscribed = false;
  bool _has_data = false;
  var data = <String, dynamic>{};
  var _subscription;
  var _client;
  Graph _graph = Graph();
  TextEditingController controller_imei = TextEditingController();

  Timer? _t;

  startScan() async {
    String barcodeRes = await FlutterBarcodeScanner.scanBarcode(
        "#ff6666", "Отмена", false, ScanMode.DEFAULT);
    setState(() {
      _barcode = barcodeRes;
      getListIMEIs();
      if (_mqtt_is_connected) _client.disconnect();
      // if (_internet_is_connected) {
      //   startMQTTConnect();
      // }
    });
  }

  no_internet() {
    return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: Text(
          "Для работы приложения необходимо подключиться к сети internet",
          style: TextStyle(fontSize: 20),
        )));
  }

  mqtt_connecting() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "Идет подключение к серверу телеметрии",
              style: TextStyle(fontSize: 20),
            ))
      ],
    );
  }

  RegExp _numeric = RegExp(r'^-?[0-9]+$');

  bool isNumeric(String str) {
    return _numeric.hasMatch(str);
  }

  need_scan_qr() {
    // if (kIsWeb) {
    //   return Center( child:Column(
    //     mainAxisAlignment: MainAxisAlignment.center,
    //     crossAxisAlignment: CrossAxisAlignment.center,
    //     children: [
    //        Padding(
    //           padding: EdgeInsets.all(20),
    //           child: SizedBox(width: 150, child: TextFormField(
    //             cursorColor: Colors.black,
    //             keyboardType: TextInputType.number,
    //             decoration: const InputDecoration(
    //                 labelText: "IMEI"),
    //             controller: controller_imei,
    //           ))),
    //       TextButton(
    //           onPressed: () {
    //             if (controller_imei.text.trim().length==15) {
    //               if (isNumeric(controller_imei.text.trim())) {
    //                 setState(() {
    //                   _barcode = "IMEI:${controller_imei.text.trim()}";
    //                   startMQTTConnect();
    //                 });
    //                 return;
    //               }
    //             }
    //             ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    //               content: Text('IMEI введен не кооректно!'),
    //             ));
    //           },
    //           child: Text("ОК")),
    //     ],
    //   ));
    //
    // }
    return Center( child:Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              "Отсканируйте QR код на роутере",
              style: TextStyle(fontSize: 20),
            )),
        TextButton(
            onPressed: () {
              startScan();
            },
            child: Text("Сканировать")),
      ],
    ));
  }

  String get_imei() {
    if (_barcode.startsWith("IMEI:"))
      return _barcode.split(":")[1].trim();
    
    String res = _barcode.replaceAll("https://how.hpn.kz/info/?", "");
    var params = res.split("&");
    for(var p in params) {
      var sub = p.split("=");
      if (sub.length>1) {
        if (sub[0]=='imei')
          return sub[1].trim();
      }
    }
    return "?";
  }

  mqtt_subscribe(String topic) {
    _client.subscribe(topic, MqttQos.atMostOnce);
  }

  quart_circle(
      int pos, double percent, double size, String label, bool show_labels) {
    return Stack(
      children: [
        SizedBox(
            width: size,
            height: size,
            child: Align(
                alignment: pos == 0
                    ? Alignment.bottomLeft
                    : pos == 1
                        ? Alignment.topLeft
                        : pos == 2
                            ? Alignment.topRight
                            : Alignment.bottomRight,
                child: Container(
                  decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: pos == 0
                            ? Alignment.bottomLeft
                            : pos == 1
                                ? Alignment.topLeft
                                : pos == 2
                                    ? Alignment.topRight
                                    : Alignment.bottomRight,
                        radius: 100 / percent,
                        colors: const [Colors.red, Colors.yellow, Colors.green],
                      ),
                      borderRadius: pos == 0
                          ? BorderRadius.only(
                              topRight: Radius.circular(percent * size / 100))
                          : pos == 1
                              ? BorderRadius.only(
                                  bottomRight:
                                      Radius.circular(percent * size / 100))
                              : pos == 2
                                  ? BorderRadius.only(
                                      bottomLeft:
                                          Radius.circular(percent * size / 100))
                                  : BorderRadius.only(
                                      topLeft: Radius.circular(
                                          percent * size / 100)),
                      border: Border.all(
                        color: Colors.grey,
                        width: 1,
                      )),
                  width: percent * size / 100,
                  height: percent * size / 100,
                ))),
        if (show_labels) ...{
          SizedBox(
              width: size,
              height: size,
              child: Padding(
                  padding: EdgeInsets.all(10),
                  child: Align(
                      alignment: pos == 0
                          ? Alignment.topRight
                          : pos == 1
                              ? Alignment.bottomRight
                              : pos == 2
                                  ? Alignment.bottomLeft
                                  : Alignment.topLeft,
                      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),))))
        }
      ],
    );
  }

  double calc_percent(
      double? val, double min_percent, double min_signal, double max_signal) {
    if (val==null)
      return min_percent;

    double percent = 0;
    if (val <= min_signal)
      percent = min_percent;
    else if (val >= max_signal)
      percent = 100;
    else {
      double dif = max_signal - min_signal;
      double dv = val - min_signal;
      percent = min_percent + (dv * 100 / dif) * (1 - min_percent / 100);
    }

    return percent;
  }

  quality_circle(double size, double? rsrp, double? rsrq, double? rssi, double? snr,
      bool show_labels) {
    double rsrp_percent = calc_percent(rsrp, 10, -100, -80);
    double rsrq_percent = calc_percent(rsrq, 10, -20, -10);
    double rssi_percent = calc_percent(rssi, 10, -95, -65);
    double snr_percent = calc_percent(snr, 10, 0, 20);

    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              quart_circle(3, rssi_percent, size, "RSSI ${rssi}", show_labels),
              quart_circle(2, snr_percent, size, "SNR ${snr}", show_labels)
            ],
          ),
          Column(
            children: [
              quart_circle(0, rsrp_percent, size, "RSRP ${rsrp}", show_labels),
              quart_circle(1, rsrq_percent, size, "RSRQ ${rsrq}", show_labels)
            ],
          )
        ],
      ),
    ]);
  }

  Widget show_selected() {
    return Center(child: Column(children: [
      Padding(padding: EdgeInsets.all(20),child:Text("IMEI:${_selected}",style: TextStyle(fontSize: 20,fontWeight: FontWeight.bold),)),
      Padding(padding: EdgeInsets.only(bottom: 20),child:Text(get_provider(_selected),style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),)),

      quality_circle(
          150,
          double.tryParse(data["${_selected}_mobile"][get_provider(_selected)]["rsrp"]),
          double.tryParse(data["${_selected}_mobile"][get_provider(_selected)]["rsrq"]),
          double.tryParse(data["${_selected}_mobile"][get_provider(_selected)]["rssi"]),
          double.tryParse(data["${_selected}_mobile"][get_provider(_selected)]["snr"]),
          true
      ),
      SizedBox(
        height: 20,
      )
    ],));


  }

  show_data() {
    if (_selected!="") {
      return show_selected();
    }
    if (_graph.nodes.length==0) {
      return Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: const [
          Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "Идет запрос телеметрии с сервера...",
                style: TextStyle(fontSize: 20),
              )),
        ],
      ));
    }

    Algorithm algo = MyAlgo();
    algo.setDimensions(MediaQuery.of(context).size.width,MediaQuery.of(context).size.height-100);
    algo.renderer = MyEdgeRenderer(get_data);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
            child: InteractiveViewer(
                constrained: false,
                //boundaryMargin: EdgeInsets.all(20),
                minScale: 0.001,
                maxScale: 100,
                child: GraphView(
                  graph: _graph,
                  algorithm: algo,
                  paint: Paint()
                    ..color = Colors.black
                    ..strokeWidth = 1
                    ..style = PaintingStyle.stroke,
                  builder: (Node node) {
                    return nodeWidget(node);
                  },
                )))
      ],
    );
  }

  String get_provider(String imei) {
    if (data.containsKey("${imei}_mobile")) {
      return data["${imei}_mobile"].keys.toList()[0];
    }
    return "???";
  }


  Widget gen_caption(Widget txt, Color color) {
    return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(1),
          boxShadow: [
            BoxShadow(color: color, spreadRadius: 0.7),
          ],
        ),
        child: txt);
  }

  Widget get_rssi_Text(String imei) {
    TextStyle w = const TextStyle(fontSize: 2,color: Colors.white);
    String param="rssi";
    String name=param.toUpperCase();
    if (!data.containsKey("${imei}_mobile")) {
      return gen_caption(Text("${name}: ???", style: w),Colors.grey);
    }

    String t = data["${imei}_mobile"][get_provider(imei)][param];
    double? val = double.tryParse(t);

    if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
    if (val > -65) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
    if (val > -85) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
    if (val > -95) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
    return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  }

  Widget get_rsrp_Text(String imei) {

    TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
    String param="rsrp";
    String name=param.toUpperCase();
    if (!data.containsKey("${imei}_mobile")) {
      return gen_caption(Text("${name}: ???", style: w),Colors.grey);
    }

    String t = data["${imei}_mobile"][get_provider(imei)][param];
    double? val = double.tryParse(t);

    if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
    if (val > -80) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
    if (val > -90) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
    if (val > -100) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
    return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  }

  Widget get_rsrq_Text(String imei) {

    TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
    String param="rsrq";
    String name=param.toUpperCase();
    if (!data.containsKey("${imei}_mobile")) {
      return gen_caption(Text("${name}: ???", style: w),Colors.grey);
    }

    String t = data["${imei}_mobile"][get_provider(imei)][param];
    double? val = double.tryParse(t);

    if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
    if (val > -10) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
    if (val > -15) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
    if (val > -20) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
    return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  }

  Widget get_snr_Text(String imei) {

    TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
    String param="snr";
    String name=param.toUpperCase();
    if (!data.containsKey("${imei}_mobile")) {
      return gen_caption(Text("${name}: ???", style: w),Colors.grey);
    }

    String t = data["${imei}_mobile"][get_provider(imei)][param];
    double? val = double.tryParse(t);

    if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
    if (val > 20) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
    if (val > 13) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
    if (val > 0) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
    return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  }


  Color get_color(String imei) {
    if (!data.containsKey("${imei}_mobile")) {
      return Colors.grey;
    }

    if (data.containsKey("${imei}_time")) {
      DateTime d = data["${imei}_time"];
      if (DateTime.now().difference(d).inSeconds>62) {
        return Colors.blue;
      }
    }

    var d = data["${imei}_mobile"][get_provider(imei)];

    if (!d.containsKey("rsrp") ||
        !d.containsKey("rsrq") ||
        !d.containsKey("rssi") ||
        !d.containsKey("snr")) {
      return Colors.grey;
    }

    double? rsrp = double.tryParse(d["rsrp"]);
    double? rsrq = double.tryParse(d["rsrq"]);
    double? rssi = double.tryParse(d["rssi"]);
    double? snr = double.tryParse(d["snr"]);

    if (rsrp == null || rsrq == null || rssi == null || snr == null)
      return Colors.grey;

    double rsrp_q = 0;
    if (rsrp > -100) rsrp_q = 1;
    if (rsrp > -90) rsrp_q = 2;
    if (rsrp > -80) rsrp_q = 3;

    double rsrq_q = 0;
    if (rsrq > -20) rsrq_q = 1;
    if (rsrq > -15) rsrq_q = 2;
    if (rsrq > -10) rsrq_q = 3;

    double rssi_q = 0;
    if (rssi > -95) rssi_q = 1;
    if (rssi > -85) rssi_q = 2;
    if (rssi > -65) rssi_q = 3;

    double snr_q = 0;
    if (snr > 0) snr_q = 1;
    if (snr > 13) snr_q = 2;
    if (snr > 20) snr_q = 3;

    double avg = (rsrp_q + rsrq_q + rssi_q + snr_q) / 4;

    Color res = Colors.red;
    if (avg >= 0.7) res = Colors.amber;
    if (avg >= 1.7) res = Colors.cyan;
    if (avg >= 2.7) res = Colors.green;

    return res;
  }

  Widget nodeWidget(Node node) {
    Color col = get_color(node.key?.value);
    return Stack(
      children: [
        Container(
            child: Center(
                child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(color: Colors.blue, spreadRadius: 1),
                ],
              ),
              child: Text(
                "${get_provider(node.key?.value)}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 4,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(
                width: 30,
                height: 30,
                child: Stack(
                  children: [
                    Center(
                        child: Container(
                      color: Colors.white,
                      width: 25,
                      height: 25,
                    )),
                    InkWell(
                        onTap: () {
                          if (get_color(node.key?.value)!=Colors.grey)
                            _selected = node.key?.value;
                        },
                        child:
                            col==Colors.red ? Image(
                                image: AssetImage('assets/images/router_red.png'))
                            : col==Colors.amber ? Image(
                                image: AssetImage('assets/images/router_amber.png'))
                            : col==Colors.blue ? Image(
                                image: AssetImage('assets/images/router_blue.png'))
                            : col==Colors.green ? Image(
                                image: AssetImage('assets/images/router_green.png'))
                            : col==Colors.cyan ? Image(
                                image: AssetImage('assets/images/router_darkcyan.png'))
                            : Image(
                                image: AssetImage('assets/images/router_gray.png'))
                    )
                  ],
                )),
            Container(
              padding: EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(color: Colors.blue, spreadRadius: 1),
                ],
              ),
              child: Text(
                "${node.key?.value}",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 4,
                    fontWeight: FontWeight.bold),
              ),
            )
          ],
        ))),
      ],
    );
  }

  dynamic get_data() {
    return data;
  }

  /// The successful connect callback
  void onConnected() {
    _mqtt_is_connected = true;
    if (_barcode!="")
      getListIMEIs();
    _client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt =
          MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      print('topic is <${c[0].topic}>, payload is <-- $pt -->');

      String topic = c[0].topic as String;
      List<String> parts = topic.split("/");
      if (parts.length > 0 && parts[0] == 'HOW') {
        String imei = parts[1];
        setState(() {
          _is_subscribed = true;
          _mqtt_is_connected = true;
          _has_data = true;

          if (topic.startsWith("HOW/${imei}/monitoring/mobile")) {
            if (pt != '{"":}') {
              data[imei + "_mobile"] = jsonDecode(pt);
              data[imei + "_time"] = DateTime.now();
            } else {
              print("!");
            }
          }
          if (topic.startsWith("HOW/${imei}/monitoring/wireless")) {
            data[imei + "_wireless"] = jsonDecode(pt);
            data["mac_${data[imei + "_wireless"].keys.toList().first}"] = imei;
            data[imei + "_time"] = DateTime.now();
          }

          var new_eds = [];
          for (Node node in _graph.nodes) {
            String cur_imei = node.key?.value;
            if (data.containsKey("${cur_imei}_wireless")) {
              var wireless = data["${cur_imei}_wireless"];
              var w_data =
                  wireless[wireless.keys.toList().first]['results'].toList();
              for (var w_el in w_data) {
                String mac = w_el['mac'].toString().toLowerCase();

                String signal = w_el['signal'].toString().toLowerCase();
                String noise = w_el['noise'].toString().toLowerCase();

                double? sig = double.tryParse(signal);
                Color line_col = Colors.red;
                if (sig!=null) {
                  if (sig > -100) line_col = Colors.amber;
                  if (sig > -90) line_col = Colors.yellow;
                  if (sig > -80) line_col = Colors.green;
                }

                Paint line_paint = Paint()..color = line_col..strokeWidth=1;

                if (data.containsKey("mac_${mac}")) {
                  String con_imei = data["mac_${mac}"];
                  Node conn = _graph.getNodeUsingId(con_imei);
                  Edge ed1 = Edge(node, conn, paint: line_paint);
                  Edge ed2 = Edge(conn, node, paint: line_paint);
                  if (!new_eds.contains(ed1)) new_eds.add(ed1);
                  if (!new_eds.contains(ed2)) new_eds.add(ed2);
                }
              }
            }
          }

          for (Edge ed in _graph.edges) {
            if (!new_eds.contains(ed)) _graph.edges.remove(ed);
          }

          for (Edge ed in new_eds) {
            Edge edd = Edge(ed.destination, ed.source, paint: ed.paint);

            if (!_graph.edges.contains(ed) &&
                !_graph.edges.contains(edd)) {
              _graph.edges.add(edd);
            }
          }
        });
      }
    });
  }

  /// Pong callback
  void pong() {}

  void onSubscribed(String topic) {
    setState(() {
      _is_subscribed = true;
    });
  }

  Future<void> startMQTTConnect() async {

    // if (kIsWeb) {
    //   _client = MqttBrowserClient('wss://mqtt.hpn.kz', Guid.newGuid.toString());
    //   _client.port = 8083;
    // } else {
      _client = MqttServerClient('mqtt.hpn.kz', '');
    //}


    _client.setProtocolV311();
    _client.keepAlivePeriod = 20;
    _client.onDisconnected = onDisconnected;
    _client.onConnected = onConnected;
    _client.onSubscribed = onSubscribed;
    _client.pongCallback = pong;
    final connMess = MqttConnectMessage()
        .withClientIdentifier(Guid.newGuid.toString())
        .startClean(); // Non persistent session for testing

    _client.connectionMessage = connMess;
    try {
      await _client.connect("IoT", "wrtPhd82");
    } on NoConnectionException catch (e) {
      // Raised by the client when connection fails.
      _client.disconnect();
    } on SocketException catch (e) {
      // Raised by the socket layer
      _client.disconnect();
    }

    /// Check we are connected
    if (_client.connectionStatus!.state != MqttConnectionState.connected) {
      _client.disconnect();
    }

    setState(() {
      _mqtt_is_connected = true;
      _is_subscribed = false;
      _has_data = false;
    });
  }

  void onDisconnected() {
    print("onDisconnected");
    setState(() {
      _is_subscribed = false;
      _mqtt_is_connected = false;
      _has_data = false;
      // if (_barcode!="") {
      //   Timer(const Duration(seconds: 5),() {startMQTTConnect();});
      // }
    });
  }

  Future<void> getListIMEIs() async {
    var url =
        Uri.parse('https://how.hpn.kz:8002/v1.0/device/imei/${get_imei()}');
    var response = await http.get(url);
    if (response.statusCode != 200) {
      return;
    }

    _graph.nodes.clear();

    for (var el in json.decode(response.body)) {
      _graph.addNode(Node.Id(el));
      mqtt_subscribe('HOW/${el}/monitoring/mobile');
      mqtt_subscribe('HOW/${el}/monitoring/wireless');
    }
  }

  @override
  initState() {
    super.initState();

    startMQTTConnect();

    // if (kIsWeb) {
    //   _internet_is_connected = true;
    //   startMQTTConnect();
    // } else {
      _subscription = Connectivity()
          .onConnectivityChanged
          .listen((ConnectivityResult result) {
        if (result == ConnectivityResult.none) {
          setState(() {
            _internet_is_connected = false;
          });
        } else {
          setState(() {
            if (!_internet_is_connected) {
              _internet_is_connected = true;
              //startMQTTConnect();
            }
          });
        }
      });
    //}

    if (!_internet_is_connected) checkInternetState();

    _t = Timer.periodic(Duration(seconds: 1), (Timer t) {
      if (data.keys.length>0) {
        for (var key in data.keys) {
          if (key.endsWith("_time")) {
            DateTime d = data[key];
            if (DateTime
                .now()
                .difference(d)
                .inSeconds > 120) {
              var imei = key.split("_")[0];
              if (data.containsKey("${imei}_mobile"))
                data.remove("${imei}_mobile");
              if (data.containsKey("${imei}_wireless"))
                data.remove("${imei}_wireless");
              if (data.containsKey("${imei}_time"))
                data.remove("${imei}_time");
              break;
            }
          }
        }
      }
    });
  }

  @override
  dispose() {
    super.dispose();
    _subscription.cancel();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: _barcode!="" ? IconButton(
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_selected!="") {
                _selected = "";
              } else {
                // if (_graph.edges.length>0)
                //   _graph.edges.removeAt(0);
                //_graph.edges.clear();
                setState(() {
                  _barcode = "";
                  _selected = "";
                  _is_subscribed = false;
                  _has_data = false;
                  data = <String, dynamic>{};
                  _graph.edges.clear();
                  _graph.nodes.clear();
                  _client.disconnect();
                });
              }
            },
          ):SizedBox(),
          title: Text(widget.title),
        ),
        body: !_internet_is_connected
            ? no_internet()
            //: !_mqtt_is_connected           ? mqtt_connecting()
            : !_barcode.startsWith("IMEI:") && !_barcode.startsWith("https://how.hpn.kz/info/?")
                ? need_scan_qr()
                : show_data());
  }

  void checkInternetState() async {
    var connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult != ConnectivityResult.none) {
      if (!_internet_is_connected) {
        _internet_is_connected = true;
        //startMQTTConnect();
      }
    }
  }


}

class MyHttpOverrides extends HttpOverrides{
  @override
  HttpClient createHttpClient(SecurityContext? context){
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port)=> true;
  }
}
