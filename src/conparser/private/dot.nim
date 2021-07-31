import macros

# https://github.com/moigagoo/norm/blob/develop/src/norm/private/dot.nim
macro dot*(obj: object, fld: string): untyped =
  ## Turn ``obj.dot("fld")`` into ``obj.fld``.
  newDotExpr(obj, newIdentNode(fld.strVal))
