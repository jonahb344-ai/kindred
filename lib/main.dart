// ============================================================
// KINDRED — Community Mutual Aid App
// Copyright (C) 2026 Jonah Boyd. All rights reserved.
//
// This program is free software: you can redistribute it
// and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation,
// either version 3 of the License, or any later version.
//
// This program is distributed in the hope that it will be
// useful, but WITHOUT ANY WARRANTY; without even the implied
// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
// PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public
// License along with this program. If not, see:
// https://www.gnu.org/licenses/
//
// GitHub: https://github.com/jonahb344-ai/kindred/tree/main
// Contact: jonahb344@gmail.com
//
// Built by Jonah — 8th grader from Bartlett, TN.
// Started summer 2026 as a neighborhood kindness project.
// The idea: neighbors helping neighbors with small stuff
// (groceries, yard work, rides, etc) — all free, no catch.
// ============================================================
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

final FlutterLocalNotificationsPlugin localNotifications = FlutterLocalNotificationsPlugin();
int _localNotifId = 0;

ImageProvider? _avatarImage(Object? url) {
  if (url == null) return null;
  final s = url.toString();
  if (s.isEmpty) return null;
  if (s.startsWith('data:')) {
    final idx = s.indexOf(',');
    if (idx < 0) return null;
    try {
      return MemoryImage(base64Decode(s.substring(idx + 1)));
    } catch (_) {
      return null;
    }
  }
  return NetworkImage(s);
}

Future<String> _myPhotoUrl() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return '';
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return (doc.data()?['photoUrl'] as String?) ?? '';
  } catch (_) {
    return '';
  }
}

@pragma('vm:entry-point')
// required for background FCM — the OS handles display, we just need this function to exist
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
}

// sets up local notifications + foreground FCM listener (android only)
Future<void> _initNotifications() async {
  await FirebaseMessaging.instance.requestPermission(alert: true, badge: true, sound: true);
  const settings = InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher'));
  await localNotifications.initialize(settings: settings);
  FirebaseMessaging.onMessage.listen((message) async {
    // foreground messages need manual display via flutter_local_notifications
    await localNotifications.show(
      id: _localNotifId++,
      title: message.notification?.title ?? 'Kindred',
      body: message.notification?.body ?? '',
      notificationDetails: const NotificationDetails(android: AndroidNotificationDetails(
        'kindred_notifications',
        'Kindred notifications',
        channelDescription: 'Messages and request updates',
        importance: Importance.high,
        priority: Priority.high,
      )),
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // web needs explicit options, android auto-detects from google-services.json
  if (kIsWeb) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } else {
    await Firebase.initializeApp();
  }
  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _initNotifications();
  }
  runApp(const KindredApp());
}

const String reportEmail = 'jonahb344+kindred@gmail.com';

// Worker URL — runs on Cloudflare free tier, holds API keys server-side
const String kServerBaseUrl = 'https://kindred.jonahb344.workers.dev';

// level thresholds — tweak these to change progression speed
const int helperThreshold = 50;
const int championThreshold = 150;
const int legendThreshold = 500;
const int pointsPerAct = 5;

// photos for the onboarding screens
const String kImgVolunteers = 'assets/volunteers.jpg';
const String kImgCleanup = 'assets/cleanup.jpg';

// map tile sources — CartoDB for normal view, Esri for satellite
const String kTilesLight =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png';
const String kTilesSatellite =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
const List<String> kTileSubdomains = ['a', 'b', 'c', 'd'];

// theme colors — dark mode is the default, light mode added later
bool _appIsDark = true;

Color get kBackground => _appIsDark ? const Color(0xFF0B1220) : const Color(0xFFF5F8FA);
Color get kCard => _appIsDark ? const Color(0xFF141E30) : const Color(0xFFFFFFFF);
Color get kCardLight => _appIsDark ? const Color(0xFF1E2B42) : const Color(0xFFEAF0F4);
Color get kAccent => _appIsDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488);
Color get kAccentDark => _appIsDark ? const Color(0xFF14B8A6) : const Color(0xFF0F766E);
Color get kBadge => _appIsDark ? kAccent : const Color(0xFF3B82F6);
// (kBadge is blue in light mode — gold clashed with the cards, tried it, didn't like it)
Color get kTextPrimary => _appIsDark ? const Color(0xFFE7EDF4) : const Color(0xFF0F172A);
Color get kTextSecondary => _appIsDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
Color get kDivider => _appIsDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0);

LinearGradient get kAccentGradient => LinearGradient(
  colors: _appIsDark
      ? [const Color(0xFF14B8A6), const Color(0xFF34D399)]
      : [const Color(0xFF0D9488), const Color(0xFF10B981)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

BoxShadow get kCardShadow => BoxShadow(
  color: _appIsDark ? const Color(0x4D000000) : const Color(0x140F172A),
  blurRadius: 24,
  offset: const Offset(0, 8),
);

BoxShadow get kSoftShadow => BoxShadow(
  color: _appIsDark ? const Color(0x33000000) : const Color(0x0A0F172A),
  blurRadius: 12,
  offset: const Offset(0, 4),
);

Color _categoryColor(String cat) {
  // each category gets its own color for the chip/label
  switch (cat) {
    case 'Grocery Run': return const Color(0xFF16A34A);
    case 'Lawn Care': return const Color(0xFF0D9488);
    case 'Moving Help': return const Color(0xFFF59E0B);
    case 'Pet Care': return const Color(0xFFEC4899);
    case 'Meal Prep': return const Color(0xFFF97316);
    case 'Give a Ride': return const Color(0xFF3B82F6);
    default: return kAccent;
  }
}

IconData _badgeIcon(String b) {
  // matching badges to material icons — took a while to find ones that felt right
  switch (b) {
    case 'first_act': return Icons.eco;
    case '10_acts': return Icons.grade;
    case '50_acts': return Icons.emoji_events;
    case 'helper': return Icons.handshake;
    case 'champion': return Icons.military_tech;
    case 'legend': return Icons.workspace_premium;
    default: return Icons.military_tech;
  }
}

IconData _levelIcon(String level) {
  switch (level) {
    case 'Helper': return Icons.handshake;
    case 'Champion': return Icons.emoji_events;
    case 'Legend': return Icons.workspace_premium;
    default: return Icons.eco;
  }
}

IconData _categoryIcon(String cat) {
  switch (cat) {
    case 'Grocery Run': return Icons.shopping_cart;
    case 'Lawn Care': return Icons.yard;
    case 'Moving Help': return Icons.inventory_2;
    case 'Pet Care': return Icons.pets;
    case 'Meal Prep': return Icons.restaurant;
    case 'Give a Ride': return Icons.directions_car;
    default: return Icons.favorite;
  }
}

String _categoryEmoji(String cat) {
  switch (cat) {
    case 'Grocery Run': return '🛒';
    case 'Lawn Care': return '🌿';
    case 'Moving Help': return '📦';
    case 'Pet Care': return '🐾';
    case 'Meal Prep': return '🍳';
    case 'Give a Ride': return '🚗';
    default: return '🌟';
  }
}

const List<Color> bannerColors = [
  Color(0xFF7BAE8A), Color(0xFF1565C0), Color(0xFF6A1B9A),
  Color(0xFFE65100), Color(0xFF37474F), Color(0xFFC62828),
];

// ─── APP ──────────────────────────────────────────────────────────────────────

class KindredApp extends StatefulWidget {
  const KindredApp({super.key});
  static _KindredAppState? of(BuildContext context) => context.findAncestorStateOfType<_KindredAppState>();

  @override
  State<KindredApp> createState() => _KindredAppState();
}

class _KindredAppState extends State<KindredApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemeFromUser();
  }

  // pull saved theme preference from Firestore on startup
  Future<void> _loadThemeFromUser() async {
    try {
      await FirebaseAuth.instance.authStateChanges().firstWhere((u) => u != null);
    } catch (_) {
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final mode = doc.data()?['themeMode'] as String?;
      if (mode != null && mounted) {
        final parsed = ThemeMode.values.where((m) => m.name == mode);
        if (parsed.isNotEmpty) setState(() => _themeMode = parsed.first);
      }
    } catch (_) {}
  }

  void setThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      FirebaseFirestore.instance.collection('users').doc(uid).set({'themeMode': mode.name}, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    final systemDark = dispatcher.platformBrightness == Brightness.dark;
    _appIsDark = _themeMode == ThemeMode.dark || (_themeMode == ThemeMode.system && systemDark);
    return MaterialApp(
      title: 'Kindred',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const AuthGate(),
      ),
    );
  }

  ThemeData _darkTheme() => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBackground,
    cardColor: kCard,
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF2DD4BF),
      secondary: Color(0xFF34D399),
      surface: Color(0xFF141E30),
    ),
    fontFamily: 'Roboto',
    useMaterial3: true,
  );

  ThemeData _lightTheme() => ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: kBackground,
    cardColor: kCard,
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF0D9488),
      secondary: Color(0xFF10B981),
      surface: Colors.white,
    ),
    fontFamily: 'Roboto',
    useMaterial3: true,
  );
}

// ─── HELPERS ──────────────────────────────────────────────────────────────────

Color get bg => kBackground;
Color get cardColor => kCard;
Color get accent => kAccent;
Color get textPrimary => kTextPrimary;
Color get textSecondary => kTextSecondary;

void _haptic() {
  // subtle tap feedback — works on mobile, no-op on web/desktop
  try {
    HapticFeedback.selectionClick();
  } catch (_) {}
}

void _hapticHeavy() {
  try {
    HapticFeedback.mediumImpact();
  } catch (_) {}
}

Future<void> _showConfetti(BuildContext context) async {
  // little celebration overlay after completing an act — people like confetti
  await Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.transparent,
    barrierDismissible: true,
    pageBuilder: (_, _, _) => const _ConfettiBurst(),
    transitionsBuilder: (_, _, _, child) => child,
  ));
}

Route<T> _fadeSlideRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 320),
  pageBuilder: (_, _, _) => page,
  transitionsBuilder: (_, animation, _, child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0.04, 0.04), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ),
);

Color _levelColor(String level) {
  switch (level) {
    case 'Helper': return Colors.blue;
    case 'Champion': return Colors.orange;
    case 'Legend': return const Color(0xFF7B1FA2);
    default: return kAccent;
  }
}

double _levelProgress(int score) {
  // returns 0.0-1.0 based on where the user is in their current level tier
  if (score >= legendThreshold) return 1.0;
  if (score >= championThreshold) return (score - championThreshold) / (legendThreshold - championThreshold);
  if (score >= helperThreshold) return (score - helperThreshold) / (championThreshold - helperThreshold);
  return score / helperThreshold;
}

String _levelNextMessage(int score) {
  if (score >= legendThreshold) return 'Max level reached';
  if (score >= championThreshold) return '${legendThreshold - score} pts to Legend';
  if (score >= helperThreshold) return '${championThreshold - score} pts to Champion';
  return '${helperThreshold - score} pts to Helper';
}

String _timeAgo(Timestamp? ts) {
  // "3m ago", "2h ago", "5d ago" — simple relative time
  if (ts == null) return '';
  final diff = DateTime.now().difference(ts.toDate());
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String _formatDate(Timestamp? timestamp) {
  if (timestamp == null) return 'Unknown';
  final date = timestamp.toDate();
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

String _formatDateTime(Timestamp ts) {
  final d = ts.toDate();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

Future<List<String>> _getBlockedUsers(String uid) async {
  final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
  return List<String>.from(snap.data()?['blockedUsers'] ?? []);
}

Future<void> _blockUser(BuildContext context, String uid, {String? name}) async {
  final current = FirebaseAuth.instance.currentUser;
  if (current == null) return;
  final confirm = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
    title: 'Block ${name ?? 'this user'}?',
    content: "They won't be able to contact you and their requests will be hidden from you.",
    actionText: 'Block',
    onAction: () => Navigator.pop(context, true),
    cancelText: 'Cancel',
    onCancel: () => Navigator.pop(context, false),
    destructive: true,
  ));
  if (confirm != true) return;
  await FirebaseFirestore.instance.collection('users').doc(current.uid).update({'blockedUsers': FieldValue.arrayUnion([uid])});
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User blocked.'), backgroundColor: kAccentDark));
}

Future<void> _unblockUser(BuildContext context, String uid) async {
  final current = FirebaseAuth.instance.currentUser;
  if (current == null) return;
  await FirebaseFirestore.instance.collection('users').doc(current.uid).update({'blockedUsers': FieldValue.arrayRemove([uid])});
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User unblocked.'), backgroundColor: kAccentDark));
}

Future<void> _deleteChat(BuildContext context, String requestId, String otherName) async {
  final confirm = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
    title: 'Delete this chat?',
    content: 'This permanently deletes the conversation and all messages with $otherName. This cannot be undone.',
    actionText: 'Delete',
    onAction: () => Navigator.pop(context, true),
    cancelText: 'Cancel',
    onCancel: () => Navigator.pop(context, false),
    destructive: true,
  ));
  if (confirm != true) return;
  try {
    final notifs = await FirebaseFirestore.instance.collection('notifications').where('chatId', isEqualTo: requestId).get();
    for (final n in notifs.docs) { await n.reference.delete(); }
    final msgs = await FirebaseFirestore.instance.collection('chats').doc(requestId).collection('messages').get();
    for (final m in msgs.docs) { await m.reference.delete(); }
    await FirebaseFirestore.instance.collection('chats').doc(requestId).delete();
    await FirebaseFirestore.instance.collection('requests').doc(requestId).delete();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Chat deleted.'), backgroundColor: kAccentDark));
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting chat: $e')));
  }
}

// builds a plain-text export of a chat for sharing/reports
Future<String?> _buildTranscript(String chatId) async {
  try {
    final snap = await FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').orderBy('createdAt').get();
    final lines = <String>[];
    for (final doc in snap.docs) {
      final m = doc.data();
      final sender = m['senderName'] ?? 'User';
      final text = m['text'] ?? '';
      final ts = m['createdAt'] as Timestamp?;
      lines.add('${ts != null ? _formatDateTime(ts) : '--'} $sender: $text');
    }
    return lines.isEmpty ? 'No messages in this chat.' : lines.join('\n');
  } catch (_) {
    return 'Unable to retrieve transcript.';
  }
}

// sends report emails via formsubmit.co — free tier, no backend needed
Future<bool> _sendReportEmail({required String subject, required Map<String, String> fields}) async {
  try {
    final response = await http.post(
      Uri.parse('https://formsubmit.co/$reportEmail'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/122.0 Safari/537.36',
        'Referer': 'https://kindred.app/',
      },
      body: {
        '_captcha': 'false',
        '_template': 'table',
        '_subject': subject,
        ...fields,
      },
    );
    return response.statusCode >= 200 && response.statusCode < 400;
  } catch (_) {
    return false;
  }
}

Future<void> _submitReport(BuildContext context, String reportedUid, String reportedName, String reason, String details, {String? chatId, bool alsoBlock = false}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  String? transcript;
  if (chatId != null) transcript = await _buildTranscript(chatId);
  await FirebaseFirestore.instance.collection('reports').add({
    'reportedBy': user.uid,
    'reportedByName': user.displayName,
    'reportedByEmail': user.email,
    'reportedUser': reportedUid,
    'reportedUserName': reportedName,
    'reason': reason,
    'details': details,
    'chatId': chatId,
    'transcript': transcript,
    'createdAt': FieldValue.serverTimestamp(),
  });
  if (alsoBlock) {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'blockedUsers': FieldValue.arrayUnion([reportedUid])});
  }
  final emailSent = await _sendReportEmail(
    subject: 'Kindred Report: $reason ($reportedName)',
    fields: {
      'Reporter': user.displayName ?? 'Unknown',
      'Reporter email': user.email ?? 'Not available',
      'Reported user': reportedName,
      'Reported user ID': reportedUid,
      'Reason': reason,
      'Details': details.isEmpty ? 'None provided' : details,
      if (chatId != null) 'Chat ID': chatId,
      'Chat transcript': transcript ?? 'Not available',
    },
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(emailSent
        ? 'Report submitted. Moderators have been notified by email.'
        : 'Report saved. Email notification failed to send.'),
    backgroundColor: emailSent ? kAccentDark : Colors.orange,
  ));
}

void _showReportSheet(BuildContext context, String reportedUid, String reportedName, {String? chatId}) {
  final reasons = ['Harassment or bullying', 'Inappropriate or abusive content', 'Suspicious or fraudulent behavior', 'Impersonation', 'Other'];
  String selectedReason = reasons.first;
  final detailsController = TextEditingController();
  bool alsoBlock = false;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(builder: (context, setModalState) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: kCard, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kDivider, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Text('Report $reportedName', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextPrimary)),
          const SizedBox(height: 4),
          Text(chatId != null ? 'A report is sent to Kindred moderators along with your chat transcript.' : 'A report is sent to Kindred moderators.', style: TextStyle(fontSize: 13, color: kTextSecondary)),
          const SizedBox(height: 20),
          Text('Reason', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: reasons.map((r) {
            final selected = selectedReason == r;
            return GestureDetector(
              onTap: () => setModalState(() => selectedReason = r),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFEF4444) : kCardLight,
                  borderRadius: BorderRadius.circular(20),
                  border: selected ? Border.all(color: const Color(0xFFEF4444)) : null,
                ),
                child: Text(r, style: TextStyle(color: selected ? Colors.white : kTextSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, fontSize: 13)),
              ),
            );
          }).toList()),
          const SizedBox(height: 16),
          Text('Details', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
          const SizedBox(height: 8),
          TextField(controller: detailsController, maxLines: 3, maxLength: 300, style: TextStyle(color: kTextPrimary),
              decoration: InputDecoration(hintText: 'Add any details that help us understand the issue...', hintStyle: TextStyle(color: kTextSecondary), filled: true, fillColor: kCardLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), counterStyle: TextStyle(color: kTextSecondary))),
          const SizedBox(height: 12),
          Row(children: [
            Checkbox(value: alsoBlock, onChanged: (v) => setModalState(() => alsoBlock = v ?? false), activeColor: const Color(0xFFEF4444)),
            Expanded(child: Text('Also block this user', style: TextStyle(color: kTextPrimary, fontSize: 14))),
          ]),
          const SizedBox(height: 8),
          _KindredButton(
            label: 'Submit Report',
            destructive: true,
            onPressed: () async {
              Navigator.pop(context);
              await _submitReport(context, reportedUid, reportedName, selectedReason, detailsController.text.trim(), chatId: chatId, alsoBlock: alsoBlock);
            },
          ),
        ])),
      ),
    )),
  );
}

