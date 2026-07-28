import 'package:flutter/widgets.dart';

PageRoute<T> hardCutRoute<T>(
  WidgetBuilder builder, {
  RouteSettings? settings,
}) => PageRouteBuilder<T>(
  settings: settings,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  pageBuilder: (context, animation, secondaryAnimation) => builder(context),
);

PageRoute<T> hardCutPageRoute<T>(
  RouteSettings settings,
  WidgetBuilder builder,
) => hardCutRoute<T>(builder, settings: settings);
