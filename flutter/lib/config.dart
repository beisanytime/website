/// Endpoints and constants shared by the whole app.
///
/// One API worker (deployed as `beis-api`) backs the library, admin uploads, the
/// community feed and the per-shiur social data, served at `api.beisanytime.com`.
class ApiConfig {
  const ApiConfig._();

  static const String apiBase = 'https://api.beisanytime.com';
  static const String mainApi = apiBase;
  static const String communityApi = apiBase;
  static const String videoApi = apiBase;

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
