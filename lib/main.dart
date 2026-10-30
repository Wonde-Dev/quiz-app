import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://vsknxaxrwvpdevocnojn.supabase.co',
    publishableKey: 'sb_publishable_IQKJm6Hy0H8JnUeqjxD1iA_yDpIt6b2',
  );

  runApp(const ProviderScope(child: MyApp()));
}
