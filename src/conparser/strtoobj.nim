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


proc serialize*[T](t: T, format: string): string =
  ## Serialize an object with passed format.

  var tokenAttribute, tokenDelimiters: string
  var pos: int = 0

  when T.hasCustomPragma(Prefix):
    const prefix: string = T.getCustomPragmaVal(Prefix)
  else:
    const prefix: string = ""

  while pos < format.len:
    pos += format.parseUntil(tokenDelimiters, '[', pos) + 1
    pos += format.parseUntil(tokenAttribute, ']', pos) + 1

    result &= tokenDelimiters
    for key, val in t.fieldPairs:
      if key == tokenAttribute:
        result &= serializeAll(t.dot(key), prefix)

func parse*[T: object](t: var T, format, value: string): bool =
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

    for key, val in t.fieldPairs:
      if key == tokenAttribute:
        try:
          if not parseAll(t.dot(key), tokenValue):
            when t.dot(key).hasCustomPragma(Default):
              t.dot(key) = t.dot(key).getCustomPragmaVal(Default)[0]
        except ValueError:
          return false
  return true


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
