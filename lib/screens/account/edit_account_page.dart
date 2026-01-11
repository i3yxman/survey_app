// lib/screens/account/edit_account_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class EditAccountPage extends StatefulWidget {
  const EditAccountPage({super.key});

  @override
  State<EditAccountPage> createState() => _EditAccountPageState();
}

class _EditAccountPageState extends State<EditAccountPage> {
  final _formKey = GlobalKey<FormState>();

  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _idNumberCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _alipayCtrl = TextEditingController();

  String _lastUserSignature = '';

  String _userSignature(dynamic user) {
    return [
      user.id,
      user.email,
      user.phone,
      user.fullName,
      user.gender,
      user.idNumber,
      user.province,
      user.city,
      user.address,
      user.alipayAccount,
    ].join('::');
  }

  void _syncFromUser(dynamic user) {
    _emailCtrl.text = user.email ?? '';
    _phoneCtrl.text = user.phone ?? '';
    _fullNameCtrl.text = user.fullName ?? '';
    _genderCtrl.text = user.gender ?? '';
    _idNumberCtrl.text = user.idNumber ?? '';
    _provinceCtrl.text = user.province ?? '';
    _cityCtrl.text = user.city ?? '';
    _addressCtrl.text = user.address ?? '';
    _alipayCtrl.text = user.alipayAccount ?? '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      await auth.refreshProfile();
      final user = auth.currentUser;
      if (user == null) return;
      _lastUserSignature = _userSignature(user);
      _syncFromUser(user);
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _fullNameCtrl.dispose();
    _genderCtrl.dispose();
    _idNumberCtrl.dispose();
    _provinceCtrl.dispose();
    _cityCtrl.dispose();
    _addressCtrl.dispose();
    _alipayCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProfile(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    await auth.updateProfile({
      'email': _emailCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'full_name': _fullNameCtrl.text.trim(),
      'gender': _genderCtrl.text.trim(),
      'id_number': _idNumberCtrl.text.trim(),
      'province': _provinceCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'alipay_account': _alipayCtrl.text.trim(),
    });
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final theme = Theme.of(context);
    if (user != null) {
      final signature = _userSignature(user);
      if (signature != _lastUserSignature) {
        _lastUserSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncFromUser(user);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('编辑资料')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('基本信息', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(labelText: '账号/邮箱'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        decoration: const InputDecoration(labelText: '手机号码'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _fullNameCtrl,
                        decoration: const InputDecoration(labelText: '姓名'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _genderCtrl,
                        decoration: const InputDecoration(labelText: '性别'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idNumberCtrl,
                        decoration: const InputDecoration(labelText: '身份证号码'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _provinceCtrl,
                        decoration: const InputDecoration(labelText: '省份'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _cityCtrl,
                        decoration: const InputDecoration(labelText: '城市'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(labelText: '地址'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _alipayCtrl,
                        decoration: const InputDecoration(labelText: '支付宝账号'),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: auth.loading ? null : () => _saveProfile(context),
                          child: Text(auth.loading ? '保存中...' : '保存资料'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
