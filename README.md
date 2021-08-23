# Description
Nim key/value config parser. Mainly written for Battlefield 2/2142 config files.

This project is currently **WIP**. Means that the usage and naming may change. And with **WIP**, I really mean WIP!

## Supported types
- [x] `enum` (string values only)
- [x] `range` (SomeFloat, SomeInteger only)
- [x] `SomeSignedInt`
- [x] `SomeUnsignedInt`
- [x] `SomeFloat`
- [x] `bool`
- [x] `object`
- [x] `string`
- [ ] `Option`
- [ ] `tuple`
- [x] `seq`
- [ ] `set`
- [ ] `byte`
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
| Default | `string \| SomeInteger \| SomeFloat \| enum \| bool` | The default value which is set to the object attribute, in case that the parsed line is invalid. |
| Format | `string` | The format how data should be serialized from and deserialized to an object (see Example -> Resolution type) |
| Valid | `Bools` | Specifiy valid bool values. If ValidBools is missing, parseBool from strutils is used. |
| RoundW | `int` | Rounds data, with passed decimal places, before written. |
| CeilW | `void` | Ceils data before written. |
| FloorW | `void` | Floors data before written. |
| BlockStart | `string` | Line prefix when to start reading a block. |
| BlockValue | `string` | Value which must match to read block into object. |

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
    distance {.Setting: "Distance", Default: 1.0f32}: range[0.0f32 .. 1.0f32]
    enabled {.Setting: "Enabled", Valid: Bools(`true`: @["1"], `false`: @["0"]), Default: true.}: bool

when isMainModule:
  var (obj, report) = readCon[MyObj](newStringStream(STR))
  echo "=== OBJ ==="
  echo obj
  echo "=== LINES ==="
  for line in report.lines:
    echo line

# Output:
# === OBJ ===
# (eula: accepted, resolution: (width: 800, height: 600, frequence: 60), distance: 0.800000011920929, enabled: true)
# === LINES ===
# (validSetting: true, validValue: true, redundant: false, setting: "MyObj.Eula", value: "accepted", raw: "MyObj.Eula accepted", lineIdx: 0, kind: akEnum)
# (validSetting: true, validValue: true, redundant: false, setting: "MyObj.Resolution", value: "800x600@60Hz", raw: "MyObj.Resolution 800x600@60Hz", lineIdx: 1, kind: akObject)
# (validSetting: true, validValue: true, redundant: false, setting: "MyObj.Distance", value: "0.8", raw: "MyObj.Distance 0.8", lineIdx: 2, kind: akFloat32)
# (validSetting: true, validValue: false, redundant: false, setting: "MyObj.Enabled", value: "false", raw: "MyObj.Enabled false", lineIdx: 3, kind: akBool)
```

## Markup export example screenshot (examples/markup.nim)
![2021-07-28-181211_610x350_scrot](https://user-images.githubusercontent.com/18078084/127376722-3b14b50d-4ec0-48d8-bc87-b1c508294558.png)
