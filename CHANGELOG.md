# Changelog -- Inspector Kern

## 1.0.1 (2022-05-14)

* Added changelog.
* Added an explicit *scanning* sub-state for bulk mode, so the application doesn't hang on very large directories.
* Performance improvements for low-end / IO-bound hardware:
  * Wrapped enumeration code into a time-limited coroutine.
  * Font-checking loop is now time-limited instead of "check X number of fonts per second."

