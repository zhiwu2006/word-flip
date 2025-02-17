import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:glassmorphism/glassmorphism.dart';
import 'models/word_model.dart';

void main() {
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
    overlays: [SystemUiOverlay.top],
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

class _WordCardsScreenState extends State<WordCardsScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  String _currentAsset = 'assets/word.json';
  bool _showMeaning = false;
  bool _isFirstLaunch = true;
  List<Word> _unfamiliarWords = [];  // 新增不熟悉单词列表
  bool _isShowingUnfamiliar = false;  // 是否正在显示不熟悉单词列表

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPrefs();
    _initAnimation();
    _initTts();
    _loadUnfamiliarWords();  // 加载不熟悉单词列表
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _isFirstLaunch = _prefs.getBool('has_launched') ?? true;
    
    // 恢复显示/隐藏含义的状态
    final showMeaning = _prefs.getBool('show_meaning') ?? false;
    // 恢复不熟悉单词列表的显示状态
    final showUnfamiliar = _prefs.getBool('show_unfamiliar') ?? false;
    
    setState(() {
      _showMeaning = showMeaning;
      _isShowingUnfamiliar = showUnfamiliar;
    });
    
    if (_isFirstLaunch) {
      await _showFileSelectionDialog();
      await _prefs.setBool('has_launched', false);
    } else {
      await _loadLastState();
    }
  }

  Future<void> _loadLastState() async {
    try {
      final lastAsset = _prefs.getString('last_asset') ?? 'assets/word.json';
      final lastPage = _prefs.getInt('last_page') ?? 0;
      
      // 先加载单词数据
      await _loadWordsFromAsset(lastAsset);
      
      // 加载不熟悉单词列表
      await _loadUnfamiliarWords();
      
      // 确保页码在有效范围内
      if (_words.isNotEmpty) {
        final validPage = lastPage.clamp(0, _words.length - 1);
        setState(() {
          _currentPage = validPage;
          _currentAsset = lastAsset;
          
          // 根据保存的状态决定显示哪个列表
          if (_isShowingUnfamiliar) {
            _words = List.from(_unfamiliarWords);
            _currentPage = _currentPage.clamp(0, _unfamiliarWords.length - 1);
          }
        });
        
        // 等待下一帧确保 PageController 已经初始化
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentPage);
          }
        });
      }
    } catch (e) {
      print('恢复状态时出错: $e');
      await _showFileSelectionDialog();
    }
  }

  Future<void> _saveCurrentState() async {
    try {
      await _prefs.setString('last_asset', _currentAsset);
      await _prefs.setInt('last_page', _currentPage);
      await _prefs.setBool('show_meaning', _showMeaning);
      await _prefs.setBool('show_unfamiliar', _isShowingUnfamiliar);
      await _saveUnfamiliarWords();
    } catch (e) {
      print('保存状态时出错: $e');
    }
  }

  void _toggleMeaning() {
    setState(() {
      _showMeaning = !_showMeaning;
      _prefs.setBool('show_meaning', _showMeaning);
    });
  }

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
        _currentAsset = assetPath;
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
      _saveCurrentState();
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

  void _initAnimation() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pageAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOutCubic,
    ).drive(Tween<double>(
      begin: 0.0,
      end: 1.0,
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

      if (jsonFiles.isEmpty) {
        _showErrorDialog('没有找到可用的单词文件');
        return;
      }

      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: !_isFirstLaunch,  // 首次启动时不允许点击外部关闭
        builder: (context) => AlertDialog(
          title: Text(_isFirstLaunch ? '选择要学习的单词文件' : '切换单词文件'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isFirstLaunch)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16.0),
                    child: Text('欢迎使用单词学习应用！\n请选择一个单词文件开始学习。'),
                  ),
                SizedBox(
                  height: 300,  // 限制列表高度
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: jsonFiles.length,
                    itemBuilder: (context, index) {
                      final fileName = jsonFiles[index].split('/').last;
                      return ListTile(
                        leading: const Icon(Icons.description),
                        title: Text(fileName),
                        subtitle: Text('点击加载这个文件'),
                        onTap: () async {
                          Navigator.pop(context);
                          await _loadWordsFromAsset(jsonFiles[index]);
                          if (_isFirstLaunch) {
                            setState(() {
                              _isFirstLaunch = false;
                            });
                          }
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: _isFirstLaunch ? null : [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog('加载文件列表失败：$e');
    }
  }

  Future<void> _loadUnfamiliarWords() async {
    try {
      final unfamiliarJson = _prefs.getString('unfamiliar_words');
      if (unfamiliarJson != null) {
        final List<dynamic> jsonList = json.decode(unfamiliarJson);
        setState(() {
          _unfamiliarWords = jsonList.map((w) => Word.fromJson(w)).toList();
        });
      }
    } catch (e) {
      print('加载不熟悉单词列表时出错: $e');
    }
  }

  Future<void> _saveUnfamiliarWords() async {
    try {
      final jsonList = _unfamiliarWords.map((w) => w.toJson()).toList();
      await _prefs.setString('unfamiliar_words', json.encode(jsonList));
    } catch (e) {
      print('保存不熟悉单词列表时出错: $e');
    }
  }

  void _toggleUnfamiliarMode() {
    setState(() {
      _isShowingUnfamiliar = !_isShowingUnfamiliar;
      if (_isShowingUnfamiliar) {
        // 切换到不熟悉单词列表
        _words = List.from(_unfamiliarWords);
      } else {
        // 切换回原始单词列表
        _words = List.from(_originalWords);
      }
      _currentPage = 0;
      _pageController.jumpToPage(0);
    });
    // 保存当前状态
    _saveCurrentState();
  }

  void _addToUnfamiliar() {
    if (_currentPage >= 0 && _currentPage < _words.length) {
      final currentWord = _words[_currentPage];
      // 检查单词是否已在不熟悉列表中
      if (!_unfamiliarWords.any((w) => w.word == currentWord.word)) {
        setState(() {
          final updatedWord = currentWord.copyWith(isUnfamiliar: true);
          _unfamiliarWords.add(updatedWord);
          
          // 更新原始列表中的单词状态
          final index = _originalWords.indexWhere((w) => w.word == currentWord.word);
          if (index != -1) {
            _originalWords[index] = updatedWord;
          }
          
          // 如果当前正在显示原始列表，也更新当前显示的列表
          if (!_isShowingUnfamiliar) {
            _words[_currentPage] = updatedWord;
          }
        });
        _saveUnfamiliarWords();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加到不熟悉单词列表'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('该单词已在不熟悉列表中'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _words.isEmpty 
          ? const Text('单词学习',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(2, 2),
                    blurRadius: 4,
                    color: Colors.black38,
                  ),
                ],
              ),
            )
          : Text(
              '${_currentPage + 1}/${_words.length}',
              style: const TextStyle(
                fontSize: 20,
                color: Colors.white,
                shadows: [
                  Shadow(
                    offset: Offset(2, 2),
                    blurRadius: 4,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.book_outlined, color: Colors.white),  // 统一使用outlined风格和白色
            onPressed: _toggleUnfamiliarMode,
            tooltip: _isShowingUnfamiliar ? '返回所有单词' : '查看不熟悉单词',
          ),
          IconButton(
            icon: const Icon(Icons.file_open, color: Colors.white),
            onPressed: _showFileSelectionDialog,
            tooltip: '切换单词文件',
          ),
        ],
      ),
      body: _words.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : PageView.builder(
              controller: _pageController,
              onPageChanged: (page) async {
                setState(() {
                  _currentPage = page;
                });
                _saveCurrentState();
                // 等待一小段时间确保页面切换动画完成
                await Future.delayed(const Duration(milliseconds: 100));
                await _speakText(_words[page].word);
              },
              itemCount: _words.length,
              itemBuilder: (context, index) {
                return AnimatedBuilder(
                  animation: _pageAnimation,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: _pageAnimation,
                      child: child,
                    );
                  },
                  child: WordCard(
                    word: _words[index],
                    onNext: () {
                      if (index < _words.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      }
                    },
                    onPrevious: () {
                      if (index > 0) {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                        );
                      }
                    },
                    showMeaning: _showMeaning,
                    onToggleMeaning: _toggleMeaning,
                  ),
                );
              },
            ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Opacity(
            opacity: 0.8,  // 设置透明度
            child: FloatingActionButton(
              heroTag: 'unfamiliar',
              onPressed: _addToUnfamiliar,
              child: Icon(Icons.add, color: Colors.white),
              backgroundColor: Colors.blue.withOpacity(0.7),  // 设置半透明背景
              elevation: 4,  // 降低阴影
              tooltip: '添加到不熟悉单词列表',
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // 在组件销毁前保存状态
    _saveCurrentState();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _animationController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // 当应用进入后台或失去焦点时保存状态
      _saveCurrentState();
    }
  }
}

class WordCard extends StatefulWidget {
  final Word word;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final bool showMeaning;
  final VoidCallback onToggleMeaning;

  const WordCard({
    Key? key,
    required this.word,
    required this.onNext,
    required this.onPrevious,
    required this.showMeaning,
    required this.onToggleMeaning,
  }) : super(key: key);

  @override
  State<WordCard> createState() => _WordCardState();
}

class _WordCardState extends State<WordCard> {
  final FlutterTts flutterTts = FlutterTts();
  bool _isSpeaking = false;

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

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) {
          widget.onPrevious();
        } else if (details.primaryVelocity! < 0) {
          widget.onNext();
        }
      },
      onDoubleTap: widget.onToggleMeaning,
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
                if (widget.showMeaning) Center(
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
                if (!widget.showMeaning) Center(
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
