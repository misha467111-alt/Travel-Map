import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/app_models.dart';

SupabaseClient get supabase => Supabase.instance.client;
const _oauthRedirectUri = 'io.supabase.travelmap://login-callback/';

class ProfileController extends ChangeNotifier {
  StreamSubscription<AuthState>? _authSubscription;
  String name = 'Експедитор';
  String userId = '';
  String inviteCode = '';
  String invitedBy = '';
  String localAvatarPath = '';
  int xp = 10;
  int invitesLeft = 1;
  bool isAuthorized = false;
  bool needsInviteStep = false;
  bool isOfflineMode = false;
  bool isDeveloper = false;

  int get createdLocationsCount =>
      cachedLocations.where((location) => location.authorId == userId).length;

  // ОЬОУ ТУТ ВОНИ МАЮТЬ БУТИ:
  bool isSigningIn = false;
  String? authError;

  int lastLevelMilestone = 0;

  List<String> savedLocationIds = [];
  List<String> savedRouteIds = [];
  List<String> offlineLocationIds = [];
  List<String> offlineRouteIds = [];

  List<LocationPreview> cachedLocations = [];
  List<CustomRouteItem> cachedAllRoutes = [];
  List<Map<String, dynamic>> cachedAllUsers = [];
  bool isLoadingData = false;

  Future<void> fetchAllData() async {
    if (isLoadingData) return;
    isLoadingData = true;
    try {
      final locationRows = await supabase
          .from('locations')
          .select()
          .order('created_at', ascending: false)
          .limit(300);
      if ((locationRows as List).isNotEmpty) {
        cachedLocations = locationRows
            .map((d) => LocationPreview.fromLocationJson(d))
            .toList();
      } else {
        cachedLocations = const <LocationPreview>[];
      }

      final usersRes = await supabase.from('users').select().limit(50);
      if ((usersRes as List).isNotEmpty) {
        cachedAllUsers = List<Map<String, dynamic>>.from(usersRes);
      }
    } catch (_) {}
    isLoadingData = false;
    notifyListeners();
  }

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
      isAuthorized = false;
      needsInviteStep = false;
      notifyListeners();
    }
  }

  void _initAuthListener() {
    _authSubscription = supabase.auth.onAuthStateChange.listen((data) async {
      if (data.session != null) {
        await _handleSession(data.session!);
      } else if (data.event == AuthChangeEvent.signedOut) {
        isAuthorized = false;
        needsInviteStep = false;
        notifyListeners();
      }
    });
  }

  Future<void> _handleSession(Session session) async {
    userId = session.user.id;
    final meta = session.user.userMetadata;
    final fullName = meta?['full_name'];
    if (fullName is String && fullName.trim().isNotEmpty) {
      name = fullName.trim();
    }

    try {
      final res = await supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
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
      needsInviteStep = true;
    }

    inviteCode = userId.length >= 6
        ? userId.substring(0, 6).toUpperCase()
        : const Uuid().v4().substring(0, 6).toUpperCase();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_uid', userId);
    await prefs.setString('pref_name', name);
    await prefs.setBool('pref_auth', isAuthorized);
    await prefs.setBool('pref_needs_invite', needsInviteStep);
    fetchAllData();
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
    localAvatarPath = prefs.getString('pref_avatar') ?? '';
    xp = prefs.getInt('pref_xp') ?? 10;
    userId = prefs.getString('pref_uid') ?? '';
    invitesLeft = prefs.getInt('pref_invites') ?? 1;
    invitedBy = prefs.getString('pref_invited_by') ?? '';
    isAuthorized = prefs.getBool('pref_auth') ?? false;
    needsInviteStep = prefs.getBool('pref_needs_invite') ?? false;
    isOfflineMode = prefs.getBool('pref_offline') ?? false;
    isDeveloper = prefs.getBool('pref_is_dev') ?? false;
    lastLevelMilestone = prefs.getInt('pref_level_milestone') ?? 1;
    savedLocationIds = prefs.getStringList('pref_saved_locations') ?? [];
    savedRouteIds = prefs.getStringList('pref_saved_routes') ?? [];
    offlineLocationIds = prefs.getStringList('pref_offline_locations') ?? [];
    offlineRouteIds = prefs.getStringList('pref_offline_routes') ?? [];
    cachedLocations = const <LocationPreview>[];

    if (userId.isEmpty) {
      userId = const Uuid().v4();
      await prefs.setString('pref_uid', userId);
    }
    inviteCode = userId.length >= 6
        ? userId.substring(0, 6).toUpperCase()
        : const Uuid().v4().substring(0, 6).toUpperCase();

    fetchAllData();
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

    fetchAllData();
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
    isAuthorized = false;
    needsInviteStep = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_auth', false);
    await prefs.setBool('pref_needs_invite', false);
    try {
      await supabase.auth.signOut();
    } catch (_) {}
  }

  Future<void> updateName(String newName) async {
    if (newName.trim().isEmpty) return;
    name = newName.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_name', name);
    try {
      await supabase
          .from('profiles')
          .update({'name': name, 'display_name': name}).eq('id', userId);
    } catch (_) {}
  }

  Future<void> updateAvatar(String newPath) async {
    localAvatarPath = newPath;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pref_avatar', localAvatarPath);
  }

  Future<void> toggleSaveLocation(String id) async {
    if (savedLocationIds.contains(id)) {
      savedLocationIds.remove(id);
    } else {
      savedLocationIds.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_saved_locations', savedLocationIds);
  }

  Future<void> toggleOfflineLocation(String id) async {
    if (offlineLocationIds.contains(id)) {
      offlineLocationIds.remove(id);
    } else {
      offlineLocationIds.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_offline_locations', offlineLocationIds);
  }

  Future<void> toggleOfflineRoute(String id) async {
    if (offlineRouteIds.contains(id)) {
      offlineRouteIds.remove(id);
    } else {
      offlineRouteIds.add(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pref_offline_routes', offlineRouteIds);
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

  ImageProvider? getAvatarImage() {
    if (localAvatarPath.isNotEmpty && File(localAvatarPath).existsSync()) {
      return FileImage(File(localAvatarPath));
    }
    return null;
  }
}

final profileController = ProfileController();
