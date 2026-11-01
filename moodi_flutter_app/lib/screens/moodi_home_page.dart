
import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/moodi_emotion.dart';

class MoodiHomePage extends StatefulWidget {
  const MoodiHomePage({super.key});

  @override
  State<MoodiHomePage> createState() => _MoodiHomePageState();
}

class _MoodiHomePageState extends State<MoodiHomePage> {
  // ============================================================
  // 1. BLE UUID CONFIGURATION
  // ============================================================

  static final Uuid _serviceUuid = Uuid.parse(
    '12345678-1234-1234-1234-1234567890AB',
  );

  static final Uuid _emotionUuid = Uuid.parse(
    '12345678-1234-1234-1234-1234567890AC',
  );

  static final Uuid _timeUuid = Uuid.parse(
    '12345678-1234-1234-1234-1234567890AD',
  );


  // ============================================================
  // 2. BLE OBJECTS AND SUBSCRIPTIONS
  // ============================================================

  final FlutterReactiveBle _ble = FlutterReactiveBle();

  StreamSubscription<BleStatus>? _statusSubscription;

  StreamSubscription<DiscoveredDevice>? _scanSubscription;

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;

  Timer? _scanTimer;


  // ============================================================
  // 3. APPLICATION STATE
  // ============================================================

  bool _isScanning = false;

  bool _isConnecting = false;

  bool _isConnected = false;

  bool _isSending = false;

  String _statusMessage = 'MOODI is ready when you are.';

  String _deviceName = 'MOODI';

  String? _deviceId;

  MoodiEmotion _selectedEmotion = MoodiEmotion.neutral;

  MoodiEmotion? _lastSentEmotion;


  // ============================================================
  // 4. INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();

