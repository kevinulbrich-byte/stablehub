import 'dart:async';

import 'url_helper.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://dbkomujdldqhrpppqfbr.supabase.co',
    publishableKey: 'sb_publishable_Dtv6t2yeJXoXFmrCAWyBbQ_ne-pPI5A',
  );

  runApp(const StableHubApp());
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Session? _session;
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    final client = Supabase.instance.client;
    _session = client.auth.currentSession;
    _authSubscription = client.auth.onAuthStateChange.listen((data) {
      if (mounted) setState(() => _session = data.session);
    });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Einladungen verwenden einen eigenen, signierten Token in der URL.
    // Dadurch wird die normale Registrierung nicht mit dem Einladungsablauf vermischt.
    final inviteToken = Uri.base.queryParameters['invite_token'];
    if (inviteToken != null && inviteToken.isNotEmpty) {
      return InvitationPage(key: ValueKey(inviteToken), token: inviteToken);
    }
    return _session == null ? const AuthPage() : const StableHubHome();
  }
}

class InvitationPage extends StatefulWidget {
  const InvitationPage({super.key, required this.token});
  final String token;

  @override
  State<InvitationPage> createState() => _InvitationPageState();
}

class _InvitationPageState extends State<InvitationPage> {
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _busy = false;
  bool _hidePassword = true;
  String? _message;
  bool _error = false;
  bool _accepted = false;

  @override
  void dispose() {
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _acceptInvitation() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || client.auth.currentSession == null) {
      setState(() {
        _message = 'Der Einladungslink konnte nicht bestätigt werden. Bitte öffne den Link direkt aus der Einladungs-E-Mail erneut.';
        _error = true;
      });
      return;
    }
    if (_password.text.length < 8) {
      setState(() {
        _message = 'Das Passwort muss mindestens 8 Zeichen haben.';
        _error = true;
      });
      return;
    }
    if (_password.text != _confirmPassword.text) {
      setState(() {
        _message = 'Die Passwörter stimmen nicht überein.';
        _error = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });
    try {
      // Erst Passwort festlegen, danach wird die Mitgliedschaft serverseitig angenommen.
      await client.auth.updateUser(UserAttributes(password: _password.text));
      final result = await client.functions.invoke(
        'stable-accept-invitation',
        body: {'token': widget.token},
      );
      if (result.status < 200 || result.status >= 300) {
        throw Exception(
          'Supabase hat die Einladung nicht angenommen (HTTP ${result.status}).',
        );
      }
      if (!mounted) return;
      setState(() {
        _accepted = true;
        _message = 'Passwort gespeichert und Einladung angenommen. Du kannst StableHub jetzt verwenden.';
        _error = false;
      });
    } on AuthException catch (e) {
      if (mounted)
        setState(() {
          _message = e.message;
          _error = true;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _message = 'Die Einladung konnte nicht abgeschlossen werden: $e';
          _error = true;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continueToApp() {
    // Entfernt den Einladungs-Token aus der Adresszeile, damit ein Neuladen
    // nicht erneut den bereits verwendeten Einladungslink öffnet.
    removeInviteTokenFromUrl();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const StableHubHome()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = Supabase.instance.client.auth.currentUser?.email ?? '';
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mail_lock_outlined,
                      size: 52,
                      color: forestGreen,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Einladung annehmen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: forestGreen,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Prüfe deine E-Mail-Adresse und lege ein persönliches Passwort fest, bevor du dem Stall beitrittst.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 22),
                    TextFormField(
                      initialValue: email,
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Eingeladene E-Mail-Adresse',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.mail_outline),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _password,
                      obscureText: _hidePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Neues Passwort',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _hidePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _hidePassword = !_hidePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _confirmPassword,
                      obscureText: _hidePassword,
                      decoration: const InputDecoration(
                        labelText: 'Passwort wiederholen',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!_busy && !_accepted) _acceptInvitation();
                      },
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _error ? const Color(0xFFFFE8E5) : mutedGreen,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            color: _error
                                ? const Color(0xFF8B1E14)
                                : forestGreen,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : (_accepted ? _continueToApp : _acceptInvitation),
                      style: FilledButton.styleFrom(
                        backgroundColor: forestGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _accepted
                                  ? 'Zu StableHub'
                                  : 'Passwort speichern und beitreten',
                            ),
                    ),
                    if (Supabase.instance.client.auth.currentSession ==
                        null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Für die Einladungssitzung fehlt die Anmeldung. Öffne bitte den Einladungslink direkt aus der E-Mail erneut.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  bool _obscurePassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      if (_isRegister) {
        final response = await auth.signUp(email: email, password: password);
        setState(() {
          _message = response.session == null
              ? 'Dein Konto wurde angelegt. Bitte bestÃ¤tige deine E-Mail-Adresse Ã¼ber den zugesandten Link. Danach kannst du dich anmelden.'
              : 'Registrierung erfolgreich. Du bist angemeldet.';
          _messageIsError = false;
        });
      } else {
        await auth.signInWithPassword(email: email, password: password);
      }
    } on AuthException catch (error) {
      setState(() {
        _message = error.message;
        _messageIsError = true;
      });
    } catch (_) {
      setState(() {
        _message = 'Ein unerwarteter Fehler ist aufgetreten. Bitte versuche es erneut.';
        _messageIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              color: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
                side: const BorderSide(color: beige),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: forestGreen,
                            borderRadius: BorderRadius.circular(19),
                          ),
                          child: const Icon(
                            Icons.calendar_month_rounded,
                            color: cream,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'StableHub',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: forestGreen,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _isRegister
                            ? 'Erstelle dein Benutzerkonto'
                            : 'Melde dich in deinem Stall an',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 28),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-Mail-Adresse',
                          prefixIcon: Icon(Icons.mail_outline),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final email = (value ?? '').trim();
                          if (email.isEmpty || !email.contains('@'))
                            return 'Bitte gib eine gÃ¼ltige E-Mail-Adresse ein.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofillHints: _isRegister
                            ? const [AutofillHints.newPassword]
                            : const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Passwort',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword
                                ? 'Passwort anzeigen'
                                : 'Passwort verbergen',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if ((value ?? '').length < 8)
                            return 'Das Passwort muss mindestens 8 Zeichen haben.';
                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _messageIsError
                                ? const Color(0xFFFFE8E5)
                                : mutedGreen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _messageIsError
                                  ? const Color(0xFF8B1E14)
                                  : forestGreen,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: forestGreen,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _isRegister ? 'Konto erstellen' : 'Anmelden',
                              ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _isRegister = !_isRegister;
                                _message = null;
                              }),
                        child: Text(
                          _isRegister
                              ? 'Ich habe bereits ein Konto â€“ anmelden'
                              : 'Noch kein Konto? Jetzt registrieren',
                          textAlign: TextAlign.center,
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
    );
  }
}

const Color forestGreen = Color(0xFF244C3A);
const Color cream = Color(0xFFF7F3E9);
const Color beige = Color(0xFFE7DDC9);
const Color mutedGreen = Color(0xFFDCE7DC);

class StableHubApp extends StatelessWidget {
  const StableHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StableHub',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: forestGreen,
          primary: forestGreen,
          surface: cream,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: cream,
          foregroundColor: forestGreen,
          elevation: 0,
        ),
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AuthGate(),
    );
  }
}

