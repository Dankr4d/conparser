type
  Bools* = object
    `true`*, `false`*: seq[string]
    normalize*: bool

template Prefix*(val: string) {.pragma.}
template Setting*(val: string) {.pragma.}
template Default*(val: string | SomeInteger | SomeFloat | enum | bool) {.pragma.}
template Format*(val: string) {.pragma.}
template Valid*(val: Bools) {.pragma.}
template RoundW*(places: int) {.pragma.}
template CeilW*() {.pragma.}
template FloorW*() {.pragma.}