import 'package:flutter/material.dart';

/// A page route that uses a fade + slight slide transition instead of the
/// default Material page transition (which includes scale).
///
/// On forward navigation: fade in + slight slide from right
/// On back navigation: simple fade out only (no slide)
class FadeSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget child;

  FadeSlidePageRoute({
    required this.child,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Check if we're going forward or backward
            final isForward = animation.status == AnimationStatus.forward ||
                              animation.status == AnimationStatus.completed;

            // Fade transition - always applies
            final fadeAnimation = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOut,
              reverseCurve: Curves.easeOut, // Smooth fade out on back
            );

            // Only apply slide on forward navigation
            if (isForward) {
              // Slight slide from right (just 5% of width)
              final slideAnimation = Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ));

              return FadeTransition(
                opacity: fadeAnimation,
                child: SlideTransition(
                  position: slideAnimation,
                  child: child,
                ),
              );
            } else {
              // On back: just fade, no slide
              return FadeTransition(
                opacity: fadeAnimation,
                child: child,
              );
            }
          },
        );
}
