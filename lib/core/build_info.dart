/// What this build calls itself.
///
/// One constant rather than a literal in each place that needs it: it was
/// written out twice already, in the diagnostic header and nowhere else that
/// agreed with it, and a version that disagrees with itself is worse than no
/// version at all — the first question about a pasted log is which build it
/// came from.
///
/// Kept in step with pubspec.yaml by a test rather than by discipline. Reading
/// pubspec at run time would mean shipping it, and a plugin to read it would be
/// a dependency for one string.
const appVersion = '0.1.0';
