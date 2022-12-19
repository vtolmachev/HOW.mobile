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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mqtt_client/mqtt_browser_client.dart';
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
      home: const Content(title: 'Настройка роутеров'),
    );
  }
}

class Content extends StatefulWidget {
  const Content({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<Content> createState() => _ContentState();
}

class _ContentState extends State<Content> {

  //Внутренние переменные
  //"https://how.hpn.kz/info/?imei=868186041755552"

  String  _barcode = "";//"""IMEI:868186041755099";//Тут хранится отсканированный
                                        // или введенный IMEI

  String  _selectedImei = "";           //Текущий выбранный IMEI
                                        // для отображения сигнала

  bool    _mqttIsConnected = false;     //Признак подключения к серверу
  var     _data = <String, dynamic>{};  //Основные данные приложения
  var     _mqttClient;                  //MQTT клиент
  final Graph _graph = Graph();         //Граф для отображения

                                        //Контроллер ручного ввода IMEI
  final TextEditingController _controllerImei = TextEditingController();

  ///Функция сканирования QR для мобильного приложения
  startScan() async {
    String barcodeRes = await FlutterBarcodeScanner.scanBarcode(
        "#ff6666", "Отмена", false, ScanMode.DEFAULT);

    if (getImei(barcodeRes)=="?") {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('IMEI не распознан!'),
      ));
      return;
    }

    //Сохраняем IMEI и получаем список IMEI для графа
    setState(() {
      _barcode = barcodeRes;
      getListIMEIs();
    });
  }

