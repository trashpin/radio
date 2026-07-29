import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:explorer_os_mobile/core/services/supabase_service.dart';

/// App-wide authentication state for ExplorerOS.
///
/// A [ChangeNotifier] (not Riverpod) so `go_router` can use it directly as a
/// `refreshListenable` and read it synchronously inside `redirect`. Wraps
/// Supabase Auth for email/password + Google OAuth, supports a no-account
/// **guest** mode, and restores the persisted session on launch (Supabase
/// stores the session in secure storage by default).
class AuthController extends ChangeNotifier {
  AuthController();

  bool _guest = false;
  bool _ready = false;
  StreamSubscription<AuthState>? _sub;

  /// True once the initial (restored) session has been resolved.
  bool get ready => _ready;

  bool get isGuest => _guest;

  GoTrueClient? get _auth =>
      SupabaseService.isConfigured ? Supabase.instance.client.auth : null;

  Session? get session => _auth?.currentSession;
  User? get user => _auth?.currentUser;
  bool get isAuthenticated => session != null;

  /// Admins get Developer Mode. Best-effort from JWT/app metadata; the profile
  /// row is the source of truth once loaded.
  bool get isAdmin {
    final u = user;
    if (u == null) return false;
    final role = (u.appMetadata['role'] ?? u.userMetadata?['role'] ?? '')
        .toString()
        .toLowerCase();
    return role == 'admin';
  }

  /// Whether the app should be entered (signed in, guest, or no backend at all
  /// so the app still works offline/demo).
  bool get canEnter =>
      isAuthenticated || _guest || !SupabaseService.isConfigured;

  /// Attaches the auth listener and resolves the restored session. Call once
  /// from `main` after `SupabaseService.initialize()`.
  void start() {
    if (!SupabaseService.isConfigured) {
      _ready = true;
      notifyListeners();
      return;
    }
    _ready = true;
    _sub = _auth!.onAuthStateChange.listen((_) => notifyListeners());
    notifyListeners();
  }

  Future<void> signIn(String email, String password) async {
    await _auth!.signInWithPassword(email: email.trim(), password: password);
    _guest = false;
    notifyListeners();
  }

  /// Creates an account. Returns true if a session was established immediately
  /// (email confirmation disabled); false if confirmation is required.
  Future<bool> signUp({
    required String email,
    required String password,
    String? firstName,
    String? lastName,
  }) async {
    final res = await _auth!.signUp(
      email: email.trim(),
      password: password,
      data: {
        if (firstName != null) 'first_name': firstName.trim(),
        if (lastName != null) 'last_name': lastName.trim(),
        if (firstName != null || lastName != null)
          'full_name': '${firstName ?? ''} ${lastName ?? ''}'.trim(),
      },
    );
    _guest = false;
    notifyListeners();
    return res.session != null;
  }

  /// Google OAuth (prepared — works once the Google provider is enabled in the
  /// Supabase dashboard). Opens the system browser / in-app auth flow.
  Future<void> signInWithGoogle() async {
    await _auth!.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'com.exploreros.explorer_os_mobile://login',
    );
  }

  Future<void> resetPassword(String email) =>
      _auth!.resetPasswordForEmail(email.trim());

  void continueAsGuest() {
    _guest = true;
    notifyListeners();
  }

  Future<void> signOut() async {
    _guest = false;
    if (SupabaseService.isConfigured) {
      await _auth!.signOut();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// The single app-wide auth controller instance (started in `main`).
final authController = AuthController();
