import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

SupabaseClient get supabase => Supabase.instance.client;
const _oauthRedirectUri = 'io.supabase.travelmap://login-callback/';

typedef ProfileFetcher = Future<Map<String, dynamic>?> Function(String userId);

class ProfileController extends ChangeNotifier {
  ProfileController({ProfileFetcher? profileFetcher})
      : _profileFetcher = profileFetcher;

  final ProfileFetcher? _profileFetcher;
  StreamSubscription<AuthState>? _authSubscription;
  String name = 'Експедитор';
  String userId = '';
  String inviteCode = '';
  String invitedBy = '';
  int xp = 10;
  int invitesLeft = 1;
  bool isAuthorized = false;
  bool needsInviteStep = false;
  bool isProfileLoading = false;
  String? profileLoadError;
  bool isOfflineMode = false;
  bool isDeveloper = false;

  // ОЬОУ ТУТ ВОНИ МАЮТЬ БУТИ:
  bool isSigningIn = false;
  String? authError;

  int lastLevelMilestone = 0;

  bool _initialized = false;
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await _loadLocal();
    _initAuthListener();

    final session = supabase.auth.currentSession;
    if (session != null) {
      await _handleSession(session);
    } else {
      _setSignedOutState();
    }
  }

  void _initAuthListener() {
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        await _handleSession(data.session!);
      } else if (data.event == AuthChangeEvent.signedOut) {
        _setSignedOutState();
      }
    });
  }

  Future<void> _handleSession(Session session) async {
    await _loadAuthenticatedProfile(
      authenticatedUserId: session.user.id,
      userMetadata: session.user.userMetadata,
    );
  }

  Future<Map<String, dynamic>?> _fetchProfile(String authenticatedUserId) {
    return supabase
        .from('profiles')
        .select()
        .eq('id', authenticatedUserId)
        .maybeSingle();
  }

  Future<void> _loadAuthenticatedProfile({
    required String authenticatedUserId,
    Map<String, dynamic>? userMetadata,
  }) async {
    userId = authenticatedUserId;
    final meta = userMetadata;
    final fullName = meta?['full_name'];
    if (fullName is String && fullName.trim().isNotEmpty) {
      name = fullName.trim();
    }

    // Cached authorization is not enough to open protected content for a
    // live session. Until the server profile has loaded successfully, the
    // access decision is unknown: neither authorized nor invite-required.
    isAuthorized = false;
    needsInviteStep = false;
    isProfileLoading = true;
    profileLoadError = null;
    notifyListeners();

    try {
      final res = await (_profileFetcher ?? _fetchProfile)(userId);
      if (res != null) {
        invitedBy = res['invited_by']?.toString() ?? '';
        xp = res['xp'] ?? 10;
        invitesLeft = res['invite_balance'] ?? 0;
        isDeveloper = res['is_developer'] ?? false;
        isAuthorized = res['invite_redeemed'] == true;
        needsInviteStep = !isAuthorized;
      } else {
        isAuthorized = false;
        needsInviteStep = true;
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not load OAuth user profile: $error');
      }
      isAuthorized = false;
      needsInviteStep = false;
      profileLoadError =
          'Не вдалося завантажити профіль. Перевірте з’єднання та спробуйте ще раз.';
      isProfileLoading = false;
      notifyListeners();
      return;
    }

    isProfileLoading = false;
    profileLoadError = null;

    inviteCode = userId.length >= 6
        ? userId.substring(0, 6).toUpperCase()
        : const Uuid().v4().substring(0, 6).toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_uid', userId);
    await prefs.setString('pref_name', name);
    await prefs.setBool('pref_auth', isAuthorized);
    await prefs.setBool('pref_needs_invite', needsInviteStep);
    notifyListeners();
  }

  /// Retries only the trusted profile lookup for the current live session.
  /// No automatic loop is used; the user explicitly initiates each retry.
  Future<void> retryProfileLoad() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      _setSignedOutState();
      return;
    }
    await _handleSession(session);
  }

  @visibleForTesting
  Future<void> handleAuthenticatedUserForTesting({
    required String authenticatedUserId,
    Map<String, dynamic>? userMetadata,
  }) {
    return _loadAuthenticatedProfile(
      authenticatedUserId: authenticatedUserId,
      userMetadata: userMetadata,
    );
  }

  void _setSignedOutState() {
    isAuthorized = false;
    needsInviteStep = false;
    isProfileLoading = false;
    profileLoadError = null;
    notifyListeners();
  }

  String get levelName {
    if (isDeveloper) return '🛠️ Головний Розробник';
    if (xp >= 1000) return 'Першовідкривач 🗺️';
    if (xp >= 600) return 'Турист 🎒';
    if (xp >= 300) return 'Мандрівник 🏕️';
    if (xp >= 100) return 'Дослідник 🧭';
    return 'Новачок 🌱';
  }

  int get currentLevelTier {
    if (xp >= 1000) return 5;
    if (xp >= 600) return 4;
    if (xp >= 300) return 3;
    if (xp >= 100) return 2;
    return 1;
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString('pref_name') ?? 'Експедитор';
    xp = prefs.getInt('pref_xp') ?? 10;
    userId = prefs.getString('pref_uid') ?? '';
    invitesLeft = prefs.getInt('pref_invites') ?? 1;
    invitedBy = prefs.getString('pref_invited_by') ?? '';
    isAuthorized = prefs.getBool('pref_auth') ?? false;
    needsInviteStep = prefs.getBool('pref_needs_invite') ?? false;
    isOfflineMode = prefs.getBool('pref_offline') ?? false;
    isDeveloper = prefs.getBool('pref_is_dev') ?? false;
    lastLevelMilestone = prefs.getInt('pref_level_milestone') ?? 1;

    if (userId.isEmpty) {
      userId = const Uuid().v4();
      await prefs.setString('pref_uid', userId);
    }
    inviteCode = userId.length >= 6
        ? userId.substring(0, 6).toUpperCase()
        : const Uuid().v4().substring(0, 6).toUpperCase();

    notifyListeners();
  }

  Future<void> signInWithGoogle() async {
    isSigningIn = true;
    authError = null;
    notifyListeners();
    try {
      final launched = await supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : _oauthRedirectUri,
      );
      if (!launched) {
        throw StateError('Не вдалося відкрити браузер для авторизації.');
      }
    } catch (e) {
      authError = 'Не вдалося відкрити Google: $e';
    } finally {
      isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signInWithApple() async {
    isSigningIn = true;
    authError = null;
    notifyListeners();
    try {
      final launched = await supabase.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? null : _oauthRedirectUri,
      );
      if (!launched) {
        throw StateError('Не вдалося відкрити браузер для авторизації.');
      }
    } catch (e) {
      authError = 'Не вдалося відкрити Apple: $e';
    } finally {
      isSigningIn = false;
      notifyListeners();
    }
  }

  Future<bool> completeInviteStep(String inviterCode) async {
    final code = inviterCode.trim().toUpperCase();
    if (code.isEmpty) return false;

    try {
      await supabase.rpc('redeem_invite', params: {'p_code': code});
      final profile = await supabase
          .from('profiles')
          .select('invited_by, invite_balance, invite_redeemed')
          .eq('id', userId)
          .single();
      invitedBy = profile['invited_by']?.toString() ?? '';
      invitesLeft = profile['invite_balance'] as int? ?? 0;
      isAuthorized = profile['invite_redeemed'] == true;
      needsInviteStep = !isAuthorized;
    } catch (_) {
      return false;
    }

    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_auth', isAuthorized);
    await prefs.setBool('pref_needs_invite', needsInviteStep);
    await prefs.setString('pref_uid', userId);
    await prefs.setString('pref_name', name);
    await prefs.setBool('pref_is_dev', isDeveloper);
    await prefs.setInt('pref_invites', invitesLeft);

    return true;
  }

  Future<String?> generateNewInviteCode() async {
    try {
      final code = await supabase.rpc<String>('create_invite');
      invitesLeft = math.max(0, invitesLeft - 1);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pref_invites', invitesLeft);
      notifyListeners();
      return code;
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    _setSignedOutState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_auth', false);
    await prefs.setBool('pref_needs_invite', false);
    try {
      await supabase.auth.signOut();
    } catch (_) {}
  }

  Future<void> setOfflineMode(bool value) async {
    if (isOfflineMode == value) return;
    isOfflineMode = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_offline', value);
  }

  Future<void> refreshServerProgress() async {
    if (userId.isEmpty || supabase.auth.currentUser == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('xp, invite_balance')
          .eq('id', userId)
          .single();
      xp = profile['xp'] as int? ?? xp;
      invitesLeft = profile['invite_balance'] as int? ?? invitesLeft;
      lastLevelMilestone = currentLevelTier;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('pref_xp', xp);
      await prefs.setInt('pref_invites', invitesLeft);
      await prefs.setInt('pref_level_milestone', lastLevelMilestone);
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final profileController = ProfileController();
