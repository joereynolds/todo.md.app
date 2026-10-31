// Folder access and "open file" on each platform.
//
// Android: notes folders are read straight from storage with dart:io (much
// faster than the Storage Access Framework for thousands of files), so the
// app needs "All files access" on Android 11+, or the storage permission
// before that. The bits that need Android APIs are in MainActivity.kt.
// iOS: apps are sandboxed; the app's own Documents folder is shown in the
// Files app ("On My iPhone › todo.md"), so notes go (or sync) there.
// Desktop (Linux, handy for development): any path.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

const _storage = MethodChannel('todomd/storage');

Future<bool> hasStorageAccess() async {
  if (!Platform.isAndroid) return true;
  return await _storage.invokeMethod<bool>('hasAccess') ?? false;
}

/// Asks for whatever is needed to read and write arbitrary folders. On
/// Android 11+ this opens a settings page; the answer is known once the user
/// comes back. Returns false if access wasn't granted.
Future<bool> ensureStorageAccess() async {
  if (await hasStorageAccess()) return true;
  final granted = await _storage.invokeMethod<bool>('requestAccess');
  if (granted != null) return granted; // the permission dialog answered
  // Wait for the return from the settings page, then check again.
  final back = Completer<void>();
  final listener = AppLifecycleListener(
    onResume: () {
      if (!back.isCompleted) back.complete();
    },
  );
  try {
    await back.future.timeout(const Duration(minutes: 5));
  } on TimeoutException {
    // gave up waiting
  } finally {
    listener.dispose();
  }
  return hasStorageAccess();
}

/// A folder chosen with the system picker, as a filesystem path; null if
/// cancelled or not available on this platform.
Future<String?> pickDirectory() async {
  if (!Platform.isAndroid) return null;
  if (!await ensureStorageAccess()) return null;
  return _storage.invokeMethod<String>('pickFolder');
}

/// Where typed paths usually start (/storage/emulated/0 on Android).
Future<String> storageRoot() async {
  if (Platform.isAndroid) return await _storage.invokeMethod<String>('externalRoot') ?? '/storage/emulated/0';
  return Platform.environment['HOME'] ?? '/';
}

/// The app's own documents folder (the default on iOS).
Future<String> appNotesDir() async => (await getApplicationDocumentsDirectory()).path;

bool get hasFolderPicker => Platform.isAndroid;
bool get canUseAnyFolder => !Platform.isIOS;

/// Opens the file in whatever app handles markdown (Markor, Obsidian, an
/// editor…). Mobile apps can't be told a line number. Returns an error
/// message, or null on success.
Future<String?> openInEditor(String path, int line) async {
  var r = await OpenFilex.open(path, type: 'text/markdown');
  if (r.type == ResultType.noAppToOpen) r = await OpenFilex.open(path, type: 'text/plain');
  return r.type == ResultType.done ? null : r.message;
}
