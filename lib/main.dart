import 'dart:async';
import 'dart:io'; // Dosya işlemleri için şart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:rxdart/rxdart.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    fullScreen: true, // Kiosk modu
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const OgrenciSeciciApp());
}

class OgrenciSeciciApp extends StatelessWidget {
  const OgrenciSeciciApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Öğrenci Seçici',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        scaffoldBackgroundColor: const Color(0xFFECEFF1),
        fontFamily: 'Sans',
        useMaterial3: false,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Varsayılan liste (Dosya bulunamazsa bu görünür)
  List<String> students = ['Öğrenci 1', 'Öğrenci 2'];

  final selectedIndex = BehaviorSubject<int>.seeded(0);
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _spinPlayer = AudioPlayer();
  final AudioPlayer _applausePlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // Uygulama açılır açılmaz otomatik dosyayı kontrol et
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStartupExcel();
    });
  }

  @override
  void dispose() {
    selectedIndex.close();
    _textController.dispose();
    _spinPlayer.dispose();
    _applausePlayer.dispose();
    super.dispose();
  }

  // --- YENİ: OTOMATİK EXCEL YÜKLEME ---
  Future<void> _loadStartupExcel() async {
    try {
      // 1. Uygulamanın çalıştığı klasörü bul
      // Linux'ta derlenmiş dosyanın (executable) olduğu klasörü verir.
      String exePath = File(Platform.resolvedExecutable).parent.path;
      String filePath = "$exePath/liste.xlsx";
      File autoFile = File(filePath);

      // 2. Dosya var mı kontrol et
      if (await autoFile.exists()) {
        var bytes = await autoFile.readAsBytes();
        var excel = Excel.decodeBytes(bytes);

        List<String> newItems = [];
        for (var table in excel.tables.keys) {
          for (var row in excel.tables[table]!.rows) {
            if (row.isNotEmpty && row[0] != null) {
              String cellValue = row[0]!.value.toString();
              if (cellValue.trim().isNotEmpty && cellValue != "null") {
                newItems.add(cellValue);
              }
            }
          }
          break; // Sadece ilk sayfa
        }

        // 3. Liste doluysa güncelle
        if (newItems.isNotEmpty) {
          setState(() {
            students = newItems;
            selectedIndex.add(0);
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "Otomatik yüklendi: liste.xlsx (${newItems.length} kişi)",
                ),
                backgroundColor: Colors.green[800],
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // Dosya yoksa kullanıcıyı rahatsız etme, varsayılan listeyle devam et.
        print("Otomatik dosya bulunamadı: $filePath");
      }
    } catch (e) {
      print("Otomatik yükleme hatası: $e");
    }
  }

  // --- Çark İşlemleri ---
  void _startSelection() {
    if (students.length < 2) return;
    setState(() {
      int randomIndex = Fortune.randomInt(0, students.length);
      selectedIndex.add(randomIndex);
    });
    _playSpinSound();
  }

  Future<void> _playSpinSound() async {
    await _spinPlayer.stop();
    await _spinPlayer.play(AssetSource('sounds/cevirme.mp3'));
  }

  Future<void> _playApplauseSound() async {
    await _spinPlayer.stop();
    await _applausePlayer.stop();
    await _applausePlayer.play(AssetSource('sounds/alkis.mp3'));
  }

  void _onSelectionEnd() {
    _playApplauseSound();
    final winnerName = students[selectedIndex.value];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.emoji_events,
                size: 80,
                color: Colors.orangeAccent,
              ),
              const SizedBox(height: 20),
              const Text(
                "SEÇİLEN ÖĞRENCİ",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                winnerName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _applausePlayer.stop();
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 15,
                  ),
                  backgroundColor: Colors.green,
                ),
                child: const Text(
                  "TAMAM",
                  style: TextStyle(fontSize: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- Manuel Excel Yükleme (Buton İçin) ---
  Future<void> _importExcel() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null) {
        var file = File(result.files.single.path!);
        var bytes = file.readAsBytesSync();
        var excel = Excel.decodeBytes(bytes);

        List<String> newItems = [];
        for (var table in excel.tables.keys) {
          for (var row in excel.tables[table]!.rows) {
            if (row.isNotEmpty && row[0] != null) {
              String cellValue = row[0]!.value.toString();
              if (cellValue.trim().isNotEmpty && cellValue != "null") {
                newItems.add(cellValue);
              }
            }
          }
          break;
        }

        if (newItems.isNotEmpty) {
          setState(() {
            students = newItems;
            selectedIndex.add(0);
          });
          _showSnack(
            "${newItems.length} öğrenci başarıyla yüklendi.",
            isError: false,
          );
        }
      }
    } catch (e) {
      _showSnack("Hata: $e", isError: true);
    }
  }

  void _addStudent() {
    if (_textController.text.trim().isNotEmpty) {
      setState(() {
        students.add(_textController.text.trim());
        _textController.clear();
      });
    }
  }

  void _removeStudent(int index) {
    if (students.length > index) {
      setState(() {
        students.removeAt(index);
        selectedIndex.add(0);
      });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green[700],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pardus ETAP - Sınıf Çarkı'),
        centerTitle: true,
        backgroundColor: const Color(0xFF283593),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.power_settings_new, color: Colors.redAccent),
          tooltip: "Uygulamadan Çık",
          onPressed: () async {
            await windowManager.close();
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever),
            tooltip: "Listeyi Temizle",
            onPressed: () {
              setState(() {
                students = ['Öğrenci A', 'Öğrenci B'];
                selectedIndex.add(0);
              });
            },
          ),
        ],
      ),
      body: Row(
        children: [
          // Sol Panel
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    onPressed: _importExcel,
                    icon: const Icon(Icons.file_upload, color: Colors.white),
                    label: const Text(
                      "Farklı Excel Seç",
                      style: TextStyle(color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF43A047),
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: const InputDecoration(
                            labelText: 'Öğrenci Adı',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: (_) => _addStudent(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Ink(
                        decoration: const ShapeDecoration(
                          color: Colors.indigo,
                          shape: CircleBorder(),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.add, color: Colors.white),
                          onPressed: _addStudent,
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 25),
                  Expanded(
                    child: students.isEmpty
                        ? const Center(child: Text("Liste Boş"))
                        : ListView.separated(
                            itemCount: students.length,
                            separatorBuilder: (ctx, i) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  backgroundColor: Colors.indigo[100],
                                  radius: 14,
                                  child: Text(
                                    "${index + 1}",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                title: Text(students[index]),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.redAccent,
                                    size: 20,
                                  ),
                                  onPressed: () => _removeStudent(index),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    "Toplam Mevcut: ${students.length}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Sağ Panel (Çark)
          Expanded(
            flex: 5,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFECEFF1), Color(0xFFCFD8DC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: students.length < 2
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 50,
                                  color: Colors.orange,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  "En az 2 öğrenci gerekli",
                                  style: TextStyle(fontSize: 18),
                                ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: FortuneWheel(
                              selected: selectedIndex.stream,
                              animateFirst: false,
                              items: [
                                for (int i = 0; i < students.length; i++)
                                  FortuneItem(
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Text(
                                        students[i],
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    style: FortuneItemStyle(
                                      color:
                                          Colors.primaries[i %
                                              Colors.primaries.length],
                                      borderColor: Colors.white,
                                      borderWidth: 2,
                                    ),
                                  ),
                              ],
                              onFling: _startSelection,
                              onAnimationEnd: _onSelectionEnd,
                              physics: CircularPanPhysics(
                                duration: const Duration(seconds: 4),
                                curve: Curves.decelerate,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  if (students.length >= 2)
                    ElevatedButton(
                      onPressed: _startSelection,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 60,
                          vertical: 22,
                        ),
                        backgroundColor: const Color(0xFF283593),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                        elevation: 5,
                      ),
                      child: const Text(
                        "KURA ÇEK",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
