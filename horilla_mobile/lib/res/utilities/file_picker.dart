import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';


const Set<String> _allowedAttachmentExtensions = {
  'pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'
};


Future<File?> pickFile(BuildContext context, {int maxSizeInMB = 20}) async {
  try {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _allowedAttachmentExtensions.toList(),
      allowMultiple: false,
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      final ext = result.files.single.extension?.toLowerCase().trim() ?? '';
      if (!_allowedAttachmentExtensions.contains(ext)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Allowed file types: PDF, JPG, JPEG, PNG, DOC, DOCX')),
        );
        return null;
      }

      final bytes = await file.length();
      if (bytes > maxSizeInMB * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('File size must be less than ${maxSizeInMB}MB')),
        );
        return null;
      }

      return file;
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error picking file: $e')),
    );
  }
  return null;
}
