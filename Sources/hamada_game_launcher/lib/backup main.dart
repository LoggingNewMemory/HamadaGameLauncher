import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/services.dart' show PlatformException;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(MyGameLauncherApp());
}

class MyGameLauncherApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Game Launcher',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        fontFamily: 'Orbitron',
        scaffoldBackgroundColor: Colors.black,
      ),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  State createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  List<InstalledApp> _cachedInstalledApps = [];
  bool _isLoadingApps = false;

  // Fade transition controller
  late AnimationController _fadeAnimController;
  late Animation<double> _fadeAnimation;
  bool _showFadeTransition = false;

  @override
  void initState() {
    super.initState();

    // Initialize the fade animation controller
    _fadeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeAnimController,
      curve: Curves.easeInOut,
    ));

    _fadeAnimController.addListener(() => setState(() {}));
    _fadeAnimController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => GameListScreen(
              preloadedApps: _cachedInstalledApps,
              isStillLoadingApps: _isLoadingApps,
            ),
          ),
        );
      }
    });

    _controller = VideoPlayerController.asset("assets/HGL.mp4")
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });

    _preloadInstalledApps();

    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration &&
          !_showFadeTransition) {
        setState(() => _showFadeTransition = true);
        _fadeAnimController.forward();
      }
    });
  }

  Future _preloadInstalledApps() async {
    setState(() => _isLoadingApps = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAppsJson = prefs.getStringList('cachedInstalledApps') ?? [];

      if (cachedAppsJson.isNotEmpty) {
        _cachedInstalledApps = cachedAppsJson.map((appJson) {
          return InstalledApp.fromMap(json.decode(appJson));
        }).toList();
      }

      const platform =
          MethodChannel('com.example.hamada_game_launcher/channel');
      final List apps = await platform.invokeMethod('getInstalledApps');

      final freshInstalledApps = apps.map((app) {
        return InstalledApp(
          packageName: app['packageName'],
          appName: app['appName'],
          icon: app['icon'] != null
              ? Uint8List.fromList(List.from(app['icon']))
              : null,
        );
      }).toList();

      final freshAppsJson =
          freshInstalledApps.map((app) => json.encode(app.toMap())).toList();
      await prefs.setStringList('cachedInstalledApps', freshAppsJson);

      setState(() {
        _cachedInstalledApps = freshInstalledApps;
        _isLoadingApps = false;
      });
    } catch (e) {
      print("Error preloading apps: $e");
      setState(() => _isLoadingApps = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _fadeAnimController.dispose();
    super.dispose();
  }

  Widget _buildFadeTransition() {
    return Stack(
      children: [
        // Video player
        Positioned.fill(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: VideoPlayer(_controller),
            ),
          ),
        ),
        // Fade overlay
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _fadeAnimation.value,
            duration: Duration(milliseconds: 0),
            child: Container(color: Colors.black),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          color: Colors.black,
          child: _showFadeTransition
              ? _buildFadeTransition()
              : FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.isInitialized
                        ? _controller.value.size.width
                        : 1,
                    height: _controller.value.isInitialized
                        ? _controller.value.size.height
                        : 1,
                    child: VideoPlayer(_controller),
                  ),
                ),
        ),
      ),
    );
  }
}

class InstalledApp {
  final String packageName;
  final String appName;
  final Uint8List? icon;

  InstalledApp({required this.packageName, required this.appName, this.icon});

  Map<String, dynamic> toMap() {
    return {
      'packageName': packageName,
      'appName': appName,
      'icon': icon != null ? base64Encode(icon!) : null,
    };
  }

  factory InstalledApp.fromMap(Map<String, dynamic> map) {
    return InstalledApp(
      packageName: map['packageName'],
      appName: map['appName'],
      icon: map['icon'] != null ? base64Decode(map['icon']) : null,
    );
  }
}

class GameListScreen extends StatefulWidget {
  final List<InstalledApp> preloadedApps;
  final bool isStillLoadingApps;

  const GameListScreen({
    Key? key,
    this.preloadedApps = const [],
    this.isStillLoadingApps = false,
  }) : super(key: key);

  @override
  _GameListScreenState createState() => _GameListScreenState();
}

class _GameListScreenState extends State<GameListScreen> {
  List<InstalledApp> addedGames = [];
  List<InstalledApp> installedApps = [];
  bool _isLoadingGames = true;
  bool _isLoadingInstalledApps = false;
  String _errorMessage = '';
  bool _isRoot = false;