bool get _isWeekend {
  final day = DateTime.now().weekday;
  return day == DateTime.saturday || day == DateTime.sunday;
}

int get _currentPoints => _isWeekend ? pointsPerAct * 2 : pointsPerAct;

// ─── AUTH GATE ────────────────────────────────────────────────────────────────
// decides what to show based on auth state — login, verify email, onboarding, or main app

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(body: Center(child: CircularProgressIndicator(color: kAccent)));
        }
        if (snapshot.hasData) {
          final user = snapshot.data!;
          final isEmailUser = user.providerData.any((p) => p.providerId == 'password');
          if (isEmailUser && !user.emailVerified) return const VerifyEmailScreen();
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
            builder: (context, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting) {
                return Scaffold(body: Center(child: CircularProgressIndicator(color: kAccent)));
              }
              final data = userSnap.data?.data() as Map<String, dynamic>?;
              final setupDone = data?['setupDone'] ?? false;
              final tutorialDone = data?['tutorialDone'] ?? false;
              if (!setupDone) return const OnboardingScreen();
              if (!tutorialDone) return const TutorialScreen();
              return const MainScreen();
            },
          );
        }
        return const LoginScreen();
      },
    );
  }
}

// ─── LOGIN ────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isSignUp = false;
  bool _obscure = true;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _ensureUserDoc(User user) async {
    // create user doc in Firestore if it doesn't exist yet (first sign-in)
    final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await doc.get();
    if (!snap.exists) {
      await doc.set({
        'name': user.displayName ?? user.email ?? 'Neighbor', 'username': '', 'bio': '',
        'photoUrl': user.photoURL ?? '', 'bannerColor': 0xFF7BAE8A,
        'frameStyle': 'none', 'kindnessScore': 0, 'level': 'Newcomer',
        'actsCompleted': 0, 'streak': 0, 'lastActDate': null, 'badges': [],
        'setupDone': false, 'tutorialDone': false, 'blockedUsers': [],
        'notifMessages': true, 'notifRequests': true, 'language': 'English',
        'nearbyRadiusMi': 1.0,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    }
    final token = kIsWeb ? null : await FirebaseMessaging.instance.getToken();
    await FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('private').doc('data')
        .set({'email': user.email, 'phone': '', 'fcmToken': token}, SetOptions(merge: true));
    _updateMyLocation();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      User? user;
      // web uses popup (can't do native GoogleSignIn on browser), android uses the plugin
      if (kIsWeb) {
        final userCredential = await FirebaseAuth.instance.signInWithPopup(GoogleAuthProvider());
        user = userCredential.user;
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) { setState(() => _isLoading = false); return; }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
        final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
        user = userCredential.user;
      }
      if (user != null) await _ensureUserDoc(user);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sign in failed: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitWithEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    if (!_isValidEmail(email)) {
      _toast('Please enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      _toast('Password must be at least 6 characters.');
      return;
    }
    if (_isSignUp && name.isEmpty) {
      _toast('Please enter your name.');
      return;
    }
    setState(() => _isLoading = true);
    try {
      if (_isSignUp) {
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = userCredential.user;
        if (user != null) {
          await user.updateProfile(displayName: name);
          await _ensureUserDoc(user);
          await user.sendEmailVerification(_verificationSettings());
        }
      } else {
        final userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        final user = userCredential.user;
        if (user != null) await _ensureUserDoc(user);
      }
    } catch (e) {
      _toast(_friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  ActionCodeSettings _verificationSettings() => ActionCodeSettings(
    url: 'https://kindred.jonahb344.workers.dev/verified',
    handleCodeInApp: false,
  );

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

String _friendlyAuthError(Object error) {
  // map Firebase error codes to plain-English messages
  if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'email-already-in-use': return 'That email is already registered. Try signing in instead.';
        case 'invalid-email': return 'That email address doesn\'t look right.';
        case 'weak-password': return 'Password must be at least 6 characters.';
        case 'user-not-found': return 'No account found with that email.';
        case 'wrong-password':
        case 'invalid-credential': return 'Incorrect email or password.';
        case 'too-many-requests': return 'Too many attempts. Please try again later.';
        case 'network-request-failed': return 'No internet connection. Check your connection and try again.';
        case 'user-disabled': return 'This account has been disabled.';
        case 'operation-not-allowed': return 'Email sign-in isn\'t enabled yet. Please try Google instead.';
      }
    }
    return 'Something went wrong: $error';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      resizeToAvoidBottomInset: true,
      body: Stack(children: [
        Positioned.fill(child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF0D9488).withValues(alpha: 0.92), const Color(0xFF134E4A).withValues(alpha: 0.85), const Color(0xFF0B1220).withValues(alpha: 0.95)],
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
            ),
          ),
        )),
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 72, 28, 28),
            child: Column(
              children: [
                _StaggerIn(child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset('assets/logo_banner_login.png', width: 260, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 26),
                  const Text('Neighbors helping neighbors.', style: TextStyle(fontSize: 15, color: Colors.white70)),
                ])),
                const SizedBox(height: 36),
                _StaggerIn(delayMs: 120, child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _Pressable(
                    onTap: _isLoading ? null : _signInWithGoogle,
                    child: Container(
                      width: double.infinity, height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.network('https://www.google.com/favicon.ico', height: 20, width: 20),
                          const SizedBox(width: 12),
                          Text('Continue with Google', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _isLoading ? const Color(0xFF94A3B8) : const Color(0xFF0F172A))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(children: [
                    const Expanded(child: Divider(color: Colors.white24)),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or with email', style: TextStyle(fontSize: 12, color: Colors.white70))),
                    const Expanded(child: Divider(color: Colors.white24)),
                  ]),
                ])),
                const SizedBox(height: 18),
                _StaggerIn(delayMs: 200, child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10))],
                  ),
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: _loginTab('Sign In', !_isSignUp, () => setState(() => _isSignUp = false))),
                      const SizedBox(width: 8),
                      Expanded(child: _loginTab('Create Account', _isSignUp, () => setState(() => _isSignUp = true))),
                    ]),
                    const SizedBox(height: 16),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _isSignUp
                          ? Column(key: const ValueKey('signup'), crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _loginField(_nameController, 'Your name', Icons.person_outline_rounded, textCapitalization: TextCapitalization.words),
                              const SizedBox(height: 12),
                              _loginField(_emailController, 'Email', Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress),
                              const SizedBox(height: 12),
                              _passwordField(),
                            ])
                          : Column(key: const ValueKey('signin'), children: [
                              _loginField(_emailController, 'Email', Icons.mail_outline_rounded, keyboardType: TextInputType.emailAddress),
                              const SizedBox(height: 12),
                              _passwordField(),
                            ]),
                    ),
                    const SizedBox(height: 18),
                    _KindredButton(
                      label: _isSignUp ? 'Create Account' : 'Sign In',
                      loading: _isLoading,
                      onPressed: _isLoading ? null : _submitWithEmail,
                    ),
                  ]),
                )),
                const SizedBox(height: 20),
                const Text('By continuing you agree to our Terms of Service', style: TextStyle(fontSize: 11, color: Colors.white70)),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _loginTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? kAccent : kCardLight,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: active ? Colors.white : kTextSecondary,
          ),
        ),
      ),
    );
  }

  InputDecoration _loginDecoration(String hint, IconData icon) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: kTextSecondary),
    prefixIcon: Icon(icon, color: kTextSecondary, size: 20),
    filled: true,
    fillColor: kCardLight,
    contentPadding: const EdgeInsets.symmetric(vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDivider)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kAccent, width: 1.5)),
  );

  Widget _loginField(TextEditingController controller, String hint, IconData icon,
      {TextInputType? keyboardType, TextCapitalization textCapitalization = TextCapitalization.none}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      style: TextStyle(color: kTextPrimary),
      cursorColor: kAccent,
      decoration: _loginDecoration(hint, icon),
    );
  }

  Widget _passwordField() {
    return TextField(
      controller: _passwordController,
      obscureText: _obscure,
      style: TextStyle(color: kTextPrimary),
      cursorColor: kAccent,
      onSubmitted: (_) { if (!_isLoading) _submitWithEmail(); },
      decoration: _loginDecoration('Password', Icons.lock_outline_rounded).copyWith(
        suffixIcon: IconButton(
          icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: kTextSecondary, size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
    );
  }
}

// ─── VERIFY EMAIL ─────────────────────────────────────────────────────────────

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});
  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;
  bool _checking = false;

  User? get _user => FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final user = _user;
    if (user == null) return;
    await user.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh != null && fresh.emailVerified && mounted) {
      await _goNext(fresh);
    }
  }

  Future<void> _goNext(User user) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    final setupDone = data?['setupDone'] ?? false;
    final tutorialDone = data?['tutorialDone'] ?? false;
    if (!mounted) return;
    final next = setupDone
        ? (tutorialDone ? const MainScreen() : const TutorialScreen())
        : const OnboardingScreen();
    await Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => next), (route) => false);
  }

  Future<void> _resend() async {
    setState(() => _sending = true);
    try {
      await _user?.sendEmailVerification(ActionCodeSettings(
        url: 'https://kindred.jonahb344.workers.dev/verified',
        handleCodeInApp: false,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email sent — check your inbox.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send: $e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _checking = true);
    final user = _user;
    if (user == null) return;
    await user.reload();
    final fresh = FirebaseAuth.instance.currentUser;
    if (fresh != null && fresh.emailVerified && mounted) {
      await _goNext(fresh);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not verified yet. Open the email and tap the link.')));
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? '';
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const SizedBox(height: 44),
            Container(
              width: 92, height: 92,
              decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(28)),
              child: Icon(Icons.mark_email_read_rounded, color: kAccent, size: 46),
            ),
            const SizedBox(height: 26),
            Text('Verify your email', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kTextPrimary, letterSpacing: -0.5)),
            const SizedBox(height: 12),
            Text('We sent a verification link to', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: kTextSecondary)),
            const SizedBox(height: 2),
            Text(email, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kAccent)),
            const SizedBox(height: 10),
            Text('Open the email and tap the link to verify your account. Don\'t see it? Check your spam folder.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: kTextSecondary, height: 1.5)),
            const SizedBox(height: 34),
            _KindredButton(label: 'I\'ve verified — Continue', loading: _checking, onPressed: _checking ? null : _checkVerified),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _sending ? null : _resend,
              child: Text('Resend verification email', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 18),
            TextButton(
              onPressed: _signOut,
              child: Text('Sign out', style: TextStyle(color: kTextSecondary)),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── ONBOARDING ───────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // first-run setup: username, bio, phone — only shown once per account
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  int _step = 0;

  InputDecoration _inputDecoration(String hint, {Widget? prefix}) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: kTextSecondary),
    prefixIcon: prefix,
    filled: true,
    fillColor: kCard,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDivider)),
  );

  Future<void> _finish() async {
    setState(() => _isLoading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'username': _usernameController.text.trim(),
      'bio': _bioController.text.trim(),
      'setupDone': true,
    });
    await FirebaseFirestore.instance
        .collection('users').doc(user.uid).collection('private').doc('data')
        .set({'phone': _phoneController.text.trim()}, SetOptions(merge: true));
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const TutorialScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      _buildStep1(),
      _buildStep2(),
      _buildStep3(),
    ];

    return Scaffold(
      backgroundColor: kBackground,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == _step ? 28 : 8, height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == _step ? kAccent : kCardLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
              const SizedBox(height: 24),
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(children: [
                  Image.asset(kImgCleanup, height: 150, width: double.infinity, fit: BoxFit.cover),
                  Positioned.fill(child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.55)], begin: Alignment.topCenter, end: Alignment.bottomCenter),
                    ),
                  )),
                  Positioned(left: 16, bottom: 12, child: Row(children: [
                    const Icon(Icons.volunteer_activism_rounded, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    const Text('Small acts, big impact', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
                  ])),
                ]),
              ),
              const SizedBox(height: 32),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim), child: child),
                ),
                child: KeyedSubtree(key: ValueKey(_step), child: steps[_step]),
              ),
              const SizedBox(height: 40),
              _KindredButton(
                label: _step < 2 ? 'Continue' : 'Get Started',
                onPressed: () async {
                  if (_step < 2) setState(() => _step++);
                  else await _finish();
                },
                loading: _isLoading,
              ),
              if (_step > 0) ...[
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: () => setState(() => _step--), child: Text('Back', style: TextStyle(color: kTextSecondary)))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep1() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Welcome to Kindred', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kTextPrimary)),
      const SizedBox(height: 8),
      Text("Let's set up your profile", style: TextStyle(fontSize: 15, color: kTextSecondary)),
      const SizedBox(height: 32),
      TextField(controller: _usernameController, style: TextStyle(color: kTextPrimary),
          decoration: _inputDecoration('Username')),
      const SizedBox(height: 16),
      TextField(controller: _bioController, maxLines: 3, maxLength: 120, style: TextStyle(color: kTextPrimary),
          decoration: _inputDecoration('Tell your community about yourself...')),
    ],
  );

  Widget _buildStep2() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Add your phone number', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kTextPrimary)),
      const SizedBox(height: 8),
      Text("Get notified when someone needs your help", style: TextStyle(fontSize: 15, color: kTextSecondary)),
      const SizedBox(height: 32),
      TextField(controller: _phoneController, keyboardType: TextInputType.phone, style: TextStyle(color: kTextPrimary),
          decoration: _inputDecoration('+1 (555) 000-0000', prefix: Icon(Icons.phone_outlined, color: kAccent))),
    ],
  );

  Widget _buildStep3() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text("You're all set!", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kTextPrimary)),
      const SizedBox(height: 8),
      Text('Welcome to your community', style: TextStyle(fontSize: 15, color: kTextSecondary)),
      const SizedBox(height: 32),
      _FeatureRow(icon: Icons.shopping_cart_outlined, title: 'Request Help', desc: 'Ask neighbors for help with everyday tasks'),
      const SizedBox(height: 12),
      _FeatureRow(icon: Icons.handshake_outlined, title: 'Volunteer', desc: 'Claim requests and earn kindness points'),
      const SizedBox(height: 12),
      _FeatureRow(icon: Icons.star_outline_rounded, title: 'Level Up', desc: 'Unlock profile customization as you grow'),
    ],
  );
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String title, desc;
  const _FeatureRow({required this.icon, required this.title, required this.desc});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
      child: Row(
        children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: kAccent, size: 22)),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kTextPrimary)),
            const SizedBox(height: 2),
            Text(desc, style: TextStyle(fontSize: 12, color: kTextSecondary)),
          ])),
        ],
      ),
    );
  }
}