class StableHubHome extends StatefulWidget {
  const StableHubHome({super.key});

  @override
  State<StableHubHome> createState() => _StableHubHomeState();
}

class _StableHubHomeState extends State<StableHubHome> {
  int selectedIndex = 0;
  DateTime selectedDate = DateTime.now();
  final SupabaseClient _db = Supabase.instance.client;
  List<Map<String, dynamic>> _stables = [];
  List<Map<String, dynamic>> _arenas = [];
  List<Map<String, dynamic>> _bookings = [];
  String? _selectedStableId;
  bool _loadingStableData = true;
  String? _dataError;
  String? _calendarArenaId;
  bool _dayView = false;
  Map<String, dynamic> _profile = {};
  final Map<String, Map<String, dynamic>> _memberProfiles = {};
  List<Map<String, dynamic>> _members = [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadStables();
  }

  String _format24(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  String _myDisplayName() {
    final nickname = (_profile['nickname'] ?? '').toString().trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName =
        '${_profile['first_name'] ?? ''} ${_profile['last_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    return _db.auth.currentUser?.email ?? 'Mitglied';
  }

  String _bookingDisplayName(Map<String, dynamic> booking) {
    final userId = booking['created_by']?.toString();
    if (userId != null && userId == _db.auth.currentUser?.id)
      return _myDisplayName();
    final profile = userId == null ? null : _memberProfiles[userId];
    final nickname = (profile?['nickname'] ?? '').toString().trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName =
        '${profile?['first_name'] ?? ''} ${profile?['last_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    final title = (booking['title'] ?? '').toString().trim();
    return title.isEmpty || title.contains('@') ? 'Stallmitglied' : title;
  }

  bool _isOwnerOfSelectedStable() => _stables.any(
    (st) =>
        st['id'] == _selectedStableId &&
        st['owner_id'] == _db.auth.currentUser?.id,
  );

  bool _isAdminOfSelectedStable() => _members.any(
    (m) => m['user_id'] == _db.auth.currentUser?.id && m['role'] == 'admin',
  );

  Future<void> _loadProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return;
    try {
      final row = await _db
          .from('profiles')
          .select()
          .eq('user_id', user.id)
          .maybeSingle();
      if (mounted && row != null)
        setState(() => _profile = Map<String, dynamic>.from(row));
    } catch (_) {
      // Die Profil-Tabelle wird über die mitgelieferte SQL-Datei angelegt.
    }
  }

