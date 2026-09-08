/// The three ways a panel can render, plus the one that hides it
/// (architecture-playbook §4.4).
enum CapabilityState {
  granted('granted', 'Ready'),
  denied('denied', 'Permission needed'),
  notDetermined('notDetermined', 'Not asked yet'),

  /// Not present in this build or on this OS. **Hidden, never teased.**
  absent('absent', 'Unavailable');

  const CapabilityState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CapabilityState fromApi(String? value) {
    for (final s in CapabilityState.values) {
      if (s.apiValue == value) return s;
    }
    return CapabilityState.notDetermined;
  }

  bool get isReady => this == CapabilityState.granted;
  bool get isHidden => this == CapabilityState.absent;
}
