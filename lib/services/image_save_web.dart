import 'package:url_launcher/url_launcher.dart';

import 'image_save_result.dart';

/// Web variant: there is no photo gallery to write to, so the image is
/// opened in a tab of its own and the browser's own save takes over.
/// Web is the mock-data development target, so this only has to be
/// sensible, not seamless.
Future<ImageSaveResult> saveImageToGallery(String url) async {
  final launched = await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
  return launched ? ImageSaveResult.saved : ImageSaveResult.failed;
}