// ─── TUTORIAL ─────────────────────────────────────────────────────────────────

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});
  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  int _step = 0;

  final List<Map<String, dynamic>> _steps = [
    {'icon': Icons.home_rounded, 'title': 'Home Screen', 'desc': 'See your Kindness Score, level progress, and log acts of kindness. Claude AI verifies every photo you submit.'},
    {'icon': Icons.handshake_rounded, 'title': 'Help Others', 'desc': 'Spot requests on the nearby map or in the feed. Tap Help to volunteer. You earn points when the requester marks it complete.'},
    {'icon': Icons.add_circle_outline_rounded, 'title': 'Post a Request', 'desc': 'Need help? Tap Post Request, choose a category, describe what you need, and set the urgency level.'},
    {'icon': Icons.chat_bubble_outline_rounded, 'title': 'Messages', 'desc': 'When someone claims your request, a chat opens automatically. Use the Messages tab to coordinate and stay in touch.'},
    {'icon': Icons.star_rounded, 'title': 'Kindness Score', 'desc': 'Every verified act earns you points. Weekends give double points! Reach milestones to unlock profile customization.'},
    {'icon': Icons.person_rounded, 'title': 'Your Profile', 'desc': 'Tap your avatar to visit your profile. Edit your username, bio, banner, and avatar frame as you level up.'},
  ];

  Future<void> _finish() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'tutorialDone': true});
    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('${_step + 1} of ${_steps.length}', style: TextStyle(color: kTextSecondary, fontSize: 13)),
                TextButton(onPressed: _finish, child: Text('Skip', style: TextStyle(color: kTextSecondary))),
              ]),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_steps.length, (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: i == _step ? 28 : 8, height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(color: i == _step ? kAccent : kCardLight, borderRadius: BorderRadius.circular(4)),
              ))),
              const Spacer(),
              Container(width: 108, height: 108,
                decoration: BoxDecoration(gradient: kAccentGradient, borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.35), blurRadius: 24, offset: const Offset(0, 10))]),
                child: Icon(step['icon'] as IconData, color: Colors.white, size: 52),
              ),
              const SizedBox(height: 30),
              Text(step['title'] as String, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kTextPrimary, letterSpacing: -0.5)),
              const SizedBox(height: 16),
              Text(step['desc'] as String, textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: kTextSecondary, height: 1.6)),
              const Spacer(),
              _KindredButton(
                label: _step < _steps.length - 1 ? 'Next' : 'Start Using Kindred',
                onPressed: () async { if (_step < _steps.length - 1) setState(() => _step++); else await _finish(); },
              ),
              if (_step > 0) ...[
                const SizedBox(height: 12),
                TextButton(onPressed: () => setState(() => _step--), child: Text('Back', style: TextStyle(color: kTextSecondary))),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── MAIN SCREEN ──────────────────────────────────────────────────────────────
// the main scaffold with bottom nav — Home, Help, Messages, Map, Profile

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  void switchToTab(int index) => setState(() => _currentIndex = index);

  final List<Widget> _screens = const [
    HomeScreen(), HelpOthersScreen(), LeaderboardScreen(), ChatsListScreen(asTab: true), ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.03, 0.02), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_currentIndex), child: _screens[_currentIndex]),
      ),
      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('notifications')
            .where('toUid', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
            .where('read', isEqualTo: false)
            .snapshots(),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? [];
          final chatUnread = docs.where((d) => (d.data() as Map)['chatId'] != null).length;
          final helpUnread = docs.length - chatUnread;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(24), boxShadow: [kCardShadow]),
            child: SafeArea(
              top: false,
              child: Row(children: [
                _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', selected: _currentIndex == 0, onTap: () => setState(() => _currentIndex = 0)),
                _NavItem(icon: Icons.volunteer_activism_outlined, activeIcon: Icons.volunteer_activism_rounded, label: 'Help', selected: _currentIndex == 1, badge: helpUnread, onTap: () => setState(() => _currentIndex = 1)),
                _NavItem(icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard_rounded, label: 'Leaders', selected: _currentIndex == 2, onTap: () => setState(() => _currentIndex = 2)),
                _NavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Messages', selected: _currentIndex == 3, badge: chatUnread, onTap: () => setState(() => _currentIndex = 3)),
                _NavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile', selected: _currentIndex == 4, onTap: () => setState(() => _currentIndex = 4)),
              ]),
            ),
          );
        },
      ),
    );
  }
}

// ─── HOME SCREEN ──────────────────────────────────────────────────────────────
// feed of open requests — pulls from Firestore, filters blocked users

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut() async {
    if (!kIsWeb) await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _updateStreak(String uid) async {
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await doc.get();
    final data = snap.data() ?? {};
    final lastActDate = (data['lastActDate'] as Timestamp?)?.toDate();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int streak = (data['streak'] ?? 0) as int;
    if (lastActDate == null) {
      streak = 1;
    } else {
      final lastDay = DateTime(lastActDate.year, lastActDate.month, lastActDate.day);
      final diff = today.difference(lastDay).inDays;
      if (diff == 0) return; // Already logged today, don't update
      if (diff == 1) streak++;
      else streak = 1; // Reset streak if more than 1 day gap
    }
    await doc.update({'streak': streak, 'lastActDate': FieldValue.serverTimestamp()});
  }

  Future<void> _checkBadges(String uid, int newScore, int acts) async {
    final doc = FirebaseFirestore.instance.collection('users').doc(uid);
    final snap = await doc.get();
    final badges = List<String>.from(snap.data()?['badges'] ?? []);
    final newBadges = <String>[];
    if (acts >= 1 && !badges.contains('first_act')) newBadges.add('first_act');
    if (acts >= 10 && !badges.contains('10_acts')) newBadges.add('10_acts');
    if (acts >= 50 && !badges.contains('50_acts')) newBadges.add('50_acts');
    if (newScore >= helperThreshold && !badges.contains('helper')) newBadges.add('helper');
    if (newScore >= championThreshold && !badges.contains('champion')) newBadges.add('champion');
    if (newScore >= legendThreshold && !badges.contains('legend')) newBadges.add('legend');
    if (newBadges.isNotEmpty) await doc.update({'badges': FieldValue.arrayUnion(newBadges)});
  }

  Future<void> _logKindnessAct(BuildContext context, String act, String emoji) async {
    // take a photo as evidence, then let the AI check it matches the description
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (picked == null) return;
    if (!context.mounted) return;

    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: kAccent),
          SizedBox(height: 16),
          Text('Verifying your photo...', style: TextStyle(color: kTextPrimary), textAlign: TextAlign.center),
        ]),
      ),
    );

    try {
      final imageBytes = await picked.readAsBytes();

      final result = await _callVerifyAct(act, base64Encode(imageBytes));

      if (!context.mounted) return;
      Navigator.pop(context);

      final approved = result['approved'] as bool;
      final reason = result['reason'] as String;

      if (approved) {
        final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
        final snapshot = await doc.get();
        final currentScore = (snapshot.data()?['kindnessScore'] ?? 0) as int;
        final currentActs = (snapshot.data()?['actsCompleted'] ?? 0) as int;
        final pts = _currentPoints;
        final newScore = currentScore + pts;
        final newActs = currentActs + 1;
        String level = 'Newcomer';
        if (newScore >= legendThreshold) level = 'Legend';
        else if (newScore >= championThreshold) level = 'Champion';
        else if (newScore >= helperThreshold) level = 'Helper';

        await doc.update({'kindnessScore': newScore, 'level': level, 'actsCompleted': FieldValue.increment(1)});
        await _updateStreak(user.uid);
        await _checkBadges(user.uid, newScore, newActs);

        await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
          'act': act, 'emoji': emoji, 'points': pts, 'approved': true, 'reason': reason,
          'completedAt': FieldValue.serverTimestamp(),
        });

        final myPhoto = await _myPhotoUrl();
        await FirebaseFirestore.instance.collection('feed').add({
          'uid': user.uid, 'name': user.displayName, 'photoUrl': myPhoto.isNotEmpty ? myPhoto : user.photoURL,
          'act': act, 'emoji': emoji, 'createdAt': FieldValue.serverTimestamp(),
        });

        if (context.mounted) {
          final bonus = _isWeekend ? ' (Weekend 2x bonus!)' : '';
          showDialog(context: context, builder: (_) => _KindredDialog(
            title: 'Verified!',
            content: '$reason\n\n+$pts points added$bonus',
            actionText: 'Awesome',
            onAction: () => Navigator.pop(context),
          ));
        }
      } else {
        if (context.mounted) {
          showDialog(context: context, builder: (_) => _KindredDialog(
            title: 'Not Verified',
            content: '$reason\n\nPlease take a clearer photo.',
            actionText: 'Try Again',
            onAction: () {
              Navigator.pop(context);
              _logKindnessAct(context, act, emoji);
            },
          ));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // points awarded for a verified act + streak + level checks
  Future<void> _awardAct(String act, String category, String reason) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final pts = _currentPoints;
    final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    final currentScore = (snapshot.data()?['kindnessScore'] ?? 0) as int;
    final currentActs = (snapshot.data()?['actsCompleted'] ?? 0) as int;
    final newScore = currentScore + pts;
    final newActs = currentActs + 1;
    String level = 'Newcomer';
    if (newScore >= legendThreshold) {
      level = 'Legend';
    } else if (newScore >= championThreshold) {
      level = 'Champion';
    } else if (newScore >= helperThreshold) {
      level = 'Helper';
    }
    await doc.update({'kindnessScore': newScore, 'level': level, 'actsCompleted': FieldValue.increment(1)});
    await _updateStreak(user.uid);
    await _checkBadges(user.uid, newScore, newActs);
    await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('history').add({
      'act': act, 'emoji': _categoryEmoji(category), 'points': pts, 'approved': true, 'reason': reason,
      'completedAt': FieldValue.serverTimestamp(),
    });
    final myPhoto = await _myPhotoUrl();
    await FirebaseFirestore.instance.collection('feed').add({
      'uid': user.uid, 'name': user.displayName, 'photoUrl': myPhoto.isNotEmpty ? myPhoto : user.photoURL,
      'act': act, 'emoji': _categoryEmoji(category), 'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _describeKindnessAct(BuildContext context, {String? initialDescription, Uint8List? initialImage}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final picker = ImagePicker();
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DescribeActSheet(
        picker: picker,
        initialDescription: initialDescription,
        initialImage: initialImage,
        onVerify: (desc, imageBytes) async {
          if (!context.mounted) return;
          Navigator.pop(context);
          await _verifyDescription(context, desc, imageBytes: imageBytes);
        },
      ),
    );
  }

  Future<void> _verifyDescription(BuildContext context, String description, {Uint8List? imageBytes}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    showDialog(context: context, barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: kAccent),
          const SizedBox(height: 16),
          Text('Verifying your act...', style: TextStyle(color: kTextPrimary), textAlign: TextAlign.center),
        ]),
      ),
    );
    try {
      final result = await _callVerifyAct(description, imageBytes != null ? base64Encode(imageBytes) : null);
      if (!context.mounted) return;
      Navigator.pop(context);
      final approved = result['approved'] as bool;
      final reason = result['reason'] as String;
      final category = (result['category'] as String?) ?? 'Other';
      if (approved) {
        await _awardAct(description, category, reason);
        if (context.mounted) {
          final bonus = _isWeekend ? ' (Weekend 2x bonus!)' : '';
          showDialog(context: context, builder: (_) => _KindredDialog(
            title: 'Verified!',
            content: '$reason\n\n+$_currentPoints points added$bonus',
            actionText: 'Awesome',
            onAction: () => Navigator.pop(context),
          ));
        }
      } else {
        if (context.mounted) {
          showDialog(context: context, builder: (_) => _KindredDialog(
            title: 'Not Verified',
            content: '$reason\n\nPlease describe your act more clearly or add a clearer photo.',
            actionText: 'Try Again',
            onAction: () {
              Navigator.pop(context);
              _describeKindnessAct(context, initialDescription: description, initialImage: imageBytes);
            },
          ));
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Image.asset('assets/logo_banner.png', width: 150, fit: BoxFit.contain),
        centerTitle: true,
        leading: IconButton(icon: Icon(Icons.logout_rounded, color: kTextSecondary), onPressed: _signOut),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
            builder: (context, snapshot) {
              final photo = (snapshot.data?.data() as Map<String, dynamic>?)?['photoUrl'];
              return GestureDetector(
                onTap: () { final m = context.findAncestorStateOfType<_MainScreenState>(); m?.switchToTab(4); },
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: CircleAvatar(
                    radius: 17,
                    backgroundImage: _avatarImage(photo ?? user?.photoURL),
                    backgroundColor: kAccent,
                    child: (photo == null || photo.toString().isEmpty) && user?.photoURL == null
                        ? const Icon(Icons.person, color: Colors.white, size: 17)
                        : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final score = data?['kindnessScore'] ?? 0;
          final level = data?['level'] ?? 'Newcomer';
          final acts = data?['actsCompleted'] ?? 0;
          final username = data?['username'] ?? '';
          final streak = data?['streak'] ?? 0;
          final badges = List<String>.from(data?['badges'] ?? []);

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero card
                _StaggerIn(
                  child: Container(
                  width: double.infinity, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.35), blurRadius: 28, offset: const Offset(0, 12))],
                  ),
                  child: Stack(children: [
                    Positioned.fill(child: _KenBurnsImage(asset: kImgVolunteers)),
                    Positioned.fill(child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _appIsDark
                              ? [kAccent.withValues(alpha: 0.92), const Color(0xFF0B1220).withValues(alpha: 0.85)]
                              : [kAccent.withValues(alpha: 0.9), const Color(0xFF052e2b).withValues(alpha: 0.82)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                      ),
                    )),
                    Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back, ${username.isNotEmpty ? username : user?.displayName?.split(' ').first ?? 'Friend'}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        const SizedBox(height: 4),
                        const Text('How can you help your community\ntoday?',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.3)),
                        const SizedBox(height: 18),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          _StatPill(label: '$score pts', icon: Icons.star_rounded),
                          _StatPill(label: '$acts acts', icon: Icons.handshake_rounded),
                          if (streak > 0) _StatPill(label: '$streak day streak', icon: Icons.local_fire_department_rounded),
                        ]),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Row(children: [
                            Icon(_levelIcon(level), size: 15, color: Colors.white),
                            const SizedBox(width: 6),
                            Text(level, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                          ]),
                          Text(_levelNextMessage(score), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ]),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: _levelProgress(score), minHeight: 6,
                            backgroundColor: Colors.white.withValues(alpha: 0.25),
                            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      ],
                    ),
                    ),
                  ]),
                  ),
                ),

                // Weekend bonus banner
                if (_isWeekend) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.bolt_rounded, color: Colors.orange, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Weekend bonus active — earn 2x points today!',
                          style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ],

                // Badges
                if (badges.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Badges', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, runSpacing: 8, children: badges.map((b) => _BadgeChip(badge: b)).toList()),
                ],

                const SizedBox(height: 24),
                Text('Log a Kind Act', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextPrimary)),
                const SizedBox(height: 4),
                Text('Take a photo or describe it — AI will verify', style: TextStyle(fontSize: 13, color: kTextSecondary)),
                const SizedBox(height: 14),

                GridView.count(
                  crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.4,
                  children: [
                    _HelpCard(icon: Icons.shopping_cart, label: 'Grocery Run', tint: _categoryColor('Grocery Run'), onTap: () => _logKindnessAct(context, 'Grocery Run', '🛒')),
                    _HelpCard(icon: Icons.yard, label: 'Lawn Care', tint: _categoryColor('Lawn Care'), onTap: () => _logKindnessAct(context, 'Lawn Care', '🌿')),
                    _HelpCard(icon: Icons.inventory_2, label: 'Moving Help', tint: _categoryColor('Moving Help'), onTap: () => _logKindnessAct(context, 'Moving Help', '📦')),
                    _HelpCard(icon: Icons.pets, label: 'Pet Care', tint: _categoryColor('Pet Care'), onTap: () => _logKindnessAct(context, 'Pet Care', '🐾')),
                    _HelpCard(icon: Icons.restaurant, label: 'Meal Prep', tint: _categoryColor('Meal Prep'), onTap: () => _logKindnessAct(context, 'Meal Prep', '🍳')),
                    _HelpCard(icon: Icons.directions_car, label: 'Give a Ride', tint: _categoryColor('Give a Ride'), onTap: () => _logKindnessAct(context, 'Give a Ride', '🚗')),
                  ],
                ),

                const SizedBox(height: 12),
                _Pressable(
                  onTap: () => _describeKindnessAct(context),
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: kBadge.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(children: [
                      Container(width: 38, height: 38, decoration: BoxDecoration(color: kBadge.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                          child: Icon(Icons.edit_note_rounded, color: kBadge, size: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Describe your own act', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: kTextPrimary)),
                        Text('Type what you did — AI verifies it', style: TextStyle(fontSize: 12, color: kTextSecondary)),
                      ])),
                      Icon(Icons.chevron_right_rounded, color: kTextSecondary),
                    ]),
                  ),
                ),

                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Community', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextPrimary)),
                  GestureDetector(
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('Sharing comes with the full app release — Kindred is in beta!'),
                      backgroundColor: kAccentDark,
                    )),
                    child: Text('Share app', style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                ]),
                const SizedBox(height: 10),

                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('feed').orderBy('createdAt', descending: true).limit(10).snapshots(),
                  builder: (context, feedSnap) {
                    if (!feedSnap.hasData || feedSnap.data!.docs.isEmpty) {
                      return Container(
                        width: double.infinity, padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Column(children: [
                          Icon(Icons.diversity_3_rounded, color: kTextSecondary.withValues(alpha: 0.5), size: 34),
                          const SizedBox(height: 10),
                          Text('No community activity yet. Be the first!', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ]),
                      );
                    }
                    return Column(
                      children: feedSnap.data!.docs.map((doc) {
                        final f = doc.data() as Map<String, dynamic>;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                          child: Row(children: [
                            CircleAvatar(radius: 18, backgroundImage: _avatarImage(f['photoUrl']), backgroundColor: kAccent,
                                child: f['photoUrl'] == null ? const Icon(Icons.person, color: Colors.white, size: 14) : null),
                            const SizedBox(width: 10),
                            Expanded(child: RichText(text: TextSpan(style: TextStyle(color: kTextSecondary, fontSize: 13), children: [
                              TextSpan(text: f['name'] ?? 'Someone', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w600)),
                              TextSpan(text: ' helped with ${f['act']} ${f['emoji'] ?? ''}'),
                            ]))),
                            const SizedBox(width: 8),
                            Text('+${_isWeekend ? pointsPerAct * 2 : pointsPerAct}', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 12)),
                          ]),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── HELP OTHERS ──────────────────────────────────────────────────────────────
// shows requests you've claimed + the "describe your own act" feature

class HelpOthersScreen extends StatefulWidget {
  const HelpOthersScreen({super.key});
  @override
  State<HelpOthersScreen> createState() => _HelpOthersScreenState();
}

class _HelpOthersScreenState extends State<HelpOthersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription<QuerySnapshot>? _helpNotifSub;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _clearHelpNotificationBadge();
  }
  @override
  void dispose() {
    _helpNotifSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _clearHelpNotificationBadge() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final existing = await FirebaseFirestore.instance.collection('notifications')
          .where('toUid', isEqualTo: uid).where('read', isEqualTo: false).get();
      for (final d in existing.docs) {
        if ((d.data() as Map)['chatId'] == null) { await d.reference.update({'read': true}); }
      }
    } catch (_) {}
    _helpNotifSub = FirebaseFirestore.instance.collection('notifications')
        .where('toUid', isEqualTo: uid).where('read', isEqualTo: false).snapshots()
        .listen((snap) async {
      for (final d in snap.docs) {
        if ((d.data() as Map)['chatId'] == null) {
          try { await d.reference.update({'read': true}); } catch (_) {}
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground, elevation: 0, scrolledUnderElevation: 0,
        title: Text('Help Others', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800, fontSize: 24)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: kCardLight, borderRadius: BorderRadius.circular(14)),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(11), boxShadow: [kSoftShadow]),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: kAccent,
                unselectedLabelColor: kTextSecondary,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                tabs: const [Tab(text: 'Open Requests'), Tab(text: 'My Requests')],
              ),
            ),
          ),
        ),
      ),
      body: LayoutBuilder(builder: (context, constraints) {
        final mapHeight = constraints.maxHeight > 420 ? 235.0 : (constraints.maxHeight * 0.32).clamp(100.0, 235.0);
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(height: mapHeight, child: _NearbyMap(onExpand: () => Navigator.of(context).push(_fadeSlideRoute(const _FullscreenMapScreen())))),
          ),
          const SizedBox(height: 4),
          Expanded(child: TabBarView(controller: _tabController, children: const [RequestFeedTab(), MyRequestsTab()])),
        ]);
      }),
      floatingActionButton: _Pressable(
        onTap: () => _showPostRequestSheet(context),
        child: Container(
          height: 52, padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(gradient: kAccentGradient, borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))]),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.add_rounded, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Post Request', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

