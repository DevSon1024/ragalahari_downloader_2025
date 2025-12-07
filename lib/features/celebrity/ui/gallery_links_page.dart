import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:convert';
import 'dart:isolate';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/celebrity_utils.dart';
import '../../downloader/ui/ragadl_page.dart';
import 'package:ragadl/shared/widgets/grid_utils.dart';

// Data class for passing data to isolate
class GalleryScrapingData {
  final String profileUrl;
  final Map<String, String> headers;
  final List<String> thumbnailDomains;

  GalleryScrapingData({
    required this.profileUrl,
    required this.headers,
    required this.thumbnailDomains,
  });
}

// Data class for batch scraping
class BatchScrapingData {
  final List<String> urls;
  final Map<String, String> headers;
  final List<String> thumbnailDomains;

  BatchScrapingData({
    required this.urls,
    required this.headers,
    required this.thumbnailDomains,
  });
}

// Data class for isolate results
class GalleryScrapingResult {
  final List<String>? urls;
  final List<GalleryItem>? items;
  final String? error;

  GalleryScrapingResult({
    this.urls,
    this.items,
    this.error,
  });
}

class GalleryLinksPage extends StatefulWidget {
  final String celebrityName;
  final String profileUrl;
  final DownloadSelectedCallback? onDownloadSelected;

  const GalleryLinksPage({
    super.key,
    required this.celebrityName,
    required this.profileUrl,
    this.onDownloadSelected,
  });

  @override
  _GalleryLinksPageState createState() => _GalleryLinksPageState();
}

class _GalleryLinksPageState extends State<GalleryLinksPage> {
  List<String> _allGalleryUrls = [];
  Map<String, GalleryItem> _loadedItems = {};
  List<String> _filteredUrls = [];
  bool _isLoadingUrls = true;
  String? _error;
  int _currentPage = 1;
  final int _itemsPerPage = 30;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Set<int> _loadingPages = {};
  Set<int> _loadedPages = {};
  bool _isCelebrityFavorite = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
    _searchController.addListener(_filterGalleries);
    _checkCelebrityFavorite();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkCelebrityFavorite() async {
    final isFav = await _isCelebrityInFavorites();
    setState(() {
      _isCelebrityFavorite = isFav;
    });
  }

