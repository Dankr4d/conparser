import ../../conparser
from strutils import join

proc validValuesMarkup(report: ConReport, line: ConLine | ConSettingNotFound, markupEscapeProc: proc(str: string): string): string =
  case line.kind:
  of akEnum:
    result &= "[" & markupEscapeProc(report.validEnum(line).join(", ")) & "]"
  of akFloat..akFloat128:
    let validRange: tuple[min, max: BiggestFloat] = validRange(BiggestFloat, report, line)
    result &= "[" & $validRange.min & " .. " & $validRange.max & "]"
  of akBool:
    let validBools: Bools = report.validBools(line)
    result &= "(true: [" & markupEscapeProc(validBools.`true`.join(",")) & "], "
    result &= "false: [" & markupEscapeProc(validBools.`false`.join(",")) & "])"
  of akObject:
    result &= markupEscapeProc(report.validFormat(line))
  else:
    raise newException(ValueError, "Kind '" & $line.kind & "' not implemented.")

proc markup*(report: ConReport, markupEscapeProc: proc(str: string): string): string =
  var multipleSettings: seq[uint] = toSeq(report.redundantLineIdxs)
  for line in report.lines:
    if line.valid:
      result &= "<span foreground=\"#DCDCDC\">"
      result &= markupEscapeProc(line.raw)
      result &= "</span>"
    else:
      if line.setting.len == 0 and line.value.len == 0:
        discard # Empty line
      elif line.lineIdx in multipleSettings:
        # Setting already applied
        result &= "<b>"
        result &= "<span foreground=\"#FFA500\" strikethrough=\"true\">"
        result &= markupEscapeProc(line.raw)
        result &= "</span>"
        result &= "</b>"
      elif not line.validSetting:
        # Setting unknown
        result &= "<b>"
        result &= "<span foreground=\"#FF6347\" strikethrough=\"true\">"
        result &= markupEscapeProc(line.raw)
        result &= "</span>"
        result &= "</b>"
      else: # elif not line.validValue:
        result &= "<b>"
        result &= line.setting
        result &= " "
        if line.value.len == 0:
          # Value missing
          result &= "<span foreground=\"#8B4513\">"
          result &= "[MISSING]"
          result &= "</span>"
        else:
          # Value not valid
          result &= "<span foreground=\"#FF6347\">"
          result &= markupEscapeProc(line.value)
          result &= "</span>"
        result &= " "

        result &= "<span foreground=\"#ADFF2F\">"
        result &= validValuesMarkup(report, line, markupEscapeProc)
        result &= "</span>"
        result &= "</b>"
    result &= "\n"

  for notFound in report.settingsNotFound:
    result &= "<b>"
    result &= "<span foreground=\"#8B4513\">"
    result &= markupEscapeProc(notFound.setting)
    result &= "</span> "
    result &= "<span foreground=\"#ADFF2F\">"
    result &= validValuesMarkup(report, notFound, markupEscapeProc)
    result &= "</span>"
    result &= "</b>"
    result &= "\n"