import 'dart:js_interop';
import 'package:flutter/material.dart';

@JS('aidTrackCaptcha.mount')
external void _mount(JSObject element, JSString siteKey, JSFunction callback);
@JS('aidTrackCaptcha.unmount')
external void _unmount(JSObject element);

class RecaptchaCheckbox extends StatefulWidget {
  final ValueChanged<String?> onChanged;
  const RecaptchaCheckbox({super.key, required this.onChanged});
  @override
  State<RecaptchaCheckbox> createState() => _RecaptchaCheckboxState();
}

class _RecaptchaCheckboxState extends State<RecaptchaCheckbox> {
  static const _siteKey = String.fromEnvironment(
    'RECAPTCHA_SITE_KEY',
    defaultValue: '6LfZ5BsuAAAAAGLjPMs_AbuIsUopj7Ujg-txftvW',
  );
  JSObject? _element;
  String? _error;
  bool _ready = false;
  int _generation = 0;

  void _created(Object element) {
    final domElement = element as JSObject;
    _element = domElement;
    final generation = _generation;
    _mount(domElement, _siteKey.toJS, ((JSString token, JSString state) {
      if (!mounted || generation != _generation) return;
      final status = state.toDart;
      setState(() {
        _ready = status != 'loading';
        _error = status == 'error'
            ? 'reCAPTCHA failed. Check the message inside the Google widget.' : null;
      });
      final value = token.toDart;
      widget.onChanged(value.isEmpty ? null : value);
    }).toJS);
  }

  void _retry() {
    if (_element != null) _unmount(_element!);
    _element = null;
    widget.onChanged(null);
    setState(() { _generation++; _ready = false; _error = null; });
  }

  @override
  void dispose() {
    if (_element != null) _unmount(_element!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_siteKey.isEmpty) {
      return const Text('reCAPTCHA site key is missing. Restart with RECAPTCHA_SITE_KEY.',
        textAlign: TextAlign.center);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Center(
        child: SizedBox(
          width: 304,
          height: 78,
          child: HtmlElementView.fromTagName(
            key: ValueKey(_generation),
            tagName: 'div',
            onElementCreated: _created,
          ),
        ),
      ),
      if (!_ready) const Text('Loading security verification...'),
      if (_error != null) ...[
        Text(_error!, textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red)),
        TextButton(onPressed: _retry, child: const Text('Retry reCAPTCHA')),
      ],
    ]);
  }
}
