# xcodeproj-lint

Two scripts for touching `Mise.xcodeproj/project.pbxproj` from a session that has
no Xcode. Same reason `resource-lint` exists: if nothing checks the file here,
nothing checks it until someone opens it on the Mac.

```sh
python3 tools/xcodeproj-lint/validate.py Mise.xcodeproj/project.pbxproj
python3 tools/xcodeproj-lint/generate.py Mise.xcodeproj/project.pbxproj   # overwrites
```

`validate.py` parses the NeXTSTEP plist the format actually is, then checks that
every 24 character object reference resolves, that nothing is orphaned, that both
targets have a synchronized group and a Debug and a Release configuration, and
that the bundle identifier and deployment target are the ones in `DECISIONS.md`.
Run it after any hand edit.

`generate.py` writes the whole file from the target and build setting description
at the top of it. It is how the project was first made and it is the easier way
to change a build setting from a cloud session, but it only knows about what is
described in it. **Once Xcode has written to the project file, stop using it**,
because a regeneration would throw away whatever Xcode added.

Neither script is part of the app build. They are not needed on the Mac, where
Xcode owns this file.
