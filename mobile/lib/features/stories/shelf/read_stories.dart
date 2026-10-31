/// Which stories this device has read to the end — for the shelf's small
/// glowing star on a finished book and for which book it faces out next.
///
/// Local only (SharedPreferences): the shelf needs it on the first frame and
/// offline, and «finished» is a mark for the child, not a record anyone else
/// reads. The reader writes it where it already logs `story_finished`.
library;

import 'package:shared_preferences/shared_preferences.dart';

class ReadStories {
  ReadStories._();

  static const key = 'tg.stories.finished';

  static Future<Set<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(key) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<void> markFinished(String storyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = (prefs.getStringList(key) ?? const <String>[]).toSet();
      if (ids.add(storyId)) await prefs.setStringList(key, ids.toList());
    } catch (_) {
      // A mark that fails to save is a star that doesn't light — never an error.
    }
  }
}
