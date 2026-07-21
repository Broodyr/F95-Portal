/// Saves an already-downloaded image into the device's photo gallery.
///
/// Android's share sheet has no "save" target of its own — it only lists
/// apps that accept an image — so handing the file to a share intent gave
/// the user nowhere to put it. Writing to the gallery is the real action,
/// and on mobile that is a platform call (MediaStore / PHPhotoLibrary),
/// hence the platform split: web has no gallery to write to and the
/// plugin doesn't compile there.
library;

export 'image_save_result.dart';
export 'image_save_web.dart' if (dart.library.io) 'image_save_io.dart';
