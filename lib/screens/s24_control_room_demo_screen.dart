import 'package:flutter/material.dart';

import 's13_discover_screen.dart';

/// Compatibility route for older demo links. The product now has one home.
class ControlRoomDemoScreen extends StatelessWidget {
  const ControlRoomDemoScreen({super.key});

  @override
  Widget build(BuildContext context) => const DiscoverScreen();
}
