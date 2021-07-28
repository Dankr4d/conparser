#[
  TODOS:
    * Pragama to allow floats starting with dot
    * Range check in write proc
    * ValidBools `true`, `false` seq len check in parse and write proc
    * If Setting pragma passed without string, use attribute name.
      Same for prefix, but maybe use another pragma name then?
]#

import streams
import strutils
import parseutils
import math
import macros
import typeinfo
import sequtils
import tables

import conparser/dot
import conparser/strtoobj

export macros
export typeinfo
export strtoobj
export sequtils

type
  Bools* = object
    `true`*: seq[string]
    `false`*: seq[string]

template Prefix*(val: string) {.pragma.}
template Setting*(val: string) {.pragma.}
template Default*(val: string | SomeFloat | enum | bool) {.pragma.}
template Format*(val: string) {.pragma.}
template Range*(val: tuple[min, max: SomeFloat]) {.pragma.} # TODO: Use range
template ValidBools*(val: Bools) {.pragma.}


type
  ConReport* = object
    lines*: seq[ConLine]
    valid*: bool # true if all lines are valid, otherwise false
    invalidLines: seq[uint] # Invalid lines for a faster lookup
    multipleSettings: Table[uint, seq[uint]] # key = first line found, value = lines which same setting found afterwards
    settingsNotFound*: seq[ConSettingNotFound] # Settings which hasn't been found
    validRanges: Table[string, tuple[min, max: float]] # key = attr name, value = valid values
    validEnums: Table[string, seq[string]] # key = attr name, value = valid values
    validBools: Table[string, Bools] # key = attr name, value = valid values
    validFormats: Table[string, string] # key = attr name, value = valid values
  ConLine* = object
    valid*: bool
    validSetting*: bool
    validValue*: bool
    setting*: string
    value*: string
    raw*: string
    lineIdx*: uint # Starts at 0
    kind*: AnyKind
  ConSettingNotFound* = object
    setting*: string
    kind*: AnyKind


iterator validLines*(report: ConReport): ConLine {.noSideEffect.} =
  for line in report.lines:
    if line.valid:
      yield line

iterator invalidLines*(report: ConReport): ConLine {.noSideEffect.} =
  for lineIdx in report.invalidLines:
    yield report.lines[lineIdx]

iterator multipleSettings*(report: ConReport): ConLine {.noSideEffect.} =
  # Currently only yields the "duplicate" files and not the first one, add also the first one?
  for lineIdxFirst, lineIdxSeq in report.multipleSettings.pairs:
    for lineIdx in lineIdxSeq:
      yield report.lines[lineIdx]

iterator multipleSettingsLineIdx*(report: ConReport): uint {.noSideEffect.} =
  for lineIdxSeq in report.multipleSettings.values:
    for lineIdx in lineIdxSeq:
      yield lineIdx


func validEnum*(report: ConReport, line: ConLine | ConSettingNotFound): seq[string] =
  return report.validEnums[line.setting]

func validRange*(report: ConReport, line: ConLine | ConSettingNotFound): tuple[min, max: SomeFloat] =
  return report.validRanges[line.setting]

func validBools*(report: ConReport, line: ConLine | ConSettingNotFound): Bools =
  return report.validBools[line.setting]

func validFormat*(report: ConReport, line: ConLine | ConSettingNotFound): string =
  return report.validFormats[line.setting]


