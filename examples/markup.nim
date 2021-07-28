# Info: Using gintro GTK3, because gtksourceview5 is only available in aur on arch linux
# TODO: Switch to GTK4, when gtksourceview5 is officially availabe on arch linux

import gintro/[gtk, gobject, glib, gio, gtksource]
import ../src/conparser
import ../src/conparser/exports/markup
import streams

type
  OffLowMediumHigh* {.pure.} = enum
    Off = "0"
    Low = "1"
    Medium = "2"
    High = "3"
  LowMediumHigh* {.pure.} = enum
    Low = "1"
    Medium = "2"
    High = "3"
  Antialiasing* {.pure.} = enum
    Off = "Off"
    FourSamples = "4Samples"
    EightSamples = "8Samples"
  Presets* {.pure.} = enum
    Low = "0"
    Medium = "1"
    High = "2"
    Custom = "3"
  Resolution* = object of RootObj # When "of RootObj" is missing, kind == akTpl .. optimization? dunno
    width*: uint16
    height*: uint16
    frequence*: uint8
  Video* {.Prefix: "VideoSettings.".} = object
    terrainQuality* {.Setting: "setTerrainQuality".}: LowMediumHigh
    geometryQuality* {.Setting: "setGeometryQuality".}: LowMediumHigh
    lightingQuality* {.Setting: "setLightingQuality".}: LowMediumHigh
    dynamicLightingQuality* {.Setting: "setDynamicLightingQuality".}: OffLowMediumHigh
    dynamicShadowsQuality* {.Setting: "setDynamicShadowsQuality".}: OffLowMediumHigh
    effectsQuality* {.Setting: "setEffectsQuality".}: LowMediumHigh
    textureQuality* {.Setting: "setTextureQuality".}: LowMediumHigh
    textureFilteringQuality* {.Setting: "setTextureFilteringQuality".}: LowMediumHigh
    resolution* {.Setting: "setResolution", Format: "[width]x[height]@[frequence]Hz".}: Resolution
    antialiasing* {.Setting: "setAntialiasing".}: Antialiasing
    viewDistanceScale* {.Setting: "setViewDistanceScale", Range: (0.0, 1.0), Default: 1.0}: float # 0.0 = 50%, 1.0 = 100%
    useBloom* {.Setting: "setUseBloom", ValidBools: Bools(`true`: @["1", "on"], `false`: @["0", "off"]).}: bool
    videoOptionScheme* {.Setting: "setVideoOptionScheme", Default: Presets.Custom.}: Presets

const STR: string = """
VideoSettings.setTerrainQuality 1
VideoSettings.setGeometryQuality
VideoSettings.setDynamicLightingQuality
VideoSettings.setDynamicShadowsQuality 1
VideoSettings.setDynamicShadowsQuality 0
VideoSettings.setEffectsQuality 1

VideoSettings.setInvalidSetting1
VideoSettings.setInvalidSetting2 <b>escaped</b>

VideoSettings.setTextureFilteringQuality 1
VideoSettings.setResolution 1920-1080@60Hz
VideoSettings.setInvalidSetting ""
VideoSettings.setDynamicShadowsQuality 1
VideoSettings.setViewDistanceScale 1.0f
VideoSettings.setUseBloom true
VideoSettings.setVideoOptionScheme 3
"""

proc markupEscapeProc(str: string): string =
  markupEscapeText(str, str.len)

proc appActivate(app: Application) =
  let window = newApplicationWindow(app)
  window.title = "conparser markup example"
  window.defaultSize = (250, 350)
  let view = newView()
  view.monospace = true
  view.editable = false
  view.showLineNumbers = true
  window.add(view)

  let (obj, report) = readCon[Video](newStringStream(STR))
  var iter: TextIter
  let markup: string = markup(report, markupEscapeProc)
  view.buffer.getEndIter(iter)
  view.buffer.insertMarkup(iter, markup, markup.len)

  window.showAll()

proc main =
  let app = newApplication("org.gtk.example")
  connect(app, "activate", appActivate)
  discard app.run()

main()
