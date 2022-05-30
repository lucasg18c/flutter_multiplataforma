import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:awesome_notifications/awesome_notifications.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:rxdart/subjects.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:hex/hex.dart';

import 'package:permission_handler/permission_handler.dart';

import 'dart:developer';

const pagina = '''
<!DOCTYPE html>
<html lang="en">
<head>
    <title>Document</title>
</head>
<body>
    <h1>Probando marquito en Flutter</h1>

    <p>Tocá el botón para usar la luz LED del celular</p>

    <input type="button" value="saludar" onclick="window.flutter_inappwebview.callHandler('led')">
    
</body>
</html>
''';

var ledPrendida = false;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Streams are created so that app can respond to notification-related events
/// since the plugin is initialised in the `main` function
final BehaviorSubject<ReceivedNotification> didReceiveLocalNotificationSubject =
    BehaviorSubject<ReceivedNotification>();

final BehaviorSubject<String?> selectNotificationSubject =
    BehaviorSubject<String?>();

const MethodChannel platform = MethodChannel('cg/ejemplo_notificacion');
// MethodChannel('dexterx.dev/flutter_local_notifications_example');

class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

String? selectedNotificationPayload;

final flutterReactiveBle = FlutterReactiveBle();

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Permission.bluetooth.request();
  await Permission.location.request();

  if (Platform.isAndroid) {
    await AndroidInAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  // Inicialización de notificaciones
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
// initialise the plugin. app_icon needs to be a added as a drawable resource to the Android head project
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  final IOSInitializationSettings initializationSettingsIOS =
      IOSInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          onDidReceiveLocalNotification: (
            int id,
            String? title,
            String? body,
            String? payload,
          ) async {
            didReceiveLocalNotificationSubject.add(
              ReceivedNotification(
                id: id,
                title: title,
                body: body,
                payload: payload,
              ),
            );
          });

  final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid, iOS: initializationSettingsIOS);

  await flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onSelectNotification: (String? payload) async {
    if (payload != null) {
      debugPrint('notification payload: $payload');
    }
    selectedNotificationPayload = payload;
    selectNotificationSubject.add(payload);
  });

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  late InAppWebViewController _webViewController;
  List<DiscoveredDevice> devices = <DiscoveredDevice>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
          body: SafeArea(
        child: InAppWebView(
            initialData: InAppWebViewInitialData(data: "cargando..."),
            // initialUrlRequest: URLRequest(
            //     url: Uri.parse(
            //         "http://172.16.17.116:50719/Access/Landing.aspx")),
            onWebViewCreated: (InAppWebViewController controller) {
              _webViewController = controller;
              _webViewController.setOptions(
                  options: InAppWebViewGroupOptions(
                      crossPlatform: InAppWebViewOptions(supportZoom: false)));
              _webViewController.loadFile(
                  assetFilePath: "assets/testPage.html");
              _webViewController.addJavaScriptHandler(
                  handlerName: "led",
                  callback: (datos) async {
                    try {
                      final ledDisponible = await TorchLight.isTorchAvailable();
                      if (ledDisponible) {
                        ledPrendida = !ledPrendida;
                        if (ledPrendida) {
                          await TorchLight.enableTorch();
                        } else {
                          TorchLight.disableTorch();
                        }
                      }
                    } on Exception catch (_) {}
                  });
              _webViewController.addJavaScriptHandler(
                  handlerName: "push1",
                  callback: (datos) async {
                    const AndroidNotificationDetails
                        androidPlatformChannelSpecifics =
                        AndroidNotificationDetails(
                            'id_canal_cg', 'Notificación de prueba',
                            channelDescription:
                                'Acá aparecen notificaciones de prueba',
                            importance: Importance.max,
                            priority: Priority.max,
                            ticker: 'ticker');
                    const NotificationDetails platformChannelSpecifics =
                        NotificationDetails(
                            android: androidPlatformChannelSpecifics);
                    // await Future.delayed(const Duration(seconds: 5));
                    await flutterLocalNotificationsPlugin.show(
                        0,
                        'Buen día! 😁',
                        datos[0]["mensaje"],
                        platformChannelSpecifics,
                        payload: 'item x');
                  });
              _webViewController.addJavaScriptHandler(
                  handlerName: "push2",
                  callback: (datos) async {
                    AwesomeNotifications().createNotification(
                        content: NotificationContent(
                            id: 10,
                            channelKey: 'cg_awesome_canal',
                            title: 'Awesome Notification',
                            body: datos[0]["mensaje"]));
                  });
              _webViewController.addJavaScriptHandler(
                  handlerName: "ble",
                  callback: (datos) async {
                    log("buscando BLE");
                    flutterReactiveBle
                        .scanForDevices(withServices: []).listen((device) {
                      //code for handling results

                      bool existe = false;
                      for (var i = 0; i < devices.length; i++) {
                        if (devices[i].id == device.id) {
                          existe = true;
                          break;
                        }
                      }

                      if (!existe) {
                        devices.add(device);
                      }

                      _webViewController.evaluateJavascript(
                          source:
                              "addDevice({mac: '${device.id}', uuid:${device.manufacturerData}, rssi: ${device.rssi}})");
                      //log("Dispositivo encontrado: $device");
                    });
                  });
              _webViewController.addJavaScriptHandler(
                  handlerName: "conectar",
                  callback: (datos) async {
                    var device = datos[0];

                    _webViewController.evaluateJavascript(
                        source:
                            "estadoConexion({mac: '${device["mac"]}', estado: 'intentando conectar...'})");

                    for (var i = 0; i < devices.length; i++) {
                      if (devices[i].id == device["mac"]) {
                        DiscoveredDevice vinculado = devices[i];

                        flutterReactiveBle
                            .connectToDevice(
                                id: vinculado.id,
                                connectionTimeout: const Duration(seconds: 5))
                            .listen((event) async {
                          _webViewController.evaluateJavascript(
                              source:
                                  "estadoConexion({mac: '${vinculado.id}', estado: '${event.connectionState.name}'})");

                          final characteristic = QualifiedCharacteristic(
                              serviceId: Uuid.parse(
                                  "6E40FE80B5A3F393A9E0E50E24CADC9E"),
                              characteristicId: Uuid.parse(
                                  "6E40FE81-B5A3-F393-A9E0-E50E24CADC9E"),
                              deviceId: vinculado.id);

                          flutterReactiveBle.subscribeToCharacteristic(characteristic).listen((datosCaracteristica) {
                            _webViewController.evaluateJavascript(
                                source:
                                "notify({mac: '${vinculado.id}', estado: '${HEX.encode(datosCaracteristica.toList())}'})");
                          });

                          await flutterReactiveBle
                              .writeCharacteristicWithResponse(characteristic,
                                  value:
                                      HEX.decode("01000800000201000F01031F")); //Gral Info
                          log("escribiendo en caracteristica");
                        }, onError: (error) {
                              log("Error: $error");
                          _webViewController.evaluateJavascript(
                              source:
                                  "estadoConexion({mac: '${vinculado.id}', estado: '${error.toString()}'})");
                        });

                        break;
                      }
                    }
                  });
            }),
      )),
    );
  }
}