class RequestFeedTab extends StatelessWidget {
  const RequestFeedTab({super.key});
  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('status', isEqualTo: 'open').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: kAccent));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const _EmptyState(icon: Icons.inbox_rounded, title: 'No open requests right now', subtitle: 'Check back soon or post one yourself');
        }
        // Filter out blocked users
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance.collection('users').doc(currentUid).get(),
          builder: (context, userSnap) {
            final blockedUsers = List<String>.from((userSnap.data?.data() as Map<String, dynamic>?)?['blockedUsers'] ?? []);
            final docs = snapshot.data!.docs.where((d) => !blockedUsers.contains((d.data() as Map)['requesterId'])).toList();
            return ListView.builder(
              padding: const EdgeInsets.all(16), itemCount: docs.length,
              itemBuilder: (context, i) => RequestCard(docId: docs[i].id, data: docs[i].data() as Map<String, dynamic>),
            );
          },
        );
      },
    );
  }
}

class MyRequestsTab extends StatelessWidget {
  const MyRequestsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('requesterId', isEqualTo: uid).orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return Center(child: CircularProgressIndicator(color: kAccent));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const _EmptyState(icon: Icons.post_add_rounded, title: "No requests yet", subtitle: 'Tap Post Request to ask for help');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16), itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, i) {
            final doc = snapshot.data!.docs[i];
            return RequestCard(docId: doc.id, data: doc.data() as Map<String, dynamic>, isOwner: true);
          },
        );
      },
    );
  }
}

class RequestCard extends StatelessWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isOwner;
  const RequestCard({super.key, required this.docId, required this.data, this.isOwner = false});

  Color _urgencyColor(String u) { switch (u) { case 'High': return Colors.red; case 'Medium': return Colors.orange; default: return kAccent; } }

  Future<void> _claimRequest(BuildContext context) async {
    // volunteer taps "I'll help" — sets the request to claimed and opens the chat
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
      title: 'Claim this request?',
      content: 'You\'re volunteering to help with ${data['category']}.',
      actionText: "I'll help",
      onAction: () => Navigator.pop(context, true),
      cancelText: 'Cancel',
      onCancel: () => Navigator.pop(context, false),
    ));
    if (confirmed != true) return;

    await _completeClaim(data, docId);

    if (context.mounted) {
      _hapticHeavy();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request claimed! They have been notified.'), backgroundColor: kAccentDark));
    }
  }

  Future<void> _markComplete(BuildContext context) async {
    final noteController = TextEditingController();
    final note = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Send a Thank You', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Send your volunteer a note of gratitude.', style: TextStyle(color: kTextSecondary)),
        const SizedBox(height: 12),
        TextField(controller: noteController, maxLines: 3, style: TextStyle(color: kTextPrimary),
            decoration: InputDecoration(hintText: 'Thank you so much for...', hintStyle: TextStyle(color: kTextSecondary), filled: true, fillColor: kCardLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ]),
      actions: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _KindredButton(label: 'Send', onPressed: () => Navigator.pop(context, noteController.text.trim()), compact: true, fullWidth: false),
            TextButton(onPressed: () => Navigator.pop(context, ''), child: Text('Skip', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600))),
          ]),
        ),
      ],
    ));

    await FirebaseFirestore.instance.collection('requests').doc(docId).update({'status': 'completed'});
    if (note != null && note.isNotEmpty) {
      await FirebaseFirestore.instance.collection('thank_you_notes').add({
        'fromUid': FirebaseAuth.instance.currentUser?.uid,
        'fromName': FirebaseAuth.instance.currentUser?.displayName,
        'toUid': data['volunteerId'], 'note': note, 'requestCategory': data['category'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    final volunteerId = data['volunteerId'];
    if (volunteerId != null) {
      final doc = FirebaseFirestore.instance.collection('users').doc(volunteerId);
      final snap = await doc.get();
      final currentScore = (snap.data()?['kindnessScore'] ?? 0) as int;
      final newScore = currentScore + _currentPoints;
      String level = 'Newcomer';
      if (newScore >= legendThreshold) level = 'Legend';
      else if (newScore >= championThreshold) level = 'Champion';
      else if (newScore >= helperThreshold) level = 'Helper';
      await doc.update({'kindnessScore': newScore, 'level': level, 'actsCompleted': FieldValue.increment(1)});

      // Notify volunteer
      await _sendPushNotification(volunteerId, 'Your help was appreciated!', 'You earned +$_currentPoints points for helping with ${data['category']}.');
    }

    if (context.mounted) {
      _hapticHeavy();
      await _showConfetti(context);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Marked as complete!'), backgroundColor: kAccentDark));
    }
  }

  Future<void> _deleteRequest(BuildContext context) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
      title: 'Delete request?',
      content: 'This will permanently remove your request.',
      actionText: 'Delete',
      onAction: () => Navigator.pop(context, true),
      cancelText: 'Cancel',
      onCancel: () => Navigator.pop(context, false),
      destructive: true,
    ));
    if (confirm == true) await FirebaseFirestore.instance.collection('requests').doc(docId).delete();
  }

  Future<void> _reportUser(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    _showReportSheet(context, data['requesterId'], data['requesterName'] ?? 'this user');
  }

  Future<void> _openChat(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final otherUid = data['requesterId'] == currentUid ? data['volunteerId'] : data['requesterId'];
    final otherName = data['requesterId'] == currentUid ? data['volunteerName'] : data['requesterName'];
    if (otherUid == null) return;

    // Mark notifications as read
    final notifSnap = await FirebaseFirestore.instance.collection('notifications')
        .where('toUid', isEqualTo: currentUid)
        .where('chatId', isEqualTo: docId)
        .get();
    for (final doc in notifSnap.docs) { await doc.reference.update({'read': true}); }

    if (context.mounted) {
      Navigator.push(context, _fadeSlideRoute(ChatScreen(chatId: docId, otherName: otherName ?? 'User', otherUid: otherUid)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = data['status'] ?? 'open';
    final urgency = data['urgency'] ?? 'Low';
    final category = data['category'] ?? 'Other';
    final description = data['description'] ?? '';
    final requesterName = data['requesterName'] ?? 'Someone';
    final volunteerName = data['volunteerName'];
    final createdAt = data['createdAt'] as Timestamp?;
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isRequester = data['requesterId'] == currentUid;
    final isVolunteer = data['volunteerId'] == currentUid;

    return _StaggerIn(
      key: ValueKey('card-$docId'),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(color: _categoryColor(category).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                child: Center(child: Icon(_categoryIcon(category), color: _categoryColor(category), size: 22))),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () {
                if (data['requesterId'] != null && data['requesterId'] != currentUid) {
                  Navigator.push(context, _fadeSlideRoute(UserProfileScreen(uid: data['requesterId'], initialName: requesterName)));
                }
              },
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(category, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kTextPrimary)),
                Text('$requesterName · ${_timeAgo(createdAt)}', style: TextStyle(fontSize: 12, color: kTextSecondary)),
              ]),
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _urgencyColor(urgency).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: _urgencyColor(urgency), shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(urgency, style: TextStyle(color: _urgencyColor(urgency), fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ),
          ]),
          if (description.isNotEmpty) ...[SizedBox(height: 10), Text(description, style: TextStyle(fontSize: 13, color: kTextSecondary, height: 1.5))],
          const SizedBox(height: 14),
          Row(children: [
            _StatusBadge(status: status),
            const Spacer(),
            if (status == 'claimed' && volunteerName != null)
              Text(volunteerName, style: TextStyle(fontSize: 12, color: kTextSecondary)),
            const SizedBox(width: 6),
            if (isRequester && status != 'completed')
              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20), onPressed: () => _deleteRequest(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            if (!isRequester && status == 'open')
              IconButton(icon: Icon(Icons.flag_outlined, color: kTextSecondary, size: 18), onPressed: () => _reportUser(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 6),
            if (status == 'claimed' && (isRequester || isVolunteer))
              IconButton(icon: Icon(Icons.chat_bubble_outline_rounded, color: kAccent, size: 20), onPressed: () => _openChat(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
            const SizedBox(width: 6),
            if (status == 'open' && !isRequester)
              _KindredButton(label: 'Help', onPressed: () => _claimRequest(context), compact: true, fullWidth: false),
            if (status == 'claimed' && isRequester)
              _Pressable(onTap: () => _markComplete(context), child: Container(
                height: 40, padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(color: const Color(0xFFF97316), borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: const Color(0xFFF97316).withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4))]),
                child: const Center(child: Text('Done', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
              )),
          ]),
        ]),
      ),
    ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (status) {
      case 'claimed': color = Colors.orange; label = 'Claimed'; break;
      case 'completed': color = kAccentDark; label = 'Completed'; break;
      default: color = Colors.blue; label = 'Open';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }
}

Future<Map<String, String>> _authHeaders() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return {};
  try {
    final idToken = await user.getIdToken();
    return {'Authorization': 'Bearer $idToken'};
  } catch (_) {
    return {};
  }
}

// sends the act description (and optional photo) to the worker for AI verification
// the worker calls Claude on the server side so the API key stays safe
Future<Map<String, dynamic>> _callVerifyAct(String description, String? imageBase64) async {
  final response = await http.post(
    Uri.parse('$kServerBaseUrl/verify'),
    headers: {
      'Content-Type': 'application/json',
      ...await _authHeaders(),
    },
    body: jsonEncode({
      'description': description,
      if (imageBase64 != null) 'imageBase64': imageBase64,
    }),
  );
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if (response.statusCode != 200) {
    throw Exception(data['error'] ?? 'Verification failed (${response.statusCode})');
  }
  return data;
}

// fire-and-forget push — fails silently if target has no FCM token
Future<void> _sendPushNotification(String targetUid, String title, String body) async {
  try {
    await http.post(
      Uri.parse('$kServerBaseUrl/push'),
      headers: {
        'Content-Type': 'application/json',
        ...await _authHeaders(),
      },
      body: jsonEncode({'targetUid': targetUid, 'title': title, 'body': body}),
    );
  } catch (_) {}
}

Future<void> _completeClaim(Map<String, dynamic> data, String docId) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await FirebaseFirestore.instance.collection('requests').doc(docId).update({
    'status': 'claimed', 'volunteerId': user.uid, 'volunteerName': user.displayName, 'claimedAt': FieldValue.serverTimestamp(),
  });
  final requesterId = data['requesterId'];
  final category = data['category'] ?? 'a request';
  if (requesterId != null && requesterId != user.uid) {
    await _sendPushNotification(requesterId as String, 'Someone is coming to help!', '${user.displayName} claimed your $category request.');
    try {
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': requesterId,
        'fromName': user.displayName,
        'title': 'Someone is coming to help!',
        'body': '${user.displayName} claimed your $category request.',
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}

Future<Position?> _getCurrentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition();
  } catch (_) {
    return null;
  }
}

Future<void> _saveMyLocation(Position pos) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirebaseFirestore.instance
        .collection('users').doc(uid).collection('private').doc('data')
        .set({'location': {'lat': pos.latitude, 'lng': pos.longitude}}, SetOptions(merge: true));
  } catch (_) {}
}

Future<void> _updateMyLocation() async {
  final pos = await _getCurrentPosition();
  if (pos != null) await _saveMyLocation(pos);
}

// pings the worker to notify users within the nearby radius about a new request
Future<void> _notifyNearby(String requestId) async {
  try {
    await http.post(
      Uri.parse('$kServerBaseUrl/notifyNearby'),
      headers: {
        'Content-Type': 'application/json',
        ...await _authHeaders(),
      },
      body: jsonEncode({'requestId': requestId}),
    );
  } catch (_) {}
}

void _showPostRequestSheet(BuildContext context) {
  final descController = TextEditingController();
  String selectedCategory = 'Grocery Run';
  String selectedUrgency = 'Low';
  final categories = ['Grocery Run', 'Lawn Care', 'Moving Help', 'Pet Care', 'Meal Prep', 'Give a Ride', 'Other'];
  final urgencies = ['Low', 'Medium', 'High'];

  showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(builder: (context, setModalState) => Container(
      height: MediaQuery.of(context).size.height * 0.82,
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kDivider, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Text('Post a Request', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kTextPrimary)),
        const SizedBox(height: 4),
        Text('Your community is here for you', style: TextStyle(color: kTextSecondary, fontSize: 13)),
        const SizedBox(height: 24),
        Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: categories.map((cat) {
          final selected = selectedCategory == cat;
          return GestureDetector(
            onTap: () => setModalState(() => selectedCategory = cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: selected ? kAccent : kCardLight, borderRadius: BorderRadius.circular(20)),
              child: Text(cat, style: TextStyle(color: selected ? Colors.white : kTextSecondary, fontWeight: selected ? FontWeight.w600 : FontWeight.normal, fontSize: 13)),
            ),
          );
        }).toList()),
        const SizedBox(height: 20),
        Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
        const SizedBox(height: 8),
        TextField(controller: descController, maxLines: 3, maxLength: 200, style: TextStyle(color: kTextPrimary),
            decoration: InputDecoration(hintText: 'Describe what you need...', hintStyle: TextStyle(color: kTextSecondary), filled: true, fillColor: kCardLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), counterStyle: TextStyle(color: kTextSecondary))),
        const SizedBox(height: 16),
        Text('Urgency', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
        const SizedBox(height: 8),
        Row(children: urgencies.map((u) {
          final selected = selectedUrgency == u;
          Color color; switch (u) { case 'High': color = Colors.red; break; case 'Medium': color = Colors.orange; break; default: color = kAccent; }
          return Expanded(child: GestureDetector(
            onTap: () => setModalState(() => selectedUrgency = u),
            child: Container(
              margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: selected ? color.withValues(alpha: 0.15) : kCardLight, borderRadius: BorderRadius.circular(10), border: selected ? Border.all(color: color) : null),
              child: Text(u, textAlign: TextAlign.center, style: TextStyle(color: selected ? color : kTextSecondary, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ));
        }).toList()),
        const SizedBox(height: 28),
        _KindredButton(
          label: 'Post Request',
          onPressed: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            if (descController.text.trim().isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a description.'))); return; }
            final pos = await _getCurrentPosition();
            if (pos != null) await _saveMyLocation(pos);
            final ref = await FirebaseFirestore.instance.collection('requests').add({
              'requesterId': user.uid, 'requesterName': user.displayName, 'category': selectedCategory,
              'description': descController.text.trim(), 'urgency': selectedUrgency, 'status': 'open',
              'volunteerId': null, 'volunteerName': null, 'createdAt': FieldValue.serverTimestamp(),
              if (pos != null) 'lat': pos.latitude,
              if (pos != null) 'lng': pos.longitude,
            });
            await _notifyNearby(ref.id);
            if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request posted!'), backgroundColor: kAccentDark)); }
          },
        ),
      ])),
    )),
  );
}

// ─── CHAT ─────────────────────────────────────────────────────────────────────
// 1:1 messaging between requester and volunteer for a specific request

class ChatScreen extends StatefulWidget {
  final String chatId, otherName, otherUid;
  const ChatScreen({super.key, required this.chatId, required this.otherName, required this.otherUid});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String? _blocked;

  @override
  void initState() {
    super.initState();
    _checkBlocked();
    _markChatRead();
    _setChatPresence(true);
  }

