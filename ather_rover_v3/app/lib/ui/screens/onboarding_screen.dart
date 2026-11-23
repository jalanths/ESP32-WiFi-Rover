import 'package:flutter/material.dart';

import '../theme.dart';

class _Page {
  const _Page(this.icon, this.title, this.body);
  final IconData icon;
  final String title;
  final String body;
}

const _pages = [
  _Page(Icons.wifi_rounded, 'Join the rover Wi-Fi',
      'Switch the rover on, then join the ATHER-ROVER network on this phone '
          '(password rover1234). If Android says it has no internet, choose to '
          'stay connected and turn mobile data off.'),
  _Page(Icons.gamepad_rounded, 'Drive',
      'Drag the joystick to drive and let go to stop. Pick Eco, Ride or Sport '
          'for top speed, or switch to Tilt and steer by tilting the phone.'),
  _Page(Icons.pan_tool_rounded, 'Safety first',
      'STOP always works. If the app loses the link the rover stops by itself '
          'within 0.4 s, and it cuts the motors at 3.6 V to protect the battery.'),
];

/// Three-page first-run guide.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _pages.length - 1) {
      widget.onDone();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final last = _index == _pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: widget.onDone, child: const Text('Skip')),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final p = _pages[i];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(Tokens.s6),
                    child: Column(
                      children: [
                        const SizedBox(height: Tokens.s5),
                        Container(
                          padding: const EdgeInsets.all(Tokens.s6),
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(p.icon, size: 72, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: Tokens.s6),
                        Semantics(
                          header: true,
                          child: Text(p.title,
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: Tokens.s3),
                        Text(p.body,
                            textAlign: TextAlign.center,
                            style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Semantics(
              label: 'Page ${_index + 1} of ${_pages.length}',
              excludeSemantics: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _index ? scheme.primary : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Tokens.s5),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _next,
                  child: Text(last ? 'Start driving' : 'Next'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
