// Flutter's browser test runner does not execute the app's generated web
// registrant. Register the installed FlutterFire implementations only for this
// opt-in integration test; no extra production dependencies are required.
// ignore_for_file: depend_on_referenced_packages
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

void registerCommunicationPlugins() {
  FirebaseCoreWeb.registerWith(webPluginRegistrar);
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
}
