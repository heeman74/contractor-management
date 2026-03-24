import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart'
    hide UserRole, BookingDao, NoteDao, AttachmentDao, TimeEntryDao,
        QuoteDao, InvoiceDao;
import '../../../../core/routing/route_names.dart';

/// Full-screen photo viewer for task photos with an annotate action.
///
/// Accepts [attachment] (the initially displayed photo), [allPhotos]
/// (full list for swipe navigation), and [initialIndex].
///
/// Tapping "Annotate" navigates to the photo annotation screen.
class TaskPhotoViewerScreen extends StatefulWidget {
  const TaskPhotoViewerScreen({
    required this.taskId,
    required this.attachment,
    required this.allPhotos,
    required this.initialIndex,
    super.key,
  });

  final String taskId;
  final TaskAttachment attachment;
  final List<TaskAttachment> allPhotos;
  final int initialIndex;

  @override
  State<TaskPhotoViewerScreen> createState() => _TaskPhotoViewerScreenState();
}

class _TaskPhotoViewerScreenState extends State<TaskPhotoViewerScreen> {
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

  TaskAttachment get _currentAttachment => widget.allPhotos[_currentIndex];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.allPhotos.length}',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          Semantics(
            label: 'Annotate this photo',
            child: TextButton.icon(
              icon: const Icon(Icons.edit, color: Colors.white),
              label: const Text(
                'Annotate',
                style: TextStyle(color: Colors.white),
              ),
              onPressed: () {
                context.push(
                  RouteNames.photoAnnotationPath(
                    widget.taskId,
                    _currentAttachment.id,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.allPhotos.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final photo = widget.allPhotos[index];
          return Center(
            child: InteractiveViewer(
              child: _buildPhoto(photo),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhoto(TaskAttachment photo) {
    if (photo.localPath != null && File(photo.localPath!).existsSync()) {
      return Image.file(
        File(photo.localPath!),
        fit: BoxFit.contain,
        errorBuilder: (context, error, _) => const Icon(
          Icons.broken_image,
          color: Colors.white54,
          size: 64,
        ),
      );
    }
    if (photo.remoteUrl != null) {
      return Image.network(
        photo.remoteUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const CircularProgressIndicator(color: Colors.white);
        },
        errorBuilder: (context, error, _) => const Icon(
          Icons.broken_image,
          color: Colors.white54,
          size: 64,
        ),
      );
    }
    return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
  }
}
