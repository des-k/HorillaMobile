import 'package:flutter_test/flutter_test.dart';

import '../lib/res/utilities/attachment_access.dart';

void main() {
  group('extractMobileAttachments', () {
    test('parses structured attachment metadata for attendance requests', () {
      final attachments = extractMobileAttachments(
        {
          'attachments': [
            {
              'id': 10,
              'name': 'surat_tugas.pdf',
              'mime_type': 'application/pdf',
              'size': 245331,
              'view_url': '/api/attendance/attendance-request-attachments/7/10/view?token=abc',
              'download_url': '/api/attendance/attendance-request-attachments/7/10/download?token=abc',
              'delete_url': '/api/attendance/attendance-request-attachment/7/10?token=abc',
            }
          ],
        },
        baseUrl: 'https://example.com',
        includeRequestedData: true,
      );

      expect(attachments, hasLength(1));
      expect(attachments.first.id, '10');
      expect(attachments.first.name, 'surat_tugas.pdf');
      expect(attachments.first.mimeType, 'application/pdf');
      expect(attachments.first.viewUrl, contains('/view?token='));
      expect(attachments.first.downloadUrl, contains('/download?token='));
      expect(attachments.first.deleteUrl, contains('/attendance-request-attachment/'));
      expect(attachments.first.isInlineViewable, isFalse);
      expect(attachments.first.preferredOpenUrl(), contains('/download?token='));
    });

    test('keeps backward compatibility for legacy raw urls', () {
      final attachments = extractMobileAttachments(
        {
          'attachment_urls': [
            '/media/legacy/proof.docx',
            '/media/legacy/proof.docx',
          ],
        },
        baseUrl: 'https://example.com',
      );

      expect(attachments, hasLength(1));
      expect(attachments.first.name, 'proof.docx');
      expect(attachments.first.preferredOpenUrl(), '/media/legacy/proof.docx');
      expect(attachments.first.isInlineViewable, isFalse);
    });


    test('prefers structured secure attachment urls over legacy raw file urls', () {
      final attachments = extractMobileAttachments(
        {
          'attachments': [
            {
              'id': 99,
              'name': 'proof.pdf',
              'mime_type': 'application/pdf',
              'view_url': '/api/attendance/secure/view?token=abc',
              'download_url': '/api/attendance/secure/download?token=abc',
            }
          ],
          'attachment_urls': [
            '/media/temp/proof.pdf',
          ],
          'file_urls': [
            '/media/temp/proof.pdf',
          ],
        },
        baseUrl: 'https://example.com',
      );

      expect(attachments, hasLength(1));
      expect(attachments.first.id, '99');
      expect(attachments.first.viewUrl, '/api/attendance/secure/view?token=abc');
      expect(attachments.first.downloadUrl, '/api/attendance/secure/download?token=abc');
      expect(attachments.first.legacyUrl, isEmpty);
    });
  test('images remain inline-viewable for in-app preview', () {
    final attachments = extractMobileAttachments(
      {
        'attachments': [
          {
            'id': 11,
            'name': 'proof.png',
            'mime_type': 'image/png',
            'view_url': '/api/attendance/secure/view-image?token=abc',
            'download_url': '/api/attendance/secure/download-image?token=abc',
          }
        ],
      },
      baseUrl: 'https://example.com',
    );

    expect(attachments, hasLength(1));
    expect(attachments.first.isInlineViewable, isTrue);
    expect(attachments.first.preferredOpenUrl(), '/api/attendance/secure/view-image?token=abc');
  });

  });

  test('absoluteAttachmentUrl joins relative paths safely', () {
    expect(
      absoluteAttachmentUrl('https://example.com', '/api/files/1'),
      'https://example.com/api/files/1',
    );
    expect(
      absoluteAttachmentUrl('https://example.com/', 'api/files/1'),
      'https://example.com/api/files/1',
    );
  });

  test('sanitizeAttachmentFileName blocks invalid names', () {
    expect(sanitizeAttachmentFileName('..'), 'attachment');
    expect(sanitizeAttachmentFileName('report:final?.pdf'), 'report_final_.pdf');
  });
}
