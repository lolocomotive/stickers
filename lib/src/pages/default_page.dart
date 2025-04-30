/*
 * This file is part of the Klient (https://github.com/lolocomotive/klient)
 *
 * Copyright (C) 2022 lolocomotive
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:stickers/generated/intl/app_localizations.dart';

/// All screens have some thing in common.
/// Having a widget with all the common parts makes it easier to modify later.
class DefaultActivity extends StatelessWidget {
  const DefaultActivity(
      {super.key, required this.child, this.appBar, this.fab, this.resizeToAvoidBottomInset});

  final Widget child;
  final bool? resizeToAvoidBottomInset;
  final PreferredSizeWidget? appBar;
  final FloatingActionButton? fab;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1600),
        child: Scaffold(
          floatingActionButton: fab,
          appBar: appBar,
          body: child,
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        ),
      ),
    );
  }
}

class DefaultSliverActivity extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? titleBackground;
  final Color? titleColor;
  final FloatingActionButton? fab;

  const DefaultSliverActivity({
    required this.child,
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.titleBackground,
    this.titleColor,
    this.titleWidget,
    this.fab,
  });

  @override
  Widget build(BuildContext context) {
    Widget t = titleWidget ??
        Text(
          title ?? AppLocalizations.of(context)!.noTitle,
          style: TextStyle(color: titleColor),
        );
    return DefaultActivity(
      fab: fab,
      child: NestedScrollView(
        floatHeaderSlivers: true,
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              backgroundColor: titleBackground,
              leading: leading,
              title: t,
              floating: true,
              forceElevated: innerBoxIsScrolled,
              actions: actions,
            )
          ];
        },
        body: Scrollbar(child: child),
      ),
    );
  }
}