  @override
  void dispose() {
    _setChatPresence(false);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _setChatPresence(bool present) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatId);
      if (present) {
        await chatRef.set({'presence': {uid: FieldValue.serverTimestamp()}}, SetOptions(merge: true));
      } else {
        await chatRef.update({'presence.$uid': FieldValue.delete()});
      }
    } catch (_) {}
  }

  Future<void> _checkBlocked() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final myDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (List<String>.from(myDoc.data()?['blockedUsers'] ?? []).contains(widget.otherUid)) {
        if (mounted) setState(() => _blocked = 'You blocked this user. Unblock them from their profile to chat again.');
        return;
      }
      final otherDoc = await FirebaseFirestore.instance.collection('users').doc(widget.otherUid).get();
      if (List<String>.from(otherDoc.data()?['blockedUsers'] ?? []).contains(uid)) {
        if (mounted) setState(() => _blocked = 'You can\'t message this user anymore.');
      }
    } catch (_) {}
  }

  Future<void> _markChatRead() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final notifSnap = await FirebaseFirestore.instance.collection('notifications')
          .where('toUid', isEqualTo: uid)
          .where('chatId', isEqualTo: widget.chatId)
          .get();
      for (final doc in notifSnap.docs) { await doc.reference.update({'read': true}); }
    } catch (_) {}
  }

  Future<void> _send() async {
    // send a chat message, then scroll to bottom + clear the input
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final myBlocked = await _getBlockedUsers(user.uid);
      if (myBlocked.contains(widget.otherUid)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You blocked this user. Unblock them to send messages.')));
        return;
      }
      final otherDoc = await FirebaseFirestore.instance.collection('users').doc(widget.otherUid).get();
      if (List<String>.from(otherDoc.data()?['blockedUsers'] ?? []).contains(user.uid)) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can no longer message this user.')));
        return;
      }
      await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').add({
        'senderId': user.uid, 'senderName': user.displayName, 'text': text, 'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message not sent. Check your connection and try again.')));
      return;
    }
    _controller.clear();

    // Don't notify the receiver if they're already viewing this chat
    bool receiverInChat = false;
    try {
      final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).get();
      final presence = chatDoc.data()?['presence'] as Map<String, dynamic>?;
      final theirTs = presence?[widget.otherUid] as Timestamp?;
      if (theirTs != null && DateTime.now().difference(theirTs.toDate()).inSeconds < 60) receiverInChat = true;
    } catch (_) {}

    if (!receiverInChat) {
      // Send notification if the receiver has message notifications enabled
      try {
        final receiverDoc = await FirebaseFirestore.instance.collection('users').doc(widget.otherUid).get();
        final notifMessages = receiverDoc.data()?['notifMessages'] ?? true;

        if (notifMessages) {
          await _sendPushNotification(widget.otherUid, user.displayName ?? 'Kindred', text);
        }

        // Save in-app notification with read status
        await FirebaseFirestore.instance.collection('notifications').add({
          'toUid': widget.otherUid,
          'fromName': user.displayName,
          'title': user.displayName ?? 'New Message',
          'body': text,
          'chatId': widget.chatId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollController.hasClients) _scrollController.animateTo(_scrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  Future<void> _completeRequestFromChat(DocumentSnapshot requestSnap) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final data = requestSnap.data() as Map<String, dynamic>?;
    if (data == null) return;
    final requesterId = data['requesterId'] as String?;
    final requesterName = data['requesterName'] ?? 'your neighbor';
    final category = data['category'] ?? 'favor';
    if (requesterId == null) return;

    final noteController = TextEditingController();
    final note = await showDialog<String>(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Done helping?', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('You helped with $category. Send $requesterName a thank-you note.', style: TextStyle(color: kTextSecondary)),
        const SizedBox(height: 12),
        TextField(controller: noteController, maxLines: 3, style: TextStyle(color: kTextPrimary),
            decoration: InputDecoration(hintText: 'Thank you for letting me help...', hintStyle: TextStyle(color: kTextSecondary), filled: true, fillColor: kCardLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ]),
      actions: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _KindredButton(label: 'Done', onPressed: () => Navigator.pop(context, noteController.text.trim()), compact: true, fullWidth: false),
            TextButton(onPressed: () => Navigator.pop(context, ''), child: Text('Skip', style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600))),
          ]),
        ),
      ],
    ));

    try {
      await FirebaseFirestore.instance.collection('requests').doc(widget.chatId).update({'status': 'completed'});

      if (note != null && note.isNotEmpty) {
        await FirebaseFirestore.instance.collection('thank_you_notes').add({
          'fromUid': user.uid,
          'fromName': user.displayName,
          'toUid': requesterId, 'note': note, 'requestCategory': category,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final doc = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await doc.get();
      final currentScore = (snap.data()?['kindnessScore'] ?? 0) as int;
      final newScore = currentScore + _currentPoints;
      String level = 'Newcomer';
      if (newScore >= legendThreshold) level = 'Legend';
      else if (newScore >= championThreshold) level = 'Champion';
      else if (newScore >= helperThreshold) level = 'Helper';
      await doc.update({'kindnessScore': newScore, 'level': level, 'actsCompleted': FieldValue.increment(1)});

      await _sendPushNotification(requesterId, '${user.displayName} finished helping!', 'Your $category request was completed.');
      await FirebaseFirestore.instance.collection('notifications').add({
        'toUid': requesterId,
        'fromName': user.displayName,
        'title': 'Request completed!',
        'body': '${user.displayName} finished helping with $category.',
        'chatId': null,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (!mounted) return;
    _hapticHeavy();
    await _showConfetti(context);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request marked done! You earned +$_currentPoints points.'), backgroundColor: kAccentDark));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kCard, elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: kTextPrimary), onPressed: () => Navigator.pop(context)),
        title: GestureDetector(
          onTap: () => Navigator.push(context, _fadeSlideRoute(UserProfileScreen(uid: widget.otherUid, initialName: widget.otherName))),
          child: Text(widget.otherName, style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
        ),
        actions: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('requests').doc(widget.chatId).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const SizedBox.shrink();
              final data = snap.data!.data() as Map<String, dynamic>?;
              if (data == null || data['volunteerId'] != currentUid || data['status'] != 'claimed') return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Mark done',
                icon: Icon(Icons.check_circle_rounded, color: kAccent),
                onPressed: () => _completeRequestFromChat(snap.data!),
              );
            },
          ),
          PopupMenuButton<String>(
            color: kCard,
            icon: Icon(Icons.more_vert_rounded, color: kTextSecondary),
            onSelected: (v) {
              switch (v) {
                case 'profile':
                  Navigator.push(context, _fadeSlideRoute(UserProfileScreen(uid: widget.otherUid, initialName: widget.otherName)));
                case 'report':
                  _showReportSheet(context, widget.otherUid, widget.otherName, chatId: widget.chatId);
                case 'block':
                  _blockUser(context, widget.otherUid, name: widget.otherName);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('View Profile')),
              PopupMenuItem(value: 'report', child: Text('Report User')),
              PopupMenuItem(value: 'block', child: Text('Block User')),
            ],
          ),
        ],
      ),
      body: _blocked != null
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.block_rounded, color: Colors.redAccent, size: 56),
                  const SizedBox(height: 16),
                  Text(_blocked!, textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 15)),
                ]),
              ),
            )
          : Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).collection('messages').orderBy('createdAt').snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text('This conversation is no longer available.', style: TextStyle(color: kTextSecondary)));
            }
            if (!snap.hasData || snap.data!.docs.isEmpty) {
              return Center(child: Text('No messages yet. Say hello!', style: TextStyle(color: kTextSecondary)));
            }
            return ListView.builder(
              controller: _scrollController, padding: const EdgeInsets.all(16),
              itemCount: snap.data!.docs.length,
              itemBuilder: (context, i) {
                final msg = snap.data!.docs[i].data() as Map<String, dynamic>;
                final isMe = msg['senderId'] == currentUid;
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: isMe
                        ? BoxDecoration(gradient: kAccentGradient, borderRadius: BorderRadius.circular(18))
                        : BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider)),
                    child: Text(msg['text'] ?? '', style: TextStyle(color: isMe ? Colors.white : kTextPrimary, fontSize: 14)),
                  ),
                );
              },
            );
          },
        )),
        Container(
          padding: EdgeInsets.all(12), color: kCard,
          child: Row(children: [
            Expanded(child: TextField(
              controller: _controller, style: TextStyle(color: kTextPrimary),
              decoration: InputDecoration(hintText: 'Message...', hintStyle: TextStyle(color: kTextSecondary), filled: true, fillColor: kCardLight, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
              onSubmitted: (_) => _send(),
            )),
            const SizedBox(width: 8),
            _Pressable(onTap: _send, pressedScale: 0.9, child: Container(width: 44, height: 44, decoration: BoxDecoration(gradient: kAccentGradient, shape: BoxShape.circle, boxShadow: [BoxShadow(color: kAccent.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))]), child: const Icon(Icons.send_rounded, color: Colors.white, size: 20))),
          ]),
        ),
      ]),
    );
  }
}

// ─── CHATS INBOX ────────────────────────────────────────────────────────────

class ChatsListScreen extends StatefulWidget {
  const ChatsListScreen({super.key, this.asTab = false});
  final bool asTab;
  @override
  State<ChatsListScreen> createState() => _ChatsListScreenState();
}

class _ChatsListScreenState extends State<ChatsListScreen> {
  StreamSubscription<QuerySnapshot>? _chatNotifSub;

  @override
  void initState() {
    super.initState();
    _clearChatNotificationBadge();
  }

  @override
  void dispose() {
    _chatNotifSub?.cancel();
    super.dispose();
  }

  Future<void> _clearChatNotificationBadge() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final existing = await FirebaseFirestore.instance.collection('notifications')
          .where('toUid', isEqualTo: uid).where('read', isEqualTo: false).get();
      for (final d in existing.docs) {
        if ((d.data() as Map)['chatId'] != null) { await d.reference.update({'read': true}); }
      }
    } catch (_) {}
    _chatNotifSub = FirebaseFirestore.instance.collection('notifications')
        .where('toUid', isEqualTo: uid).where('read', isEqualTo: false).snapshots()
        .listen((snap) async {
      for (final d in snap.docs) {
        if ((d.data() as Map)['chatId'] != null) {
          try { await d.reference.update({'read': true}); } catch (_) {}
        }
      }
    });
  }

  Stream<List<QueryDocumentSnapshot>> _chatStreams(String uid) {
    final a = FirebaseFirestore.instance.collection('requests').where('requesterId', isEqualTo: uid).snapshots();
    final b = FirebaseFirestore.instance.collection('requests').where('volunteerId', isEqualTo: uid).snapshots();
    final controller = StreamController<List<QueryDocumentSnapshot>>();
    QuerySnapshot? latestA;
    QuerySnapshot? latestB;
    void emit() {
      final combined = <String, QueryDocumentSnapshot>{};
      for (final d in latestA?.docs ?? const <QueryDocumentSnapshot>[]) { combined[d.id] = d; }
      for (final d in latestB?.docs ?? const <QueryDocumentSnapshot>[]) { combined[d.id] = d; }
      controller.add(combined.values.toList());
    }
    late final StreamSubscription<QuerySnapshot> sa;
    late final StreamSubscription<QuerySnapshot> sb;
    controller.onListen = () {
      sa = a.listen((s) { latestA = s; emit(); });
      sb = b.listen((s) { latestB = s; emit(); });
    };
    controller.onCancel = () async {
      await sa.cancel();
      await sb.cancel();
    };
    return controller.stream;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground, elevation: 0, scrolledUnderElevation: 0,
        leading: widget.asTab ? null : IconButton(icon: Icon(Icons.arrow_back_rounded, color: kTextPrimary), onPressed: () => Navigator.pop(context)),
        title: Text('Messages', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: StreamBuilder<List<QueryDocumentSnapshot>>(
        stream: uid == null ? const Stream.empty() : _chatStreams(uid),
        builder: (context, snap) {
          if (!snap.hasData) return Center(child: CircularProgressIndicator(color: kAccent));
          final docs = snap.data!;
          final chats = docs.where((d) {
            final s = (d.data() as Map<String, dynamic>)['status'] ?? '';
            return s == 'claimed' || s == 'completed';
          }).toList()
            ..sort((a, b) {
              final ta = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final tb = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              return (tb?.millisecondsSinceEpoch ?? 0).compareTo(ta?.millisecondsSinceEpoch ?? 0);
            });
          if (chats.isEmpty) {
            return const _EmptyState(icon: Icons.forum_outlined, title: 'No conversations yet', subtitle: 'Chats open up when someone claims your request');
          }
          return FutureBuilder<DocumentSnapshot>(
            future: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).get(),
            builder: (context, userSnap) {
              final blockedUsers = List<String>.from((userSnap.data?.data() as Map<String, dynamic>?)?['blockedUsers'] ?? []);
              final visible = chats.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final isRequester = data['requesterId'] == uid;
                final otherUid = isRequester ? data['volunteerId'] : data['requesterId'];
                return !blockedUsers.contains(otherUid);
              }).toList();
              if (visible.isEmpty) {
                return const _EmptyState(icon: Icons.block_rounded, title: 'No conversations', subtitle: 'Chats with blocked users are hidden');
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: visible.length,
                itemBuilder: (context, i) {
                  final doc = visible[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] ?? 'claimed';
                  final category = data['category'] ?? 'Help';
                  final isRequester = data['requesterId'] == uid;
                  final otherName = isRequester ? (data['volunteerName'] ?? 'Helper') : (data['requesterName'] ?? 'Neighbor');
                  final otherUid = isRequester ? (data['volunteerId'] as String?) : (data['requesterId'] as String?);
                  final color = _categoryColor(category);
                  return _StaggerIn(
                    key: ValueKey('chat-${doc.id}'),
                    delayMs: i * 45,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Pressable(
                        onTap: () {
                          if (otherUid == null) return;
                          Navigator.of(context).push(_fadeSlideRoute(ChatScreen(chatId: doc.id, otherName: otherName, otherUid: otherUid)));
                        },
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                          child: Row(children: [
                            Container(width: 50, height: 50, decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                                child: Icon(_categoryIcon(category), color: color, size: 24)),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(otherName, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kTextPrimary))),
                                Text(status == 'completed' ? 'Completed' : 'In progress', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: status == 'completed' ? kAccent : Colors.orange)),
                              ]),
                              const SizedBox(height: 3),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('chats').doc(doc.id).collection('messages').orderBy('createdAt', descending: true).limit(1).snapshots(),
                                builder: (context, msgSnap) {
                                  final last = msgSnap.hasData && msgSnap.data!.docs.isNotEmpty ? msgSnap.data!.docs.first.data() as Map<String, dynamic> : null;
                                  final text = last?['text'] ?? '${status == 'completed' ? 'You' : ''} connected for $category';
                                  return Text(text.length > 60 ? '${text.substring(0, 60)}…' : text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: kTextSecondary));
                                },
                              ),
                            ])),
                            const SizedBox(width: 4),
                            StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('notifications')
                                  .where('toUid', isEqualTo: uid)
                                  .where('read', isEqualTo: false)
                                  .snapshots(),
                              builder: (context, notifSnap) {
                                final unread = notifSnap.data?.docs.where((d) => (d.data() as Map)['chatId'] == doc.id).length ?? 0;
                                if (unread == 0) return const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20);
                                return _PulsingDot(color: const Color(0xFF2DD4BF), size: 12);
                              },
                            ),
                            const SizedBox(width: 2),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                              tooltip: 'Delete chat',
                              onPressed: () => _deleteChat(context, doc.id, otherName),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ─── NEARBY MAP (CartoDB) ───────────────────────────────────────────────────
// shows open requests as pins on a map — users can tap to claim from here too

// haversine distance — used to filter nearby requests to the user's radius setting
double _distanceMiles(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusMi = 3958.8;
  final double dLat = (lat2 - lat1) * math.pi / 180;
  final double dLon = (lon2 - lon1) * math.pi / 180;
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * earthRadiusMi * math.asin(math.sqrt(a));
}

class _NearbyMap extends StatefulWidget {
  const _NearbyMap({this.expanded = false, this.onExpand});
  final bool expanded;
  final VoidCallback? onExpand;
  @override
  State<_NearbyMap> createState() => _NearbyMapState();
}

class _NearbyMapState extends State<_NearbyMap> {
  final MapController _mapController = MapController();
  LatLng _center = const LatLng(35.1495, -90.0490);
  bool _locationLoaded = false;
  bool _satellite = false;
  double _radiusMi = 1.0;