  static const platform =
      MethodChannel('com.example.hamada_game_launcher/channel');

  @override
  void initState() {
    super.initState();
    installedApps = widget.preloadedApps;
    _isLoadingInstalledApps = widget.isStillLoadingApps;

    if (_isLoadingInstalledApps) {
      _refreshInstalledAppsWhenReady();
    }

    _loadSavedGames();
    _checkRootStatus();
  }

  Future _checkRootStatus() async {
    final rootStatus = await checkRootStatus();
    setState(() {
      _isRoot = rootStatus;
    });
  }

  Future _refreshInstalledAppsWhenReady() async {
    if (installedApps.isEmpty) await _loadCachedInstalledApps();
    if (_isLoadingInstalledApps) _getInstalledAppsInBackground();
  }

  Future _loadCachedInstalledApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedAppsJson = prefs.getStringList('cachedInstalledApps') ?? [];

      if (cachedAppsJson.isNotEmpty) {
        setState(() {
          installedApps = cachedAppsJson.map((appJson) {
            return InstalledApp.fromMap(json.decode(appJson));
          }).toList();
        });
      }
    } catch (e) {
      print("Error loading cached apps: $e");
    }
  }

  Future _getInstalledAppsInBackground() async {
    setState(() => _isLoadingInstalledApps = true);

    try {
      final List apps = await platform.invokeMethod('getInstalledApps');
      final freshApps = apps.map((app) {
        return InstalledApp(
          packageName: app['packageName'],
          appName: app['appName'],
          icon: app['icon'] != null
              ? Uint8List.fromList(List.from(app['icon']))
              : null,
        );
      }).toList();

      final prefs = await SharedPreferences.getInstance();
      final freshAppsJson =
          freshApps.map((app) => json.encode(app.toMap())).toList();
      await prefs.setStringList('cachedInstalledApps', freshAppsJson);

      if (mounted) {
        setState(() {
          installedApps = freshApps;
          _isLoadingInstalledApps = false;
        });
      }
    } catch (e) {
      print("Error getting installed apps: $e");
      if (mounted) setState(() => _isLoadingInstalledApps = false);
    }
  }

  Future _loadSavedGames() async {
    setState(() => _isLoadingGames = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedGamesJson = prefs.getStringList('savedGames') ?? [];

      final loadedGames = savedGamesJson.map((gameJson) {
        return InstalledApp.fromMap(json.decode(gameJson));
      }).toList();

      setState(() {
        addedGames = loadedGames;
        _isLoadingGames = false;
      });
    } catch (e) {
      print("Error loading saved games: $e");
      setState(() {
        _isLoadingGames = false;
        _errorMessage = "Failed to load saved games: $e";
      });
    }
  }

  Future _saveGames() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gamesJson =
          addedGames.map((game) => json.encode(game.toMap())).toList();
      await prefs.setStringList('savedGames', gamesJson);
    } catch (e) {
      print("Error saving games: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save games: $e")),
        );
      }
    }
  }

  Future<bool> checkRootStatus() async {
    try {
      return await platform.invokeMethod('isRoot');
    } on PlatformException catch (e) {
      print("Error checking root status: ${e.message}");
      return false;
    }
  }

  void _addGame() async {
    if (installedApps.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text("Loading Apps"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text("Loading installed applications...")
            ],
          ),
        ),
      );

      await _getInstalledAppsInBackground();
      Navigator.of(context).pop();
    }

    if (installedApps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(_errorMessage.isEmpty ? "No apps found" : _errorMessage)),
      );
      return;
    }

    final sortedApps = List.from(installedApps)
      ..sort(
          (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()));

    final selectedApp = await showDialog<InstalledApp>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.videogame_asset),
              SizedBox(width: 8),
              Text("Select a Game"),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            height: 500,
            child: Column(
              children: [
                if (_isLoadingInstalledApps)
                  Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text("Refreshing app list..."),
                      ],
                    ),
                  ),
                Expanded(
                  child: sortedApps.isEmpty
                      ? Center(
                          child: Text("No games found",
                              style: TextStyle(color: Colors.grey)))
                      : GridView.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 4.0,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: sortedApps.length,
                          itemBuilder: (context, index) {
                            final app = sortedApps[index];
                            return InkWell(
                              onTap: () => Navigator.of(context).pop(app),
                              child: Card(
                                elevation: 2,
                                margin: EdgeInsets.all(2),
                                child: Padding(
                                  padding:
                                      EdgeInsets.fromLTRB(8.0, 4.0, 4.0, 4.0),
                                  child: Row(
                                    children: [
                                      app.icon != null
                                          ? Image.memory(app.icon!,
                                              width: 20, height: 20)
                                          : Icon(Icons.app_registration,
                                              size: 20),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          app.appName,
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            Container(
              height: 30,
              padding: EdgeInsets.only(right: 10, bottom: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: Icon(Icons.refresh, size: 14),
                    label: Text("Refresh", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: Size(50, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _getInstalledAppsInBackground();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Refreshing app list...")),
                      );
                    },
                  ),
                  SizedBox(width: 4),
                  TextButton(
                    onPressed: Navigator.of(context).pop,
                    child: Text("Cancel", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      minimumSize: Size(50, 24),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (selectedApp != null) {
      setState(() {
        if (!addedGames
            .any((game) => game.packageName == selectedApp.packageName)) {
          addedGames.add(selectedApp);
          _saveGames();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text("${selectedApp.appName} is already in your list")),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Hamada Game Launcher", style: TextStyle(fontSize: 16)),
        toolbarHeight: 40,
        leadingWidth: 40,
        titleSpacing: 10,
        actions: [
          IconButton(
            icon: Icon(Icons.add, size: 20),
            padding: EdgeInsets.all(8),
            constraints: BoxConstraints(),
            onPressed: _addGame,
          ),
        ],
      ),
      body: Row(
        children: [
          // Left column - Game List (60% of width)
          Expanded(
            flex: 6,
            child: _isLoadingGames
                ? Center(child: CircularProgressIndicator())
                : addedGames.isEmpty
                    ? Center(
                        child: GestureDetector(
                          onTap: _addGame,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_circle_outline,
                                  size: 64, color: Colors.blue),
                              SizedBox(height: 16),
                              Text(
                                "Tap to add your games",
                                style: TextStyle(
                                    fontSize: 24, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildGameList(),
          ),
          // Right column - Status Info (40% of width)
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Root status card with transparent background
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "System Status",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                _isRoot
                                    ? Icons.security
                                    : Icons.security_outlined,
                                color: _isRoot ? Colors.green : Colors.orange,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Text(
                                "Root :",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                _isRoot ? "ROOT" : "NON-ROOT",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: _isRoot ? Colors.green : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Text(
                            _isRoot
                                ? "Root Mode. All features are available."
                                : "Non-Root Mode. Features are limited.",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Spacer(),
                    // Additional info or controls could go here
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGameList() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: addedGames.length,
      itemBuilder: (context, index) {
        final game = addedGames[index];
        return Card(
          margin: EdgeInsets.only(bottom: 12),
          elevation: 4,
          child: InkWell(
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => GameScreen(
                    isRoot: _isRoot,
                    gameName: game.appName,
                    packageName: game.packageName,
                    gameIcon: game.icon,
                  ),
                ),
              );
            },
            child: Padding(
              padding: EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    child: ClipOval(
                      child: game.icon != null
                          ? Image.memory(game.icon!, width: 32, height: 32)
                          : Icon(Icons.gamepad, size: 32),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          game.appName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          game.packageName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.play_arrow, color: Colors.green),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => GameScreen(
                            isRoot: _isRoot,
                            gameName: game.appName,
                            packageName: game.packageName,
                            gameIcon: game.icon,
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon:
                        Icon(Icons.delete, color: Colors.red.withOpacity(0.7)),
                    onPressed: () {
                      setState(() {
                        addedGames.removeAt(index);
                        _saveGames();
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// Updated GameScreen widget with lifecycle handling for performance scripts.
class GameScreen extends StatefulWidget {
  final bool isRoot;
  final String gameName;
  final String packageName;
  final Uint8List? gameIcon;

  const GameScreen({
    Key? key,
    required this.isRoot,
    required this.gameName,
    required this.packageName,
    this.gameIcon,
  }) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const platform =
      MethodChannel('com.example.hamada_game_launcher/channel');
  bool _scriptsInitialized = false;
  bool _launchedGame = false;
  bool _balancedScriptExecuted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAndRunScript();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_balancedScriptExecuted) {
      _executeScript(widget.isRoot
          ? "root_balanced_perf.sh"
          : "non_root_balanced_perf.sh");
      _balancedScriptExecuted = true;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the app is resumed after launching the game externally,
    // execute the balanced script if it hasn’t been executed yet.
    if (state == AppLifecycleState.resumed &&
        _launchedGame &&
        !_balancedScriptExecuted) {
      _executeScript(widget.isRoot
          ? "root_balanced_perf.sh"
          : "non_root_balanced_perf.sh");
      _balancedScriptExecuted = true;
    }
  }

  Future<void> _initializeAndRunScript() async {
    if (!_scriptsInitialized) {
      await _extractScriptsIfNeeded();
    }
    await _executeScript(widget.isRoot ? "root_perf.sh" : "non_root_perf.sh");
  }

  Future<void> _extractScriptsIfNeeded() async {
    try {
      final scriptsExtracted =
          await platform.invokeMethod('areScriptsExtracted');
      if (!scriptsExtracted) {
        final scriptContents = await Future.wait([
          _loadAssetContent('assets/scripts/root_perf.sh'),
          _loadAssetContent('assets/scripts/root_balanced_perf.sh'),
          _loadAssetContent('assets/scripts/non_root_perf.sh'),
          _loadAssetContent('assets/scripts/non_root_balanced_perf.sh'),
        ]);
        await platform.invokeMethod('extractScripts', {
          "rootPerf": scriptContents[0],
          "rootBalancedPerf": scriptContents[1],
          "nonRootPerf": scriptContents[2],
          "nonRootBalancedPerf": scriptContents[3],
        });
      }
      _scriptsInitialized = true;
    } catch (e) {
      print("Error extracting scripts: $e");
    }
  }

  Future<String> _loadAssetContent(String assetPath) async {
    try {
      return await rootBundle.loadString(assetPath);
    } catch (e) {
      print("Error loading asset $assetPath: $e");
      return "echo 'Error loading script'";
    }
  }

  Future<void> _executeScript(String scriptName) async {
    try {
      await platform.invokeMethod('executeScript', {"scriptName": scriptName});
      print("Executed script: $scriptName");
    } on PlatformException catch (e) {
      print("Error executing $scriptName: ${e.message}");
    }
  }

  Future<void> _launchSelectedGame() async {
    _launchedGame = true;
    try {
      await platform
          .invokeMethod('launchApp', {"packageName": widget.packageName});
    } on PlatformException catch (e) {
      print("Error launching game: ${e.message}");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.gameName, style: TextStyle(fontSize: 16)),
        toolbarHeight: 40,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, size: 20),
          padding: EdgeInsets.all(8),
          constraints: BoxConstraints(),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: Row(
        children: [
          // Left column - Game details
          Expanded(
            flex: 6,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.7),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: widget.gameIcon != null
                          ? Image.memory(widget.gameIcon!,
                              width: 64, height: 64)
                          : Icon(Icons.gamepad, size: 64, color: Colors.blue),
                    ),
                  ),
                  SizedBox(height: 24),
                  Text(
                    widget.gameName,
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    widget.packageName,
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  SizedBox(height: 36),
                  ElevatedButton.icon(
                    icon: Icon(Icons.play_arrow),
                    label: Text("Launch Game", style: TextStyle(fontSize: 18)),
                    style: ElevatedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    ),
                    onPressed: _launchSelectedGame,
                  ),
                ],
              ),
            ),
          ),
          // Right column - Status Info
          Expanded(
            flex: 4,
            child: Container(
              color: Colors.transparent,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Launch Options",
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 16),
                          Row(
                            children: [
                              Icon(
                                widget.isRoot
                                    ? Icons.security
                                    : Icons.security_outlined,
                                color: widget.isRoot
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "Mode:",
                                style: TextStyle(
                                    fontSize: 16, color: Colors.white70),
                              ),
                              SizedBox(width: 8),
                              Text(
                                widget.isRoot ? "Root" : "Standard",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: widget.isRoot
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Text(
                            widget.isRoot
                                ? "Advanced features are available with root access."
                                : "Limited features available in standard mode.",
                            style:
                                TextStyle(fontSize: 14, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    Spacer(),
                    Center(
                      child: TextButton.icon(
                        icon: Icon(Icons.arrow_back),
                        label: Text("Return to Game List"),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
