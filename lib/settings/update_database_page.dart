import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:csv/csv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_isolate/flutter_isolate.dart';

class UpdateDatabasePage extends StatefulWidget {
  const UpdateDatabasePage({super.key});

  @override
  State<UpdateDatabasePage> createState() => _UpdateDatabasePageState();
}

class _UpdateDatabasePageState extends State<UpdateDatabasePage> {
  bool _isLoading = false;
  double _progress = 0.0;
  String _statusText = '';
  List<String> _logMessages = [];
  final ScrollController _scrollController = ScrollController();
  String _updateFrequency = 'Every 24 Hours';
  Timer? _updateTimer;
  String _lastUpdateText = 'Never';
  FlutterIsolate? _isolate;
  ReceivePort? _receivePort;

  @override
  void initState() {
    super.initState();
    _loadLastUpdateTime();
    _startAutoUpdate();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _updateTimer?.cancel();
    _isolate?.kill();
    _receivePort?.close();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadLastUpdateTime() async {
    final prefs = await SharedPreferences.getInstance();
    final lastUpdate = prefs.getInt('lastUpdateTimestamp');
    if (lastUpdate != null) {
      final lastUpdateTime = DateTime.fromMillisecondsSinceEpoch(lastUpdate);
      final duration = DateTime.now().difference(lastUpdateTime);
      setState(() {
        if (duration.inDays > 30) {
          _lastUpdateText = '${duration.inDays ~/ 30} month${(duration.inDays ~/ 30) > 1 ? 's' : ''} ago';
        } else if (duration.inDays > 0) {
          _lastUpdateText = '${duration.inDays} day${duration.inDays > 1 ? 's' : ''} ago';
        } else {
          _lastUpdateText = '${duration.inHours} hour${duration.inHours > 1 ? 's' : ''} ago';
        }
      });
    }
  }

  void _startAutoUpdate() {
    _updateTimer?.cancel();
    Duration interval;
    switch (_updateFrequency) {
      case 'Every Week':
        interval = const Duration(days: 7);
        break;
      case 'Every Month':
        interval = const Duration(days: 30);
        break;
      default:
        interval = const Duration(hours: 24);
    }
    _updateTimer = Timer.periodic(interval, (_) => _runUpdateInBackground());
  }

  Future<void> _runUpdateInBackground() async {
    if (_isLoading) return;
    _receivePort = ReceivePort();
    _isolate = await FlutterIsolate.spawn(_backgroundUpdate, _receivePort!.sendPort);
    _receivePort!.listen((message) {
      if (message == 'done') {
        setState(() {
          _isLoading = false;
        });
        _loadLastUpdateTime();
        _isolate?.kill();
        _receivePort?.close();
      } else if (message is String) {
        _addLog(message);
      }
    });
  }

  static void _backgroundUpdate(SendPort sendPort) async {
    List<Map<String, String>> actorsData = [];
    List<Map<String, String>> actressesData = [];
    List<List<dynamic>> newCsvData = [];
    List<String> logs = [];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';

    try {
      List<String> existingNames = await _readExistingNames('Fetched_StarZone_Data.csv');
      for (var letter in alphabet.split('')) {
        var actorData = await _fetchLinksFromAlpha(letter, 'actor');
        var actressData = await _fetchLinksFromAlpha(letter, 'actress');
        actorsData.addAll(actorData);
        actressesData.addAll(actressData);
        for (var data in [...actorData, ...actressData]) {
          String name = data['Name']!;
          if (!existingNames.contains(name)) {
            newCsvData.add([name, data['URL']]);
            logs.add('$name Added');
          }
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (newCsvData.isNotEmpty) {
        Directory saveDir = await getApplicationDocumentsDirectory();
        String dirPath = '${saveDir.path}/RagalahariData';
        Directory(dirPath).createSync(recursive: true);

        // Save CSV
        String csvFilePath = '$dirPath/Fetched_StarZone_Data.csv';
        File csvFile = File(csvFilePath);
        List<List<dynamic>> existingCsvData = [];
        if (await csvFile.exists()) {
          String csvContent = await csvFile.readAsString();
          existingCsvData = const CsvToListConverter().convert(csvContent);
        }
        List<List<dynamic>> csvData = [
          ['Name', 'URL'],
          ...existingCsvData.skip(1),
          ...newCsvData,
        ];
        String csv = const ListToCsvConverter().convert(csvData);
        await csvFile.writeAsString(csv);

        // Save JSON
        String jsonFilePath = '$dirPath/Fetched_Albums_StarZone.json';
        File jsonFile = File(jsonFilePath);
        Map<String, dynamic> jsonData = {
          'actors': actorsData,
          'actresses': actressesData,
        };
        await jsonFile.writeAsString(json.encode(jsonData));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('lastUpdateTimestamp', DateTime.now().millisecondsSinceEpoch);
      } else {
        logs.add('No new entries found.');
      }
    } catch (e) {
      logs.add('Error: $e');
    } finally {
      for (var log in logs) {
        sendPort.send(log);
      }
      sendPort.send('done');
    }
  }

  static Future<List<String>> _readExistingNames(String filename) async {
    try {
      Directory saveDir = await getApplicationDocumentsDirectory();
      String dirPath = '${saveDir.path}/RagalahariData';
      String filePath = '$dirPath/$filename';
      Directory(dirPath).createSync(recursive: true);
      File file = File(filePath);
      if (await file.exists()) {
        String csvContent = await file.readAsString();
        List<List<dynamic>> csvData = const CsvToListConverter().convert(csvContent);
        return csvData.skip(1).map((row) => row[0].toString()).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<Map<String, String>>> _fetchLinksFromAlpha(String alphaLetter, String category) async {
    String baseUrl = 'https://www.ragalahari.com/$category/$alphaLetter/starzonesearch.aspx';
    List<Map<String, String>> linksData = [];

    try {
      final response = await http.get(Uri.parse(baseUrl));
      if (response.statusCode == 200) {
        var document = parser.parse(response.body);
        var aTags = document.querySelectorAll('a.galleryname#lnknav');
        for (var aTag in aTags) {
          String? href = aTag.attributes['href'];
          String name = aTag.text.trim();
          if (href != null && href.isNotEmpty && name.isNotEmpty) {
            String fullUrl = 'https://www.ragalahari.com$href';
            linksData.add({'Name': name, 'URL': fullUrl});
          }
        }
      }
    } catch (e) {
      // Errors logged in background
    }
    return linksData;
  }

  Future<void> _updateDatabase({bool isBackground = false}) async {
    if (_isLoading) return;

    if (!isBackground) {
      setState(() {
        _isLoading = true;
        _progress = 0.0;
        _statusText = 'Updating database...';
        _logMessages = [];
      });
    }

    try {
      List<Map<String, String>> actorsData = [];
      List<Map<String, String>> actressesData = [];
      List<List<dynamic>> newCsvData = [];
      const alphabet = 'abcdefghijklmnopqrstuvwxyz';
      List<String> existingNames = await _readExistingNames('Fetched_StarZone_Data.csv');

      for (int i = 0; i < alphabet.length; i++) {
        String letter = alphabet[i];
        if (!isBackground) {
          setState(() {
            _progress = i / alphabet.length;
          });
        }

        var actorDataFuture = _fetchLinksFromAlpha(letter, 'actor');
        var actressDataFuture = _fetchLinksFromAlpha(letter, 'actress');
        var results = await Future.wait([actorDataFuture, actressDataFuture]);
        var actorData = results[0];
        var actressData = results[1];

        actorsData.addAll(actorData);
        actressesData.addAll(actressData);

        for (var data in [...actorData, ...actressData]) {
          String name = data['Name']!;
          if (!existingNames.contains(name)) {
            newCsvData.add([name, data['URL']]);
            _addLog('$name Added');
          }
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      if (newCsvData.isNotEmpty) {
        if (!isBackground) {
          setState(() {
            _statusText = 'Saving data to CSV and JSON...';
          });
        }

        Directory saveDir = await getApplicationDocumentsDirectory();
        String dirPath = '${saveDir.path}/RagalahariData';
        Directory(dirPath).createSync(recursive: true);

        // Save CSV
        String csvFilePath = '$dirPath/Fetched_StarZone_Data.csv';
        File csvFile = File(csvFilePath);
        List<List<dynamic>> existingCsvData = [];
        if (await csvFile.exists()) {
          String csvContent = await csvFile.readAsString();
          existingCsvData = const CsvToListConverter().convert(csvContent);
        }
        List<List<dynamic>> csvData = [
          ['Name', 'URL'],
          ...existingCsvData.skip(1),
          ...newCsvData,
        ];
        String csv = const ListToCsvConverter().convert(csvData);
        await csvFile.writeAsString(csv);

        // Save JSON
        String jsonFilePath = '$dirPath/Fetched_Albums_StarZone.json';
        File jsonFile = File(jsonFilePath);
        Map<String, dynamic> jsonData = {
          'actors': actorsData,
          'actresses': actressesData,
        };
        await jsonFile.writeAsString(json.encode(jsonData));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('lastUpdateTimestamp', DateTime.now().millisecondsSinceEpoch);

        if (!isBackground) {
          setState(() {
            _statusText = 'Database updated successfully!';
            _progress = 1.0;
          });
        }
      } else {
        if (!isBackground) {
          setState(() {
            _statusText = 'No new data to add.';
          });
          _addLog('No new entries found.');
        }
      }
    } catch (e) {
      if (!isBackground) {
        setState(() {
          _statusText = 'Error: $e';
        });
      }
      _addLog('Error: $e');
    } finally {
      if (!isBackground) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _addLog(String message) {
    setState(() {
      _logMessages.add('${DateTime.now().toString().substring(11, 19)}: $message');
      Future.delayed(Duration.zero, _scrollToBottom);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Update Database',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: theme.colorScheme.surfaceTint,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Database Updater',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Click on "Update Database" to add newly added celebrities to your app.',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              surfaceTintColor: theme.colorScheme.surfaceTint,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    const Text('Auto-update: ', style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _updateFrequency,
                      items: ['Every 24 Hours', 'Every Week', 'Every Month']
                          .map((String value) => DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      ))
                          .toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _updateFrequency = newValue;
                          });
                          _startAutoUpdate();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Last updated: $_lastUpdateText',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : () => _updateDatabase(),
              icon: const Icon(Icons.cloud_download),
              label: Text(_isLoading ? 'Updating...' : 'Update Database'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
            ),
            const SizedBox(height: 24),
            if (_isLoading || _progress > 0)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                surfaceTintColor: theme.colorScheme.surfaceTint,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _statusText,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Log:',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                surfaceTintColor: theme.colorScheme.surfaceTint,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListView.builder(
                    controller: _scrollController,
                    itemCount: _logMessages.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          _logMessages[index],
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}