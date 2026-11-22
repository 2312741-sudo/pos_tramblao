import 'package:flutter/material.dart';

class EditAttendanceDialog extends StatelessWidget {
  const EditAttendanceDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa giờ công'),
      content: const Text('Form sửa giờ'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
      ],
    );
  }
}
