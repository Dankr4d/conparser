#[
  TODOS:
    * Pragama to allow floats starting with dot
    * If Setting pragma passed without string, use attribute name.
      Same for prefix, but maybe use another pragma name then?
    * Reading/Storing multiline strings
    * Cast intVal in ConTypeValidation to uint if kind is ntyUInt..ntyUInt64
]#

## This module implements a key value config parser.
## It parses and writes files from and into objects.
## A report with lines and invalid lines is created withit you can query
## the valid values for representing the invalid format issue. BLALBLA
##
## Overview
## ========
##
## Parsing into an object
## ----------------------
## .. code-block:: Nim
##    import conparser
##    import streams # Or use readCon(path: string)
##
##    const DATA = """
##    MyObj.Eula accepted
##    MyObj.Resolution 800x600@60Hz
##    MyObj.Distance 0.8
##    MyObj.Enabled 1
##    """
##
##    type
##      AcceptedDenied* = enum
##        Accepted = "accepted"
##        Denied = "denied"
##      Resolution* = object of RootObj
##        width*: uint16
##        height*: uint16
##        frequence*: uint8
##      MyObj* {.Prefix: "MyObj.".} = object
##        eula* {.Setting: "Eula", Default: Denied.}: AcceptedDenied
##        resolution* {.Setting: "Resolution", Format: "[width]x[height]@[frequence]Hz".}: Resolution
##        distance* {.Setting: "Distance", Default: 1.0f32}: range[0.0f32 .. 1.0f32]
##        enabled* {.Setting: "Enabled", Valid: Bools(`true`: @["1"], `false`: @["0"]).}: bool
##
##    var (obj, report) = readCon[MyObj](newStringStream(DATA))
##    echo "=== OBJ ==="
##    echo obj
##    echo "=== LINES ==="
##    for line in report.lines:
##      echo line
##
##    # Output:
##    # === OBJ ===
##    # (eula: denied, resolution: (width: 800, height: 600, frequence: 60), distance: 1.0, enabled: true)
##    # === LINES ===
##    # (status: 3, setting: "MyObj.Eula", value: "accepted", raw: "MyObj.Eula accepted", lineIdx: 0, kind: akEnum)
##    # (status: 3, setting: "MyObj.Resolution", value: "800x600@60Hz", raw: "MyObj.Resolution 800x600@60Hz", lineIdx: 1, kind: akObject)
##    # (status: 3, setting: "MyObj.Distance", value: "0.8", raw: "MyObj.Distance 0.8", lineIdx: 2, kind: akFloat32)
##    # (status: 3, setting: "MyObj.Enabled", value: "1", raw: "MyObj.Enabled 1", lineIdx: 3, kind: akBool)

import streams
import strutils
import parseutils
import macros
import typeinfo
import sequtils
import tables

import conparser/private/validate
import conparser/private/parse
import conparser/private/serialize
import conparser/pragmas
import conparser/strtoobj

export macros
export typeinfo
export strtoobj
export sequtils
export pragmas


const
  NONE = (high(uint8) shl 7) shr 8 # 0
  VALID_SETTING = (high(uint8) shl 7) shr 7 # 1
  VALID_VALUE = (high(uint8) shl 7) shr 6 # 2
  REDUNDANT = (high(uint8) shl 7) shr 5 # 4


type
  ConReport* = object
    ## This is the report/object you get when calling ``readCon``.
    lines*: seq[ConLine] ## Contains all lines read in.
    valid*: bool ## true if all lines are valid, otherwise false
    invalidLines: seq[uint] ## Contains indices of invalid lines for a faster
                            ## lookup when calling `invalidLines` iterator.
    redundantSettings: Table[uint, seq[uint]] ## key = first found line,
                                              ## value = lines which same setting found afterwards
    settingsNotFound*: seq[ConSettingNotFound] ## Settings which hasn't been found.
    validIntRanges: Table[string, tuple[min, max: BiggestInt]] ## key = attr name, value = valid values
    validFloatRanges: Table[string, tuple[min, max: BiggestFloat]] ## key = attr name, value = valid values
    validEnums: Table[string, seq[string]] ## key = attr name, value = valid values
    validBools: Table[string, Bools] ## key = attr name, value = valid values
    validFormats: Table[string, string] ## key = attr name, value = valid values
  ConLine* = object
    ## Represents a line of read in config
    status: uint8 ## Bitmask which contains VALID_SETTING, VALID_VALUE or/and REDUNDANT.
                  ## Use helper procs: valid, validSetting, validValue or redundant
    setting*: string ## The parsed setting
    value*: string ## The parsed value
    raw*: string ## The raw line
    lineIdx*: uint ## The index of the line (starts at 0)
    kind*: AnyKind ## The kind of the attribute (for visualisation)
  ConSettingNotFound* = object
    ## Represents missing settings
    setting*: string ## The setting which hasn't been found
    kind*: AnyKind ## The kind of the attribute

