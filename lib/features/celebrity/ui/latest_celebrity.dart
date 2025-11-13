import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html show parse;
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:ragadl/shared/widgets/grid_utils.dart';
import '../../downloader/ui/ragadl_page.dart';
import '../data/profile_cache_service.dart';
import 'gallery_links_page.dart';

class LatestCelebrityPage extends StatefulWidget {
  const LatestCelebrityPage({super.key});

  @override
  _LatestCelebrityPageState createState() => _LatestCelebrityPageState();
}

class _LatestCelebrityPageState extends State<LatestCelebrityPage> {
  final String baseUrl = 'https://www.ragalahari.com';
  final String targetUrl = 'https://www.ragalahari.com/starzone.aspx';
  List<Map<String, String>> celebrityList = [];
  bool isLoading = true;
  Map<int, bool> loadingProfileLinks = {};

  @override
  void initState() {
    super.initState();
    fetchStarzoneLinks();
  }

  Future<void> fetchStarzoneLinks() async {
    try {
      final response = await http.get(Uri.parse(targetUrl));
      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final columns = document.getElementsByClassName('column');

        List<Map<String, String>> tempList = [];

        for (var col in columns) {
          final aTag = col.querySelector('a.galimg');
          final imgTag = aTag?.querySelector('img');
          final h5Tag = col.querySelector('h5.galleryname a.galleryname');
          final h6Tag = col.querySelector('h6.gallerydate');

          final imgSrc = imgTag?.attributes['src'] ?? '';
          if (!imgSrc.endsWith('thumb.jpg')) continue;

          final partialUrl = aTag?.attributes['href'] ?? '';
          final fullUrl =
          partialUrl.startsWith('/') ? baseUrl + partialUrl : partialUrl;
          final galleryTitle = h5Tag?.text.trim() ?? '';
          final galleryDate = h6Tag?.text.trim() ?? '';

          tempList.add({
            'url': fullUrl,
            'img': imgSrc,
            'title': galleryTitle,
            'date': galleryDate,
            'name': '',
            'profileLink': '',
          });
        }

        setState(() {
          celebrityList = tempList;
          isLoading = false;
        });
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> fetchCelebrityName(int index) async {
    final item = celebrityList[index];
    final url = item['url']!;

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final breadcrumb = document.querySelector('ul.breadcrumbs');
        if (breadcrumb != null) {
          final links = breadcrumb.querySelectorAll('li a');
          for (var link in links) {
            final href = link.attributes['href'] ?? '';
            if (href.startsWith('https://www.ragalahari.com/stars/profile/')) {
              final name = link.text.trim();
              setState(() {
                celebrityList[index]['name'] = name;
                celebrityList[index]['profileLink'] = href;
              });

              // Cache the profile link
              await ProfileCacheService.saveProfileLink(url, href);

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RagaDL(
                    initialUrl: url,
                    initialFolder: name,
                  ),
                ),
              );
              break;
            }
          }
        }
      }
    } catch (e) {
      print('Detail fetch error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load celebrity name: $e')),
      );
    }
  }

  Future<void> fetchAndNavigateToProfile(int index) async {
    final item = celebrityList[index];
    final galleryUrl = item['url']!;

    setState(() {
      loadingProfileLinks[index] = true;
    });

    try {
      // Check cache first
      String? cachedProfileLink = await ProfileCacheService.getProfileLink(galleryUrl);
      String? celebrityName;

      if (cachedProfileLink != null) {
        // Extract name from cached profile link
        celebrityName = _extractCelebrityNameFromUrl(cachedProfileLink);

        setState(() {
          celebrityList[index]['profileLink'] = cachedProfileLink;
          celebrityList[index]['name'] = celebrityName ?? 'Unknown';
          loadingProfileLinks[index] = false;
        });

        if (celebrityName != null) {
          _navigateToGalleryLinks(cachedProfileLink, celebrityName);
          return;
        }
      }

      // Fetch from web if not cached
      final response = await http.get(Uri.parse(galleryUrl));
      if (response.statusCode == 200) {
        final document = html.parse(response.body);
        final breadcrumb = document.querySelector('ul.breadcrumbs');

        if (breadcrumb != null) {
          final links = breadcrumb.querySelectorAll('li a');
          for (var link in links) {
            final href = link.attributes['href'] ?? '';
            if (href.startsWith('https://www.ragalahari.com/stars/profile/')) {
              final name = link.text.trim();

              setState(() {
                celebrityList[index]['name'] = name;
                celebrityList[index]['profileLink'] = href;
                loadingProfileLinks[index] = false;
              });

              // Cache the profile link
              await ProfileCacheService.saveProfileLink(galleryUrl, href);

              _navigateToGalleryLinks(href, name);
              return;
            }
          }
        }
      }

      setState(() {
        loadingProfileLinks[index] = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile link not found')),
      );
    } catch (e) {
      setState(() {
        loadingProfileLinks[index] = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load profile: $e')),
      );
    }
  }

  String? _extractCelebrityNameFromUrl(String profileUrl) {
    try {
      // Extract from URL: https://www.ragalahari.com/stars/profile/97688/ashika-ranganath.aspx
      final urlParts = profileUrl.split('/');
      if (urlParts.isNotEmpty) {
        final lastPart = urlParts.last.replaceAll('.aspx', '');
        final nameParts = lastPart.split('-');
        // Convert hyphenated name to proper case
        return nameParts.map((part) =>
        part[0].toUpperCase() + part.substring(1)).join(' ');
      }
    } catch (e) {
      print('Error extracting celebrity name: $e');
    }
    return null;
  }

  void _navigateToGalleryLinks(String profileLink, String celebrityName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryLinksPage(
          profileUrl: profileLink,
          celebrityName: celebrityName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Latest Celebrities',
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: isLoading
          ? _buildShimmerGrid()
          : GridView.builder(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: calculateGridColumns(context),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.65,
        ),
        itemCount: celebrityList.length,
        itemBuilder: (context, index) {
          final item = celebrityList[index];
          final isLoadingProfile = loadingProfileLinks[index] ?? false;

          return Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => fetchCelebrityName(index),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: item['img'] ?? '',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        placeholder: (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                        errorWidget: (context, url, error) =>
                        const Icon(Icons.error),
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
                        item['title'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item['date'] ?? '',
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: isLoadingProfile
                              ? null
                              : () => fetchAndNavigateToProfile(index),
                          icon: isLoadingProfile
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                              : const Icon(Icons.grid_view, size: 16),
                          label: Text(
                            isLoadingProfile
                                ? 'Loading...'
                                : 'Show Galleries',
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 100),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: calculateGridColumns(context),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.65,
      ),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16),
                      ),
                    ),
                    width: double.infinity,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: 80,
                        height: 12,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        height: 32,
                        color: Colors.grey[300],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
