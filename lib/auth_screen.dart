import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart';
import 'style.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _errorMessage;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitEmailAuth() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      if (_isSignUp) {
        await _supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Перевір пошту — надіслали лист для підтвердження'),
            ),
          );
        }
      } else {
        await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }
    } on AuthException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(() => _errorMessage = 'Щось пішло не так. Спробуй ще раз.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    googleSignInPending.value = true;

    try {
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.supabase.nepogano://login-callback',
      );
      // Запобіжник: якщо юзер скасував вхід у браузері й повернувся без
      // редіректу, зняти лоадер через деякий час замість вічного очікування.
      Future.delayed(const Duration(seconds: 8), () {
        googleSignInPending.value = false;
      });
    } catch (e) {
      googleSignInPending.value = false;
      setState(() => _errorMessage = 'Не вдалось увійти через Google.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nepogano',
                    textAlign: TextAlign.center,
                    style: appSerif(fontSize: 36, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp ? 'Створи акаунт' : 'Увійди в акаунт',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: AppColors.inkMuted),
                  ),
                  const SizedBox(height: 32),

                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Email',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Пароль',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),

                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ],

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _loading ? null : _submitEmailAuth,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.ink,
                      foregroundColor: AppColors.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.background,
                            ),
                          )
                        : Text(_isSignUp ? 'Зареєструватись' : 'Увійти'),
                  ),

                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Вже є акаунт? Увійти'
                          : 'Немає акаунту? Зареєструватись',
                    ),
                  ),

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Expanded(child: Divider(color: AppColors.divider)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('або', style: TextStyle(color: Colors.grey.shade500)),
                      ),
                      const Expanded(child: Divider(color: AppColors.divider)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  OutlinedButton(
                    onPressed: _loading ? null : _signInWithGoogle,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: AppColors.surface,
                      foregroundColor: AppColors.ink,
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Продовжити з Google'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}