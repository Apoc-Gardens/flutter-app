import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import '../models/receiver.dart';
import '../services/database_service.dart';
import 'package:mybluetoothapp/models/node.dart';

class SyncCard extends StatefulWidget {
  const SyncCard({super.key});

  @override
  State<SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<SyncCard> {
  DatabaseHelper databaseHelper = DatabaseHelper();
  late Receiver receiverDevice;
  late BluetoothDevice bluetoothDevice;
  int lastSync = 0;
  bool isConnected = false;

  @override
  void initState() {
    super.initState();
    getDevices();
  }

  Future<void> getDevices() async {
    List<Receiver> devices = await databaseHelper.getAllDevices();
    receiverDevice = devices[0];
    lastSync = receiverDevice.lastSynced ?? 0;
    print(
        'ID: ${receiverDevice.id}, Name: ${receiverDevice.name}, MAC: ${receiverDevice.mac}, LastSync: ${receiverDevice.lastSynced}');
    scanForDevice(receiverDevice.mac);
  }

  void scanForDevice(String MAC) {
    FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        if (result.device.remoteId.toString() == receiverDevice.mac) {
          FlutterBluePlus.stopScan();
          bluetoothDevice = result.device;
          setState(() async {
            await bluetoothDevice.connect();
            setState(() {
              isConnected = true;
            });
            print("Devices connected");
          });
        }
      }
    });
    FlutterBluePlus.startScan(
        withServices: [Guid('8292fed4-e037-4dd7-b0c8-c8d7c80feaae')],
        timeout: const Duration(seconds: 10));
  }

  Future<BluetoothCharacteristic?> getCharacteristic(
      BluetoothDevice bluetoothDevice,
      Guid serviceUuid,
      Guid characteristicUuid) async {
    List<BluetoothService> services = await bluetoothDevice.discoverServices();

    for (BluetoothService service in services) {
      if (service.uuid == serviceUuid) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid == characteristicUuid) {
            return characteristic;
          }
        }
      }
    }
    return null;
  }

  Future<void> syncData(BluetoothDevice bluetoothDevice) async {
    // Find the desired service and characteristic
    final serviceUuid = Guid("8292fed4-e037-4dd7-b0c8-c8d7c80feaae");
    final characteristicUuid = Guid("870e104f-ba63-4de3-a3ac-106969eac292");
    List<String> sensorData = [];
    List<String> elements = []; //
    List<List<String>> listOfElements = [];
    List<BluetoothService> services = await bluetoothDevice.discoverServices();
    BluetoothCharacteristic? selectedCharacteristic;

    String asciiValues(List<int> value) {
      String hexString =
          value.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
      List<int> asciiList =
          hexString.split(' ').map((e) => int.parse(e, radix: 16)).toList();
      return asciiList.map((e) => String.fromCharCode(e)).join('');
    }

    if (bluetoothDevice.isConnected) {
      for (BluetoothService service in services) {
        if (service.uuid == serviceUuid) {
          for (BluetoothCharacteristic characteristic
              in service.characteristics) {
            if (characteristic.uuid == characteristicUuid) {
              selectedCharacteristic = characteristic;
            }
          }
        }
      }

      if (selectedCharacteristic != null) {
        String asciiString = asciiValues(await selectedCharacteristic.read());
        print(asciiString);
        if (asciiString == "ok") {
          while (asciiString != "end") {
            asciiString = asciiValues(await selectedCharacteristic.read());
            if (asciiString != "end") {
              elements = asciiString.split(",");
              listOfElements.add(elements);
              sensorData.add(asciiString);
            }
          }
          print("data to be saved");
          for (List<String> element in listOfElements) {
            print(
                "Id: ${element[0]}, battery: ${element[1]}, Temp: ${element[2]}, Hum: ${element[3]}, Lux : ${element[4]}");
            List<Map<String, dynamic>> nodeToBeInserted =
                await databaseHelper.getNodeById(element[0]);
            if (nodeToBeInserted.isEmpty) {
              Node newNode = Node(
                  id: -1,
                  nid: element[0],
                  name: 'new node',
                  description: null);
              int newNodeId = await databaseHelper.insertNode(newNode);
              nodeToBeInserted = [
                {'id': newNodeId}
              ];
              print("saving new node");
            }
            int nodeId = nodeToBeInserted[0]['id'] as int;

            double temp = double.tryParse(element[2]) ?? 0.0;
            double hum = double.tryParse(element[3]) ?? 0.0;
            double lux = double.tryParse(element[4]) ?? 0.0;
            double soil = double.tryParse(element[5]) ?? 0.0;

            await databaseHelper.insertData(
                nodeId,
                1,
                temp,
                DateTime.now()
                    .millisecondsSinceEpoch); //ToDo: change this insert the timestamp received from the receiver module
            await databaseHelper.insertData(
                nodeId, 2, hum, DateTime.now().millisecondsSinceEpoch);
            await databaseHelper.insertData(
                nodeId, 3, lux, DateTime.now().millisecondsSinceEpoch);
            await databaseHelper.insertData(
                nodeId, 4, soil, DateTime.now().millisecondsSinceEpoch);
            await databaseHelper.updateLastSync(
                receiverDevice.id ?? 1, DateTime.now().millisecondsSinceEpoch);
            setState(() {
              lastSync = DateTime.now().millisecondsSinceEpoch;
            });
            print("data inserted");
          }
        } else {
          print(
              "cannot read data file"); //ToDo: add a toast here to inform user
        }
      } else {
        print("error"); //ToDo: add a toast here to inform user
      }
    } else {
      setState(() {
        isConnected = false;
      });
      scanForDevice(receiverDevice.mac); //print if connected
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.0), // Border radius
        side: const BorderSide(
          color: Color(0xFFE4E4E4), // Border color
          width: 1.0, // Border thickness
        ),
      ),
      child: Container(
        color: const Color(0xFFCDE8DD),
        padding: const EdgeInsets.all(16.0), // Padding
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Receiver',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            if (isConnected)
                              const Padding(
                                padding: EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  Icons.circle,
                                  color: Colors.green,
                                  size: 10,
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.only(left: 8.0),
                                child: Icon(
                                  Icons.circle,
                                  color: Colors.red,
                                  size: 10,
                                ),
                              )
                          ],
                        ),
                        Text(
                          'last sync: ${DateFormat('HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(lastSync))}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.normal,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () {
                    if (isConnected) {
                      // if connected
                      syncData(bluetoothDevice);
                    } else {
                      // if not connected
                      scanForDevice(receiverDevice.mac);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0AA061),
                    side:
                        const BorderSide(color: Color(0xFF0AA061), width: 1.0),
                    // Outline color and thickness
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4.0), // Border radius
                    ),
                    padding: const EdgeInsets.all(6.0), // Padding
                  ),
                  child: Text(isConnected ? 'Sync Data' : 'Connect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
