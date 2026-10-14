import '../core/json.dart';
import 'api_client.dart';

/// Standard CRUD endpoints of sdms_api for one resource.
class Resource {
  Resource(this._c, this.route);

  final ApiClient _c;
  final String route;

  Future<Json> list([Map<String, dynamic>? params]) => _c.get('/$route', params: params);
  Json? peekList([Map<String, dynamic>? params]) => _c.peek('/$route', params: params);
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
  /// Mobile login. Every active web account can sign in.
  Future<Json> login(String email, String password) =>
      client.post('/auth/login/app', body: {'email': email, 'password': password}, skipAuth: true);

  /// Ends this device's session on the server (older servers do not have it: ignore errors).
  Future<void> logout() async {
    try {
      await client.post('/auth/logout', body: <String, dynamic>{});
    } catch (_) {}
  }

  // ---------------- User ----------------
  /// Wakes the server (and its database connection) so the first real call is not a cold start.
  /// Never throws; no sign-in needed.
  Future<void> warmUp() async {
    try {
      await client.get('/health');
    } catch (_) {}
  }

  // ---------------- Push notifications ----------------
  Future<void> pushRegister(String token, String platform) async {
    await client.post('/push/register', body: {'token': token, 'platform': platform});
  }

  Future<void> pushUnregister(String token) async {
    await client.post('/push/unregister', body: {'token': token});
  }

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

  // Last saved answers (any age) to paint a screen at once; null when there is none yet.
  Json? peekHomeSummary({required String month, required String dateField}) =>
      client.peek('/home/summary', params: {'month': month, 'date_field': dateField});
  Json? peekHomeNewDocuments(Map<String, dynamic> params) => client.peek('/home/new-documents', params: params);
  Json? peekInbox(Map<String, dynamic> params) => client.peek('/document-transfer/inbox', params: params);
  Json? peekDocumentList(Map<String, dynamic> params) => client.peek('/document', params: params);
  Json? peekDocument(String id) => client.peek('/document/$id');
  Json? peekDocumentTracking(String id) => client.peek('/document/$id/tracking');
  Json? peekOrgTree(String key) => client.peek('/master-data/$key-tree', params: {'include_users': true});
  Json? peekMyOffice() => client.peek('/home/my-office');

  // ---------------- Org tree ----------------
  /// Organisation tree with the users of every office (key: unit | general-directorate | department).
  Future<Json> orgTree(String key) =>
      client.get('/master-data/$key-tree', params: {'include_users': true});

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
