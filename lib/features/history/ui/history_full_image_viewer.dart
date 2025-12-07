import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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
          (_) => TransformationController(),
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

  void _precacheAdjacentImages(int currentIndex) {
    final len = widget.images.length;
    final indicesToCache = <int>[];

    indicesToCache.add(currentIndex);
    if (currentIndex > 0) indicesToCache.add(currentIndex - 1);
    if (currentIndex > 1) indicesToCache.add(currentIndex - 2);
    if (currentIndex < len - 1) indicesToCache.add(currentIndex + 1);
    if (currentIndex < len - 2) indicesToCache.add(currentIndex + 2);

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

    _cleanupDistantCache(currentIndex);
  }

  void _cleanupDistantCache(int currentIndex) {
    final indicesToRemove = <int>[];

    for (final cachedIndex in _imageCache.keys) {
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

  void _onInteractionUpdate(
      ScaleUpdateDetails details,
      TransformationController controller,
      ) {
    final scale = controller.value.getMaxScaleOnAxis();
    final newIsZoomed = scale > 1.1;

    if (newIsZoomed != _isZoomed) {
      setState(() {
        _isZoomed = newIsZoomed;
        if (_isZoomed && _showControls) {
          _showControls = false;
          _appBarAnimationController.reverse();
        }
      });
    }
  }

  void _onInteractionEnd(ScaleEndDetails details, int index) {
    final controller = _controllers[index];
    final scale = controller.value.getMaxScaleOnAxis();

    if (scale < 1.05 && scale > 0.95) {
      controller.value = Matrix4.identity();
      setState(() {
        _isZoomed = false;
        if (!_showControls) {
          _showControls = true;
          _appBarAnimationController.forward();
        }
      });
    }
  }

  void _handleDoubleTap(int index) {
    final controller = _controllers[index];
    final currentScale = controller.value.getMaxScaleOnAxis();
    final targetScale = currentScale > 1.5 ? 1.0 : 2.5;

    // Get screen center for zoom
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    final begin = controller.value;
    final end = targetScale == 1.0
        ? Matrix4.identity()
        : Matrix4.identity()
      ..translate(centerX, centerY)
      ..scale(targetScale)
      ..translate(-centerX, -centerY);

    final animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    final animation = Matrix4Tween(begin: begin, end: end).animate(
      CurvedAnimation(parent: animController, curve: Curves.easeOut),
    );

    animation.addListener(() {
      controller.value = animation.value;
    });

    animController.forward().then((_) {
      animController.dispose();
      setState(() {
        _isZoomed = targetScale > 1.0;
        if (_isZoomed && _showControls) {
          _showControls = false;
          _appBarAnimationController.reverse();
        } else if (!_isZoomed && !_showControls) {
          _showControls = true;
          _appBarAnimationController.forward();
        }
      });
    });

    HapticFeedback.mediumImpact();
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
          if (_showControls && !_isZoomed) _buildNavigationButtons(),
          if (_showControls) _buildBottomInfo(color),
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

        // Reset zoom for all other pages
        for (int j = 0; j < _controllers.length; j++) {
          if (j != i) {
            _controllers[j].value = Matrix4.identity();
          }
        }

        setState(() {
          _isZoomed = false;
          if (!_showControls) {
            _showControls = true;
            _appBarAnimationController.forward();
          }
        });

        HapticFeedback.selectionClick();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _precacheAdjacentImages(i);
          _isPageTransitioning = false;
        });
      },
      itemBuilder: (context, index) {
        return _buildImageItem(index);
      },
    );
  }

  Widget _buildImageItem(int index) {
    final controller = _controllers[index];

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Single tap - toggle controls only when not zoomed
        if (!_isZoomed) {
          _toggleControls();
        }
      },
      onDoubleTap: () {
        // Double tap - zoom in/out
        _handleDoubleTap(index);
      },
      child: InteractiveViewer(
        transformationController: controller,
        minScale: 1.0,
        maxScale: 5.0,
        panEnabled: _isZoomed,
        scaleEnabled: true,
        constrained: true,
        onInteractionUpdate: (details) =>
            _onInteractionUpdate(details, controller),
        onInteractionEnd: (details) => _onInteractionEnd(details, index),
        child: Hero(
          tag: widget.images[index].path,
          child: Center(
            child: _buildCachedImage(index),
          ),
        ),
      ),
    );
  }

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
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.white70),
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
                                  Row(
                                    children: [
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
                                      Text(
                                        ' • Tap: controls • Double tap: zoom',
                                        style: TextStyle(
                                          color: Colors.blue[300],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
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