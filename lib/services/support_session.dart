import '../models/models.dart';

/// Stanje „support mode"-a (impersonacija) — DRŽI SE U MEMORIJI (ne u sigurnom
/// skladištu), jer impersonation token je kratkoživeći i namjerno ne preživljava
/// restart aplikacije (SSA se tada vrati na salon-picker).
///
/// Dijeli ga [AuthInterceptor] (bira token po pozivu) i AuthController/UI.
class SupportSession {
  String? token; // impersonation access token (null = nije u support modu)
  int? sellingPlaceId; // za re-impersonaciju na 401
  int? businessId;
  String? businessName;
  String? sellingPlaceName;

  /// Da li smo trenutno „unutar" nekog salona (impersonacija aktivna).
  bool get active => token != null;

  /// Postavi iz odgovora servera (ulazak/prebacivanje salona).
  void setFrom(ImpersonationResponse r) {
    token = r.accessToken;
    sellingPlaceId = r.sellingPlaceId ?? sellingPlaceId;
    businessId = r.businessId;
    businessName = r.businessName;
    sellingPlaceName = r.sellingPlaceName;
  }

  /// Ažuriraj token (i eventualno info) iz sirovog JSON-a — koristi interceptor
  /// pri re-impersonaciji (bez modela).
  void updateFromMap(Map<String, dynamic> data) {
    token = data['accessToken'] as String?;
    sellingPlaceId =
        (data['sellingPlaceId'] as num?)?.toInt() ?? sellingPlaceId;
    businessId = (data['businessId'] as num?)?.toInt() ?? businessId;
    businessName = (data['businessName'] as String?) ?? businessName;
    sellingPlaceName = (data['sellingPlaceName'] as String?) ?? sellingPlaceName;
  }

  void clear() {
    token = null;
    sellingPlaceId = null;
    businessId = null;
    businessName = null;
    sellingPlaceName = null;
  }
}
