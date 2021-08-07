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

# proc validatePrefix*(nIdentDefs: NimNode) =
#   discard

proc validateObject*(nIdentDefs: NimNode) =
    var nPragma: NimNode = nIdentDefs.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
    echo nIdentDefs.treeRepr
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

    # Check rekursively each type implementation of each attribute
    for nIdentDefs in nAttrImpl.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList):
      validateObject(nIdentDefs)



macro validate*(tdesc: typedesc): untyped =
  let impl: NimNode = tdesc.getTypeInst()[1].getImpl()

  # Validate object pragmas
  let nObjectPragma: NimNode = impl[0][1] #.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
  for nExprColonExpr in nObjectPragma.children():
    if not (nExprColonExpr[0] in [sym(Prefix), sym(Format)]):
      error(nExprColonExpr[0].strVal & " not allowed in object annotation.", nExprColonExpr[0])

  # Validate object attribute pragmas
  let nAttrRecList: NimNode = impl[2][2] #.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList)
  for identDefs in nAttrRecList.children:
    let nAttrPragma: NimNode = identDefs[0][1] #.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
    var nAttrTypeSym: NimNode = identDefs[1]
    var nkAttrType: NimNodeKind = nAttrTypeSym.getType().kind

    for nExprColonExpr in nAttrPragma.children:
      var nAttrTypeInst: NimNode
      if nAttrTypeSym.kind == nnkBracketExpr and nAttrTypeSym[0].getTypeInst() == getTypeInst(range):
        nAttrTypeInst = nAttrTypeSym[1][1].getTypeInst()
      else:
        nAttrTypeInst = nAttrTypeSym.getTypeInst()
      let nAttrPragmaTypeInst: NimNode = nExprColonExpr[1].getTypeInst()

      if nExprColonExpr[0] == sym(Prefix):
        # Prefix is not allowed on attributes
        error("Prefix is not allowed on attributes.", nExprColonExpr[0])
      elif nExprColonExpr[0] == sym(Default):
        # Validate if `Default` value type is the same as type of attribute
        if nAttrTypeInst != nAttrPragmaTypeInst:
          error("Invalid Default value. You passed " & $nAttrPragmaTypeInst & ", but expected " & $nAttrTypeInst & ".", nExprColonExpr[1])

        var isLower, isHigher: bool = false
        if nAttrTypeSym.kind == nnkBracketExpr and nAttrTypeSym[0].getTypeInst() == getTypeInst(range):
          let nMinVal: NimNode = nAttrTypeSym[1][1]
          let nMaxVal: NimNode = nAttrTypeSym[1][2]
          case nAttrTypeInst.typeKind:
          of ntyInt..ntyInt64:
            isLower = nExprColonExpr[1].intVal < nMinVal.intVal
            isHigher = nExprColonExpr[1].intVal > nMaxVal.intVal
          of ntyUInt..ntyUInt64:
            isLower = nExprColonExpr[1].intVal < nMinVal.intVal # TODO: Cast to uintXX type
            isHigher = nExprColonExpr[1].intVal > nMaxVal.intVal # TODO: Cast to uintXX type
          of ntyFloat..ntyFloat128:
            isLower = nExprColonExpr[1].floatVal < nMinVal.floatVal
            isHigher = nExprColonExpr[1].floatVal > nMaxVal.floatVal
          else:
            error("Range type " & $nAttrTypeInst & " is not implemented!", nAttrTypeSym[1])
          if isLower:
            error("Default value is lower than specified in range.", nExprColonExpr[1])
          elif isHigher:
            error("Default value is higher than specified in range.", nExprColonExpr[1])
      elif nExprColonExpr[0] == sym(Valid):
        if nAttrTypeInst != getTypeInst(bool):
          error("Valid is not allowed at attribute of type " &  $nAttrTypeInst & ".", nExprColonExpr[1])
        if nAttrPragmaTypeInst == getTypeInst(Bools):
          var foundTrue, foundFalse: bool = false
          for idx, nChild in nExprColonExpr[1].pairs:
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
            error("Empty seq at Bools constructor parameter of `true` or `false`.", nExprColonExpr[1])

    validateObject(identDefs)
