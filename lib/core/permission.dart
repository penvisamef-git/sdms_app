import 'json.dart';

/// The fixed roles saved in the user's `role` field (must match sdms_api/src/util/user_roles.js).
class Role {
  static const String superAdmin = 'អ្នកគ្រប់គ្រងប្រព័ន្ធមេ';
  static const String docIn = 'អ្នកគ្រប់គ្រងឯកសារចូល';
  static const String docOut = 'អ្នកគ្រប់គ្រងឯកសារចេញ';
  static const String docBoth = 'អ្នកគ្រប់គ្រងឯកសារចេញ/ចូល';

  static const List<String> all = [superAdmin, docIn, docOut, docBoth];
}

/// What a screen needs (same rules as the web: sdms/src/page/util/permission.js).
enum Access { all, docIn, docOut, superAdmin }

String roleOf(Json? user) {
  if (user == null) return '';
  if (user['is_super_admin'] == true) return Role.superAdmin;
  final r = user['role'];
  return r is String ? r : s(asObj(r)['name']);
}

bool canAccess(Json? user, Access access) {
  final role = roleOf(user);
  if (role == Role.superAdmin) return true;
  switch (access) {
    case Access.all:
      return true;
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
