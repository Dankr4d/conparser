import math

template serialize*(attr: untyped): string =
  var result: string
  when type(attr) is enum:
    result = $attr
  elif type(attr) is range or type(attr) is SomeInteger or type(attr) is SomeFloat:
    when type(attr) is SomeInteger:
      result = $attr
    elif type(attr) is SomeFloat:
      when attr.hasCustomPragma(RoundW):
        result = $round(attr, attr.getCustomPragmaVal(RoundW))
      elif attr.hasCustomPragma(CeilW):
        result = $ceil(attr)
      elif attr.hasCustomPragma(FloorW):
        result = $floor(attr)
      else:
        result = $attr
  elif type(attr) is bool:
    when attr.hasCustomPragma(Valid):
      const validBools: Bools = attr.getCustomPragmaVal(Valid)
      if attr:
        result = validBools.`true`[0]
      else:
        result = validBools.`false`[0]
    else:
      $attr
  elif type(attr) is object:
    result = attr.serialize(attr.getCustomPragmaVal(Format))
  elif type(attr) is string:
    result = attr
  else:
    {.fatal: "Attribute type '" & type(attr) & "' not implemented.".}
  result