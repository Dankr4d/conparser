#[
  TODOS:
    * Pragama to allow floats starting with dot
    * If Setting pragma passed without string, use attribute name.
      Same for prefix, but maybe use another pragma name then?
    * Reading/Storing multiline strings
    * Cast intVal in ConTypeValidation to uint if kind is ntyUInt..ntyUInt64
]#

import streams
import strutils
import parseutils
import math
import macros
import typeinfo
import sequtils
import tables

import conparser/private/validate
import conparser/private/parse
import conparser/private/serialize
import conparser/private/dot
import conparser/pragmas
import conparser/strtoobj

export macros
export typeinfo
export strtoobj
export sequtils
export pragmas




type
  ConReport* = object
    lines*: seq[ConLine]
    valid*: bool # true if all lines are valid, otherwise false
    invalidLines: seq[uint] # Invalid lines for a faster lookup
    redundantSettings: Table[uint, seq[uint]] # key = first line found, value = lines which same setting found afterwards
    settingsNotFound*: seq[ConSettingNotFound] # Settings which hasn't been found
    # validFloatRanges: Table[string, tuple[min, max: float]] # key = attr name, value = valid values
    # validUIntRanges: Table[string, tuple[min, max: uint]] # key = attr name, value = valid values
    validIntRanges: Table[string, tuple[min, max: BiggestInt]] # key = attr name, value = valid values
    validFloatRanges: Table[string, tuple[min, max: BiggestFloat]] # key = attr name, value = valid values
    validEnums: Table[string, seq[string]] # key = attr name, value = valid values
    validBools: Table[string, Bools] # key = attr name, value = valid values
    validFormats: Table[string, string] # key = attr name, value = valid values
  ConLine* = object
    validSetting*: bool
    validValue*: bool
    redundant*: bool
    setting*: string
    value*: string
    raw*: string
    lineIdx*: uint # Starts at 0
    kind*: AnyKind
  ConSettingNotFound* = object
    setting*: string
    kind*: AnyKind

func valid*(line: ConLine): bool =
  return line.validSetting and line.validValue and not line.redundant

func validEnum*(report: ConReport, line: ConLine | ConSettingNotFound): seq[string] =
  return report.validEnums[line.setting]

func validRange*(tdesc: typedesc, report: ConReport, line: ConLine | ConSettingNotFound): tuple[min, max: tdesc] =
  when tdesc is SomeInteger:
    let validRange: tuple[min, max: BiggestInt] = report.validIntRanges[line.setting]
    result.min = tdesc(validRange.min)
    result.max = tdesc(validRange.max)
  elif tdesc is SomeFloat:
    let validRange: tuple[min, max: BiggestFloat] = report.validFloatRanges[line.setting]
    result.min = tdesc(validRange.min)
    result.max = tdesc(validRange.max)

func validBools*(report: ConReport, line: ConLine | ConSettingNotFound): Bools =
  return report.validBools[line.setting]

func validFormat*(report: ConReport, line: ConLine | ConSettingNotFound): string =
  return report.validFormats[line.setting]

iterator validLines*(report: ConReport): ConLine {.noSideEffect.} =
  for line in report.lines:
    if line.valid:
      yield line

iterator invalidLines*(report: ConReport): ConLine {.noSideEffect.} =
  for lineIdx in report.invalidLines:
    yield report.lines[lineIdx]

iterator redundantLines*(report: ConReport): ConLine {.noSideEffect.} =
  for lineIdxFirst, lineIdxSeq in report.redundantSettings.pairs:
    for lineIdx in lineIdxSeq:
      yield report.lines[lineIdx]

iterator redundantLineIdxs*(report: ConReport): uint {.noSideEffect.} =
  for lineIdxSeq in report.redundantSettings.values:
    for lineIdx in lineIdxSeq:
      yield lineIdx


