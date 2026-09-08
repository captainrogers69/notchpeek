/// Every URL in the app. There are two, because NotchPeek has no backend
/// (architecture-playbook §5). No URL literals at call sites.
abstract final class ApiEndpoint {
  /// iTunes Search API. Public, unauthenticated, rate-limited at ~20 calls
  /// per minute — which is far above anything a track change can produce.
  static const String itunesBaseUrl = 'https://itunes.apple.com';

  /// Artwork fallback, used only when neither player hands us an image.
  /// `?term=<artist album>&entity=album&limit=1`.
  static const String search = '/search';
}