  Future<bool> _isCelebrityInFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteKey = 'favorites';
    final favoritesJson = prefs.getStringList(favoriteKey) ?? [];
    final favorites = favoritesJson
        .map((json) => FavoriteItem.fromJson(
      Map<String, String>.from(jsonDecode(json) as Map<String, dynamic>),
    ))
        .toList();
    return favorites.any(
          (item) =>
      item.type == 'celebrity' &&
          item.name == widget.celebrityName &&
          item.url == widget.profileUrl,
    );
  }

  Future<void> _toggleCelebrityFavorite() async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteKey = 'favorites';
    List<String> favoritesJson = prefs.getStringList(favoriteKey) ?? [];
    List<FavoriteItem> favorites = favoritesJson
        .map((json) => FavoriteItem.fromJson(
      Map<String, String>.from(jsonDecode(json) as Map<String, dynamic>),
    ))
        .toList();

    final favoriteItem = FavoriteItem(
      type: 'celebrity',
      name: widget.celebrityName,
      url: widget.profileUrl,
      thumbnailUrl: null,
      celebrityName: widget.celebrityName,
    );

    final isFavorite = favorites.any(
          (fav) =>
      fav.type == 'celebrity' &&
          fav.name == widget.celebrityName &&
          fav.url == widget.profileUrl,
    );

    if (isFavorite) {
      favorites.removeWhere(
            (fav) =>
        fav.type == 'celebrity' &&
            fav.name == widget.celebrityName &&
            fav.url == widget.profileUrl,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.celebrityName} removed from favorites'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      favorites.add(favoriteItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${widget.celebrityName} added to favorites'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }

    await prefs.setStringList(
      favoriteKey,
      favorites.map((item) => jsonEncode(item.toJson())).toList(),
    );

    setState(() {
      _isCelebrityFavorite = !isFavorite;
    });
  }

  Future<void> _loadAllData() async {
    // Load cached URLs and items
    await _loadCachedUrls();
    await _loadCachedItems();

    if (_allGalleryUrls.isNotEmpty) {
      setState(() {
        _filteredUrls = List.from(_allGalleryUrls);
        _isLoadingUrls = false;
      });
      // Load current page items
      _loadPageItems(_currentPage);
    }

    // Fetch fresh URLs in background
    _fetchGalleryUrls();
  }

  Future<void> _loadCachedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'gallery_urls_${widget.profileUrl.hashCode}';
    final cachedData = prefs.getString(cacheKey);
    if (cachedData != null) {
      final List<dynamic> jsonData = jsonDecode(cachedData);
      _allGalleryUrls = jsonData.cast<String>();
    }
  }

  Future<void> _loadCachedItems() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'gallery_items_${widget.profileUrl.hashCode}';
    final cachedData = prefs.getString(cacheKey);
    if (cachedData != null) {
      final Map<String, dynamic> jsonData = jsonDecode(cachedData);
      _loadedItems = jsonData.map((url, data) => MapEntry(
        url,
        GalleryItem(
          url: data['url'],
          title: data['title'],
          thumbnailUrl: data['thumbnailUrl'],
          pages: data['pages'],
          date: DateTime.parse(data['date']),
        ),
      ));
    }
  }

  Future<void> _cacheUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'gallery_urls_${widget.profileUrl.hashCode}';
    await prefs.setString(cacheKey, jsonEncode(_allGalleryUrls));
  }

  Future<void> _cacheItems() async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'gallery_items_${widget.profileUrl.hashCode}';
    final jsonData = _loadedItems.map((url, item) => MapEntry(
      url,
      {
        'url': item.url,
        'title': item.title,
        'thumbnailUrl': item.thumbnailUrl,
        'pages': item.pages,
        'date': item.date.toIso8601String(),
      },
    ));
    await prefs.setString(cacheKey, jsonEncode(jsonData));
  }

  Future<void> _fetchGalleryUrls() async {
    try {
      final receivePort = ReceivePort();

      receivePort.listen((message) {
        if (message is GalleryScrapingResult) {
          if (message.error != null) {
            setState(() {
              _error = message.error;
              _isLoadingUrls = false;
            });
          } else if (message.urls != null) {
            setState(() {
              _allGalleryUrls = message.urls!;
              _filteredUrls = List.from(_allGalleryUrls);
              _isLoadingUrls = false;
            });
            _cacheUrls();
            // Load current page items if not already loaded
            if (!_loadedPages.contains(_currentPage)) {
              _loadPageItems(_currentPage);
            }
          }
        }
        receivePort.close();
      });

      final scrapingData = GalleryScrapingData(
        profileUrl: widget.profileUrl,
        headers: headers,
        thumbnailDomains: thumbnailDomains,
      );

      await Isolate.spawn(
        _fetchUrlsIsolate,
        [receivePort.sendPort, scrapingData],
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to fetch gallery URLs: $e';
        _isLoadingUrls = false;
      });
    }
  }

  static Future<void> _fetchUrlsIsolate(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final GalleryScrapingData data = args[1];

    try {
      final response = await http
          .get(Uri.parse(data.profileUrl), headers: data.headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        sendPort.send(GalleryScrapingResult(
          error: 'Failed to load page: ${response.statusCode}',
        ));
        return;
      }

      final document = html_parser.parse(response.body);
      final urls = _extractGalleryLinksIsolate(document, data.profileUrl);

      sendPort.send(GalleryScrapingResult(urls: urls));
    } catch (e) {
      sendPort.send(GalleryScrapingResult(error: 'Failed to fetch URLs: $e'));
    }
  }

  static List<String> _extractGalleryLinksIsolate(
      dom.Document document, String profileUrl) {
    final galleriesPanel = document.getElementById('galleries_panel');
    if (galleriesPanel == null) return [];

    return galleriesPanel
        .getElementsByClassName('galimg')
        .map((element) => element.attributes['href'] ?? '')
        .where((href) => href.isNotEmpty)
        .map((href) => Uri.parse(profileUrl).resolve(href).toString())
        .toList();
  }

  Future<void> _loadPageItems(int page) async {
    if (_loadingPages.contains(page) || _loadedPages.contains(page)) {
      return;
    }

    setState(() {
      _loadingPages.add(page);
    });

    final startIndex = (page - 1) * _itemsPerPage;
    final endIndex = min(startIndex + _itemsPerPage, _filteredUrls.length);
    final pageUrls = _filteredUrls.sublist(startIndex, endIndex);

    // Filter out already loaded items
    final urlsToLoad = pageUrls.where((url) => !_loadedItems.containsKey(url)).toList();

    if (urlsToLoad.isEmpty) {
      setState(() {
        _loadingPages.remove(page);
        _loadedPages.add(page);
      });
      return;
    }

    try {
      final receivePort = ReceivePort();

      receivePort.listen((message) {
        if (message is GalleryScrapingResult) {
          if (message.items != null) {
            setState(() {
              for (final item in message.items!) {
                _loadedItems[item.url] = item;
              }
              _loadingPages.remove(page);
              _loadedPages.add(page);
            });
            _cacheItems();
          } else if (message.error != null) {
            setState(() {
              _loadingPages.remove(page);
            });
          }
        }
        receivePort.close();
      });

      final batchData = BatchScrapingData(
        urls: urlsToLoad,
        headers: headers,
        thumbnailDomains: thumbnailDomains,
      );

      await Isolate.spawn(
        _loadBatchIsolate,
        [receivePort.sendPort, batchData],
      );
    } catch (e) {
      setState(() {
        _loadingPages.remove(page);
      });
    }
  }

  static Future<void> _loadBatchIsolate(List<dynamic> args) async {
    final SendPort sendPort = args[0];
    final BatchScrapingData data = args[1];

    try {
      final futures = data.urls
          .map((url) => _processSingleLinkIsolate(url, data.headers, data.thumbnailDomains))
          .toList();

      final results = await Future.wait(futures);
      final items = results.whereType<GalleryItem>().toList();

      sendPort.send(GalleryScrapingResult(items: items));
    } catch (e) {
      sendPort.send(GalleryScrapingResult(error: 'Failed to load batch: $e'));
    }
  }

  static Future<GalleryItem?> _processSingleLinkIsolate(
      String link,
      Map<String, String> headers,
      List<String> thumbnailDomains) async {
    try {
      final response = await http
          .get(Uri.parse(link), headers: headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);

      String title = '';
      final titleElement = document.querySelector('h1.gallerytitle') ??
          document.querySelector('.gallerytitle') ??
          document.querySelector('h1');

      if (titleElement != null && titleElement.text.trim().isNotEmpty) {
        title = titleElement.text.trim();
      } else {
        final uri = Uri.parse(link);
        final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        title = link.split('/').last.replaceAll(".aspx", "");
        if (pathSegments.length > 2) {
          title = '${pathSegments[pathSegments.length - 2]}-${pathSegments.last.replaceAll(".aspx", "")}';
        }
      }

      String? thumbnailUrl;
      final images = document.getElementsByTagName('img');
      for (final img in images) {
        final src = img.attributes['src'] ?? img.attributes['data-src'] ?? '';
        if (thumbnailDomains.any((domain) => src.contains(domain))) {
          thumbnailUrl = src;
          break;
        }
      }

      final (pages, date) = await _getGalleryInfoIsolate(link, headers);

      return GalleryItem(
        url: link,
        title: title,
        thumbnailUrl: thumbnailUrl,
        pages: pages,
        date: date,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<(int, DateTime)> _getGalleryInfoIsolate(
      String url, Map<String, String> headers) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return (1, DateTime(1900));

      final document = html_parser.parse(response.body);

      final pageLinks = document.getElementsByClassName('otherPage');
      final lastPage = pageLinks.isEmpty
          ? 1
          : pageLinks.map((e) => int.tryParse(e.text.trim()) ?? 1).reduce(max);

      final dateElement = document.querySelector('.gallerydate time');
      final dateStr = dateElement?.text.trim() ?? '';
      final date = dateStr.startsWith('Updated on ')
          ? DateFormat('MMMM dd, yyyy').parse(dateStr.substring(11))
          : DateTime.now();

      return (lastPage, date);
    } catch (e) {
      return (1, DateTime(1900));
    }
  }

  Future<void> _toggleGalleryFavorite(GalleryItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteKey = 'favorites';
    List<String> favoritesJson = prefs.getStringList(favoriteKey) ?? [];
    List<FavoriteItem> favorites = favoritesJson
        .map((json) => FavoriteItem.fromJson(
      Map<String, String>.from(jsonDecode(json) as Map<String, dynamic>),
    ))
        .toList();

    final favoriteItem = FavoriteItem(
      type: 'gallery',
      name: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      celebrityName: widget.celebrityName,
    );

    final isFavorite = favorites.any(
          (fav) =>
      fav.type == 'gallery' &&
          fav.url == item.url &&
          fav.celebrityName == widget.celebrityName,
    );

    if (isFavorite) {
      favorites.removeWhere(
            (fav) =>
        fav.type == 'gallery' &&
            fav.url == item.url &&
            fav.celebrityName == widget.celebrityName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} removed from favorites')),
        );
      }
    } else {
      favorites.add(favoriteItem);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} added to favorites')),
        );
      }
    }

    await prefs.setStringList(
      favoriteKey,
      favorites.map((item) => jsonEncode(item.toJson())).toList(),
    );
    setState(() {});
  }

  void _navigateToDownloader(String galleryUrl, String galleryTitle) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RagaDL(
          initialUrl: galleryUrl,
          initialFolder: widget.celebrityName,
        ),
      ),
    );
  }

  void _filterGalleries() {
    final query = _searchController.text.trim();
    setState(() {
      if (query.isEmpty) {
        _filteredUrls = List.from(_allGalleryUrls);
      } else {
        _filteredUrls = _allGalleryUrls.where((url) {
          final galleryId = url
              .split('/')
              .where((segment) => RegExp(r'^\d+$').hasMatch(segment))
              .firstOrNull;
          return galleryId != null && galleryId.startsWith(query);
        }).toList();
      }
      _currentPage = 1;
      _loadedPages.clear();
      _loadPageItems(_currentPage);
    });
  }

  void _changePage(int page) {
    setState(() {
      _currentPage = page;
    });
    _loadPageItems(page);
  }

  Widget _buildGalleryCard(String url, {bool isPlaceholder = false}) {
    final theme = Theme.of(context);
    final item = _loadedItems[url];

    if (item == null || isPlaceholder) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Shimmer.fromColors(
          baseColor: theme.colorScheme.surfaceContainerHighest,
          highlightColor: theme.colorScheme.surfaceContainerLow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 14,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 12,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.grey,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<bool>(
      future: _isGalleryFavorite(item.url),
      builder: (context, snapshot) {
        final isFavorite = snapshot.data ?? false;
        return GestureDetector(
          onTap: () => _navigateToDownloader(item.url, item.title),
          onLongPress: () => _toggleGalleryFavorite(item),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            color: isFavorite
                ? theme.colorScheme.primaryContainer.withOpacity(0.3)
                : theme.colorScheme.surface,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: item.thumbnailUrl != null &&
                            item.thumbnailUrl!.isNotEmpty
                            ? Image.network(
                          item.thumbnailUrl!,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                      loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: theme.colorScheme.errorContainer,
                            child: Icon(
                              Icons.broken_image,
                              size: 60,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        )
                            : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.image_not_supported,
                            size: 60,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.photo_library_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${item.pages} Page(s)',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      DateFormat('MMM dd, yyyy').format(item.date),
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: () => _toggleGalleryFavorite(item),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        color: isFavorite ? Colors.amber : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _isGalleryFavorite(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final favoriteKey = 'favorites';
    final favoritesJson = prefs.getStringList(favoriteKey) ?? [];
    final favorites = favoritesJson
        .map((json) => FavoriteItem.fromJson(
      Map<String, String>.from(jsonDecode(json) as Map<String, dynamic>),
    ))
        .toList();
    return favorites.any(
          (item) =>
      item.type == 'gallery' &&
          item.url == url &&
          item.celebrityName == widget.celebrityName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalPages = (_filteredUrls.length / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = min(startIndex + _itemsPerPage, _filteredUrls.length);
    final currentPageUrls = _filteredUrls.sublist(startIndex, endIndex);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.celebrityName} - Galleries',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isCelebrityFavorite ? Icons.star : Icons.star_border,
              color: _isCelebrityFavorite ? Colors.amber : null,
            ),
            tooltip: _isCelebrityFavorite
                ? 'Remove from Favorites'
                : 'Add to Favorites',
            onPressed: _toggleCelebrityFavorite,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search by gallery code...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _searchFocusNode.unfocus();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainer,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              keyboardType: TextInputType.number,
              autofocus: false,
            ),
          ),
        ),
      ),
      body: _error != null
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      )
          : _isLoadingUrls
          ? const Center(child: CircularProgressIndicator())
          : _filteredUrls.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No galleries found',
              style: theme.textTheme.bodyLarge,
            ),
          ],
        ),
      )
          : Column(
        children: [
          if (_loadingPages.contains(_currentPage))
            LinearProgressIndicator(
              backgroundColor: theme.colorScheme.surfaceContainer,
            ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: calculateGridColumns(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: currentPageUrls.length,
              itemBuilder: (context, index) {
                final url = currentPageUrls[index];
                return _buildGalleryCard(
                  url,
                  isPlaceholder: !_loadedItems.containsKey(url),
                );
              },
            ),
          ),
          if (totalPages > 1)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed: _currentPage > 1
                        ? () => _changePage(_currentPage - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'Page $_currentPage of $totalPages',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton.filledTonal(
                    onPressed: _currentPage < totalPages
                        ? () => _changePage(_currentPage + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}