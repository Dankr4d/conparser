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

macro validate*(tdesc: typedesc): untyped =
  let impl: NimNode = tdesc.getTypeInst()[1].getImpl()

  # Validate object pragmas
  let nObjectPragma: NimNode = impl.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
  for nExprColonExpr in nObjectPragma.children():
    if not (nExprColonExpr[0] in [sym(Prefix), sym(Format)]):
      error(nExprColonExpr[0].strVal & " not allowed in object annotation.", nExprColonExpr[0])

  # Validate object attribute pragmas
  let nAttrRecList: NimNode = impl.findChild(it.kind == nnkObjectTy).findChild(it.kind == nnkRecList)
  for identDefs in nAttrRecList.children:
    let nPragma: NimNode = identDefs.findChild(it.kind == nnkPragmaExpr).findChild(it.kind == nnkPragma)
    var nAttrTypeSym: NimNode = identDefs[1]
    var nkAttrType: NimNodeKind = nAttrTypeSym.getType().kind

    for nExprColonExpr in nPragma.children:
      var nTypeInstAttr: NimNode
      if nAttrTypeSym.kind == nnkBracketExpr and nAttrTypeSym[0].getTypeInst() == getTypeInst(range):
        nTypeInstAttr = nAttrTypeSym[1][1].getTypeInst()
      else:
        nTypeInstAttr = nAttrTypeSym.getTypeInst()
      let nTypeInstPragma: NimNode = nExprColonExpr[1].getTypeInst()

      if nExprColonExpr[0] == sym(Prefix):
        # Prefix is not allowed on attributes
        error("Prefix is not allowed on attributes.", nExprColonExpr[0])
      elif nExprColonExpr[0] == sym(Format):
        # Validate if `Format` is only applied to attributes of type object
        if nkAttrType != nnkObjectTy:
          error("Format pragma is only allowed on attributes of kind " & $nnkObjectTy & ", not of " & $nkAttrType & ".", nExprColonExpr[0])
      elif nExprColonExpr[0] == sym(Default):
        # Validate if `Default` value type is the same as type of attribute
        if nTypeInstAttr != nTypeInstPragma:
          error("Invalid Default value. You passed " & $nTypeInstPragma & ", but expected " & $nTypeInstAttr & ".", nExprColonExpr[1])

        var isLower, isHigher: bool = false
        if nAttrTypeSym.kind == nnkBracketExpr and nAttrTypeSym[0].getTypeInst() == getTypeInst(range):
          let nMinVal: NimNode = nAttrTypeSym[1][1]
          let nMaxVal: NimNode = nAttrTypeSym[1][2]
          case nTypeInstAttr.typeKind:
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
            error("Range type " & $nTypeInstAttr & " is not implemented!", nAttrTypeSym[1])
          if isLower:
            error("Default value is lower than specified in range.", nExprColonExpr[1])
          elif isHigher:
            error("Default value is higher than specified in range.", nExprColonExpr[1])
      elif nExprColonExpr[0] == sym(Valid):
        if nTypeInstAttr != getTypeInst(bool):
          error("Valid is not allowed at attribute of type " &  $nTypeInstAttr & ".", nExprColonExpr[1])
        if nTypeInstPragma == getTypeInst(Bools):
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