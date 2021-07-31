import strutils

template parseEnum*(attr: untyped, value: string) =
  attr = parseEnum[type(attr)](value)

template parseRange*(attr: untyped, value: string): bool =
  var result: bool = true
  when type(attr) is SomeFloat:
    let tmpValue = parseFloat(value)
  elif type(attr) is SomeSignedInt:
    let tmpValue = parseInt(value)
  elif type(attr) is SomeUnsignedInt:
    let tmpValue = parseUInt(value)
  else:
    {.fatal: "Attribute type '" & $type(attr) & "' not implemented.".}
  if tmpValue >= low(type(attr)) and tmpValue <= high(type(attr)):
    attr = type(attr)(tmpValue)
  else:
    result = false
  result

template parseSomeInteger*(attr: untyped, value: string) =
  attr = type(attr)(parseInt(value))

template parseSomeFloat*(attr: untyped, value: string): bool =
  var result: bool = true
  if not value.startsWith('.'):
    # TODO: low/high check
    # TODO: Round/Floor/Ceil .. How to handle it? Check or apply?
    attr = type(attr)(parseFloat(value))
  else:
    result = false
  result

template parseBool*(attr: untyped, value: string): bool =
  var result: bool = true
  when attr.hasCustomPragma(Valid):
    const validBools: Bools = attr.getCustomPragmaVal(Valid)

    var tmpValue: string
    var validTrues, validFalses: seq[string]
    if validBools.normalize:
      tmpValue = normalize(value)
      validTrues = validBools.`true`.mapIt(normalize(it))
      validFalses = validBools.`false`.mapIt(normalize(it))
    else:
      tmpValue = value
      validTrues = validBools.`true`
      validFalses = validBools.`false`

    if tmpValue in validTrues:
      attr = true
    elif tmpValue in validFalses:
      discard # Not required since default of bool is false
    else:
      result = false
  else:
    attr = parseBool(value)
  result

template parseObject*(attr: untyped, value: string): bool =
  # TODO: Check if object has a format macro, when attr doesn't have it
  var result: bool = attr.hasCustomPragma(Format)
  if result:
    attr = parse[type(attr)](attr.getCustomPragmaVal(Format), value)
  result

template parseString*(attr: untyped, value: string): bool =
  var result: bool = value.len > 0
  if result:
    attr = value
  result


template parseAll*(attr: untyped, value: string): bool =
  var result: bool = true
  when type(attr) is enum:
    parseEnum(attr, value)
  elif type(attr) is range:
    result = parseRange(attr, value)
  elif type(attr) is SomeInteger:
    parseSomeInteger(attr, value)
  elif type(attr) is SomeFloat:
    result = parseSomeFloat(attr, value)
  elif type(attr) is bool:
    result = parseBool(attr, value)
  elif type(attr) is object:
    result = parseObject(attr, value)
  elif type(attr) is string:
    result = parseString(attr, value)
  else:
    {.fatal: "Attribute type '" & type(attr) & "' not implemented.".}
  result