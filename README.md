# InkDrive

iPad-first PDF notebook. Expo 56 hosts the library; Swift/PDFKit/PencilKit owns the editor and coordinated, in-place file access. iPadOS 17+, iPad Pro M2 / Pencil 2 baseline.

## Workspace rules

- `../sources/` is a read-only project mirror. This app never writes there.
- A private GitHub repository and manually dispatched Actions workflows were authorized by the user. Run 39392434096 produced an unsigned arm64 Debug development IPA; run 39391400158 passed all 13 iPad simulator core tests. No EAS build or App Store submission was run.
- The IPA contains the Expo development client and Swift module. Sign and install with Sideloadly, then connect to the local Metro server. Expo Go cannot run the module. See docs/DEVELOPMENT-BUILD.md.
- A Windows JavaScript test pass is not proof of iOS compilation or iCloud interoperability.

## Local checks (no IPA)

`npm ci`, `npm test`, `npm run typecheck`, `npx expo config --type public`, `npx expo-modules-autolinking resolve --platform ios`.

Native tests live in `modules/inkdrive/ios/Tests`. Run with the iOS Swift package test target on an iPad simulator on a Mac, after explicit build authorization. Do not run `eas build`, `expo run:ios`, `xcodebuild`, or any GitHub push without the user's instruction.

See `docs/STATUS.md` for the exact verification boundary and `docs/ARCHITECTURE.md` for the file lifecycle.

## Notebook manual button

The Windows desktop shortcut **InkDrive 수업 정리** opens a loopback-only control window. **지금 수업 정리** starts the same pipeline used by the nightly automation, including the previous seven days if selected. `scripts/open-manual.cmd` opens it from a relocated source checkout. It uses the existing ChatGPT-authenticated Codex CLI, strips separate API-key environment variables, and requests the workspace-write sandbox. Closing the browser window does not stop an already running helper process. No startup item or Windows scheduled task is installed.
