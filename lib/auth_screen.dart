import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_localizations.dart';
import 'locale_provider.dart';
import 'style.dart';

// Web Client ID з Google Cloud Console (той самий, що використовує Supabase
// для Google-провайдера) — потрібен нативному Google Sign-In, щоб отримати
// idToken, який Supabase зможе перевірити через signInWithIdToken.
const _googleWebClientId =
    '850571671108-6fpmkc0lnspkela5avrb3qqndnjrpm22.apps.googleusercontent.com';

// iOS OAuth Client ID з того ж проєкту Google Cloud Console (тип застосунку
// "iOS") — на Android serverClientId сам добуває його через Google Play
// Services, але на iOS google_sign_in вимагає його явно окремим полем.
const _googleIosClientId =
    '850571671108-f4fmglpu700jslvk8kqtq7vmaphjjud3.apps.googleusercontent.com';

// Apple вимагає nonce у Sign in with Apple, щоб id-токен не можна було
// перевикористати в атаці типу replay — генеруємо сирий nonce тут, а Apple
// отримує лише його SHA256-хеш, звіряючи потім, що сирий nonce, який
// повернувся в токені, дає той самий хеш.
String _generateNonce([int length = 32]) {
  const charset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
  final random = Random.secure();
  return List.generate(
    length,
    (_) => charset[random.nextInt(charset.length)],
  ).join();
}

String _sha256Hex(String input) {
  return sha256.convert(utf8.encode(input)).toString();
}

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

  // Клієнтський кулдаун після реєстрації — не заміна серверних Rate
  // Limits у Supabase Dashboard (той захист лишається головним і працює
  // незалежно від застосунку), а перша лінія проти найпростішого
  // зловживання: повторний тап "Зареєструватись" одразу після
  // попереднього, щоб закидати чужу (чи будь-яку) поштову скриньку
  // листами підтвердження. 30с — досить, щоб зробити ручний спам
  // відчутно повільним, не заважаючи звичайній реєстрації.
  static const _signUpCooldownSeconds = 30;
  int _signUpCooldownRemaining = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startSignUpCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _signUpCooldownRemaining = _signUpCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_signUpCooldownRemaining <= 1) {
          _signUpCooldownRemaining = 0;
          timer.cancel();
        } else {
          _signUpCooldownRemaining--;
        }
      });
    });
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
        _startSignUpCooldown();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).checkEmailToConfirm),
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
      // Кулдаун і тут теж, не лише при успіху — запит однаково дійшов до
      // сервера (і врахувався в його власний rate limit), тож дозволяти
      // миттєвий повтор після помилки так само дозволяло б спамити
      // швидше, ніж захист має на меті.
      if (_isSignUp) _startSignUpCooldown();
      setState(() => _errorMessage = e.message);
    } catch (e) {
      if (_isSignUp) _startSignUpCooldown();
      if (mounted) {
        setState(
          () => _errorMessage = AppLocalizations.of(context).somethingWentWrong,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // Нативний вхід через Google Play Services — без відкриття браузера,
      // тому немає розриву застосунок→браузер→застосунок, який на деяких
      // пристроях провокував тривалі мережеві збої одразу після повернення.
      final googleUser = await GoogleSignIn(
        serverClientId: _googleWebClientId,
        clientId: Platform.isIOS ? _googleIosClientId : null,
      ).signIn();
      if (googleUser == null) {
        // Юзер закрив вибір акаунта.
        return;
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        throw const AuthException('No ID Token found.');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAuth.accessToken,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = AppLocalizations.of(context).googleSignInFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final rawNonce = _generateNonce();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: _sha256Hex(rawNonce),
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('No ID Token found.');
      }

      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _errorMessage = AppLocalizations.of(context).appleSignInFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Той самий перемикач, що на онбордингу, у тій самій позиції
              // (верх-ліворуч, з тим самим відступом зверху) — автовизначення
              // мови системи не завжди вгадує, і на логін-екрані так само
              // немає іншого способу її змінити до входу. Свідомо поза
              // центрованим блоком форми нижче, інакше він "плавав" би разом
              // з формою замість того, щоб лишатись прикріпленим до верху
              // екрана.
              const SizedBox(height: 8),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      final next = appLocale.value.languageCode == 'uk'
                          ? 'en'
                          : 'uk';
                      setAppLocale(Locale(next));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        appLocale.value.languageCode == 'uk' ? 'EN' : 'UK',
                        style: const TextStyle(
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Nepogano',
                          textAlign: TextAlign.center,
                          style: appSerif(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isSignUp ? l10n.createAccount : l10n.signInToAccount,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.inkMuted,
                          ),
                        ),
                        const SizedBox(height: 32),

                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: l10n.emailHint,
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
                            hintText: l10n.passwordHint,
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
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ],

                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed:
                              (_loading ||
                                  (_isSignUp && _signUpCooldownRemaining > 0))
                              ? null
                              : _submitEmailAuth,
                          child: _loading
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentInk,
                                  ),
                                )
                              : Text(
                                  _isSignUp && _signUpCooldownRemaining > 0
                                      ? l10n.signUpCooldown(
                                          _signUpCooldownRemaining,
                                        )
                                      : (_isSignUp
                                            ? l10n.signUp
                                            : l10n.signIn),
                                ),
                        ),

                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => setState(() => _isSignUp = !_isSignUp),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: _isSignUp
                                      ? l10n.alreadyHaveAccountQuestion
                                      : l10n.noAccountYetQuestion,
                                ),
                                const TextSpan(text: ' '),
                                TextSpan(
                                  text: _isSignUp ? l10n.signIn : l10n.signUp,
                                  style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const Expanded(
                              child: Divider(color: AppColors.divider),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                l10n.or,
                                style: TextStyle(color: Colors.grey.shade500),
                              ),
                            ),
                            const Expanded(
                              child: Divider(color: AppColors.divider),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        OutlinedButton(
                          onPressed: _loading ? null : _signInWithGoogle,
                          // Навмисно окремий вигляд (залита поверхня, без
                          // рамки) — конвенція для кнопки стороннього
                          // провайдера входу, не звичайна другорядна дія
                          // застосунку.
                          style: OutlinedButton.styleFrom(
                            backgroundColor: AppColors.surface,
                            foregroundColor: AppColors.ink,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(l10n.continueWithGoogle),
                        ),

                        // Apple вимагає рівноцінну альтернативу для
                        // будь-якого стороннього логіну (Guideline 4.8) —
                        // тому тільки на iOS, на Android Google Sign-In
                        // лишається єдиним варіантом.
                        if (Platform.isIOS) ...[
                          const SizedBox(height: 12),
                          SignInWithAppleButton(
                            onPressed: _loading ? () {} : _signInWithApple,
                            text: l10n.signInWithApple,
                            height: 48,
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
