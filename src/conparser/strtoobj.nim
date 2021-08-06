#[
  TODO:
    * Add "InvalidFormat" and "InvalidValue" exceptions
]#

import parseutils
import private/parse
import private/serialize
import private/dot
import private/validate
import pragmas
import macros


func serialize*[T](t: T, format: string): string =
  ## Serialize an object with passed format.

  var tokenAttribute, tokenDelimiters: string
  var pos: int = 0

  while pos < format.len:
    pos += format.parseUntil(tokenDelimiters, '[', pos) + 1
    pos += format.parseUntil(tokenAttribute, ']', pos) + 1

    result &= tokenDelimiters
    for key, val in t.fieldPairs:
      if key == tokenAttribute:
        result &= serialize(t.dot(key))

func parse*[T](format, value: string): T =
  ## Parses a string to an object with passed format.
  var tokenAttribute, tokenValue, tokenDelimiters: string
  var posFormat, posValue: int = 0

  # Skip delemitters at start of string
  posFormat = format.skipUntil('[', 0) + 1
  posValue = posFormat - 1

  while posFormat < format.len:
    posFormat += format.parseUntil(tokenAttribute, ']', posFormat) + 1
    posFormat += format.parseUntil(tokenDelimiters, '[', posFormat) + 1

    posValue += value.parseUntil(tokenValue, tokenDelimiters, posValue)
    posValue += tokenDelimiters.len

    var valid: bool = false
    for key, val in result.fieldPairs:
      if key == tokenAttribute:
        try:
          valid = parseAll(result.dot(key), tokenValue)
        except ValueError:
          discard # valid already set to false
        if not valid:
          when result.dot(key).hasCustomPragma(Default):
            result.dot(key) = result.dot(key).getCustomPragmaVal(Default)[0]


when isMainModule:
  type
    Resolution* = object
      width*: uint16
      height*: uint16
      frequence*: uint8

  let format: string = "[width]x[height]@[frequence]Hz"
  let value: string = "800x600@60Hz"

  var res: Resolution = parse[Resolution](format, value)
  echo res
  echo res.serialize(format)
