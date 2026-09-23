import 'package:flutter/material.dart';
import '../features/matching/domain/models.dart';

class CommunicationScope extends InheritedWidget {
  const CommunicationScope({
    super.key,
    required super.child,
    required this.openMessages,
    required this.openAssistant,
  });
  final void Function(BuildContext, Contractor?) openMessages;
  final void Function(BuildContext) openAssistant;
  static CommunicationScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommunicationScope>();
  @override
  bool updateShouldNotify(CommunicationScope oldWidget) => true;
}
