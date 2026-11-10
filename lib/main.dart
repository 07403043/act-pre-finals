import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show sqfliteFfiInit, databaseFactoryFfi;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for desktop platforms.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();

    // Tell SQLite to use the FFI database factory.
    databaseFactory = databaseFactoryFfi;
  }

  // Load saved theme before displaying the app.
  bool savedDarkMode = false;
  try {
    final prefs = SharedPreferencesAsync();
    savedDarkMode = await prefs.getBool('isDarkMode') ?? false;
  } catch (e) {
    debugPrint('LOAD THEME ERROR: $e');
  }

  runApp(MovieApp(initialDarkMode: savedDarkMode));
}

// ============================================================
// 1. MOVIE MODEL
// ============================================================

class Movie {
  final int? id;
  final String title;
  final int rating;

  Movie({
    this.id,
    required this.title,
    required this.rating,
  });

  // Convert Movie object into a Map for SQLite.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'title': title,
      'rating': rating,
    };

    if (id != null) {
      map['id'] = id;
    }

    return map;
  }

  // Convert SQLite Map into a Movie object.
  factory Movie.fromMap(Map<String, dynamic> map) {
    return Movie(
      id: map['id'] as int?,
      title: map['title'] as String,
      rating: map['rating'] as int,
    );
  }
}

// ============================================================
// 2. DATABASE HELPER (SINGLETON)
// ============================================================

class MovieDatabase {
  // One shared instance for the entire application.
  static final MovieDatabase instance = MovieDatabase._init();

  MovieDatabase._init();

  // Cached database connection.
  Database? _database;

  // Cached opening operation to prevent multiple simultaneous opens.
  Future<Database>? _databaseFuture;

  // Return the existing database connection.
  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _databaseFuture ??= _initDatabase();