proc readCon*[T](stream: Stream): tuple[obj: T, report: ConReport] =
  var tableFound: Table[string, uint] # table of first lineIdx setting was found

  # fill valid* tables
  when T.hasCustomPragma(Prefix):
    const prefix: string = T.getCustomPragmaVal(Prefix)
  else:
    const prefix: string = ""
  for key, val in result.obj.fieldPairs:
    when result.obj.dot(key).hasCustomPragma(Setting):
      const setting: string = prefix & result.obj.dot(key).getCustomPragmaVal(Setting)
      when type(val) is enum:
        result.report.validEnums[setting] = type(val).toSeq().mapIt($it)
      elif type(val) is SomeFloat:
        when result.obj.dot(key).hasCustomPragma(Range):
          result.report.validRanges[setting] = result.obj.dot(key).getCustomPragmaVal(Range)
        else:
          result.report.validRanges[setting] = (low(float), high(float))
      elif type(val) is bool:
        when result.obj.dot(key).hasCustomPragma(ValidBools):
          result.report.validBools[setting] = result.obj.dot(key).getCustomPragmaVal(ValidBools)
        else:
          result = Bools(`true`: @["y", "yes", "true", "1", "on"], `false`: @["n", "no", "false", "0", "off"])
      elif type(val) is object:
        result.report.validFormats[setting] = result.obj.dot(key).getCustomPragmaVal(Format)
      else:
        {.fatal: "Attribute type '" & type(val) & "' not implemented.".}

  var lineRaw: string
  var lineIdx: uint = 0

  while stream.readLine(lineRaw): # TODO: Doesn't read last empty line

    var line: ConLine = ConLine(
      valid: true,
      validSetting: true,
      validValue: true,
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
            line.valid = false

            let lineIdxFirst: uint = tableFound[setting]
            if not result.report.multipleSettings.hasKey(lineIdxFirst):
              result.report.multipleSettings[lineIdxFirst]= @[lineIdx]
            else:
              result.report.multipleSettings[lineIdxFirst].add(lineIdx)
          else:
            tableFound[setting] = lineIdx

          line.kind = toAny(result.obj.dot(key)).kind

          if line.value.len > 0:
            try:
              when type(val) is enum:
                result.obj.dot(key) = parseEnum[type(val)](line.value)
              elif type(val) is SomeFloat:
                if line.value.startsWith('.'):
                  line.valid = false
                  line.validValue = false
                else:
                  when result.obj.dot(key).hasCustomPragma(Range):
                    let valFloat: SomeFloat = parseFloat(line.value)
                    const rangeTpl: tuple[min, max: SomeFloat] = result.obj.dot(key).getCustomPragmaVal(Range)
                    if valFloat >= rangeTpl.min and valFloat <= rangeTpl.max:
                      result.obj.dot(key) = valFloat
                    else:
                      line.valid = false
                      line.validValue = false
                  else:
                    result.obj.dot(key) = parseFloat(line.value)
              elif type(val) is bool:
                when result.obj.dot(key).hasCustomPragma(ValidBools):
                  const validBools: Bools = result.obj.dot(key).getCustomPragmaVal(ValidBools)
                  if line.value in validBools.`true`:
                    result.obj.dot(key) = true
                  elif line.value in validBools.`false`:
                    discard # Not required since default of bool is false
                  else:
                    line.valid = false
                    line.validValue = false
                else:
                  result.obj.dot(key) = parseBool(line.value)
              elif type(val) is object:
                result.obj.dot(key) = parse[type(val)](result.obj.dot(key).getCustomPragmaVal(Format), line.value)
              else:
                {.fatal: "Attribute type '" & type(val) & "' not implemented.".}
            except ValueError:
              line.valid = false
              line.validValue = false
          else:
            # Setting found, but value is empty
            line.valid = false
            line.validValue = false
          if not line.valid:
            when result.obj.dot(key).hasCustomPragma(Default):
              when result.obj.dot(key) is SomeFloat:
                const valDefault: SomeFloat = result.obj.dot(key).getCustomPragmaVal(Default)[0] # TODO: Why the fuck do I get a tuple?!?
                when result.obj.dot(key).hasCustomPragma(Range):
                  const rangeTpl: tuple[min, max: SomeFloat] = result.obj.dot(key).getCustomPragmaVal(Range)
                  when valDefault < rangeTpl.min or valDefault > rangeTpl.max:
                    {.fatal: "Default value " & $valDefault & " is not in range (" & $rangeTpl.min & ", " & $rangeTpl.max & ").".}
                  else:
                    result.obj.dot(key) = valDefault
                else:
                    result.obj.dot(key) = valDefault
              else:
                result.obj.dot(key) = result.obj.dot(key).getCustomPragmaVal(Default)[0] # TODO: Why the fuck do I get a tuple?!?
          break # Setting found, break
    if not foundSetting:
      line.valid = false
      line.validSetting = false
    if not line.valid:
      result.report.valid = false
      result.report.invalidLines.add(lineIdx)
    result.report.lines.add(line)
    lineIdx.inc()

  # Check for missing settings and add them to report
  for key, val in result.obj.fieldPairs:
    when result.obj.dot(key).hasCustomPragma(Setting):
      const setting: string = prefix & result.obj.dot(key).getCustomPragmaVal(Setting)
      if not tableFound.hasKey(setting):
        # TODO: Set default value to result.obj.dot(key)
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
  let fileStream: FileStream = newFileStream(path, fmWrite)

  if not isNil(fileStream):

    when T.hasCustomPragma(Prefix):
      const prefix: string = T.getCustomPragmaVal(Prefix)
    else:
      const prefix: string = ""

    for key, val in t.fieldPairs:
      when t.dot(key).hasCustomPragma(Setting):
        const setting: string = prefix & t.dot(key).getCustomPragmaVal(Setting)

        when type(val) is enum:
          fileStream.writeLine(setting & " " & $t.dot(key))
        elif type(val) is SomeFloat:
          fileStream.writeLine(setting & " " & $round(t.dot(key), 6)) # TODO: Add Round pragma
        elif type(val) is bool:
          when t.dot(key).hasCustomPragma(ValidBools):
            const validBools: Bools = t.dot(key).getCustomPragmaVal(ValidBools)
            # fileStream.writeLine(setting & " " & validBools.dot($t.dot(key))[0])
            if t.dot(key):
              fileStream.writeLine(setting & " " & validBools.`true`[0])
            else:
              fileStream.writeLine(setting & " " & validBools.`false`[0])
          else:
            fileStream.writeLine(setting & " " & $t.dot(key))
        elif type(val) is object:
          fileStream.writeLine(setting & " " & t.dot(key).serialize(t.dot(key).getCustomPragmaVal(Format)))
        else:
          {.fatal: "Attribute type '" & type(val) & "' not implemented.".}

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
      distance* {.Setting: "Distance", Range: (0.0, 1.0), Default: 1.0}: float
      enabled* {.Setting: "Enabled", ValidBools: Bools(`true`: @["1"], `false`: @["0"]).}: bool
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
