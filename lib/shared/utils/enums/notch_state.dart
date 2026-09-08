enum NotchState {
  collapsed('collapsed', 'Collapsed'),
  peeking('peeking', 'Peeking'),
  expanded('expanded', 'Expanded');

  const NotchState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static NotchState fromApi(String? value) {
    for (final s in NotchState.values) {
      if (s.apiValue == value) return s;
    }
    return NotchState.collapsed;
  }
}
