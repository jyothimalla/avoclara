import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/tracker_models.dart';
import 'screens/tracker_home_page.dart';

void main() {
  runApp(const HobbyTrackerApp());
}

const String _kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_WEB_CLIENT_ID',
  defaultValue: '',
);
const String _kGoogleServerClientId = String.fromEnvironment(
  'GOOGLE_SERVER_CLIENT_ID',
  defaultValue: '',
);

class HobbyTrackerApp extends StatelessWidget {
  const HobbyTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hobby & Task Tracker',
      debugShowCheckedModeBanner: false,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: const TextScaler.linear(0.88)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE83E76)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const String _accountsKey = 'local_accounts_v1';
  static const String _sessionKey = 'active_session_email_v1';
  final GoogleSignIn _authGoogleSignIn = GoogleSignIn.instance;

  bool _loading = true;
  bool _googleInitialized = false;
  LocalUserAccount? _currentUser;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? sessionEmail = prefs.getString(_sessionKey);
    if (sessionEmail == null) {
      setState(() {
        _loading = false;
      });
      return;
    }
    final List<LocalUserAccount> accounts = await _readAccounts();
    final LocalUserAccount? match = accounts
        .cast<LocalUserAccount?>()
        .firstWhere(
          (LocalUserAccount? account) =>
              account?.email.toLowerCase() == sessionEmail.toLowerCase(),
          orElse: () => null,
        );
    setState(() {
      _currentUser = match;
      _loading = false;
    });
  }

  Future<List<LocalUserAccount>> _readAccounts() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> raw = prefs.getStringList(_accountsKey) ?? <String>[];
    return raw
        .map(
          (String value) => LocalUserAccount.fromJson(
            jsonDecode(value) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<void> _writeAccounts(List<LocalUserAccount> accounts) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _accountsKey,
      accounts
          .map((LocalUserAccount item) => jsonEncode(item.toJson()))
          .toList(),
    );
  }

  String _hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  UserType? _parseUserType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    for (final UserType type in UserType.values) {
      if (type.name == value) {
        return type;
      }
    }
    return null;
  }

  Future<String?> _login({
    required String email,
    required String password,
    required bool rememberSession,
  }) async {
    final List<LocalUserAccount> accounts = await _readAccounts();
    final String targetEmail = email.trim().toLowerCase();
    final String passwordHash = _hashPassword(password);
    LocalUserAccount? matchedAccount;
    for (final LocalUserAccount account in accounts) {
      if (account.email.toLowerCase() == targetEmail &&
          account.passwordHash == passwordHash) {
        matchedAccount = account;
        break;
      }
    }
    if (matchedAccount == null) {
      return 'Invalid email or password';
    }
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (rememberSession) {
      await prefs.setString(_sessionKey, matchedAccount.email);
    } else {
      await prefs.remove(_sessionKey);
    }
    setState(() {
      _currentUser = matchedAccount;
    });
    return null;
  }

  Future<String?> _register({
    required String name,
    required String email,
    required String password,
    required bool rememberSession,
  }) async {
    final List<LocalUserAccount> accounts = await _readAccounts();
    final String targetEmail = email.trim().toLowerCase();
    final bool exists = accounts.any(
      (LocalUserAccount account) => account.email.toLowerCase() == targetEmail,
    );
    if (exists) {
      return 'An account with this email already exists';
    }
    final LocalUserAccount account = LocalUserAccount(
      name: name.trim(),
      email: targetEmail,
      passwordHash: _hashPassword(password),
      provider: 'email',
      createdAtIso: DateTime.now().toIso8601String(),
    );
    accounts.add(account);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _writeAccounts(accounts);
    if (rememberSession) {
      await prefs.setString(_sessionKey, account.email);
    } else {
      await prefs.remove(_sessionKey);
    }
    setState(() {
      _currentUser = account;
    });
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Successfully registered')));
    }
    return null;
  }

  Future<void> _completeUserSetup({
    required UserType userType,
    required String displayName,
    String? childName,
  }) async {
    final LocalUserAccount? current = _currentUser;
    if (current == null) {
      return;
    }
    final List<LocalUserAccount> accounts = await _readAccounts();
    final int index = accounts.indexWhere(
      (LocalUserAccount item) =>
          item.email.toLowerCase() == current.email.toLowerCase(),
    );
    final LocalUserAccount updated = LocalUserAccount(
      name: displayName.trim(),
      email: current.email,
      passwordHash: current.passwordHash,
      provider: current.provider,
      createdAtIso: current.createdAtIso,
      userType: userType.name,
      childName: childName?.trim().isEmpty ?? true ? null : childName!.trim(),
    );
    if (index >= 0) {
      accounts[index] = updated;
      await _writeAccounts(accounts);
    }
    setState(() {
      _currentUser = updated;
    });
  }

  Future<void> _initializeGoogleAuth() async {
    if (_googleInitialized) {
      return;
    }
    await _authGoogleSignIn.initialize(
      clientId: kIsWeb ? _kGoogleWebClientId.trim() : null,
      serverClientId: _kGoogleServerClientId.trim().isEmpty
          ? null
          : _kGoogleServerClientId.trim(),
    );
    _googleInitialized = true;
  }

  Future<String?> _continueWithGoogle({required bool rememberSession}) async {
    try {
      if (kIsWeb && _kGoogleWebClientId.trim().isEmpty) {
        return 'Google sign-in on web needs GOOGLE_WEB_CLIENT_ID.';
      }
      await _initializeGoogleAuth();
      final GoogleSignInAccount account = await _authGoogleSignIn
          .authenticate();
      final List<LocalUserAccount> accounts = await _readAccounts();
      final String targetEmail = account.email.trim().toLowerCase();
      final int existingIndex = accounts.indexWhere(
        (LocalUserAccount item) => item.email.toLowerCase() == targetEmail,
      );
      final LocalUserAccount googleAccount = LocalUserAccount(
        name: (account.displayName ?? account.email.split('@').first).trim(),
        email: targetEmail,
        passwordHash: existingIndex >= 0
            ? accounts[existingIndex].passwordHash
            : null,
        provider: 'google',
        createdAtIso: existingIndex >= 0
            ? accounts[existingIndex].createdAtIso
            : DateTime.now().toIso8601String(),
      );
      if (existingIndex >= 0) {
        accounts[existingIndex] = googleAccount;
      } else {
        accounts.add(googleAccount);
      }
      await _writeAccounts(accounts);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      if (rememberSession) {
        await prefs.setString(_sessionKey, googleAccount.email);
      } else {
        await prefs.remove(_sessionKey);
      }
      setState(() {
        _currentUser = googleAccount;
      });
      return null;
    } catch (error) {
      return 'Google sign-in failed: $error';
    }
  }

  Future<String?> _resetPassword({
    required String email,
    required String newPassword,
  }) async {
    final List<LocalUserAccount> accounts = await _readAccounts();
    final String targetEmail = email.trim().toLowerCase();
    final int existingIndex = accounts.indexWhere(
      (LocalUserAccount item) => item.email.toLowerCase() == targetEmail,
    );
    if (existingIndex < 0) {
      return 'No account found for that email';
    }
    final LocalUserAccount existing = accounts[existingIndex];
    if (!existing.usesPassword) {
      return 'This account uses Google sign-in. Please continue with Google.';
    }
    accounts[existingIndex] = LocalUserAccount(
      name: existing.name,
      email: existing.email,
      passwordHash: _hashPassword(newPassword),
      provider: existing.provider,
      createdAtIso: existing.createdAtIso,
    );
    await _writeAccounts(accounts);
    return null;
  }

  Future<String?> _changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final LocalUserAccount? current = _currentUser;
    if (current == null) {
      return 'No signed-in user';
    }
    if (!current.usesPassword) {
      return 'This account uses Google sign-in. Password change is unavailable here.';
    }
    if (_hashPassword(currentPassword) != current.passwordHash) {
      return 'Current password is incorrect';
    }
    final List<LocalUserAccount> accounts = await _readAccounts();
    final int index = accounts.indexWhere(
      (LocalUserAccount item) =>
          item.email.toLowerCase() == current.email.toLowerCase(),
    );
    if (index < 0) {
      return 'Account not found';
    }
    final LocalUserAccount updated = LocalUserAccount(
      name: current.name,
      email: current.email,
      passwordHash: _hashPassword(newPassword),
      provider: current.provider,
      createdAtIso: current.createdAtIso,
      userType: current.userType,
      childName: current.childName,
    );
    accounts[index] = updated;
    await _writeAccounts(accounts);
    setState(() {
      _currentUser = updated;
    });
    return null;
  }

  Future<void> _logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
    if (_googleInitialized) {
      await _authGoogleSignIn.signOut();
    }
    setState(() {
      _currentUser = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_currentUser == null) {
      return AuthScreen(
        onLogin: _login,
        onRegister: _register,
        onContinueWithGoogle: _continueWithGoogle,
        onResetPassword: _resetPassword,
      );
    }
    final UserType? userType = _parseUserType(_currentUser!.userType);
    if (userType == null) {
      return UserTypeSetupScreen(
        initialName: _currentUser!.name,
        currentEmail: _currentUser!.email,
        onComplete: _completeUserSetup,
      );
    }
    return TrackerHomePage(
      initialMotherName: _currentUser!.name,
      currentUserEmail: _currentUser!.email,
      initialUserType: userType,
      initialChildName: _currentUser!.childName,
      canChangePassword: _currentUser!.usesPassword,
      onChangePassword: _changePassword,
      onLogout: _logout,
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.onLogin,
    required this.onRegister,
    required this.onContinueWithGoogle,
    required this.onResetPassword,
  });

  final Future<String?> Function({
    required String email,
    required String password,
    required bool rememberSession,
  })
  onLogin;
  final Future<String?> Function({
    required String name,
    required String email,
    required String password,
    required bool rememberSession,
  })
  onRegister;
  final Future<String?> Function({required bool rememberSession})
  onContinueWithGoogle;
  final Future<String?> Function({
    required String email,
    required String newPassword,
  })
  onResetPassword;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberSession = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          _error = null;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _passwordStrengthLabel(String password) {
    if (password.length >= 10 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) {
      return 'Strong password';
    }
    if (password.length >= 8) {
      return 'Good password';
    }
    return 'Use at least 8 characters for a stronger password';
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final bool isLogin = _tabController.index == 0;
    final String? result = isLogin
        ? await widget.onLogin(
            email: _emailController.text,
            password: _passwordController.text,
            rememberSession: _rememberSession,
          )
        : await widget.onRegister(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            rememberSession: _rememberSession,
          );
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _error = result;
    });
  }

  Future<void> _submitGoogle() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final String? result = await widget.onContinueWithGoogle(
      rememberSession: _rememberSession,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _error = result;
    });
  }

  Future<void> _openPasswordReset() async {
    final TextEditingController emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    final TextEditingController passwordController = TextEditingController();
    final TextEditingController confirmController = TextEditingController();
    String? inlineError;
    bool saving = false;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: Icon(Icons.verified_user_outlined),
                      ),
                    ),
                    if (inlineError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        inlineError!,
                        style: const TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final String email = emailController.text.trim();
                          final String newPassword = passwordController.text;
                          if (!email.contains('@')) {
                            setDialogState(() {
                              inlineError = 'Enter a valid email';
                            });
                            return;
                          }
                          if (newPassword.length < 6) {
                            setDialogState(() {
                              inlineError =
                                  'Password must be at least 6 characters';
                            });
                            return;
                          }
                          if (newPassword != confirmController.text) {
                            setDialogState(() {
                              inlineError = 'Passwords do not match';
                            });
                            return;
                          }
                          setDialogState(() {
                            saving = true;
                            inlineError = null;
                          });
                          final String? result = await widget.onResetPassword(
                            email: email,
                            newPassword: newPassword,
                          );
                          if (!context.mounted || !dialogContext.mounted) {
                            return;
                          }
                          if (result == null) {
                            _emailController.text = email;
                            Navigator.of(dialogContext).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Password updated. Sign in with the new password.',
                                ),
                              ),
                            );
                            return;
                          }
                          setDialogState(() {
                            saving = false;
                            inlineError = result;
                          });
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
    emailController.dispose();
    passwordController.dispose();
    confirmController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isLogin = _tabController.index == 0;
    final String passwordText = _passwordController.text;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF312E81),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: colorScheme.primary,
                              size: 34,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Welcome Back',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use email or Google sign-in to keep routines, points, and family plans synced on this device.',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: TabBar(
                              controller: _tabController,
                              dividerColor: Colors.transparent,
                              indicator: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              labelColor: Colors.white,
                              unselectedLabelColor: Colors.black87,
                              tabs: const [
                                Tab(text: 'Sign In'),
                                Tab(text: 'Create Account'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (!isLogin) ...[
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                              validator: (String? value) {
                                if (_tabController.index == 0) {
                                  return null;
                                }
                                if (value == null || value.trim().length < 2) {
                                  return 'Enter your name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (String? value) {
                              final String text = value?.trim() ?? '';
                              if (text.isEmpty || !text.contains('@')) {
                                return 'Enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            onChanged: (_) {
                              setState(() {});
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                ),
                              ),
                            ),
                            validator: (String? value) {
                              if ((value ?? '').length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          if (!isLogin) ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _confirmPasswordController,
                              obscureText: _obscureConfirmPassword,
                              decoration: InputDecoration(
                                labelText: 'Confirm Password',
                                prefixIcon: const Icon(
                                  Icons.verified_user_outlined,
                                ),
                                suffixIcon: IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _obscureConfirmPassword =
                                          !_obscureConfirmPassword;
                                    });
                                  },
                                  icon: Icon(
                                    _obscureConfirmPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                  ),
                                ),
                              ),
                              validator: (String? value) {
                                if (isLogin) {
                                  return null;
                                }
                                if (value != _passwordController.text) {
                                  return 'Passwords do not match';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _passwordStrengthLabel(passwordText),
                                style: TextStyle(
                                  color: passwordText.length >= 8
                                      ? const Color(0xFF15803D)
                                      : Colors.grey.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            value: _rememberSession,
                            onChanged: _loading
                                ? null
                                : (bool? value) {
                                    setState(() {
                                      _rememberSession = value ?? true;
                                    });
                                  },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Keep me signed in on this device',
                            ),
                          ),
                          if (isLogin)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _loading ? null : _openPasswordReset,
                                child: const Text('Forgot password?'),
                              ),
                            ),
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFDC2626),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _tabController.index == 0
                                        ? Icons.login_rounded
                                        : Icons.person_add_alt_1_rounded,
                                  ),
                            label: Text(isLogin ? 'Sign In' : 'Create Account'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                child: Text(
                                  'or',
                                  style: TextStyle(color: Colors.grey.shade700),
                                ),
                              ),
                              const Expanded(child: Divider()),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _loading ? null : _submitGoogle,
                            icon: const Icon(Icons.account_circle_outlined),
                            label: const Text('Continue with Google'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class UserTypeSetupScreen extends StatefulWidget {
  const UserTypeSetupScreen({
    super.key,
    required this.initialName,
    required this.currentEmail,
    required this.onComplete,
  });

  final String initialName;
  final String currentEmail;
  final Future<void> Function({
    required UserType userType,
    required String displayName,
    String? childName,
  })
  onComplete;

  @override
  State<UserTypeSetupScreen> createState() => _UserTypeSetupScreenState();
}

class _UserTypeSetupScreenState extends State<UserTypeSetupScreen> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.initialName,
  );
  final TextEditingController _childNameController = TextEditingController();
  UserType? _selectedType;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  String _label(UserType type) {
    switch (type) {
      case UserType.individual:
        return 'Individual';
      case UserType.student:
        return 'Student';
      case UserType.parent:
        return 'Parent';
      case UserType.kid:
        return 'Kid';
    }
  }

  String _description(UserType type) {
    switch (type) {
      case UserType.individual:
        return 'Personal planner with a single profile.';
      case UserType.student:
        return 'School-friendly planning with one learner profile.';
      case UserType.parent:
        return 'Manage child routines and family planning.';
      case UserType.kid:
        return 'Simple personal routine tracking for a child user.';
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null) {
      setState(() {
        _error = 'Choose who is using this app';
      });
      return;
    }
    final String displayName = _nameController.text.trim();
    if (displayName.length < 2) {
      setState(() {
        _error = 'Enter a valid name';
      });
      return;
    }
    if (_selectedType == UserType.parent &&
        _childNameController.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter the first child name or learner name';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.onComplete(
      userType: _selectedType!,
      displayName: displayName,
      childName: _selectedType == UserType.parent
          ? _childNameController.text.trim()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color(0xFF0F172A),
              Color(0xFF1E293B),
              Color(0xFF312E81),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Set Up Your Profile',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choose who is using the app so we can show the right profile and controls.',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.currentEmail,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Your Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Who is using this app?',
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...UserType.values.map((UserType type) {
                          final bool selected = _selectedType == type;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: selected
                                    ? colorScheme.primary
                                    : Colors.grey.shade300,
                                width: selected ? 2 : 1,
                              ),
                              color: selected
                                  ? colorScheme.primary.withValues(alpha: 0.08)
                                  : Colors.white,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                setState(() {
                                  _selectedType = type;
                                  _error = null;
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off,
                                      color: selected
                                          ? colorScheme.primary
                                          : Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _label(type),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(_description(type)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                        if (_selectedType == UserType.parent) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _childNameController,
                            decoration: const InputDecoration(
                              labelText: 'First Child Name',
                              prefixIcon: Icon(Icons.child_care_outlined),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _saving ? null : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Continue'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
