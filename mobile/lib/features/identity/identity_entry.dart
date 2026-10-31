/// Whether the app offers «حساب Google» (sign in, link, backup) at all.
///
/// Off since 1.0.76: on Play builds the sign-in has no Android OAuth client for
/// Play's app-signing key, so it fails before reaching the server, and the
/// server no longer moves data between linked phones (IDENTITY_CROSS_DEVICE,
/// PR #179). Offering a button that can only fail, for a feature that would do
/// nothing if it worked, is worse than not offering it.
///
/// The ownership side is done (backend v37: bare sessions cannot confirm a
/// link, the first push token waits out its pause, an unvouched token change
/// unconfirms, deletions are not merged back). What is left before turning
/// this on: the Android OAuth client for Play's app-signing SHA-1 in the
/// Google Cloud project of the web client id, checked on a Play-signed build.
const bool kGoogleAccountEntryEnabled = false;
