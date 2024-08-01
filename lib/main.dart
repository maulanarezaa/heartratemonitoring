import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:math';
import 'dart:async';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: DeviceScanScreen(),
    );
  }
}

class DeviceScanScreen extends StatefulWidget {
  @override
  _DeviceScanScreenState createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  List<ScanResult> scanResults = [];

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() {
    setState(() {
      scanResults.clear();
    });
    FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
    FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        scanResults = results;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Select Heart Rate Device'),
      ),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (context, index) {
          final result = scanResults[index];
          return ListTile(
            title: Text(result.device.name.isEmpty
                ? 'Unknown device'
                : result.device.name),
            subtitle: Text(result.device.id.toString()),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => HeartRateMonitor(device: result.device),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.refresh),
        onPressed: startScan,
      ),
    );
  }
}

class HeartRateMonitor extends StatefulWidget {
  final BluetoothDevice device;

  HeartRateMonitor({required this.device});

  @override
  _HeartRateMonitorState createState() => _HeartRateMonitorState();
}

class _HeartRateMonitorState extends State<HeartRateMonitor> {
  List<BluetoothService> services = [];
  bool isConnected = false;
  int heartRate = 0;
  List<int> rrIntervals = [];
  double totalRrInterval = 0.0;
  int rrIntervalCount = 0;
  double sdnn = 0.0;
  double rmssd = 0.0;
  double pnn50 = 0.0;
  double averageRrInterval = 0.0;
  Timer? timer;
  int countdown = 60;
  List<int> bpmList = [];
  double averageBpm = 0.0;
  double averageSdnn = 0.0;
  double averageRmssd = 0.0;
  double averagePnn50 = 0.0;
  double averagerr = 0.0;
  BluetoothCharacteristic? hrCharacteristic;

  @override
  void initState() {
    super.initState();
    connectToDevice();
  }

  void connectToDevice() async {
    try {
      await widget.device.connect();
      setState(() {
        isConnected = true;
      });
      discoverServices();
    } catch (e) {
      print('Failed to connect: $e');
    }
  }

  void discoverServices() async {
    List<BluetoothService> discoveredServices = await widget.device.discoverServices();
    setState(() {
      services = discoveredServices;
    });
  }

  void subscribeToCharacteristic(BluetoothCharacteristic characteristic) async {
    try {
      await characteristic.setNotifyValue(true);
      characteristic.value.listen((value) {
        if (value.isNotEmpty) {
          setState(() {
            heartRate = value[1];
            bpmList.add(heartRate);
          });

          if (value.length > 2) {
            int rr = value[2] | (value[3] << 8);
            double rrMs = rr * 0.625;
            rrIntervals.add(rrMs.toInt());
            if (rrIntervals.length > 1) {
              calculateMetrics();
            }
          }
        }
      });

      // Start countdown
      startCountdown();
    } catch (e) {
      print('Error subscribing to characteristic: $e');
    }
  }

