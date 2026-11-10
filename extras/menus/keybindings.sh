#!/bin/sh
# Executable menu: lists the descriptions of the Karabiner rules in the selected profile.
# "Name: details" descriptions are split into a title and a dim subtitle.
[ $# -gt 0 ] && exit 0   # entries are for reading; choosing one does nothing
osascript -l JavaScript -e '
ObjC.import("Foundation");
const path = $.NSString.stringWithString("~/.config/karabiner/karabiner.json").stringByExpandingTildeInPath;
const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
const cfg = JSON.parse(ObjC.unwrap(text));
const profile = cfg.profiles.find(p => p.selected) || cfg.profiles[0];
((profile.complex_modifications || {}).rules || []).map(r => {
  const d = r.description || "";
  const i = d.indexOf(":");
  return JSON.stringify(i > 0 ? { name: d.slice(0, i), subtitle: d.slice(i + 1).trim() } : { name: d });
}).join("\n");'
