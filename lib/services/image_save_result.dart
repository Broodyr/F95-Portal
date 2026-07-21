/// Outcome of a save, so the caller can tell "you said no" apart from
/// "it broke" — the two need different things said to the user, and only
/// one of them is worth an error-styled toast.
enum ImageSaveResult {
  saved,

  /// An animated source saved as a single frame. Nothing failed, but the
  /// user got less than they were looking at, so it can't be reported as
  /// a plain success. Writing the animation would mean encoding a format
  /// Flutter can't produce (PNG and raw pixels are the only options), so
  /// this is the deliberate outcome rather than a shortfall to fix here.
  ///
  /// Rare in practice: f95 re-encodes only *still* attachments to AVIF
  /// and leaves animations as GIF, which save byte-for-byte with the
  /// animation intact and report [saved]. This covers animated AVIF from
  /// anywhere else — don't read it as "animations are broken".
  savedAsStill,

  denied,
  failed,
}