  void startCountdown() {
    timer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        countdown--;
        if (countdown <= 0) {
          timer.cancel();
          calculateAverages();
        }
      });
    });
  }

  void calculateMetrics() {
    if (rrIntervals.isEmpty) {
      return;
    }
    totalRrInterval += rrIntervals.last;
    rrIntervalCount++;


    double mean = rrIntervals.reduce((a, b) => a + b).toDouble() / rrIntervals.length;

    // Calculate SDNN
    double sumSquaredDiff = rrIntervals
        .map((interval) => pow(interval - mean, 2))
        .reduce((a, b) => a + b)
        .toDouble();
    sdnn = sqrt(sumSquaredDiff / rrIntervals.length);

    // Calculate rMSSD
    List<double> successiveDifferences = [];
    for (int i = 1; i < rrIntervals.length; i++) {
      double diff = rrIntervals[i].toDouble() - rrIntervals[i - 1].toDouble();
      successiveDifferences.add(diff);
    }
    double sumSquaredDiffs = successiveDifferences
        .map((diff) => pow(diff, 2))
        .reduce((a, b) => a + b)
        .toDouble();
    rmssd = sqrt(sumSquaredDiffs / successiveDifferences.length);

    // Calculate pNN50
    int countNN50 = successiveDifferences.where((diff) => diff.abs() > 50).length;
    pnn50 = (countNN50 / successiveDifferences.length) * 100;

    // Calculate average RR interval
    averageRrInterval = rrIntervals.isNotEmpty
        ? rrIntervals.reduce((a, b) => a + b).toDouble() / rrIntervals.length
        : 0.0;

    setState(() {
      sdnn = sdnn;
      rmssd = rmssd;
      pnn50 = pnn50;
      averageRrInterval = averageRrInterval;
    });
  }

  void calculateAverages() {
    if (bpmList.isNotEmpty) {
      averageBpm = bpmList.reduce((a, b) => a + b).toDouble() / bpmList.length;
    }
    if (rrIntervals.isNotEmpty) {
      averageSdnn = sdnn;
      averageRmssd = rmssd;
      averagePnn50 = pnn50;
      averageRrInterval = totalRrInterval / rrIntervalCount;
      averagerr = totalRrInterval/rrIntervalCount;
    }

    setState(() {
      averageBpm = averageBpm;
      averageSdnn = averageSdnn;
      averageRmssd = averageRmssd;
      averagePnn50 = averagePnn50;
      averageRrInterval = averageRrInterval;
      averagerr = averagerr;
      // averageRrInterval = rrIntervals.isNotEmpty
      //     ? rrIntervals.reduce((a, b) => a + b).toDouble() / rrIntervals.length
      //     : 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Heart Rate Monitor'),
      ),
      body: isConnected
          ? SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 20),
                  Text(
                    'Heart Rate:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '$heartRate BPM',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Interval R-R:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${rrIntervals.isNotEmpty ? rrIntervals.last.toStringAsFixed(2) : 'N/A'} ms',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'SDNN:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${sdnn.toStringAsFixed(2)} ms',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'rMSSD:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${rmssd.toStringAsFixed(2)} ms',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'pNN50:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${pnn50.toStringAsFixed(2)} %',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Countdown: $countdown seconds',
                    style: TextStyle(fontSize: 24),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Average Heart Rate:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${averageBpm.toStringAsFixed(2)} BPM',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
      Text(
        'Average RR Interval:',
        style: TextStyle(fontSize: 24),
      ),
      Text(
        '${averagerr.toStringAsFixed(2)} ms',
        style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
      ),
                  SizedBox(height: 20),
                  Text(
                    'Average SDNN:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${averageSdnn.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Average rMSSD:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${averageRmssd.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  Text(
                    'Average pNN50:',
                    style: TextStyle(fontSize: 24),
                  ),
                  Text(
                    '${averagePnn50.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 20),
                  // Display services and characteristics
                  Column(
                    children: services.map((service) {
                      return ExpansionTile(
                        title: Text('Service: ${service.uuid}'),
                        children: service.characteristics.map((characteristic) {
                          return ListTile(
                          title: Text('Characteristic: ${characteristic.uuid.toString()}'),
                          subtitle: Row(
                            children: [
                              characteristic.properties.read
                                  ? ElevatedButton(
                                      onPressed: () async {
                                        try {
                                          var value = await characteristic.read();
                                          print('Read value: $value');
                                        } catch (e) {
                                          print('Error reading characteristic: $e');
                                        }
                                      },
                                      child: Text('Read'),
                                    )
                                  : Container(),
                              characteristic.properties.write
                                  ? ElevatedButton(
                                      onPressed: () {
                                        // Handle write
                                      },
                                      child: Text('Write'),
                                    )
                                  : Container(),
                              characteristic.properties.notify
                                  ? ElevatedButton(
                                      onPressed: () {
                                        subscribeToCharacteristic(characteristic);
                                      },
                                      child: Text('Notify'),
                                    )
                                  : Container(),
                            ],
                          ),
                          onTap: () {
                            if (characteristic.uuid.toString() == '00002A37-0000-1000-8000-00805F9B34FB') {
                              subscribeToCharacteristic(characteristic);
                            }
                          },
                        );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ],
              ),
            )
          : Center(
              child: CircularProgressIndicator(),
            ),
    );
  }

  @override
  void dispose() {
    widget.device.disconnect();
    timer?.cancel();
    super.dispose();
  }
}
