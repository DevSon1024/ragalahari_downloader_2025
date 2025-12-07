import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:math';

class FullImageViewer extends StatefulWidget {
  final List<File> images;
  final int initialIndex;

  const FullImageViewer({
    super.key,
    required this.images,
    required this.initialIndex,
  });

  @override
  State<FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<FullImageViewer>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late ValueNotifier<int> _currentIndexNotifier;
  late List<TransformationController> _controllers;
  late AnimationController _appBarAnimationController;
  late AnimationController _fadeAnimationController;
  late Animation<double> _appBarAnimation;
  late Animation<double> _fadeAnimation;

  // Cache for loaded images
  final Map<int, ImageProvider> _imageCache = {};
  final Set<int> _precachedIndices = {};

  bool _firstBuild = true;
  bool _showControls = true;
  bool _isZoomed = false;
  bool _isPageTransitioning = false;

  @override
  void initState() {
    super.initState();
    _currentIndexNotifier = ValueNotifier(widget.initialIndex);
    _pageController = PageController(initialPage: widget.initialIndex);
    _controllers = List.generate(
        widget.images.length,
            (_) => TransformationController()
    );

    _appBarAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _appBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _appBarAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _appBarAnimationController.forward();
    _fadeAnimationController.forward();

    // Set up system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_firstBuild) {
      _firstBuild = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _precacheAdjacentImages(_currentIndexNotifier.value);
      });
    }
  }

  // Enhanced precaching with extended range and caching strategy
  void _precacheAdjacentImages(int currentIndex) {
    final len = widget.images.length;

    // Precache range: current ± 2 images for smoother scrolling
    final indicesToCache = <int>[];

    // Add current image
    indicesToCache.add(currentIndex);

    // Add previous images (up to 2)
    if (currentIndex > 0) indicesToCache.add(currentIndex - 1);
    if (currentIndex > 1) indicesToCache.add(currentIndex - 2);

    // Add next images (up to 2)
    if (currentIndex < len - 1) indicesToCache.add(currentIndex + 1);
    if (currentIndex < len - 2) indicesToCache.add(currentIndex + 2);

    // Precache images that haven't been cached yet
    for (final index in indicesToCache) {
      if (!_precachedIndices.contains(index)) {
        final imageProvider = FileImage(widget.images[index]);
        _imageCache[index] = imageProvider;

        precacheImage(imageProvider, context).then((_) {
          _precachedIndices.add(index);
        }).catchError((error) {
          debugPrint('Failed to precache image at index $index: $error');
        });
      }
    }

    // Clean up cache for distant images to save memory
    _cleanupDistantCache(currentIndex);
  }

  // Remove cached images that are too far from current position
  void _cleanupDistantCache(int currentIndex) {
    final indicesToRemove = <int>[];

    for (final cachedIndex in _imageCache.keys) {
      // Keep images within ±3 range
      if ((cachedIndex - currentIndex).abs() > 3) {
        indicesToRemove.add(cachedIndex);
      }
    }

    for (final index in indicesToRemove) {
      _imageCache.remove(index);
      _precachedIndices.remove(index);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    _currentIndexNotifier.dispose();
    _pageController.dispose();
    _appBarAnimationController.dispose();
    _fadeAnimationController.dispose();
    for (final controller in _controllers) {
      controller.dispose();
    }
    _imageCache.clear();
    _precachedIndices.clear();
    super.dispose();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _appBarAnimationController.forward();
    } else {
      _appBarAnimationController.reverse();
    }
  }

  Future<void> _shareImage() async {
    final idx = _currentIndexNotifier.value;
    final imagePath = widget.images[idx].path;
    HapticFeedback.mediumImpact();
    await Share.shareXFiles(
      [XFile(imagePath)],
      text: 'Sharing image from RagaDL',
    );
  }

  Future<void> _deleteImage() async {
    final idx = _currentIndexNotifier.value;
    final confirmed = await _showDeleteDialog();
    if (confirmed != true) return;

    HapticFeedback.heavyImpact();
    final imageFile = widget.images[idx];
    final newPath = imageFile.path.replaceFirst(
      RegExp(r'([^/]+)$'),
      '.trashed-${DateTime.now().millisecondsSinceEpoch}-${imageFile.path.split('/').last}',
    );

    try {
      await imageFile.rename(newPath);

      // Clean up cache for deleted image
      _imageCache.remove(idx);
      _precachedIndices.remove(idx);

      widget.images.removeAt(idx);
      _controllers.removeAt(idx);

      if (widget.images.isEmpty) {
        Navigator.pop(context);
      } else {
        final newLen = widget.images.length;
        final newIdx = idx >= newLen ? newLen - 1 : idx;
        _currentIndexNotifier.value = newIdx;
        setState(() {});
        _pageController.jumpToPage(newIdx);

        // Recache after deletion
        _precacheAdjacentImages(newIdx);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Image moved to recycle bin'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete image: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<bool?> _showDeleteDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Delete Image',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: const Text(
            'Are you sure you want to move this image to the recycle bin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
  }

  void _onScaleUpdate(
      ScaleUpdateDetails details,
      TransformationController controller,
      ) {
    final scale = controller.value.getMaxScaleOnAxis();
    final newIsZoomed = scale > 1.1;
    if (newIsZoomed != _isZoomed) {
      setState(() {
        _isZoomed = newIsZoomed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: _buildAnimatedAppBar(color),
      body: Stack(
        children: [
          _buildImagePageView(),
          if (_showControls) _buildBottomControls(color), // <-- USE NEW METHOD
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAnimatedAppBar(ColorScheme color) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: AnimatedBuilder(
        animation: _appBarAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(0, -kToolbarHeight * (1 - _appBarAnimation.value)),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.7 * _appBarAnimation.value),
                    Colors.transparent,
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: _buildGlassButton(
                  icon: Icons.arrow_back_rounded,
                  onPressed: () => Navigator.pop(context),
                ),
                title: ValueListenableBuilder<int>(
                  valueListenable: _currentIndexNotifier,
                  builder: (context, index, child) => Text(
                    '${index + 1} of ${widget.images.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                centerTitle: true,
                actions: [
                  _buildGlassButton(
                    icon: Icons.share_rounded,
                    onPressed: _shareImage,
                  ),
                  _buildGlassButton(
                    icon: Icons.delete_outline_rounded,
                    onPressed: _deleteImage,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomControls(ColorScheme color) {
    return AnimatedBuilder(
      animation: _appBarAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16,
          right: 16,
          child: Transform.translate(
            offset: Offset(0, 100 * (1 - _appBarAnimation.value)),
            child: Opacity(
              opacity: _appBarAnimation.value,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentIndexNotifier,
                builder: (context, index, child) {
                  final fileName = widget.images[index].path.split('/').last;
                  final totalImages = widget.images.length;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Part 1: File Info Box (from your original _buildBottomInfo)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.image_rounded,
                                    color: Colors.white70,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        fileName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      FutureBuilder<int>(
                                        future: widget.images[index].length(),
                                        builder: (context, snapshot) {
                                          if (snapshot.hasData) {
                                            final sizeKB =
                                            (snapshot.data! / 1024)
                                                .toStringAsFixed(1);
                                            return Text(
                                              '$sizeKB KB',
                                              style: TextStyle(
                                                color: Colors.white
                                                    .withOpacity(0.7),
                                                fontSize: 12,
                                              ),
                                            );
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Part 2: Navigation Slider (Inspired by PixChive)
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.1),
                              ),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_previous_rounded,
                                    color: index > 0
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                                  ),
                                  onPressed: index > 0
                                      ? () {
                                    _pageController.previousPage(
                                      duration: const Duration(
                                          milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                      : null,
                                ),
                                // --- FIX HERE ---
                                SizedBox(
                                  width: 32,
                                  child: Center(
                                    child: Text(
                                      "${index + 1}",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: index.toDouble(),
                                    min: 0,
                                    max: (totalImages - 1).toDouble(),
                                    // --- FIX HERE ---
                                    divisions: max(totalImages - 1, 1).toInt(),
                                    activeColor:
                                    Theme.of(context).colorScheme.primary,
                                    inactiveColor:
                                    Colors.white.withOpacity(0.3),
                                    onChanged: (value) {
                                      _pageController
                                          .jumpToPage(value.toInt());
                                    },
                                  ),
                                ),
                                // --- FIX HERE ---
                                SizedBox(
                                  width: 32,
                                  child: Center(
                                    child: Text(
                                      "$totalImages",
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.7),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.skip_next_rounded,
                                    color: index < totalImages - 1
                                        ? Colors.white
                                        : Colors.white.withOpacity(0.3),
                                  ),
                                  onPressed: index < totalImages - 1
                                      ? () {
                                    _pageController.nextPage(
                                      duration: const Duration(
                                          milliseconds: 300),
                                      curve: Curves.easeOutCubic,
                                    );
                                  }
                                      : null,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: IconButton(
              icon: Icon(icon, color: Colors.white, size: 20),
              onPressed: onPressed,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePageView() {
    return PageView.builder(
      controller: _pageController,
      itemCount: widget.images.length,
      physics: _isZoomed
          ? const NeverScrollableScrollPhysics()
          : const PageScrollPhysics(),
      onPageChanged: (int i) {
        _isPageTransitioning = true;
        _currentIndexNotifier.value = i;

        // Reset zoom for current page
        _controllers[i].value = Matrix4.identity();

        setState(() {
          _isZoomed = false;
        });

        HapticFeedback.selectionClick();

        // Precache adjacent images
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _precacheAdjacentImages(i);
          _isPageTransitioning = false;
        });
      },
      itemBuilder: (context, index) {
        final controller = _controllers[index];

        return InteractiveViewer(
          transformationController: controller,
          minScale: 1.0,
          maxScale: 4.0,
          panEnabled: true,
          scaleEnabled: true,
          onInteractionStart: (details) {
            if (details.pointerCount == 1) {
              _toggleControls();
            }
          },
          onInteractionUpdate: (details) => _onScaleUpdate(details, controller),
          child: GestureDetector(
            onDoubleTap: () {
              HapticFeedback.mediumImpact();
              final size = MediaQuery.of(context).size;
              final matrix = controller.value;
              final currentScale = matrix.getMaxScaleOnAxis();
              final targetScale = currentScale > 1.5 ? 1.0 : 2.5;

              if (targetScale == 1.0) {
                controller.value = Matrix4.identity();
              } else {
                final x = size.width / 2;
                final y = size.height / 2;
                controller.value = Matrix4.identity()
                  ..translate(x)
                  ..scale(targetScale)
                  ..translate(-x);
              }

              setState(() {
                _isZoomed = targetScale > 1.0;
              });
            },
            child: Hero(
              tag: widget.images[index].path,
              child: _buildCachedImage(index),
            ),
          ),
        );
      },
    );
  }

  // Build image with caching support
  Widget _buildCachedImage(int index) {
    final imageProvider = _imageCache[index] ?? FileImage(widget.images[index]);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Image(
        image: imageProvider,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) {
            return child;
          }

          // Show loading indicator while image loads
          return AnimatedOpacity(
            opacity: frame == null ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: frame == null
                ? Container(
              color: Colors.grey[900],
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                ),
              ),
            )
                : child,
          );
        },
        errorBuilder: (context, error, stackTrace) => Container(
          color: Colors.grey[900],
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white70,
                  size: 64,
                ),
                SizedBox(height: 16),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return ValueListenableBuilder<int>(
      valueListenable: _currentIndexNotifier,
      builder: (context, index, child) {
        return Stack(
          children: [
            if (index > 0)
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_left_rounded,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ),
            if (index < widget.images.length - 1)
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _buildNavigationButton(
                    icon: Icons.chevron_right_rounded,
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildNavigationButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white, size: 32),
            onPressed: onPressed,
            padding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomInfo(ColorScheme color) {
    return AnimatedBuilder(
      animation: _appBarAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: MediaQuery.of(context).padding.bottom + 16,
          left: 16,
          right: 16,
          child: Transform.translate(
            offset: Offset(0, 100 * (1 - _appBarAnimation.value)),
            child: Opacity(
              opacity: _appBarAnimation.value,
              child: ValueListenableBuilder<int>(
                valueListenable: _currentIndexNotifier,
                builder: (context, index, child) {
                  final fileName = widget.images[index].path.split('/').last;
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.image_rounded,
                                color: Colors.white70,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    fileName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  FutureBuilder<int>(
                                    future: widget.images[index].length(),
                                    builder: (context, snapshot) {
                                      if (snapshot.hasData) {
                                        final sizeKB =
                                        (snapshot.data! / 1024)
                                            .toStringAsFixed(1);
                                        return Text(
                                          '$sizeKB KB',
                                          style: TextStyle(
                                            color:
                                            Colors.white.withOpacity(0.7),
                                            fontSize: 12,
                                          ),
                                        );
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                ],
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
          ),
        );
      },
    );
  }
}