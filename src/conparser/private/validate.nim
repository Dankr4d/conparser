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
    if nPragmaChild[0] == sym(Prefix):
      # Prefix is not allowed on attributes
      error("Prefix is not allowed on attributes.", nPragmaChild[0])

proc validateObject(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil and nIdentDefs[1].getTypeImpl().kind != nnkObjectTy:
    return

  # Search Format pragma in attribute
  var foundFormat: bool = false
  for nPragmaChild in nPragma.children:
    if nPragmaChild[0] == sym(Format):
      foundFormat = true # Found pragma at Attribute

  if nIdentDefs[1].getTypeImpl().kind != nnkObjectTy:
    if foundFormat:
      error("Format pragma is only allowed on attributes of type object.", nPragma)
    return # Not an object

  # Search Format pragma in object, if Format not already found.
  let nAttrImpl: NimNode = nIdentDefs[1].getImpl()
  if not foundFormat:
    let nAttrImplPragma: NimNode = nAttrImpl.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
    if nAttrImplPragma != nil:
      for nPragmaChild in nAttrImplPragma.children:
        if nPragmaChild[0] == sym(Format):
          foundFormat = true
          break

  if not foundFormat:
    # Format pragma not found on attribute and object
    error("Format pragma is missing on attribute or object declaration.", nIdentDefs[0])

proc validateDefault(nIdentDefs, nPragma: NimNode) =
  if nPragma == nil:
    return

  for nPragmaChild in nPragma.children:
    if nPragmaChild[0] != sym(Default):
      continue

    var nTypeInst: NimNode
    if nIdentDefs[1].kind == nnkBracketExpr and nIdentDefs[1][0].getTypeInst() == getTypeInst(range):
      nTypeInst = nIdentDefs[1][1][1].getTypeInst()
    else:
      nTypeInst = nIdentDefs[1].getTypeInst()
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
      var foundTrue, foundFalse: bool = false
      for idx, nChild in nPragmaChild[1].pairs:
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
        error("Empty seq at Bools constructor parameter of `true` or/and `false`.", nPragmaChild[1])

proc validateAttributes(nAttrRecList: NimNode) =
  for identDefs in nAttrRecList.children:
    let nPragma: NimNode = identDefs.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)

    validatePrefix(identDefs, nPragma)
    validateObject(identDefs, nPragma)
    validateDefault(identDefs, nPragma)
    validateValid(identDefs, nPragma)

    # Call recursivly this function for each attribute with type object
    if identDefs[1].getTypeImpl().kind == nnkObjectTy:
      validateAttributes(identDefs[1].getImpl().findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList))

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
    if not (nSym in [sym(Prefix), sym(Format)]):
      error(nSym.strVal & " not allowed in object annotation.", nSym)

  # Validate object attribute pragmas
  validateAttributes(impl.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList))