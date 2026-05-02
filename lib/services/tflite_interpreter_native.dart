import 'package:tflite_flutter/tflite_flutter.dart' as tflite;

class Interpreter {
  final tflite.Interpreter _delegate;

  Interpreter._(this._delegate);

  static Future<Interpreter> fromAsset(String assetName) async {
    final interpreter = await tflite.Interpreter.fromAsset(assetName);
    return Interpreter._(interpreter);
  }

  void run(Object input, Object output) {
    _delegate.run(input, output);
  }

  void close() {
    _delegate.close();
  }
}
