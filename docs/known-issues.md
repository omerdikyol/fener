# Known issues

## Some windows have no title (OmniWM)

`omniwmctl query windows` (seen with OmniWM 0.8.0) reports an empty `title` for some
windows, for example every Ghostty window, even though macOS has the title: both the
Accessibility API (`kAXTitleAttribute`) and `CGWindowListCopyWindowInfo` (`kCGWindowName`)
return it. Changing Ghostty's `macos-titlebar-style` from `hidden` to `transparent` did not
help. Helium windows do get their title, so it seems tied to how the title is set, perhaps
when it changes after the window opens.

fener shows whatever OmniWM reports and falls back to the app name, so several Ghostty
windows all show up as "Ghostty", told apart only by their workspace.

Possible fixes:

1. Report it upstream to OmniWM (preferred; no change in fener).
2. When OmniWM's title is empty, read the title through Accessibility. That needs the
   Accessibility permission. fener is now a signed app bundle when a certificate is
   available, so that grant would survive rebuilds; this fallback is not built yet.