  Future<void> _loadMembers() async {
    final stableId = _selectedStableId;
    if (stableId == null) return;
    setState(() => _loadingMembers = true);
    try {
      final rows = await _db
          .from('stable_members')
          .select(
            'user_id,role,profiles(nickname,first_name,last_name,phone,horses,emergency_contact)',
          )
          .eq('stable_id', stableId);
      if (!mounted) return;
      final members = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _members = members;
        for (final member in members) {
          final uid = member['user_id']?.toString();
          final prof = member['profiles'];
          if (uid != null && prof is Map)
            _memberProfiles[uid] = Map<String, dynamic>.from(prof);
        }
      });
    } catch (e) {
      if (mounted)
        _showMessage(
          'Mitglieder konnten nicht geladen werden. Bitte zuerst die StableHub-SQL-Datei ausführen.',
        );
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _editProfile() async {
    final nickname = TextEditingController(
      text: _profile['nickname']?.toString() ?? '',
    );
    final first = TextEditingController(
      text: _profile['first_name']?.toString() ?? '',
    );
    final last = TextEditingController(
      text: _profile['last_name']?.toString() ?? '',
    );
    final phone = TextEditingController(
      text: _profile['phone']?.toString() ?? '',
    );
    final horses = TextEditingController(
      text: _profile['horses']?.toString() ?? '',
    );
    final emergency = TextEditingController(
      text: _profile['emergency_contact']?.toString() ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool busy = false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Kontoeinstellungen'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nickname,
                      decoration: const InputDecoration(
                        labelText: 'Nickname *',
                      ),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Bitte einen Nickname eingeben.'
                          : null,
                    ),
                    TextFormField(
                      controller: first,
                      decoration: const InputDecoration(labelText: 'Vorname'),
                    ),
                    TextFormField(
                      controller: last,
                      decoration: const InputDecoration(labelText: 'Nachname'),
                    ),
                    TextFormField(
                      controller: phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefonnummer',
                      ),
                    ),
                    TextFormField(
                      controller: horses,
                      decoration: const InputDecoration(
                        labelText: 'Pferd(e) / Pferdename',
                      ),
                    ),
                    TextFormField(
                      controller: emergency,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Notfallkontakt (Name und Telefonnummer)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Anmeldung: ${_db.auth.currentUser?.email ?? ''}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setDialogState(() => busy = true);
                      try {
                        final user = _db.auth.currentUser!;
                        final data = {
                          'user_id': user.id,
                          'nickname': nickname.text.trim(),
                          'first_name': first.text.trim(),
                          'last_name': last.text.trim(),
                          'phone': phone.text.trim(),
                          'horses': horses.text.trim(),
                          'emergency_contact': emergency.text.trim(),
                          'updated_at': DateTime.now()
                              .toUtc()
                              .toIso8601String(),
                        };
                        await _db
                            .from('profiles')
                            .upsert(data, onConflict: 'user_id');
                        if (dialogContext.mounted)
                          Navigator.pop(dialogContext, true);
                      } catch (e) {
                        setDialogState(() => busy = false);
                        if (this.context.mounted)
                          _showMessage(
                            'Profil konnte nicht gespeichert werden: $e',
                          );
                      }
                    },
              child: Text(busy ? 'Speichert…' : 'Speichern'),
            ),
          ],
        ),
      ),
    );
    for (final c in [nickname, first, last, phone, horses, emergency]) {
      c.dispose();
    }
    if (saved == true) {
      await _loadProfile();
      if (mounted) setState(() {});
      _showMessage('Kontoeinstellungen gespeichert.');
    }
  }

  Future<void> _inviteMember() async {
    final stableId = _selectedStableId;
    if (stableId == null) {
      _showMessage('Bitte zuerst einen Stall auswählen.');
      return;
    }
    final email = TextEditingController();
    String role = 'member';
    bool busy = false;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Mitglied per E-Mail einladen'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-Mail-Adresse',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(labelText: 'Rolle'),
                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Mitglied')),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Stalladministrator'),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() => role = v ?? 'member'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Die Einladung wird per E-Mail verschickt. Dafür muss die Edge Function in Supabase eingerichtet sein.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      final address = email.text.trim();
                      if (!address.contains('@')) {
                        _showMessage(
                          'Bitte eine gültige E-Mail-Adresse eingeben.',
                        );
                        return;
                      }
                      setDialogState(() => busy = true);
                      try {
                        await _db.functions.invoke(
                          'invite-stable-member',
                          body: {
                            'stable_id': stableId,
                            'email': address,
                            'role': role,
                          },
                        );
                        if (dialogContext.mounted)
                          Navigator.pop(dialogContext, true);
                      } catch (e) {
                        setDialogState(() => busy = false);
                        if (this.context.mounted)
                          _showMessage(
                            'Einladung fehlgeschlagen. Bitte SQL und Edge Function einrichten. Details: $e',
                          );
                      }
                    },
              child: Text(busy ? 'Sendet…' : 'Einladung senden'),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    if (sent == true) {
      await _loadMembers();
      if (mounted) _showMessage('Einladung wurde versendet.');
    }
  }

  Future<void> _changeMemberRole(
    Map<String, dynamic> member,
    String role,
  ) async {
    if (_selectedStableId == null ||
        member['user_id'] == _db.auth.currentUser?.id)
      return;
    try {
      await _db
          .from('stable_members')
          .update({'role': role})
          .eq('stable_id', _selectedStableId!)
          .eq('user_id', member['user_id']);
      await _loadMembers();
    } catch (e) {
      _showMessage('Rolle konnte nicht geändert werden: $e');
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    if (_selectedStableId == null ||
        member['user_id'] == _db.auth.currentUser?.id)
      return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mitglied entfernen?'),
        content: const Text(
          'Das Mitglied verliert den Zugang zu diesem Stall.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Entfernen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db
          .from('stable_members')
          .delete()
          .eq('stable_id', _selectedStableId!)
          .eq('user_id', member['user_id']);
      await _loadMembers();
    } catch (e) {
      _showMessage('Mitglied konnte nicht entfernt werden: $e');
    }
  }

  Future<void> _loadStables() async {
    if (mounted)
      setState(() {
        _loadingStableData = true;
        _dataError = null;
      });
    try {
      final userId = _db.auth.currentUser?.id;
      if (userId == null) throw Exception('Bitte melde dich erneut an.');
      final memberships = await _db
          .from('stable_members')
          .select('stable_id')
          .eq('user_id', userId);
      final ids = memberships.map((m) => m['stable_id'] as String).toList();
      List<Map<String, dynamic>> rows = [];
      if (ids.isNotEmpty) {
        final result = await _db
            .from('stables')
            .select('id,name,owner_id,created_at')
            .inFilter('id', ids)
            .order('created_at');
        rows = List<Map<String, dynamic>>.from(result);
      }
      if (!mounted) return;
      setState(() {
        _stables = rows;
        if (_selectedStableId == null ||
            !rows.any((s) => s['id'] == _selectedStableId)) {
          _selectedStableId = rows.isEmpty ? null : rows.first['id'] as String;
        }
      });
      await _loadStableDetails();
      if (_selectedStableId != null) await _loadMembers();
    } catch (e) {
      if (mounted)
        setState(
          () => _dataError = 'Stalldaten konnten nicht geladen werden: $e',
        );
    } finally {
      if (mounted) setState(() => _loadingStableData = false);
    }
  }

  Future<void> _loadStableDetails() async {
    final stableId = _selectedStableId;
    if (stableId == null) {
      if (mounted)
        setState(() {
          _arenas = [];
          _bookings = [];
        });
      return;
    }
    try {
      final arenaRows = await _db
          .from('riding_arenas')
          .select('id,stable_id,name,active,created_at')
          .eq('stable_id', stableId)
          .order('created_at');
      final bookingRows = await _db
          .from('bookings')
          .select(
            'id,stable_id,arena_id,created_by,title,starts_at,ends_at,usage_type,recurrence,comment',
          )
          .eq('stable_id', stableId)
          .order('starts_at');
      if (!mounted) return;
      setState(() {
        _arenas = List<Map<String, dynamic>>.from(arenaRows);
        _bookings = List<Map<String, dynamic>>.from(bookingRows);
      });
    } catch (e) {
      if (mounted)
        setState(
          () => _dataError =
              'Stallinformationen konnten nicht geladen werden: $e',
        );
    }
  }

  Future<void> _createStable() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Neuen Stall erstellen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name des Stalls',
            hintText: 'z. B. Reitanlage Sonnenhof',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Stall erstellen'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final newId = await _db.rpc(
        'create_stable',
        params: {'p_name': name.trim()},
      );
      if (mounted) {
        setState(() => _selectedStableId = newId.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stall wurde gespeichert.')),
        );
      }
      await _loadStables();
      if (mounted) setState(() => _selectedStableId = newId.toString());
      await _loadStableDetails();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stall konnte nicht erstellt werden: $e')),
        );
    }
  }

  Future<void> _createArena() async {
    final stableId = _selectedStableId;
    if (stableId == null) {
      _showMessage('Lege zuerst einen Stall an.');
      return;
    }
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reitplatz hinzufügen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Name des Reitplatzes',
            hintText: 'z. B. Außenplatz',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Abbrechen'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.pop(dialogContext, value);
            },
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      await _db.from('riding_arenas').insert({
        'stable_id': stableId,
        'name': name.trim(),
      });
      await _loadStableDetails();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reitplatz wurde gespeichert.')),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reitplatz konnte nicht gespeichert werden: $e'),
          ),
        );
    }
  }

  final List<String> weekdays = const [
    'Mo',
    'Di',
    'Mi',
    'Do',
    'Fr',
    'Sa',
    'So',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 78,
        title: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: forestGreen,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.calendar_month_rounded,
                color: cream,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'StableHub',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                    letterSpacing: -0.6,
                  ),
                ),
                Text(
                  'ALLES IM BLICK. ALLES IM STALL.',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 1.1,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.account_circle_outlined, size: 28),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: IndexedStack(
          index: selectedIndex,
          children: [
            _buildCalendarPage(),
            _buildArenaPage(),
            _buildStablePage(),
            _buildProfilePage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        backgroundColor: Colors.white,
        indicatorColor: mutedGreen,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Kalender',
          ),
          NavigationDestination(
            icon: Icon(Icons.fence_outlined),
            selectedIcon: Icon(Icons.fence),
            label: 'ReitplÃ¤tze',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups),
            label: 'Mein Stall',
          ),
          NavigationDestination(
            icon: Icon(Icons.manage_accounts_outlined),
            selectedIcon: Icon(Icons.manage_accounts),
            label: 'Konto',
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarPage() {
    final monday = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    ).subtract(Duration(days: selectedDate.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final visibleArenas = _arenas.where((a) => a['active'] != false).toList();
    final filtered = _bookings
        .where(
          (b) => _calendarArenaId == null || b['arena_id'] == _calendarArenaId,
        )
        .toList();
    final currentUserId = _db.auth.currentUser?.id;
    String dateLabel(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
    Color bookingColor(Map<String, dynamic> b) =>
        b['created_by'] == currentUserId
        ? const Color(0xFFDCE7DC)
        : const Color(0xFFF7DCDC);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Wochenübersicht',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: forestGreen,
                      ),
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null && mounted)
                        setState(() => selectedDate = d);
                    },
                    child: Text(dateLabel(selectedDate)),
                  ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Vorherige Woche',
                    onPressed: () => setState(
                      () => selectedDate = selectedDate.subtract(
                        const Duration(days: 7),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Nächste Woche',
                    onPressed: () => setState(
                      () => selectedDate = selectedDate.add(
                        const Duration(days: 7),
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => selectedDate = DateTime.now()),
                    icon: const Icon(Icons.today),
                    label: const Text('Heute'),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Woche'),
                        icon: Icon(Icons.view_week),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Tag'),
                        icon: Icon(Icons.calendar_view_day),
                      ),
                    ],
                    selected: {_dayView},
                    onSelectionChanged: (v) =>
                        setState(() => _dayView = v.first),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: visibleArenas.isEmpty
                        ? null
                        : () => _addBooking(),
                    icon: const Icon(Icons.add),
                    label: const Text('Buchung'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _calendarArenaId,
                decoration: const InputDecoration(
                  labelText: 'Reitplatzkalender',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Alle Plätze'),
                  ),
                  ...visibleArenas.map(
                    (a) => DropdownMenuItem<String?>(
                      value: a['id'] as String,
                      child: Text(a['name']?.toString() ?? 'Reitplatz'),
                    ),
                  ),
                ],
                onChanged: (v) => setState(() => _calendarArenaId = v),
              ),
            ],
          ),
        ),
        if (_dataError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _dataError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        if (_loadingStableData) const LinearProgressIndicator(),
        Expanded(
          child: _selectedStableId == null
              ? Center(
                  child: _emptyCard(
                    Icons.home_work_outlined,
                    'Noch kein Stall',
                    'Lege zuerst unter „Mein Stall“ einen Stall an.',
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final displayDays = _dayView ? [selectedDate] : days;
                    final double colWidth = _dayView
                        ? (constraints.maxWidth - 62).clamp(180.0, 500.0)
                        : 132.0;
                    return Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: 62 + displayDays.length * colWidth,
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  SizedBox(
                                    width: 62,
                                    height: 48,
                                    child: Container(
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'Uhr',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                  ...displayDays.map(
                                    (d) => SizedBox(
                                      width: colWidth,
                                      height: 48,
                                      child: Container(
                                        alignment: Alignment.center,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF0EDE5),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _dayView
                                                  ? [
                                                      'Montag',
                                                      'Dienstag',
                                                      'Mittwoch',
                                                      'Donnerstag',
                                                      'Freitag',
                                                      'Samstag',
                                                      'Sonntag',
                                                    ][d.weekday - 1]
                                                  : weekdays[d.weekday - 1],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(
                                              dateLabel(d),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: Column(
                                    children: List.generate(17, (hourIndex) {
                                      final hour = hourIndex + 6;
                                      return SizedBox(
                                        height: 58,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            SizedBox(
                                              width: 62,
                                              child: Container(
                                                alignment: Alignment.topCenter,
                                                padding: const EdgeInsets.only(
                                                  top: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  border: Border(
                                                    top: BorderSide(
                                                      color: beige,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  '${hour.toString().padLeft(2, '0')}:00',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            ...displayDays.map((d) {
                                              final dayBookings = filtered.where(
                                                (b) {
                                                  final dt = DateTime.tryParse(
                                                    b['starts_at']
                                                            ?.toString() ??
                                                        '',
                                                  )?.toLocal();
                                                  return dt != null &&
                                                      dt.year == d.year &&
                                                      dt.month == d.month &&
                                                      dt.day == d.day &&
                                                      dt.hour == hour;
                                                },
                                              ).toList();
                                              return SizedBox(
                                                width: colWidth,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    border: Border(
                                                      left: BorderSide(
                                                        color: beige,
                                                      ),
                                                      top: BorderSide(
                                                        color: beige,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Stack(
                                                    children: [
                                                      Positioned.fill(
                                                        child: Material(
                                                          color: Colors
                                                              .transparent,
                                                          child: InkWell(
                                                            onTap: () =>
                                                                _addBooking(
                                                                  initialDate:
                                                                      d,
                                                                  initialHour:
                                                                      hour,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                      if (dayBookings
                                                          .isNotEmpty)
                                                        Positioned.fill(
                                                          child: Column(
                                                            children: dayBookings.map((
                                                              b,
                                                            ) {
                                                              final dt =
                                                                  DateTime.tryParse(
                                                                    b['starts_at']
                                                                            ?.toString() ??
                                                                        '',
                                                                  )?.toLocal();
                                                              return Expanded(
                                                                child: Padding(
                                                                  padding:
                                                                      const EdgeInsets.all(
                                                                        2,
                                                                      ),
                                                                  child: Material(
                                                                    color:
                                                                        bookingColor(
                                                                          b,
                                                                        ),
                                                                    borderRadius:
                                                                        BorderRadius.circular(
                                                                          5,
                                                                        ),
                                                                    child: InkWell(
                                                                      onTap: () =>
                                                                          _showBookingDetails(
                                                                            b,
                                                                          ),
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            5,
                                                                          ),
                                                                      child: Container(
                                                                        padding:
                                                                            const EdgeInsets.all(
                                                                              3,
                                                                            ),
                                                                        decoration: BoxDecoration(
                                                                          borderRadius:
                                                                              BorderRadius.circular(
                                                                                5,
                                                                              ),
                                                                          border: Border(
                                                                            left: BorderSide(
                                                                              color: b['created_by'] == currentUserId ? forestGreen : Colors.redAccent,
                                                                              width: 3,
                                                                            ),
                                                                          ),
                                                                        ),
                                                                        child: Text(
                                                                          '${dt == null ? '' : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} '}${_bookingDisplayName(b)}',
                                                                          maxLines:
                                                                              3,
                                                                          overflow:
                                                                              TextOverflow.ellipsis,
                                                                          style: const TextStyle(
                                                                            fontSize:
                                                                                10,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ),
                                                              );
                                                            }).toList(),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }),
                                          ],
                                        ),
                                      );
                                    }),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Future<void> _addBooking({
    DateTime? initialDate,
    int? initialHour,
    Map<String, dynamic>? existing,
  }) async {
    final stableId = _selectedStableId;
    final user = _db.auth.currentUser;
    final arenas = _arenas.where((a) => a['active'] != false).toList();
    if (stableId == null || user == null) {
      _showMessage('Bitte zuerst anmelden und einen Stall auswählen.');
      return;
    }
    if (arenas.isEmpty) {
      _showMessage('Lege zuerst einen Reitplatz an.');
      return;
    }
    final isEdit = existing != null;
    if (isEdit && existing['created_by'] != user.id) {
      _showMessage('Du kannst nur deine eigenen Buchungen bearbeiten.');
      return;
    }
    final now = DateTime.now();
    final initialStart = existing == null
        ? DateTime(
            (initialDate ?? selectedDate).year,
            (initialDate ?? selectedDate).month,
            (initialDate ?? selectedDate).day,
            initialHour ?? (now.hour.clamp(6, 21)),
          )
        : DateTime.parse(existing['starts_at']).toLocal();
    DateTime bookingDate = initialStart;
    TimeOfDay startTime = TimeOfDay.fromDateTime(initialStart);
    String? arenaId =
        existing?['arena_id']?.toString() ??
        (_calendarArenaId != null &&
                arenas.any((a) => a['id'] == _calendarArenaId)
            ? _calendarArenaId
            : arenas.first['id'] as String);
    int duration = existing == null
        ? 60
        : DateTime.parse(existing['ends_at'])
              .difference(DateTime.parse(existing['starts_at']))
              .inMinutes
              .clamp(15, 720);
    String usage = existing?['usage_type']?.toString() ?? 'general';
    String recurrence = existing?['recurrence']?.toString() ?? 'none';
    final commentController = TextEditingController(
      text: existing?['comment']?.toString() ?? '',
    );
    bool busy = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, dialogSetState) => AlertDialog(
          title: Text(isEdit ? 'Buchung bearbeiten' : 'Buchung eintragen'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: arenaId,
                    decoration: const InputDecoration(labelText: 'Reitplatz'),
                    items: arenas
                        .map(
                          (a) => DropdownMenuItem(
                            value: a['id'] as String,
                            child: Text(a['name'].toString()),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => dialogSetState(() => arenaId = v),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.calendar_month),
                    title: const Text('Datum'),
                    subtitle: Text(
                      '${bookingDate.day.toString().padLeft(2, '0')}.${bookingDate.month.toString().padLeft(2, '0')}.${bookingDate.year}',
                    ),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: bookingDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (d != null)
                        dialogSetState(
                          () => bookingDate = DateTime(
                            d.year,
                            d.month,
                            d.day,
                            startTime.hour,
                            startTime.minute,
                          ),
                        );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule),
                    title: const Text('Startzeit'),
                    subtitle: Text(_format24(startTime) + ' Uhr'),
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (t != null) dialogSetState(() => startTime = t);
                    },
                  ),
                  DropdownButtonFormField<int>(
                    value: duration,
                    decoration: const InputDecoration(labelText: 'Dauer'),
                    items: [30, 45, 60, 90, 120, 180, 240, 480, 960]
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(
                              m >= 60
                                  ? '${m ~/ 60} Std${m % 60 == 0 ? '' : ' ${m % 60} Min'}'
                                  : '$m Minuten',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => dialogSetState(() => duration = v ?? 60),
                  ),
                  DropdownButtonFormField<String>(
                    value: usage,
                    decoration: const InputDecoration(labelText: 'Nutzungsart'),
                    items: const [
                      DropdownMenuItem(
                        value: 'general',
                        child: Text(
                          'Allgemeinnutzung – Platz darf mitbenutzt werden',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'exclusive',
                        child: Text('Alleinnutzung – Platz exklusiv'),
                      ),
                    ],
                    onChanged: (v) =>
                        dialogSetState(() => usage = v ?? 'general'),
                  ),
                  DropdownButtonFormField<String>(
                    value: recurrence,
                    decoration: const InputDecoration(
                      labelText: 'Wiederholung',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('Einmaliger Termin'),
                      ),
                      DropdownMenuItem(
                        value: 'weekly',
                        child: Text('Wöchentlich'),
                      ),
                    ],
                    onChanged: (v) =>
                        dialogSetState(() => recurrence = v ?? 'none'),
                  ),
                  TextField(
                    controller: commentController,
                    decoration: const InputDecoration(
                      labelText: 'Kommentar (optional)',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Gebucht von: ${_myDisplayName()}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (arenaId == null) return;
                      dialogSetState(() => busy = true);
                      try {
                        final start = DateTime(
                          bookingDate.year,
                          bookingDate.month,
                          bookingDate.day,
                          startTime.hour,
                          startTime.minute,
                        );
                        final end = start.add(Duration(minutes: duration));
                        final query = _db
                            .from('bookings')
                            .select('id,starts_at,ends_at,usage_type')
                            .eq('arena_id', arenaId!)
                            .lt('starts_at', end.toUtc().toIso8601String())
                            .gt('ends_at', start.toUtc().toIso8601String());
                        final conflicts = await query;
                        final others = List<Map<String, dynamic>>.from(
                          conflicts,
                        ).where((b) => b['id'] != existing?['id']).toList();
                        if (others.isNotEmpty &&
                            (usage == 'exclusive' ||
                                others.any(
                                  (b) => b['usage_type'] == 'exclusive',
                                ))) {
                          dialogSetState(() => busy = false);
                          if (context.mounted)
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Dieser Zeitraum kollidiert mit einer exklusiven Buchung.',
                                ),
                              ),
                            );
                          return;
                        }
                        final data = {
                          'stable_id': stableId,
                          'arena_id': arenaId,
                          'created_by': user.id,
                          'title': _myDisplayName(),
                          'starts_at': start.toUtc().toIso8601String(),
                          'ends_at': end.toUtc().toIso8601String(),
                          'usage_type': usage,
                          'recurrence': recurrence,
                          'comment': commentController.text.trim().isEmpty
                              ? null
                              : commentController.text.trim(),
                        };
                        if (isEdit) {
                          await _db
                              .from('bookings')
                              .update(data)
                              .eq('id', existing['id'])
                              .eq('created_by', user.id);
                        } else {
                          await _db.from('bookings').insert(data);
                        }
                        if (dialogContext.mounted)
                          Navigator.pop(dialogContext, true);
                      } catch (e) {
                        dialogSetState(() => busy = false);
                        if (this.context.mounted)
                          _showMessage(
                            'Buchung konnte nicht gespeichert werden: $e',
                          );
                      }
                    },
              child: Text(busy ? 'Speichert…' : 'Speichern'),
            ),
          ],
        ),
      ),
    );
    commentController.dispose();
    if (result == true) {
      await _loadStableDetails();
      if (mounted) _showMessage('Buchung gespeichert.');
    }
  }

  Future<void> _showBookingDetails(Map<String, dynamic> booking) async {
    final userId = _db.auth.currentUser?.id;
    final start = DateTime.parse(booking['starts_at']).toLocal();
    final end = DateTime.parse(booking['ends_at']).toLocal();
    final own = booking['created_by'] == userId;
    final arena =
        _arenas
            .where((a) => a['id'] == booking['arena_id'])
            .map((a) => a['name'])
            .firstOrNull ??
        'Reitplatz';
    final action = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(_bookingDisplayName(booking)),
        content: Text(
          '$arena\n${start.day}.${start.month}.${start.year}\n${_format24(TimeOfDay.fromDateTime(start))}–${_format24(TimeOfDay.fromDateTime(end))}\n${booking['usage_type'] == 'exclusive' ? 'Alleinnutzung' : 'Allgemeinnutzung'}\n${booking['comment'] ?? ''}\n\n${own ? 'Deine Buchung' : 'Buchung eines anderen Mitglieds'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Schließen'),
          ),
          if (own)
            TextButton(
              onPressed: () => Navigator.pop(c, 'delete'),
              child: const Text('Löschen'),
            ),
          if (own)
            FilledButton(
              onPressed: () => Navigator.pop(c, 'edit'),
              child: const Text('Bearbeiten'),
            ),
        ],
      ),
    );
    if (action == 'edit') await _addBooking(existing: booking);
    if (action == 'delete' && own) {
      try {
        await _db
            .from('bookings')
            .delete()
            .eq('id', booking['id'])
            .eq('created_by', userId!);
        await _loadStableDetails();
        if (mounted) _showMessage('Buchung gelöscht.');
      } catch (e) {
        if (mounted) _showMessage('Buchung konnte nicht gelöscht werden: $e');
      }
    }
  }

  Widget _buildArenaPage() {
    final activeArenas = _arenas.where((a) => a['active'] != false).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Reitplätze',
                style: TextStyle(
                  fontSize: 26,
                  color: forestGreen,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: _selectedStableId == null ? null : _createArena,
              tooltip: 'Reitplatz hinzufügen',
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Die Reitplätze deines ausgewählten Stalls.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 16),
        if (_stables.length > 1) _stableSelector(),
        if (_loadingStableData)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!_loadingStableData && _selectedStableId == null)
          _emptyCard(
            Icons.home_work_outlined,
            'Noch kein Stall',
            'Lege unter „Mein Stall“ zuerst deinen Stall an.',
          ),
        if (!_loadingStableData &&
            _selectedStableId != null &&
            activeArenas.isEmpty)
          _emptyCard(
            Icons.fence,
            'Noch keine Reitplätze',
            'Über das Plus kannst du deinen ersten Reitplatz hinzufügen.',
          ),
        ...activeArenas.map(
          (a) => Card(
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: mutedGreen,
                child: Icon(Icons.fence, color: forestGreen),
              ),
              title: Text(a['name']?.toString() ?? 'Reitplatz'),
              subtitle: const Text('In Supabase gespeichert'),
              trailing: IconButton(
                tooltip: 'Deaktivieren',
                icon: const Icon(Icons.archive_outlined),
                onPressed: () async {
                  try {
                    await _db
                        .from('riding_arenas')
                        .update({'active': false})
                        .eq('id', a['id']);
                    await _loadStableDetails();
                  } catch (e) {
                    if (mounted)
                      _showMessage(
                        'Reitplatz konnte nicht deaktiviert werden: $e',
                      );
                  }
                },
              ),
            ),
          ),
        ),
        if (_dataError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_dataError!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _buildStablePage() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Mein Stall',
                style: TextStyle(
                  fontSize: 26,
                  color: forestGreen,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: _createStable,
              icon: const Icon(Icons.add),
              label: const Text('Stall erstellen'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Deine Ställe und die zugehörigen Reitplätze verwalten.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        if (_loadingStableData)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!_loadingStableData && _stables.isEmpty)
          _emptyCard(
            Icons.home_work_outlined,
            'Willkommen bei StableHub',
            'Erstelle deinen ersten Stall. Er wird deinem Benutzerkonto zugeordnet und dauerhaft gespeichert.',
          ),
        if (_stables.length > 1) _stableSelector(),
        ..._stables.map(
          (stable) => Card(
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: mutedGreen,
                child: Icon(Icons.home_work_outlined, color: forestGreen),
              ),
              title: Text(
                stable['name']?.toString() ?? 'Mein Stall',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                stable['owner_id'] == _db.auth.currentUser?.id
                    ? 'Du bist Eigentümer'
                    : 'Mitglied',
              ),
              trailing: Radio<String>(
                value: stable['id'] as String,
                groupValue: _selectedStableId,
                onChanged: (value) async {
                  setState(() => _selectedStableId = value);
                  await _loadStableDetails();
                  await _loadMembers();
                },
              ),
              onTap: () async {
                setState(() => _selectedStableId = stable['id'] as String);
                await _loadStableDetails();
                await _loadMembers();
              },
            ),
          ),
        ),
        if (_selectedStableId != null)
          _infoCard(
            Icons.fence,
            'Reitplätze',
            '${_arenas.length} Reitplatz/Reitplätze in diesem Stall',
          ),
        if (_selectedStableId != null)
          Card(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Mitglieder verwalten',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (_isOwnerOfSelectedStable() ||
                          _isAdminOfSelectedStable())
                        FilledButton.icon(
                          onPressed: _inviteMember,
                          icon: const Icon(Icons.person_add_alt_1),
                          label: const Text('Einladen'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_loadingMembers)
                    const Center(child: CircularProgressIndicator()),
                  if (!_loadingMembers && _members.isEmpty)
                    const Text(
                      'Noch keine Mitglieder geladen. Tippe auf „Einladen“ oder prüfe die Supabase-Einrichtung.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ..._members.map((m) {
                    final prof = m['profiles'] is Map
                        ? Map<String, dynamic>.from(m['profiles'])
                        : <String, dynamic>{};
                    final name =
                        (prof['nickname'] ?? '').toString().trim().isNotEmpty
                        ? prof['nickname'].toString()
                        : ('${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'
                                  .trim()
                                  .isEmpty
                              ? 'Mitglied'
                              : '${prof['first_name'] ?? ''} ${prof['last_name'] ?? ''}'
                                    .trim());
                    final isSelf = m['user_id'] == _db.auth.currentUser?.id;
                    final owner = _isOwnerOfSelectedStable();
                    final canManage = owner || _isAdminOfSelectedStable();
                    return ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.person_outline),
                      ),
                      title: Text(name),
                      subtitle: Text(
                        m['role'] == 'admin'
                            ? 'Stalladministrator'
                            : 'Mitglied',
                      ),
                      trailing: canManage && !isSelf
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'member' || v == 'admin')
                                  _changeMemberRole(m, v);
                                if (v == 'remove') _removeMember(m);
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'member',
                                  child: Text('Als Mitglied setzen'),
                                ),
                                if (owner)
                                  const PopupMenuItem(
                                    value: 'admin',
                                    child: Text('Zum Administrator machen'),
                                  ),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Mitglied entfernen'),
                                ),
                              ],
                            )
                          : null,
                    );
                  }),
                ],
              ),
            ),
          ),
        if (_dataError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_dataError!, style: const TextStyle(color: Colors.red)),
          ),
      ],
    );
  }

  Widget _buildProfilePage() {
    final user = _db.auth.currentUser;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Kontoeinstellungen',
          style: TextStyle(
            fontSize: 26,
            color: forestGreen,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Dein Nickname wird im Kalender anstelle deiner E-Mail-Adresse angezeigt.',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        Card(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: mutedGreen,
                      child: Icon(Icons.person, color: forestGreen, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _myDisplayName(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),
                _profileLine('Vorname', _profile['first_name']),
                _profileLine('Nachname', _profile['last_name']),
                _profileLine('Telefonnummer', _profile['phone']),
                _profileLine('Pferd(e)', _profile['horses']),
                _profileLine('Notfallkontakt', _profile['emergency_contact']),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _editProfile,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Profil bearbeiten'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await _db.auth.signOut();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Abmelden'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileLine(String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 145,
          child: Text(label, style: const TextStyle(color: Colors.black54)),
        ),
        Expanded(
          child: Text(
            (value ?? '').toString().trim().isEmpty ? '–' : value.toString(),
          ),
        ),
      ],
    ),
  );

  Widget _stableSelector() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      value: _selectedStableId,
      decoration: const InputDecoration(
        labelText: 'Aktiver Stall',
        border: OutlineInputBorder(),
      ),
      items: _stables
          .map(
            (s) => DropdownMenuItem<String>(
              value: s['id'] as String,
              child: Text(s['name']?.toString() ?? 'Stall'),
            ),
          )
          .toList(),
      onChanged: (value) async {
        setState(() => _selectedStableId = value);
        await _loadStableDetails();
        await _loadMembers();
      },
    ),
  );

  Widget _emptyCard(IconData icon, String title, String subtitle) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: beige),
    ),
    child: Column(
      children: [
        Icon(icon, size: 40, color: forestGreen),
        const SizedBox(height: 10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
      ],
    ),
  );

  Widget _infoCard(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: beige),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: mutedGreen,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: forestGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
