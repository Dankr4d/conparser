# Description
Nim key/value config parser. Mainly written for Battlefield 2/2142 config files.

This project is currently **WIP**. Means that the usage and naming may change. And with **WIP**, I really mean WIP!

## Supported types
- [ ] `enum` -> Partially done, missing from object parsing
- [ ] `SomeFloat` -> Partially done, missing from object parsing
- [ ] `bool` -> Partially done, object parsing currently ignore `ValidBools`
- [ ] `object` -> Partially done
- [ ] `string` -> Partially done in object parsing
- [ ] `SomeSignedInt` -> Partially done in object parsing (only SomeInteger)
- [ ] `SomeUnsignedInt` -> Partially done in object parsing (only SomeInteger)
- [ ] `Option`
- [ ] `tuple`
- [ ] `seq`
- [ ] `set`
- [ ] `byte`
- [ ] `range`
- [ ] `array`
- [ ] `byte`
- [ ] `Table`
- [ ] `HashSet` / `OrderedSet`

## Supported pragmas
### Object
| Pragma | Parameter | Description |
| - | - | - |
| Prefix | `string` | Key prefix of attribute Setting pragma (see Attributes -> Setting). If Prefix is not set, no prefix is used. |
### Attributes
| Pragma | Parameter | Description |
| - | - | - |
| Setting | `string` | Key which is used to read and write config files. If Setting is not set, attribute is skipped. |
| Default | `string \| SomeFloat \| enum \| bool` | The default value which is set to the object attribute, in case that the parsed line is invalid. |
| Format | `string` | The format how data should be serialized from and deserialized to an object (see Example -> Resolution type) |
| Range | `tuple[SomeFloat, SomeFloat]` | Specify the range of valid `SomeFloat` values. |
| ValidBools | `Bools(true, false: seq[string])` | Specifiy valid bool values. If ValidBools is missing, parseBool from strutils is used. |

## Example
```nim
import conparser
import streams

const STR: string = """
MyObj.Eula accepted
MyObj.Resolution 800x600@60Hz
MyObj.Distance 0.8
MyObj.Enabled false
"""

type
  AcceptedDenied = enum
    Accepted = "accepted"
    Denied = "denied"
  Resolution = object of RootObj
    width*: uint16
    height*: uint16
    frequence*: uint8
  MyObj {.Prefix: "MyObj.".} = object
    eula {.Setting: "Eula", Default: Denied.}: AcceptedDenied
    resolution {.Setting: "Resolution", Format: "[width]x[height]@[frequence]Hz".}: Resolution
    distance {.Setting: "Distance", Range: (0.0, 1.0), Default: 1.0}: float
    enabled {.Setting: "Enabled", ValidBools: Bools(`true`: @["1"], `false`: @["0"]), Default: true.}: bool

when isMainModule:
  var (obj, report) = readCon[MyObj](newStringStream(STR))
  echo "=== OBJ ==="
  echo obj
  echo "=== LINES ==="
  for line in report.lines:
    echo line

# Output:
# === OBJ ===
# (eula: accepted, resolution: (width: 800, height: 600, frequence: 60), distance: 0.8, enabled: true)
# === LINES ===
# (valid: true, validSetting: true, validValue: true, setting: "MyObj.Eula", value: "accepted", raw: "MyObj.Eula accepted", lineIdx: 0, kind: akEnum)
# (valid: true, validSetting: true, validValue: true, setting: "MyObj.Resolution", value: "800x600@60Hz", raw: "MyObj.Resolution 800x600@60Hz", lineIdx: 1, kind: akObject)
# (valid: true, validSetting: true, validValue: true, setting: "MyObj.Distance", value: "0.8", raw: "MyObj.Distance 0.8", lineIdx: 2, kind: akFloat)
# (valid: false, validSetting: true, validValue: false, setting: "MyObj.Enabled", value: "false", raw: "MyObj.Enabled false", lineIdx: 3, kind: akBool)
```

## Markup export example screenshot (examples/markup.nim)
![2021-07-28-181211_610x350_scrot](https://user-images.githubusercontent.com/18078084/127376722-3b14b50d-4ec0-48d8-bc87-b1c508294558.png)
