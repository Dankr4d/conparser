type
  Bools* = object
    ## Specifies valid bools for parsing (use Valid pragma).
    `true`*, `false`*: seq[string]
    normalize*: bool

template Prefix*(val: string) {.pragma.} ## The prefix for each setting (attribute) to be added/parsed.
template Setting*(val: string) {.pragma.} ## The setting name which is used for parsing and writing (Prefix pragma is prepended).
template Default*(val: string | SomeInteger | SomeFloat | enum | bool | object) {.pragma.} ## The default value when parsing fails (ValueError).
template Format*(val: string) {.pragma.} ## The format of the object that should be parsed written with attribute name in square brackets (e.g. "[width]x[height]@[freequence]Hz)
template Valid*(val: Bools) {.pragma.} ## Specify which values are valid. Currently only implemented for bools.
template RoundW*(places: int) {.pragma.} ## Round SomeFloat when writing/serializing.
template CeilW*() {.pragma.} ## Ceil SomeFloat when writing/serializing.
template FloorW*() {.pragma.} ## Floor SomeFloat when writing/serializing.