func validSetting*(line: ConLine): bool =
  ## Returns if setting is valid.
  return (line.status and VALID_SETTING) > 0

func validValue*(line: ConLine): bool =
  ## Returns if value is valid. If setting is invalid, value is also invalid.
  return (line.status and VALID_VALUE) > 0

func redundant*(line: ConLine): bool =
  ## Returns if the setting is redundnat. First found setting doesn't have the redundant flag set.
  return (line.status and REDUNDANT) > 0

func valid*(line: ConLine): bool =
  ## Returns if the line is valid.
  return (line.validSetting and line.validValue and not line.redundant)
  # return (line.status and (VALID_SETTING or VALID_VALUE or REDUNDANT)) == (VALID_SETTING or VALID_VALUE)

func validEnum*(report: ConReport, line: ConLine | ConSettingNotFound): seq[string] =
  ## Returns valid enum values. Enums **must** have strings as values.
  return report.validEnums[line.setting]

func validRange*(tdesc: typedesc, report: ConReport, line: ConLine | ConSettingNotFound): tuple[min, max: tdesc] =
  ## Returns the valid range for this line. You need to check the line.kind attribute
  ## to pass the correct type description.
  runnableExamples:
    import streams

    type MyObj {.Prefix: "MyPrefix.".} = object
      myRange {.Setting: "MySetting", Default: 50u8.} : range[0u8 .. 100u8]

    var (obj, report) = readCon[MyObj](newStringStream("MyPrefix.MySetting 101"))
    for line in report.invalidLines:
      if line.kind == akUInt32:
        let validRange: tuple[min, max: uint32] = validRange(uint32, report, line)

  when tdesc is SomeInteger:
    let validRange: tuple[min, max: BiggestInt] = report.validIntRanges[line.setting]
    result.min = tdesc(validRange.min)
    result.max = tdesc(validRange.max)
  elif tdesc is SomeFloat:
    let validRange: tuple[min, max: BiggestFloat] = report.validFloatRanges[line.setting]
    result.min = tdesc(validRange.min)
    result.max = tdesc(validRange.max)

func validBools*(report: ConReport, line: ConLine | ConSettingNotFound): Bools =
  ## Returns valid bools for this line.
  return report.validBools[line.setting]

func validFormat*(report: ConReport, line: ConLine | ConSettingNotFound): string =
  ## Returns valid format for this line.
  return report.validFormats[line.setting]


iterator validLines*(report: ConReport): ConLine {.noSideEffect.} =
  ## Iterator for valid lines.
  for line in report.lines:
    if line.valid:
      yield line

iterator invalidLines*(report: ConReport): ConLine {.noSideEffect.} =
  ## Iterator for invalid lines.
  for lineIdx in report.invalidLines:
    yield report.lines[lineIdx]

iterator redundantLines*(report: ConReport): ConLine {.noSideEffect.} =
  ## Iterator for redundant lines (settings). First line isn't marked
  ## as redundant, also if value is invalid.
  for lineIdxFirst, lineIdxSeq in report.redundantSettings.pairs:
    for lineIdx in lineIdxSeq:
      yield report.lines[lineIdx]

iterator redundantLineIdxs*(report: ConReport): uint {.noSideEffect.} =
  ## Same as redundantLines except it's yielding the line index.
  for lineIdxSeq in report.redundantSettings.values:
    for lineIdx in lineIdxSeq:
      yield lineIdx