  @override
  void initState() { super.initState(); _loadSettings(); _loadLocation(); }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = doc.data();
      if (data != null) {
        final radius = data['nearbyRadiusMi'];
        if (radius is num && radius > 0) {
          setState(() => _radiusMi = radius.toDouble());
        }
      }
    } catch (_) {}
  }

  Future<void> _loadLocation() async {
    final pos = await _getCurrentPosition();
    if (pos == null) return;
    if (mounted) { setState(() { _center = LatLng(pos.latitude, pos.longitude); _locationLoaded = true; }); _mapController.move(_center, 13); }
    _saveMyLocation(pos);
  }

  Widget _pin(IconData icon, Color color) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.25)!], begin: Alignment.topLeft, end: Alignment.bottomRight),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Icon(icon, color: Colors.white, size: 19),
      ),
      Transform.rotate(angle: math.pi / 4, child: Container(width: 12, height: 12, decoration: BoxDecoration(color: color))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('status', isEqualTo: 'open').snapshots(),
      builder: (context, snap) {
        final markers = <Marker>[];
        var nearbyCount = 0;
        if (snap.hasData) {
          for (int i = 0; i < snap.data!.docs.length; i++) {
            final doc = snap.data!.docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final lat = (data['lat'] as double?) ?? (_center.latitude + (i * 0.002));
            final lng = (data['lng'] as double?) ?? (_center.longitude + (i * 0.002));
            if (_locationLoaded && _distanceMiles(_center.latitude, _center.longitude, lat, lng) > _radiusMi) {
              continue;
            }
            nearbyCount++;
            markers.add(Marker(
              point: LatLng(lat, lng), width: 48, height: 62, alignment: Alignment.bottomCenter,
              child: GestureDetector(
                onTap: () => _showDetail(context, data, doc.id),
                child: _pin(_categoryIcon(data['category'] ?? 'Other'), _categoryColor(data['category'] ?? 'Other')),
              ),
            ));
          }
        }
        final baseTiles = _satellite ? kTilesSatellite : kTilesLight;
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.expanded ? 0 : 18),
          child: Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 13,
                onTap: (tapPosition, point) {
                  if (!widget.expanded) widget.onExpand?.call();
                },
              ),
              children: [
                TileLayer(urlTemplate: baseTiles, subdomains: kTileSubdomains, userAgentPackageName: 'com.kindred.app'),
                MarkerLayer(markers: markers),
              ],
            ),
              if (!_locationLoaded) Positioned(top: 12, left: 12, right: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.orange.withValues(alpha: 0.3))),
                child: const Row(children: [
                  Icon(Icons.location_off_rounded, color: Colors.orange, size: 16), SizedBox(width: 8),
                  Expanded(child: Text('Enable location to see requests near you', style: TextStyle(fontSize: 12, color: Colors.orange))),
                ]),
              )),
              Positioned(top: 12, right: 12, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                _Pressable(
                  onTap: widget.expanded ? () => widget.onExpand?.call() : widget.onExpand,
                  pressedScale: 0.9,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kDivider), boxShadow: [kCardShadow]),
                    child: Icon(widget.expanded ? Icons.close_rounded : Icons.fullscreen_rounded, color: kAccent, size: 18),
                  ),
                ),
                const SizedBox(height: 8),
                _Pressable(
                  onTap: () => setState(() { _satellite = !_satellite; _haptic(); }),
                  pressedScale: 0.9,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kDivider), boxShadow: [kCardShadow]),
                    child: Column(children: [
                      Icon(_satellite ? Icons.map_rounded : Icons.satellite_alt_rounded, color: kAccent, size: 18),
                      const SizedBox(height: 2),
                      Text(_satellite ? 'Streets' : 'Satellite', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kTextPrimary)),
                    ]),
                  ),
                ),
              ])),
              Positioned(bottom: 12, left: 12, right: 12, child: _Pressable(
                onTap: () => _loadLocation(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kDivider), boxShadow: [kCardShadow]),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const _PulsingDot(color: Color(0xFF34D399), size: 8),
                    const SizedBox(width: 8),
                    Text(snap.hasData ? '$nearbyCount open request${nearbyCount == 1 ? '' : 's'} nearby' : 'Loading...', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kTextPrimary)),
                    const SizedBox(width: 6),
                    Text('· within ${_radiusMi.toStringAsFixed(_radiusMi == _radiusMi.roundToDouble() ? 0 : 1)} mi', style: TextStyle(fontSize: 12, color: kTextSecondary)),
                  ]),
                ),
              )),
            ]),
          );
      },
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> data, String docId) {
    _hapticHeavy();
    showModalBottomSheet(context: context, backgroundColor: Colors.transparent, builder: (_) => Container(
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kDivider, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(color: _categoryColor(data['category'] ?? 'Other').withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
              child: Icon(_categoryIcon(data['category'] ?? 'Other'), color: _categoryColor(data['category'] ?? 'Other'), size: 26)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(data['category'] ?? 'Help Request', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextPrimary)),
            Text('by ${data['requesterName'] ?? 'Someone'}', style: TextStyle(color: kTextSecondary)),
          ])),
        ]),
        if ((data['description'] ?? '').isNotEmpty) ...[SizedBox(height: 12), Text(data['description'], style: TextStyle(fontSize: 14, color: kTextSecondary, height: 1.5))],
        const SizedBox(height: 20),
        _KindredButton(
          label: "I'll Help",
          onPressed: () async {
            final user = FirebaseAuth.instance.currentUser;
            if (user == null) return;
            if (data['requesterId'] == user.uid) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That's your own request!"))); return; }
            await _completeClaim(data, docId);
            if (context.mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You claimed this request!'), backgroundColor: kAccentDark)); }
          },
        ),
        const SizedBox(height: 8),
      ]),
    ));
  }
}

class _FullscreenMapScreen extends StatelessWidget {
  const _FullscreenMapScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: SafeArea(
        child: _NearbyMap(expanded: true, onExpand: () => Navigator.of(context).pop()),
      ),
    );
  }
}

// ─── LEADERBOARD ──────────────────────────────────────────────────────────────
// top users sorted by kindness score — shows level badge and acts count

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    // ranked top-50 helpers, excludes anyone the user has blocked
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground, elevation: 0, scrolledUnderElevation: 0,
        title: Text('Leaderboard', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800, fontSize: 24)),
        centerTitle: true,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: currentUid == null ? null : FirebaseFirestore.instance.collection('users').doc(currentUid).get(),
        builder: (context, userSnap) {
          final blockedUsers = List<String>.from((userSnap.data?.data() as Map<String, dynamic>?)?['blockedUsers'] ?? []);
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').orderBy('kindnessScore', descending: true).limit(50).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return Center(child: CircularProgressIndicator(color: kAccent));
              final docs = snap.data!.docs.where((d) => !blockedUsers.contains(d.id)).toList();
              return ListView.builder(
                padding: const EdgeInsets.all(16), itemCount: docs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) return Padding(padding: EdgeInsets.only(bottom: 16), child: Text('Top Community Helpers', style: TextStyle(fontSize: 15, color: kTextSecondary, fontWeight: FontWeight.w600)));
                  final i = index - 1;
                  final data = docs[i].data() as Map<String, dynamic>;
                  final isMe = docs[i].id == currentUid;
                  final rank = i + 1;
                  String rankLabel = '#$rank';
                  Color rankColor = kTextSecondary;
                  if (rank == 1) { rankColor = const Color(0xFFFFD700); }
                  else if (rank == 2) { rankColor = const Color(0xFFC9D4DE); }
                  else if (rank == 3) { rankColor = const Color(0xFFD2966A); }

                  return _Pressable(
                    onTap: isMe
                        ? () { final m = context.findAncestorStateOfType<_MainScreenState>(); m?.switchToTab(4); }
                        : () => Navigator.of(context).push(_fadeSlideRoute(UserProfileScreen(uid: docs[i].id))),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isMe ? kAccent.withValues(alpha: 0.1) : kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isMe ? kAccent : kDivider),
                        boxShadow: [kSoftShadow],
                      ),
                      child: Row(children: [
                        SizedBox(width: 40, child: rank <= 3 ? _Medal(rank: rank, size: 34) : Text(rankLabel, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: rankColor))),
                        CircleAvatar(radius: 18, backgroundImage: _avatarImage(data['photoUrl']), backgroundColor: kAccent, child: data['photoUrl'] == null ? const Icon(Icons.person, color: Colors.white, size: 14) : null),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(data['username']?.isNotEmpty == true ? '@${data['username']}' : data['name'] ?? 'Kindred Member',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: isMe ? kAccent : kTextPrimary)),
                          Text('${data['actsCompleted'] ?? 0} acts · ${data['level'] ?? 'Newcomer'}', style: TextStyle(fontSize: 12, color: kTextSecondary)),
                        ])),
                        Text('${data['kindnessScore'] ?? 0}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: kAccent)),
                        Text(' pts', style: TextStyle(fontSize: 12, color: kTextSecondary)),
                        Icon(Icons.chevron_right_rounded, color: kTextSecondary.withValues(alpha: 0.5), size: 18),
                      ]),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

// ─── PROFILE ──────────────────────────────────────────────────────────────────
// own profile: edit username/bio/phone/photo, view points and badges

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  // TODO: move phone number to the private subcollection only — it's PII
  Future<void> _showEditProfile(BuildContext context, Map<String, dynamic> data, String level) async {
    var phone = '';
    try {
      final priv = await FirebaseFirestore.instance
          .collection('users').doc(FirebaseAuth.instance.currentUser?.uid)
          .collection('private').doc('data').get();
      phone = (priv.data()?['phone'] as String?) ?? '';
    } catch (_) {}
    if (!context.mounted) return;
    final usernameController = TextEditingController(text: data['username'] ?? '');
    final bioController = TextEditingController(text: data['bio'] ?? '');
    final phoneController = TextEditingController(text: phone);
    final user = FirebaseAuth.instance.currentUser;
    final canEditUsername = level != 'Newcomer';
    final canEditBanner = level == 'Champion' || level == 'Legend';
    final canEditFrame = level == 'Legend';
    int selectedBannerColor = data['bannerColor'] ?? 0xFF7BAE8A;
    String selectedFrame = data['frameStyle'] ?? 'none';
    String? newPhotoData;
    void Function(VoidCallback)? setModalState;

    Future<void> pickPhoto() async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 72);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setModalState?.call(() => newPhotoData = 'data:image/jpeg;base64,${base64Encode(bytes)}');
    }

    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (context, setState) {
        setModalState = setState;
        return Container(
        height: MediaQuery.of(context).size.height * 0.95,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: EdgeInsets.only(left: 24, right: 24, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Edit Profile', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextPrimary)),
            TextButton(
              onPressed: () async {
                final updates = <String, dynamic>{};
                if (canEditUsername) { updates['username'] = usernameController.text.trim(); updates['bio'] = bioController.text.trim(); }
                if (canEditBanner) updates['bannerColor'] = selectedBannerColor;
                if (canEditFrame) updates['frameStyle'] = selectedFrame;
                if (newPhotoData != null) updates['photoUrl'] = newPhotoData;
                await FirebaseFirestore.instance.collection('users').doc(user?.uid).update(updates);
                await FirebaseFirestore.instance
                    .collection('users').doc(user?.uid).collection('private').doc('data')
                    .set({'phone': phoneController.text.trim()}, SetOptions(merge: true));
                if (context.mounted) Navigator.pop(context);
              },
              child: Text('Save', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ]),
          const SizedBox(height: 20),
          _ProfileField(title: 'Profile Photo', locked: false, lockMessage: '',
              child: Row(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: _avatarImage(newPhotoData ?? data['photoUrl'] ?? user?.photoURL),
                  backgroundColor: kAccent.withValues(alpha: 0.3),
                  child: newPhotoData == null && data['photoUrl'] == null && user?.photoURL == null
                      ? const Icon(Icons.person, size: 30, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(child: Wrap(spacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: pickPhoto,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Choose photo'),
                    style: OutlinedButton.styleFrom(foregroundColor: kAccent, side: BorderSide(color: kAccent.withValues(alpha: 0.6))),
                  ),
                  if (newPhotoData != null)
                    TextButton(
                      onPressed: () => setState(() => newPhotoData = null),
                      child: Text('Cancel', style: TextStyle(color: kTextSecondary)),
                    ),
                ])),
              ])),
          const SizedBox(height: 16),
          _ProfileField(title: 'Username', locked: !canEditUsername, lockMessage: 'Reach Helper to unlock',
              child: TextField(controller: usernameController, enabled: canEditUsername, style: TextStyle(color: kTextPrimary),
                  decoration: _fieldDecoration('username'))),
          const SizedBox(height: 16),
          _ProfileField(title: 'Bio', locked: !canEditUsername, lockMessage: 'Reach Helper to unlock',
              child: TextField(controller: bioController, enabled: canEditUsername, maxLines: 3, maxLength: 120, style: TextStyle(color: kTextPrimary),
                  decoration: _fieldDecoration('Tell your community about yourself...', counter: true))),
          const SizedBox(height: 16),
          _ProfileField(title: 'Phone', locked: false, lockMessage: '',
              child: TextField(controller: phoneController, keyboardType: TextInputType.phone, style: TextStyle(color: kTextPrimary),
                  decoration: _fieldDecoration('+1 (555) 000-0000', prefix: Icon(Icons.phone_outlined, color: kAccent, size: 20)))),
          const SizedBox(height: 16),
          _ProfileField(title: 'Banner Color', locked: !canEditBanner, lockMessage: 'Reach Champion to unlock',
              child: Wrap(spacing: 10, children: bannerColors.map((color) {
                final isSelected = selectedBannerColor == color.toARGB32();
                return GestureDetector(
                  onTap: canEditBanner ? () => setState(() => selectedBannerColor = color.toARGB32()) : null,
                  child: Container(width: 38, height: 38, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.white, width: 3) : null),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null),
                );
              }).toList())),
          const SizedBox(height: 16),
          _ProfileField(title: 'Avatar Frame', locked: !canEditFrame, lockMessage: 'Reach Legend to unlock',
              child: Wrap(spacing: 8, children: ['none', 'gold', 'purple', 'rainbow'].map((f) {
                final labels = {'none': 'None', 'gold': 'Gold', 'purple': 'Purple', 'rainbow': 'Rainbow'};
                final isSelected = selectedFrame == f;
                return GestureDetector(
                  onTap: canEditFrame ? () => setState(() => selectedFrame = f) : null,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: isSelected ? kAccent.withValues(alpha: 0.2) : kCardLight, borderRadius: BorderRadius.circular(10), border: isSelected ? Border.all(color: kAccent) : null),
                    child: Text(labels[f]!, style: TextStyle(color: isSelected ? kAccent : kTextSecondary, fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal)),
                  ),
                );
              }).toList())),
        ])));
      }),
    );
  }

  static InputDecoration _fieldDecoration(String hint, {Widget? prefix, bool counter = false}) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: kTextSecondary),
    prefixIcon: prefix,
    filled: true, fillColor: kCardLight,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: kDivider)),
    counterStyle: counter ? TextStyle(color: kTextSecondary) : null,
  );

  void _showProfile(BuildContext context, String uid, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.all(32),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Your Kindred Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextPrimary)),
            const SizedBox(height: 6),
            Text('@$name', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 24),
            _KindredButton(
              label: 'Share Profile',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: const Text('Sharing comes with the full app release — Kindred is in beta!'),
                backgroundColor: kAccentDark,
              )),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: kBackground,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final score = data?['kindnessScore'] ?? 0;
          final level = data?['level'] ?? 'Newcomer';
          final acts = data?['actsCompleted'] ?? 0;
          final joinedAt = data?['joinedAt'] as Timestamp?;
          final username = data?['username'] ?? '';
          final bio = data?['bio'] ?? '';
          final streak = data?['streak'] ?? 0;
          final badges = List<String>.from(data?['badges'] ?? []);
          final bannerColorVal = data?['bannerColor'] ?? 0xFF7BAE8A;
          final frameStyle = data?['frameStyle'] ?? 'none';
          final bannerColor = Color(bannerColorVal);

          return CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 220, pinned: true, backgroundColor: kBackground,
              actions: [
                IconButton(
                  icon: const Icon(Icons.qr_code_rounded, color: Colors.white),
                  onPressed: () => _showProfile(context, user?.uid ?? '', username.isNotEmpty ? username : user?.displayName ?? ''),
                ),
                IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.white), onPressed: () => _showEditProfile(context, data ?? {}, level)),
                IconButton(icon: const Icon(Icons.settings_rounded, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [bannerColor, bannerColor.withValues(alpha: 0.6)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  child: SafeArea(child: LayoutBuilder(builder: (context, constraints) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 14),
                          _AvatarWithFrame(photoUrl: data?['photoUrl'] ?? user?.photoURL, frameStyle: frameStyle),
                          const SizedBox(height: 10),
                          Text(username.isNotEmpty ? '@$username' : user?.displayName ?? 'Kindred Member',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                          if (bio.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                              child: Text(bio, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          if (streak > 0) const SizedBox(height: 6),
                          if (streak > 0) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                            child: Text('$streak day streak', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  ))),
                ),
              ),
            ),

            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kDivider)),
                  child: Text('Joined ${_formatDate(joinedAt)}', style: TextStyle(fontSize: 13, color: kTextSecondary))),
              const SizedBox(height: 16),
              Row(children: [
                _StatCard(label: 'Points', value: '$score', icon: Icons.star_rounded),
                const SizedBox(width: 10),
                _StatCard(label: 'Acts', value: '$acts', icon: Icons.handshake_rounded),
                const SizedBox(width: 10),
                _StatCard(label: 'Streak', value: '$streak', icon: Icons.local_fire_department_rounded),
              ]),

              if (badges.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(width: double.infinity, padding: EdgeInsets.all(16), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Badges', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kTextPrimary)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: badges.map((b) => _BadgeChip(badge: b)).toList()),
                    ])),
              ],

              const SizedBox(height: 16),
              Container(width: double.infinity, padding: EdgeInsets.all(18), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [
                      Icon(_levelIcon(level), color: _levelColor(level), size: 17),
                      const SizedBox(width: 6),
                      Text(level, style: TextStyle(color: _levelColor(level), fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    Text(_levelNextMessage(score), style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _levelProgress(score), minHeight: 6, backgroundColor: kCardLight, valueColor: AlwaysStoppedAnimation<Color>(_levelColor(level)))),
                  const SizedBox(height: 16),
                  Divider(color: kDivider),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerLeft, child: Text('Level Perks', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kTextPrimary))),
                  const SizedBox(height: 10),
                  _PerkRow(icon: Icons.person_rounded, level: 'Newcomer', perk: 'Basic profile', unlocked: true),
                  _PerkRow(icon: Icons.edit_rounded, level: 'Helper (50pts)', perk: 'Custom username & bio', unlocked: score >= helperThreshold),
                  _PerkRow(icon: Icons.palette_rounded, level: 'Champion (150pts)', perk: 'Banner color picker', unlocked: score >= championThreshold),
                  _PerkRow(icon: Icons.auto_awesome_rounded, level: 'Legend (500pts)', perk: 'Exclusive avatar frames', unlocked: score >= legendThreshold),
                ])),

              const SizedBox(height: 24),
              Align(alignment: Alignment.centerLeft, child: Text('Thank You Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary))),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('thank_you_notes').where('toUid', isEqualTo: user?.uid).orderBy('createdAt', descending: true).snapshots(),
                builder: (context, noteSnap) {
                  if (!noteSnap.hasData || noteSnap.data!.docs.isEmpty) {
                    return Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Column(children: [
                          Icon(Icons.favorite_outline_rounded, color: kBadge.withValues(alpha: 0.6), size: 32),
                          const SizedBox(height: 10),
                          Text('No thank you notes yet. Help someone!', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ]));
                  }
                  return Column(children: noteSnap.data!.docs.map((doc) {
                    final n = doc.data() as Map<String, dynamic>;
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kBadge.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: kBadge.withValues(alpha: 0.2))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('From ${n['fromName'] ?? 'Someone'}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kBadge)),
                          const SizedBox(height: 4),
                          Text(n['note'] ?? '', style: TextStyle(fontSize: 13, color: kTextPrimary, height: 1.5)),
                          Text('For: ${n['requestCategory'] ?? ''}', style: TextStyle(fontSize: 11, color: kTextSecondary)),
                        ]));
                  }).toList());
                },
              ),

              const SizedBox(height: 24),
              Align(alignment: Alignment.centerLeft, child: Text('Kindness History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary))),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(user?.uid).collection('history').orderBy('completedAt', descending: true).snapshots(),
                builder: (context, histSnap) {
                  if (!histSnap.hasData || histSnap.data!.docs.isEmpty) {
                    return Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Column(children: [
                          Icon(Icons.volunteer_activism_outlined, color: kAccent.withValues(alpha: 0.6), size: 32),
                          const SizedBox(height: 10),
                          Text('No acts logged yet. Start helping!', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ]));
                  }
                  return Column(children: histSnap.data!.docs.map((doc) {
                    final h = doc.data() as Map<String, dynamic>;
                    final completedAt = h['completedAt'] as Timestamp?;
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Row(children: [
                          Container(width: 42, height: 42, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                              child: Center(child: Text(h['emoji'] ?? '🌟', style: const TextStyle(fontSize: 20)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h['act'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
                            Text(h['reason'] ?? '', style: TextStyle(fontSize: 11, color: kTextSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (completedAt != null) Text(_formatDate(completedAt), style: TextStyle(fontSize: 10, color: kTextSecondary)),
                          ])),
                          Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text('+${h['points']} pts', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 12))),
                        ]));
                  }).toList());
                },
              ),
              const SizedBox(height: 20),
            ]))),
          ]);
        },
      ),
    );
  }
}

