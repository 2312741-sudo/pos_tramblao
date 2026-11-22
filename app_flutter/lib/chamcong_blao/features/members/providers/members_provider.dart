import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/member_model.dart';

final membersProvider = Provider<List<MemberModel>>((ref) {
  return [];
});