template checkAndParse*[T](obj: T) =
  for key, val in obj.fieldPairs:
    when val.hasCustomPragma(Setting):
      const setting: string = pre & val.getCustomPragmaVal(Setting)

      if setting == line.setting:
        line.status = line.status or VALID_SETTING

        # Check if already found and add to duplicates of first found line
        if tableFound.hasKey($type(obj) & setting) and not obj.hasCustomPragma(BlockValue):
          line.status = line.status or REDUNDANT
          let lineIdxFirst: uint = tableFound[$type(obj) & setting]
          if not result.report.redundantSettings.hasKey(lineIdxFirst):
            result.report.redundantSettings[lineIdxFirst]= @[lineIdx]
          else:
            result.report.redundantSettings[lineIdxFirst].add(lineIdx)
        else:
          tableFound[$type(obj) & setting] = lineIdx

        line.kind = toAny(val).kind

        if line.value.len > 0:
          try:
            if parseAll(val, line.value):
              line.status = line.status or VALID_VALUE
          except ValueError:
            discard

        if not line.validValue and not line.redundant:
          when val.hasCustomPragma(Default):
            val = val.getCustomPragmaVal(Default)[0]

        break # Setting found, break

proc readCon*[T](stream: Stream): tuple[obj: T, report: ConReport] =
  ## Prases the stream into an object and produces a report.
  ## Check the report.valid flag if there are any invalid lines.
  validate(T)

  result.report.valid = true

  var tableFound: Table[string, uint] # table of first lineIdx setting was found

  when T.hasCustomPragma(Prefix):
    const pre: string = T.getCustomPragmaVal(Prefix)
  else:
    const pre: string = ""
  for key, val in result.obj.fieldPairs:
    when val.hasCustomPragma(Setting):
      const setting {.used.}: string = pre & val.getCustomPragmaVal(Setting)
      when type(val) is enum:
        result.report.validEnums[setting] = type(val).toSeq().mapIt($it)
      elif type(val) is range:
        when type(val) is SomeInteger:
          result.report.validIntRanges[setting] = (BiggestInt(low(type(val))), BiggestInt(high(type(val))))
        elif type(val) is SomeFloat:
          result.report.validFloatRanges[setting] = (BiggestFloat(low(type(val))), BiggestFloat(high(type(val))))
        else:
          {.fatal: "Range type '" & type(val) & "' not implemented.".}
      elif type(val) is SomeInteger or type(val) is SomeFloat:
        discard # All numbers are valid
      elif type(val) is bool:
        when val.hasCustomPragma(Valid):
          result.report.validBools[setting] = val.getCustomPragmaVal(Valid)
        else:
          result.report.validBools[setting] = Bools(`true`: @["y", "yes", "true", "1", "on"], `false`: @["n", "no", "false", "0", "off"], normalize: true)
      elif type(val) is object:
        when val.hasCustomPragma(Format):
          result.report.validFormats[setting] = val.getCustomPragmaVal(Format)
        elif type(val).hasCustomPragma(Format):
          result.report.validFormats[setting] = type(val).getCustomPragmaVal(Format)
        # else:
        #   {.fatal: "Format pragma missing.".}
      elif type(val) is string:
        discard # All strings are valid
      elif type(val) is seq:
        discard # TODO
      else:
        {.fatal: "Attribute type '" & $type(val) & "' not implemented.".}

  var lineRaw: string
  var lineIdx: uint = 0
  var curAttrObjName: string

  while stream.readLine(lineRaw): # TODO: Doesn't read last empty line

    var line: ConLine = ConLine(
      status: 0,
      lineIdx: lineIdx,
      raw: lineRaw
    )

    let pos: int = lineRaw.parseUntil(line.setting, Whitespace, 0) + 1
    if pos < lineRaw.len:
      discard lineRaw.parseUntil(line.value, Newlines, pos)
      line.value = line.value.strip(leading = false) # TODO: Pass by parameter if multiple whitespaces are allowed as delemitter

    if line.setting.len == 0 and line.value.len == 0:
      # Empty line
      result.report.lines.add(line)
      lineIdx.inc()
      continue

    when T.hasCustomPragma(BlockStart):
      const blockStart: string = T.getCustomPragmaVal(BlockStart)
      for key, val in result.obj.fieldPairs:
        when val.hasCustomPragma(BlockValue):
          const blockValue: string = val.getCustomPragmaVal(BlockValue)
          if line.setting == blockStart:
            if line.value == blockValue:
              line.status = line.status or VALID_SETTING or VALID_VALUE
              curAttrObjName = key
            else:
              curAttrObjName = ""
          if key == curAttrObjName:
            checkAndParse(val)
            break
    else:
      # checkAndParse(result.obj) # TODO: Crashes (iterates over result too)
      var obj: T = result.obj
      checkAndParse(obj)
      result.obj = obj

    if not line.valid:
      result.report.valid = false
      result.report.invalidLines.add(lineIdx)
    result.report.lines.add(line)
    lineIdx.inc()

  # Check for missing settings and add them to report
  when T.hasCustomPragma(BlockStart):
    for key, val in result.obj.fieldPairs:
      for key2, val2 in val.fieldPairs:
        when val2.hasCustomPragma(Setting):
          const setting: string = T.getCustomPragmaVal(Prefix) & val2.getCustomPragmaVal(Setting)
          if not tableFound.hasKey($type(val) & setting):
            result.report.valid = false

            when val2.hasCustomPragma(Default):
              val2 = val2.getCustomPragmaVal(Default)[0]
            result.report.settingsNotFound.add(ConSettingNotFound(
              setting: setting,
              kind: toAny(val2).kind
            ))
  else:
    for key, val in result.obj.fieldPairs:
      when val.hasCustomPragma(Setting):
        const setting: string = pre & val.getCustomPragmaVal(Setting)
        if not tableFound.hasKey($type(result.obj) & setting):
          result.report.valid = false

          when val.hasCustomPragma(Default):
            val = val.getCustomPragmaVal(Default)[0]
          result.report.settingsNotFound.add(ConSettingNotFound(
            setting: setting,
            kind: toAny(val).kind
          ))


