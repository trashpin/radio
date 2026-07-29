// Pure form-validation helpers for the auth screens (unit-testable, no Flutter).

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? validateEmail(String? value) {
  final v = (value ?? '').trim();
  if (v.isEmpty) return 'Enter your email';
  if (!_emailRe.hasMatch(v)) return 'Enter a valid email address';
  return null;
}

String? validatePassword(String? value) {
  final v = value ?? '';
  if (v.isEmpty) return 'Enter a password';
  if (v.length < 8) return 'Password must be at least 8 characters';
  return null;
}

String? validateConfirmPassword(String? password, String? confirm) {
  if ((confirm ?? '').isEmpty) return 'Re-enter your password';
  if (password != confirm) return 'Passwords do not match';
  return null;
}

String? validateRequired(String? value, String label) {
  if ((value ?? '').trim().isEmpty) return 'Enter your $label';
  return null;
}

/// Turns a Supabase/auth error into a friendly, user-facing message.
String friendlyAuthError(Object error) {
  final msg = error.toString().toLowerCase();
  if (msg.contains('invalid login') || msg.contains('invalid credentials')) {
    return 'Incorrect email or password.';
  }
  if (msg.contains('already registered') || msg.contains('already exists') ||
      msg.contains('user already')) {
    return 'An account with this email already exists.';
  }
  if (msg.contains('email not confirmed')) {
    return 'Please confirm your email, then sign in.';
  }
  if (msg.contains('network') || msg.contains('socket') ||
      msg.contains('failed host')) {
    return 'Network error — check your connection and try again.';
  }
  if (msg.contains('rate limit') || msg.contains('too many')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  return 'Something went wrong. Please try again.';
}
