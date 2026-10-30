import 'package:flutter/material.dart';
import 'src/model/game_config.dart';
import 'src/ui/game_screen.dart';

export 'src/controller/zero_game_controller.dart';
export 'src/model/game_config.dart';
export 'src/model/soa_entities.dart';
export 'src/rendering/flutter_game_stage.dart';
export 'src/rendering/z_game_stage.dart';
export 'src/ui/battle_overlay_hud.dart';
export 'src/ui/engine_compare_hud.dart';
export 'src/ui/game_screen.dart';

void main() {
  runApp(const ZeroOverdriveGameApp());
}

/// Root application widget for ZERO OVERDRIVE (`apps/games`).
class ZeroOverdriveGameApp extends StatelessWidget {
  const ZeroOverdriveGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZERO OVERDRIVE — D-Zero Showcase Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: ZeroGamePalette.bgVoid,
        colorScheme: const ColorScheme.dark(
          primary: ZeroGamePalette.neonGreen,
          secondary: ZeroGamePalette.neonCyan,
          surface: ZeroGamePalette.panelDark,
        ),
      ),
      home: const ZeroOverdriveScreen(),
    );
  }
}
