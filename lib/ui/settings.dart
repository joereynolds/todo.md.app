// Persistent settings (the desktop app's QSettings keys, in SharedPreferences).

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme.dart';

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
}
