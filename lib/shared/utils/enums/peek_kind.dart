/// The catalogue of events that trigger a peek grows per milestone. M1 ships
/// these two (spec §9).
enum PeekKind {
  trackChange('trackChange', 'Now playing'),
  charger('charger', 'Power');

  const PeekKind(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static PeekKind? fromApi(String? value) {
    for (final k in PeekKind.values) {
      if (k.apiValue == value) return k;
    }
    return null;
  }
}