  ///Отображение в случае отсутствия интернета
  Widget noInternet() {
    return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
            child: Text(
          "Для работы приложения необходимо подключиться к сети Internet",
          style: TextStyle(fontSize: 20),
        )));
  }

  ///Отображение в случае отсутствия связи с MQTT сервером
  Widget mqttConnecting() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        Padding(
            padding: EdgeInsets.all(20),
            child: Center( child: Text(
              "Идет подключение к серверу телеметрии...",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20),
            )))
      ],
    );
  }

  //Регуляряка для проверки что введено числовое значение
  final RegExp _numeric = RegExp(r'^-?[0-9]+$');
  ///Функция проверки ввода числового значения
  bool isNumeric(String str) {
    return _numeric.hasMatch(str);
  }

  Widget needScanQR() {
      return Center( child:Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
           Padding(
              padding: EdgeInsets.all(20),
              child: SizedBox(width: 150, child: TextFormField(
                cursorColor: Colors.black,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: "IMEI"),
                controller: _controllerImei,
              ))),
          TextButton(
              onPressed: () {
                String im = _controllerImei.text.trim().replaceAll("-", "");
                if (im.length==15) {
                  if (isNumeric(im)) {
                    setState(() {
                      _barcode = "IMEI:$im";
                      //startMQTTConnect();
                      getListIMEIs();
                    });
                    return;
                  }
                }
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('IMEI введен не кооректно!'),
                ));
              },
              child: Text("ОК")),
          if (!kIsWeb) ... [
            TextButton(
                onPressed: () {
                  startScan();
                },
                child: Text("Сканировать"))
          ]

        ],
      ));


  }

  ///Извлекает IMEI из отсканированной либо введенной переменной _barcode
  String getImei(String bc) {
    if (bc.startsWith("IMEI:"))
      return bc.split(":")[1].trim();
    
    String res = bc.replaceAll("https://how.hpn.kz/info/?", "");
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

  ///Осуществляет подписку на роутер
  void mqtt_subscribe(String topic) {
    _mqttClient.subscribe(topic, MqttQos.atMostOnce);
  }

  ///Отрисовывает четвертинку для сигнала роутера
  /// pos - 0 (ниж. левый угол), 1 (верх левый), 2 (верх правый), 3 (нижний прав)
  /// percent - процент уровня сигнала
  /// size - размер виджета (всех 4х частей)
  /// label - подпись
  /// showLabels - признак того, нужны ли надписи
  Widget quart_circle(
      int pos, double percent, double size, String label, bool showLabels) {
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
        if (showLabels) ...{
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

  ///Вычисляет процент по сигналу
  ///val - значение, которое нужно преобразовать в процент
  ///minPercent - минимальный процент, меньше которого отображать нельзя
  ///minSignal - минимальный уровень сигнала
  ///maxSignal - максимальный уровень сигнала
  double calcSignalPercent(
      double? val, double minPercent, double minSignal, double maxSignal) {
    if (val==null) {
      return minPercent;
    }

    double percent = 0;
    if (val <= minSignal) {
      percent = minPercent;
    } else if (val >= maxSignal) {
      percent = 100;
    } else {
      double dif = maxSignal - minSignal;
      double dv = val - minSignal;
      percent = minPercent + (dv * 100 / dif) * (1 - minPercent / 100);
    }

    return percent;
  }

  ///Рисует 4х лепестковый индиктор сигнала для lte соединения
  ///size - размер виджета
  ///rsrp,rsrq,rssi,snr - параметры сигнала
  ///showLabels - подписывать или нет уровни сигнала
  Widget qualityCircle(double size, double? rsrp, double? rsrq, double? rssi,
      double? snr, bool showLabels) {

    double rsrpPercent = calcSignalPercent(rsrp, 10, -100, -80);
    double rsrqPercent = calcSignalPercent(rsrq, 10, -20, -10);
    double rssiPercent = calcSignalPercent(rssi, 10, -95, -65);
    double snrPercent = calcSignalPercent(snr, 10, 0, 20);

    return Column(children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Column(
            children: [
              quart_circle(3, rssiPercent, size, "RSSI ${rssi}", showLabels),
              quart_circle(2, snrPercent, size, "SNR ${snr}", showLabels)
            ],
          ),
          Column(
            children: [
              quart_circle(0, rsrpPercent, size, "RSRP ${rsrp}", showLabels),
              quart_circle(1, rsrqPercent, size, "RSRQ ${rsrq}", showLabels)
            ],
          )
        ],
      ),
    ]);
  }

  ///Отображает выбранный индикатор сигнала для роутера
  Widget showSelectedIMEI() {
    return Center(child: Column(children: [
      Padding(padding: const EdgeInsets.all(20),
          child:Text("IMEI:$_selectedImei",
          style: const TextStyle(fontSize: 20,fontWeight: FontWeight.bold),)),
      Padding(padding: const EdgeInsets.only(bottom: 20),
          child:Text(getProvider(_selectedImei),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),)),

      qualityCircle(
          150,
          double.tryParse(_data["${_selectedImei}_mobile"][getProvider(_selectedImei)]["rsrp"]),
          double.tryParse(_data["${_selectedImei}_mobile"][getProvider(_selectedImei)]["rsrq"]),
          double.tryParse(_data["${_selectedImei}_mobile"][getProvider(_selectedImei)]["rssi"]),
          double.tryParse(_data["${_selectedImei}_mobile"][getProvider(_selectedImei)]["snr"]),
          true
      ),
      const SizedBox(
        height: 20,
      )
    ],));
  }

  ///Отображение графа либо выбранного роутера
  Widget showData() {
    if (_selectedImei!="") {
      return showSelectedIMEI();
    }
    if (_graph.nodes.isEmpty) {
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

  ///Извлекает название сотового оператора
  String getProvider(String imei) {
    if (_data.containsKey("${imei}_mobile")) {
      return _data["${imei}_mobile"].keys.toList()[0];
    }
    return "???";
  }


  // Widget gen_caption(Widget txt, Color color) {
  //   return Container(
  //       decoration: BoxDecoration(
  //         borderRadius: BorderRadius.circular(1),
  //         boxShadow: [
  //           BoxShadow(color: color, spreadRadius: 0.7),
  //         ],
  //       ),
  //       child: txt);
  // }
  //
  // Widget get_rssi_Text(String imei) {
  //   TextStyle w = const TextStyle(fontSize: 2,color: Colors.white);
  //   String param="rssi";
  //   String name=param.toUpperCase();
  //   if (!_data.containsKey("${imei}_mobile")) {
  //     return gen_caption(Text("${name}: ???", style: w),Colors.grey);
  //   }
  //
  //   String t = _data["${imei}_mobile"][getProvider(imei)][param];
  //   double? val = double.tryParse(t);
  //
  //   if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
  //   if (val > -65) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
  //   if (val > -85) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
  //   if (val > -95) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
  //   return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  // }
  //
  // Widget get_rsrp_Text(String imei) {
  //
  //   TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
  //   String param="rsrp";
  //   String name=param.toUpperCase();
  //   if (!_data.containsKey("${imei}_mobile")) {
  //     return gen_caption(Text("${name}: ???", style: w),Colors.grey);
  //   }
  //
  //   String t = _data["${imei}_mobile"][getProvider(imei)][param];
  //   double? val = double.tryParse(t);
  //
  //   if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
  //   if (val > -80) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
  //   if (val > -90) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
  //   if (val > -100) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
  //   return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  // }
  //
  // Widget get_rsrq_Text(String imei) {
  //
  //   TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
  //   String param="rsrq";
  //   String name=param.toUpperCase();
  //   if (!_data.containsKey("${imei}_mobile")) {
  //     return gen_caption(Text("${name}: ???", style: w),Colors.grey);
  //   }
  //
  //   String t = _data["${imei}_mobile"][getProvider(imei)][param];
  //   double? val = double.tryParse(t);
  //
  //   if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
  //   if (val > -10) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
  //   if (val > -15) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
  //   if (val > -20) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
  //   return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  // }
  //
  // Widget get_snr_Text(String imei) {
  //
  //   TextStyle w = TextStyle(fontSize: 2,color: Colors.white);
  //   String param="snr";
  //   String name=param.toUpperCase();
  //   if (!_data.containsKey("${imei}_mobile")) {
  //     return gen_caption(Text("${name}: ???", style: w),Colors.grey);
  //   }
  //
  //   String t = _data["${imei}_mobile"][getProvider(imei)][param];
  //   double? val = double.tryParse(t);
  //
  //   if (val == null) return gen_caption(Text("${name}: ${t}", style: w),Colors.grey);
  //   if (val > 20) return gen_caption(Text("${name}: ${t}", style: w),Colors.green);
  //   if (val > 13) return gen_caption(Text("${name}: ${t}", style: w),Colors.yellow);
  //   if (val > 0) return gen_caption(Text("${name}: ${t}", style: w),Colors.amber);
  //   return gen_caption(Text("${name}: ${t}", style: w),Colors.red);
  // }


  ///Определяет каким цветом отображать роутер
  Color getColor(String imei) {
    if (!_data.containsKey("${imei}_mobile")) {
      return Colors.grey;
    }

    if (_data.containsKey("${imei}_time")) {
      DateTime d = _data["${imei}_time"];
      if (DateTime.now().difference(d).inSeconds>62) {
        return Colors.blue;
      }
    }

    var d = _data["${imei}_mobile"][getProvider(imei)];

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

    if (rsrp == null || rsrq == null || rssi == null || snr == null) {
      return Colors.grey;
    }

    double rsrpQ = 0;
    if (rsrp > -100) rsrpQ = 1;
    if (rsrp > -90) rsrpQ = 2;
    if (rsrp > -80) rsrpQ = 3;

    double rsrqQ = 0;
    if (rsrq > -20) rsrqQ = 1;
    if (rsrq > -15) rsrqQ = 2;
    if (rsrq > -10) rsrqQ = 3;

    double rssiQ = 0;
    if (rssi > -95) rssiQ = 1;
    if (rssi > -85) rssiQ = 2;
    if (rssi > -65) rssiQ = 3;

    double snrQ = 0;
    if (snr > 0) snrQ = 1;
    if (snr > 13) snrQ = 2;
    if (snr > 20) snrQ = 3;

    double avg = (rsrpQ + rsrqQ + rssiQ + snrQ) / 4;

    Color res = Colors.red;
    if (avg >= 0.7) res = Colors.amber;
    if (avg >= 1.7) res = Colors.cyan;
    if (avg >= 2.7) res = Colors.green;

    return res;
  }

  ///Отображает роутер
  Widget nodeWidget(Node node) {
    Color col = getColor(node.key?.value);
    return Stack(
      children: [
        Center(
            child: Column(
          children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(color: Colors.blue, spreadRadius: 1),
            ],
          ),
          child: Text(
            getProvider(node.key?.value),
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
                      if (getColor(node.key?.value)!=Colors.grey)
                        _selectedImei = node.key?.value;
                    },
                    child:
                        col==Colors.red ? const Image(
                            image: AssetImage('assets/images/router_red.png'))
                        : col==Colors.amber ? const Image(
                            image: AssetImage('assets/images/router_amber.png'))
                        : col==Colors.blue ? const Image(
                            image: AssetImage('assets/images/router_blue.png'))
                        : col==Colors.green ? const Image(
                            image: AssetImage('assets/images/router_green.png'))
                        : col==Colors.cyan ? const Image(
                            image: AssetImage('assets/images/router_darkcyan.png'))
                        : const Image(
                            image: AssetImage('assets/images/router_gray.png'))
                )
              ],
            )),
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
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
        )),
      ],
    );
  }

  ///Функция для подстановки данных в алгоритм
  dynamic get_data() {
    return _data;
  }

  /// The successful connect callback
  void onConnected() {
    print("onConnected");
    //Подпишемся на прием данных от тпиков
    _mqttClient.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      final recMess = c![0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);

      //print('topic is <${c[0].topic}>, payload is <-- $pt -->');

      String topic = c[0].topic as String;
      List<String> parts = topic.split("/");
      if (parts.isNotEmpty && parts[0] == 'HOW') {
        String imei = parts[1];
        setState(() {
          if (topic.startsWith("HOW/${imei}/monitoring/mobile")) {
            if (pt != '{"":}') {
              _data["${imei}_mobile"] = jsonDecode(pt);
              _data["${imei}_time"] = DateTime.now();
            }
          }

          if (topic.startsWith("HOW/$imei/monitoring/wireless")) {
            _data["${imei}_wireless"] = jsonDecode(pt);
            _data["mac_${_data["${imei}_wireless"].keys.toList().first}"] = imei;
            _data["${imei}_time"] = DateTime.now();
          }

          var newEds = [];
          for (Node node in _graph.nodes) {
            String curImei = node.key?.value;
            if (_data.containsKey("${curImei}_wireless")) {
              var wireless = _data["${curImei}_wireless"];
              var wData =
                  wireless[wireless.keys.toList().first]['results'].toList();
              for (var wEl in wData) {
                String mac = wEl['mac'].toString().toLowerCase();

                String signal = wEl['signal'].toString().toLowerCase();
                String noise = wEl['noise'].toString().toLowerCase();

                double? sig = double.tryParse(signal);
                Color lineCol = Colors.red;
                if (sig!=null) {
                  if (sig > -100) lineCol = Colors.amber;
                  if (sig > -90) lineCol = Colors.yellow;
                  if (sig > -80) lineCol = Colors.green;
                }

                Paint linePaint = Paint()..color = lineCol..strokeWidth=1;

                if (_data.containsKey("mac_${mac}")) {
                  String conImei = _data["mac_${mac}"];
                  Node conn = _graph.getNodeUsingId(conImei);
                  Edge ed1 = Edge(node, conn, paint: linePaint);
                  Edge ed2 = Edge(conn, node, paint: linePaint);
                  if (!newEds.contains(ed1)) newEds.add(ed1);
                  if (!newEds.contains(ed2)) newEds.add(ed2);
                }
              }
            }
          }

          for (Edge ed in _graph.edges) {
            if (!newEds.contains(ed)) _graph.edges.remove(ed);
          }

          for (Edge ed in newEds) {
            Edge edd = Edge(ed.destination, ed.source, paint: ed.paint);

            if (!_graph.edges.contains(ed) &&
                !_graph.edges.contains(edd)) {
              _graph.edges.add(edd);
              print("-- ${edd.source.key!.value} -> ${edd.destination.key!.value} --");
            }
          }
        });
      }
    });

    //Оповестим, что мы подключились к серверу
    setState(() {
      _mqttIsConnected = true;
    });

  }

  /// Pong callback
  void pong() {}

  void onSubscribed(String topic) {}

  ///Запускает подключение к серверу
  Future<void> startMQTTConnect() async {
    print("startMQTTConnect");
    while(true) {
      await Future.delayed(const Duration(seconds: 1));
      if (kIsWeb) {
        _mqttClient = MqttBrowserClient('wss://mqtt.hpn.kz', Guid.newGuid.toString());
        _mqttClient.port = 8083;
        //_mqttClient.autoReconnect = true;
      } else {
        _mqttClient = MqttServerClient('mqtt.hpn.kz', '');
        _mqttClient.autoReconnect = true;
      }


      _mqttClient.setProtocolV311();
      _mqttClient.keepAlivePeriod = 5;
      _mqttClient.onDisconnected = onDisconnected;
      _mqttClient.onConnected = onConnected;
      _mqttClient.onSubscribed = onSubscribed;
      _mqttClient.pongCallback = pong;
      final connMess = MqttConnectMessage()
          .withClientIdentifier(Guid.newGuid.toString())
          .startClean(); // Non persistent session for testing

      _mqttClient.connectionMessage = connMess;
      try {
        await _mqttClient.connect("IoT", "wrtPhd82");
      } on NoConnectionException catch (e) {
        // Raised by the client when connection fails.
        //_mqttClient.disconnect();
        continue;
      } on SocketException catch (e) {
        // Raised by the socket layer
        //_mqttClient.disconnect();
        continue;
      }

      /// Check we are connected
      if (_mqttClient.connectionStatus!.state != MqttConnectionState.connected) {
        //_mqttClient.disconnect();
        continue;
      }

      break;

      // setState(() {
      //   _mqttIsConnected = true;
      //   _is_subscribed = false;
      //   _has_data = false;
      // });
    }
    print("startMQTTConnect end");
  }

  ///Вызывается при отключении от сервера
  void onDisconnected() {
    print("onDisconnected");
    setState(() {
      _mqttIsConnected = false;
      startMQTTConnect();
    });
  }


  ///Запрашивает список связанных IMEI и подписывается на топики
  Future<void> getListIMEIs() async {
    var url =
        Uri.parse('https://how.hpn.kz:8002/v1.0/device/imei/${getImei(_barcode)}');
    var response = await http.get(url);
    if (response.statusCode != 200) {
      return;
    }

    _graph.nodes.clear();

    for (var el in json.decode(response.body)) {
      _graph.addNode(Node.Id(el));
      mqtt_subscribe('HOW/$el/monitoring/mobile');
      mqtt_subscribe('HOW/$el/monitoring/wireless');
    }

    if (_graph.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('IMEI не найден в базе!'),
      ));
      setState(() {
        _barcode = "";
        _selectedImei = "";
        _data = <String, dynamic>{};
        _graph.edges.clear();
        _graph.nodes.clear();
        _mqttClient.disconnect();
      });
    }
  }

  @override
  initState() {
    super.initState();

    startMQTTConnect();

    //Раз в секунду проверяем что соединение не протухло
    Timer.periodic(const Duration(seconds: 1), (Timer t) {
      int min_dif = 1000000;
      if (_data.keys.isNotEmpty) {
        for (var key in _data.keys) {
          if (key.endsWith("_time")) {
            DateTime d = _data[key];
            int dif = DateTime
                .now()
                .difference(d)
                .inSeconds;

            min_dif = dif<min_dif?dif:min_dif;

            if (dif > 120) {
              var imei = key.split("_")[0];
              if (_data.containsKey("${imei}_mobile")) {
                _data.remove("${imei}_mobile");
              }
              if (_data.containsKey("${imei}_wireless")) {
                _data.remove("${imei}_wireless");
              }
              if (_data.containsKey("${imei}_time")) {
                _data.remove("${imei}_time");
              }
              break;
            }
          }
        }
        if (min_dif>61) {
          setState(() {
            _mqttIsConnected = false;
          });
        }
      }

    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          leading: _barcode!="" ? IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (_selectedImei!="") {
                _selectedImei = "";
              } else {
                setState(() {
                  _barcode = "";
                  _selectedImei = "";
                  _data = <String, dynamic>{};
                  _graph.edges.clear();
                  _graph.nodes.clear();
                  _mqttClient.disconnect();
                });
              }
            },
          ):const SizedBox(),
          title: Text(widget.title),
        ),
        body: !_mqttIsConnected ? mqttConnecting()
            : !_barcode.startsWith("IMEI:") && !_barcode.startsWith("https://how.hpn.kz/info/?")
                ? needScanQR()
                : showData());
  }

  // void checkInternetState() async {
  //   var connectivityResult = await (Connectivity().checkConnectivity());
  //   if (connectivityResult != ConnectivityResult.none) {
  //     if (!_internetIsConnected) {
  //       _internetIsConnected = true;
  //       //startMQTTConnect();
  //     }
  //   }
  // }


}

///Это нужно для того чтобы https сертификаты нормально работали
class MyHttpOverrides extends HttpOverrides{
  @override
  HttpClient createHttpClient(SecurityContext? context){
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port)=> true;
  }
}
