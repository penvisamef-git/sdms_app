import 'json.dart';

/// The fixed roles saved in the user's `role` field (must match sdms_api/src/util/user_roles.js).
class Role {
  static const String superAdmin = 'អ្នកគ្រប់គ្រងប្រព័ន្ធមេ';
  static const String docIn = 'អ្នកគ្រប់គ្រងឯកសារចូល';
  static const String docOut = 'អ្នកគ្រប់គ្រងឯកសារចេញ';
  static const String docBoth = 'អ្នកគ្រប់គ្រងឯកសារចេញ/ចូល';

  /// Big Boss (only one): inbox + history + my account. Receives, signs, comments and returns documents.
  static const String boss = 'ថ្នាក់ដឹកនាំ';

  static const List<String> all = [superAdmin, docIn, docOut, docBoth, boss];
}

/// What a screen needs (same rules as the web: sdms/src/page/util/permission.js).
enum Access { all, staff, docIn, docOut, superAdmin, boss }

String roleOf(Json? user) {
  if (user == null) return '';
  if (user['is_super_admin'] == true) return Role.superAdmin;
  final r = user['role'];
  return r is String ? r : s(asObj(r)['name']);
}

bool isBoss(Json? user) => roleOf(user) == Role.boss;

/// Where a signed-in user starts (the Big Boss has no dashboard).
String homePathFor(Json? user) => isBoss(user) ? '/inbox' : '/home';

bool canAccess(Json? user, Access access) {
  final role = roleOf(user);
  // the Big Boss sees his own two screens and his account, nothing else
  if (role == Role.boss) return access == Access.boss || access == Access.all;
  if (access == Access.boss) return false;
  if (role == Role.superAdmin) return true;
  switch (access) {
    case Access.all:
    case Access.staff:
      return true;
    case Access.boss:
      return false;
    case Access.docIn:
      return role == Role.docIn || role == Role.docBoth;
    case Access.docOut:
      return role == Role.docOut || role == Role.docBoth;
    case Access.superAdmin:
      return false;
  }
}

/// Which document list this user may open: the wanted one ("in" | "out"), else the other, else null.
String? docBoxFor(Json? user, String wanted) {
  final ok = {'in': canAccess(user, Access.docIn), 'out': canAccess(user, Access.docOut)};
  if (ok[wanted] == true) return wanted;
  final other = wanted == 'out' ? 'in' : 'out';
  return ok[other] == true ? other : null;
}
