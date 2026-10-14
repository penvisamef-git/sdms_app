import '../core/json.dart';
import 'api_client.dart';

/// Standard CRUD endpoints of sdms_api for one resource.
class Resource {
  Resource(this._c, this.route);

  final ApiClient _c;
  final String route;

  Future<Json> list([Map<String, dynamic>? params]) => _c.get('/$route', params: params);
  Future<Json> all([Map<String, dynamic>? params]) => _c.get('/$route-all', params: params);
  Future<Json> get(String id) => _c.get('/$route/$id');
  Future<Json> create(Object data) => _c.post('/$route', body: data);
  Future<Json> update(String id, Object data) => _c.put('/$route/$id', body: data);
  Future<Json> remove(String id) => _c.delete('/$route/$id');
  Future<Json> restore(String id) => _c.put('/$route/restore/$id');
}

/// Every endpoint the app uses (mirrors sdms/src/api/api.service.js).
class Api {
  Api(this.client)
      : users = Resource(client, 'users'),
        documentTypes = Resource(client, 'master-data/type-of-document'),
        frameworks = Resource(client, 'master-data/framework'),
        statusOfProcess = Resource(client, 'master-data/status-of-process'),
        units = Resource(client, 'master-data/unit'),
        generalDirectorates = Resource(client, 'master-data/general-directorate'),
        departments = Resource(client, 'master-data/department'),
        offices = Resource(client, 'master-data/office'),
        documents = Resource(client, 'document');

  final ApiClient client;
  final Resource users;
  final Resource documentTypes;
  final Resource frameworks;
  final Resource statusOfProcess;
  final Resource units;
  final Resource generalDirectorates;
  final Resource departments;
  final Resource offices;
  final Resource documents;

  // ---------------- Auth ----------------
  /// Mobile login. The account must have "can_login_in_app" switched on.
  Future<Json> login(String email, String password) =>
      client.post('/auth/login/app', body: {'email': email, 'password': password}, skipAuth: true);

  /// Ends this device's session on the server (older servers do not have it: ignore errors).
  Future<void> logout() async {
    try {
      await client.post('/auth/logout', body: <String, dynamic>{});
    } catch (_) {}
  }

  // ---------------- User ----------------
  Future<Json> profile() => client.get('/users-app/profile');
  Future<Json> allUsers() => users.all();

  /// My own password: needs the old one.
  Future<Json> changePassword(String oldPassword, String newPassword) => client.put(
        '/users/change-password',
        body: {'old_password': oldPassword, 'new_password': newPassword},
      );

  Future<Json> resetPassword(String id, String password) =>
      client.put('/users/reset-password/$id', body: {'password': password});

  // ---------------- Home ----------------
  Future<Json> homeSummary({required String month, required String dateField}) =>
      client.get('/home/summary', params: {'month': month, 'date_field': dateField});

  Future<Json> homeNewDocuments(Map<String, dynamic> params) =>
      client.get('/home/new-documents', params: params);

  Future<Json> myOffice() => client.get('/home/my-office');

  // ---------------- Org tree ----------------
  Future<Json> unitTree({Map<String, dynamic>? params}) =>
      client.get('/master-data/unit-tree', params: params);

  // ---------------- Documents ----------------
  Future<Json> documentList(Map<String, dynamic> params) => documents.list(params);
  Future<Json> document(String id) => documents.get(id);
  Future<Json> documentTracking(String id) => client.get('/document/$id/tracking');

  Future<Json> documentCreate(Json body) => documents.create(body);
  Future<Json> documentUpdate(String id, Json body) => documents.update(id, body);

  /// Set / add receivers: `{send_to_office_id: [...], send_to_user_id: [...], note}`
  Future<Json> documentSend(String id, Json body) => client.post('/document/$id/send', body: body);

  /// Replace one saved file with a signed copy (already uploaded to Cloudinary):
  /// `{public_id: <file being replaced>, file: <uploaded file info>}`
  Future<Json> documentReplaceFile(String id, Json body) => client.put('/document/$id/file', body: body);

  // ---------------- Transfers ----------------
  Future<Json> inbox(Map<String, dynamic> params) =>
      client.get('/document-transfer/inbox', params: params);
  Future<Json> sent(Map<String, dynamic> params) =>
      client.get('/document-transfer/sent', params: params);
  Future<Json> receive(String tid) => client.put('/document-transfer/$tid/receive', body: <String, dynamic>{});
  Future<Json> forward(String tid, Json data) => client.post('/document-transfer/$tid/forward', body: data);
  Future<Json> returnBack(String tid, Json data) => client.post('/document-transfer/$tid/return', body: data);
  Future<Json> done(String tid, Json data) => client.put('/document-transfer/$tid/done', body: data);

  // ---------------- Upload ----------------
  /// Signature to upload a big file straight to Cloudinary.
  Future<Json> uploadSignature(String folder) =>
      client.get('/upload/signature', params: {'folder': folder});
}
