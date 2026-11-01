/// Whether the app offers «حساب Google» (sign in, link, backup) at all.
///
/// Off since 1.0.76: on Play builds the sign-in has no Android OAuth client for
/// Play's app-signing key, so it fails before reaching the server, and the
/// server no longer moves data between linked phones (IDENTITY_CROSS_DEVICE,
/// PR #179). Offering a button that can only fail, for a feature that would do
/// nothing if it worked, is worse than not offering it.
///
/// On again from 1.0.77. The ownership side was fixed first (backend v37: a
/// bare session cannot confirm a link, the first push token waits out its
/// pause, an unvouched token change unconfirms, deletions are not merged back),
/// and the Android OAuth client for Play's app-signing SHA-1 exists in the web
/// client's Google Cloud project, whose consent screen is published.
/// What a link carries between phones is still the server's call:
/// IDENTITY_CROSS_DEVICE.
const bool kGoogleAccountEntryEnabled = true;
