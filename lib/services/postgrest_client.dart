import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/postgrest_config.dart';

const Duration _httpTimeout = Duration(seconds: 25);

class PostgrestException implements Exception {
  PostgrestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'PostgrestException($statusCode): $message';
}

/// Lightweight PostgREST HTTP client (replaces supabase_flutter for data access).
class PostgrestClient {
  PostgrestClient._();

  static final PostgrestClient instance = PostgrestClient._();

  PostgrestFilterBuilder from(String table) => PostgrestFilterBuilder(table);

  Future<dynamic> rpc(
    String functionName, {
    Map<String, dynamic>? params,
  }) async {
    final uri = Uri.parse('${PostgrestConfig.restBaseUrl}/rpc/$functionName');
    final response = await http.post(
      uri,
      headers: _headers(),
      body: jsonEncode(params ?? {}),
    ).timeout(_httpTimeout);
    return PostgrestFilterBuilder._decodeResponse(response, maybeSingle: false);
  }

  static Map<String, String> _headers({bool maybeSingle = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (maybeSingle) 'Accept': 'application/vnd.pgrst.object+json',
    };
    final key = PostgrestConfig.anonKey;
    if (PostgrestConfig.jwtAuthEnabled) {
      headers['apikey'] = key;
      headers['Authorization'] = 'Bearer $key';
    }
    return headers;
  }
}

enum _PostgrestMethod { get, post, patch, delete }

class PostgrestFilterBuilder implements Future<dynamic> {
  PostgrestFilterBuilder(this._table);

  final String _table;
  _PostgrestMethod _method = _PostgrestMethod.get;
  String _select = '*';
  bool _selectSet = false;
  final List<MapEntry<String, String>> _filters = [];
  final List<String> _orders = [];
  int? _limit;
  Map<String, dynamic>? _body;
  bool _maybeSingle = false;
  bool _returnRepresentation = false;

  PostgrestFilterBuilder select([String columns = '*']) {
    _selectSet = true;
    _select = columns.trim().isEmpty ? '*' : columns.trim();
    _returnRepresentation = _method != _PostgrestMethod.get;
    return this;
  }

  PostgrestFilterBuilder insert(Map<String, dynamic> values) {
    _method = _PostgrestMethod.post;
    _body = values;
    return this;
  }

  PostgrestFilterBuilder update(Map<String, dynamic> values) {
    _method = _PostgrestMethod.patch;
    _body = values;
    return this;
  }

  PostgrestFilterBuilder delete() {
    _method = _PostgrestMethod.delete;
    return this;
  }

  PostgrestFilterBuilder eq(String column, Object? value) {
    _filters.add(MapEntry(column, 'eq.${_encodeFilterValue(value)}'));
    return this;
  }

  PostgrestFilterBuilder inFilter(String column, List<Object?> values) {
    final encoded = values.map(_encodeFilterValue).join(',');
    _filters.add(MapEntry(column, 'in.($encoded)'));
    return this;
  }

  PostgrestFilterBuilder ilike(String column, String pattern) {
    _filters.add(MapEntry(column, 'ilike.${_encodeFilterValue(pattern)}'));
    return this;
  }

  PostgrestFilterBuilder gte(String column, Object value) {
    _filters.add(MapEntry(column, 'gte.${_encodeFilterValue(value)}'));
    return this;
  }

  PostgrestFilterBuilder lte(String column, Object value) {
    _filters.add(MapEntry(column, 'lte.${_encodeFilterValue(value)}'));
    return this;
  }

  PostgrestFilterBuilder order(String column, {bool ascending = true}) {
    _orders.add('$column.${ascending ? 'asc' : 'desc'}');
    return this;
  }

  PostgrestFilterBuilder limit(int count) {
    _limit = count;
    return this;
  }

  Future<Map<String, dynamic>?> maybeSingle() async {
    _maybeSingle = true;
    _limit = 1;
    _ensureOrderForLimit();
    final result = await _execute();
    if (result == null) return null;
    if (result is List) {
      if (result.isEmpty) return null;
      return Map<String, dynamic>.from(result.first as Map);
    }
    if (result is Map) return Map<String, dynamic>.from(result);
    return null;
  }

