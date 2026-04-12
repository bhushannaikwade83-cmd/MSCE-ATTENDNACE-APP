import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/storage_service.dart';
import 'shimmer_effect.dart';

/// Secure network image widget that handles B2 signed URLs and 401 errors
/// Automatically retries with fresh authorization if URL is unsigned or returns 401
class SecureNetworkImage extends StatefulWidget {
  final String? imageUrl;
  final String? storagePath; // Alternative: storage path to generate URL from
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final Color? backgroundColor;

  const SecureNetworkImage({
    super.key,
    this.imageUrl,
    this.storagePath,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.backgroundColor,
  }) : assert(imageUrl != null || storagePath != null, 'Either imageUrl or storagePath must be provided');

  @override
  State<SecureNetworkImage> createState() => _SecureNetworkImageState();
}

class _SecureNetworkImageState extends State<SecureNetworkImage> {
  String? _currentUrl;
  bool _isRetrying = false;
  int _retryCount = 0;
  static const int _maxRetries = 2;

  @override
  void initState() {
    super.initState();
    _loadPhotoUrl();
  }

  @override
  void didUpdateWidget(SecureNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl || oldWidget.storagePath != widget.storagePath) {
      _retryCount = 0;
      _loadPhotoUrl();
    }
  }

  Future<void> _loadPhotoUrl() async {
    // Use the automatic temporary URL generation method
    // This handles all cases: storagePath, photoUrl (signed/unsigned), etc.
    try {
      final urlToUse = await StorageService.getTemporaryPhotoUrl(
        photoUrl: widget.imageUrl,
        storagePath: widget.storagePath,
      );

      if (mounted) {
        setState(() {
          _currentUrl = urlToUse;
          _isRetrying = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Error generating temporary photo URL: $e');
      if (mounted) {
        setState(() {
          _currentUrl = null;
          _isRetrying = false;
        });
      }
    }
  }

  Future<void> _retryWithFreshAuth(String? failedUrl) async {
    if (_retryCount >= _maxRetries || _isRetrying) return;

    setState(() {
      _isRetrying = true;
      _retryCount++;
    });

    try {
      // Wait a bit before retry (exponential backoff)
      await Future.delayed(Duration(milliseconds: 500 * _retryCount));
      
      // Use the automatic temporary URL generation method for retry
      // This handles all cases automatically
      final urlToRetry = await StorageService.getTemporaryPhotoUrl(
        photoUrl: failedUrl ?? widget.imageUrl,
        storagePath: widget.storagePath,
      );

      if (urlToRetry != null && urlToRetry.isNotEmpty && mounted) {
        setState(() {
          _currentUrl = urlToRetry;
          _isRetrying = false;
        });
      } else if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('❌ Retry failed (attempt $_retryCount/$_maxRetries): $e');
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show placeholder while loading or retrying
    if (_currentUrl == null || _currentUrl!.isEmpty || _isRetrying) {
      return widget.placeholder ??
          ShimmerEffect(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            borderRadius: BorderRadius.circular(8),
          );
    }

    return CachedNetworkImage(
      imageUrl: _currentUrl!,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      placeholder: (context, url) => widget.placeholder ??
          ShimmerEffect(
            width: widget.width ?? double.infinity,
            height: widget.height ?? double.infinity,
            borderRadius: BorderRadius.circular(8),
          ),
      errorWidget: (context, url, error) {
        final errorStr = error.toString();
        
        // Check if it's a 401 error for B2 URL
        if (errorStr.contains('401') && 
            url != null && 
            url.toString().contains('backblazeb2.com') &&
            _retryCount < _maxRetries) {
          
          // Retry with fresh authorization
          _retryWithFreshAuth(url.toString());
          
          // Show loading while retrying
          return widget.placeholder ??
              Container(
                width: widget.width,
                height: widget.height,
                color: widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              );
        }

        // Show error widget after all retries failed
        return widget.errorWidget ??
            Container(
              width: widget.width,
              height: widget.height,
              color: widget.backgroundColor ?? Colors.white.withValues(alpha: 0.1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Failed to load',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
      },
    );
  }
}