// ─── PUBLIC USER PROFILE ─────────────────────────────────────────────────────

class UserProfileScreen extends StatefulWidget {
  final String uid;
  final String? initialName;
  const UserProfileScreen({super.key, required this.uid, this.initialName});
  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _isBlocked = false;
  bool _loadingBlocked = true;

  @override
  void initState() {
    super.initState();
    _loadBlockState();
  }

  Future<void> _loadBlockState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final blocked = await _getBlockedUsers(uid);
    if (mounted) setState(() { _isBlocked = blocked.contains(widget.uid); _loadingBlocked = false; });
  }

  Future<void> _toggleBlock() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _hapticHeavy();
    if (_isBlocked) {
      await _unblockUser(context, widget.uid);
      if (mounted) setState(() => _isBlocked = false);
      return;
    }
    final confirm = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
      title: 'Block this user?',
      content: "They won't be able to contact you and their requests will be hidden from you.",
      actionText: 'Block',
      onAction: () => Navigator.pop(context, true),
      cancelText: 'Cancel',
      onCancel: () => Navigator.pop(context, false),
      destructive: true,
    ));
    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({'blockedUsers': FieldValue.arrayUnion([widget.uid])});
    if (mounted) {
      setState(() => _isBlocked = true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User blocked.'), backgroundColor: kAccentDark));
    }
  }

  Future<void> _openChat(String otherName) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final r1 = await FirebaseFirestore.instance.collection('requests')
        .where('requesterId', isEqualTo: myUid).where('volunteerId', isEqualTo: widget.uid).get();
    final r2 = await FirebaseFirestore.instance.collection('requests')
        .where('requesterId', isEqualTo: widget.uid).where('volunteerId', isEqualTo: myUid).get();
    String? chatId;
    if (r1.docs.isNotEmpty) { chatId = r1.docs.first.id; }
    else if (r2.docs.isNotEmpty) { chatId = r2.docs.first.id; }
    if (chatId == null || !mounted) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('You can message $otherName after you connect through a request.')));
      return;
    }
    Navigator.push(context, _fadeSlideRoute(ChatScreen(chatId: chatId, otherName: otherName, otherUid: widget.uid)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isMe = user?.uid == widget.uid;
    return Scaffold(
      backgroundColor: kBackground,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() as Map<String, dynamic>?;
          final usernameField = data?['username'] as String?;
          final nameField = data?['name'] as String?;
          final displayName = (usernameField != null && usernameField.isNotEmpty ? usernameField : nameField) ?? widget.initialName ?? 'Kindred Member';
          final score = data?['kindnessScore'] ?? 0;
          final level = data?['level'] ?? 'Newcomer';
          final acts = data?['actsCompleted'] ?? 0;
          final joinedAt = data?['joinedAt'] as Timestamp?;
          final bio = data?['bio'] ?? '';
          final streak = data?['streak'] ?? 0;
          final badges = List<String>.from(data?['badges'] ?? []);
          final bannerColor = Color(data?['bannerColor'] ?? 0xFF7BAE8A);
          final frameStyle = data?['frameStyle'] ?? 'none';
          final photoUrl = data?['photoUrl'];

          return CustomScrollView(slivers: [
            SliverAppBar(
              expandedHeight: 220, pinned: true, backgroundColor: kBackground,
              leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => Navigator.pop(context)),
              actions: [
                if (!isMe) ...[
                  IconButton(
                    icon: Icon(_loadingBlocked ? Icons.hourglass_top_rounded : (_isBlocked ? Icons.block_rounded : Icons.block_outlined), color: _isBlocked ? Colors.red : Colors.white),
                    tooltip: _isBlocked ? 'Unblock' : 'Block',
                    onPressed: _loadingBlocked ? null : _toggleBlock,
                  ),
                  IconButton(icon: const Icon(Icons.flag_outlined, color: Colors.white), tooltip: 'Report',
                      onPressed: () => _showReportSheet(context, widget.uid, displayName)),
                ],
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: BoxDecoration(gradient: LinearGradient(colors: [bannerColor, bannerColor.withValues(alpha: 0.6)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                  child: SafeArea(child: LayoutBuilder(builder: (context, constraints) => Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const SizedBox(height: 14),
                          _AvatarWithFrame(photoUrl: photoUrl, frameStyle: frameStyle),
                          const SizedBox(height: 10),
                          Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                          if (bio.isNotEmpty) Padding(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                              child: Text(bio, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          if (streak > 0) const SizedBox(height: 6),
                          if (streak > 0) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                            child: Text('$streak day streak', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          ),
                        ]),
                      ),
                    ),
                  ))),
                ),
              ),
            ),

            SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
              Container(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kDivider)),
                  child: Text('Joined ${_formatDate(joinedAt)}', style: TextStyle(fontSize: 13, color: kTextSecondary))),
              const SizedBox(height: 16),
              Row(children: [
                _StatCard(label: 'Points', value: '$score', icon: Icons.star_rounded),
                const SizedBox(width: 10),
                _StatCard(label: 'Acts', value: '$acts', icon: Icons.handshake_rounded),
                const SizedBox(width: 10),
                _StatCard(label: 'Streak', value: '$streak', icon: Icons.local_fire_department_rounded),
              ]),
              const SizedBox(height: 16),
              if (!isMe)
                _KindredButton(
                  label: 'Message $displayName',
                  onPressed: () => _openChat(displayName),
                ),
              if (!isMe) const SizedBox(height: 8),

              if (badges.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(width: double.infinity, padding: EdgeInsets.all(16), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Badges', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: kTextPrimary)),
                      const SizedBox(height: 10),
                      Wrap(spacing: 8, runSpacing: 8, children: badges.map((b) => _BadgeChip(badge: b)).toList()),
                    ])),
              ],

              const SizedBox(height: 16),
              Container(width: double.infinity, padding: EdgeInsets.all(18), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Row(children: [
                      Icon(_levelIcon(level), color: _levelColor(level), size: 17),
                      const SizedBox(width: 6),
                      Text(level, style: TextStyle(color: _levelColor(level), fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    Text(_levelNextMessage(score), style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _levelProgress(score), minHeight: 6, backgroundColor: kCardLight, valueColor: AlwaysStoppedAnimation<Color>(_levelColor(level)))),
                ])),

              const SizedBox(height: 24),
              Align(alignment: Alignment.centerLeft, child: Text('Thank You Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary))),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('thank_you_notes').where('toUid', isEqualTo: widget.uid).orderBy('createdAt', descending: true).snapshots(),
                builder: (context, noteSnap) {
                  if (!noteSnap.hasData || noteSnap.data!.docs.isEmpty) {
                    return Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Column(children: [
                          Icon(Icons.favorite_outline_rounded, color: kBadge.withValues(alpha: 0.6), size: 32),
                          const SizedBox(height: 10),
                          Text('No thank you notes yet.', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ]));
                  }
                  return Column(children: noteSnap.data!.docs.map((doc) {
                    final n = doc.data() as Map<String, dynamic>;
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kBadge.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: kBadge.withValues(alpha: 0.2))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('From ${n['fromName'] ?? 'Someone'}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: kBadge)),
                          const SizedBox(height: 4),
                          Text(n['note'] ?? '', style: TextStyle(fontSize: 13, color: kTextPrimary, height: 1.5)),
                          Text('For: ${n['requestCategory'] ?? ''}', style: TextStyle(fontSize: 11, color: kTextSecondary)),
                        ]));
                  }).toList());
                },
              ),

              const SizedBox(height: 24),
              Align(alignment: Alignment.centerLeft, child: Text('Kindness History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextPrimary))),
              const SizedBox(height: 10),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').doc(widget.uid).collection('history').orderBy('completedAt', descending: true).snapshots(),
                builder: (context, histSnap) {
                  if (!histSnap.hasData || histSnap.data!.docs.isEmpty) {
                    return Container(width: double.infinity, padding: EdgeInsets.all(20), decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Column(children: [
                          Icon(Icons.volunteer_activism_outlined, color: kAccent.withValues(alpha: 0.6), size: 32),
                          const SizedBox(height: 10),
                          Text('No acts logged yet.', textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
                        ]));
                  }
                  return Column(children: histSnap.data!.docs.map((doc) {
                    final h = doc.data() as Map<String, dynamic>;
                    final completedAt = h['completedAt'] as Timestamp?;
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
                        child: Row(children: [
                          Container(width: 42, height: 42, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                              child: Center(child: Text(h['emoji'] ?? '🌟', style: const TextStyle(fontSize: 20)))),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(h['act'] ?? '', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
                            Text(h['reason'] ?? '', style: TextStyle(fontSize: 11, color: kTextSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                            if (completedAt != null) Text(_formatDate(completedAt), style: TextStyle(fontSize: 10, color: kTextSecondary)),
                          ])),
                          Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text('+${h['points']} pts', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 12))),
                        ]));
                  }).toList());
                },
              ),
              const SizedBox(height: 20),
            ]))),
          ]);
        },
      ),
    );
  }
}

// ─── SETTINGS ─────────────────────────────────────────────────────────────────
// account, notifications, nearby radius, theme, privacy links, report, delete

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifMessages = true;
  bool _notifRequests = true;
  ThemeMode _themeMode = ThemeMode.system;
  String _language = 'English';
  double _nearbyRadiusMi = 1.0;
  // TODO: pull this from package_info at startup instead of hardcoding fallback
  String _appVersion = 'bv0.6.0';

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    setState(() => _appVersion = info.version);
  }

  Future<void> _loadSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return;
    setState(() {
      _notifMessages = data['notifMessages'] ?? true;
      _notifRequests = data['notifRequests'] ?? true;
      _language = data['language'] ?? 'English';
      final radius = data['nearbyRadiusMi'];
      if (radius is num && radius > 0) _nearbyRadiusMi = radius.toDouble();
      final mode = data['themeMode'] as String?;
      if (mode != null) {
        final parsed = ThemeMode.values.where((m) => m.name == mode);
        if (parsed.isNotEmpty) {
          _themeMode = parsed.first;
          KindredApp.of(context)?.setThemeMode(parsed.first);
        }
      }
    });
  }

  Future<void> _saveSettings() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'notifMessages': _notifMessages,
      'notifRequests': _notifRequests,
      'language': _language,
      'nearbyRadiusMi': _nearbyRadiusMi,
    });
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => _KindredDialog(
      title: 'Delete Account?',
      content: 'This will permanently delete your account and all your data. This cannot be undone.',
      actionText: 'Delete',
      onAction: () => Navigator.pop(context, true),
      cancelText: 'Cancel',
      onCancel: () => Navigator.pop(context, false),
      destructive: true,
    ));
    if (confirm != true) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await FirebaseFirestore.instance.collection('users').doc(uid).collection('private').doc('data').delete();
      await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    }
    await FirebaseAuth.instance.currentUser?.delete();
    if (!kIsWeb) await GoogleSignIn().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: kBackground, elevation: 0, scrolledUnderElevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: kTextPrimary), onPressed: () => Navigator.pop(context)),
        title: Text('Settings', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800, fontSize: 22)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _SettingsSection(title: 'Appearance', children: [
            _SettingsTile(
              icon: Icons.brightness_auto_rounded,
              title: 'Theme',
              trailing: DropdownButton<ThemeMode>(
                value: _themeMode,
                dropdownColor: kCard,
                style: TextStyle(color: kTextPrimary),
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                  DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _themeMode = v);
                    KindredApp.of(context)?.setThemeMode(v);
                  }
                },
              ),
            ),
            _SettingsTile(
              icon: Icons.language_rounded,
              title: 'Language',
              trailing: DropdownButton<String>(
                value: _language,
                dropdownColor: kCard,
                style: TextStyle(color: kTextPrimary),
                underline: const SizedBox(),
                items: ['English', 'Spanish', 'French', 'Portuguese'].map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) { if (v != null) { setState(() => _language = v); _saveSettings(); } },
              ),
            ),
          ]),

          _SettingsSection(title: 'Notifications', children: [
            _SettingsTile(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'Message notifications',
              trailing: Switch(value: _notifMessages, onChanged: (v) { setState(() => _notifMessages = v); _saveSettings(); }, activeThumbColor: kAccent),
            ),
            _SettingsTile(
              icon: Icons.volunteer_activism_outlined,
              title: 'Request notifications',
              trailing: Switch(value: _notifRequests, onChanged: (v) { setState(() => _notifRequests = v); _saveSettings(); }, activeThumbColor: kAccent),
            ),
          ]),

          _SettingsSection(title: 'Nearby', children: [
            _SettingsTile(
              icon: Icons.radar_rounded,
              title: 'Nearby search radius',
              subtitle: 'Only requests within this distance count as nearby.',
              trailing: Text('${_nearbyRadiusMi.toStringAsFixed(_nearbyRadiusMi == _nearbyRadiusMi.roundToDouble() ? 0 : 1)} mi', style: TextStyle(color: kAccent, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Slider(
                value: _nearbyRadiusMi.clamp(0.25, 25.0),
                min: 0.25,
                max: 25.0,
                divisions: 99,
                activeColor: kAccent,
                inactiveColor: kDivider,
                label: '${_nearbyRadiusMi.toStringAsFixed(_nearbyRadiusMi == _nearbyRadiusMi.roundToDouble() ? 0 : 1)} mi',
                onChanged: (v) { setState(() => _nearbyRadiusMi = v); _saveSettings(); },
              ),
            ),
          ]),

          _SettingsSection(title: 'Privacy', children: [
            const _BlockedUsersSection(),
          ]),

          _SettingsSection(title: 'About', children: [
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              title: 'About Kindred',
              onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                backgroundColor: kCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('About Kindred', style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
                content: Text('Kindred is a community mutual-aid app where neighbors can help neighbors with everyday tasks — completely free of charge, powered by kindness.\n\nBuilt with love to make communities stronger, one act at a time. Made with ❤️ in Bartlett, TN by Jonah B.', style: TextStyle(color: kTextSecondary, height: 1.6)),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: kAccent)))],
              )),
            ),
            _SettingsTile(
              icon: Icons.school_outlined,
              title: 'View Tutorial',
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TutorialScreen())),
            ),
            _SettingsTile(
              icon: Icons.bug_report_outlined,
              title: 'Report a Bug',
              onTap: () async {
                final uri = Uri.parse('mailto:jonahb344+kindred@gmail.com?subject=${Uri.encodeQueryComponent('Kindred Bug Report')}&body=${Uri.encodeQueryComponent('Describe the bug...')}');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No email app found. Report to jonahb344+kindred@gmail.com')));
                }
              },
            ),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              title: 'App Version',
              trailing: Text(_appVersion, style: TextStyle(color: kTextSecondary, fontSize: 14)),
            ),
          ]),

          _SettingsSection(title: 'Account', children: [
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Sign Out',
              onTap: () async {
                if (!kIsWeb) await GoogleSignIn().signOut();
                await FirebaseAuth.instance.signOut();
              },
            ),
            _SettingsTile(
              icon: Icons.delete_outline_rounded,
              title: 'Delete Account',
              titleColor: Colors.red,
              onTap: () => _deleteAccount(context),
            ),
          ]),

          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Text.rich(
              TextSpan(
                style: TextStyle(fontSize: 12, color: kTextSecondary, height: 1.8),
                children: [
                  TextSpan(text: 'By using Kindred you agree to our '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: TextStyle(color: kAccent, fontWeight: FontWeight.w600),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openUrl('https://kindred.jonahb344.workers.dev/privacy'),
                  ),
                  TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: TextStyle(color: kAccent, fontWeight: FontWeight.w600),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => _openUrl('https://kindred.jonahb344.workers.dev/terms'),
                  ),
                  TextSpan(text: '.'),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
      }
    }
  }
}

