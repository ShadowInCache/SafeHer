import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:firebase_messaging/firebase_messaging.dart'; // Disabled for web compatibility
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  // static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance; // Disabled for web compatibility

  static Future<void> initialize() async {
    // Request permissions
    await _requestPermissions();

    // Initialize local notifications
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Setup Firebase Messaging
    await _setupFirebaseMessaging();
  }

  static Future<void> _requestPermissions() async {
    await Permission.notification.request();

    // Firebase messaging permissions disabled for web compatibility
    // NotificationSettings settings = await _firebaseMessaging.requestPermission(
    //   alert: true,
    //   badge: true,
    //   sound: true,
    //   criticalAlert: true,
    // );

    debugPrint('Notification permission requested (Firebase disabled for web)');
  }

  static Future<void> _setupFirebaseMessaging() async {
    // Firebase messaging disabled for web compatibility
    // Get FCM token
    // String? token = await _firebaseMessaging.getToken();
    // dev.log('FCM Token: $token');

    // Handle foreground messages
    // FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    //   _showLocalNotification(
    //     title: message.notification?.title ?? 'SafeHer Alert',
    //     body: message.notification?.body ?? '',
    //     payload: message.data.toString(),
    //   );
    // });

    // Handle background messages
    // FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

    debugPrint('Firebase messaging setup disabled for web compatibility');
  }

  // static Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  //   dev.log('Background message: ${message.messageId}');
  // }

  static Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
    bool isEmergency = false,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'safeher_alerts',
      'SafeHer Alerts',
      channelDescription: 'Critical safety alerts from SafeHer',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  static Future<void> showEmergencyAlert({
    required String message,
    required String location,
  }) async {
    await _showLocalNotification(
      title: '🚨 EMERGENCY ALERT',
      body: message,
      payload: location,
      isEmergency: true,
    );
  }

  static Future<void> showThreatDetected({
    required String threatType,
    required double confidence,
  }) async {
    await _showLocalNotification(
      title: '⚠️ Threat Detected',
      body:
          '$threatType detected (${(confidence * 100).toStringAsFixed(0)}% confidence)',
    );
  }

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('Notification tapped: ${response.payload}');
    // Navigate to appropriate screen based on payload
  }
}
