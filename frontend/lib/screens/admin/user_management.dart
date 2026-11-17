import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';

// ========================================
// USER MANAGEMENT
// Admin invites Staff by email.
// Admin can manage registered accounts.
// ========================================

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  List<Map<String, dynamic>> _users = [];

  bool _loading = true;
  bool _saving = false;
  int? _updatingUserId;

  String _searchText = '';
  String? _listError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  // ========================================
  // REQUEST HEADERS
  // ========================================

  Map<String, String> _headers() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException('Please log out and log in again.');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========================================
  // BACKEND RESPONSE HANDLING
  // ========================================

  void _checkResponse(http.Response response, int expectedCode) {
    if (response.statusCode == expectedCode) return;

    if (response.statusCode == 401) {
      throw const AuthException(
        'Your session expired. Please log out and log in again.',
      );
    }

    if (response.statusCode == 403) {
      throw const AuthException('Only administrators can access this feature.');
    }

    if (response.statusCode == 422) {
      throw const AuthException('Check the Staff email address and try again.');
    }

    if ([400, 404, 409, 410, 429, 503].contains(response.statusCode)) {
      try {
        final data = jsonDecode(response.body);

        if (data is Map && data['detail'] is String) {
          throw AuthException(data['detail'] as String);
        }
      } on FormatException {
        // Non-JSON response gets a generic error.
      }
    }

    throw const AuthException('The server could not complete the request.');
  }

  // ========================================
  // LOAD USER ACCOUNTS
  // ========================================

  Future<void> _loadUsers() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _listError = null;
    });

    try {
      final response = await http
          .get(Uri.parse('${AuthService.baseUrl}/users'), headers: _headers())
          .timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      final data = jsonDecode(response.body) as List;

      final users = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;

      setState(() {
        _users = users;
      });
    } on AuthException catch (error) {
      if (mounted) {
        setState(() {
          _listError = error.message;
        });
      }
    } on TimeoutException {
      if (mounted) {
        setState(() {
          _listError = 'Loading timed out. Try Refresh.';
        });
      }
    } on http.ClientException {
      if (mounted) {
        setState(() {
          _listError = 'Cannot connect to the server.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _listError = 'Could not load the accounts.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ========================================
  // CONFIRMATION BUTTONS
  // ========================================

  Widget _buildActionButtons({
    required String actionLabel,
    required VoidCallback? onCancel,
    required VoidCallback? onConfirm,
    Color actionColor = const Color(0xFF175C3A),
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF175C3A),
                    side: const BorderSide(color: Color(0xFF175C3A)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(actionLabel, textAlign: TextAlign.center),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // FEEDBACK AND LOADING DIALOGS
  // ========================================

  Future<void> _showFeedbackDialog({
    required bool success,
    required String title,
    required String message,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.check_circle_outline : Icons.error_outline,
                color: success
                    ? const Color(0xFF175C3A)
                    : const Color(0xFFC62828),
                size: 58,
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF263238),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF175C3A),
              foregroundColor: Colors.white,
              minimumSize: const Size(120, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showProcessingDialog(String title) {
    unawaited(
      showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(
                  color: Color(0xFF175C3A),
                  strokeWidth: 3,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF263238),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please wait while the request is processed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF667085)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _requestError(Object error, String fallback) {
    if (error is AuthException) {
      return error.message;
    }
    if (error is TimeoutException) {
      return 'Request timed out. Refresh the account list before trying again.';
    }
    if (error is http.ClientException) {
      return 'Cannot connect to the server. Check your connection.';
    }
    return fallback;
  }

  // ========================================
  // INVITE STAFF MEMBER
  // ========================================

  Future<void> _inviteStaff() async {
    if (_saving || _updatingUserId != null) {
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invalid Staff Email',
        message: 'Enter a valid email address before sending an invitation.',
      );
      return;
    }

    setState(() {
      _saving = true;
      _formError = null;
    });

    _showProcessingDialog('Sending Staff Invitation...');
    await WidgetsBinding.instance.endOfFrame;

    String? failureMessage;
    bool sent = false;
    try {
      final response = await http
          .post(
            Uri.parse('${AuthService.baseUrl}/staff-invitations'),
            headers: _headers(),
            body: jsonEncode({
              'email': _emailController.text.trim().toLowerCase(),
            }),
          )
          .timeout(const Duration(seconds: 20));

      _checkResponse(response, 201);
      sent = true;
    } catch (error) {
      failureMessage = _requestError(
        error,
        'Could not confirm the invitation. Check the server before resending.',
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _saving = false;
          _formError = failureMessage;
        });
      }
    }

    if (!mounted) {
      return;
    }
    if (!sent) {
      await _showFeedbackDialog(
        success: false,
        title: 'Invitation Not Sent',
        message: failureMessage ?? 'Unable to send the invitation.',
      );
      return;
    }

    _formKey.currentState?.reset();
    _emailController.clear();
    await _showFeedbackDialog(
      success: true,
      title: 'Staff Invitation Sent',
      message:
          'The registration link has been sent to the Staff email. '
          'The account will appear after the recipient completes registration.',
    );
    if (mounted) {
      await _loadUsers();
    }
  }

  // ========================================
  // ACTIVATE / DEACTIVATE STAFF
  // ========================================

  Future<void> _changeUserStatus(Map<String, dynamic> user) async {
    if (_updatingUserId != null || _saving || _loading) {
      return;
    }

    final userId = user['user_id'] as int;
    final currentlyActive = user['is_active'] == true;
    final action = currentlyActive ? 'Deactivate' : 'Activate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action Staff Account?'),
        content: Text(
          currentlyActive
              ? '${user['full_name']} will lose access to the system.'
              : '${user['full_name']} will be allowed to log in again.',
        ),
        actions: [
          _buildActionButtons(
            actionLabel: action,
            actionColor: currentlyActive
                ? const Color(0xFFB71C1C)
                : const Color(0xFF175C3A),
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _updatingUserId = userId;
      _listError = null;
    });

    _showProcessingDialog(
      currentlyActive
          ? 'Deactivating Staff Account...'
          : 'Activating Staff Account...',
    );
    await WidgetsBinding.instance.endOfFrame;

    String? failureMessage;
    bool updated = false;
    try {
      final response = await http
          .patch(
            Uri.parse('${AuthService.baseUrl}/users/$userId/status'),
            headers: _headers(),
            body: jsonEncode({'is_active': !currentlyActive}),
          )
          .timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);
      updated = true;
    } catch (error) {
      failureMessage = _requestError(
        error,
        'Could not confirm the status change. Refresh accounts before retrying.',
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _updatingUserId = null;
          _listError = failureMessage;
        });
      }
    }

    if (!mounted) {
      return;
    }
    if (updated) {
      await _loadUsers();
      if (!mounted) {
        return;
      }
      await _showFeedbackDialog(
        success: true,
        title: currentlyActive
            ? 'Staff Account Deactivated'
            : 'Staff Account Activated',
        message: currentlyActive
            ? 'The Staff account has been deactivated successfully.'
            : 'The Staff account has been activated successfully.',
      );
    } else {
      await _showFeedbackDialog(
        success: false,
        title: 'Status Update Failed',
        message: failureMessage ?? 'Unable to update the Staff account.',
      );
    }
  }

  // ========================================
  // DELETE STAFF ACCOUNT
  // ========================================

  Future<void> _deleteStaff(Map<String, dynamic> user) async {
    if (_updatingUserId != null || _saving || _loading) {
      return;
    }

    final userId = user['user_id'] as int;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Staff Account?', textAlign: TextAlign.center),
        content: Text(
          'Permanently delete ${user['full_name']} '
          '(${user['email']})?\n\n'
          'This cannot be undone.',
          textAlign: TextAlign.center,
        ),
        actions: [
          _buildActionButtons(
            actionLabel: 'Delete Permanently',
            actionColor: const Color(0xFFB71C1C),
            onCancel: () => Navigator.of(dialogContext).pop(false),
            onConfirm: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _updatingUserId = userId;
      _listError = null;
    });

    _showProcessingDialog('Deleting Staff Account...');
    await WidgetsBinding.instance.endOfFrame;

    String? failureMessage;
    bool deleted = false;
    try {
      final response = await http
          .delete(
            Uri.parse('${AuthService.baseUrl}/users/$userId'),
            headers: _headers(),
          )
          .timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);
      deleted = true;
    } catch (error) {
      failureMessage = _requestError(
        error,
        'Could not confirm deletion. Refresh accounts before retrying.',
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _updatingUserId = null;
          _listError = failureMessage;
        });
      }
    }

    if (!mounted) {
      return;
    }
    if (deleted) {
      await _loadUsers();
      if (!mounted) {
        return;
      }
      await _showFeedbackDialog(
        success: true,
        title: 'Staff Account Deleted',
        message: 'The Staff account has been deleted successfully.',
      );
    } else {
      await _showFeedbackDialog(
        success: false,
        title: 'Account Deletion Failed',
        message: failureMessage ?? 'Unable to delete the Staff account.',
      );
    }
  }

  // ========================================
  // USER MANAGEMENT PAGE
  // ========================================

  @override
  Widget build(BuildContext context) {
    final query = _searchText.trim().toLowerCase();

    final filteredUsers = _users.where((user) {
      final name = (user['full_name'] ?? '').toString().toLowerCase();

      final email = (user['email'] ?? '').toString().toLowerCase();

      return name.contains(query) || email.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ========================================
        // INVITE STAFF FORM
        // ========================================

        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Invite Staff Member',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Send a private registration link to a Staff member. '
                    'They will enter their full name and create their own password.',
                  ),

                  const SizedBox(height: 20),

                  // Staff email input
                  TextFormField(
                    controller: _emailController,
                    enabled: !_saving,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_saving) {
                        _inviteStaff();
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Staff Email Address',
                      hintText: 'Enter the email address for the invitation',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';

                      if (email.isEmpty) {
                        return 'Enter the Staff email address.';
                      }

                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address.';
                      }

                      return null;
                    },
                  ),

                  // Invitation errors
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Send invitation button
                  ElevatedButton.icon(
                    onPressed: _saving || _updatingUserId != null
                        ? null
                        : _inviteStaff,
                    icon: const Icon(Icons.mail_outline),
                    label: Text(
                      _saving
                          ? 'Sending Invitation...'
                          : 'Send Staff Invitation',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ========================================
        // USER ACCOUNTS LIST
        // ========================================
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'User Accounts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh accounts',
                      onPressed: _loading || _saving ? null : _loadUsers,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Search accounts
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchText = value;
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search by name or email...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 16),

                // Loading / Error / Empty / Table
                if (_loading)
                  const Center(child: CircularProgressIndicator())
                else if (_listError != null)
                  Text(_listError!, style: const TextStyle(color: Colors.red))
                else if (filteredUsers.isEmpty)
                  Text(
                    _users.isEmpty
                        ? 'No accounts found.'
                        : 'No matching accounts found.',
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('Name')),
                              DataColumn(label: Text('Email')),
                              DataColumn(label: Text('Role')),
                              DataColumn(label: Text('Status')),
                              DataColumn(label: Text('Actions')),
                            ],
                            rows: filteredUsers.map((user) {
                              final active = user['is_active'] == true;

                              final isStaff = user['role'] == 'Staff';

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text((user['full_name'] ?? '').toString()),
                                  ),

                                  DataCell(
                                    Text((user['email'] ?? '').toString()),
                                  ),

                                  DataCell(
                                    Text((user['role'] ?? '').toString()),
                                  ),

                                  DataCell(
                                    Text(
                                      active ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        color: active
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                    ),
                                  ),

                                  // Staff Actions
                                  DataCell(
                                    isStaff
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Activate / Deactivate
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: active
                                                      ? const Color(0xFFB71C1C)
                                                      : const Color(0xFF175C3A),
                                                  backgroundColor: active
                                                      ? const Color(0xFFFFEBEE)
                                                      : const Color(0xFFE8F5E9),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                  ),
                                                ),
                                                onPressed:
                                                    _updatingUserId != null ||
                                                        _saving ||
                                                        _loading
                                                    ? null
                                                    : () => _changeUserStatus(
                                                        user,
                                                      ),
                                                child: Text(
                                                  _updatingUserId ==
                                                          user['user_id']
                                                      ? 'Updating...'
                                                      : active
                                                      ? 'Deactivate'
                                                      : 'Activate',
                                                ),
                                              ),

                                              const SizedBox(width: 8),

                                              // Delete Staff
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(
                                                    0xFFB71C1C,
                                                  ),
                                                ),
                                                onPressed:
                                                    _updatingUserId != null ||
                                                        _saving ||
                                                        _loading
                                                    ? null
                                                    : () => _deleteStaff(user),
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                ),
                                                label: const Text('Delete'),
                                              ),
                                            ],
                                          )
                                        : const Text('—'),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
