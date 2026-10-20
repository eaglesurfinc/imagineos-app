import 'package:flutter/widgets.dart';

/// App feature controls. Server authorization independently protects cloud data.
/// These controls cannot prevent screenshots or copies of already received data.
class CreationPermissions extends InheritedWidget {
  const CreationPermissions(
      {super.key,
      required super.child,
      this.manageProfiles = true,
      this.deleteSavedWork = true,
      this.export = true,
      this.authorizeExport});
  final bool manageProfiles, deleteSavedWork, export;
  final Future<void> Function()? authorizeExport;
  static CreationPermissions of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CreationPermissions>() ??
      const CreationPermissions(child: SizedBox.shrink());
  Future<void> requireExport() async {
    if (!export)
      throw StateError(
          'Ask your parent to allow saving copies to this device.');
    await authorizeExport?.call();
  }

  @override
  bool updateShouldNotify(CreationPermissions oldWidget) =>
      manageProfiles != oldWidget.manageProfiles ||
      deleteSavedWork != oldWidget.deleteSavedWork ||
      export != oldWidget.export ||
      authorizeExport != oldWidget.authorizeExport;
}
