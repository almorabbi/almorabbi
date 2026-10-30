/// Whether the app offers «حساب Google» (sign in, link, backup) at all.
///
/// Off since 1.0.76: on Play builds the sign-in has no Android OAuth client for
/// Play's app-signing key, so it fails before reaching the server, and the
/// server no longer moves data between linked phones (IDENTITY_CROSS_DEVICE,
/// PR #179). Offering a button that can only fail, for a feature that would do
/// nothing if it worked, is worse than not offering it. Turn back on together
/// with the ownership-proof redesign and the OAuth client.
const bool kGoogleAccountEntryEnabled = false;