    _statusSubscription = _ble.statusStream.listen((status) {

      if (!mounted) return;

      if (status != BleStatus.ready &&
          !_isConnected &&
          !_isScanning) {

        setState(() {
          _statusMessage = _bleStatusMessage(status);
        });

      }

    });

  }


  // ============================================================
  // 5. BLUETOOTH STATUS MESSAGES
  // ============================================================

  String _bleStatusMessage(BleStatus status) {

    switch (status) {

      case BleStatus.ready:
        return 'Bluetooth is ready.';

      case BleStatus.poweredOff:
        return 'Turn on Bluetooth on your phone.';

      case BleStatus.unauthorized:
        return 'Bluetooth permission is not granted.';

      case BleStatus.locationServicesDisabled:
        return 'Location services are disabled. Check Android Bluetooth settings.';

      case BleStatus.unsupported:
        return 'This phone does not support Bluetooth Low Energy.';

      case BleStatus.unknown:
        return 'Checking Bluetooth availability…';

    }

  }


  // ============================================================
  // 6. REQUEST BLUETOOTH PERMISSIONS
  // ============================================================

  Future<bool> _requestBluetoothPermissions() async {

    final androidInfo = await DeviceInfoPlugin().androidInfo;

    final int sdkInt = androidInfo.version.sdkInt;


    if (sdkInt >= 31) {

      final statuses = await <Permission>[
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      return statuses.values.every(
        (status) => status.isGranted,
      );

    }


    // Android 11 and below require location permission for BLE scanning.
    // MOODI does not read or transmit the phone's location.

    final status = await Permission.locationWhenInUse.request();

    return status.isGranted;

  }


  // ============================================================
  // 7. START BLE SCANNING
  // ============================================================

  Future<void> _startScan() async {

    if (_isScanning || _isConnecting || _isConnected) return;


    setState(() {

      _isScanning = true;

      _statusMessage = 'Asking for Bluetooth permission…';

      _lastSentEmotion = null;

    });


    try {

      final permissionsGranted =
          await _requestBluetoothPermissions();

      if (!mounted) return;


      if (!permissionsGranted) {

        setState(() {

          _isScanning = false;

          _statusMessage =
              'Bluetooth permission is needed. Allow it in Android app settings and try again.';

        });

        return;

      }


      // Check Bluetooth readiness.

      if (_ble.status != BleStatus.ready) {

        setState(() {

          _statusMessage = _bleStatusMessage(_ble.status);

        });


        final readyStatus = await _ble.statusStream
            .firstWhere(
              (status) => status == BleStatus.ready,
            )
            .timeout(
              const Duration(seconds: 8),
              onTimeout: () => _ble.status,
            );


        if (!mounted) return;


        if (readyStatus != BleStatus.ready) {

          setState(() {

            _isScanning = false;

            _statusMessage = _bleStatusMessage(readyStatus);

          });

          return;

        }

      }


      setState(() {

        _statusMessage = 'Looking for MOODI nearby…';

      });


      // Scan using the existing MOODI service UUID.

      _scanSubscription = _ble
          .scanForDevices(
            withServices: <Uuid>[_serviceUuid],
            scanMode: ScanMode.lowLatency,
            requireLocationServicesEnabled: false,
          )
          .listen(

        (device) async {

          if (!_isScanning ||
              _isConnecting ||
              _isConnected) return;


          await _stopScan(updateUi: false);

          if (!mounted) return;


          await _connectToDevice(device);

        },


        onError: (Object error) {

          _scanTimer?.cancel();

          if (!mounted) return;


          setState(() {

            _isScanning = false;

            _statusMessage = 'Scan failed: $error';

          });

        },

      );


      // Scan timeout.

      _scanTimer?.cancel();

      _scanTimer = Timer(
        const Duration(seconds: 15),
        () async {

          await _stopScan(updateUi: false);

          if (!mounted ||
              _isConnected ||
              _isConnecting) return;


          setState(() {

            _statusMessage =
                'MOODI was not found. Check that it is powered on and advertising.';

          });

        },
      );

    }


    catch (error) {

      if (!mounted) return;


      setState(() {

        _isScanning = false;

        _statusMessage = 'Could not start Bluetooth: $error';

      });

    }

  }


  // ============================================================
  // 8. STOP BLE SCANNING
  // ============================================================

  Future<void> _stopScan({bool updateUi = true}) async {

    _scanTimer?.cancel();

    _scanTimer = null;


    await _scanSubscription?.cancel();

    _scanSubscription = null;


    if (updateUi && mounted) {

      setState(() => _isScanning = false);

    }

    else {

      _isScanning = false;

    }

  }


  // ============================================================
  // 9. CONNECT TO MOODI
  // ============================================================

  Future<void> _connectToDevice(
    DiscoveredDevice device,
  ) async {

    if (!mounted) return;


    setState(() {

      _isConnecting = true;

      _statusMessage =
          'Connecting to ${device.name.isEmpty ? 'MOODI' : device.name}…';

      _deviceName =
          device.name.isEmpty ? 'MOODI' : device.name;

      _deviceId = device.id;

    });


    await _connectionSubscription?.cancel();


    _connectionSubscription = _ble
        .connectToDevice(

          id: device.id,

          // Discover BOTH BLE characteristics.
          servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{

            _serviceUuid: <Uuid>[

              _emotionUuid,

              _timeUuid,

            ],

          },

          connectionTimeout: const Duration(seconds: 12),

        )

        .listen(

      (update) {

        if (!mounted) return;


        // ------------------------------------------------------
        // CONNECTED
        // ------------------------------------------------------

        if (update.connectionState ==
            DeviceConnectionState.connected) {


          setState(() {

            _isConnecting = false;

            _isConnected = true;

            _statusMessage =
                'Connected. Synchronizing time...';

          });


          // Automatically send phone time.
          unawaited(
            _syncTimeToDevice(device.id),
          );

        }


        // ------------------------------------------------------
        // CONNECTING
        // ------------------------------------------------------

        else if (update.connectionState ==
            DeviceConnectionState.connecting) {


          setState(() {

            _isConnecting = true;

            _isConnected = false;

            _statusMessage =
                'Connecting to $_deviceName…';

          });

        }


        // ------------------------------------------------------
        // DISCONNECTED
        // ------------------------------------------------------

        else if (update.connectionState ==
            DeviceConnectionState.disconnected) {


          setState(() {

            _isConnecting = false;

            _isConnected = false;

            _isSending = false;

            _deviceId = null;

            _statusMessage =
                'Disconnected from MOODI. Tap Connect to retry.';

          });

        }

      },


      onError: (Object error) {

        if (!mounted) return;


        setState(() {

          _isConnecting = false;

          _isConnected = false;

          _deviceId = null;

          _statusMessage = 'Connection failed: $error';

        });

      },

    );

  }


  // ============================================================
  // 10. DISCONNECT FROM MOODI
  // ============================================================

  Future<void> _disconnect() async {

    await _connectionSubscription?.cancel();

    _connectionSubscription = null;


    if (!mounted) return;


    setState(() {

      _isConnected = false;

      _isConnecting = false;

      _isSending = false;

      _deviceId = null;

      _statusMessage =
          'Disconnected. MOODI is safe and waiting.';

    });

  }


  // ============================================================
  // 11. AUTOMATIC PHONE TIME SYNCHRONIZATION
  // ============================================================

  Future<void> _syncTimeToDevice(
    String deviceId,
  ) async {


    if (!_isConnected ||
        _deviceId != deviceId ||
        _isSending) return;


    // Get phone's current local time.

    final DateTime now = DateTime.now();


    // Unix timestamp represents an absolute UTC instant.

    final int epochSeconds =
        now.toUtc().millisecondsSinceEpoch ~/ 1000;


    // Get phone timezone offset in minutes.
    // India = +330 minutes.

    final int timezoneOffsetMinutes =
        now.timeZoneOffset.inMinutes;


    // Construct the ESP32 command.
    // Example: 1793577600,330

    final String payload =
        '$epochSeconds,$timezoneOffsetMinutes';


    // Identify the new time characteristic.

    final characteristic = QualifiedCharacteristic(

      serviceId: _serviceUuid,

      characteristicId: _timeUuid,

      deviceId: deviceId,

    );


    setState(() {

      _isSending = true;

      _statusMessage =
          'Sending phone time to MOODI…';

    });


    try {


      // Send time through BLE with response.

      await _ble.writeCharacteristicWithResponse(

        characteristic,

        value: payload.codeUnits,

      );


      if (!mounted ||
          !_isConnected ||
          _deviceId != deviceId) return;


      setState(() {

        _statusMessage =
            'Connected. Time and date synchronized.';

      });


      debugPrint(
        'MOODI time payload sent: $payload',
      );

    }


    catch (error) {

      if (!mounted ||
          !_isConnected ||
          _deviceId != deviceId) return;


      setState(() {

        _statusMessage =
            'Connected, but time sync failed: $error';

      });


      debugPrint(
        'MOODI time sync failed: $error',
      );

    }


    finally {

      if (mounted) {

        setState(() {

          _isSending = false;

        });

      }

    }

  }


  // ============================================================
  // 12. SEND EMOTION COMMAND
  // ============================================================

  Future<void> _sendEmotion(
    MoodiEmotion emotion,
  ) async {


    final deviceId = _deviceId;


    if (!_isConnected ||
        deviceId == null ||
        _isSending) return;


    final characteristic = QualifiedCharacteristic(

      serviceId: _serviceUuid,

      characteristicId: _emotionUuid,

      deviceId: deviceId,

    );


    setState(() {

      _isSending = true;

      _statusMessage =
          'Sending ${emotion.label.toLowerCase()}…';

    });


    try {


      // Send the existing emotion command.

      await _ble.writeCharacteristicWithResponse(

        characteristic,

        value: encodeEmotionCommand(emotion),

      );


      if (!mounted) return;


      setState(() {

        _selectedEmotion = emotion;

        _lastSentEmotion = emotion;

        _statusMessage =
            'MOODI is feeling ${emotion.label.toLowerCase()}.';

      });

    }


    catch (error) {

      if (!mounted) return;


      setState(() {

        _statusMessage =
            'Could not send the emotion: $error';

      });

    }


    finally {

      if (mounted) {

        setState(() => _isSending = false);

      }

    }

  }


  // ============================================================
  // 13. CLEANUP
  // ============================================================

  Future<void> _disposeBleResources() async {

    await _scanSubscription?.cancel();

    await _connectionSubscription?.cancel();

    await _statusSubscription?.cancel();

    await _ble.deinitialize();

  }


  @override
  void dispose() {

    _scanTimer?.cancel();

    unawaited(_disposeBleResources());

    super.dispose();

  }


  // ============================================================
  // 14. MAIN UI
  // ============================================================

  @override
  Widget build(BuildContext context) {

    final bool busy =
        _isScanning || _isConnecting;


    return Scaffold(

      body: SafeArea(

        child: SingleChildScrollView(

          padding: const EdgeInsets.fromLTRB(
            20, 18, 20, 28,
          ),

          child: Column(

            crossAxisAlignment:
                CrossAxisAlignment.start,

            children: <Widget>[

              _buildHeader(),

              const SizedBox(height: 26),

              _buildDeviceCard(busy),

              const SizedBox(height: 24),

              _buildSectionHeading(
                'MOOD CONTROLS',
                'Choose how MOODI feels',
              ),

              const SizedBox(height: 12),

              _buildEmotionGrid(),

              const SizedBox(height: 20),

              _buildInfoCard(),

              const SizedBox(height: 18),

              Center(

                child: Text(

                  'MADE FOR YOUR LITTLE DIGITAL COMPANION',

                  style: TextStyle(

                    color: Colors.white.withValues(
                      alpha: 0.35,
                    ),

                    fontSize: 9,

                    letterSpacing: 1.5,

                    fontWeight: FontWeight.w700,

                  ),

                ),

              ),

            ],

          ),

        ),

      ),

    );

  }


  // ============================================================
  // 15. APP HEADER
  // ============================================================

  Widget _buildHeader() {

    return Row(

      children: <Widget>[

        Container(

          width: 46,

          height: 46,

          decoration: BoxDecoration(

            color: const Color(0xFF193A3B),

            borderRadius: BorderRadius.circular(15),

            border: Border.all(
              color: const Color(0xFF376C68),
            ),

          ),

          child: const Icon(

            Icons.face_retouching_natural_rounded,

            color: Color(0xFF79E5D2),

            size: 27,

          ),

        ),

        const SizedBox(width: 12),

        const Column(

          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: <Widget>[

            Text(

              'MOODI',

              style: TextStyle(

                fontSize: 23,

                height: 1,

                fontWeight: FontWeight.w900,

                letterSpacing: 2.5,

              ),

            ),

            SizedBox(height: 5),

            Text(

              'YOUR POCKET-SIZED COMPANION',

              style: TextStyle(

                color: Color(0xFF91A3A9),

                fontSize: 9,

                letterSpacing: 1.2,

                fontWeight: FontWeight.w600,

              ),

            ),

          ],

        ),

        const Spacer(),

        Container(

          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),

          decoration: BoxDecoration(

            color: const Color(0xFF151B24),

            borderRadius: BorderRadius.circular(20),

            border: Border.all(
              color: const Color(0xFF283541),
            ),

          ),

          child: const Row(

            children: <Widget>[

              Icon(
                Icons.bluetooth,
                size: 14,
                color: Color(0xFF79E5D2),
              ),

              SizedBox(width: 5),

              Text(

                'BLE',

                style: TextStyle(

                  fontSize: 10,

                  letterSpacing: 1,

                  fontWeight: FontWeight.bold,

                ),

              ),

            ],

          ),

        ),

      ],

    );

  }


  // ============================================================
  // 16. DEVICE CONNECTION CARD
  // ============================================================

  Widget _buildDeviceCard(bool busy) {

    final connectedColor = _isConnected
        ? const Color(0xFF79E5D2)
        : const Color(0xFF9AAAB1);


    final buttonLabel = _isConnected
        ? 'Disconnect'
        : _isConnecting
            ? 'Connecting…'
            : _isScanning
                ? 'Searching…'
                : 'Connect to MOODI';


    return Container(

      width: double.infinity,

      padding: const EdgeInsets.all(18),

      decoration: BoxDecoration(

        borderRadius: BorderRadius.circular(24),

        gradient: const LinearGradient(

          begin: Alignment.topLeft,

          end: Alignment.bottomRight,

          colors: <Color>[
            Color(0xFF1A3034),
            Color(0xFF151B24),
          ],

        ),

        border: Border.all(
          color: const Color(0xFF2C4E50),
        ),

      ),

      child: Column(

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: <Widget>[

          Row(

            children: <Widget>[

              Container(

                height: 12,

                width: 12,

                decoration: BoxDecoration(

                  color: _isConnected
                      ? const Color(0xFF79E5D2)
                      : _isConnecting || _isScanning
                          ? const Color(0xFFFFC66D)
                          : const Color(0xFF64727A),

                  shape: BoxShape.circle,

                  boxShadow: _isConnected
                      ? <BoxShadow>[
                          BoxShadow(
                            color: const Color(0xFF79E5D2)
                                .withValues(alpha: 0.4),
                            blurRadius: 10,
                          ),
                        ]
                      : const <BoxShadow>[],

                ),

              ),

              const SizedBox(width: 9),

              Text(

                _isConnected
                    ? 'DEVICE CONNECTED'
                    : _isConnecting
                        ? 'CONNECTING'
                        : _isScanning
                            ? 'SCANNING FOR DEVICE'
                            : 'DEVICE NOT CONNECTED',

                style: TextStyle(

                  color: connectedColor,

                  fontSize: 10,

                  fontWeight: FontWeight.w800,

                  letterSpacing: 1.3,

                ),

              ),

              const Spacer(),

              const Icon(

                Icons.bluetooth_connected,

                color: Color(0xFF79E5D2),

                size: 18,

              ),

            ],

          ),

          const SizedBox(height: 18),

          Row(

            children: <Widget>[

              Container(

                width: 68,

                height: 68,

                decoration: BoxDecoration(

                  color: const Color(0xFF0D171D),

                  borderRadius: BorderRadius.circular(20),

                ),

                alignment: Alignment.center,

                child: Text(

                  _selectedEmotion.emoji,

                  style: const TextStyle(fontSize: 38),

                ),

              ),

              const SizedBox(width: 14),

              Expanded(

                child: Column(

                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: <Widget>[

                    Text(

                      _deviceName,

                      style: const TextStyle(

                        fontSize: 21,

                        fontWeight: FontWeight.w800,

                      ),

                    ),

                    const SizedBox(height: 4),

                    Text(

                      _statusMessage,

                      maxLines: 3,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(

                        color: Color(0xFFB5C4C8),

                        fontSize: 12,

                        height: 1.4,

                      ),

                    ),

                  ],

                ),

              ),

            ],

          ),

          const SizedBox(height: 18),

          SizedBox(

            width: double.infinity,

            height: 49,

            child: FilledButton.icon(

              onPressed: busy
                  ? null
                  : _isConnected
                      ? _disconnect
                      : _startScan,

              icon: Icon(

                _isConnected
                    ? Icons.link_off_rounded
                    : _isScanning
                        ? Icons.radar_rounded
                        : Icons.bluetooth_searching_rounded,

                size: 18,

              ),

              label: Text(buttonLabel),

              style: FilledButton.styleFrom(

                backgroundColor: const Color(0xFF79E5D2),

                foregroundColor: const Color(0xFF09201F),

                disabledBackgroundColor:
                    const Color(0xFF42615F),

                disabledForegroundColor:
                    const Color(0xFFD4E8E4),

                textStyle: const TextStyle(

                  fontWeight: FontWeight.w800,

                  letterSpacing: 0.2,

                ),

                shape: RoundedRectangleBorder(

                  borderRadius: BorderRadius.circular(15),

                ),

              ),

            ),

          ),

        ],

      ),

    );

  }


  // ============================================================
  // 17. SECTION HEADING
  // ============================================================

  Widget _buildSectionHeading(
    String eyebrow,
    String title,
  ) {

    return Column(

      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: <Widget>[

        Text(

          eyebrow,

          style: const TextStyle(

            color: Color(0xFF79E5D2),

            fontSize: 9,

            letterSpacing: 1.7,

            fontWeight: FontWeight.w800,

          ),

        ),

        const SizedBox(height: 5),

        Text(

          title,

          style: const TextStyle(

            fontSize: 19,

            fontWeight: FontWeight.w800,

          ),

        ),

      ],

    );

  }


  // ============================================================
  // 18. EMOTION BUTTON GRID
  // ============================================================

  Widget _buildEmotionGrid() {

    return GridView.builder(

      shrinkWrap: true,

      physics: const NeverScrollableScrollPhysics(),

      itemCount: MoodiEmotion.values.length,

      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(

        crossAxisCount: 2,

        crossAxisSpacing: 11,

        mainAxisSpacing: 11,

        mainAxisExtent: 88,

      ),

      itemBuilder: (context, index) {

        final emotion = MoodiEmotion.values[index];

        final selected = _selectedEmotion == emotion;

        final enabled = _isConnected && !_isSending;


        return Material(

          color: selected
              ? const Color(0xFF1A3C3B)
              : const Color(0xFF151B24),

          borderRadius: BorderRadius.circular(18),

          child: InkWell(

            onTap: enabled
                ? () => _sendEmotion(emotion)
                : null,

            borderRadius: BorderRadius.circular(18),

            child: Container(

              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 12,
              ),

              decoration: BoxDecoration(

                borderRadius: BorderRadius.circular(18),

                border: Border.all(

                  color: selected
                      ? const Color(0xFF79E5D2)
                      : const Color(0xFF29333F),

                  width: selected ? 1.4 : 1,

                ),

              ),

              child: Row(

                children: <Widget>[

                  Text(
                    emotion.emoji,
                    style: const TextStyle(fontSize: 29),
                  ),

                  const SizedBox(width: 10),

                  Expanded(

                    child: Column(

                      mainAxisAlignment:
                          MainAxisAlignment.center,

                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: <Widget>[

                        Text(

                          emotion.label,

                          style: TextStyle(

                            fontSize: 14,

                            fontWeight: FontWeight.w800,

                            color: enabled
                                ? Colors.white
                                : Colors.white.withValues(
                                    alpha: 0.48,
                                  ),

                          ),

                        ),

                        const SizedBox(height: 3),

                        Text(

                          selected &&
                                  _lastSentEmotion == emotion
                              ? 'Sent to MOODI'
                              : enabled
                                  ? 'Tap to send'
                                  : 'Connect first',

                          style: TextStyle(

                            color: enabled
                                ? const Color(0xFF9DB2B6)
                                : const Color(0xFF65747C),

                            fontSize: 9,

                          ),

                        ),

                      ],

                    ),

                  ),

                  if (selected &&
                      _lastSentEmotion == emotion)

                    const Icon(

                      Icons.check_circle,

                      color: Color(0xFF79E5D2),

                      size: 16,

                    ),

                ],

              ),

            ),

          ),

        );

      },

    );

  }


  // ============================================================
  // 19. INFORMATION CARD
  // ============================================================

  Widget _buildInfoCard() {

    return Container(

      padding: const EdgeInsets.all(14),

      decoration: BoxDecoration(

        color: const Color(0xFF111720),

        borderRadius: BorderRadius.circular(17),

        border: Border.all(
          color: const Color(0xFF26313B),
        ),

      ),

      child: const Row(

        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: <Widget>[

          Icon(

            Icons.lightbulb_outline_rounded,

            color: Color(0xFFFFC66D),

            size: 19,

          ),

          SizedBox(width: 10),

          Expanded(

            child: Text(

              'Keep MOODI powered on and nearby. If you used nRF Connect earlier, disconnect it before connecting here. Emotion controls become active after the BLE connection is ready. Time and date are synchronized automatically when the connection is established.',

              style: TextStyle(

                color: Color(0xFFAAB8BE),

                fontSize: 11,

                height: 1.45,

              ),

            ),

          ),

        ],

      ),

    );

  }

}
