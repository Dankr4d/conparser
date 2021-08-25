import macros
import ../pragmas

macro sym(n: typed{sym}): untyped =
  return nnkStmtList.newTree(
    nnkCall.newTree(
      newIdentNode("bindSym"),
      nnkDotExpr.newTree(
        newIdentNode(n.strVal),
        newIdentNode("repr")
      )
    )
  )

proc validatePrefix(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil:
    return
  for nPragmaChild in nPragma.children:
    if nPragmaChild.kind in {nnkSym}:
      continue
    if nPragmaChild[0] == sym(Prefix):

      # Prefix is not allowed on attributes
      error("Prefix is not allowed on attributes.", nPragmaChild[0])

proc validateObject(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil and nIdentDefs[1].getTypeImpl().kind != nnkObjectTy:
    return

  # Search Format pragma in attribute
  var foundFormat: bool = false
  var foundBlock: bool = false
  for nPragmaChild in nPragma.children:
    if nPragmaChild.kind in {nnkSym}:
      continue

    if nPragmaChild[0] == sym(Format):
      foundFormat = true # Found pragma at Attribute
    elif nPragmaChild[0] == sym(BlockValue):
      foundBlock = true

  if foundFormat and foundBlock:
    error("Only " & sym(Format).strVal & " OR " & sym(BlockValue).strVal & " pragma is allowed on attributes of type object.", nPragma)

  if nIdentDefs[1].getTypeImpl().kind != nnkObjectTy and nIdentDefs[1].getTypeImpl().typeKind != ntySequence:
    const errorMsg: string = " pragma is only allowed on attributes of type object."
    if foundFormat:
      error(sym(Format).strVal & errorMsg, nPragma)
    elif foundBlock:
      error(sym(BlockValue).strVal & errorMsg, nPragma)
    return # Not an object

  if nIdentDefs[1].kind == nnkBracketExpr:
    # BracketExpr
    #   Sym "seq"
    #   Sym "Kit"
    return

  # Search Format pragma in object, if Format not already found.
  let nAttrImpl: NimNode = nIdentDefs[1].getImpl()
  if not foundFormat:
    let nAttrImplPragma: NimNode = nAttrImpl.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
    if nAttrImplPragma != nil:
      for nPragmaChild in nAttrImplPragma.children:
        if nPragmaChild[0] == sym(Format):
          foundFormat = true
          break

  if not foundFormat and not foundBlock:
    # Format pragma not found on attribute and object
    error("Format pragma is missing on attribute or object declaration.", nIdentDefs[0])

proc validateDefault(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil:
    return

  for nPragmaChild in nPragma.children:
    if nPragmaChild.kind in {nnkSym}:
      continue

    if nPragmaChild[0] != sym(Default):
      continue

    var nTypeInst: NimNode
    if nIdentDefs[1].kind == nnkBracketExpr and nIdentDefs[1][0].getTypeInst() == getTypeInst(range):
      nTypeInst = nIdentDefs[1][1][1].getTypeInst()
    else:
      nTypeInst = nIdentDefs[1].getTypeInst()

    if nPragmaChild[1].kind == nnkPrefix and nPragmaChild[1][0].kind == nnkSym and nPragmaChild[1][0].strVal == "@":
      if nPragmaChild[1][1].kind == nnkBracket and nPragmaChild[1][1][0].kind == nnkObjConstr:
        if nPragmaChild[1][1][0][0] != nTypeInst[1]:
          error("Invalid Default value. You passed") # " & $nPragmaDefaultTypeInst & ", but expected " & $nTypeInst & ".", nPragmaChild[1])
          return
        return

    if nPragmaChild[1].kind == nnkCall:
      let nPragmaChildTypeImpl: NimNode = nPragmaChild[1].getTypeImpl()
      if nPragmaChildTypeImpl.kind == nnkBracketExpr:
        if nPragmaChildTypeImpl[1] != nTypeInst[1]:
          error("Invalid Default value. You passed") # " & $nPragmaDefaultTypeInst & ", but expected " & $nTypeInst & ".", nPragmaChild[1])
          return
        return


    let nPragmaDefaultTypeInst: NimNode = nPragmaChild[1].getTypeInst()
    if nTypeInst != nPragmaDefaultTypeInst:
      error("Invalid Default value. You passed " & $nPragmaDefaultTypeInst & ", but expected " & $nTypeInst & ".", nPragmaChild[1])

    var isLower, isHigher: bool = false
    if nIdentDefs[1].kind == nnkBracketExpr and nIdentDefs[1][0].getTypeInst() == getTypeInst(range):
      let nMinVal: NimNode = nIdentDefs[1][1][1]
      let nMaxVal: NimNode = nIdentDefs[1][1][2]
      case nTypeInst.typeKind:
      of ntyInt..ntyInt64:
        isLower = nPragmaChild[1].intVal < nMinVal.intVal
        isHigher = nPragmaChild[1].intVal > nMaxVal.intVal
      of ntyUInt..ntyUInt64:
        isLower = nPragmaChild[1].intVal < nMinVal.intVal # TODO: Cast to uintXX type
        isHigher = nPragmaChild[1].intVal > nMaxVal.intVal # TODO: Cast to uintXX type
      of ntyFloat..ntyFloat128:
        isLower = nPragmaChild[1].floatVal < nMinVal.floatVal
        isHigher = nPragmaChild[1].floatVal > nMaxVal.floatVal
      else:
        error("Range type " & $nTypeInst & " is not implemented!", nIdentDefs[1][1])
      if isLower:
        error("Default value is lower than specified in range.", nPragmaChild[1])
      elif isHigher:
        error("Default value is higher than specified in range.", nPragmaChild[1])

proc validateValid(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil:
    return

  for nPragmaChild in nPragma.children:
    if nPragmaChild.kind in {nnkSym}:
      continue

    if nPragmaChild[0] != sym(Valid):
      continue

    var nTypeInst: NimNode
    if nIdentDefs[1].kind == nnkBracketExpr and nIdentDefs[1][0].getTypeInst() == getTypeInst(range):
      nTypeInst = nIdentDefs[1][1][1].getTypeInst()
    else:
      nTypeInst = nIdentDefs[1].getTypeInst()
    let nPragmaValidInst: NimNode = nPragmaChild[1].getTypeInst()
    if nTypeInst != getTypeInst(bool):
      error("Valid is not allowed at attribute of type " &  $nTypeInst & ".", nPragmaChild[1])

    if nPragmaValidInst == getTypeInst(Bools):
      var nChilds: NimNode
      if nPragmaChild[1].kind == nnkStmtListExpr:
        nChilds = nPragmaChild[1] # Tempalte, like Bools01
      else:
        nChilds = nPragmaChild
      var foundTrue, foundFalse: bool = false
      for idx, nChild in nChilds[1].pairs:
        if idx == 0:
          continue # Skip Sym "Bools"
        case nChild[0].strVal:
        of "true":
          foundTrue = true
        of "false":
          foundFalse = true
        else:
          continue
        if nChild[1][1].findChild(it.kind == nnkStrLit) == nil:
          error("Empty seq at Bools constructor parameter `" & nChild[0].strVal & "`.", nChild[1][1])
      if not foundTrue or not foundFalse:
        error("Empty seq at Bools constructor parameter of `true` or/and `false`.", nChilds[1])

proc validateAttributes(nAttrRecList: NimNode) =
  for identDefs in nAttrRecList.children:
    let nPragma: NimNode = identDefs.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)

    validatePrefix(identDefs, nPragma)
    validateObject(identDefs, nPragma)
    validateDefault(identDefs, nPragma)
    validateValid(identDefs, nPragma)

    var nObjImpl: NimNode
    if identDefs[1].typeKind == ntySequence:
      nObjImpl = identDefs[1][1]
      if nObjImpl.kind == nnkBracketExpr:
        nObjImpl = nObjImpl[0]
      nObjImpl = nObjImpl.getImpl()
    elif identDefs[1].typeKind == ntyObject:
      nObjImpl = identDefs[1].getImpl()
      if nObjImpl[2][2].kind == nnkEmpty:
        nObjImpl = nObjImpl[2][1][0]
        if nObjImpl.kind == nnkBracketExpr:
          nObjImpl = nObjImpl[0]
        nObjImpl = nObjImpl.getImpl()

    if nObjImpl.kind == nnkTypeDef:
      validateAttributes(nObjImpl.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList))


macro validate*(tdesc: typedesc): untyped =
  let impl: NimNode = tdesc.getTypeInst()[1].getImpl()

  # Validate object pragmas
  let nObjectPragma: NimNode = impl[0][1] #.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
  var nSym: NimNode
  for nExprColonExpr in nObjectPragma.children():
    if nExprColonExpr.kind == nnkSym:
      nSym = nExprColonExpr
    else:
      nSym = nExprColonExpr[0]
    if not (nSym in [sym(Prefix), sym(Format), sym(BlockStart)]):
      error(nSym.strVal & " not allowed in object annotation.", nSym)

  # Validate object attribute pragmas
  validateAttributes(impl.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList))

when isMainModule:
  import conparser

  type
    Armor* = object of RootObj
      team*: range[0u8 .. 1u8]
      kit*: range[0u8 .. 3u8]
      val* {.Valid: Bools01, Default: false.}: bool

  func getDefaultArmors(): seq[Armor] =
    for team in 0u8..1u8:
      for kit in 0u8..3u8:
        result.add(Armor(team: team, kit: kit, val: false))

  func getDefaultStr(): string =
    return "My default string."

  type
    Profile* {.Prefix: "LocalProfile.".} = object
      # armors* {.Setting: "setCurrentProfileHeavyArmor", Format: "[team] [kit] [val]", Default: @[Armor(team: 0, kit: 0, val: false), Armor(team: 0, kit: 1, val: false), Armor(team: 0, kit: 2, val: false), Armor(team: 0, kit: 3, val: false), Armor(team: 1, kit: 0, val: false), Armor(team: 1, kit: 1, val: false), Armor(team: 1, kit: 2, val: false), Armor(team: 1, kit: 3, val: false)].}: seq[Armor]
      armors* {.Setting: "setCurrentProfileHeavyArmor", Format: "[team] [kit] [val]", Default: getDefaultArmors().}: seq[Armor]
      str* {.Setting: "str", Default: getDefaultStr().}: string

  let path: string = """/home/dankrad/Battlefield 2142/Profiles/0001/Profile.con"""
  var profile: Profile
  var report: ConReport
  (profile, report) = readCon[Profile](path)
  # for line in report.lines:
  #   echo line
  echo profile