  Future<dynamic> _execute() async {
    if (!PostgrestConfig.isConfigured) {
      throw PostgrestException('PostgREST not configured');
    }

    final query = <String, String>{};
    if (_method == _PostgrestMethod.get ||
        _method == _PostgrestMethod.post ||
        _method == _PostgrestMethod.patch) {
      if (_selectSet || _method == _PostgrestMethod.get) {
        query['select'] = _select;
      }
    }
    for (final filter in _filters) {
      query[filter.key] = filter.value;
    }
    if (_orders.isNotEmpty) {
      query['order'] = _orders.join(',');
    }
    if (_limit != null) {
      if (_orders.isEmpty) _ensureOrderForLimit();
      query['limit'] = '${_limit!}';
    }

    final uri = Uri.parse(
      '${PostgrestConfig.restBaseUrl}/$_table',
    ).replace(queryParameters: query.isEmpty ? null : query);

    final headers = PostgrestClient._headers(maybeSingle: _maybeSingle);
    if (_returnRepresentation &&
        (_method == _PostgrestMethod.post || _method == _PostgrestMethod.patch)) {
      headers['Prefer'] = 'return=representation';
    }

    late http.Response response;
    switch (_method) {
      case _PostgrestMethod.get:
        response = await http.get(uri, headers: headers).timeout(_httpTimeout);
      case _PostgrestMethod.post:
        response = await http
            .post(
              uri,
              headers: headers,
              body: jsonEncode(_body ?? {}),
            )
            .timeout(_httpTimeout);
      case _PostgrestMethod.patch:
        response = await http
            .patch(
              uri,
              headers: headers,
              body: jsonEncode(_body ?? {}),
            )
            .timeout(_httpTimeout);
      case _PostgrestMethod.delete:
        response = await http.delete(uri, headers: headers).timeout(_httpTimeout);
    }

    return _decodeResponse(response, maybeSingle: _maybeSingle);
  }

  /// PostgREST requires an explicit `order` on unique column(s) when `limit` is set.
  void _ensureOrderForLimit() {
    if (_orders.isNotEmpty) return;

    final eqColumns = _filters
        .where((f) => f.value.startsWith('eq.'))
        .map((f) => f.key)
        .toList();

    if (eqColumns.contains('id')) {
      _orders.add('id.asc');
      return;
    }
    if (eqColumns.length == 1) {
      _orders.add('${eqColumns.first}.asc');
      return;
    }
    final select = _select.trim();
    if (select.isNotEmpty && select != '*' && !select.contains(',')) {
      _orders.add('$select.asc');
      return;
    }
    _orders.add('id.asc');
  }

  static dynamic _decodeResponse(
    http.Response response, {
    required bool maybeSingle,
  }) {
    if (response.statusCode >= 400) {
      throw PostgrestException(response.body, statusCode: response.statusCode);
    }
    if (response.body.isEmpty) return maybeSingle ? null : <dynamic>[];
    final decoded = jsonDecode(response.body);
    if (maybeSingle && decoded is List && decoded.isEmpty) return null;
    return decoded;
  }

  static String _encodeFilterValue(Object? value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    final s = value.toString();
    // PostgREST accepts unquoted values with @ (emails). Quoted emails break
    // eq/ilike filters on api.hku.hk-style gateways (match includes literal ").
    if (RegExp(r'^[A-Za-z0-9._@-]+$').hasMatch(s)) return s;
    return '"${s.replaceAll('"', '\\"')}"';
  }

  @override
  Future<R> then<R>(
    FutureOr<R> Function(dynamic value) onValue, {
    Function? onError,
  }) {
    return _execute().then(onValue, onError: onError);
  }

  @override
  Future<dynamic> catchError(
    Function onError, {
    bool Function(Object error)? test,
  }) {
    return _execute().catchError(onError, test: test);
  }

  @override
  Future<dynamic> whenComplete(FutureOr<void> Function() action) {
    return _execute().whenComplete(action);
  }

  @override
  Future<dynamic> timeout(
    Duration timeLimit, {
    FutureOr<dynamic> Function()? onTimeout,
  }) {
    return _execute().timeout(timeLimit, onTimeout: onTimeout);
  }

  @override
  Stream<dynamic> asStream() => _execute().asStream();
}
