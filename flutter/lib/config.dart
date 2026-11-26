/// Endpoints and constants shared by the whole app.
///
/// Mirrors `APIConfig` in `APIClient.swift`: the same three workers back the
/// library, the community feed and the per-shiur social data.
class ApiConfig {
  const ApiConfig._();

  static const String mainApi = 'https://beis-api.beisanytime.workers.dev';
  static const String communityApi =
      'https://beis-social-worker.beisanytime.workers.dev';
  static const String videoApi =
      'https://beis-anytime-viewsapi.beisanytime.workers.dev';

  /// Public site, used for share links.
  static const String siteUrl = 'https://beisanytime.com';

  /// Accounts allowed to publish, mirroring `ADMIN_EMAILS` on the web app.
  static const Set<String> adminEmails = {
    'joshuacalvert1@gmail.com',
  };

  /// R2 requires every part except the last to be exactly this size.
  static const int uploadChunkSize = 10 * 1024 * 1024;

  /// The web player's route for a single shiur, used when sharing.
  static Uri shareUrlFor(String shiurId) =>
      Uri.parse('$siteUrl/#view_shiur/$shiurId');
}
