# F-Droid packaging candidate

`io.github.irisphilip.netmap.yml` is a candidate metadata file for `fdroiddata/metadata/`. It uses F-Droid's Flutter srclib, a pinned Flutter version, NDK r28c, a scanned local pub cache, and an unsigned universal APK. The bundled Gradle wrapper JAR is removed before F-Droid scanning; Flutter restores the build-tool wrapper when it builds.

The file refers to the first release tag `v1.0.0`. That tag must exist and point to reviewed source before submitting the recipe. Confirm the GitHub Linux verification workflow passes for the release commit first.

This recipe has not been validated with `fdroid readmeta`, `fdroid lint`, or an F-Droid build-server build. A passing ordinary Linux build is useful evidence but does not replace those checks or maintainer review. Do not claim a successful F-Droid build until it has actually run.

For main-repository inclusion, file a request at https://gitlab.com/fdroid/rfp/-/issues/new or contribute a merge request to https://gitlab.com/fdroid/fdroiddata. GitLab offers a GitHub sign-in option; new-account setup and any legal acceptance must be completed by the account owner.

The application uses the permanent ID `io.github.irisphilip.netmap`. Earlier test APKs used `com.example.netmap` and are separate Android applications. The developer's private signing key is not needed by F-Droid and must never be uploaded.

Default F-Droid signing is used in this candidate. Upstream/developer-signature reproducibility has not been established; there is deliberately no `Binaries` or `AllowedAPKSigningKeys` declaration claiming otherwise.
