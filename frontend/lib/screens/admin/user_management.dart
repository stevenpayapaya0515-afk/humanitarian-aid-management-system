import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';

// ========================================
// USER MANAGEMENT
// Admin can view accounts and create Staff.
// ========================================

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  // Display Cancel and the action beside each other.
  Widget _buildActionButtons({
    String cancelLabel = 'Cancel',
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
            // LEFT: White Cancel button with green border.
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF175C3A),
                    side: const BorderSide(
                      color: Color(0xFF175C3A),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    cancelLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 12),

            // RIGHT: Solid-colored action button.
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  // Form validation and input controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Accounts received from the backend
  List<Map<String, dynamic>> _users = [];

  // Loading and password visibility
  bool _loading = true;
  bool _saving = false;
  // Account currently being activated or deactivated
  int? _updatingUserId;
  bool _hidePassword = true;

  // Search text and error messages
  String _searchText = '';
  String? _listError;
  String? _formError;

  @override
  void initState() {
    super.initState();

    // Load accounts when this page opens.
    _loadUsers();
  }

  @override
  void dispose() {
    // Release the input controllers when leaving the page.
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ========================================
  // REQUEST HEADERS
  // Attach the logged-in user's token.
  // ========================================

  Map<String, String> _headers() {
    final token = AuthService.accessToken;

    if (token == null || token.isEmpty) {
      throw const AuthException(
        'Please log out and log in again.',
      );
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ========================================
  // BACKEND RESPONSE CHECKING
  // Convert errors into readable messages.
  // ========================================

  void _checkResponse(
    http.Response response,
    int expectedCode,
  ) {
    if (response.statusCode == expectedCode) return;

    if (response.statusCode == 401) {
      throw const AuthException(
        'Your session expired. Please log out and log in again.',
      );
    }

    if (response.statusCode == 403) {
      throw const AuthException(
        'Only administrators can access this feature.',
      );
    }
  
    // Use the backend's specific message for these errors.
    if (response.statusCode == 404 || response.statusCode == 409) {
       final data = jsonDecode(response.body);
        
        throw AuthException(
          data['detail'] as String? ?? 'Refresh and try again.',
      );
    }

    if (response.statusCode == 422) {
      throw const AuthException(
        'Check your name, email, and password. '
        'The password must contain at least 12 characters.',
      );
    }

    throw const AuthException(
      'The server could not complete the request.',
    );
  }

  // ========================================
  // LOAD USER ACCOUNTS
  // This function only loads the account list.
  // It does not display a success popup.
  // ========================================

  Future<void> _loadUsers() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _listError = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${AuthService.baseUrl}/users'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      // Convert the JSON list into Dart maps.
      final data = jsonDecode(response.body) as List;

      final users = data
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;

      setState(() {
        _users = users;
      });
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _listError = error.message;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _listError = 'Loading timed out. Try Refresh.';
      });
    } on http.ClientException {
      if (!mounted) return;

      setState(() {
        _listError = 'Cannot connect to the server.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _listError = 'Could not load the accounts.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ========================================
  // CENTERED SUCCESS POPUP
  // Called only after successful creation.
  // ========================================

  Future<void> _showSuccessDialog() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),

          // Green check icon and heading
          title: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: Color(0xFF175C3A),
                size: 60,
              ),
              SizedBox(height: 16),
              Text(
                'Account Created!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF175C3A),
                ),
              ),
            ],
          ),

          // Success message
          content: const Text(
            'The Staff account was created successfully.',
            textAlign: TextAlign.center,
          ),

          // Close the popup
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // DELETE STAFF ACCOUNT
  // Confirm before permanently deleting.
  // ========================================

  Future<void> _deleteStaff(Map<String, dynamic> user) async {
    if (_updatingUserId != null || _saving || _loading) return;

    final userId = user['user_id'] as int;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
             title: const Text(
            'Delete Staff Account?',
            textAlign: TextAlign.center,
          ),
          content: Text(
            'Permanently delete ${user['full_name']} '
            '(${user['email']})?\n\n'
            'This cannot be undone.',
            textAlign: TextAlign.center,
          ),

          // Cancel on the left; Delete on the right.
          actions: [
            _buildActionButtons(
              actionLabel: 'Delete Permanently',
              actionColor: const Color(0xFFB71C1C),
              onCancel: () => Navigator.of(dialogContext).pop(false),
              onConfirm: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    
    if (!mounted || confirmed != true) return;
    if (_updatingUserId != null || _saving || _loading) return;

    setState(() {
      _updatingUserId = userId;
      _listError = null;
    });

    try {
      final response = await http.delete(
        Uri.parse('${AuthService.baseUrl}/users/$userId'),
        headers: _headers(),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      if (!mounted) return;

      // Refresh the table after deletion.
      await _loadUsers();
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _listError = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _listError =
            'Could not confirm deletion. '
            'Refresh the account list before retrying.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserId = null;
        });
      }
    }
  }

  // ========================================
  // ACTIVATE OR DEACTIVATE STAFF
  // Ask for confirmation before changing status.
  // ========================================

  Future<void> _changeUserStatus(Map<String, dynamic> user) async {
    if (_updatingUserId != null) return;

    final userId = user['user_id'] as int;
    final currentlyActive = user['is_active'] == true;
    final action = currentlyActive ? 'Deactivate' : 'Activate';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
        );
      },
    );

    if (!mounted || confirmed != true) return;
    if (_updatingUserId != null) return;

    setState(() {
      _updatingUserId = userId;
      _listError = null;
    });

    try {
      final response = await http.patch(
        Uri.parse('${AuthService.baseUrl}/users/$userId/status'),
        headers: _headers(),
        body: jsonEncode({
          'is_active': !currentlyActive,
        }),
      ).timeout(const Duration(seconds: 15));

      _checkResponse(response, 200);

      if (!mounted) return;

      // Reload the table to show the updated status.
      await _loadUsers();
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _listError = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _listError =
            'Could not confirm the status change. '
            'Refresh the account list before retrying.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _updatingUserId = null;
        });
      }
    }
  }

  // ========================================
  // CREATE STAFF ACCOUNT
  // The backend assigns the Staff role.
  // ========================================

  Future<void> _createStaff() async {
    
    // Prevent repeated clicks while saving.
    if (_saving) return;

    // Check the form before sending a request.
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _formError = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/users'),
        headers: _headers(),
        body: jsonEncode({
          'full_name': _nameController.text.trim(),
          'email': _emailController.text.trim().toLowerCase(),
          'password': _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 15));

      // Continue only if the backend created the account.
      _checkResponse(response, 201);

      if (!mounted) return;

      // Clear the form after successful creation.
      _formKey.currentState!.reset();
      _nameController.clear();
      _emailController.clear();
      _passwordController.clear();

      setState(() {
        _hidePassword = true;
      });

      // Display the centered success popup once.
      await _showSuccessDialog();

      if (!mounted) return;

      // Refresh the account list after closing the popup.
      await _loadUsers();
    } on AuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _formError = error.message;
      });
    } on TimeoutException {
      if (!mounted) return;

      setState(() {
        _formError =
            'The request timed out. Refresh the account list '
            'to check whether the account was created before retrying.';
      });
    } on http.ClientException {
      if (!mounted) return;

      setState(() {
        _formError =
            'Connection interrupted. Check the server and refresh '
            'the account list before retrying.';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _formError =
            'Could not confirm the result. Refresh the account list.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ========================================
  // PAGE CONTENT
  // ========================================

  @override
  Widget build(BuildContext context) {
    // Filter accounts by name or email.
    final query = _searchText.trim().toLowerCase();

    final filteredUsers = _users.where((user) {
      final name = (user['full_name'] as String).toLowerCase();
      final email = (user['email'] as String).toLowerCase();

      return name.contains(query) || email.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ========================================
        // ADD STAFF ACCOUNT FORM
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
                    'Add Staff Account',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'New accounts created here have the Staff role.',
                  ),
                  const SizedBox(height: 20),

                  // Full name input
                  TextFormField(
                    controller: _nameController,
                    enabled: !_saving,
                    maxLength: 100,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Enter the full name.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Email input
                  TextFormField(
                    controller: _emailController,
                    enabled: !_saving,
                    maxLength: 254,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';

                      if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch(email)) {
                        return 'Enter a valid email address.';
                      }

                      return null;
                    },
                  ),
                  const SizedBox(height: 12),

                  // Password input
                  TextFormField(
                    controller: _passwordController,
                    enabled: !_saving,
                    obscureText: _hidePassword,
                    enableSuggestions: false,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,

                    // Enter key also submits the form.
                    onFieldSubmitted: (_) => _createStaff(),

                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: 'At least 12 characters',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),

                      // Show or hide the password.
                      suffixIcon: IconButton(
                        onPressed: () {
                          setState(() {
                            _hidePassword = !_hidePassword;
                          });
                        },
                        icon: Icon(
                          _hidePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.length < 12) {
                        return 'Use at least 12 characters.';
                      }

                      if (value.length > 1024) {
                        return 'Use no more than 1024 characters.';
                      }

                      return null;
                    },
                  ),

                  // Display form errors below the password.
                  if (_formError != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _formError!,
                      style: const TextStyle(
                        color: Colors.red,
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Create Staff button
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _createStaff,
                    icon: const Icon(Icons.person_add_outlined),
                    label: Text(
                      _saving ? 'Creating...' : 'Create Staff Account',
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
                // Heading and refresh button
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

                // Search accounts by name or email.
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

                // Display loading, error, empty state, or table.
                if (_loading)
                  const Center(
                    child: CircularProgressIndicator(),
                  )
                else if (_listError != null)
                  Text(
                    _listError!,
                    style: const TextStyle(
                      color: Colors.red,
                    ),
                  )
                else if (filteredUsers.isEmpty)
                  Text(
                    _users.isEmpty
                        ? 'No accounts found.'
                        : 'No matching accounts found.',
                  )
                else
                  // Match the table width to the search bar.
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

                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(user['full_name'] as String),
                                  ),
                                  DataCell(
                                    Text(user['email'] as String),
                                  ),
                                  DataCell(
                                    Text(user['role'] as String),
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
                                
                                  // Staff accounts have status and delete actions.
                                  DataCell(
                                    user['role'] == 'Staff'
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Activate or deactivate this account.
                                              TextButton(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: active
                                                      ? const Color(0xFFB71C1C)
                                                      : const Color(0xFF175C3A),
                                                  backgroundColor: active
                                                      ? const Color(0xFFFFEBEE)
                                                      : const Color(0xFFE8F5E9),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                ),
                                                onPressed:
                                                    _updatingUserId != null || _saving || _loading
                                                        ? null
                                                        : () => _changeUserStatus(user),
                                                child: Text(
                                                  _updatingUserId == user['user_id']
                                                      ? 'Updating...'
                                                      : active
                                                          ? 'Deactivate'
                                                          : 'Activate',
                                                ),
                                              ),
                                              const SizedBox(width: 8),

                                              // Permanently delete this Staff account.
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  foregroundColor: const Color(0xFFB71C1C),
                                                ),
                                                onPressed:
                                                    _updatingUserId != null || _saving || _loading
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