import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'copyable_snackbar.dart';

/// True when [uri] targets this app’s Firebase Storage bucket (uploaded attachments).
bool _isProjectFirebaseStorageDownloadUrl(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  if (uri.host.toLowerCase() != 'firebasestorage.googleapis.com') return false;
  if (Firebase.apps.isEmpty) return false;
  try {
    final bucket = Firebase.app().options.storageBucket?.trim() ?? '';
    if (bucket.isEmpty) return false;
    return uri.path.contains('/b/$bucket/');
  } catch (_) {
    return false;
  }
}

User? _firebaseUserIfAvailable() {
  if (Firebase.apps.isEmpty) return null;
  try {
    return FirebaseAuth.instance.currentUser;
  } catch (_) {
    return null;
  }
}

/// Opens [raw] in the browser / default handler when it looks like `http` / `https`.
///
/// Firebase Storage links for this project require a **signed-in** Firebase user so
/// logged-out people using the app cannot open uploaded attachments from here.
Future<void> openAttachmentUrl(BuildContext context, String raw) async {
  final t = raw.trim();
  if (t.isEmpty) return;
  final uri = Uri.tryParse(t);
  if (uri == null || !uri.hasScheme) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'This attachment is not a valid web link',
      backgroundColor: Colors.orange,
    );
    return;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Cannot open links of type “$scheme” from here',
      backgroundColor: Colors.orange,
    );
    return;
  }
  if (_isProjectFirebaseStorageDownloadUrl(uri) && _firebaseUserIfAvailable() == null) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Sign in to open this attachment.',
      backgroundColor: Colors.orange,
    );
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showCopyableSnackBar(
        context,
        'Could not open the link',
        backgroundColor: Colors.orange,
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    showCopyableSnackBar(
      context,
      'Could not open link: $e',
      backgroundColor: Colors.orange,
    );
  }
}