proc readCon*[T](stream: Stream): tuple[obj: T, report: ConReport] =
  validate(T)

  var tableFound: Table[string, uint] # table of first lineIdx setting was found

  when T.hasCustomPragma(Prefix):
    const prefix: string = T.getCustomPragmaVal(Prefix)
  else:
    const prefix: string = ""
  for key, val in result.obj.fieldPairs:
    when result.obj.dot(key).hasCustomPragma(Setting):
      const setting: string = prefix & result.obj.dot(key).getCustomPragmaVal(Setting)
      when type(val) is enum:
        result.report.validEnums[setting] = type(val).toSeq().mapIt($it)
      elif type(val) is range:
        when type(val) is SomeInteger:
          result.report.validIntRanges[setting] = (BiggestInt(low(val)), BiggestInt(high(val)))
        elif type(val) is SomeFloat:
          result.report.validFloatRanges[setting] = (BiggestFloat(low(val)), BiggestFloat(high(val)))
        else:
          {.fatal: "Range type '" & type(val) & "' not implemented.".}
      elif type(val) is SomeInteger or type(val) is SomeFloat:
        discard # All numbers are valid
      elif type(val) is bool:
        when result.obj.dot(key).hasCustomPragma(Valid):
          result.report.validBools[setting] = result.obj.dot(key).getCustomPragmaVal(Valid)
        else:
          result.report.validBools[setting] = Bools(`true`: @["y", "yes", "true", "1", "on"], `false`: @["n", "no", "false", "0", "off"], normalize: true)
      elif type(val) is object:
        result.report.validFormats[setting] = result.obj.dot(key).getCustomPragmaVal(Format)
      elif type(val) is string:
        discard # All strings are valid
      else:
        {.fatal: "Attribute type '" & type(val) & "' not implemented.".}

  var lineRaw: string
  var lineIdx: uint = 0

  while stream.readLine(lineRaw): # TODO: Doesn't read last empty line

    var line: ConLine = ConLine(
      validSetting: true,
      validValue: true,
      redundant: false,
      lineIdx: lineIdx,
      raw: lineRaw
    )

    let pos: int = lineRaw.parseUntil(line.setting, Whitespace, 0) + 1
    if pos < lineRaw.len:
      discard lineRaw.parseUntil(line.value, Newlines, pos)
      line.value = line.value.strip(leading = false) # TODO: Pass by parameter if multiple whitespaces are allowed as delemitter

    var foundSetting: bool = false
    for key, val in result.obj.fieldPairs:
      when result.obj.dot(key).hasCustomPragma(Setting):
        const setting: string = prefix & result.obj.dot(key).getCustomPragmaVal(Setting)

        if setting == line.setting:
          foundSetting = true

          # Check if already found and add to duplicates of first found line
          if tableFound.hasKey(setting):
            line.redundant = true
            let lineIdxFirst: uint = tableFound[setting]
            if not result.report.redundantSettings.hasKey(lineIdxFirst):
              result.report.redundantSettings[lineIdxFirst]= @[lineIdx]
            else:
              result.report.redundantSettings[lineIdxFirst].add(lineIdx)
          else:
            tableFound[setting] = lineIdx

          line.kind = toAny(result.obj.dot(key)).kind

          if line.value.len > 0:
            try:
              line.validValue = parseAll(result.obj.dot(key), line.value)
            except ValueError:
              line.validValue = false
          else:
            # Setting found, but value is empty
            line.validValue = false

          if not line.validValue and not line.redundant:
            when result.obj.dot(key).hasCustomPragma(Default):
              result.obj.dot(key) = result.obj.dot(key).getCustomPragmaVal(Default)[0]

          break # Setting found, break

    if not foundSetting:
      line.validSetting = false
    if not line.validSetting or not line.validValue or line.redundant:
      result.report.valid = false
      result.report.invalidLines.add(lineIdx)
    result.report.lines.add(line)
    lineIdx.inc()

  # Check for missing settings and add them to report
  for key, val in result.obj.fieldPairs:
    when result.obj.dot(key).hasCustomPragma(Setting):
      const setting: string = prefix & result.obj.dot(key).getCustomPragmaVal(Setting)
      if not tableFound.hasKey(setting):
        when result.obj.dot(key).hasCustomPragma(Default):
          result.obj.dot(key) = result.obj.dot(key).getCustomPragmaVal(Default)[0]
        result.report.settingsNotFound.add(ConSettingNotFound(
          setting: setting,
          kind: toAny(result.obj.dot(key)).kind
        ))


proc readCon*[T](path: string): tuple[obj: T, report: ConReport] =
  var file: File
  if not file.open(path, fmRead, -1):
    raise newException(ValueError, "FILE COULD NOT BE OPENED!") # TODO
  let stream: FileStream = newFileStream(file)
  return readCon[T](stream)


proc writeCon*[T](t: T, path: string) =
  validate(T)

  let fileStream: FileStream = newFileStream(path, fmWrite)
  if isNil(fileStream):
    raise newException(ValueError, "FILE COULD NOT BE OPENED!") # TODO

  when T.hasCustomPragma(Prefix):
    const prefix: string = T.getCustomPragmaVal(Prefix)
  else:
    const prefix: string = ""

  for key, val in t.fieldPairs:
    when t.dot(key).hasCustomPragma(Setting):
      const setting: string = prefix & t.dot(key).getCustomPragmaVal(Setting)

      fileStream.writeLine(setting & " " & serialize(t.dot(key)))

  fileStream.close()


when isMainModule:
  type
    AcceptedDenied* = enum
      Accepted = "accepted"
      Denied = "denied"
    Resolution* = object of RootObj # When without "of RootObj", kind == akTpl? .. optimization? dunno ....
      width*: uint16
      height*: uint16
      frequence*: uint8
    MyObj* {.Prefix: "MyObj.".} = object
      eula* {.Setting: "Eula", Default: Denied.}: AcceptedDenied
      resolution* {.Setting: "Resolution", Format: "[width]x[height]@[frequence]Hz".}: Resolution
      distanceRange* {.Setting: "Distance", Default: 1.0f32}: range[0.0f32 .. 1.0f32]
      distanceRangeUInt* {.Setting: "RANGE UINT", Default: 1u32}: range[0u32 .. 100u32]
      distanceFloat* {.Setting: "Distance", Default: 1.0f32, RoundW: 6}: float32
      enabled* {.Setting: "Enabled", Valid: Bools(`true`: @["1"], `false`: @["0"]).}: bool
      uint8Attr* {.Setting: "uint8Attr", Default: 5u8.}: uint8
      name* {.Setting: "Name", Default: "Peter Pan".}: string
  var stream: StringStream = newStringStream("""
MyObj.Eula accepted
MyObj.Resolution 800x600@60Hz
MyObj.Distance 0.8
MyObj.Enabled 1
""")
  var (obj, report) = readCon[MyObj](stream)
  echo "=== OBJ ==="
  echo obj
  echo "=== LINES ==="
  for line in validLines(report):
    echo line
  obj.writeCon("/home/dankrad/Desktop/write.con")
