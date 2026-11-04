# Local design dependency

The app uses the actual `@imfacto/svelte` 0.1.0 package from Atlas Design Pack,
commit `2466107017cc628d0c3d370c6db6764b9453ddeb`.

Run `node scripts/prepare-design-pack.mjs` before `npm ci`. This requires authorized
SSH access to the internal GitLab repository. The script checks out the pinned
commit, installs its lockfile, builds, and packs `vendor/imfacto-svelte-0.1.0.tgz`.

The upstream package declares `UNLICENSED`. The tarball is ignored by Git and is
not part of this project's MIT license. Public redistribution of the package or
bundles containing it requires a license decision. Public source users cannot
currently build the app without access to this dependency.
