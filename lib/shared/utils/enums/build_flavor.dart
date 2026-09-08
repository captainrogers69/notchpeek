/// Reported by `CapabilityProbe`. M1 only ever builds [direct]; the field
/// exists because the MAS build differs in what it may call (spike §4.3).
enum BuildFlavor {
  direct('direct', 'Direct download'),
  mas('mas', 'App Store');

  const BuildFlavor(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static BuildFlavor fromApi(String? value) {
    for (final f in BuildFlavor.values) {
      if (f.apiValue == value) return f;
    }
    return BuildFlavor.direct;
  }
}
