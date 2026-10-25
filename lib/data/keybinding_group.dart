import 'package:keybinder/keybinder.dart';

/// Keybindings bound by one widget, so they can be removed together
/// without removing other widgets' callbacks for the same keys
/// (e.g. the other editor in split view).
class KeybindingGroup {
  final _bindings = <(Keybinding, Function)>[];

  void bind(Keybinding keybinding, Function callback) {
    Keybinder.bind(keybinding, callback);
    _bindings.add((keybinding, callback));
  }

  void removeAll() {
    for (final (keybinding, callback) in _bindings) {
      Keybinder.remove(keybinding, callback);
    }
    _bindings.clear();
  }
}
