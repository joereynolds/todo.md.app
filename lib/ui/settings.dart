// Persistent settings (the desktop app's QSettings keys, in SharedPreferences).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

/// A saved, named filter (see TaskFilter.setView).
@immutable
class SavedView {
  const SavedView(this.name, this.filter);
  final String name, filter;

  Map<String, String> toJson() => {'name': name, 'filter': filter};
  static SavedView? fromJson(Object? o) {
    if (o is! Map) return null;
    final n = o['name'], f = o['filter'];
    return n is String && f is String && n.isNotEmpty ? SavedView(n, f) : null;
  }
}

class Settings extends ChangeNotifier {
  Settings(this._p);

  final SharedPreferences _p;

  static Future<Settings> load() async => Settings(await SharedPreferences.getInstance());

  List<String> get directories => _p.getStringList('directories') ?? const [];
  set directories(List<String> v) => _p.setStringList('directories', v);

  AppTheme get theme => themeFromString(_p.getString('view/theme'));
  set theme(AppTheme t) {
    _p.setString('view/theme', t.name);
    notifyListeners();
  }

  /// Bit per TaskState; done and cancelled hidden by default.
  int get states => _p.getInt('filter/states') ?? 0x3;
  set states(int v) => _p.setInt('filter/states', v);

  int get etaPreset => _p.getInt('filter/eta') ?? 0;
  set etaPreset(int v) => _p.setInt('filter/eta', v);

  List<String> get collapsed => _p.getStringList('view/collapsed') ?? const [];
  set collapsed(List<String> v) => _p.setStringList('view/collapsed', v);

  List<String> get agendaCollapsed => _p.getStringList('view/agendaCollapsed') ?? const [];
  set agendaCollapsed(List<String> v) => _p.setStringList('view/agendaCollapsed', v);

  bool get emptyDays => _p.getBool('agenda/emptyDays') ?? false;
  set emptyDays(bool v) => _p.setBool('agenda/emptyDays', v);

  int get tab => _p.getInt('view/tab') ?? 0;
  set tab(int v) => _p.setInt('view/tab', v);

  /// Saved views, in the user's order (JSON list of {name, filter}).
  List<SavedView> get views {
    try {
      final raw = jsonDecode(_p.getString('views/list') ?? '[]');
      return [
        if (raw is List)
          for (final o in raw) ?SavedView.fromJson(o),
      ];
    } on FormatException {
      return const [];
    }
  }

  set views(List<SavedView> v) => _p.setString('views/list', jsonEncode([for (final x in v) x.toJson()]));

  /// Name of the active view; null for none (all tasks).
  String? get currentView => _p.getString('views/current');
  set currentView(String? v) => v == null ? _p.remove('views/current') : _p.setString('views/current', v);
}
