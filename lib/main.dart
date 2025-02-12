import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'models/word_model.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '单词学习',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        textTheme: TextTheme(
          displayLarge: GoogleFonts.notoSans(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
          displayMedium: GoogleFonts.notoSans(
            fontSize: 32,
            fontWeight: FontWeight.w500,
          ),
          titleLarge: GoogleFonts.notoSans(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
          bodyLarge: GoogleFonts.notoSans(
            fontSize: 20,
            color: Colors.black87,
          ),
        ),
      ),
      home: const WordCardsScreen(),
    );
  }
}

class WordCardsScreen extends StatefulWidget {
  const WordCardsScreen({super.key});

  @override
  State<WordCardsScreen> createState() => _WordCardsScreenState();
}

class _WordCardsScreenState extends State<WordCardsScreen> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController(initialPage: 0);
  late AnimationController _animationController;
  late Animation<double> _pageAnimation;
  List<Word> _words = [];
  List<Word> _originalWords = [];
  int _currentPage = 0;
  late SharedPreferences _prefs;
  final List<Color> _gradientColors = [
    Colors.blue.shade300,
    Colors.purple.shade300,
    Colors.pink.shade300,
  ];
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _initPrefs();
    _initAnimation();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFileSelectionDialog();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _loadCurrentPage() async {
    if (_words.isEmpty) return;
    final savedPage = _prefs.getInt('current_page') ?? 0;
    if (savedPage < _words.length) {
      setState(() {
        _currentPage = savedPage;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(savedPage);
      }
    }
  }

  void _initAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pageAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.4);  // 降低语速
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    
    _flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
    });
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await _flutterTts.stop();
      await Future.delayed(const Duration(milliseconds: 300));  // 等待停止完成
    }
    _isSpeaking = true;
    await _flutterTts.speak(text);
  }

  // 显示文件选择对话框
  Future<void> _showFileSelectionDialog() async {
    if (!mounted) return;

    try {
      final manifestContent = await DefaultAssetBundle.of(context).loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      final jsonFiles = manifestMap.keys.where((String key) => 
        key.startsWith('assets/') && key.endsWith('.json')
      ).toList();

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('选择单词文件'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: jsonFiles.length,
              itemBuilder: (context, index) {
                final fileName = jsonFiles[index].split('/').last;
                return ListTile(
                  leading: const Icon(Icons.description),
                  title: Text(fileName),
                  onTap: () async {
                    Navigator.pop(context);
                    await _loadWordsFromAsset(jsonFiles[index]);
                  },
                );
              },
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('加载文件列表失败：$e');
    }
  }

  // 从指定的 asset 文件加载单词
  Future<void> _loadWordsFromAsset(String assetPath) async {
    try {
      final String jsonString = await rootBundle.loadString(assetPath);
      final List<dynamic> jsonList = json.decode(jsonString);
      
      List<Map<String, dynamic>> validJsonList = [];

      for (var wordJson in jsonList) {
        if (wordJson is Map<String, dynamic>) {
          if (_isValidWordFormat(wordJson)) {
            validJsonList.add(wordJson);
          }
        }
      }

      if (validJsonList.isEmpty) {
        _showErrorDialog('文件格式不正确或没有有效的单词数据。请确保包含所有必需的字段：word、chinese_meaning、phrases、example_sentences');
        return;
      }

      if (!mounted) return;

      setState(() {
        _words = validJsonList.map((w) => Word.fromJson(w)).toList();
        _originalWords = List.from(_words);
        _currentPage = 0;
      });

      await Future.delayed(Duration.zero);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
      
      _animationController.forward();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功加载 ${_words.length} 个单词'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('加载失败：$e');
    }
  }

  bool _isValidWordFormat(Map<String, dynamic> json) {
    return json.containsKey('word') &&
           json.containsKey('chinese_meaning') &&
           json.containsKey('phrases') &&
           json.containsKey('example_sentences') &&
           json['phrases'] is Map &&
           json['example_sentences'] is List;
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _showFileSelectionDialog();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveWords() async {
    final wordsJson = json.encode(_words.map((w) => w.toJson()).toList());
    await _prefs.setString('words', wordsJson);
  }

  void _resetWords() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重置单词列表'),
        content: const Text('确定要恢复所有已删除的单词吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _words = List.from(_originalWords);
                _currentPage = 0;
                _pageController.jumpToPage(0);
              });
              _saveWords();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('单词列表已重置'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCurrentPage(int page) async {
    await _prefs.setInt('current_page', page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(40.0),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade300,
                  Colors.purple.shade300,
                  Colors.pink.shade300,
                ],
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (_currentPage + 1) / _words.length,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentPage + 1} / ${_words.length}',
                      style: GoogleFonts.notoSans(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(
                  Icons.folder_open,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: _showFileSelectionDialog,
                tooltip: '选择单词文件',
              ),
            ],
          ),
        ),
      ),
      body: _words.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              itemCount: _words.length,
              onPageChanged: (index) async {
                setState(() {
                  _currentPage = index;
                });
                _saveCurrentPage(index);
                // 等待一小段时间确保页面切换动画完成
                await Future.delayed(const Duration(milliseconds: 300));
                await _speakText(_words[index].word);
              },
              itemBuilder: (context, index) {
                return WordCard(
                  word: _words[index],
                  onNext: () {
                    if (index < _words.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  onPrevious: () {
                    if (index > 0) {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                );
              },
            ),
      floatingActionButton: null,
    );
  }
}

