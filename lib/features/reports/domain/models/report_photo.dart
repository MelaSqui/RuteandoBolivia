import 'package:image_picker/image_picker.dart';

class ReportPhoto {
  final XFile file;
  bool isValidating;
  bool? isValid;
  String? rejectionReason;

  ReportPhoto({
    required this.file,
    this.isValidating = false,
    this.isValid,
    this.rejectionReason,
  });
}
