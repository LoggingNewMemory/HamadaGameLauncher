import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/services.dart' show PlatformException;
import 'package:fluttertoast/fluttertoast.dart';

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
  bool _appsLoaded = false; // Flag to indicate apps are fully loaded

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

    // Listen to video playback and trigger transition when apps are loaded
    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration &&
          !_showFadeTransition &&
          _appsLoaded) {
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
          // Convert icon data properly using List<int>.from
          icon: (app['icon'] != null && (app['icon'] as List).isNotEmpty)
              ? Uint8List.fromList(List<int>.from(app['icon']))
              : null,
        );
      }).toList();

      final freshAppsJson =
          freshInstalledApps.map((app) => json.encode(app.toMap())).toList();
      await prefs.setStringList('cachedInstalledApps', freshAppsJson);

      setState(() {
        _cachedInstalledApps = freshInstalledApps;
        _isLoadingApps = false;
        _appsLoaded = true;
      });

      // If the video is finished, trigger the transition now.
      if (_controller.value.isInitialized &&
          _controller.value.position >= _controller.value.duration &&
          !_showFadeTransition) {
        setState(() => _showFadeTransition = true);
        _fadeAnimController.forward();
      }
    } catch (e) {
      print("Error preloading apps: $e");
      setState(() {
        _isLoadingApps = false;
        _appsLoaded = true;
      });
      if (_controller.value.isInitialized &&
          _controller.value.position >= _controller.value.duration &&
          !_showFadeTransition) {
        setState(() => _showFadeTransition = true);
        _fadeAnimController.forward();
      }
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
          // Convert icon data properly using List<int>.from
          icon: (app['icon'] != null && (app['icon'] as List).isNotEmpty)
              ? Uint8List.fromList(List<int>.from(app['icon']))
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
          // Left column – Game List (60% of width)
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
          // Right column – Status Info (40% of width)
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
                                ? "Advanced Performance Script Available."
                                : "Basic Performance Script Available.",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                          SizedBox(height: 16),
                          // Author credit
                          Text(
                            "By: Kanagawa Yamada",
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

// Updated _GameScreenState: The performance script is now executed when the user presses "Launch Game".
// The button text changes to "Optimizing" while the script is being executed.
class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const platform =
      MethodChannel('com.example.hamada_game_launcher/channel');
  bool _scriptsInitialized = false;
  bool _launchedGame = false;
  bool _balancedScriptExecuted = false;
  bool _isOptimizing = false;
  DateTime? _gameStartTime;

  final List<String> _goodLuckMessages = [
    "Press start to play!",
    "Game on, warrior!",
    "Power up and conquer!",
    "Keep calm and press button!",
    "Victory awaits, jump in!",
    "One life, one chance!",
    "No respawn needed!",
    "Epic moves only!",
    "Combo attack activated!",
    "Level up your game!",
    "Score high, aim higher!",
    "Challenge accepted!",
    "Dare to defeat!",
    "Your quest begins now!",
    "Push your limits!",
    "Master the controls!",
    "Unleash your power!",
    "Speed up, gear up!",
    "Fight like a legend!",
    "Game face on!",
    "In the zone, dominate!",
    "Crush the competition!",
    "No cheat codes needed!",
    "Precision is key!",
    "Your adventure awaits!",
    "Hone your skills!",
    "Ready, set, game!",
    "Strategize and conquer!",
    "Climb the leaderboard!",
    "In this game, you're king!",
    "Run, jump, defeat!",
    "Defeat is not an option!",
    "Challenge the impossible!",
    "Play to win!",
    "Conquer with courage!",
    "Game over? Never!",
    "Victory through skill!",
    "Unstoppable force!",
    "No boundaries, just game!",
    "Thrill in every level!",
    "Adventure calls, answer it!",
    "Be legendary!",
    "Never back down!",
    "Beat the boss!",
    "Push past limits!",
    "Stay sharp, play smart!",
    "The game is yours!",
    "Victory at every turn!",
    "Aim true, win big!",
    "Gear up for glory!",
    "Step into the arena!",
    "Unyielding spirit!",
    "Challenge the norm!",
    "Thrill-seeker, play on!",
    "Press on, never quit!",
    "In it to win it!",
    "Raise the bar!",
    "Master every level!",
    "Go full throttle!",
    "Your journey begins here!",
    "Feel the rush!",
    "Score a critical hit!",
    "Game like a pro!",
    "Seize the joystick!",
    "Stay ahead of the game!",
    "No game, no glory!",
    "Awaken the hero!",
    "Your skills speak volumes!",
    "Fight for every pixel!",
    "Make every move count!",
    "Embrace the challenge!",
    "Ready for battle!",
    "Hero mode activated!",
    "New high score, here we come!",
    "It's all about the game!",
    "Keep your eyes on the prize!",
    "Blast through barriers!",
    "Embody the champion!",
    "Play with passion!",
    "Push beyond limits!",
    "Victory is just a play away!",
    "Unleash fury on the field!",
    "Stay relentless!",
    "Command the game!",
    "No rules, just game!",
    "Bring on the challenge!",
    "Defy expectations!",
    "Conquer with heart!",
    "Turn the game around!",
    "Embrace every challenge!",
    "Adventure is out there!",
    "Level the playing field!",
    "Pursue perfection!",
    "Game hard, win harder!",
    "Win with honor!",
    "Charge into action!",
    "Rule the realm!",
    "Strike with precision!",
    "Outplay, outlast, outwin!",
    "It's your time to shine!",
    "Dominate the digital realm!",
    "Battle, win, repeat!",
    "No fear, just game!",
    "Embody the warrior spirit!",
    "Game on, legends!",
    "Rise above the rest!",
    "Unravel the challenge!",
    "Clash with honor!",
    "Master the game mechanics!",
    "Press on, conquer all!",
    "Unlock your potential!",
    "Keep your cool!",
    "Challenge your limits!",
    "Every play counts!",
    "The game never ends!",
    "Hustle, play, win!",
    "Strive for greatness!",
    "Rule the leaderboard!",
    "Make your mark!",
    "Achieve the impossible!",
    "Score that win!",
    "Every victory matters!",
    "Game up, level up!",
    "Every level, a new chance!",
    "Claim your crown!",
    "The digital arena awaits!",
    "No mission too hard!",
    "Step up your game!",
    "Press pause, then win!",
    "Keep the streak alive!",
    "Surpass your limits!",
    "Play like a champion!",
    "Every second counts!",
    "Live the game!",
    "Never miss a beat!",
    "Unlock epic moments!",
    "Your legend starts now!",
    "Let the game begin!",
    "Dominate with finesse!",
    "Chase the high score!",
    "Game with heart!",
    "Edge out the competition!",
    "Sprint to success!",
    "Live the adventure!",
    "Onwards to glory!",
    "Press play, feel the adrenaline!",
    "Every battle counts!",
    "Write your own legend!",
    "Game on, let's roll!",
    "Charge forward with courage!",
    "Ambatukammm... Ooouuuuu...",
    "Aduh Kang... Kakangkuh...",
  ];
  String _goodLuckMessage = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Select one random message from the list on initialization.
    _goodLuckMessage =
        _goodLuckMessages[math.Random().nextInt(_goodLuckMessages.length)];
    // Note: We no longer execute the perf script on init; it will be executed when "Launch Game" is pressed.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _launchedGame) {
      // App paused – likely switched to the game
      _gameStartTime = DateTime.now();
    } else if (state == AppLifecycleState.resumed && _launchedGame) {
      // App resumed – if user returns from game, check duration
      if (_gameStartTime != null) {
        final gamePlayDuration = DateTime.now().difference(_gameStartTime!);
        // Increase threshold to 15 seconds before running the balanced script
        if (gamePlayDuration.inSeconds > 15 && !_balancedScriptExecuted) {
          print(
              "User returned from game after ${gamePlayDuration.inSeconds} seconds");
          _executeScript(widget.isRoot
              ? "root_balanced_perf.sh"
              : "non_root_balanced_perf.sh");
          _balancedScriptExecuted = true;
          Fluttertoast.showToast(
              msg: "Performance settings restored",
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.BOTTOM,
              backgroundColor:
                  const Color.fromARGB(255, 41, 38, 47).withOpacity(0.5),
              textColor: const Color.fromARGB(255, 203, 161, 233),
              fontSize: 12.0);
        }
      }
    }
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
    try {
      setState(() {
        _isOptimizing = true;
      });
      // Execute performance script when "Launch Game" is pressed.
      if (!_scriptsInitialized) {
        await _extractScriptsIfNeeded();
      }
      await _executeScript(widget.isRoot ? "root_perf.sh" : "non_root_perf.sh");

      _launchedGame = true;
      _balancedScriptExecuted = false;

      Fluttertoast.showToast(
          msg: "Optimized for Performance. Happy Gaming",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          timeInSecForIosWeb: 2,
          backgroundColor:
              const Color.fromARGB(255, 41, 38, 47).withOpacity(0.5),
          textColor: const Color.fromARGB(255, 203, 161, 233),
          fontSize: 12.0);

      // Invoke native method to launch the game
      await platform
          .invokeMethod('launchApp', {"packageName": widget.packageName});

      // Start tracking the launch time
      _gameStartTime = DateTime.now();

      // Register a callback for game exit notification from native side
      platform.setMethodCallHandler((call) async {
        if (call.method == 'onGameExited' && !_balancedScriptExecuted) {
          print("Game exit detected via platform channel");
          await _executeScript(widget.isRoot
              ? "root_balanced_perf.sh"
              : "non_root_balanced_perf.sh");
          _balancedScriptExecuted = true;
          Fluttertoast.showToast(
              msg: "Performance settings restored",
              toastLength: Toast.LENGTH_SHORT,
              gravity: ToastGravity.BOTTOM,
              backgroundColor:
                  const Color.fromARGB(255, 41, 38, 47).withOpacity(0.5),
              textColor: const Color.fromARGB(255, 203, 161, 233),
              fontSize: 12.0);
        }
        return null;
      });
    } on PlatformException catch (e) {
      print("Error launching game: ${e.message}");
      Fluttertoast.showToast(
          msg: "Error launching game: ${e.message}",
          backgroundColor: Colors.red.withOpacity(0.8),
          textColor: Colors.white);
      setState(() {
        _isOptimizing = false;
      });
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
          // Left column – Game details
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
                          color: const Color.fromARGB(255, 203, 161, 234)
                              .withOpacity(0.7),
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
                    label: Text(
                      _isOptimizing ? "Optimizing" : "Launch Game",
                      style: TextStyle(fontSize: 18),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding:
                          EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                    ),
                    onPressed:
                        _isOptimizing ? null : () => _launchSelectedGame(),
                  ),
                ],
              ),
            ),
          ),
          // Right column – Status Info
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
                          // Display the random "Good Luck" message for both modes
                          Text(
                            _goodLuckMessage,
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
