import 'package:flutter/material.dart';

/// A page route optimized for hero animations.
///
/// On forward navigation: fade in + slight slide from right
/// On back navigation: quick fade out + slide down
class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  FadeSlidePageRoute({
    required this.child,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 200), // Quick back animation
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Fade transition - uses optimized cubic curves for smoother hero animations
            final fadeAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Check direction for slide
            final isReverse = animation.status == AnimationStatus.reverse;

            if (isReverse) {
              // Back navigation: slide DOWN with easeInCubic for smooth deceleration
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0, 0.08), // Slide down 8%
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeInCubic,
              ));

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            } else {
              // Forward navigation: slide from RIGHT with easeOutCubic for natural motion
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.05, 0), // Slide from right 5%
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ));

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            }
          },
        );
}
