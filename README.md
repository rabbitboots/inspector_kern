# Inspector Kern

This is a quick-and-dirty utility for checking if a TrueType font exhibits kerning offsets when used in [LÖVE](https://love2d.org/) 11.4. It loads TTF fonts in LÖVE, and checks `Font:getKerning()` against a list of common kerning pairs which are taken from [The Ultimate List of Kerning Pairs](https://github.com/andre-fuchs/kerning-pairs).

Inspector Kern defaults to an interactive mode: drag-and-drop TTF files onto the application window to get a report on the number of non-zero kerning offsets detected. It starts with the default LÖVE font ([Vera Sans](https://en.wikipedia.org/wiki/Bitstream_Vera) in 11.x).

A bulk test mode is also available, accessible from the command line. It will recursively scan a directory for TrueType fonts (identified by having a `.ttf` extension) and list those fonts which exhibit any non-zero kerning pair offsets.

Additionally, for each font loaded, Inspector Kern can run a sequence of strings against `Font:hasGlyphs()` and print the results.


## Usage

The following assumes you are in the same directory as `main.lua`.


`love .`
* Interactive mode. Drag-and-drop a TTF file onto the window to check the number of non-zero kerning offsets.


`love . --bulk path/to/fonts`
* Uses love.filesystem to recursively test all fonts in a given path. The testing loop is time-limited to prevent the application from becoming unresponsive.


`love . --bulk-nfs path/to/fonts`
* Like above, but uses the [nativefs](https://github.com/EngineerSmith/nativefs) i/o library instead of love.filesystem, which may be able to reach more paths (but may not work the same on all platforms.)


### Interactive Mode Controls

* Escape: Quit the application.


### Bulk Mode Controls

* Up/Down: Scroll the list of fonts.
* PageUp/PageDown: Scroll the list 10 at a time.
* Home/End: Jump to the top or bottom of the list.
* Escape: Quit the application.


## hasGlyphs mode

"hasGlyphs" mode can be enabled by passing the command line argument `--has-glyphs`. When this mode is active, each loaded font is tested against a series of strings with the `Font:hasGlyphs()` method. In interactive mode, the results are printed below the kerning pair examples. In bulk mode, the results are printed to the console/terminal only. (It's a horrible mess. Sorry. You may need to paste the results into a spreadsheet, or run them through a text processor to make it readable.)

The `glyphs_t` table contains the strings that are tested. Each entry is a sub-table: the first index is an identifier, and the second index is the actual string to test. The `glyph_t` defaults are all common ASCII whitespace chars, because those were the glyphs that I originally wanted to check when I added this option.


## Notes

* Inspector Kern doesn't know anything about the TrueType format, including whether a given font actually has kerning information. It only reports if `Font:getKerning()` detects any non-zero kerning offsets, among a predefined set of glyph pairs, at size 72.

* Some fonts don't have kerning information by design. Check the font in a known-good application to be sure. A common kerning pair which is easy to identify at a glance is upper-case "LT" at a large font size.