class WordCard extends StatefulWidget {
  final Word word;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const WordCard({
    Key? key,
    required this.word,
    required this.onNext,
    required this.onPrevious,
  }) : super(key: key);

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;
  bool _showMeaning = false;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.4);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);
  }

  Future<void> _speakText(String text) async {
    if (_isSpeaking) {
      await flutterTts.stop();
      _isSpeaking = false;
    }
    _isSpeaking = true;
    await flutterTts.speak(text);
    _isSpeaking = false;
  }

  void _toggleMeaning() {
    setState(() {
      _showMeaning = !_showMeaning;
    });
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size screenSize = MediaQuery.of(context).size;
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          widget.onPrevious();
        } else if (details.primaryVelocity! < 0) {
          widget.onNext();
        }
      },
      onDoubleTap: _toggleMeaning,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade300,
              Colors.purple.shade300,
              Colors.pink.shade300,
            ],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    widget.word.word,
                    style: GoogleFonts.libreBaskerville(
                      fontSize: 56,
                      color: Colors.white,
                      height: 1.2,
                      shadows: [
                        const Shadow(
                          offset: Offset(2, 2),
                          blurRadius: 4,
                          color: Colors.black38,
                        ),
                      ],
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (_showMeaning) Center(
                  child: Text(
                    widget.word.chineseMeaning,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white70,
                      shadows: [
                        const Shadow(
                          offset: Offset(1, 1),
                          blurRadius: 2,
                          color: Colors.black26,
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (!_showMeaning) Center(
                  child: Text(
                    '双击显示中文含义',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white38,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                // 词组部分
                if (widget.word.phrases.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '词组',
                          style: GoogleFonts.notoSans(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...widget.word.phrases.entries.map((entry) => GestureDetector(
                          onTap: () => _speakText(entry.key),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    entry.key,
                                    style: GoogleFonts.notoSans(
                                      fontSize: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    entry.value,
                                    style: GoogleFonts.notoSans(
                                      fontSize: 20,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )).toList(),
                      ],
                    ),
                  ),
                ],
                // 例句部分
                if (widget.word.exampleSentences.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '例句',
                          style: GoogleFonts.notoSans(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (int i = 0; i < widget.word.exampleSentences.length; i += 2)
                          GestureDetector(
                            onTap: () => _speakText(widget.word.exampleSentences[i]),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.word.exampleSentences[i],
                                    style: GoogleFonts.notoSans(
                                      fontSize: 20,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.word.exampleSentences[i + 1],
                                    style: GoogleFonts.notoSans(
                                      fontSize: 20,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