class _BlockedUsersSection extends StatelessWidget {
  const _BlockedUsersSection();
  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot>(
      stream: uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final blockedIds = List<String>.from((snap.data?.data() as Map<String, dynamic>?)?['blockedUsers'] ?? []);
        if (blockedIds.isEmpty) {
          return const _SettingsTile(icon: Icons.block_rounded, title: 'Blocked Users');
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text('Blocked Users (${blockedIds.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSecondary, letterSpacing: 0.8))),
          ...blockedIds.map((id) => FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(id).get(),
            builder: (context, uSnap) {
              final d = uSnap.data?.data() as Map<String, dynamic>?;
              final usernameField = d?['username'] as String?;
              final nameField = d?['name'] as String?;
              final name = (usernameField != null && usernameField.isNotEmpty ? '@$usernameField' : nameField) ?? 'Blocked user';
              return ListTile(
                leading: CircleAvatar(radius: 16, backgroundImage: _avatarImage(d?['photoUrl']), backgroundColor: kCardLight, child: d?['photoUrl'] == null ? const Icon(Icons.person, size: 16) : null),
                title: Text(name, style: TextStyle(color: kTextPrimary, fontSize: 14)),
                trailing: TextButton(
                  onPressed: () async {
                    if (uid == null) return;
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({'blockedUsers': FieldValue.arrayRemove([id])});
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User unblocked.'), backgroundColor: kAccentDark));
                  },
                  child: Text('Unblock', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600)),
                ),
              );
            },
          )),
        ]);
      },
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: EdgeInsets.only(bottom: 10), child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kTextSecondary, letterSpacing: 0.8))),
      Container(
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
        child: Column(children: children.asMap().entries.map((e) {
          return Column(children: [
            e.value,
            if (e.key < children.length - 1) Divider(height: 1, color: kDivider, indent: 52),
          ]);
        }).toList()),
      ),
      const SizedBox(height: 24),
    ]);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final String? subtitle;
  const _SettingsTile({required this.icon, required this.title, this.trailing, this.onTap, this.titleColor, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: (titleColor == Colors.red ? Colors.red : kAccent).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: titleColor == Colors.red ? Colors.red : kAccent, size: 19)),
        title: Text(title, style: TextStyle(color: titleColor ?? kTextPrimary, fontSize: 15, fontWeight: FontWeight.w500)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: kTextSecondary, fontSize: 12)),
        trailing: trailing ?? (onTap != null ? Icon(Icons.chevron_right_rounded, color: kTextSecondary, size: 20) : null),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
    );
  }
}

// ─── SHARED WIDGETS ───────────────────────────────────────────────────────────
// dialogs, cards, buttons that are reused across multiple screens

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  const _Pressable({required this.child, this.onTap, this.pressedScale = 0.97});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) {
        if (widget.onTap != null) _haptic();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _DescribeActSheet extends StatefulWidget {
  final ImagePicker picker;
  final String? initialDescription;
  final Uint8List? initialImage;
  final Future<void> Function(String desc, Uint8List? imageBytes) onVerify;
  const _DescribeActSheet({required this.picker, this.initialDescription, this.initialImage, required this.onVerify});

  @override
  State<_DescribeActSheet> createState() => _DescribeActSheetState();
}

class _DescribeActSheetState extends State<_DescribeActSheet> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialDescription ?? '');
  late Uint8List? _imageBytes = widget.initialImage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = _imageBytes;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(color: kCard, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: kDivider, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Text('Describe a kind act', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextPrimary)),
            const SizedBox(height: 4),
            Text('Tell us what you did and add a photo — AI will verify both', style: TextStyle(fontSize: 13, color: kTextSecondary)),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: kTextPrimary, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'e.g. Helped Mrs. Chen carry her groceries up two flights of stairs',
                hintStyle: TextStyle(color: kTextSecondary),
                filled: true, fillColor: kCardLight,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            Builder(builder: (_) {
              final previewImage = imageBytes;
              if (previewImage != null) {
                return Stack(children: [
                  Container(
                    width: double.infinity, height: 130,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: kDivider)),
                    child: Image.memory(previewImage, fit: BoxFit.cover),
                  ),
                  Positioned(top: 8, right: 8, child: _Pressable(
                    onTap: () => setState(() => _imageBytes = null),
                    child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded, color: Colors.white, size: 16)),
                  )),
                  Positioned(bottom: 8, left: 8, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text('Photo attached', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                    ]),
                  )),
                ]);
              }
              return _Pressable(
                onTap: () async {
                  final picked = await widget.picker.pickImage(source: ImageSource.camera, imageQuality: 70);
                  if (picked == null) return;
                  final bytes = await picked.readAsBytes();
                  if (mounted) setState(() => _imageBytes = bytes);
                },
                pressedScale: 0.97,
                child: Container(
                  width: double.infinity, height: 72,
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kAccent.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.camera_alt_rounded, color: kAccent, size: 20),
                    const SizedBox(width: 8),
                    Text('Add a photo', style: TextStyle(color: kAccent, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(width: 8),
                    Text('(optional)', style: TextStyle(color: kTextSecondary, fontSize: 12)),
                  ]),
                ),
              );
            }),
            const SizedBox(height: 16),
            _KindredButton(
              label: 'Verify with AI',
              onPressed: () async {
                final desc = _controller.text.trim();
                if (desc.isEmpty) return;
                await widget.onVerify(desc, _imageBytes);
              },
            ),
          ]),
        ),
      ),
    );
  }
}

class _StaggerIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  const _StaggerIn({super.key, required this.child, this.delayMs = 0});

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _anim =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
            .animate(_anim),
        child: widget.child,
      ),
    );
  }
}

class _KenBurnsImage extends StatefulWidget {
  final String asset;
  const _KenBurnsImage({required this.asset});
  @override
  State<_KenBurnsImage> createState() => _KenBurnsImageState();
}

class _KenBurnsImageState extends State<_KenBurnsImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat(reverse: true);
  late final Animation<double> _scale = Tween<double>(begin: 1.0, end: 1.14).animate(_c);
  late final Animation<Offset> _drift =
      Tween<Offset>(begin: const Offset(-0.03, 0), end: const Offset(0.03, 0.03)).animate(_c);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Transform.translate(
          offset: Offset(_drift.value.dx * 24, _drift.value.dy * 24),
          child: Transform.scale(
            scale: _scale.value,
            alignment: Alignment.center,
            child: SizedBox.expand(
              child: Image.asset(widget.asset, fit: BoxFit.cover),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  final double size;
  const _PulsingDot({this.color = const Color(0xFF34D399), this.size = 10});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final scale = 0.8 + t * 0.35;
        return Container(
          width: widget.size * scale,
          height: widget.size * scale,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withValues(alpha: 0.15 + t * 0.4),
            border: Border.all(color: widget.color, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.25 + t * 0.4),
                blurRadius: 6 + t * 5,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Medal extends StatelessWidget {
  final int rank;
  final double size;
  const _Medal({required this.rank, required this.size});

  Color get _color {
    switch (rank) {
      case 1: return const Color(0xFFFFD700);
      case 2: return const Color(0xFFC9D4DE);
      case 3: return const Color(0xFFD2966A);
      default: return kTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = switch (rank) {
      1 => Icons.emoji_events,
      2 => Icons.workspace_premium,
      3 => Icons.military_tech,
      _ => Icons.trending_up,
    };
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _color.withValues(alpha: rank <= 3 ? 0.16 : 0.1),
        border: Border.all(color: _color.withValues(alpha: rank <= 3 ? 0.7 : 0.3)),
      ),
      child: Icon(icon, color: _color, size: size * 0.55),
    );
  }
}

class _ConfettiBurst extends StatefulWidget {
  const _ConfettiBurst();
  @override
  State<_ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<_ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().then((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
              animation: _c,
              colors: [const Color(0xFF2DD4BF), const Color(0xFF34D399), const Color(0xFFF59E0B), const Color(0xFFEC4899), const Color(0xFF3B82F6)],
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final Animation<double> animation;
  final List<Color> colors;
  late final List<_ConfettiPiece> _pieces;

  _ConfettiPainter({required this.animation, required this.colors}) {
    final rand = math.Random(7);
    _pieces = List.generate(90, (_) {
      return _ConfettiPiece(
        x: rand.nextDouble(),
        y: -0.1 - rand.nextDouble() * 0.3,
        drift: rand.nextDouble() * 2 * math.pi,
        speed: 0.35 + rand.nextDouble() * 0.55,
        sway: 40 + rand.nextDouble() * 60,
        spin: (rand.nextDouble() - 0.5) * 8,
        size: 5 + rand.nextDouble() * 7,
        color: colors[rand.nextInt(colors.length)],
        round: rand.nextDouble() > 0.5,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    if (t <= 0) return;
    for (final p in _pieces) {
      final progress = (t - p.y.abs() * 0.3).clamp(0.0, 1.0);
      final x = (p.x + math.sin(t * p.speed * 6 + p.drift) * 0.02) * size.width;
      final y = (p.y + p.speed * t) * size.height + (p.speed * t * t) * size.height * 0.5;
      final alpha = (1 - progress).clamp(0.0, 1.0);
      if (alpha <= 0 || y > size.height + 20) continue;
      final paint = Paint()..color = p.color.withValues(alpha: alpha);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.drift + t * p.spin);
      if (p.round) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6),
            const Radius.circular(2),
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => true;
}

class _ConfettiPiece {
  final double x, y, drift, speed, sway, spin, size;
  final Color color;
  final bool round;
  const _ConfettiPiece({required this.x, required this.y, required this.drift, required this.speed, required this.sway, required this.spin, required this.size, required this.color, required this.round});
}

class _KindredButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool destructive;
  final bool compact;
  final bool fullWidth;
  const _KindredButton({
    required this.label,
    this.onPressed,
    this.loading = false,
    this.destructive = false,
    this.compact = false,
    this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = loading || onPressed == null;
    final danger = destructive ? const Color(0xFFEF4444) : kAccent;
    final button = AnimatedOpacity(
      opacity: disabled ? 0.6 : 1.0,
      duration: const Duration(milliseconds: 150),
      child: Container(
        height: compact ? 44 : 54,
        padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 24),
        decoration: BoxDecoration(
          gradient: destructive ? null : kAccentGradient,
          color: destructive ? const Color(0xFFEF4444) : null,
          borderRadius: BorderRadius.circular(compact ? 12 : 16),
          boxShadow: [BoxShadow(color: danger.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: loading
              ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(label, style: TextStyle(color: Colors.white, fontSize: compact ? 14 : 16, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        ),
      ),
    );
    final pressable = _Pressable(onTap: disabled ? null : onPressed, child: button);
    return fullWidth ? SizedBox(width: double.infinity, child: pressable) : pressable;
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _EmptyState({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 88, height: 88, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, color: kAccent, size: 38)),
        const SizedBox(height: 18),
        Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kTextPrimary)),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: kTextSecondary, fontSize: 13)),
        ],
      ]),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon, activeIcon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.selected, this.badge = 0, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? kAccent : kTextSecondary;
    return Expanded(
      child: _Pressable(
        onTap: onTap,
        pressedScale: 0.88,
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44, height: 30,
            decoration: BoxDecoration(color: selected ? kAccent.withValues(alpha: 0.14) : Colors.transparent, borderRadius: BorderRadius.circular(15)),
            child: Center(child: badge > 0
                ? Badge(label: Text('$badge'), child: Icon(selected ? activeIcon : icon, size: 23, color: color))
                : Icon(selected ? activeIcon : icon, size: 23, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: color)),
        ]),
      ),
    );
  }
}

class _KindredDialog extends StatelessWidget {
  final String title, content, actionText;
  final VoidCallback onAction;
  final String? cancelText;
  final VoidCallback? onCancel;
  final bool destructive;
  const _KindredDialog({required this.title, required this.content, required this.actionText, required this.onAction, this.cancelText, this.onCancel, this.destructive = false});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(title, style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w800)),
      content: SingleChildScrollView(child: Text(content, style: TextStyle(color: kTextSecondary, height: 1.5))),
      actions: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!destructive && cancelText != null)
              _KindredButton(label: actionText, onPressed: onAction, destructive: destructive, compact: true, fullWidth: false),
            if (cancelText != null)
              TextButton(onPressed: onCancel, child: Text(cancelText!, style: TextStyle(color: kTextSecondary, fontWeight: FontWeight.w600))),
            if (destructive)
              _KindredButton(label: actionText, onPressed: onAction, destructive: destructive, compact: true, fullWidth: false),
          ]),
        ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final String badge;
  const _BadgeChip({required this.badge});

  String _label(String b) {
    switch (b) {
      case 'first_act': return 'First Act';
      case '10_acts': return '10 Acts';
      case '50_acts': return '50 Acts';
      case 'helper': return 'Helper';
      case 'champion': return 'Champion';
      case 'legend': return 'Legend';
      default: return b;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: kBadge.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: kBadge.withValues(alpha: 0.25))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_badgeIcon(badge), size: 13, color: kBadge),
        const SizedBox(width: 6),
        Text(_label(badge), style: TextStyle(color: kBadge, fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final IconData icon;
  const _StatPill({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: Colors.white, size: 13),
        const SizedBox(width: 5),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _AvatarWithFrame extends StatelessWidget {
  final String? photoUrl;
  final String frameStyle;
  const _AvatarWithFrame({required this.photoUrl, required this.frameStyle});

  @override
  Widget build(BuildContext context) {
    Color? frameColor; List<Color>? gradientColors;
    switch (frameStyle) {
      case 'gold': gradientColors = [Colors.amber, Colors.orange]; break;
      case 'purple': frameColor = const Color(0xFF7B1FA2); break;
      case 'rainbow': gradientColors = [Colors.red, Colors.orange, Colors.yellow, Colors.green, Colors.blue, Colors.purple]; break;
    }
    final avatar = CircleAvatar(radius: 42, backgroundImage: _avatarImage(photoUrl), backgroundColor: kAccent.withValues(alpha: 0.3), child: photoUrl == null ? const Icon(Icons.person, size: 42, color: Colors.white) : null);
    if (frameStyle == 'none') return avatar;
    return Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradientColors != null ? LinearGradient(colors: gradientColors) : null, color: frameColor), padding: const EdgeInsets.all(3), child: avatar);
  }
}

class _ProfileField extends StatelessWidget {
  final String title, lockMessage;
  final bool locked;
  final Widget child;
  const _ProfileField({required this.title, required this.locked, required this.lockMessage, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: kTextPrimary)),
        if (locked) ...[SizedBox(width: 8), Container(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kCardLight, borderRadius: BorderRadius.circular(10)), child: Text(lockMessage, style: TextStyle(fontSize: 10, color: kTextSecondary)))],
      ]),
      const SizedBox(height: 8),
      Opacity(opacity: locked ? 0.4 : 1.0, child: child),
    ]);
  }
}

class _PerkRow extends StatelessWidget {
  final IconData icon;
  final String level, perk;
  final bool unlocked;
  const _PerkRow({required this.icon, required this.level, required this.perk, required this.unlocked});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(children: [
      Icon(icon, size: 16, color: unlocked ? kAccent : kTextSecondary),
      const SizedBox(width: 10),
      Expanded(child: RichText(text: TextSpan(style: TextStyle(fontSize: 13, color: unlocked ? kTextPrimary : kTextSecondary), children: [
        TextSpan(text: '$level — ', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: perk),
      ]))),
      Icon(unlocked ? Icons.check_circle_rounded : Icons.lock_outline_rounded, size: 15, color: unlocked ? kAccent : kTextSecondary),
    ]));
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
      child: Column(children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: kAccent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: kAccent, size: 21)),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kTextPrimary)),
        Text(label, style: TextStyle(color: kTextSecondary, fontSize: 11)),
      ]),
    ));
  }
}

class _HelpCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;
  const _HelpCard({required this.icon, required this.label, required this.tint, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Pressable(onTap: onTap, child: Container(
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18), border: Border.all(color: kDivider), boxShadow: [kSoftShadow]),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(width: 50, height: 50, decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
            child: Center(child: Icon(icon, color: tint, size: 25))),
        const SizedBox(height: 10),
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: kTextPrimary)),
      ]),
    ));
  }
}