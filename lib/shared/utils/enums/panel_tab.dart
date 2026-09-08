/// Every panel NotchPeek will ever have. **M1 renders only [music]** — the
/// tab strip takes its tab list as a parameter from the start, so M2–M4 add
/// entries here without touching the strip (spec §5).
enum PanelTab {
  music('music', 'Music'),
  calendar('calendar', 'Calendar'),
  clipboard('clipboard', 'Clipboard'),
  shelf('shelf', 'Shelf'),
  timer('timer', 'Timer'),
  notes('notes', 'Notes'),
  webcam('webcam', 'Camera'),
  game('game', 'Game'),
  ai('ai', 'AI');

  const PanelTab(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PanelTab fromApi(String? value) {
    for (final t in PanelTab.values) {
      if (t.apiValue == value) return t;
    }
    return PanelTab.music;
  }
}