proc readCon*[T](path: string): tuple[obj: T, report: ConReport] =
  ## Same as readCon above, except that it reads from a file.
  var file: File
  if not file.open(path, fmRead, -1):
    raise newException(ValueError, "FILE COULD NOT BE OPENED!") # TODO
  let stream: FileStream = newFileStream(file)
  result = readCon[T](stream)
  stream.close()


proc writeCon*[T](t: T, path: string) =
  ## Writes the object to a config file.
  validate(T)

  let fileStream: FileStream = newFileStream(path, fmWrite)
  if isNil(fileStream):
    raise newException(ValueError, "FILE COULD NOT BE OPENED!") # TODO

  when T.hasCustomPragma(Prefix):
    const prefix: string = T.getCustomPragmaVal(Prefix)
  else:
    const prefix: string = ""

  when T.hasCustomPragma(BlockStart):
    for key, val in t.fieldPairs:
      when val.hasCustomPragma(BlockValue):
        fileStream.writeLine(T.getCustomPragmaVal(BlockStart) & " " & val.getCustomPragmaVal(BlockValue))

        for key2, val2 in val.fieldPairs:
          when val2.hasCustomPragma(Setting):
            # fileStream.writeLine(serializeAll(val2, prefix))
            var str: string = serializeAll(val2, prefix)
            if str.len > 0: # TODO: Check in which case there could be empty lines
              fileStream.writeLine(str)
        fileStream.writeLine()
  else:
    for key, val in t.fieldPairs:
      when val.hasCustomPragma(Setting):
        fileStream.writeLine(serializeAll(val, prefix))

  fileStream.close()

func newDefault*[T: object](): T =
  for key, val in result.fieldPairs:
    when val.hasCustomPragma(Default):
      val = val.getCustomPragmaVal(Default)[0]

when isMainModule and not defined(nimdoc):
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
MyObj.Eula accepte
MyObj.Resolution 800x600@60Hz
MyObj.Distance 0.8
MyObj.DistanceInvalid
MyObj.Enabled 1
""")
  var (obj, report) = readCon[MyObj](stream)
  echo "=== OBJ ==="
  echo obj
  echo "=== LINES ==="
  # for line in validLines(report):
  for line in report.lines:
    echo line.validSetting,  " ", line.validValue, " ", line.redundant, line
  obj.writeCon("/home/dankrad/Desktop/write.con")
