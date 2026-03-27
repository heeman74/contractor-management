import 'package:flutter/material.dart';

import '../../../jobs/domain/attachment_entity.dart';

/// Full-screen photo gallery viewer with pinch-to-zoom and swipe navigation.
///
/// Navigated to via [RouteNames.photoViewer] with extra params:
///   - `photos`: List&lt;AttachmentEntity&gt; with non-null remoteUrl
///   - `initialIndex`: int index into photos list to start at
///
/// Features:
///   - Swipe left/right to browse between photos via [PageView]
///   - Pinch-to-zoom via [InteractiveViewer]
///   - "X of Y" counter in AppBar updates on swipe
///   - Caption overlay at bottom when [AttachmentEntity.caption] is set
///   - "Long press to save" snackbar on download button tap
class PhotoViewerScreen extends StatefulWidget {
  final List<AttachmentEntity> photos;
  final int initialIndex;

  const PhotoViewerScreen({
    required this.photos, required this.initialIndex, super.key,
  });

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];
    final hasCaption = photo.caption != null && photo.caption!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.7),
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} of ${widget.photos.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, color: Colors.white),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Long press the photo to save it.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Save photo',
          ),
        ],
      ),
      body: Stack(
        children: [
          // Photo gallery with swipe (PageView) and pinch-to-zoom (InteractiveViewer)
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final p = widget.photos[index];
              return InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(
                  child: Image.network(
                    p.remoteUrl!,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image,
                                color: Colors.white54, size: 64),
                            SizedBox(height: 8),
                            Text(
                              'Could not load image',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      );
                    },
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white,
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),

          // Caption overlay at bottom
          if (hasCaption)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Text(
                  photo.caption!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