    try {
      _database = await _databaseFuture!;
      return _database!;
    } catch (e) {
      // Allow a retry if opening the database fails.
      _databaseFuture = null;
      rethrow;
    }
  }

  // Open or create the SQLite database.
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();

    final fullPath = path.join(
      dbPath,
      'pocket_notes_movies.db',
    );

    return await openDatabase(
      fullPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE movies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            rating INTEGER NOT NULL
          )
        ''');

        debugPrint('Movies table created successfully.');
      },
    );
  }

  // ----------------------------------------------------------
  // CREATE: Insert a new movie.
  // ----------------------------------------------------------

  Future<int> insertMovie(Movie movie) async {
    try {
      final db = await database;

      final id = await db.insert(
        'movies',
        {
          'title': movie.title,
          'rating': movie.rating,
        },
      );

      debugPrint('Movie inserted successfully. ID: $id');

      return id;
    } catch (e) {
      debugPrint('INSERT MOVIE ERROR: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // READ: Retrieve all movies.
  // ----------------------------------------------------------

  Future<List<Movie>> getAllMovies() async {
    try {
      final db = await database;

      final result = await db.query(
        'movies',
        orderBy: 'id DESC',
      );

      return result.map((map) => Movie.fromMap(map)).toList();
    } catch (e) {
      debugPrint('GET MOVIES ERROR: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // UPDATE: Update movie using where + whereArgs.
  // ----------------------------------------------------------

  Future<int> updateMovie(Movie movie) async {
    try {
      final db = await database;

      return await db.update(
        'movies',
        {
          'title': movie.title,
          'rating': movie.rating,
        },
        where: 'id = ?',
        whereArgs: [movie.id],
      );
    } catch (e) {
      debugPrint('UPDATE MOVIE ERROR: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // DELETE: Delete movie using where + whereArgs.
  // ----------------------------------------------------------

  Future<int> deleteMovie(int id) async {
    try {
      final db = await database;

      return await db.delete(
        'movies',
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      debugPrint('DELETE MOVIE ERROR: $e');
      rethrow;
    }
  }

  // ----------------------------------------------------------
  // DELETE ALL: Remove every movie (useful for tests).
  // ----------------------------------------------------------

  Future<int> deleteAllMovies() async {
    try {
      final db = await database;
      return await db.delete('movies');
    } catch (e) {
      debugPrint('DELETE ALL MOVIES ERROR: $e');
      rethrow;
    }
  }
}

// ============================================================
// 3. MAIN APPLICATION
// ============================================================

class MovieApp extends StatefulWidget {
  final bool initialDarkMode;

  const MovieApp({
    super.key,
    required this.initialDarkMode,
  });

  @override
  State<MovieApp> createState() => _MovieAppState();
}

class _MovieAppState extends State<MovieApp> {
  late bool isDarkMode;

  @override
  void initState() {
    super.initState();

    isDarkMode = widget.initialDarkMode;
  }

  // Toggle and save the theme preference.
  Future<void> toggleTheme() async {
    final newTheme = !isDarkMode;

    setState(() {
      isDarkMode = newTheme;
    });

    try {
      final prefs = SharedPreferencesAsync();
      await prefs.setBool('isDarkMode', newTheme);
    } catch (e) {
      debugPrint('SAVE THEME ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pocket Notes: Movies',

      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

      // Light theme.
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // Dark theme.
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      home: MovieHomePage(
        isDarkMode: isDarkMode,
        onToggleTheme: toggleTheme,
      ),
    );
  }
}

// ============================================================
// 4. ADD / EDIT DIALOG (own StatefulWidget so it owns and
//    safely disposes its TextEditingController)
// ============================================================

class MovieFormDialog extends StatefulWidget {
  final Movie? movie;

  const MovieFormDialog({super.key, this.movie});

  @override
  State<MovieFormDialog> createState() => _MovieFormDialogState();
}

class _MovieFormDialogState extends State<MovieFormDialog> {
  final MovieDatabase _dbHelper = MovieDatabase.instance;

  late final TextEditingController _titleController;
  late int _rating;

  bool _isSaving = false;
  String? _titleError;
  String? _saveError;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.movie?.title ?? '',
    );
    _rating = widget.movie?.rating ?? 10;
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();

    // Validate title.
    if (title.isEmpty) {
      setState(() {
        _titleError = 'Please enter a movie title.';
      });
      return;
    }

    setState(() {
      _titleError = null;
      _saveError = null;
      _isSaving = true;
    });

    try {
      final movie = Movie(
        id: widget.movie?.id,
        title: title,
        rating: _rating,
      );

      if (widget.movie == null) {
        await _dbHelper.insertMovie(movie);
      } else {
        await _dbHelper.updateMovie(movie);
      }

      if (!mounted) return;

      // Tell the home page that the save succeeded.
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('SAVE MOVIE ERROR: $e');

      if (!mounted) return;

      setState(() {
        _isSaving = false;
        _saveError = 'Failed to save movie: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.movie == null ? 'Add Movie' : 'Edit Movie'),

      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              autofocus: true,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Movie Title',
                hintText: 'Enter movie title',
                border: const OutlineInputBorder(),
                errorText: _titleError,
              ),
            ),

            const SizedBox(height: 20),

            Text(
              'Rating: $_rating / 10',
              style: theme.textTheme.titleMedium,
            ),

            Slider(
              value: _rating.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              label: _rating.toString(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _rating = value.round();
                      });
                    },
            ),

            if (_saveError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _saveError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),

      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),

        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.movie == null ? 'Save' : 'Update'),
        ),
      ],
    );
  }
}

// ============================================================
// 5. HOME PAGE + 8+ RATING FILTER
// ============================================================

class MovieHomePage extends StatefulWidget {
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const MovieHomePage({
    super.key,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<MovieHomePage> createState() => _MovieHomePageState();
}

class _MovieHomePageState extends State<MovieHomePage> {
  // Reuse the Singleton database instance.
  final MovieDatabase dbHelper = MovieDatabase.instance;

  List<Movie> movies = [];

  // Plain State variable for the filter.
  bool onlyHighRated = false;

  @override
  void initState() {
    super.initState();
    loadMovies();
  }

  // ----------------------------------------------------------
  // LOAD MOVIES
  // ----------------------------------------------------------

  Future<void> loadMovies() async {
    try {
      final data = await dbHelper.getAllMovies();

      if (!mounted) return;

      setState(() {
        movies = data;
      });
    } catch (e) {
      debugPrint('LOAD MOVIES ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load movies: $e'),
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // 8+ RATING FILTER
  // ----------------------------------------------------------

  List<Movie> get filteredMovies {
    if (onlyHighRated) {
      return movies.where((movie) => movie.rating >= 8).toList();
    }

    return movies;
  }

  // ----------------------------------------------------------
  // ADD / EDIT MOVIE
  // ----------------------------------------------------------

  void showAddMovieDialog() {
    showMovieDialog();
  }

  void showEditMovieDialog(Movie movie) {
    showMovieDialog(movie: movie);
  }

  Future<void> showMovieDialog({Movie? movie}) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MovieFormDialog(movie: movie),
    );

    if (saved != true) return;

    await loadMovies();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          movie == null
              ? 'Movie added successfully!'
              : 'Movie updated successfully!',
        ),
      ),
    );
  }

  // ----------------------------------------------------------
  // DELETE MOVIE
  // ----------------------------------------------------------

  Future<void> removeMovie(Movie movie) async {
    if (movie.id == null) return;

    try {
      await dbHelper.deleteMovie(movie.id!);

      await loadMovies();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Movie deleted successfully!'),
        ),
      );
    } catch (e) {
      debugPrint('REMOVE MOVIE ERROR: $e');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete movie: $e'),
        ),
      );
    }
  }

  // ----------------------------------------------------------
  // USER INTERFACE
  // ----------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleMovies = filteredMovies;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Notes: Movies'),

        actions: [
          IconButton(
            tooltip: widget.isDarkMode ? 'Light Mode' : 'Dark Mode',
            icon: Icon(
              widget.isDarkMode ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: widget.onToggleTheme,
          ),
        ],
      ),

      body: Column(
        children: [
          // Filter chip.
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: const Text('8+ Rating Only'),
                avatar: const Icon(Icons.star),
                selected: onlyHighRated,
                onSelected: (value) {
                  setState(() {
                    onlyHighRated = value;
                  });
                },
              ),
            ),
          ),

          // Movie list.
          Expanded(
            child: visibleMovies.isEmpty
                ? Center(
                    child: Text(
                      onlyHighRated
                          ? 'No movies rated 8 or above.'
                          : 'No movies yet. Add your first movie!',
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: visibleMovies.length,
                    itemBuilder: (context, index) {
                      final movie = visibleMovies[index];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),

                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text('${movie.rating}'),
                          ),

                          title: Text(movie.title),

                          subtitle: Text('Rating: ${movie.rating}/10'),

                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'edit') {
                                showEditMovieDialog(movie);
                              } else if (value == 'delete') {
                                removeMovie(movie);
                              }
                            },

                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit'),
                              ),

                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Delete'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),

      // Floating button to add a movie.
      floatingActionButton: FloatingActionButton(
        onPressed: showAddMovieDialog,
        tooltip: 'Add Movie',
        child: const Icon(Icons.add),
      ),
    );
  }
}
