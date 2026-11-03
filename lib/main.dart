import 'package:flutter/material.dart';

import 'src/controller.dart';
import 'src/ui/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FlutterLiveApp(controller: InterpreterController()));
}
