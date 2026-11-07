# Local design dependency

The app uses the actual `@imfacto/svelte` 0.1.0 package from Atlas Design Pack,
commit `765b3c44515a59578347c595bfefaff24b19f694`.

Run `node scripts/prepare-design-pack.mjs` before `npm ci`. This requires authorized
SSH access to the internal GitLab repository. The script checks out the pinned
commit, installs its lockfile, builds, and packs `vendor/imfacto-svelte-0.1.0-765b3c4.tgz`.

The upstream package declares `UNLICENSED`. The tarball is ignored by Git and is
not part of this project's MIT license. Public redistribution of the package or
bundles containing it requires a license decision. Public source users cannot
currently build the app without access to this dependency.

## November 2026 binary release authorization

On 2026-11-07, the package rights holder approved the maintainer's public
distribution of the v0.2.2 app bundle and the v0.2.3 and v0.2.4 follow-up releases containing this dependency. This approval
does not change the package's `UNLICENSED` declaration or grant a separate
license to redistribute the standalone design package.
