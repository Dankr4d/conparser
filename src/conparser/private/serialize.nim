import math
import ../pragmas

template serializeEnum*(attr: untyped): string =
  $attr

template serializeSomeInteger*(attr: untyped): string =
  $attr

template serializeSomeFloat*(attr: untyped): string =
  var result: string
  when attr.hasCustomPragma(RoundW):
    result = $round(attr, attr.getCustomPragmaVal(RoundW))
  elif attr.hasCustomPragma(CeilW):
    result = $ceil(attr)
  elif attr.hasCustomPragma(FloorW):
    result = $floor(attr)
  else:
    result = $attr
  result

template serializeRange*(attr: untyped): string =
  var result: string
  when type(attr) is SomeInteger:
    result = serializeSomeInteger(attr)
  elif type(attr) is SomeFloat:
    result = serializeSomeFloat(attr)
  result

template serializeBool*(attr: untyped): string =
  var result: string
  when attr.hasCustomPragma(Valid):
    const validBools: Bools = attr.getCustomPragmaVal(Valid)
    if attr:
      result = validBools.`true`[0]
    else:
      result = validBools.`false`[0]
  else:
    result = $attr
  result

template serializeObject*(attr: untyped, fmt: string = ""): string =
  when fmt.len > 0:
    const format: string = fmt
  else:
    when attr.hasCustomPragma(Format):
      const format: string = attr.getCustomPragmaVal(Format)
    elif type(attr).hasCustomPragma(Format):
      const format: string = type(attr).getCustomPragmaVal(Format)
  attr.serialize(format)

template serializeString*(attr: untyped): string =
  attr

template serializeSeq*(attr: untyped): seq[string] =
  var result: seq[string]

  for item in attr.items:
    when type(item) is object:
      when attr.hasCustomPragma(Format):
        const format: string = attr.getCustomPragmaVal(Format)
      else:
        const format: string = ""

      result.add(serializeObject(item, format))
    else:
      discard # TODO
      # result &= serializeAll(item)
  result

template serializeAll*(attr: untyped, prefix: string): string =
  ## Serialize object.
  var result: string

  when attr.hasCustomPragma(Setting):
    const pre: string = prefix & attr.getCustomPragmaVal(Setting) & " "
  else:
    const pre: string = ""

  when type(attr) is enum:
    result = pre & serializeEnum(attr)
  elif type(attr) is range:
    result = pre & serializeRange(attr)
  elif type(attr) is SomeInteger:
    result = pre & serializeSomeInteger(attr)
  elif type(attr) is SomeFloat:
    result = pre & serializeSomeFloat(attr)
  elif type(attr) is bool:
    result = pre & serializeBool(attr)
  elif type(attr) is object:
    result = pre & serializeObject(attr)
  elif type(attr) is string:
    result = pre & serializeString(attr)
  elif type(attr) is seq:
    let tmpSeq: seq[string] = serializeSeq(attr)
    for idx, item in tmpSeq:
      result &=  pre & item
      if idx < tmpSeq.high:
        result &= "\n"
  else:
    {.fatal: "Attribute type '" & type(attr) & "' not implemented.".}
  result