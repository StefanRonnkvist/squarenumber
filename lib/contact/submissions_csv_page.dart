import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Scaffold wrapper for displaying submissions fetched from a CSV endpoint.
class SubmissionsCsvPage extends StatefulWidget {
  const SubmissionsCsvPage({
    super.key,
    this.csvUrl = 'https://stefanronnkvist.com/submissions.csv',
    this.showAppBar = true,
  });

  final String csvUrl;
  final bool showAppBar;

  @override
  State<SubmissionsCsvPage> createState() => _SubmissionsCsvPageState();
}

class _SubmissionsCsvPageState extends State<SubmissionsCsvPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(title: const Text('Submissions CSV'))
          : null,
      body: SubmissionsCsvCardsView(csvUrl: widget.csvUrl),
    );
  }
}

class SubmissionsCsvCardsView extends StatefulWidget {
  const SubmissionsCsvCardsView({
    super.key,
    this.csvUrl = 'https://stefanronnkvist.com/submissions.csv',
  });

  final String csvUrl;

  @override
  State<SubmissionsCsvCardsView> createState() =>
      _SubmissionsCsvCardsViewState();
}

class _SubmissionsCsvCardsViewState extends State<SubmissionsCsvCardsView> {
  static const double _titleFontSize = 15;
  static const double _fieldFontSize = 13.5;
  static const int _visibleFieldStartIndex = 2;
  static const int _appColumnIndex = 2;

  static const List<String> _fixedHeaders = <String>[
    'Name',
    'eMail',
    'App',
    'Version',
    'Series',
    'Content',
    'Date Time',
  ];

  late Future<_CsvTableData> _tableFuture;

  @override
  void initState() {
    super.initState();
    _tableFuture = _loadCsv();
  }

  Future<_CsvTableData> _loadCsv() async {
    // Fetch, normalize, and filter remotely hosted rows to this package only.
    final Uri uri = Uri.parse(widget.csvUrl);
    final http.Response response = await http
        .get(uri)
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server returned status ${response.statusCode}.');
    }

    final String csvText = utf8.decode(response.bodyBytes);
    final List<List<String>> rows = _parseCsv(csvText);

    if (rows.isEmpty) {
      return const _CsvTableData(headers: <String>[], rows: <List<String>>[]);
    }

    final int maxColumnCount = _fixedHeaders.length;
    final List<String> headers = List<String>.from(_fixedHeaders);

    // Pad short rows so fixed-column indexing is safe for legacy submissions.
    final List<List<String>> normalizedRows = rows
        .map(
          (List<String> row) => <String>[
            ...row,
            ...List<String>.filled(maxColumnCount - row.length, ''),
          ],
        )
        .toList(growable: false);

    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final String currentApp = packageInfo.packageName.trim().toLowerCase();

    final List<List<String>> filteredRows = normalizedRows
        .where((List<String> row) {
          final String appValue = row[_appColumnIndex].trim().toLowerCase();
          return appValue == currentApp;
        })
        .toList(growable: false);

    return _CsvTableData(headers: headers, rows: filteredRows);
  }

  List<List<String>> _parseCsv(String input) {
    // Parse RFC 4180-style quoted fields, escaped quotes, and both common line
    // endings without splitting commas or newlines embedded inside quotes.
    final List<List<String>> rows = <List<String>>[];
    final List<String> currentRow = <String>[];
    final StringBuffer currentField = StringBuffer();
    bool inQuotes = false;

    int i = 0;
    while (i < input.length) {
      final String char = input[i];

      if (char == '"') {
        if (inQuotes && i + 1 < input.length && input[i + 1] == '"') {
          currentField.write('"');
          i += 2;
          continue;
        }

        inQuotes = !inQuotes;
        i += 1;
        continue;
      }

      if (!inQuotes && char == ',') {
        currentRow.add(currentField.toString());
        currentField.clear();
        i += 1;
        continue;
      }

      if (!inQuotes && (char == '\n' || char == '\r')) {
        currentRow.add(currentField.toString());
        currentField.clear();

        if (currentRow.any((String value) => value.isNotEmpty)) {
          rows.add(List<String>.from(currentRow));
        }
        currentRow.clear();

        if (char == '\r' && i + 1 < input.length && input[i + 1] == '\n') {
          i += 2;
        } else {
          i += 1;
        }
        continue;
      }

      currentField.write(char);
      i += 1;
    }

    currentRow.add(currentField.toString());
    if (currentRow.any((String value) => value.isNotEmpty)) {
      rows.add(List<String>.from(currentRow));
    }

    return rows;
  }

  Widget _buildNoInformationMessage() {
    return const Center(child: Text('No inquiries avalible'));
  }

  Widget _buildSubmissionCard({
    required int index,
    required List<String> headers,
    required List<String> row,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Submission #$index',
              style: TextStyle(
                fontSize: _titleFontSize,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 10),
            ...List<Widget>.generate(headers.length - _visibleFieldStartIndex, (
              int offset,
            ) {
              final int fieldIndex = _visibleFieldStartIndex + offset;
              final String value = fieldIndex < row.length
                  ? row[fieldIndex]
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildFieldRow(headers[fieldIndex], value),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(String label, String value) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: _fieldFontSize,
          color: colorScheme.onSurface,
        ),
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: TextStyle(
              fontSize: _fieldFontSize,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          TextSpan(text: value.isEmpty ? '-' : value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CsvTableData>(
      future: _tableFuture,
      builder: (BuildContext context, AsyncSnapshot<_CsvTableData> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildNoInformationMessage();
        }

        final _CsvTableData tableData =
            snapshot.data ??
            const _CsvTableData(headers: <String>[], rows: <List<String>>[]);

        if (tableData.rows.isEmpty) {
          return _buildNoInformationMessage();
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: List<Widget>.generate(tableData.rows.length, (int index) {
              final List<String> row = tableData.rows[index];
              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == tableData.rows.length - 1 ? 0 : 10,
                ),
                child: _buildSubmissionCard(
                  index: index + 1,
                  headers: tableData.headers,
                  row: row,
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _CsvTableData {
  /// Parsed table data after row normalization and package filtering.
  const _CsvTableData({required this.headers, required this.rows});

  final List<String> headers;
  final List<List<String>> rows;
}
